import Foundation
import TitikCore
import TitikPluginKit

/// Manages plugin lifecycle. State is read from config.json on every reindex.
/// The user edits config.json directly to enable/disable plugins.
/// Plugin ID must match the bundle filename stem (e.g. "io.github.foo.bar.titikplugin").
public final class PluginManager: @unchecked Sendable {
    public static let shared = PluginManager()

    private let host: PluginHost
    private let configLoader: ConfigLoader
    private let lock = NSLock()

    public init(host: PluginHost = .shared, configLoader: ConfigLoader = .shared) {
        self.host = host
        self.configLoader = configLoader
    }

    /// Re-reads config.json, rescans plugins folder, loads enabled plugins, unloads disabled ones.
    /// Called at startup and on `!plugin reload`.
    public func reindex() {
        lock.lock()
        defer { lock.unlock() }

        // 1. Re-read config from disk
        configLoader.load()
        let registrations = configLoader.currentConfig.plugins.registrations

        // 2. Load / update built-in plugins
        let currentlyLoaded = Set(host.allNativePlugins().map { $0.manifest.id })
        for entry in BuiltinPluginRegistry.all {
            let isEnabled = registrations[entry.id] ?? true
            if isEnabled {
                if !currentlyLoaded.contains(entry.id) {
                    let plugin = entry.factory(PluginContext(pluginId: entry.id))
                    host.registerNativePlugin(plugin, manifest: entry.manifest)
                }
            } else {
                if currentlyLoaded.contains(entry.id) {
                    host.unloadPlugin(id: entry.id)
                }
            }
        }

        // 3. Discover bundles on disk
        let discovered = discoverBundles()

        // 4. Update currently loaded native plugins set after built-ins handling
        let loadedAfterBuiltins = Set(host.allNativePlugins().map { $0.manifest.id })

        // 5. Process each discovered bundle
        var seenIds = Set<String>()
        for (manifest, url) in discovered {
            let id = manifest.id

            // Validate filename convention
            let expectedStem = url.deletingPathExtension().lastPathComponent
            if expectedStem != id {
                Logger.shared.warn(
                    "Plugin filename mismatch: expected '\(id).titikplugin', got '\(url.lastPathComponent)'. Loading anyway.",
                    subsystem: "Titik.PluginManager"
                )
            }

            seenIds.insert(id)
            let enabled = registrations[id] ?? false

            if enabled {
                if !loadedAfterBuiltins.contains(id) {
                    do {
                        _ = try host.loadNativePluginBundle(at: url)
                    } catch {
                        Logger.shared.error(
                            "Failed to load plugin '\(id)': \(error.localizedDescription)",
                            subsystem: "Titik.PluginManager"
                        )
                    }
                }
            } else {
                if loadedAfterBuiltins.contains(id) {
                    host.unloadPlugin(id: id)
                }
            }
        }

        // 6. Unload plugins that are no longer on disk (excluding built-ins)
        let builtinIds = Set(BuiltinPluginRegistry.all.map { $0.id })
        let currentLoadedFinal = Set(host.allNativePlugins().map { $0.manifest.id })
        for id in currentLoadedFinal where !seenIds.contains(id) && !builtinIds.contains(id) {
            host.unloadPlugin(id: id)
            Logger.shared.info("Unloaded plugin no longer on disk: \(id)", subsystem: "Titik.PluginManager")
        }

        Logger.shared.info("Plugin reindex complete. Discovered: \(discovered.count), registered: \(registrations.count)", subsystem: "Titik.PluginManager")
    }

    /// Returns all plugins (built-ins and disk bundles) with their registration state.
    /// - `registeredEnabled == nil` → on disk but not in config (never loaded)
    /// - `registeredEnabled == true` → enabled
    /// - `registeredEnabled == false` → disabled
    public func list() -> [(manifest: PluginManifest, registeredEnabled: Bool?)] {
        let registrations = configLoader.currentConfig.plugins.registrations
        var results: [(manifest: PluginManifest, registeredEnabled: Bool?)] = []
        for entry in BuiltinPluginRegistry.all {
            results.append((manifest: entry.manifest, registeredEnabled: registrations[entry.id] ?? true))
        }
        for (manifest, _) in discoverBundles() {
            results.append((manifest: manifest, registeredEnabled: registrations[manifest.id]))
        }
        return results
    }

    // MARK: - Private

    /// Scans ~/.config/titik/plugins/ for .titikplugin bundles and parses their manifests.
    private func discoverBundles() -> [(manifest: PluginManifest, url: URL)] {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/titik/plugins")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var results: [(PluginManifest, URL)] = []

        for url in contents where url.pathExtension == "titikplugin" {
            let manifestURL = url.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL) else {
                Logger.shared.warn("Missing manifest.json in bundle: \(url.lastPathComponent)", subsystem: "Titik.PluginManager")
                continue
            }
            do {
                let manifest = try PluginManifest.validate(jsonData: data)
                results.append((manifest, url))
            } catch {
                Logger.shared.warn("Invalid manifest in \(url.lastPathComponent): \(error.localizedDescription)", subsystem: "Titik.PluginManager")
            }
        }

        return results
    }
}
