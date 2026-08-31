import Foundation
import TitikCore
import TitikPluginKit

private final class LoadedPluginInstance {
    let descriptor: PluginDescriptor
    let handle: UnsafeMutableRawPointer
    let plugin: CTitikPlugin
    var lastModifiedTime: Date

    init(descriptor: PluginDescriptor, handle: UnsafeMutableRawPointer, plugin: CTitikPlugin, lastModifiedTime: Date) {
        self.descriptor = descriptor
        self.handle = handle
        self.plugin = plugin
        self.lastModifiedTime = lastModifiedTime
    }
}

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
    public static let shared = PluginHost()

    private let lock = NSLock()
    private var plugins: [String: LoadedPluginInstance] = [:]
    private var nativePlugins: [String: LoadedNativePluginInstance] = [:]

    public init() {}

    public static var defaultPluginDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".config/titik/plugins"),
            URL(fileURLWithPath: "plugins"),
            URL(fileURLWithPath: "plugins/math_plugin")
        ]
    }

    // MARK: - Generic Loader

    public func loadPlugin(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension == "titikplugin" || FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) {
            do {
                _ = try loadNativePluginBundle(at: url)
                return true
            } catch {
                Logger.shared.error("Failed to load native plugin at \(path): \(error.localizedDescription)", subsystem: "Titik.PluginHost")
                return false
            }
        }

        lock.lock()
        defer { lock.unlock() }
        return loadLegacyPluginLocked(at: path)
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

        // 5. Register in host
        registerNativePlugin(instance, manifest: manifest, bundle: bundle)
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

    // MARK: - Legacy Dylib Loading

    private func loadLegacyPluginLocked(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.shared.warn("Plugin file does not exist: \(path)", subsystem: "Titik.PluginHost")
            return false
        }

        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let err = String(cString: dlerror())
            Logger.shared.error("Failed to dlopen plugin at \(path): \(err)", subsystem: "Titik.PluginHost")
            return false
        }

        guard let entrySym = dlsym(handle, "titik_plugin_entry") else {
            Logger.shared.error("Missing symbol 'titik_plugin_entry' in \(path)", subsystem: "Titik.PluginHost")
            dlclose(handle)
            return false
        }

        let entryFn = unsafeBitCast(entrySym, to: CTitikPluginEntryFn.self)
        guard let rawPtr = entryFn() else {
            Logger.shared.error("titik_plugin_entry returned NULL for \(path)", subsystem: "Titik.PluginHost")
            dlclose(handle)
            return false
        }

        let plugin = rawPtr.assumingMemoryBound(to: CTitikPlugin.self).pointee

        let id = plugin.id.flatMap { String(cString: $0) } ?? UUID().uuidString
        let name = plugin.name.flatMap { String(cString: $0) } ?? "Unknown Plugin"
        let version = plugin.version.flatMap { String(cString: $0) } ?? "1.0.0"
        let description = plugin.description.flatMap { String(cString: $0) } ?? ""
        let shortBang = plugin.short_bang.flatMap { String(cString: $0) } ?? ""

        // If plugin with this ID already loaded, unload first
        if let existing = plugins[id] {
            existing.plugin.shutdown?()
            dlclose(existing.handle)
            plugins.removeValue(forKey: id)
        }

        // Call init()
        if let initFn = plugin.`init` {
            let res = initFn()
            if res != 0 {
                Logger.shared.error("Plugin \(name) (\(id)) init failed with code \(res)", subsystem: "Titik.PluginHost")
                dlclose(handle)
                return false
            }
        }

        let modTime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
        let descriptor = PluginDescriptor(id: id, name: name, version: version, description: description, shortBang: shortBang, path: path)
        let instance = LoadedPluginInstance(descriptor: descriptor, handle: handle, plugin: plugin, lastModifiedTime: modTime)

        plugins[id] = instance
        Logger.shared.info("Successfully loaded legacy plugin: \(name) v\(version) (\(id)) from \(path)", subsystem: "Titik.PluginHost")
        return true
    }

    // MARK: - Query & Dispatch Routing

    public func findActivePlugin(command: String) -> PluginDescriptor? {
        lock.lock()
        let active = Array(plugins.values)
        let natives = Array(nativePlugins.values)
        lock.unlock()

        let lower = command.lowercased()

        // Check native plugins
        for native in natives {
            if native.manifest.name.lowercased() == lower {
                return PluginDescriptor(
                    id: native.manifest.id,
                    name: native.manifest.name,
                    version: native.manifest.version,
                    description: native.manifest.description,
                    shortBang: native.manifest.normalizedBangs.first ?? "",
                    path: native.bundle?.bundlePath ?? ""
                )
            }
            for bang in native.manifest.normalizedBangs {
                let clean = bang.lowercased()
                if clean == lower {
                    return PluginDescriptor(
                        id: native.manifest.id,
                        name: native.manifest.name,
                        version: native.manifest.version,
                        description: native.manifest.description,
                        shortBang: bang,
                        path: native.bundle?.bundlePath ?? ""
                    )
                }
            }
        }

        // Check legacy dylibs
        for inst in active {
            let name = inst.descriptor.name.lowercased()
            var short = inst.descriptor.shortBang.lowercased()
            if short.hasPrefix("!") {
                short = String(short.dropFirst())
            }
            if lower == name || (!short.isEmpty && lower == short) {
                return inst.descriptor
            }
        }
        return nil
    }

    public func findActivePlugin(forQuery query: String) -> (descriptor: PluginDescriptor, subquery: String)? {
        lock.lock()
        let active = Array(plugins.values)
        let natives = Array(nativePlugins.values)
        lock.unlock()

        guard query.hasPrefix("!") else { return nil }

        let lower = query.lowercased()

        // 1. Check native plugins
        for native in natives {
            for bang in native.manifest.normalizedBangs {
                let exactBang = "!" + bang.lowercased()
                let bangPrefix = exactBang + " "
                if lower == exactBang {
                    let desc = PluginDescriptor(
                        id: native.manifest.id,
                        name: native.manifest.name,
                        version: native.manifest.version,
                        description: native.manifest.description,
                        shortBang: bang,
                        path: native.bundle?.bundlePath ?? ""
                    )
                    return (desc, "")
                } else if lower.hasPrefix(bangPrefix) {
                    let subquery = String(query.dropFirst(bangPrefix.count)).trimmingCharacters(in: .whitespaces)
                    let desc = PluginDescriptor(
                        id: native.manifest.id,
                        name: native.manifest.name,
                        version: native.manifest.version,
                        description: native.manifest.description,
                        shortBang: bang,
                        path: native.bundle?.bundlePath ?? ""
                    )
                    return (desc, subquery)
                }
            }
        }

        // 2. Check legacy dylibs
        for inst in active {
            let name = inst.descriptor.name.hasPrefix("!") ? String(inst.descriptor.name.dropFirst()) : inst.descriptor.name
            let exactName = "!" + name.lowercased()
            let nameBang = exactName + " "
            let short = inst.descriptor.shortBang.hasPrefix("!") ? String(inst.descriptor.shortBang.dropFirst()) : inst.descriptor.shortBang
            let exactShort = short.isEmpty ? "" : ("!" + short.lowercased())
            let shortBang = short.isEmpty ? "" : (exactShort + " ")

            if lower == exactName {
                return (inst.descriptor, "")
            } else if lower.hasPrefix(nameBang) {
                let subquery = String(query.dropFirst(nameBang.count)).trimmingCharacters(in: .whitespaces)
                return (inst.descriptor, subquery)
            } else if !exactShort.isEmpty && lower == exactShort {
                return (inst.descriptor, "")
            } else if !shortBang.isEmpty && lower.hasPrefix(shortBang) {
                let subquery = String(query.dropFirst(shortBang.count)).trimmingCharacters(in: .whitespaces)
                return (inst.descriptor, subquery)
            }
        }
        return nil
    }

    public func queryPlugin(id: String, subquery: String) -> [PluginItem] {
        lock.lock()
        guard let instance = plugins[id], let queryFn = instance.plugin.query else {
            lock.unlock()
            return []
        }
        lock.unlock()

        var results: [PluginItem] = []
        let maxItems = 16
        let itemSize = PluginItem.cItemSize
        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: itemSize * maxItems, alignment: 8)
        defer { rawBuffer.deallocate() }
        memset(rawBuffer, 0, itemSize * maxItems)

        let count = subquery.withCString { qStr in
            queryFn(qStr, rawBuffer, Int32(maxItems))
        }

        guard count > 0 else { return [] }
        let actualCount = min(Int(count), maxItems)
        for i in 0..<actualCount {
            let itemPtr = rawBuffer.advanced(by: i * itemSize)
            let item = PluginItem.fromRawMemory(itemPtr, pluginId: instance.descriptor.id)
            results.append(item)
        }
        return results
    }

    public func unloadPlugin(id: String) {
        lock.lock()
        defer { lock.unlock() }

        if let native = nativePlugins.removeValue(forKey: id) {
            native.cancelAllTasks()
            native.plugin.onShutdown()
            Logger.shared.info("Unloaded native plugin \(id)", subsystem: "Titik.PluginHost")
        }

        if let instance = plugins.removeValue(forKey: id) {
            instance.plugin.shutdown?()
            dlclose(instance.handle)
            Logger.shared.info("Unloaded legacy plugin \(id)", subsystem: "Titik.PluginHost")
        }
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
                } else if url.pathExtension == "dylib" {
                    _ = loadPlugin(at: url.path)
                }
            }
        }
    }

    public func queryAll(query: String) -> [PluginItem] {
        lock.lock()
        let activePlugins = Array(plugins.values)
        lock.unlock()

        var results: [PluginItem] = []
        let maxItems = 16
        let itemSize = PluginItem.cItemSize

        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: itemSize * maxItems, alignment: 8)
        defer { rawBuffer.deallocate() }

        for instance in activePlugins {
            guard let queryFn = instance.plugin.query else { continue }

            memset(rawBuffer, 0, itemSize * maxItems)

            let count = query.withCString { qStr in
                queryFn(qStr, rawBuffer, Int32(maxItems))
            }

            guard count > 0 else { continue }

            let actualCount = min(Int(count), maxItems)
            for i in 0..<actualCount {
                let itemPtr = rawBuffer.advanced(by: i * itemSize)
                let item = PluginItem.fromRawMemory(itemPtr, pluginId: instance.descriptor.id)
                results.append(item)
            }
        }

        return results
    }

    public func executeItem(pluginId: String, itemId: String, actionPayload: String) -> Bool {
        lock.lock()
        let instance = plugins[pluginId]
        lock.unlock()

        guard let inst = instance, let execFn = inst.plugin.execute else {
            Logger.shared.error("Cannot execute item: plugin \(pluginId) not found or no execute fn", subsystem: "Titik.PluginHost")
            return false
        }

        let res = itemId.withCString { idPtr in
            actionPayload.withCString { payloadPtr in
                execFn(idPtr, payloadPtr)
            }
        }

        Logger.shared.debug("Plugin \(pluginId) executed item \(itemId) with result \(res)", subsystem: "Titik.PluginHost")
        return res == 0
    }

    public func cancelAllActiveTasks() {
        lock.lock()
        let activeNatives = Array(nativePlugins.values)
        lock.unlock()

        for native in activeNatives {
            native.cancelAllTasks()
        }
    }

    public func checkAndReloadModifiedPlugins() {
        lock.lock()
        let active = Array(plugins.values)
        lock.unlock()

        let fileManager = FileManager.default
        for inst in active {
            guard let currentMod = try? fileManager.attributesOfItem(atPath: inst.descriptor.path)[.modificationDate] as? Date else { continue }
            if currentMod > inst.lastModifiedTime {
                Logger.shared.info("Plugin modified on disk, reloading: \(inst.descriptor.name)", subsystem: "Titik.PluginHost")
                _ = loadPlugin(at: inst.descriptor.path)
            }
        }
    }

    public func loadedPlugins() -> [PluginDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        var descriptors = plugins.values.map { $0.descriptor }
        for native in nativePlugins.values {
            descriptors.append(
                PluginDescriptor(
                    id: native.manifest.id,
                    name: native.manifest.name,
                    version: native.manifest.version,
                    description: native.manifest.description,
                    shortBang: native.manifest.normalizedBangs.first ?? "",
                    path: native.bundle?.bundlePath ?? ""
                )
            )
        }
        return descriptors
    }

    public func shutdownAll() {
        cancelAllActiveTasks()

        lock.lock()
        defer { lock.unlock() }

        for (_, native) in nativePlugins {
            native.plugin.onShutdown()
        }
        nativePlugins.removeAll()

        for (_, instance) in plugins {
            instance.plugin.shutdown?()
            dlclose(instance.handle)
        }
        plugins.removeAll()

        Logger.shared.info("Shutdown all plugins", subsystem: "Titik.PluginHost")
    }

    deinit {
        shutdownAll()
    }
}
