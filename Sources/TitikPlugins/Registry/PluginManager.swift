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
    private let pluginsDirectory: URL?
    private let lock = NSLock()

    public init(
        host: PluginHost = .shared,
        configLoader: ConfigLoader = .shared,
        pluginsDirectory: URL? = nil
    ) {
        self.host = host
        self.configLoader = configLoader
        self.pluginsDirectory = pluginsDirectory
    }

    public convenience init(host: PluginHost = .shared, configLoader: ConfigLoader = .shared) {
        self.init(host: host, configLoader: configLoader, pluginsDirectory: nil)
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

            if seenIds.contains(id) {
                continue
            }

            // Validate filename convention
            let stem = url.deletingPathExtension().lastPathComponent
            let sanitizedName = manifest.name.replacingOccurrences(of: " ", with: "")
            let matchesExpected = stem == id || stem == manifest.name || stem == sanitizedName || stem == manifest.entrypoint
            if !matchesExpected {
                Logger.shared.warn(
                    "Plugin filename mismatch: expected '\(id).bundle', got '\(url.lastPathComponent)'. Loading anyway.",
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
            results.append((manifest, registeredEnabled: registrations[manifest.id]))
        }
        return results
    }

    // MARK: - Private

    /// Scans ~/.config/titik/plugins/ and Bundle.main.builtInPlugInsURL for .bundle and .titikplugin bundles and parses their manifests.
    private func discoverBundles() -> [(manifest: PluginManifest, url: URL)] {
        let isRunningInTestProcess = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["SWIFT_TESTING"] != nil ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.contains("xctest") || $0.contains("testing-helper") || $0.contains("TitikPackageTests") })

        var searchDirs: [URL] = []
        if let customDir = pluginsDirectory {
            searchDirs.append(customDir)
        } else if !isRunningInTestProcess {
            searchDirs.append(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/titik/plugins")
            )
        }

        let fileManager = FileManager.default
        if let builtIn = Bundle.main.builtInPlugInsURL {
            searchDirs.append(builtIn)
        }

        let exeURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let appPluginsDir = exeURL.standardized.deletingLastPathComponent().appendingPathComponent("plugins")
        if fileManager.fileExists(atPath: appPluginsDir.path) {
            searchDirs.append(appPluginsDir)
        }

        var discoveredIds = Set<String>()
        var results: [(PluginManifest, URL)] = []

        for dir in searchDirs {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else {
                continue
            }

            for url in contents where url.pathExtension == "bundle" || url.pathExtension == "titikplugin" {
                var manifestURL = url.appendingPathComponent("Contents/Resources/manifest.json")
                if !fileManager.fileExists(atPath: manifestURL.path) {
                    manifestURL = url.appendingPathComponent("manifest.json")
                }
                guard let data = try? Data(contentsOf: manifestURL) else {
                    Logger.shared.warn("Missing manifest.json in bundle: \(url.lastPathComponent)", subsystem: "Titik.PluginManager")
                    continue
                }
                do {
                    let manifest = try PluginManifest.validate(jsonData: data)
                    if discoveredIds.contains(manifest.id) {
                        if let existingIndex = results.firstIndex(where: { $0.0.id == manifest.id }) {
                            let existingURL = results[existingIndex].1
                            let existingDate = (try? existingURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                            let newDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                            if newDate > existingDate {
                                Logger.shared.info("Replacing older bundle for plugin '\(manifest.id)' with newer bundle at \(url.path)", subsystem: "Titik.PluginManager")
                                results[existingIndex] = (manifest, url)
                            } else {
                                Logger.shared.info("Skipping duplicate bundle for plugin '\(manifest.id)' at \(url.path)", subsystem: "Titik.PluginManager")
                            }
                        }
                        continue
                    }
                    discoveredIds.insert(manifest.id)
                    results.append((manifest, url))
                } catch {
                    Logger.shared.warn("Invalid manifest in \(url.lastPathComponent): \(error.localizedDescription)", subsystem: "Titik.PluginManager")
                }
            }
        }

        return results
    }
}
