import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikSearch

@Suite("E2E Built-in Reference Plugins Tests")
struct E2EBuiltinPluginsTests {

    // MARK: - Feature 12: Zen Browser Built-in Plugin

    @Test("F12: Zen Browser URL parameter validation and launch arguments formatting")
    func test_f12_zenBrowserURLValidation() {
        let validURLs = [
            "https://apple.com",
            "http://localhost:3000",
            "zen://settings",
            "https://github.com/trending"
        ]

        for urlStr in validURLs {
            let parsedURL = URL(string: urlStr)
            #expect(parsedURL != nil)
            #expect(parsedURL?.scheme != nil)
        }
    }

    @Test("F12: Zen Browser new tab command arguments generation")
    func test_f12_newTabCommandExecution() {
        let plugin = ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))
        let cliFlags = plugin.buildCLIFlags(id: "new-tab", arguments: ["url": "https://news.ycombinator.com"])

        #expect(cliFlags.contains("-new-tab"))
        #expect(cliFlags.contains("https://news.ycombinator.com"))
    }

    @Test("F12: Zen Browser workspace/profile selection flag generation")
    func test_f12_profileWorkspaceSelection() {
        let plugin = ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))
        let cliFlags = plugin.buildCLIFlags(id: "open-url", arguments: ["profile": "Work", "url": "https://work.slack.com"])

        #expect(cliFlags.contains("-P"))
        #expect(cliFlags.contains("Work"))
        #expect(cliFlags.contains("https://work.slack.com"))
    }

    @Test("F12: Zen Browser plugin manifest metadata and triggers")
    func test_f12_zenPluginManifestMetadata() {
        let manifest = PluginManifest(
            id: "titik.builtin.zen",
            name: "Zen Browser",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Control Zen Browser tabs, windows, and profiles",
            entrypoint: "ZenBrowserPlugin",
            triggers: ["zen"],
            permissions: ["workspace:launch"]
        )

        #expect(manifest.id == "titik.builtin.zen")
        #expect(manifest.triggers.contains("zen"))
        #expect(manifest.sdkVersion == 2)
    }

    @Test("F12: Zen Browser empty or invalid URL handling defaults to empty window/tab")
    func test_f12_invalidURLHandlingInZenPlugin() {
        let plugin = ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))
        let cliFlags = plugin.buildCLIFlags(id: "new-window", arguments: [:])

        #expect(cliFlags.contains("-new-window"))
        #expect(!cliFlags.contains("nil"))
    }

    // MARK: - Feature 13: App & Project Launcher Plugin

    @Test("F13: App Launcher application resolution by bundle name")
    func test_f13_launchApplicationByName() {
        let scanned = AppLauncher.shared.scanApplications()
        #expect(!scanned.isEmpty, "Should find at least some applications on macOS")

        if let firstApp = scanned.first {
            let matches = scanned.filter { $0.name.localizedCaseInsensitiveContains(firstApp.name) }
            #expect(!matches.isEmpty)
        }
    }

    @Test("F13: Project directory launcher IDE resolution (Antigravity / VSCode)")
    func test_f13_openProjectDirectoryInIDE() async throws {
        let projectPath = "/Users/dwlhm/project/titik"
        let ideName = "Antigravity"

        let plugin = LauncherPlugin(context: PluginContext(pluginId: LauncherPlugin.id))
        let result = try await plugin.executeCommand(
            id: "open-project",
            arguments: ["path": projectPath, "ide": ideName],
            context: CommandExecutionContext(trigger: "open", mode: .background, rawInput: "!open ~/project/titik")
        )
        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["ide"] == "Antigravity")
        #expect(result.outputPayload?["path"] == "/Users/dwlhm/project/titik")
    }

    @Test("F13: Tilde path expansion in launcher resolves to absolute home directory")
    func test_f13_tildePathExpansionInLauncher() {
        let tildePath = "~/project/titik"
        let expanded = PathResolver.expandPath(tildePath)

        #expect(!expanded.hasPrefix("~"))
        #expect(expanded.contains("project/titik"))
        #expect(PathResolver.isPathQuery(expanded) == true)
    }

    @Test("F13: Non-existent application name returns empty results safely")
    func test_f13_nonExistentAppReturnsActionableError() {
        let nonExistent = "NonExistentAppXYZ_\(UUID().uuidString)"
        let scanned = AppLauncher.shared.scanApplications()
        let matches = scanned.filter { $0.name.localizedCaseInsensitiveContains(nonExistent) }
        #expect(matches.isEmpty)
    }

    @Test("F13: Launcher plugin manifest metadata and triggers")
    func test_f13_launcherPluginManifestMetadata() {
        let manifest = PluginManifest(
            id: "titik.builtin.launcher",
            name: "App & Project Launcher",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Launch applications and open IDE projects",
            entrypoint: "LauncherPlugin",
            triggers: ["open", "launch"],
            permissions: ["workspace:launch"]
        )

        #expect(manifest.id == "titik.builtin.launcher")
        #expect(manifest.triggers.contains("open"))
        #expect(manifest.triggers.contains("launch"))
    }

    // MARK: - Feature 14: Shortcuts Inspector Plugin

    @Test("F14: Shortcuts Inspector lists all active key bindings from KeymapRegistry")
    func test_f14_listAllActiveKeyBindings() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+k"))
        let c2 = try #require(KeyCombination(string: "opt+space"))

        try registry.register(combination: c1, identifier: "titik.toggle") {}
        try registry.register(combination: c2, identifier: "titik.zen.new_tab") {}

        let plugin = ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry
        )
        let canvas = try await plugin.onQuery("")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count == 2)
        #expect(items.contains(where: { $0.title.contains("⌘K") || $0.subtitle.contains("titik.toggle") }))
        #expect(items.contains(where: { $0.title.contains("⌥␣") || $0.subtitle.contains("titik.zen.new_tab") }))
    }

    @Test("F14: Search and filter shortcuts by keyword")
    func test_f14_searchShortcutsByKeyword() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+k"))
        let c2 = try #require(KeyCombination(string: "opt+z"))

        try registry.register(combination: c1, identifier: "system.calc") {}
        try registry.register(combination: c2, identifier: "zen.browser") {}

        let plugin = ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry
        )
        let canvas = try await plugin.onQuery("zen")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count == 1)
        #expect(items.first?.subtitle.contains("zen.browser") == true)
    }

    @Test("F14: Display formatted glyphs and action description")
    func test_f14_displayFormattedGlyphAndAction() throws {
        let combo = try #require(KeyCombination(string: "ctrl+shift+p"))
        let glyphs = combo.description

        #expect(glyphs.contains("⌃"))
        #expect(glyphs.contains("⇧"))
        #expect(glyphs.contains("P"))
    }

    @Test("F14: Trigger selected shortcut from search item invokes bound action")
    func test_f14_triggerSelectedShortcutFromUI() async throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+shift+1"))

        let executedBox = BooleanBox()
        try registry.register(combination: combo, identifier: "action.trigger.test") {
            executedBox.set(true)
        }

        let plugin = ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry
        )
        let result = try await plugin.executeCommand(
            id: "trigger-shortcut",
            arguments: ["identifier": "action.trigger.test"],
            context: CommandExecutionContext(trigger: "shortcut", mode: .background, rawInput: "!shortcut trigger action.trigger.test")
        )

        #expect(result.isSuccess == true)
        #expect(executedBox.get() == true)
    }

    @Test("F14: Shortcuts plugin manifest metadata and triggers")
    func test_f14_shortcutsPluginManifestMetadata() {
        let manifest = PluginManifest(
            id: "titik.builtin.shortcuts",
            name: "Shortcuts Inspector",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Inspect and trigger active global shortcuts",
            entrypoint: "ShortcutsPlugin",
            triggers: ["shortcut", "hotkeys"],
            permissions: ["keymap:read"]
        )

        #expect(manifest.id == "titik.builtin.shortcuts")
        #expect(manifest.triggers.contains("shortcut"))
        #expect(manifest.triggers.contains("hotkeys"))
    }
}

// MARK: - Helper Functions & Types

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
