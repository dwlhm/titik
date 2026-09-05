import Foundation
import TitikCore
import TitikPluginKit

public final class PluginWorkerSupervisor: @unchecked Sendable {
    public static let shared = PluginWorkerSupervisor()

    private let lock = NSLock()
    private var workers: [String: PluginWorkerInstance] = [:]
    private var startingTasks: [String: Task<PluginWorkerInstance, Error>] = [:]
    private var registeredPlugins: [String: (bundlePath: String?, manifestData: Data?)] = [:]

    private var continuations: [UUID: AsyncStream<IPCResponse>.Continuation] = [:]
    private var queryToPlugin: [UUID: String] = [:]
    private var loadContinuations: [String: CheckedContinuation<Bool, Error>] = [:]

    private var customBinaryURL: URL?
    private var isShuttingDown = false
    private var mockWriter: IPCMessageWriter?

    public init(customBinaryURL: URL? = nil) {
        self.customBinaryURL = customBinaryURL
    }

    private func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    public static func defaultWorkerEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let developerDir: String = {
            if let envDevDir = env["DEVELOPER_DIR"], !envDevDir.isEmpty, FileManager.default.fileExists(atPath: envDevDir) {
                return envDevDir
            }
            if FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools") {
                return "/Library/Developer/CommandLineTools"
            }
            if FileManager.default.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer") {
                return "/Applications/Xcode.app/Contents/Developer"
            }
            return "/Library/Developer/CommandLineTools"
        }()

        if env["DYLD_LIBRARY_PATH"] == nil {
            let libPath = "\(developerDir)/Library/Developer/usr/lib"
            if FileManager.default.fileExists(atPath: libPath) {
                env["DYLD_LIBRARY_PATH"] = libPath
            } else if FileManager.default.fileExists(atPath: "\(developerDir)/usr/lib") {
                env["DYLD_LIBRARY_PATH"] = "\(developerDir)/usr/lib"
            }
        }
        if env["DYLD_FRAMEWORK_PATH"] == nil {
            let frameworkPath = "\(developerDir)/Library/Developer/Frameworks"
            if FileManager.default.fileExists(atPath: frameworkPath) {
                env["DYLD_FRAMEWORK_PATH"] = frameworkPath
            } else if FileManager.default.fileExists(atPath: "\(developerDir)/Library/Frameworks") {
                env["DYLD_FRAMEWORK_PATH"] = "\(developerDir)/Library/Frameworks"
            }
        }
        return env
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
            workers.values.contains { $0.isRunning } || mockWriter != nil
        }
    }

    public func isWorkerRunning(for pluginId: String) -> Bool {
        withLock {
            workers[pluginId]?.isRunning == true || mockWriter != nil
        }
    }

    public func worker(for pluginId: String) -> PluginWorkerInstance? {
        withLock { workers[pluginId] }
    }

    public var activeWorkers: [String: PluginWorkerInstance] {
        withLock { workers }
    }

    // MARK: - Per-Plugin Worker Lifecycle Management

    public func start() async throws {
        let pluginsToStart = withLock {
            Array(registeredPlugins.keys)
        }
        for pluginId in pluginsToStart {
            _ = try await getOrCreateWorker(for: pluginId)
        }
    }

    @discardableResult
    public func getOrCreateWorker(
        for pluginId: String,
        bundlePath: String? = nil,
        manifestData: Data? = nil
    ) async throws -> PluginWorkerInstance {
        // Record registration if provided
        withLock {
            if let bp = bundlePath, let md = manifestData {
                registeredPlugins[pluginId] = (bundlePath: bp, manifestData: md)
            } else if registeredPlugins[pluginId] == nil {
                registeredPlugins[pluginId] = (bundlePath: nil, manifestData: nil)
            }
        }

        // Fast path: Check existing running worker
        let (existingWorker, inFlightTask, shuttingDown) = withLock { () -> (PluginWorkerInstance?, Task<PluginWorkerInstance, Error>?, Bool) in
            if isShuttingDown {
                return (nil, nil, true)
            }
            if let worker = workers[pluginId], worker.isRunning {
                return (worker, nil, false)
            }
            return (nil, startingTasks[pluginId], false)
        }

        if shuttingDown {
            throw PluginError.runtimeCrash("Supervisor is shutting down")
        }

        if let worker = existingWorker {
            if let bp = bundlePath, let md = manifestData {
                try await loadBundle(bundlePath: bp, manifestData: md, pluginId: pluginId, into: worker)
            }
            return worker
        }

        if let task = inFlightTask {
            return try await task.value
        }

        // Spawn on-demand using deduplicated Task
        let task = Task<PluginWorkerInstance, Error> { [weak self] in
            guard let self = self else {
                throw PluginError.runtimeCrash("Supervisor deallocated")
            }

            defer {
                self.withLock {
                    _ = self.startingTasks.removeValue(forKey: pluginId)
                }
            }

            guard let workerURL = Self.findWorkerBinary(customURL: self.customBinaryURL) else {
                Logger.shared.error("titik-worker executable not found", subsystem: "Titik.WorkerSupervisor")
                throw PluginError.runtimeCrash("titik-worker executable not found")
            }

            let instance = try await PluginWorkerInstance.spawn(
                pluginId: pluginId,
                executableURL: workerURL,
                environment: Self.defaultWorkerEnvironment()
            )

            instance.onMessage = { [weak self] workerInstance, response in
                self?.handleIncomingResponse(response, from: workerInstance.pluginId)
            }

            instance.onTermination = { [weak self] workerInstance, exitCode in
                self?.handleWorkerTermination(pluginId: workerInstance.pluginId, exitCode: exitCode)
            }

            self.withLock {
                self.workers[pluginId] = instance
            }

            // Sync registered bundle if exists
            let reg = self.withLock { self.registeredPlugins[pluginId] }
            let bpToLoad = bundlePath ?? reg?.bundlePath
            let mdToLoad = manifestData ?? reg?.manifestData

            if let bp = bpToLoad, let md = mdToLoad {
                try await self.loadBundle(bundlePath: bp, manifestData: md, pluginId: pluginId, into: instance)
            }

            Logger.shared.info(
                "Worker daemon spawned & handshaked for '\(pluginId)' (PID: \(instance.pid))",
                subsystem: "Titik.WorkerSupervisor"
            )

            return instance
        }

        withLock {
            startingTasks[pluginId] = task
        }

        return try await task.value
    }

    private func loadBundle(
        bundlePath: String,
        manifestData: Data,
        pluginId: String,
        into worker: PluginWorkerInstance
    ) async throws {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            withLock {
                self.loadContinuations[pluginId] = continuation
            }

            do {
                try worker.writer.write(IPCRequest.load(bundlePath: bundlePath, manifestData: manifestData))
            } catch {
                withLock {
                    _ = self.loadContinuations.removeValue(forKey: pluginId)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleIncomingResponse(_ response: IPCResponse, from pluginId: String) {
        switch response {
        case .handshakeAck:
            // Handshake is handled directly inside PluginWorkerInstance
            break

        case .loadResult(let loadedPluginId, let success, let error):
            let continuation = withLock {
                loadContinuations.removeValue(forKey: loadedPluginId)
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
                    queryToPlugin.removeValue(forKey: requestId)
                } else if case .error = event {
                    continuations.removeValue(forKey: requestId)
                    queryToPlugin.removeValue(forKey: requestId)
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
                queryToPlugin.removeValue(forKey: requestId)
                return continuations.removeValue(forKey: requestId)
            }

            continuation?.yield(response)
            continuation?.finish()

        case .queryError(let requestId, _):
            let continuation = withLock {
                queryToPlugin.removeValue(forKey: requestId)
                return continuations.removeValue(forKey: requestId)
            }

            continuation?.yield(response)
            continuation?.finish()

        case .heartbeat:
            break
        }
    }

    private func handleWorkerTermination(pluginId: String, exitCode: Int32) {
        let (affectedContinuations, pendingLoad, shouldRecover) = withLock { () -> ([AsyncStream<IPCResponse>.Continuation], CheckedContinuation<Bool, Error>?, Bool) in
            let shuttingDown = isShuttingDown
            _ = workers.removeValue(forKey: pluginId)

            var affected: [AsyncStream<IPCResponse>.Continuation] = []
            let reqIdsForPlugin = queryToPlugin.compactMap { (reqId, pId) -> UUID? in
                pId == pluginId ? reqId : nil
            }
            for reqId in reqIdsForPlugin {
                if let cont = continuations.removeValue(forKey: reqId) {
                    affected.append(cont)
                }
                queryToPlugin.removeValue(forKey: reqId)
            }

            let pendingLoad = loadContinuations.removeValue(forKey: pluginId)
            let shouldRecover = !shuttingDown && (registeredPlugins[pluginId] != nil)

            return (affected, pendingLoad, shouldRecover)
        }

        // Fail inflight queries dedicated to this worker
        for c in affectedContinuations {
            c.yield(.queryError(requestId: UUID(), error: "Worker process terminated (exit code: \(exitCode))"))
            c.finish()
        }

        pendingLoad?.resume(throwing: PluginError.runtimeCrash("Worker for '\(pluginId)' terminated before plugin load"))

        if shouldRecover {
            Logger.shared.error(
                "Worker process for '\(pluginId)' crashed with exit code \(exitCode). Triggering auto-recovery...",
                subsystem: "Titik.WorkerSupervisor"
            )
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms backoff
                let reg = self.withLock { self.registeredPlugins[pluginId] }
                _ = try? await self.getOrCreateWorker(for: pluginId, bundlePath: reg?.bundlePath, manifestData: reg?.manifestData)
            }
        }
    }

    // MARK: - Query & Streaming Dispatch

    public func query(pluginId: String, query: String) -> (requestId: UUID, stream: AsyncStream<IPCResponse>) {
        let requestId = UUID()

        let stream = AsyncStream<IPCResponse> { continuation in
            let (activeWorker, fallbackMock) = withLock { () -> (PluginWorkerInstance?, IPCMessageWriter?) in
                self.continuations[requestId] = continuation
                self.queryToPlugin[requestId] = pluginId
                return (self.workers[pluginId], self.mockWriter)
            }

            continuation.onTermination = { [weak self] _ in
                self?.cancelQuery(requestId: requestId)
            }

            if let worker = activeWorker, worker.isRunning {
                do {
                    try worker.writer.write(IPCRequest.query(requestId: requestId, pluginId: pluginId, query: query))
                } catch {
                    continuation.yield(.queryError(requestId: requestId, error: error.localizedDescription))
                    continuation.finish()
                    self.withLock {
                        _ = self.continuations.removeValue(forKey: requestId)
                        _ = self.queryToPlugin.removeValue(forKey: requestId)
                    }
                }
            } else if let mock = fallbackMock {
                do {
                    try mock.write(IPCRequest.query(requestId: requestId, pluginId: pluginId, query: query))
                } catch {
                    continuation.yield(.queryError(requestId: requestId, error: error.localizedDescription))
                    continuation.finish()
                    self.withLock {
                        _ = self.continuations.removeValue(forKey: requestId)
                        _ = self.queryToPlugin.removeValue(forKey: requestId)
                    }
                }
            } else {
                // Ensure dedicated worker is running or spawn on-demand
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        let reg = self.withLock { self.registeredPlugins[pluginId] }
                        let worker = try await self.getOrCreateWorker(
                            for: pluginId,
                            bundlePath: reg?.bundlePath,
                            manifestData: reg?.manifestData
                        )
                        try worker.writer.write(IPCRequest.query(requestId: requestId, pluginId: pluginId, query: query))
                    } catch {
                        continuation.yield(.queryError(requestId: requestId, error: error.localizedDescription))
                        continuation.finish()
                        self.withLock {
                            _ = self.continuations.removeValue(forKey: requestId)
                            _ = self.queryToPlugin.removeValue(forKey: requestId)
                        }
                    }
                }
            }
        }

        return (requestId, stream)
    }

    public func cancelQuery(requestId: UUID) {
        let (continuation, writer) = withLock { () -> (AsyncStream<IPCResponse>.Continuation?, IPCMessageWriter?) in
            let cont = continuations.removeValue(forKey: requestId)
            let pluginId = queryToPlugin.removeValue(forKey: requestId)
            let writer = pluginId.flatMap { workers[$0]?.writer } ?? mockWriter
            return (cont, writer)
        }

        continuation?.finish()
        if let writer = writer {
            try? writer.write(IPCRequest.cancelQuery(requestId: requestId))
        }
    }

    public func cancelAllQueries() {
        let (conts, pairs) = withLock { () -> ([AsyncStream<IPCResponse>.Continuation], [(UUID, IPCMessageWriter)]) in
            let conts = Array(continuations.values)
            var pairs: [(UUID, IPCMessageWriter)] = []
            for (reqId, pid) in queryToPlugin {
                if let writer = workers[pid]?.writer ?? mockWriter {
                    pairs.append((reqId, writer))
                }
            }
            continuations.removeAll()
            queryToPlugin.removeAll()
            return (conts, pairs)
        }

        for c in conts {
            c.finish()
        }

        for (reqId, writer) in pairs {
            try? writer.write(IPCRequest.cancelQuery(requestId: reqId))
        }
    }

    // MARK: - Plugin Registration & Sync

    public func loadPlugin(bundlePath: String, manifestData: Data, pluginId: String) async throws -> Bool {
        _ = try await getOrCreateWorker(for: pluginId, bundlePath: bundlePath, manifestData: manifestData)
        return true
    }

    public func unloadPlugin(pluginId: String) {
        let worker = withLock { () -> PluginWorkerInstance? in
            registeredPlugins.removeValue(forKey: pluginId)
            return workers.removeValue(forKey: pluginId)
        }

        if let w = worker {
            try? w.writer.write(IPCRequest.unload(pluginId: pluginId))
            w.shutdown()
        }
    }

    // MARK: - Testing Utilities

    public func terminateWorkerForTesting(pluginId: String? = nil) {
        let workersToTerminate = withLock { () -> [PluginWorkerInstance] in
            if let pid = pluginId, let w = workers[pid] {
                return [w]
            }
            return Array(workers.values)
        }
        for w in workersToTerminate {
            w.terminate()
        }
    }

    public func injectResponseForTesting(_ response: IPCResponse, for pluginId: String? = nil) {
        handleIncomingResponse(response, from: pluginId ?? "default")
    }

    public func handleProcessTerminationForTesting(exitCode: Int32, pluginId: String? = nil) {
        if let pid = pluginId {
            handleWorkerTermination(pluginId: pid, exitCode: exitCode)
        } else {
            let pluginsToTerminate = withLock { () -> Set<String> in
                var p = Set(workers.keys)
                for pid in queryToPlugin.values { p.insert(pid) }
                if p.isEmpty { p.insert("default") }
                return p
            }
            for pid in pluginsToTerminate {
                handleWorkerTermination(pluginId: pid, exitCode: exitCode)
            }
        }
    }

    public func setWriterForTesting(_ writer: IPCMessageWriter, for pluginId: String = "default") {
        withLock {
            self.mockWriter = writer
        }
    }

    // MARK: - Shutdown

    public func shutdown() {
        let activeWorkers = withLock { () -> [PluginWorkerInstance] in
            isShuttingDown = true
            let all = Array(workers.values)
            workers.removeAll()
            startingTasks.removeAll()
            registeredPlugins.removeAll()
            continuations.removeAll()
            queryToPlugin.removeAll()
            loadContinuations.removeAll()
            mockWriter = nil
            return all
        }

        for worker in activeWorkers {
            worker.shutdown()
        }

        Logger.shared.info(
            "Worker supervisor shut down cleanly (\(activeWorkers.count) workers)",
            subsystem: "Titik.WorkerSupervisor"
        )
    }

    deinit {
        shutdown()
    }
}
