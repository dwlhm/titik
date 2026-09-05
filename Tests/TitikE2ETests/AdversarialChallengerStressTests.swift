import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform
@testable import TitikSearch

@Suite("Adversarial Challenger Stress & Boundary Tests")
struct AdversarialChallengerStressTests {

    // MARK: - 1. Hotkey Concurrency & Invariant Stress Tests

    @Test("Adversarial: 100 concurrent tasks hammering KeymapRegistry with registrations and unregistrations")
    func test_adversarial_keymapRegistryConcurrencyHammer() async {
        let registry = KeymapRegistry()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let keyNum = i % 15
                    let mod = (i % 2 == 0) ? "cmd" : "opt"
                    if let combo = KeyCombination(string: "\(mod)+\(keyNum)") {
                        let id = "adv.concurrency.worker.\(i)"
                        // Alternating actions
                        if i % 3 == 0 {
                            try? registry.register(combination: combo, identifier: id) {}
                        } else if i % 3 == 1 {
                            registry.unregister(identifier: id)
                        } else {
                            _ = registry.find(combination: combo)
                            _ = registry.isRegistered(identifier: id)
                        }
                    }
                }
            }
        }

        let bindings = registry.allBindings()

        // Verify invariant: allBindings count matches uniqueness of combinations
        let comboSet = Set(bindings.map(\.combination))
        #expect(bindings.count == comboSet.count)
    }

    @Test("Adversarial: KeymapRegistry multi-threaded rapid register, lookup, and unregister stress")
    func test_adversarial_keymapRegistryMultiThreadStress() async {
        let registry = KeymapRegistry()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let keyChar = Character(UnicodeScalar(97 + (i % 26))!) // a-z
                    if let combo = KeyCombination(string: "ctrl+\(keyChar)") {
                        let id = "adv.reg.worker.\(i)"
                        let runCount = CounterBox()
                        do {
                            try registry.register(combination: combo, identifier: id, mode: .background) {
                                runCount.increment()
                            }
                            _ = registry.isRegistered(identifier: id)
                            _ = registry.isRegistered(combination: combo)
                            _ = registry.find(identifier: id)
                            registry.find(combination: combo)?.action()
                        } catch {
                            // Expected collisions on duplicate combos
                        }

                        if i % 4 == 0 {
                            registry.unregister(identifier: id)
                        }
                    }
                }
            }
        }

        registry.clear()
        #expect(registry.allBindings().isEmpty)
    }

    // MARK: - 2. Key Collision, Race-to-Register, and Recovery

    @Test("Adversarial: 20 threads racing to register the exact same key combination")
    func test_adversarial_raceToRegisterDuplicateKeyCombination() async throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+shift+alt+k"))

        let successCounter = CounterBox()
        let failureCounter = CounterBox()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    do {
                        try registry.register(
                            combination: combo,
                            identifier: "racer.\(i)",
                            mode: .background
                        ) {}
                        successCounter.increment()
                    } catch KeymapError.duplicateBinding {
                        failureCounter.increment()
                    } catch {
                        // Unexpected error
                    }
                }
            }
        }

        // In a race for a single combination with distinct identifiers, exactly 1 must win
        #expect(successCounter.count == 1)
        #expect(failureCounter.count == 19)
        #expect(registry.isRegistered(combination: combo) == true)

        // Free the combination
        let winner = registry.find(combination: combo)
        #expect(winner != nil)
        if let winnerId = winner?.identifier {
            registry.unregister(identifier: winnerId)
        }
        #expect(registry.isRegistered(combination: combo) == false)

        // Now another registration must immediately succeed
        try registry.register(combination: combo, identifier: "subsequent.winner") {}
        #expect(registry.isRegistered(combination: combo) == true)
        #expect(registry.find(combination: combo)?.identifier == "subsequent.winner")
    }

    @Test("Adversarial: Rapid cyclic rebinding between two identifiers and combinations")
    func test_adversarial_cyclicKeyRebinding() throws {
        let registry = KeymapRegistry()
        let comboA = try #require(KeyCombination(string: "cmd+1"))
        let comboB = try #require(KeyCombination(string: "cmd+2"))

        for iteration in 0..<20 {
            registry.unregister(identifier: "actionA")
            registry.unregister(identifier: "actionB")
            if iteration % 2 == 0 {
                try registry.register(combination: comboA, identifier: "actionA") {}
                try registry.register(combination: comboB, identifier: "actionB") {}
            } else {
                // Swap assignments
                try registry.register(combination: comboB, identifier: "actionA") {}
                try registry.register(combination: comboA, identifier: "actionB") {}
            }
        }

        #expect(registry.allBindings().count == 2)
    }

    // MARK: - 3. ConfigWatcher Rapid Mutations & Filesystem Stress

    @Test("Adversarial: Rapid atomic config file replacements and watcher debouncing")
    func test_adversarial_configWatcherRapidAtomicWrites() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_watcher_adv_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent("config.json")

        // Initial write
        let initialConfig = Config(window: WindowConfig(width: 500, height: 300))
        let initialData = try JSONEncoder().encode(initialConfig)
        try initialData.write(to: configFile, options: .atomic)

        let reloadCounter = CounterBox()
        let lastReceivedWidth = AtomicDoubleBox()

        let watcher = ConfigWatcher(debounceInterval: 0.05)
        watcher.startWatching(path: configFile.path) { updatedConfig in
            reloadCounter.increment()
            lastReceivedWidth.set(updatedConfig.window.width)
        }

        #expect(watcher.isWatching == true)

        // Give dispatch source time to arm in kernel
        try await Task.sleep(nanoseconds: 50_000_000)

        // Perform 10 rapid atomic writes
        for i in 1...10 {
            let config = Config(window: WindowConfig(width: Double(500 + i), height: 300))
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFile, options: .atomic)
        }

        let satisfied = await waitForCondition(timeoutSeconds: 3.0) {
            lastReceivedWidth.get() == 510.0
        }

        watcher.stopWatching()
        #expect(watcher.isWatching == false)
        #expect(satisfied)
        #expect(reloadCounter.count >= 1)
    }

    @Test("Adversarial: ConfigWatcher handles file deletion, recreate, and corrupted writes")
    func test_adversarial_configWatcherFileDeletionAndCorruptionRecovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_watcher_corrupt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent("config.json")
        let initialConfig = Config(window: WindowConfig(width: 600, height: 400))
        try JSONEncoder().encode(initialConfig).write(to: configFile, options: .atomic)

        let receivedWidth = AtomicDoubleBox()

        let watcher = ConfigWatcher(debounceInterval: 0.03)
        watcher.startWatching(path: configFile.path) { conf in
            receivedWidth.set(conf.window.width)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // 1. Delete the config file
        try FileManager.default.removeItem(at: configFile)
        _ = await waitForCondition(timeoutSeconds: 1.5) {
            receivedWidth.get() == 720.0
        }

        // 2. Write completely invalid garbage JSON
        let garbage = "{ \"window\": \"not an object\", \"corrupted\": [ "
        try garbage.write(to: configFile, atomically: true, encoding: .utf8)
        _ = await waitForCondition(timeoutSeconds: 1.5) {
            receivedWidth.get() == 720.0
        }
        #expect(receivedWidth.get() == 720.0)

        // 3. Recreate valid config file
        let validConfig = Config(window: WindowConfig(width: 888, height: 555))
        try JSONEncoder().encode(validConfig).write(to: configFile, options: .atomic)
        let validSatisfied = await waitForCondition(timeoutSeconds: 2.0) {
            receivedWidth.get() == 888.0
        }

        #expect(validSatisfied)
        #expect(receivedWidth.get() == 888.0)
        watcher.stopWatching()
    }

    // MARK: - 4. Resilient Shortcut Decoding Adversarial Tests

    @Test("Adversarial: SafeShortcutDecoder survives hostile and corrupted shortcut payloads")
    func test_adversarial_safeShortcutDecoderHostilePayloads() throws {
        let corruptedJson = """
        {
            "window": { "width": 800 },
            "shortcuts": [
                {
                    "id": "valid.1",
                    "key": "k",
                    "modifiers": ["cmd"],
                    "mode": "background",
                    "action": { "type": "quickLink", "target": "https://apple.com" }
                },
                {
                    "id": "corrupted.missing.key",
                    "mode": "palette",
                    "action": { "type": "toggleWindow", "target": "" }
                },
                {
                    "id": "corrupted.invalid.mode",
                    "key": "j",
                    "modifiers": ["opt"],
                    "mode": "INVALID_SUPER_MODE_1234",
                    "action": { "type": "toggleWindow", "target": "" }
                },
                {
                    "id": "corrupted.invalid.action.type",
                    "key": "l",
                    "modifiers": ["ctrl"],
                    "mode": "background",
                    "action": { "type": "DELETE_ALL_DATA_ACTION", "target": "" }
                },
                {
                    "id": "valid.2",
                    "shortcut": "cmd+shift+p",
                    "mode": "palette",
                    "action": {
                        "type": "pluginCommand",
                        "plugin_id": "titik.builtin.zen",
                        "args": ["--profile", "work", "--new-tab"]
                    }
                },
                {
                    "id": "corrupted.null.action",
                    "key": "m",
                    "modifiers": ["cmd"],
                    "action": null
                }
            ]
        }
        """

        let data = corruptedJson.data(using: .utf8)!
        let config = try JSONDecoder().decode(Config.self, from: data)

        // Only the 2 valid shortcuts must survive
        #expect(config.shortcuts.count == 2)
        #expect(config.shortcuts.map(\.id).contains("valid.1"))
        #expect(config.shortcuts.map(\.id).contains("valid.2"))

        let valid2 = config.shortcuts.first(where: { $0.id == "valid.2" })
        #expect(valid2?.key == "p")
        #expect(valid2?.modifiers == ["cmd", "shift"])
        #expect(valid2?.action.type == .pluginCommand)
        #expect(valid2?.action.target == "titik.builtin.zen")
        #expect(valid2?.action.arguments?["args"] == "--profile work --new-tab")
    }

    @Test("Adversarial: KeyCombination string parser handles formatting variants and glyphs")
    func test_adversarial_keyCombinationStringParserTorture() {
        let testCases: [(input: String, expectedKey: Keycode?, expectedMods: [KeyModifier])] = [
            ("cmd+shift+k", .k, [.command, .shift]),
            ("cmd-shift-k", .k, [.command, .shift]),
            ("CMD+SHIFT+K", .k, [.command, .shift]),
            ("CMD-SHIFT-K", .k, [.command, .shift]),
            ("cmd + shift + k", .k, [.command, .shift]),
            ("cmd+cmd+cmd+k", .k, [.command]), // Deduplication
            ("ctrl+opt+cmd+space", .space, [.control, .option, .command]),
            ("ctrl-opt-cmd-space", .space, [.control, .option, .command]),
            ("⌘+⌥+⇧+return", .returnKey, [.command, .option, .shift]),
            ("opt+f1", .f1, [.option]),
            ("opt-f1", .f1, [.option]),
            ("cmd+escape", .escape, [.command]),
            ("cmd-escape", .escape, [.command])
        ]

        for test in testCases {
            let combo = KeyCombination(string: test.input)
            #expect(combo != nil, "Failed to parse: \(test.input)")
            #expect(combo?.key == test.expectedKey)
            for mod in test.expectedMods {
                #expect(combo?.modifiers.contains(mod) == true, "Missing modifier \(mod) in \(test.input)")
            }
        }

        // Test ShortcutConfig parser for hyphenated strings
        let (parsedKey, parsedMods) = ShortcutConfig.parseKeyCombinationString("cmd-shift-k")
        #expect(parsedKey == "k")
        #expect(Set(parsedMods) == Set(["cmd", "shift"]))
    }

    // MARK: - 5. PluginCommandDispatcher Boundary & Failure Modes

    @Test("Adversarial: Dispatcher handles missing plugin, missing command, and huge argument values")
    func test_adversarial_dispatcherMissingPluginAndHugeArgs() async {
        let dispatcher = PluginCommandDispatcher.shared

        // 1. Target plugin does not exist
        let nonExistentResult = await dispatcher.dispatch(
            action: ShortcutActionConfig(type: .pluginCommand, target: "com.nonexistent.fake.plugin"),
            mode: .background
        )
        #expect(nonExistentResult.isSuccess == false)
        #expect(nonExistentResult.message?.contains("not found") == true)

        // 2. Huge string argument payload (50,000 chars)
        let hugeArg = String(repeating: "A", count: 50_000)
        let quickLinkResult = await dispatcher.dispatch(
            action: ShortcutActionConfig(type: .quickLink, target: "https://example.com/search?q=\(hugeArg)"),
            mode: .background
        )
        #expect(quickLinkResult.isSuccess == true)

        // 3. Bang query with empty / whitespace query
        let emptyQuery = await dispatcher.dispatch(query: "   \t\n   ", mode: .background)
        #expect(emptyQuery.isSuccess == false)
        #expect(emptyQuery.message == "Empty query")
    }

    @Test("Adversarial: Bang query parser with multiple flags, equal signs, and quote combinations")
    func test_adversarial_bangQueryArgumentParsingVariants() async {
        let dispatcher = PluginCommandDispatcher.shared

        // Test Zen browser bang query with complex flag syntax
        let query = "!zen -new-tab -P=Work \"https://apple.com/macbook-pro\""
        let result = await dispatcher.dispatch(query: query, mode: .background)

        #expect(result.isSuccess == true)
    }

    // MARK: - Helper

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

// MARK: - Concurrency Test Helpers

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

private final class AtomicDoubleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Double = 0.0

    func set(_ val: Double) {
        lock.lock()
        defer { lock.unlock() }
        _value = val
    }

    func get() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
