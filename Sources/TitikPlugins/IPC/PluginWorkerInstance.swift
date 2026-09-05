import Foundation
import TitikCore
import TitikPluginKit

/// Encapsulates a dedicated worker process for a single plugin.
public final class PluginWorkerInstance: @unchecked Sendable {
    public let pluginId: String
    public let process: Process
    public let pid: Int32
    public let writer: IPCMessageWriter
    public let stdinPipe: Pipe
    public let stdoutPipe: Pipe

    private let lock = NSLock()
    private var handshakeContinuation: CheckedContinuation<Bool, Error>?
    private var hasTerminated = false
    private var readerThread: Thread?

    public var onMessage: (@Sendable (PluginWorkerInstance, IPCResponse) -> Void)?
    public var onTermination: (@Sendable (PluginWorkerInstance, Int32) -> Void)?

    public var isRunning: Bool {
        process.isRunning
    }

    public init(
        pluginId: String,
        process: Process,
        pid: Int32,
        stdinPipe: Pipe,
        stdoutPipe: Pipe,
        writer: IPCMessageWriter
    ) {
        self.pluginId = pluginId
        self.process = process
        self.pid = pid
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.writer = writer
    }

    private func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    /// Spawns a dedicated worker process for the given pluginId, establishes IPC pipes,
    /// and performs the initial handshake.
    public static func spawn(
        pluginId: String,
        executableURL: URL,
        environment: [String: String]? = nil,
        arguments: [String] = []
    ) async throws -> PluginWorkerInstance {
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = ["--plugin-id", pluginId] + arguments
        if let env = environment {
            proc.environment = env
        }

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.standardError

        let msgWriter = IPCMessageWriter(handle: inPipe.fileHandleForWriting)

        do {
            try proc.run()
        } catch {
            Logger.shared.error(
                "Failed to spawn worker process for '\(pluginId)': \(error.localizedDescription)",
                subsystem: "Titik.WorkerInstance"
            )
            throw PluginError.runtimeCrash("Failed to spawn titik-worker for \(pluginId): \(error.localizedDescription)")
        }

        let instance = PluginWorkerInstance(
            pluginId: pluginId,
            process: proc,
            pid: proc.processIdentifier,
            stdinPipe: inPipe,
            stdoutPipe: outPipe,
            writer: msgWriter
        )

        proc.terminationHandler = { [weak instance] p in
            instance?.handleTermination(exitCode: p.terminationStatus)
        }

        instance.startReader()
        try await instance.performHandshake()

        return instance
    }

    private func startReader() {
        readerThread = IPCTransport.startMessageReader(
            from: stdoutPipe.fileHandleForReading,
            as: IPCResponse.self,
            onMessage: { [weak self] response in
                self?.handleIncomingResponse(response)
            },
            onEOF: { [weak self] in
                self?.handleEOF()
            }
        )
    }

    public func performHandshake(timeoutNanoseconds: UInt64 = 3_000_000_000) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    let alreadyTerminated = self.withLock { () -> Bool in
                        if self.hasTerminated {
                            return true
                        }
                        self.handshakeContinuation = continuation
                        return false
                    }

                    if alreadyTerminated {
                        continuation.resume(throwing: PluginError.runtimeCrash("Worker for '\(self.pluginId)' terminated before handshake"))
                        return
                    }

                    do {
                        try self.writer.write(IPCRequest.handshake(sdkVersion: 2))
                    } catch {
                        self.withLock {
                            self.handshakeContinuation = nil
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PluginError.timeout("Worker for '\(self.pluginId)' handshake timed out after 3.0s")
            }

            defer {
                self.withLock {
                    let pending = self.handshakeContinuation
                    self.handshakeContinuation = nil
                    pending?.resume(throwing: PluginError.timeout("Worker for '\(self.pluginId)' handshake timed out after 3.0s"))
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private func handleIncomingResponse(_ response: IPCResponse) {
        if case .handshakeAck(let sdkVersion, let success) = response {
            let continuation = withLock { () -> CheckedContinuation<Bool, Error>? in
                let c = handshakeContinuation
                handshakeContinuation = nil
                return c
            }

            if success && sdkVersion == 2 {
                continuation?.resume(returning: true)
            } else {
                continuation?.resume(throwing: PluginError.incompatibleSDK(current: 2, required: sdkVersion))
            }
            return
        }

        onMessage?(self, response)
    }

    private func handleEOF() {
        if isRunning {
            handleTermination(exitCode: -1)
        }
    }

    public func handleTermination(exitCode: Int32) {
        let shouldNotify = withLock { () -> Bool in
            if hasTerminated { return false }
            hasTerminated = true

            let pending = handshakeContinuation
            handshakeContinuation = nil
            pending?.resume(throwing: PluginError.runtimeCrash("Worker for '\(pluginId)' terminated before handshake (exit code: \(exitCode))"))
            return true
        }

        if shouldNotify {
            onTermination?(self, exitCode)
        }
    }

    public func terminate() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    public func shutdown() {
        withLock {
            hasTerminated = true
            let pending = handshakeContinuation
            handshakeContinuation = nil
            pending?.resume(throwing: PluginError.runtimeCrash("Worker shutting down"))
        }

        try? writer.write(IPCRequest.shutdown)
        writer.close()

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    public func injectResponseForTesting(_ response: IPCResponse) {
        handleIncomingResponse(response)
    }

    public func handleTerminationForTesting(exitCode: Int32) {
        handleTermination(exitCode: exitCode)
    }

    deinit {
        shutdown()
    }
}
