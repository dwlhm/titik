import Foundation
import TitikCore

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

public final class PluginHost: @unchecked Sendable {
    public static let shared = PluginHost()

    private let lock = NSLock()
    private var plugins: [String: LoadedPluginInstance] = [:]

    public init() {}

    public static var defaultPluginDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".config/titik/plugins"),
            URL(fileURLWithPath: "plugins"),
            URL(fileURLWithPath: "plugins/math_plugin")
        ]
    }

    public func loadPlugin(at path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadPluginLocked(at: path)
    }

    private func loadPluginLocked(at path: String) -> Bool {
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
        Logger.shared.info("Successfully loaded plugin: \(name) v\(version) (\(id)) from \(path)", subsystem: "Titik.PluginHost")
        return true
    }

    public func findActivePlugin(command: String) -> PluginDescriptor? {
        lock.lock()
        let active = Array(plugins.values)
        lock.unlock()

        let lower = command.lowercased()
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
        lock.unlock()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!") else { return nil }

        let lower = trimmed.lowercased()
        for inst in active {
            let nameBang = "!" + inst.descriptor.name.lowercased()
            let shortBang = inst.descriptor.shortBang.lowercased()
            let normalizedShortBang = shortBang.hasPrefix("!") ? shortBang : ("!" + shortBang)

            // Must be followed by a space
            if lower.hasPrefix(nameBang + " ") {
                let subquery = String(trimmed.dropFirst(nameBang.count + 1)).trimmingCharacters(in: .whitespaces)
                return (inst.descriptor, subquery)
            } else if !shortBang.isEmpty && lower.hasPrefix(normalizedShortBang + " ") {
                let subquery = String(trimmed.dropFirst(normalizedShortBang.count + 1)).trimmingCharacters(in: .whitespaces)
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

        guard let instance = plugins.removeValue(forKey: id) else { return }
        instance.plugin.shutdown?()
        dlclose(instance.handle)
        Logger.shared.info("Unloaded plugin \(id)", subsystem: "Titik.PluginHost")
    }

    public func loadAll(from directories: [URL]? = nil) {
        let dirs = directories ?? PluginHost.defaultPluginDirectories
        let fileManager = FileManager.default

        for dir in dirs {
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }

            for url in contents {
                if url.pathExtension == "dylib" {
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
        return plugins.values.map { $0.descriptor }
    }

    public func shutdownAll() {
        lock.lock()
        defer { lock.unlock() }

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
