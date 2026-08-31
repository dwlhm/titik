import Foundation
import Dispatch
import TitikCore
import TitikPluginKit
import TitikPlugins

signal(SIGPIPE, SIG_IGN)

final class WorkerDispatcher: @unchecked Sendable {
    private let host = PluginHost()
    private let writer = IPCMessageWriter(handle: FileHandle.standardOutput)
    private var activeQueryTasks: [UUID: Task<Void, Never>] = [:]
    private let lock = NSLock()

    private func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    func run() {
        _ = IPCTransport.startMessageReader(
            from: FileHandle.standardInput,
            as: IPCRequest.self,
            onMessage: { [weak self] request in
                Task {
                    await self?.handleRequest(request)
                }
            },
            onEOF: {
                exit(0)
            }
        )

        dispatchMain()
    }

    private func handleRequest(_ request: IPCRequest) async {
        switch request {
        case .handshake(let sdkVersion):
            let isSupported = (sdkVersion == 2)
            try? writer.write(IPCResponse.handshakeAck(workerSdkVersion: 2, success: isSupported))

        case .load(let bundlePath, let manifestData):
            do {
                let manifest = try PluginManifest.validate(jsonData: manifestData)
                let bundleURL = URL(fileURLWithPath: bundlePath)
                _ = try host.loadNativePluginBundle(at: bundleURL)
                try? writer.write(IPCResponse.loadResult(pluginId: manifest.id, success: true, error: nil))
            } catch {
                var pluginId = bundlePath
                if let manifest = try? PluginManifest.validate(jsonData: manifestData) {
                    pluginId = manifest.id
                }
                try? writer.write(IPCResponse.loadResult(pluginId: pluginId, success: false, error: error.localizedDescription))
            }

        case .unload(let pluginId):
            host.unloadPlugin(id: pluginId)

        case .query(let requestId, let pluginId, let query):
            let task = Task { [weak self] in
                guard let self = self else { return }

                guard let plugin = self.host.getNativePlugin(id: pluginId) else {
                    try? self.writer.write(IPCResponse.queryError(requestId: requestId, error: "Plugin '\(pluginId)' not found in worker"))
                    return
                }

                if let streamingPlugin = plugin as? (any TitikStreamingPlugin) {
                    do {
                        let canvas = try await streamingPlugin.onQuery(query)
                        switch canvas {
                        case .streaming(let emitter):
                            let events = await emitter.stream()
                            var emittedFinished = false
                            for await event in events {
                                if Task.isCancelled { break }
                                if case .finished = event {
                                    emittedFinished = true
                                }
                                try? self.writer.write(IPCResponse.streamEvent(requestId: requestId, event: event))
                            }
                            if !emittedFinished && !Task.isCancelled {
                                try? self.writer.write(IPCResponse.streamEvent(requestId: requestId, event: .finished))
                            }

                        case .list(let items):
                            try? self.writer.write(IPCResponse.listResult(requestId: requestId, items: items))

                        case .empty:
                            try? self.writer.write(IPCResponse.listResult(requestId: requestId, items: []))

                        case .customView:
                            try? self.writer.write(IPCResponse.listResult(requestId: requestId, items: []))
                        }
                    } catch {
                        try? self.writer.write(IPCResponse.queryError(requestId: requestId, error: error.localizedDescription))
                    }
                } else {
                    try? self.writer.write(IPCResponse.queryError(requestId: requestId, error: "Plugin '\(pluginId)' does not conform to TitikStreamingPlugin"))
                }

                self.withLock {
                    _ = self.activeQueryTasks.removeValue(forKey: requestId)
                }
            }

            withLock {
                activeQueryTasks[requestId] = task
            }

        case .cancelQuery(let requestId):
            let task = withLock {
                activeQueryTasks.removeValue(forKey: requestId)
            }

            task?.cancel()

        case .shutdown:
            host.shutdownAll()
            writer.close()
            exit(0)
        }
    }
}

let dispatcher = WorkerDispatcher()
dispatcher.run()
