import Foundation

/// Thread-safe live file watcher that observes `~/.config/titik/config.json` (or any custom path)
/// for modifications using `DispatchSourceFileSystemObject` with debouncing.
public final class ConfigWatcher: @unchecked Sendable {
    public static let shared = ConfigWatcher()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.titik.config.watcher", qos: .utility)

    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var dirSource: (any DispatchSourceFileSystemObject)?
    private var fileDescriptor: Int32 = -1
    private var dirDescriptor: Int32 = -1

    private var currentPath: String?
    private var changeHandler: (@Sendable (Config) -> Void)?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    public init(debounceInterval: TimeInterval = 0.10) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stopWatching()
    }

    /// Indicates whether the watcher is currently active.
    public var isWatching: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fileSource != nil || dirSource != nil
    }

    /// The path currently being observed.
    public var watchedPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentPath
    }

    /// Begins monitoring the specified configuration file path.
    /// - Parameters:
    ///   - path: Absolute or tilde-expanded file path to observe. Defaults to `ConfigLoader.userConfigPath.path`.
    ///   - onChange: Callback invoked on the watcher queue with the newly loaded `Config` whenever modifications settle.
    public func startWatching(
        path: String = ConfigLoader.userConfigPath.path,
        onChange: @escaping @Sendable (Config) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        // Clean up any existing watcher state before reattaching
        stopWatchingInternal()

        let resolvedPath = PathResolver.expandPath(path)
        self.currentPath = resolvedPath
        self.changeHandler = onChange

        setupWatchersInternal(for: resolvedPath)
        Logger.shared.info("Started watching config file at \(resolvedPath)", subsystem: "Titik.ConfigWatcher")
    }

    /// Stops watching and releases all underlying file descriptors and dispatch sources.
    public func stopWatching() {
        lock.lock()
        defer { lock.unlock() }
        stopWatchingInternal()
        Logger.shared.info("Stopped watching config file", subsystem: "Titik.ConfigWatcher")
    }

    /// Manually triggers a reload and notifies the change handler.
    public func triggerReload() {
        queue.async { [weak self] in
            self?.performReload()
        }
    }

    // MARK: - Internal Setup & Teardown

    private func setupWatchersInternal(for filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        let dirURL = fileURL.deletingLastPathComponent()

        // 1. Ensure parent directory exists and monitor it for atomic file replacements
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let dirFD = open(dirURL.path, O_EVTONLY)
        if dirFD >= 0 {
            self.dirDescriptor = dirFD
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirFD,
                eventMask: [.write, .extend, .rename, .link],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebouncedReload()
            }
            source.setCancelHandler {
                close(dirFD)
            }
            self.dirSource = source
            source.resume()
        }

        // 2. Monitor the config file itself if it exists
        if FileManager.default.fileExists(atPath: filePath) {
            setupFileSourceInternal(filePath: filePath)
        }
    }

    private func setupFileSourceInternal(filePath: String) {
        if let existing = fileSource {
            existing.cancel()
            fileSource = nil
        }
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }

        self.fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                // File was replaced atomically or removed; re-arm file source
                self.queue.async {
                    self.rearmFileSourceAfterAtomicReplace()
                }
            }
            self.scheduleDebouncedReload()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.fileSource = source
        source.resume()
    }

    private func rearmFileSourceAfterAtomicReplace() {
        lock.lock()
        defer { lock.unlock() }
        guard let path = currentPath else { return }

        // Close old file descriptor and source
        if let existing = fileSource {
            existing.cancel()
            fileSource = nil
        }
        fileDescriptor = -1

        // If file exists, attach fresh descriptor
        if FileManager.default.fileExists(atPath: path) {
            setupFileSourceInternal(filePath: path)
        }
    }

    private func stopWatchingInternal() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let source = fileSource {
            source.cancel()
            fileSource = nil
        }
        if let source = dirSource {
            source.cancel()
            dirSource = nil
        }

        fileDescriptor = -1
        dirDescriptor = -1
        currentPath = nil
        changeHandler = nil
    }

    // MARK: - Debounced Reload

    private func scheduleDebouncedReload() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performReload()
        }
        self.debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func performReload() {
        var targetPath: String?
        var handler: (@Sendable (Config) -> Void)?

        lock.lock()
        targetPath = currentPath
        handler = changeHandler
        lock.unlock()

        guard let targetPath, let handler else { return }

        // If the file source was dropped during an atomic write, re-arm it now
        lock.lock()
        if fileSource == nil && FileManager.default.fileExists(atPath: targetPath) {
            setupFileSourceInternal(filePath: targetPath)
        }
        lock.unlock()

        let targetURL = URL(fileURLWithPath: targetPath)
        let loadedConfig = ConfigLoader.shared.load(from: targetURL)

        Logger.shared.info(
            "ConfigWatcher detected file change, loaded updated config from \(targetPath)",
            subsystem: "Titik.ConfigWatcher"
        )
        handler(loadedConfig)
    }
}
