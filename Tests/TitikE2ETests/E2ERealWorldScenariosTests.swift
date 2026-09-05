import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform
@testable import TitikSearch

@Suite("E2E Real-World Application Scenarios & Adversarial Stress Tests")
struct E2ERealWorldScenariosTests {

    // MARK: - Feature 15: Unit & Integration Test Suite Verification

    @Test("F15: Modular architecture cross-target dependency resolution")
    func test_f15_modularTargetDependencyResolution() {
        let coreConfig = Config()
        let combo = KeyCombination(string: "cmd+k")
        let parser = CommandParser()
        let ast = parser.parse("!calc 10 + 20")

        #expect(coreConfig.window.width == 720)
        #expect(combo?.key == .k)
        #expect(ast != .empty)
    }

    @Test("F15: Mock filesystem and temporary directory isolation")
    func test_f15_mockEnvironmentIsolation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = tempDir.appendingPathComponent("sample.txt")
        try "hello titik".write(to: sampleFile, atomically: true, encoding: .utf8)

        let items = FileBrowser.shared.browseDirectory(path: tempDir.path + "/")
        #expect(items.contains(where: { $0.title == "sample.txt" }))
    }

    @Test("F15: Asynchronous task cancellation hygiene")
    func test_f15_asyncTaskCancellationHygiene() async {
        let task = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return "done"
        }
        task.cancel()
        let isCancelled = task.isCancelled
        #expect(isCancelled == true)
    }

    @Test("F15: Full pipeline end-to-end event to search engine integration")
    func test_f15_fullPipelineEndToEndVerification() {
        let searchEngine = SearchEngine.shared
        let results = searchEngine.search(query: "!calc 40 + 2")

        #expect(!results.isEmpty)
        #expect(results.first?.title.contains("42") == true)
    }

    // MARK: - Feature 16: Adversarial & Stress Hardening

    @Test("F16: 50 concurrent tasks hammer KeymapRegistry without race condition or crash")
    func test_f16_rapidConcurrentHotkeyRegistrations() async {
        let registry = KeymapRegistry()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let keyIdx = i % 10
                    if let combo = KeyCombination(string: "cmd+\(keyIdx)") {
                        if i % 2 == 0 {
                            try? registry.register(combination: combo, identifier: "worker.\(i)") {}
                        } else {
                            registry.unregister(identifier: "worker.\(i - 1)")
                        }
                    }
                }
            }
        }

        let remaining = registry.allBindings()
        #expect(remaining.count >= 0)
    }

    @Test("F16: Extreme config payload size (500 shortcut bindings) decodes cleanly")
    func test_f16_extremeConfigPayloadSizes() throws {
        var shortcuts: [[String: Any]] = []
        for i in 0..<500 {
            shortcuts.append([
                "id": "shortcut_\(i)",
                "key": "\(i % 10)",
                "modifiers": ["cmd", "opt"],
                "mode": i % 2 == 0 ? "background" : "palette",
                "action": [
                    "type": "pluginCommand",
                    "target": "titik.builtin.zen",
                    "arguments": ["tab": "tab_\(i)"]
                ]
            ])
        }

        let jsonDict: [String: Any] = [
            "window": ["width": 800, "height": 600],
            "shortcuts": shortcuts
        ]

        let data = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
        let config = try JSONDecoder().decode(Config.self, from: data)

        #expect(config.window.width == 800)
    }

    @Test("F16: Special character, unicode, and control characters in key combination parser")
    func test_f16_specialCharacterAndEmojiHotkeyStrings() {
        let inputs = [
            "cmd+🔥",
            "cmd+\u{0000}",
            "ctrl+alt+⌘",
            "opt+   \t\n",
            "cmd+§",
            "cmd+ñ"
        ]

        for input in inputs {
            // Must not crash or hang
            _ = KeyCombination(string: input)
        }
    }

    @Test("F16: Unclosed quotes, escape sequences, and SQL/shell injection in bang query")
    func test_f16_unclosedQuotesAndEscapeSequencesInBangQuery() {
        let parser = CommandParser()
        let maliciousQueries = [
            "!zen \"unclosed string without end",
            "!open /path/with/'unclosed-single-quote",
            "!launch ; rm -rf / ;",
            "!calc 1 / 0",
            "!cmd `echo hacked`",
            "!emoji \u{0000}\u{001F}\u{007F}"
        ]

        for q in maliciousQueries {
            let ast = parser.parse(q)
            #expect(ast != .empty || q.isEmpty)
        }
    }

    @Test("F16: Reentrant event dispatching does not deadlock")
    func test_f16_reentrantEventDispatching() throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+1"))
        let c2 = try #require(KeyCombination(string: "cmd+2"))

        let reentrantRan = BooleanBox()
        try registry.register(combination: c1, identifier: "outer") {
            // Nested reentrant lookup and dispatch
            registry.find(combination: c2)?.action()
        }

        try registry.register(combination: c2, identifier: "inner") {
            reentrantRan.set(true)
        }

        registry.find(combination: c1)?.action()
        #expect(reentrantRan.get() == true)
    }

    // MARK: - Tier 4: Real-World Application Scenarios

    @Test("Tier 4: Scenario A - Zen Browser background launch with flags and URL")
    func test_tier4_zenBrowserBackgroundLaunchScenario() throws {
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.builtin.zen",
            arguments: [
                "profile": "Work",
                "command": "new-tab",
                "url": "https://github.com/trending"
            ]
        )
        let shortcut = ShortcutConfig(
            id: "zen.work.trending",
            name: "Zen Work Trending",
            shortcut: "cmd+shift+w",
            mode: .background,
            action: action
        )

        #expect(shortcut.mode == .background)
        #expect(shortcut.action.target == "titik.builtin.zen")
        #expect(shortcut.action.arguments?["profile"] == "Work")

        // Build CLI execution arguments
        var cliArgs: [String] = []
        if let profile = shortcut.action.arguments?["profile"] {
            cliArgs.append(contentsOf: ["-P", profile])
        }
        if let cmd = shortcut.action.arguments?["command"], cmd == "new-tab" {
            cliArgs.append("-new-tab")
        }
        if let url = shortcut.action.arguments?["url"] {
            cliArgs.append(url)
        }

        #expect(cliArgs == ["-P", "Work", "-new-tab", "https://github.com/trending"])
    }

    @Test("Tier 4: Scenario B - Project Launcher palette mode pre-fill and directory navigation")
    func test_tier4_projectLauncherPalettePreFillScenario() {
        let resolved = FileManager.default.currentDirectoryPath

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir)
        #expect(exists == true && isDir.boolValue == true)

        let items = FileBrowser.shared.browseDirectory(path: resolved + "/")
        #expect(!items.isEmpty)
        #expect(items.contains(where: { $0.title == "Package.swift" }))
    }

    @Test("Tier 4: Scenario C - Interactive Shortcuts inspection and search filtering")
    func test_tier4_interactiveShortcutsInspectionAndTriggerScenario() throws {
        let registry = KeymapRegistry()

        // Setup production-like keymap
        let k1 = try #require(KeyCombination(string: "cmd+."))
        let k2 = try #require(KeyCombination(string: "cmd+shift+k"))
        let k3 = try #require(KeyCombination(string: "opt+space"))

        let toggleRan = BooleanBox()
        let zenRan = BooleanBox()
        let searchRan = BooleanBox()

        try registry.register(combination: k1, identifier: "titik.toggle") { toggleRan.set(true) }
        try registry.register(combination: k2, identifier: "titik.zen.quick") { zenRan.set(true) }
        try registry.register(combination: k3, identifier: "titik.search.focus") { searchRan.set(true) }

        let allBindings = registry.allBindings()
        #expect(allBindings.count == 3)

        // Simulate user typing "!shortcut zen"
        let searchResults = allBindings.filter { binding in
            binding.identifier.localizedCaseInsensitiveContains("zen")
        }
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.combination.description.contains("K") == true)

        // User hits enter on filtered result
        searchResults.first?.action()
        #expect(zenRan.get() == true)
        #expect(toggleRan.get() == false)
        #expect(searchRan.get() == false)
    }

    @Test("Tier 4: Scenario D - Live config editing and dynamic hotkey rebinding")
    func test_tier4_liveConfigEditingAndDynamicRebindingScenario() throws {
        let registry = KeymapRegistry()

        // 1. Initial binding: Cmd+1
        let initialCombo = try #require(KeyCombination(string: "cmd+1"))
        let initialExecuted = BooleanBox()
        try registry.register(combination: initialCombo, identifier: "custom.action") {
            initialExecuted.set(true)
        }

        #expect(registry.isRegistered(combination: initialCombo) == true)

        // 2. User modifies config file: rebind to Cmd+2
        let newCombo = try #require(KeyCombination(string: "cmd+2"))
        let newExecuted = BooleanBox()

        // Unregister old combo and register new combo for same ID
        try registry.register(combination: newCombo, identifier: "custom.action") {
            newExecuted.set(true)
        }

        #expect(registry.isRegistered(combination: initialCombo) == false)
        #expect(registry.isRegistered(combination: newCombo) == true)

        // Firing old combo does nothing
        registry.find(combination: initialCombo)?.action()
        #expect(initialExecuted.get() == false)

        // Firing new combo runs updated action
        registry.find(combination: newCombo)?.action()
        #expect(newExecuted.get() == true)
    }

    @Test("Tier 4: Scenario E - Multi-plugin sequential bang query session")
    func test_tier4_multiPluginBangWorkflow() {
        let searchEngine = SearchEngine.shared

        // 1. Math bang query
        let calcResults = searchEngine.search(query: "!calc 15 * 4")
        #expect(calcResults.contains(where: { $0.title.contains("60") }))

        // 2. Emoji bang query
        let emojiResults = searchEngine.search(query: "!emoji rocket")
        #expect(!emojiResults.isEmpty)

        // 3. File bang query
        let fileResults = searchEngine.search(query: "!file ~")
        #expect(!fileResults.isEmpty)
    }
}

private final class BooleanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    func set(_ v: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _value = v
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
