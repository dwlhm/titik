import Foundation
import Testing
@testable import TitikPluginKit
@testable import TitikPlugins

@Suite("PluginSystemPlugin Tests")
struct PluginSystemPluginTests {

    func makePlugin() -> PluginSystemPlugin {
        PluginSystemPlugin(context: PluginContext(pluginId: PluginSystemPlugin.id))
    }

    @Test("onQuery('reload') returns reload item")
    func test_query_reload_returnsReloadItem() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("reload")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].id == "plugin.system.reload")
        #expect(items[0].actionPayload == "reload")
    }

    @Test("onQuery('RELOAD') is case-insensitive")
    func test_query_reloadCaseInsensitive() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("RELOAD")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }
        #expect(items[0].id == "plugin.system.reload")
    }

    @Test("onQuery unknown subcommand returns hint item")
    func test_query_unknown_returnsHintItem() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("unknown")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].id == "plugin.system.hint")
    }

    @Test("onQuery empty string returns hint item")
    func test_query_empty_returnsHintItem() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].id == "plugin.system.hint")
    }
}
