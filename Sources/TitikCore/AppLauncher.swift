import Foundation
import AppKit

public struct AppInfo: Identifiable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let bundleURL: URL
    public let path: String
    public let icon: NSImage?
    public let processIdentifier: pid_t?

    public init(name: String, bundleURL: URL, icon: NSImage? = nil, processIdentifier: pid_t? = nil) {
        self.id = bundleURL.path
        self.name = name
        self.bundleURL = bundleURL
        self.path = bundleURL.path
        self.icon = icon
        self.processIdentifier = processIdentifier
    }
}

public final class AppLauncher: @unchecked Sendable {
    public static let shared = AppLauncher()

    private let lock = NSLock()
    private var cachedApps: [AppInfo] = []
    private var lastScanTime: Date?
    private var activeScanTask: Task<[AppInfo], Never>?
    private var iconCache: [String: NSImage] = [:]

    public init() {}

    public func icon(forPath path: String) -> NSImage {
        let cached: NSImage? = lock.withLock {
            iconCache[path]
        }
        if let cached = cached {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        lock.withLock {
            iconCache[path] = icon
        }
        return icon
    }

    private func getCachedApps() -> [AppInfo]? {
        lock.withLock {
            cachedApps.isEmpty ? nil : cachedApps
        }
    }

    private func getOrStartScanTask() -> Task<[AppInfo], Never> {
        lock.withLock {
            if let existing = activeScanTask {
                return existing
            }
            let newTask = Task<[AppInfo], Never> {
                let scanned = self.performScanApplications(directories: AppLauncher.defaultSearchDirectories, maxDepth: 3)
                self.lock.withLock {
                    self.cachedApps = scanned
                    self.lastScanTime = Date()
                    self.activeScanTask = nil
                }
                return scanned
            }
            self.activeScanTask = newTask
            return newTask
        }
    }

    public static let defaultSearchDirectories: [URL] = {
        let fileManager = FileManager.default
        var urls: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ]
        let cryptexApps = URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications")
        if fileManager.fileExists(atPath: cryptexApps.path) {
            urls.append(cryptexApps)
        }
        let userApps = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        if fileManager.fileExists(atPath: userApps.path) {
            urls.append(userApps)
        }
        return urls
    }()

    public func getRunningApplications() -> [AppInfo] {
        let currentPID = NSRunningApplication.current.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != currentPID
        }

        var results: [AppInfo] = []
        for app in apps {
            guard let bundleURL = app.bundleURL else { continue }
            let name = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
            let icon = app.icon ?? self.icon(forPath: bundleURL.path)
            results.append(AppInfo(name: name, bundleURL: bundleURL, icon: icon, processIdentifier: app.processIdentifier))
        }

        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return results
    }

    @discardableResult
    public func activateRunningApp(bundleURL: URL? = nil, processIdentifier: pid_t? = nil) -> Bool {
        if let pid = processIdentifier, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return app.activate(options: .activateIgnoringOtherApps)
        }
        if let bundleURL = bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true

            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var success = false

            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { app, error in
                if let error = error {
                    Logger.shared.error(
                        "Failed to activate app at \(bundleURL.path): \(error.localizedDescription)",
                        subsystem: "Titik.AppLauncher"
                    )
                    success = false
                } else {
                    Logger.shared.info(
                        "Activated application: \(app?.localizedName ?? bundleURL.lastPathComponent)",
                        subsystem: "Titik.AppLauncher"
                    )
                    success = true
                }
                semaphore.signal()
            }

            _ = semaphore.wait(timeout: .now() + 2.0)
            return success
        }
        return false
    }

    @discardableResult
    public func scanApplications(directories: [URL]? = nil, maxDepth: Int = 3) -> [AppInfo] {
        let dirs = directories ?? AppLauncher.defaultSearchDirectories
        let scanned = performScanApplications(directories: dirs, maxDepth: maxDepth)
        lock.withLock {
            self.cachedApps = scanned
            self.lastScanTime = Date()
        }
        return scanned
    }

    private func performScanApplications(directories: [URL], maxDepth: Int) -> [AppInfo] {
        let fileManager = FileManager.default
        var results: [AppInfo] = []
        var seenPaths = Set<String>()

        for dir in directories {
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            scanDirectory(dir, currentDepth: 1, maxDepth: maxDepth, results: &results, seenPaths: &seenPaths)
        }

        // Sort alphabetically by clean name
        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        Logger.shared.info("Scanned \(results.count) applications", subsystem: "Titik.AppLauncher")
        return results
    }

    private let ignoredFolderNames: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData", ".Trash", "Caches", "tmp", "temp",
        "Frameworks", "PlugIns", "SharedSupport", "XPCServices", "Resources"
    ]

    private func scanDirectory(_ directory: URL, currentDepth: Int, maxDepth: Int, results: inout [AppInfo], seenPaths: inout Set<String>) {
        guard currentDepth <= maxDepth else { return }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let path = url.path
            let filename = url.lastPathComponent
            if ignoredFolderNames.contains(filename) { continue }

            if path.hasSuffix(".app") {
                if !seenPaths.contains(path) {
                    seenPaths.insert(path)
                    let name = url.deletingPathExtension().lastPathComponent
                    let appIcon = icon(forPath: path)
                    results.append(AppInfo(name: name, bundleURL: url, icon: appIcon))
                }
                // Do NOT descend into the .app bundle directory itself!
                continue
            }

            // If it is a directory and not a package, recurse
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                if let isPkg = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage, isPkg {
                    continue
                }
                scanDirectory(url, currentDepth: currentDepth + 1, maxDepth: maxDepth, results: &results, seenPaths: &seenPaths)
            }
        }
    }

    public func getApplicationsAsync() async -> [AppInfo] {
        if let apps = getCachedApps() {
            return apps
        }
        let task = getOrStartScanTask()
        return await task.value
    }

    public func getApplications() -> [AppInfo] {
        if let apps = getCachedApps() {
            return apps
        }
        return scanApplications()
    }

    public func searchApplications(query: String) -> [SearchItem] {
        let apps = getApplications()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return apps.map { app in
                SearchItem(
                    id: "app:\(app.bundleURL.path)",
                    title: app.name,
                    subtitle: app.path,
                    category: .application,
                    score: 50,
                    icon: app.icon,
                    actionPayload: app.path,
                    autocompletePayload: app.name,
                    action: { [path = app.path] in
                        AppLauncher.shared.launchApp(at: path)
                    }
                )
            }
        }

        var results: [SearchItem] = []
        for app in apps {
            if let match = FuzzyMatcher.match(query: trimmed, target: app.name) {
                results.append(
                    SearchItem(
                        id: "app:\(app.bundleURL.path)",
                        title: app.name,
                        subtitle: app.path,
                        category: .application,
                        score: match.score + 50,
                        icon: app.icon,
                        actionPayload: app.path,
                        matchedIndices: match.matchedIndices,
                        autocompletePayload: app.name,
                        action: { [path = app.path] in
                            AppLauncher.shared.launchApp(at: path)
                        }
                    )
                )
            }
        }

        results.sort { $0.score > $1.score }
        return results
    }

    @discardableResult
    public func launchApp(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var success = false

        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error = error {
                Logger.shared.error("Failed to launch app at \(path): \(error.localizedDescription)", subsystem: "Titik.AppLauncher")
                success = false
            } else {
                Logger.shared.info("Launched application: \(app?.localizedName ?? url.lastPathComponent)", subsystem: "Titik.AppLauncher")
                success = true
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2.0)
        return success
    }
}
