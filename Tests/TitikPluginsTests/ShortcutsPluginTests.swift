import AppKit
import Combine
import Foundation
import Testing

@testable import TitikCore
@testable import TitikKeymap
@testable import TitikPluginKit
@testable import TitikPlugins

@Suite("ShortcutsPlugin Unit & Integration Tests", .serialized)
struct ShortcutsPluginTests {

    func makePlugin(
        registry: KeymapRegistry = .shared,
        manager: HotkeyManager = .shared,
        shortcutManager: ShortcutManager? = nil
    ) -> ShortcutsPlugin {
        ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry,
            hotkeyManager: manager,
            shortcutManager: shortcutManager
        )
    }

    // MARK: - Manifest & Commands

    @Test("Manifest metadata matches specification")
    func testManifestMetadata() {
        #expect(shortcutsPluginManifest.id == "titik.builtin.shortcuts")
        #expect(shortcutsPluginManifest.name == "Shortcuts Inspector")
        #expect(shortcutsPluginManifest.triggers.contains("keys") || shortcutsPluginManifest.triggers.contains("shortcut"))
        #expect(shortcutsPluginManifest.normalizedBangs.contains("keys") || shortcutsPluginManifest.normalizedBangs.contains("shortcut"))
        #expect(shortcutsPluginManifest.permissions.contains("keymap:read"))
    }

    @Test("Plugin declares list-shortcuts, trigger-shortcut, inspect-conflicts, and reload-shortcuts commands")
    func testDeclaredCommands() {
        let plugin = makePlugin()
        let commandIds = plugin.commands.map(\.id)

        #expect(commandIds.contains("list-shortcuts"))
        #expect(commandIds.contains("trigger-shortcut"))
        #expect(commandIds.contains("inspect-conflicts"))
        #expect(commandIds.contains("reload-shortcuts"))
    }

    @Test("reload-shortcuts executes successfully")
    @MainActor
    func testReloadShortcutsCommand() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let sm = ShortcutManager(configLoader: isolatedLoader)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plugin = makePlugin(shortcutManager: sm)
        let context = CommandExecutionContext(trigger: "test", mode: .background)

        let result = try await plugin.executeCommand(
            id: "reload-shortcuts",
            arguments: [:],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["reloaded"] == "true")
    }

    @Test("trigger-shortcut triggers by target query and name")
    @MainActor
    func testTriggerShortcutByTargetOrName() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let sm = ShortcutManager(configLoader: isolatedLoader)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plugin = makePlugin(shortcutManager: sm)
        let context = CommandExecutionContext(trigger: "test", mode: .background)

        let targetBox = StringBox()
        sm.dispatcher = { target in
            targetBox.set(target)
        }

        let sc = ShortcutConfig(
            id: "sc-test-unique",
            name: "Lock Screen",
            shortcut: "ctrl+opt+l",
            action: ShortcutActionConfig(type: .rawQuery, target: "!cmd lock")
        )
        sm.shortcuts = [sc]

        // Trigger by name
        let resName = try await plugin.executeCommand(
            id: "trigger-shortcut",
            arguments: ["identifier": "Lock Screen"],
            context: context
        )
        #expect(resName.isSuccess == true)
        #expect(targetBox.get() == "!cmd lock")

        // Trigger by target
        targetBox.set("")
        let resTarget = try await plugin.executeCommand(
            id: "trigger-shortcut",
            arguments: ["identifier": "!cmd lock"],
            context: context
        )
        #expect(resTarget.isSuccess == true)
        #expect(targetBox.get() == "!cmd lock")
    }

    // MARK: - Command Execution

    @Test("list-shortcuts returns active registrations from registry")
    func testListShortcutsExecution() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+k"))
        let c2 = try #require(KeyCombination(string: "opt+space"))

        try registry.register(combination: c1, identifier: "titik.search", mode: .palette) {}
        try registry.register(combination: c2, identifier: "titik.zen.new_tab", mode: .background) {}

        let plugin = makePlugin(registry: registry)
        let context = CommandExecutionContext(trigger: "test", mode: .palette)

        let result = try await plugin.executeCommand(
            id: "list-shortcuts",
            arguments: [:],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["count"] == "2")
        #expect(result.outputPayload?["shortcuts"]?.contains("titik.search") == true)
        #expect(result.outputPayload?["shortcuts"]?.contains("titik.zen.new_tab") == true)
    }

    @Test("list-shortcuts filters by keyword")
    func testListShortcutsFiltered() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+k"))
        let c2 = try #require(KeyCombination(string: "opt+z"))

        try registry.register(combination: c1, identifier: "titik.search") {}
        try registry.register(combination: c2, identifier: "titik.zen.url") {}

        let plugin = makePlugin(registry: registry)
        let context = CommandExecutionContext(trigger: "test", mode: .palette)

        let result = try await plugin.executeCommand(
            id: "list-shortcuts",
            arguments: ["filter": "zen"],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["count"] == "1")
        #expect(result.outputPayload?["shortcuts"]?.contains("titik.zen.url") == true)
    }

    @Test("trigger-shortcut executes registered action")
    func testTriggerShortcut() async throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+1"))

        let invokedBox = BooleanBox()
        try registry.register(combination: combo, identifier: "test.action.trigger") {
            invokedBox.set(true)
        }

        let plugin = makePlugin(registry: registry)
        let context = CommandExecutionContext(trigger: "test", mode: .background)

        let result = try await plugin.executeCommand(
            id: "trigger-shortcut",
            arguments: ["identifier": "test.action.trigger"],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(invokedBox.get() == true)
    }

    @Test("trigger-shortcut for non-existent shortcut returns failure")
    func testTriggerNonExistent() async throws {
        let registry = KeymapRegistry()
        let plugin = makePlugin(registry: registry)
        let context = CommandExecutionContext(trigger: "test", mode: .background)

        let result = try await plugin.executeCommand(
            id: "trigger-shortcut",
            arguments: ["identifier": "nonexistent.shortcut.id"],
            context: context
        )

        #expect(result.isSuccess == false)
        #expect(result.message?.contains("not found") == true)
    }

    @Test("inspect-conflicts verifies absence of hotkey conflicts")
    func testInspectConflicts() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+k"))
        let c2 = try #require(KeyCombination(string: "opt+space"))

        try registry.register(combination: c1, identifier: "titik.search") {}
        try registry.register(combination: c2, identifier: "titik.toggle") {}

        let plugin = makePlugin(registry: registry)
        let context = CommandExecutionContext(trigger: "test", mode: .palette)

        let result = try await plugin.executeCommand(
            id: "inspect-conflicts",
            arguments: [:],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["conflicts"] == "0")
        #expect(result.outputPayload?["total"] == "2")
    }

    // MARK: - Query / Canvas Streaming

    @Test("onQuery returns formatted plugin items with mode badge")
    func testOnQuery() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+shift+k"))
        let c2 = try #require(KeyCombination(string: "ctrl+opt+t"))

        try registry.register(combination: c1, identifier: "titik.search", mode: .palette) {}
        try registry.register(combination: c2, identifier: "titik.term", mode: .background) {}

        let plugin = makePlugin(registry: registry)
        let canvas = try await plugin.onQuery("")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count == 2)
        #expect(items.contains { $0.subtitle.contains("[palette]") })
        #expect(items.contains { $0.subtitle.contains("[bg]") })
        #expect(items.contains { $0.title.contains(c1.description) })
        #expect(items.contains { $0.title.contains(c2.description) })
    }

    @Test("onQuery strips leading subcommand aliases cleanly")
    func testOnQueryWithSubcommandAlias() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+shift+k"))
        let c2 = try #require(KeyCombination(string: "ctrl+opt+t"))

        try registry.register(combination: c1, identifier: "titik.search", mode: .palette) {}
        try registry.register(combination: c2, identifier: "titik.term", mode: .background) {}

        let plugin = makePlugin(registry: registry)

        for alias in ["list-shortcuts", "list", "all"] {
            let canvas = try await plugin.onQuery(alias)
            guard case .list(let items) = canvas else {
                #expect(Bool(false), "Expected .list canvas for alias \(alias)")
                continue
            }
            #expect(items.count == 2)
        }
    }

    @Test("onQuery strips subcommand alias and filters by remaining term")
    func testOnQueryWithSubcommandAliasAndFilter() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+shift+k"))
        let c2 = try #require(KeyCombination(string: "ctrl+opt+t"))

        try registry.register(combination: c1, identifier: "titik.search", mode: .palette) {}
        try registry.register(combination: c2, identifier: "titik.term", mode: .background) {}

        let plugin = makePlugin(registry: registry)
        let canvas = try await plugin.onQuery("list-shortcuts term")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count == 1)
        #expect(items.first?.actionPayload == "titik.term")
    }

    // MARK: - Dynamic Recommendations & Editor State

    @Test("testViewModelDefaultRecommendationsOnBang: empty and '!' return defaults")
    @MainActor
    func testViewModelDefaultRecommendationsOnBang() {
        let vm = ShortcutsPluginViewModel()
        vm.formCommand = ""
        #expect(!vm.activeRecommendations.isEmpty)
        let emptyExamples = vm.activeRecommendations.map(\.example)
        #expect(emptyExamples.contains("!app"))
        #expect(emptyExamples.contains(where: { $0.contains("!cmd") }))

        vm.formCommand = "!"
        #expect(!vm.activeRecommendations.isEmpty)
        let bangExamples = vm.activeRecommendations.map(\.example)
        #expect(bangExamples.contains("!app"))
        #expect(bangExamples.contains(where: { $0.contains("!zen") }))
        #expect(bangExamples.contains(where: { $0.contains("!file") }))
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName != nil })
    }

    private func resetPluginHostWithBuiltins() {
        PluginHost.shared.shutdownAll()
        for entry in BuiltinPluginRegistry.all {
            let plugin = entry.factory(PluginContext(pluginId: entry.id))
            PluginHost.shared.registerNativePlugin(plugin, manifest: entry.manifest)
        }
        let zen = ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))
        PluginHost.shared.registerNativePlugin(zen, manifest: zenBrowserPluginManifest)
    }

    @MainActor
    private func waitUntil(timeoutNanoseconds: UInt64 = 1_000_000_000, condition: @MainActor () -> Bool) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                break
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    @Test("testViewModelAppRecommendationsWithPrefix: prefix and word boundaries")
    @MainActor
    func testViewModelAppRecommendationsWithPrefix() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        vm.formCommand = "!app"
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "app.badge" })

        vm.formCommand = "!app "
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.example.hasPrefix("!app") })
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "app.badge" })

        vm.formCommand = "app "
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.example.hasPrefix("!app") })

        // Word boundary enforcement: "!apple" should not match !app prefix branch
        vm.formCommand = "!apple"
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.activeRecommendations.allSatisfy { !$0.example.hasPrefix("!app ") })
    }

    @Test("testViewModelCommandRecommendations: '!cmd ' returns system commands")
    @MainActor
    func testViewModelCommandRecommendations() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        vm.formCommand = "!cmd"
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "gearshape.fill" })

        vm.formCommand = "!cmd "
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.activeRecommendations.isEmpty)
        let examples = vm.activeRecommendations.map(\.example)
        #expect(examples.contains(where: { $0.contains("lock") }))
        #expect(examples.contains(where: { $0.contains("sleep") }))
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "gearshape.fill" })

        vm.formCommand = "!cmd lock"
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.activeRecommendations.contains(where: { $0.example.contains("lock") }))

        // Word boundary enforcement: "!cmdline" should not match !cmd prefix branch
        vm.formCommand = "!cmdline"
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.activeRecommendations.allSatisfy { !$0.example.hasPrefix("!cmd ") })
    }

    @Test("testViewModelZenRecommendations: '!zen ' returns Zen subcommands")
    @MainActor
    func testViewModelZenRecommendations() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        vm.formCommand = "!zen"
        try await waitUntil {
            !vm.activeRecommendations.isEmpty && vm.activeRecommendations.allSatisfy { $0.iconName == "globe" }
        }
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "globe" })

        vm.formCommand = "!zen "
        try await waitUntil {
            !vm.activeRecommendations.isEmpty && vm.activeRecommendations.contains(where: { $0.example.contains("new-tab") })
                && vm.activeRecommendations.contains(where: { $0.example.contains("new-window") })
                && vm.activeRecommendations.allSatisfy { $0.iconName == "globe" }
        }
        #expect(!vm.activeRecommendations.isEmpty)
        let examples = vm.activeRecommendations.map(\.example)
        #expect(examples.contains(where: { $0.contains("new-tab") }))
        #expect(examples.contains(where: { $0.contains("new-window") }))
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "globe" })

        vm.formCommand = "!zen example.com"
        try await waitUntil {
            vm.activeRecommendations.contains(where: { $0.example.contains("example.com") })
        }
        #expect(vm.activeRecommendations.contains(where: { $0.example.contains("example.com") }))

        // Word boundary enforcement: "!zenith" should not match !zen prefix branch
        vm.formCommand = "!zenith"
        try await waitUntil {
            vm.activeRecommendations.allSatisfy { !$0.example.hasPrefix("!zen ") }
        }
        #expect(vm.activeRecommendations.allSatisfy { !$0.example.hasPrefix("!zen ") })
    }

    @Test("testViewModelFileRecommendations: '!file ' returns filesystem targets")
    @MainActor
    func testViewModelFileRecommendations() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        vm.formCommand = "!file"
        try await waitUntil {
            !vm.activeRecommendations.isEmpty && vm.activeRecommendations.allSatisfy { $0.iconName == "folder.fill" }
        }
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "folder.fill" })

        vm.formCommand = "!file "
        try await waitUntil {
            !vm.activeRecommendations.isEmpty && vm.activeRecommendations.allSatisfy { $0.iconName == "folder.fill" }
        }
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "folder.fill" })

        vm.formCommand = "!file ~"
        try await waitUntil {
            !vm.activeRecommendations.isEmpty && vm.activeRecommendations.allSatisfy { $0.iconName == "folder.fill" }
        }
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.allSatisfy { $0.iconName == "folder.fill" })

        // Word boundary enforcement: "!filename" should not match !file prefix branch
        vm.formCommand = "!filename"
        try await waitUntil {
            vm.activeRecommendations.allSatisfy { !$0.example.hasPrefix("!file ") }
        }
        #expect(vm.activeRecommendations.allSatisfy { !$0.example.hasPrefix("!file ") })
    }

    @Test("testViewModelPlainTextRecommendations: plain text search")
    @MainActor
    func testViewModelPlainTextRecommendations() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        vm.formCommand = "safari"
        try await waitUntil {
            !vm.activeRecommendations.isEmpty
                && vm.activeRecommendations.contains(where: { $0.title.localizedCaseInsensitiveContains("Safari") })
        }
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(vm.activeRecommendations.contains(where: { $0.title.localizedCaseInsensitiveContains("Safari") }))

        vm.formCommand = "lock"
        try await waitUntil {
            !vm.activeRecommendations.isEmpty
                && vm.activeRecommendations.contains(where: {
                    $0.title.localizedCaseInsensitiveContains("Lock") || $0.example.contains("lock")
                })
        }
        #expect(!vm.activeRecommendations.isEmpty)
        #expect(
            vm.activeRecommendations.contains(where: {
                $0.title.localizedCaseInsensitiveContains("Lock") || $0.example.contains("lock")
            }))
    }

    @Test("testViewModelApplyRecommendation: updates formCommand and formName")
    @MainActor
    func testViewModelApplyRecommendation() {
        let vm = ShortcutsPluginViewModel()
        let rec = BangRecommendation(
            id: "test-rec",
            bang: "!zen new-tab",
            title: "New Tab",
            description: "Open a new browser tab",
            example: "!zen new-tab",
            iconName: "globe"
        )
        vm.applyRecommendation(rec)
        #expect(vm.formCommand == "!zen new-tab")
        #expect(vm.formName == "New Tab")
        #expect(!vm.activeRecommendations.isEmpty)
    }

    @Test("testViewModelSearchBridgeIntegration: debounced and merged")
    @MainActor
    func testViewModelSearchBridgeIntegration() async throws {
        let bridgeCalledBox = BooleanBox()
        defer {
            ShortcutsPluginViewModel.searchBridge = nil
        }

        ShortcutsPluginViewModel.searchBridge = { query in
            bridgeCalledBox.set(true)
            return [
                BangRecommendation(
                    id: "bridge-item",
                    bang: "!bridge",
                    title: "Bridge Result",
                    description: "From bridge for \(query)",
                    example: "!bridge \(query)",
                    iconName: "network"
                )
            ]
        }

        let vm = ShortcutsPluginViewModel()

        // Type "query1" and immediately change to "query2" to test debouncing/cancellation
        vm.formCommand = "query1"
        vm.formCommand = "query2"

        // Immediately after keystroke, bridge has not fired yet due to 150ms debounce
        #expect(vm.activeRecommendations.allSatisfy { $0.id != "bridge-item" })

        // Wait for debounce (150ms) to complete
        for _ in 0..<20 {
            if vm.activeRecommendations.contains(where: { $0.id == "bridge-item" }) {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(bridgeCalledBox.get() == true)
        #expect(vm.activeRecommendations.contains(where: { $0.id == "bridge-item" }))
        #expect(vm.activeRecommendations.contains(where: { $0.example == "!bridge query2" }))
        // query1 should have been cancelled / never applied
        #expect(!vm.activeRecommendations.contains(where: { $0.example == "!bridge query1" }))

        // Trigger update again to verify no duplicate additions
        vm.updateRecommendations(for: "query2")
        try await Task.sleep(nanoseconds: 250_000_000)

        let matchingItems = vm.activeRecommendations.filter { $0.id == "bridge-item" }
        #expect(matchingItems.count == 1)
    }

    private func makeKeyEvent(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
    }

    // MARK: - Form Focus & Keyboard Navigation Tests

    @Test("testFormInitialFocusIsCommand: startCreate and startEdit reset focus to .command and index to 0")
    @MainActor
    func testFormInitialFocusIsCommand() {
        let vm = ShortcutsPluginViewModel()
        vm.formFocusedField = .cancelButton
        vm.selectedRecommendationIndex = 3

        vm.startCreate()
        #expect(vm.formFocusedField == .command)
        #expect(vm.selectedRecommendationIndex == 0)
        #expect(vm.page == .create)

        vm.formFocusedField = .saveButton
        vm.selectedRecommendationIndex = 2
        let sc = ShortcutConfig(
            id: "test-sc",
            name: "Test",
            shortcut: "cmd+shift+t",
            action: ShortcutActionConfig(type: .rawQuery, target: "!zen")
        )
        vm.startEdit(shortcut: sc)
        #expect(vm.formFocusedField == .command)
        #expect(vm.selectedRecommendationIndex == 0)
        if case .edit(let editSc) = vm.page {
            #expect(editSc.id == "test-sc")
        } else {
            Issue.record("Expected page to be .edit")
        }
    }

    @Test("testFormTabNavigationLoop: nextFormField and previousFormField cycle through all fields")
    @MainActor
    func testFormTabNavigationLoop() {
        let vm = ShortcutsPluginViewModel()
        vm.startCreate()
        #expect(vm.formFocusedField == .command)

        // Forward tab loop: command -> name -> keyString -> recordButton -> saveButton -> cancelButton -> command
        vm.nextFormField()
        #expect(vm.formFocusedField == .name)
        vm.nextFormField()
        #expect(vm.formFocusedField == .keyString)
        vm.nextFormField()
        #expect(vm.formFocusedField == .recordButton)
        vm.nextFormField()
        #expect(vm.formFocusedField == .saveButton)
        vm.nextFormField()
        #expect(vm.formFocusedField == .cancelButton)
        vm.nextFormField()
        #expect(vm.formFocusedField == .command)

        // Backward tab loop: command -> cancelButton -> saveButton -> recordButton -> keyString -> name -> command
        vm.previousFormField()
        #expect(vm.formFocusedField == .cancelButton)
        vm.previousFormField()
        #expect(vm.formFocusedField == .saveButton)
        vm.previousFormField()
        #expect(vm.formFocusedField == .recordButton)
        vm.previousFormField()
        #expect(vm.formFocusedField == .keyString)
        vm.previousFormField()
        #expect(vm.formFocusedField == .name)
        vm.previousFormField()
        #expect(vm.formFocusedField == .command)
    }

    @Test("testRecommendationNavigationUpDown: up/down navigation and boundary clamping")
    @MainActor
    func testRecommendationNavigationUpDown() {
        let vm = ShortcutsPluginViewModel()
        vm.activeRecommendations = [
            BangRecommendation(id: "1", bang: "!app", title: "App", description: "", example: "!app"),
            BangRecommendation(id: "2", bang: "!zen", title: "Zen", description: "", example: "!zen"),
            BangRecommendation(id: "3", bang: "!file", title: "File", description: "", example: "!file"),
        ]
        vm.selectedRecommendationIndex = 0

        // Going up from 0 should clamp at 0
        vm.selectPreviousRecommendation()
        #expect(vm.selectedRecommendationIndex == 0)

        // Going down advances index
        vm.selectNextRecommendation()
        #expect(vm.selectedRecommendationIndex == 1)
        vm.selectNextRecommendation()
        #expect(vm.selectedRecommendationIndex == 2)

        // Going down beyond the end should clamp at count - 1
        vm.selectNextRecommendation()
        #expect(vm.selectedRecommendationIndex == 2)

        // Going back up
        vm.selectPreviousRecommendation()
        #expect(vm.selectedRecommendationIndex == 1)

        // Empty recommendations handling
        vm.activeRecommendations = []
        #expect(vm.selectedRecommendationIndex == 0)
        vm.selectNextRecommendation()
        #expect(vm.selectedRecommendationIndex == 0)
        vm.selectPreviousRecommendation()
        #expect(vm.selectedRecommendationIndex == 0)
    }

    @Test("testRecommendationEnterInjection: enter in command field injects recommendation")
    @MainActor
    func testRecommendationEnterInjection() {
        let vm = ShortcutsPluginViewModel()
        vm.startCreate()
        let rec1 = BangRecommendation(id: "r1", bang: "!app", title: "App Launcher", description: "Launch apps", example: "!app")
        let rec2 = BangRecommendation(id: "r2", bang: "!zen", title: "Zen Browser", description: "Search tabs", example: "!zen")
        vm.activeRecommendations = [rec1, rec2]
        vm.selectedRecommendationIndex = 1
        vm.formFocusedField = .command

        vm.handleFormEnter()
        #expect(vm.formCommand == "!zen")
        #expect(vm.formName == "Zen Browser")
    }

    @Test("testFormEnterOnButtons: Enter triggers save, cancel, and key recording")
    @MainActor
    func testFormEnterOnButtons() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let sm = ShortcutManager(configLoader: isolatedLoader)
        let uniqueKey = "cmd+shift+opt+ctrl+9"
        defer {
            if let combo = KeyCombination(string: uniqueKey) {
                HotkeyManager.shared.unregister(combination: combo)
            }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let vm = ShortcutsPluginViewModel(manager: sm)
        vm.startCreate()

        // 1. Record button toggles listening
        vm.formFocusedField = .recordButton
        #expect(vm.isListeningForKey == false)
        vm.handleFormEnter()
        #expect(vm.isListeningForKey == true)
        vm.handleFormEnter()
        #expect(vm.isListeningForKey == false)

        // 2. Cancel button cancels form
        vm.formFocusedField = .cancelButton
        vm.handleFormEnter()
        #expect(vm.page == .list)

        // 3. Save button saves form
        vm.startCreate()
        vm.formCommand = "!cmd lock"
        vm.formName = "Lock"
        vm.updateFormKeyString(uniqueKey)
        vm.formFocusedField = .saveButton
        vm.handleFormEnter()
        // ShortcutManager should have received the add, returning page to .list
        #expect(vm.duplicateWarning == nil)
        #expect(vm.page == .list)
    }

    @Test("testFormKeymapRegistration: form mode registers tab, arrows, enter, esc")
    @MainActor
    func testFormKeymapRegistration() {
        let vm = ShortcutsPluginViewModel()
        vm.startCreate()

        let recs = [
            BangRecommendation(id: "1", bang: "!app", title: "App", description: "", example: "!app"),
            BangRecommendation(id: "2", bang: "!zen", title: "Zen", description: "", example: "!zen"),
        ]
        vm.activeRecommendations = recs
        vm.selectedRecommendationIndex = 0
        vm.formFocusedField = .command

        // Down arrow via keymap trigger
        let downEvent = makeKeyEvent(keyCode: Keycode.downArrow.rawValue)!
        let handledDown = vm.keymapScope.trigger(event: downEvent)
        #expect(handledDown == true)
        #expect(vm.selectedRecommendationIndex == 1)

        // Up arrow via keymap trigger
        let upEvent = makeKeyEvent(keyCode: Keycode.upArrow.rawValue)!
        let handledUp = vm.keymapScope.trigger(event: upEvent)
        #expect(handledUp == true)
        #expect(vm.selectedRecommendationIndex == 0)

        // Arrow keys should be ignored when focus is not on .command
        vm.formFocusedField = .name
        _ = vm.keymapScope.trigger(event: downEvent)
        #expect(vm.selectedRecommendationIndex == 0)

        // Tab via keymap trigger
        let tabEvent = makeKeyEvent(keyCode: Keycode.tab.rawValue)!
        let handledTab = vm.keymapScope.trigger(event: tabEvent)
        #expect(handledTab == true)
        #expect(vm.formFocusedField == .keyString)

        // Shift+Tab via keymap trigger
        let shiftTabEvent = makeKeyEvent(keyCode: Keycode.tab.rawValue, modifierFlags: [.shift])!
        let handledShiftTab = vm.keymapScope.trigger(event: shiftTabEvent)
        #expect(handledShiftTab == true)
        #expect(vm.formFocusedField == .name)

        // Esc via keymap trigger
        let escEvent = makeKeyEvent(keyCode: Keycode.escape.rawValue)!
        let handledEsc = vm.keymapScope.trigger(event: escEvent)
        #expect(handledEsc == true)
        #expect(vm.page == .list)
    }

    @Test("testFormFooterKeycaps: footer keycaps contextually update based on focused field")
    @MainActor
    func testFormFooterKeycaps() {
        let vm = ShortcutsPluginViewModel()
        vm.startCreate()
        vm.activeRecommendations = [
            BangRecommendation(id: "1", bang: "!app", title: "App", description: "", example: "!app")
        ]
        vm.formFocusedField = .command
        let commandCaps = vm.footerKeycaps.map(\.label)
        #expect(commandCaps.contains("Select"))
        #expect(commandCaps.contains("Next Field"))

        vm.formFocusedField = .recordButton
        let recordCaps = vm.footerKeycaps.map(\.label)
        #expect(recordCaps.contains("Record"))

        vm.isListeningForKey = true
        let listeningCaps = vm.footerKeycaps.map(\.label)
        #expect(listeningCaps.contains("Stop"))

        vm.formFocusedField = .cancelButton
        let cancelCaps = vm.footerKeycaps.map(\.label)
        #expect(cancelCaps.contains("Cancel"))
    }

    // MARK: - New Shortcuts Tests (⌘N, Sequential Arrow Navigation, Single-Pass Resolution)

    @Test("testListKeymapScopeCmdN: both ⌘N and cmd+n trigger startCreate")
    @MainActor
    func testListKeymapScopeCmdN() {
        let vm = ShortcutsPluginViewModel()
        #expect(vm.page == .list)

        // Trigger via keymap with ⌘N event
        let cmdNEvent = makeKeyEvent(keyCode: Keycode.n.rawValue, modifierFlags: [.command])!
        let handled = vm.keymapScope.trigger(event: cmdNEvent)
        #expect(handled == true)
        #expect(vm.page == .create)

        // Cancel and return to list
        vm.cancelForm()
        #expect(vm.page == .list)

        // Both combination representations must be valid and equal
        let comboCmdN = KeyCombination(string: "cmd+n")
        let comboGlyphN = KeyCombination(string: "⌘N")
        #expect(comboCmdN != nil)
        #expect(comboCmdN == comboGlyphN)

        // Re-trigger
        let handled2 = vm.keymapScope.trigger(event: cmdNEvent)
        #expect(handled2 == true)
        #expect(vm.page == .create)
    }

    @Test("testArrowNavigationSequentialUpdates: arrows smoothly update selectedRecommendationIndex sequentially")
    @MainActor
    func testArrowNavigationSequentialUpdates() {
        let vm = ShortcutsPluginViewModel()
        vm.startCreate()
        vm.activeRecommendations = [
            BangRecommendation(id: "1", bang: "!app", title: "App 1", description: "", example: "!app 1"),
            BangRecommendation(id: "2", bang: "!app", title: "App 2", description: "", example: "!app 2"),
            BangRecommendation(id: "3", bang: "!app", title: "App 3", description: "", example: "!app 3"),
            BangRecommendation(id: "4", bang: "!app", title: "App 4", description: "", example: "!app 4"),
        ]
        vm.selectedRecommendationIndex = 0
        vm.formFocusedField = .command

        let downEvent = makeKeyEvent(keyCode: Keycode.downArrow.rawValue)!
        let upEvent = makeKeyEvent(keyCode: Keycode.upArrow.rawValue)!

        // Downward sequential movement
        for expected in 1...3 {
            let handled = vm.keymapScope.trigger(event: downEvent)
            #expect(handled == true)
            #expect(vm.selectedRecommendationIndex == expected)
        }

        // Clamp at bottom
        _ = vm.keymapScope.trigger(event: downEvent)
        #expect(vm.selectedRecommendationIndex == 3)

        // Upward sequential movement
        for expected in (0...2).reversed() {
            let handled = vm.keymapScope.trigger(event: upEvent)
            #expect(handled == true)
            #expect(vm.selectedRecommendationIndex == expected)
        }

        // Clamp at top
        _ = vm.keymapScope.trigger(event: upEvent)
        #expect(vm.selectedRecommendationIndex == 0)
    }

    @Test("testSinglePassAtomicRecommendationsResolution: single-pass atomic recommendations resolution without flicker")
    @MainActor
    func testSinglePassAtomicRecommendationsResolution() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        var updateCount = 0
        let cancellable = vm.$activeRecommendations.dropFirst().sink { _ in
            updateCount += 1
        }
        defer { cancellable.cancel() }

        ShortcutsPluginViewModel.searchBridge = { query in
            [
                BangRecommendation(
                    id: "bridge-item",
                    bang: "!bridge",
                    title: "Bridge",
                    description: "Bridge desc",
                    example: "!bridge"
                )
            ]
        }
        defer { ShortcutsPluginViewModel.searchBridge = nil }

        vm.formCommand = "!cmd"
        try await Task.sleep(nanoseconds: 300_000_000)

        // Active recommendations should contain both internal and bridge results
        #expect(vm.activeRecommendations.contains(where: { $0.id == "bridge-item" }))
        #expect(vm.activeRecommendations.contains(where: { $0.bang == "!cmd" }))

        // Exactly one publication must happen for the async search task
        #expect(updateCount == 1)

        // Deduplication test: duplicate ID and example should not produce duplicate entries
        let currentCount = vm.activeRecommendations.count
        vm.updateRecommendations(for: "!cmd")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.activeRecommendations.count == currentCount)
    }

    @Test("testAppRecommendationsFormatting: clean !app <AppName> and app:<name> id")
    @MainActor
    func testAppRecommendationsFormatting() async throws {
        resetPluginHostWithBuiltins()
        let vm = ShortcutsPluginViewModel()

        vm.formCommand = "!app"
        try await Task.sleep(nanoseconds: 300_000_000)

        let appRecs = vm.activeRecommendations.filter { $0.bang == "!app" }
        #expect(!appRecs.isEmpty)
        for rec in appRecs {
            #expect(rec.example.hasPrefix("!app"))
            #expect(!rec.example.contains(".app/"))
            #expect(rec.id.hasPrefix("app:") || rec.id == "app")
        }
    }

    @Test("onActivated and handleSearchQuery do not reset page when in create or edit state")
    @MainActor
    func testFormStatePreservedOnActivatedAndHandleSearchQuery() {
        let plugin = makePlugin()
        let vm = plugin.viewModel

        // 1. In .create state
        vm.startCreate()
        #expect(vm.page == .create)

        plugin.onActivated()
        #expect(vm.page == .create)

        plugin.handleSearchQuery("test query")
        #expect(vm.page == .create)
        #expect(vm.filterQuery != "test query")

        // 2. In .edit state
        let sampleShortcut = ShortcutConfig(
            id: "sc-edit-preserve",
            name: "Test Edit",
            shortcut: "cmd+shift+e",
            action: ShortcutActionConfig(type: .rawQuery, target: "!test")
        )
        vm.startEdit(shortcut: sampleShortcut)
        #expect(vm.page == .edit(sampleShortcut))

        plugin.onActivated()
        #expect(vm.page == .edit(sampleShortcut))

        plugin.handleSearchQuery("another query")
        #expect(vm.page == .edit(sampleShortcut))
        #expect(vm.filterQuery != "another query")

        // 3. When returned to .list state, onActivated and handleSearchQuery function normally
        vm.cancelForm()
        #expect(vm.page == .list)

        plugin.handleSearchQuery("list filter")
        #expect(vm.filterQuery == "list filter")

        plugin.onActivated()
        #expect(vm.page == .list)
        #expect(vm.filterQuery == "")
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

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""

    func set(_ v: String) {
        lock.lock()
        defer { lock.unlock() }
        _value = v
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
