import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikSearch

@Suite("SearchEngine Command Plugin Routing Tests")
struct SearchEngineCommandRoutingTests {

    @Test("SearchEngine bang query without arguments lists all plugin subcommands")
    func testBangWithoutArgumentsListsSubcommands() {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.cmd_routing",
            name: "Routing Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Routing test plugin",
            entrypoint: "MockRoutingCommandPlugin",
            triggers: ["route", "rt"]
        )
        let plugin = MockRoutingCommandPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let engine = SearchEngine(pluginHost: host)
        let results = engine.search(query: "!route")

        #expect(results.count == 2)
        #expect(results.contains { $0.id == "titik.test.cmd_routing:create" })
        #expect(results.contains { $0.id == "titik.test.cmd_routing:delete" })
        #expect(results.first?.category == .plugin)
    }

    @Test("SearchEngine bang query with subcommand routes to exact sub-command")
    func testBangWithSubcommand() {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.cmd_routing",
            name: "Routing Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Routing test plugin",
            entrypoint: "MockRoutingCommandPlugin",
            triggers: ["route", "rt"]
        )
        let plugin = MockRoutingCommandPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let engine = SearchEngine(pluginHost: host)
        let results = engine.search(query: "!route create my-resource")

        #expect(results.count == 1)
        #expect(results.first?.id == "titik.test.cmd_routing:create")
        #expect(results.first?.title == "Create Resource")
    }

    @Test("SearchEngine bang query with arguments maps to primary command")
    func testBangWithArgumentsMapsToPrimaryCommand() {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.cmd_routing",
            name: "Routing Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Routing test plugin",
            entrypoint: "MockRoutingCommandPlugin",
            triggers: ["route", "rt"]
        )
        let plugin = MockRoutingCommandPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let engine = SearchEngine(pluginHost: host)
        let results = engine.search(query: "!route single-arg-value")

        #expect(results.count == 1)
        #expect(results.first?.id == "titik.test.cmd_routing:create")
    }

    @Test("SearchEngine getBangSuggestions includes command plugin triggers and subcommands")
    func testGetBangSuggestionsWithCommandPlugins() {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.cmd_routing",
            name: "Routing Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Routing test plugin",
            entrypoint: "MockRoutingCommandPlugin",
            triggers: ["route", "rt"]
        )
        let plugin = MockRoutingCommandPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let engine = SearchEngine(pluginHost: host)
        let suggestions = engine.getBangSuggestions()

        #expect(suggestions.contains { $0.id.contains("titik.test.cmd_routing") })
        #expect(suggestions.contains { $0.id.contains("create") })
        #expect(suggestions.contains { $0.id.contains("delete") })
    }
    @Test("SearchEngine bang query for shortcuts plugin streams and triggers action")
    func testShortcutsPluginSearchRouting() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "cmd+k"))
        let invokedBox = BooleanBox()
        try registry.register(combination: c1, identifier: "titik.test.shortcut", mode: .palette) {
            invokedBox.set(true)
        }

        let host = PluginHost()
        let plugin = ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry,
            hotkeyManager: HotkeyManager.shared
        )
        host.registerNativePlugin(plugin, manifest: shortcutsPluginManifest)

        let engine = SearchEngine(pluginHost: host)
        let results = engine.search(query: "!shortcut")
        #expect(!results.isEmpty)
        #expect(results.first?.title.contains("titik.test.shortcut") == true)

        let actionResult = results.first?.action()
        #expect(actionResult == true)
        #expect(invokedBox.get() == true)
    }

    @Test("SearchEngine bang query with list-shortcuts alias streams items")
    func testShortcutsPluginWithSubcommandAlias() async throws {
        let registry = KeymapRegistry()
        let c1 = try #require(KeyCombination(string: "opt+z"))
        try registry.register(combination: c1, identifier: "titik.zen.url", mode: .background) {}

        let host = PluginHost()
        let plugin = ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry,
            hotkeyManager: HotkeyManager.shared
        )
        host.registerNativePlugin(plugin, manifest: shortcutsPluginManifest)

        let engine = SearchEngine(pluginHost: host)
        let results = engine.search(query: "!shortcut list-shortcuts")
        #expect(!results.isEmpty)
        #expect(results.first?.title.contains("titik.zen.url") == true)
    }
}

// MARK: - Mock Routing Command Plugin

private final class MockRoutingCommandPlugin: TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    static let id: String = "titik.test.cmd_routing"
    static let name: String = "Routing Test Plugin"
    static let version: String = "1.0.0"

    var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "create",
                name: "Create Resource",
                description: "Creates a new named resource",
                triggers: ["!create", "create"],
                arguments: [
                    PluginCommandArgument(name: "name", description: "Resource name", isRequired: true)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "delete",
                name: "Delete Resource",
                description: "Deletes a named resource",
                triggers: ["!delete", "delete"],
                arguments: [
                    PluginCommandArgument(name: "name", description: "Resource name", isRequired: true)
                ],
                defaultMode: .background
            )
        ]
    }

    init(context: PluginContext) {}

    func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        switch id {
        case "create":
            let name = arguments["name"] ?? "unnamed"
            return CommandExecutionResult.success(message: "Created \(name)")
        case "delete":
            let name = arguments["delete"] ?? "unnamed"
            return CommandExecutionResult.success(message: "Deleted \(name)")
        default:
            return CommandExecutionResult.failure(message: "Unknown command: \(id)")
        }
    }

    func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .list(commands.map { cmd in
                SearchItem(
                    id: "\(Self.id):\(cmd.id)",
                    title: cmd.name,
                    subtitle: cmd.description,
                    category: .plugin,
                    score: 500,
                    actionPayload: "!route \(cmd.id) "
                )
            }.map { item in
                PluginItem(
                    id: item.id.replacingOccurrences(of: "\(Self.id):", with: ""),
                    title: item.title,
                    subtitle: item.subtitle,
                    category: "Plugin",
                    actionPayload: item.actionPayload,
                    scoreBoost: 500,
                    pluginId: Self.id
                )
            })
        }
        let matching = commands.filter {
            $0.id.localizedCaseInsensitiveContains(trimmed) ||
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed)
        }
        if !matching.isEmpty {
            return .list(matching.map { cmd in
                PluginItem(
                    id: cmd.id,
                    title: cmd.name,
                    subtitle: cmd.description,
                    category: "Plugin",
                    actionPayload: "!route \(cmd.id) ",
                    scoreBoost: 600,
                    pluginId: Self.id
                )
            })
        }
        let firstCmd = commands.first!
        return .list([
            PluginItem(
                id: firstCmd.id,
                title: firstCmd.name,
                subtitle: firstCmd.description,
                category: "Plugin",
                actionPayload: "!route \(firstCmd.id) \(trimmed)",
                scoreBoost: 600,
                pluginId: Self.id
            )
        ])
    }

    func cancelActiveStream() async {}
    func onShutdown() {}
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
