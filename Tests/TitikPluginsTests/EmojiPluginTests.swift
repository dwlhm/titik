import Foundation
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins
import class TitikUI.ToastManager

@Suite("EmojiPlugin Tests", .serialized)
struct EmojiPluginTests {

    func makePlugin() -> EmojiPlugin {
        EmojiPlugin(context: PluginContext(pluginId: EmojiPlugin.id))
    }

    @Test("onQuery with empty query returns first 50 emojis")
    func test_onQuery_emptyQuery_returnsPrefix50() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count == 50)
        #expect(items.first?.id.hasPrefix("emoji:") == true)
        #expect(items.first?.category == "Emoji")
        #expect(items.first?.scoreBoost == 500)
    }

    @Test("onQuery with search term returns matching items")
    func test_onQuery_searchTerm_returnsMatches() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("fire")
        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(!items.isEmpty)
        #expect(items.contains { $0.actionPayload == "🔥" })
        if let fire = items.first(where: { $0.actionPayload == "🔥" }) {
            #expect(fire.id == "emoji:🔥")
            #expect(fire.title.contains("🔥"))
            #expect(fire.subtitle.contains(":fire:"))
            #expect(fire.category == "Emoji")
            #expect(fire.scoreBoost == 500)
            #expect(fire.pluginId == EmojiPlugin.id)
        }
    }

    @Test("Manifest triggers contain canonical triggers")
    func test_manifest_triggers() {
        #expect(emojiPluginManifest.id == "titik.builtin.emoji")
        #expect(emojiPluginManifest.triggers.contains("emoji"))
        #expect(emojiPluginManifest.triggers.contains("e"))
        #expect(emojiPluginManifest.normalizedBangs.contains("emoji"))
    }

    @Test("PluginManager.reindex() registers built-in plugins by default")
    func test_reindex_registersBuiltinsByDefault() {
        let host = PluginHost()
        defer { host.shutdownAll() }
        let loader = ConfigLoader(config: Config())
        let manager = PluginManager(host: host, configLoader: loader)

        manager.reindex()

        #expect(host.getNativePlugin(id: EmojiPlugin.id) != nil)
        #expect(host.getNativePlugin(id: PluginSystemPlugin.id) != nil)
        #expect(host.allNativePlugins().count == BuiltinPluginRegistry.all.count)
    }

    @Test("Disabling titik.builtin.emoji in config unloads the plugin")
    func test_reindex_disablingBuiltinEmoji_unloadsPlugin() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        // Start enabled
        let configEnabled = Config(plugins: PluginsConfig(registrations: [
            "titik.system.plugin": true,
            "titik.builtin.emoji": true
        ]))
        let loader = ConfigLoader(config: configEnabled)
        let manager = PluginManager(host: host, configLoader: loader)

        manager.reindex()
        #expect(host.getNativePlugin(id: EmojiPlugin.id) != nil)

        // Disable emoji plugin
        let configDisabled = Config(plugins: PluginsConfig(registrations: [
            "titik.system.plugin": true,
            "titik.builtin.emoji": false
        ]))
        loader.currentConfig = configDisabled

        manager.reindex()
        #expect(host.getNativePlugin(id: EmojiPlugin.id) == nil)
        #expect(host.getNativePlugin(id: PluginSystemPlugin.id) != nil)
    }

    @Test("PluginContext showToast and dismissToast delegate to ToastManager")
    @MainActor
    func test_pluginContext_toast() {
        let context = PluginContext(pluginId: "test.toast")
        ToastManager.shared.dismiss()
        #expect(ToastManager.shared.currentToast == nil)

        context.showToast(message: "Emoji copied!", icon: "sparkles", type: .success, duration: 2.0)
        #expect(ToastManager.shared.currentToast != nil)
        #expect(ToastManager.shared.currentToast?.message == "Emoji copied!")
        #expect(ToastManager.shared.currentToast?.icon == "sparkles")
        #expect(ToastManager.shared.currentToast?.type == .success)

        context.dismissToast()
        #expect(ToastManager.shared.currentToast == nil)
    }
}
