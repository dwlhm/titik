import Foundation
import TitikCore
import TitikPluginKit

public final class PluginWorkerSupervisor: @unchecked Sendable {
    public static let shared = PluginWorkerSupervisor()

    private let lock = NSLock()
    private var process: Process?
    private var writer: IPCMessageWriter?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?

    private var continuations: [UUID: AsyncStream<IPCResponse>.Continuation] = [:]
    private var handshakeContinuation: CheckedContinuation<Bool, Error>?
    private var loadContinuations: [String: CheckedContinuation<Bool, Error>] = [:]

    private var registeredPlugins: [String: (bundlePath: String, manifestData: Data)] = [:]
    private var customBinaryURL: URL?
    private var isStarting = false
    private var isShuttingDown = false

    public init(customBinaryURL: URL? = nil) {
        self.customBinaryURL = customBinaryURL
    }

    private func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    public static func findWorkerBinary(customURL: URL? = nil) -> URL? {
        if let custom = customURL, FileManager.default.isExecutableFile(atPath: custom.path) {
            return custom
        }

        // 1. Auxiliary executable in App bundle
        if let url = Bundle.main.url(forAuxiliaryExecutable: "titik-worker"), FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        // 2. Relative to main executable
        if let execURL = Bundle.main.executableURL {
            let candidate = execURL.deletingLastPathComponent().appendingPathComponent("titik-worker")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 3. Project root relative to source file
        let sourceURL = URL(fileURLWithPath: #filePath)
        let root = sourceURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        // 4. Current working directory / bin / build dirs
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/titik-worker"),
            root.appendingPathComponent(".build/arm64-apple-macosx/release/titik-worker"),
            root.appendingPathComponent("bin/titik-worker"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/debug/titik-worker"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/release/titik-worker"),
            cwd.appendingPathComponent("bin/titik-worker"),
            cwd.appendingPathComponent(".build/release/titik-worker"),
            cwd.appendingPathComponent(".build/debug/titik-worker"),
            URL(fileURLWithPath: "/usr/local/bin/titik-worker")
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    public var isWorkerRunning: Bool {
        withLock {
            process?.isRunning == true && writer != nil
        }
    }

    // MARK: - Lifecycle Management

    public func start() async throws {
        let shouldStart = withLock { () -> Bool in
            if process?.isRunning == true || isStarting {
                return false
            }
            isStarting = true
            isShuttingDown = false
            return true
        }

        guard shouldStart else { return }

        defer {
            withLock { isStarting = false }
        }

        guard let workerURL = Self.findWorkerBinary(customURL: customBinaryURL) else {
            Logger.shared.error("titik-worker executable not found", subsystem: "Titik.WorkerSupervisor")
            throw PluginError.runtimeCrash("titik-worker executable not found")
        }

        let proc = Process()
        proc.executableURL = workerURL
        var env = ProcessInfo.processInfo.environment
        if env["DYLD_LIBRARY_PATH"] == nil {
            env["DYLD_LIBRARY_PATH"] = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
        }
        if env["DYLD_FRAMEWORK_PATH"] == nil {
            env["DYLD_FRAMEWORK_PATH"] = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
        }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.standardError

        let msgWriter = IPCMessageWriter(handle: inPipe.fileHandleForWriting)

        withLock {
            self.process = proc
            self.writer = msgWriter
            self.stdinPipe = inPipe
            self.stdoutPipe = outPipe
        }

        proc.terminationHandler = { [weak self] p in
            self?.handleProcessTermination(exitCode: p.terminationStatus)
        }

        do {
            try proc.run()
        } catch {
            Logger.shared.error("Failed to spawn titik-worker: \(error.localizedDescription)", subsystem: "Titik.WorkerSupervisor")
            throw PluginError.runtimeCrash("Failed to spawn titik-worker: \(error.localizedDescription)")
        }

        // Start message reading directly on dedicated reader thread
        _ = IPCTransport.startMessageReader(
            from: outPipe.fileHandleForReading,
            as: IPCResponse.self,
            onMessage: { [weak self] response in
                self?.handleIncomingResponse(response)
            },
            onEOF: { [weak self] in
                self?.handleEOF()
            }
        )

        // Perform handshake
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            withLock {
                self.handshakeContinuation = continuation
            }

            do {
                try msgWriter.write(IPCRequest.handshake(sdkVersion: 2))
            } catch {
                withLock {
                    self.handshakeContinuation = nil
                }
                continuation.resume(throwing: error)
            }
        }

        // Re-load registered plugins after handshake
        let pluginsToSync = withLock {
            Array(registeredPlugins.values)
        }

        for plugin in pluginsToSync {
            try? msgWriter.write(IPCRequest.load(bundlePath: plugin.bundlePath, manifestData: plugin.manifestData))
        }

        Logger.shared.info("Worker daemon started & handshaked successfully (PID: \(proc.processIdentifier))", subsystem: "Titik.WorkerSupervisor")
    }

    private func handleIncomingResponse(_ response: IPCResponse) {
        switch response {
        case .handshakeAck(let sdkVersion, let success):
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

        case .loadResult(let pluginId, let success, let error):
            let continuation = withLock {
                loadContinuations.removeValue(forKey: pluginId)
            }

            if success {
                continuation?.resume(returning: true)
            } else {
                continuation?.resume(throwing: PluginError.runtimeCrash(error ?? "Plugin load failed"))
            }

        case .streamEvent(let requestId, let event):
            let continuation = withLock { () -> AsyncStream<IPCResponse>.Continuation? in
                let c = continuations[requestId]
                if case .finished = event {
                    continuations.removeValue(forKey: requestId)
                } else if case .error = event {
                    continuations.removeValue(forKey: requestId)
                }
                return c
            }

            continuation?.yield(response)
            if case .finished = event {
                continuation?.finish()
            } else if case .error = event {
                continuation?.finish()
            }

        case .listResult(let requestId, _):
            let continuation = withLock {
                continuations.removeValue(forKey: requestId)
            }

            continuation?.yield(response)
            continuation?.finish()

        case .queryError(let requestId, _):
            let continuation = withLock {
                continuations.removeValue(forKey: requestId)
            }

            continuation?.yield(response)
            continuation?.finish()

        case .heartbeat:
            break
        }
    }

    private func handleProcessTermination(exitCode: Int32) {
        let (shuttingDown, activeContinuations, pendingHandshake, pendingLoads) = withLock { () -> (Bool, [AsyncStream<IPCResponse>.Continuation], CheckedContinuation<Bool, Error>?, [CheckedContinuation<Bool, Error>]) in
            let shuttingDown = isShuttingDown
            let activeContinuations = Array(continuations.values)
            continuations.removeAll()

            let pendingHandshake = handshakeContinuation
            handshakeContinuation = nil

            let pendingLoads = Array(loadContinuations.values)
            loadContinuations.removeAll()

            process = nil
            writer = nil
            stdinPipe = nil
            stdoutPipe = nil

            return (shuttingDown, activeContinuations, pendingHandshake, pendingLoads)
        }

        // Fail inflight continuations
        for c in activeContinuations {
            c.yield(.queryError(requestId: UUID(), error: "Worker process terminated (exit code: \(exitCode))"))
            c.finish()
        }

        pendingHandshake?.resume(throwing: PluginError.runtimeCrash("Worker terminated before handshake"))
        for l in pendingLoads {
            l.resume(throwing: PluginError.runtimeCrash("Worker terminated before plugin load"))
        }

        if !shuttingDown {
            Logger.shared.error("Worker process crashed with exit code \(exitCode). Triggering auto-recovery...", subsystem: "Titik.WorkerSupervisor")
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms backoff
                try? await self.start()
            }
        }
    }

    private func handleEOF() {
        let isRunning = withLock {
            process?.isRunning == true
        }

        if isRunning {
            handleProcessTermination(exitCode: -1)
        }
    }

    // MARK: - Query & Streaming Dispatch

    public func query(pluginId: String, query: String) -> (requestId: UUID, stream: AsyncStream<IPCResponse>) {
        let requestId = UUID()

        let stream = AsyncStream<IPCResponse> { continuation in
            let w = withLock { () -> IPCMessageWriter? in
                self.continuations[requestId] = continuation
                return self.writer
            }

            continuation.onTermination = { [weak self] _ in
                self?.cancelQuery(requestId: requestId)
            }

            if let writer = w {
                do {
                    try writer.write(IPCRequest.query(requestId: requestId, pluginId: pluginId, query: query))
                } catch {
                    continuation.yield(.queryError(requestId: requestId, error: error.localizedDescription))
                    continuation.finish()
                    self.withLock {
                        _ = self.continuations.removeValue(forKey: requestId)
                    }
                }
            } else {
                // Ensure worker is running or try to start
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        try await self.start()
                        let activeWriter = self.withLock { self.writer }

                        if let writer = activeWriter {
                            try writer.write(IPCRequest.query(requestId: requestId, pluginId: pluginId, query: query))
                        } else {
                            continuation.yield(.queryError(requestId: requestId, error: "Worker process unavailable"))
                            continuation.finish()
                            self.withLock {
                                _ = self.continuations.removeValue(forKey: requestId)
                            }
                        }
                    } catch {
                        continuation.yield(.queryError(requestId: requestId, error: error.localizedDescription))
                        continuation.finish()
                        self.withLock {
                            _ = self.continuations.removeValue(forKey: requestId)
                        }
                    }
                }
            }
        }

        return (requestId, stream)
    }

    public func cancelQuery(requestId: UUID) {
        let (continuation, w) = withLock { () -> (AsyncStream<IPCResponse>.Continuation?, IPCMessageWriter?) in
            (continuations.removeValue(forKey: requestId), writer)
        }

        continuation?.finish()
        if let writer = w {
            try? writer.write(IPCRequest.cancelQuery(requestId: requestId))
        }
    }

    public func cancelAllQueries() {
        let (ids, activeContinuations, w) = withLock { () -> ([UUID], [AsyncStream<IPCResponse>.Continuation], IPCMessageWriter?) in
            let ids = Array(continuations.keys)
            let activeContinuations = Array(continuations.values)
            continuations.removeAll()
            return (ids, activeContinuations, writer)
        }

        for c in activeContinuations {
            c.finish()
        }

        if let writer = w {
            for id in ids {
                try? writer.write(IPCRequest.cancelQuery(requestId: id))
            }
        }
    }

    // MARK: - Plugin Registration & Sync

    public func loadPlugin(bundlePath: String, manifestData: Data, pluginId: String) async throws -> Bool {
        let (running, w) = withLock { () -> (Bool, IPCMessageWriter?) in
            registeredPlugins[pluginId] = (bundlePath: bundlePath, manifestData: manifestData)
            return (process?.isRunning == true, writer)
        }

        if !running || w == nil {
            try await start()
        }

        let activeWriter = try withLock { () -> IPCMessageWriter in
            guard let writer = writer else {
                throw PluginError.runtimeCrash("Worker is not running")
            }
            return writer
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            withLock {
                self.loadContinuations[pluginId] = continuation
            }

            do {
                try activeWriter.write(IPCRequest.load(bundlePath: bundlePath, manifestData: manifestData))
            } catch {
                withLock {
                    _ = self.loadContinuations.removeValue(forKey: pluginId)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    public func unloadPlugin(pluginId: String) {
        let w = withLock { () -> IPCMessageWriter? in
            registeredPlugins.removeValue(forKey: pluginId)
            return writer
        }

        if let writer = w {
            try? writer.write(IPCRequest.unload(pluginId: pluginId))
        }
    }

    public func terminateWorkerForTesting() {
        withLock {
            process?.terminate()
        }
    }

    public func injectResponseForTesting(_ response: IPCResponse) {
        handleIncomingResponse(response)
    }

    public func handleProcessTerminationForTesting(exitCode: Int32) {
        handleProcessTermination(exitCode: exitCode)
    }

    public func setWriterForTesting(_ writer: IPCMessageWriter) {
        withLock {
            self.writer = writer
        }
    }

    public func shutdown() {
        let (w, proc) = withLock { () -> (IPCMessageWriter?, Process?) in
            isShuttingDown = true
            let w = writer
            let proc = process
            continuations.removeAll()
            registeredPlugins.removeAll()
            process = nil
            writer = nil
            stdinPipe = nil
            stdoutPipe = nil
            return (w, proc)
        }

        if let writer = w {
            try? writer.write(IPCRequest.shutdown)
            writer.close()
        }

        if let p = proc, p.isRunning {
            p.terminate()
        }

        Logger.shared.info("Worker supervisor shut down cleanly", subsystem: "Titik.WorkerSupervisor")
    }

    deinit {
        shutdown()
    }
}
