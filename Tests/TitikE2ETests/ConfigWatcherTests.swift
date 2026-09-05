import Foundation
import Testing
import TitikCore

@Suite("ConfigWatcher Tests")
struct ConfigWatcherTests {

    @Test("ConfigWatcher lifecycle and state tracking")
    func testWatcherLifecycle() throws {
        let watcher = ConfigWatcher(debounceInterval: 0.05)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)

        #expect(!watcher.isWatching)
        #expect(watcher.watchedPath == nil)

        watcher.startWatching(path: configURL.path) { _ in }

        #expect(watcher.isWatching)
        #expect(watcher.watchedPath == configURL.path)

        watcher.stopWatching()

        #expect(!watcher.isWatching)
        #expect(watcher.watchedPath == nil)
    }

    @Test("ConfigWatcher detects file modifications and delivers updated config")
    func testWatcherFileModificationTrigger() async throws {
        let watcher = ConfigWatcher(debounceInterval: 0.05)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            watcher.stopWatching()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let configURL = tempDir.appendingPathComponent("config.json")
        let initialJSON = """
        {
            "window": { "width": 640 },
            "shortcuts": []
        }
        """
        try initialJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let expectation = LockedBox<Config?>(nil)

        watcher.startWatching(path: configURL.path) { newConfig in
            expectation.set(newConfig)
        }

        // Give dispatch source time to arm
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let updatedJSON = """
        {
            "window": { "width": 880 },
            "shortcuts": [
                {
                    "id": "test-shortcut",
                    "key": "k",
                    "modifiers": ["cmd"],
                    "mode": "background",
                    "action": {
                        "type": "quick_link",
                        "target": "https://apple.com"
                    }
                }
            ]
        }
        """
        try updatedJSON.write(to: configURL, atomically: false, encoding: .utf8)

        let satisfied = await waitForCondition(timeoutSeconds: 3.0) {
            expectation.get()?.window.width == 880
        }
        #expect(satisfied)

        let loaded = expectation.get()
        #expect(loaded != nil)
        #expect(loaded?.window.width == 880)
        #expect(loaded?.shortcuts.count == 1)
        #expect(loaded?.shortcuts.first?.id == "test-shortcut")
        #expect(loaded?.shortcuts.first?.action.target == "https://apple.com")
    }

    @Test("ConfigWatcher handles atomic file replacement")
    func testWatcherAtomicFileReplacement() async throws {
        let watcher = ConfigWatcher(debounceInterval: 0.05)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            watcher.stopWatching()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let configURL = tempDir.appendingPathComponent("config.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)

        let expectation = LockedBox<Config?>(nil)

        watcher.startWatching(path: configURL.path) { newConfig in
            expectation.set(newConfig)
        }

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Write atomically (write to temp file and rename over target)
        let atomicJSON = """
        {
            "window": { "width": 920 },
            "shortcuts": [
                {
                    "id": "zen-shortcut",
                    "keys": "cmd+shift+z",
                    "action": { "type": "plugin_command", "target": "titik.builtin.zen" }
                }
            ]
        }
        """
        try atomicJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let satisfied = await waitForCondition(timeoutSeconds: 3.0) {
            expectation.get()?.window.width == 920
        }
        #expect(satisfied)

        let loaded = expectation.get()
        #expect(loaded != nil)
        #expect(loaded?.window.width == 920)
        #expect(loaded?.shortcuts.count == 1)
        #expect(loaded?.shortcuts.first?.id == "zen-shortcut")
    }

    @Test("ConfigWatcher triggerReload manually invokes callback")
    func testWatcherManualTriggerReload() async throws {
        let watcher = ConfigWatcher(debounceInterval: 0.05)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            watcher.stopWatching()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
            "window": { "width": 777 }
        }
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)

        let expectation = LockedBox<Config?>(nil)

        watcher.startWatching(path: configURL.path) { newConfig in
            expectation.set(newConfig)
        }

        watcher.triggerReload()

        let satisfied = await waitForCondition(timeoutSeconds: 3.0) {
            expectation.get()?.window.width == 777
        }
        #expect(satisfied)

        let loaded = expectation.get()
        #expect(loaded?.window.width == 777)
    }

    private func waitForCondition(
        timeoutSeconds: Double = 3.0,
        condition: @Sendable () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        return condition()
    }
}

/// Simple thread-safe box for async test assertions.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ initial: T) {
        self.value = initial
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
