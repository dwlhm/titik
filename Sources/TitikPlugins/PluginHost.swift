import Foundation
import TitikCore
import TitikPluginKit

public final class LoadedNativePluginInstance: @unchecked Sendable {
    public let manifest: PluginManifest
    public let bundle: Bundle?
    public let plugin: any TitikPlugin
    public let context: PluginContext
    public var activeTasks: [UUID: Task<Void, Never>] = [:]
    private let taskLock = NSLock()

    public init(manifest: PluginManifest, bundle: Bundle?, plugin: any TitikPlugin, context: PluginContext) {
        self.manifest = manifest
        self.bundle = bundle
        self.plugin = plugin
        self.context = context
    }

    public func addTask(_ task: Task<Void, Never>) -> UUID {
        taskLock.lock()
        defer { taskLock.unlock() }
        let id = UUID()
        activeTasks[id] = task
        return id
    }

    public func removeTask(id: UUID) {
        taskLock.lock()
        defer { taskLock.unlock() }
        activeTasks.removeValue(forKey: id)
    }

    public func cancelAllTasks() {
        taskLock.lock()
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        taskLock.unlock()

        for t in tasks {
            t.cancel()
        }

        if let streaming = plugin as? (any TitikStreamingPlugin) {
            Task {
                await streaming.cancelActiveStream()
            }
        }
    }
}

public final class PluginHost: @unchecked Sendable {
    public static let shared = PluginHost(supervisor: .shared)

    public let supervisor: PluginWorkerSupervisor?
    private let lock = NSLock()
    private var nativePlugins: [String: LoadedNativePluginInstance] = [:]

    public init(supervisor: PluginWorkerSupervisor? = nil) {
        self.supervisor = supervisor
    }

    public static var defaultPluginDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".config/titik/plugins")
        ]
    }

    // MARK: - Generic Loader

    public func loadPlugin(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension == "titikplugin" || url.pathExtension == "bundle" || FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) {
            do {
                _ = try loadNativePluginBundle(at: url)
                return true
            } catch {
                Logger.shared.error("Failed to load native plugin at \(path): \(error.localizedDescription)", subsystem: "Titik.PluginHost")
                return false
            }
        }
        Logger.shared.warn("Unrecognized plugin format at \(path)", subsystem: "Titik.PluginHost")
        return false
    }

    // MARK: - Native Dynamic Bundle Loading

    public func loadNativePluginBundle(at bundleURL: URL) throws -> any TitikPlugin {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: bundleURL.path) else {
            throw PluginError.invalidManifest("Bundle path does not exist: \(bundleURL.path)")
        }

        // 1. Locate and parse manifest.json
        var manifestURL = bundleURL.appendingPathComponent("manifest.json")
        if !fileManager.fileExists(atPath: manifestURL.path) {
            manifestURL = bundleURL.appendingPathComponent("Contents/Resources/manifest.json")
        }
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PluginError.invalidManifest("Missing manifest.json in bundle at \(bundleURL.path)")
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try PluginManifest.validate(jsonData: manifestData)

        // 2. Load bundle binary
        let bundle = Bundle(url: bundleURL) ?? Bundle(path: bundleURL.path)
        if let b = bundle, !b.isLoaded, b.executableURL != nil {
            guard b.load() else {
                throw PluginError.runtimeCrash("Failed to load bundle binary at \(bundleURL.path)")
            }
        }

        // 3. Resolve entrypoint / principal class
        var resolvedClass: AnyClass? = bundle?.classNamed(manifest.entrypoint)
        if resolvedClass == nil {
            resolvedClass = NSClassFromString(manifest.entrypoint)
        }
        if resolvedClass == nil, let bundleId = bundle?.bundleIdentifier {
            resolvedClass = NSClassFromString("\(bundleId).\(manifest.entrypoint)")
        }
        if resolvedClass == nil {
            let bundleName = bundleURL.deletingPathExtension().lastPathComponent
            resolvedClass = NSClassFromString("\(bundleName).\(manifest.entrypoint)")
        }

        guard let targetClass = resolvedClass else {
            throw PluginError.missingPrincipalClass(manifest.entrypoint)
        }

        guard let pluginType = targetClass as? any TitikPlugin.Type else {
            throw PluginError.nonConformingPrincipalClass(manifest.entrypoint)
        }

        // 4. Instantiate with scoped context
        let context = PluginContext(pluginId: manifest.id)
        let instance = pluginType.init(context: context)

        // 5. Register in host registry and sync with worker supervisor if configured
        registerNativePlugin(instance, manifest: manifest, bundle: bundle)

        if let supervisor = supervisor {
            Task {
                try? await supervisor.loadPlugin(bundlePath: bundleURL.path, manifestData: manifestData, pluginId: manifest.id)
            }
        }

        return instance
    }

    public func registerNativePlugin(_ plugin: any TitikPlugin, manifest: PluginManifest, bundle: Bundle? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = nativePlugins[manifest.id] {
            existing.cancelAllTasks()
            existing.plugin.onShutdown()
        }

        let context = PluginContext(pluginId: manifest.id)
        let loaded = LoadedNativePluginInstance(manifest: manifest, bundle: bundle, plugin: plugin, context: context)
        nativePlugins[manifest.id] = loaded
        Logger.shared.info("Registered native plugin: \(manifest.name) v\(manifest.version) (\(manifest.id))", subsystem: "Titik.PluginHost")
    }

    public func getNativePlugin(id: String) -> (any TitikPlugin)? {
        lock.lock()
        defer { lock.unlock() }
        return nativePlugins[id]?.plugin
    }

    public func getLoadedNativePlugin(id: String) -> LoadedNativePluginInstance? {
        lock.lock()
        defer { lock.unlock() }
        return nativePlugins[id]
    }

    public func allNativePlugins() -> [LoadedNativePluginInstance] {
        lock.lock()
        defer { lock.unlock() }
        return Array(nativePlugins.values)
    }

    // MARK: - Query & Dispatch Routing

    public func findActivePlugin(command: String) -> PluginManifest? {
        lock.lock()
        let natives = Array(nativePlugins.values)
        lock.unlock()

        let lower = command.lowercased()

        // Check native plugins
        for native in natives {
            if native.manifest.name.lowercased() == lower {
                return native.manifest
            }
            for bang in native.manifest.normalizedBangs {
                let clean = bang.lowercased()
                if clean == lower {
                    return native.manifest
                }
            }
        }
        return nil
    }

    public func findActivePlugin(forQuery query: String) -> (manifest: PluginManifest, subquery: String)? {
        lock.lock()
        let natives = Array(nativePlugins.values)
        lock.unlock()

        guard query.hasPrefix("!") else { return nil }

        let lower = query.lowercased()

        // Check native plugins
        for native in natives {
            for bang in native.manifest.normalizedBangs {
                let exactBang = "!" + bang.lowercased()
                let bangPrefix = exactBang + " "
                if lower == exactBang {
                    return (native.manifest, "")
                } else if lower.hasPrefix(bangPrefix) {
                    let subquery = String(query.dropFirst(bangPrefix.count)).trimmingCharacters(in: .whitespaces)
                    return (native.manifest, subquery)
                }
            }
        }
        return nil
    }

    /// Dispatches a query either via the out-of-process sandboxed worker supervisor
    /// or local in-process fallback.
    public func query(pluginId: String, query: String) -> (requestId: UUID, stream: AsyncStream<IPCResponse>) {
        if getNativePlugin(id: pluginId) == nil,
           let sup = supervisor, sup.isWorkerRunning || PluginWorkerSupervisor.findWorkerBinary() != nil {
            return sup.query(pluginId: pluginId, query: query)
        }

        // In-process fallback
        let requestId = UUID()
        let stream = AsyncStream<IPCResponse> { continuation in
            let localPlugin = self.getNativePlugin(id: pluginId)
            guard let plugin = localPlugin as? (any TitikStreamingPlugin) else {
                continuation.yield(.queryError(requestId: requestId, error: "Plugin '\(pluginId)' not found or not streaming"))
                continuation.finish()
                return
            }

            Task {
                do {
                    let canvas = try await plugin.onQuery(query)
                    switch canvas {
                    case .streaming(let emitter):
                        let events = await emitter.stream()
                        var emittedFinished = false
                        for await event in events {
                            if case .finished = event { emittedFinished = true }
                            continuation.yield(.streamEvent(requestId: requestId, event: event))
                        }
                        if !emittedFinished {
                            continuation.yield(.streamEvent(requestId: requestId, event: .finished))
                        }
                    case .list(let items):
                        continuation.yield(.listResult(requestId: requestId, items: items))
                    case .empty, .customView:
                        continuation.yield(.listResult(requestId: requestId, items: []))
                    }
                } catch {
                    continuation.yield(.queryError(requestId: requestId, error: error.localizedDescription))
                }
                continuation.finish()
            }
        }

        return (requestId, stream)
    }

    public func unloadPlugin(id: String) {
        lock.lock()
        let native = nativePlugins.removeValue(forKey: id)
        lock.unlock()

        if let n = native {
            n.cancelAllTasks()
            n.plugin.onShutdown()
            Logger.shared.info("Unloaded native plugin \(id)", subsystem: "Titik.PluginHost")
        }

        supervisor?.unloadPlugin(pluginId: id)
    }

    public func loadAll(from directories: [URL]? = nil) {
        let dirs = directories ?? PluginHost.defaultPluginDirectories
        let fileManager = FileManager.default

        for dir in dirs {
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }

            for url in contents {
                if url.pathExtension == "titikplugin" || url.pathExtension == "bundle" {
                    _ = loadPlugin(at: url.path)
                }
            }
        }
    }

    public func loadedManifests() -> [PluginManifest] {
        lock.lock()
        defer { lock.unlock() }
        return nativePlugins.values.map { $0.manifest }
    }

    public func cancelAllActiveTasks() {
        lock.lock()
        let activeNatives = Array(nativePlugins.values)
        lock.unlock()

        for native in activeNatives {
            native.cancelAllTasks()
        }

        supervisor?.cancelAllQueries()
    }

    public func shutdownAll() {
        cancelAllActiveTasks()

        lock.lock()
        defer { lock.unlock() }

        for (_, native) in nativePlugins {
            native.plugin.onShutdown()
        }
        nativePlugins.removeAll()

        supervisor?.shutdown()

        Logger.shared.info("Shutdown all plugins", subsystem: "Titik.PluginHost")
    }

    deinit {
        shutdownAll()
    }
}
