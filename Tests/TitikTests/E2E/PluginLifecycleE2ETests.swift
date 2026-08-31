import Foundation
import Testing
import TitikPlugins

@Suite("PluginLifecycle E2E Tests")
struct PluginLifecycleE2ETests {
    @Test("Dynamic plugin full lifecycle")
    func testDynamicPluginFullLifecycle() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let pluginPath = "plugins/math_plugin/math.dylib"
        guard FileManager.default.fileExists(atPath: pluginPath) else {
            return
        }

        // 1. Load plugin & inspect metadata
        let loaded = host.loadPlugin(at: pluginPath)
        #expect(loaded, "Plugin should load successfully")
        let loadedPlugins = host.loadedPlugins()
        #expect(!loadedPlugins.isEmpty)
        let mathDescriptor = loadedPlugins.first { $0.id == "titik.plugin.math" }
        #expect(mathDescriptor != nil)
        #expect(mathDescriptor?.name == "math")
        #expect(mathDescriptor?.shortBang == "calc")

        // 2. Test findActivePlugin
        let activeShort = host.findActivePlugin(forQuery: "!calc 12 * 12")
        #expect(activeShort != nil)
        #expect(activeShort?.descriptor.id == "titik.plugin.math")
        #expect(activeShort?.subquery == "12 * 12")

        let activeName = host.findActivePlugin(forQuery: "!math 12 * 12")
        #expect(activeName != nil)
        #expect(activeName?.descriptor.id == "titik.plugin.math")
        #expect(activeName?.subquery == "12 * 12")

        let exactBang = host.findActivePlugin(forQuery: "!calc")
        #expect(exactBang != nil)
        #expect(exactBang?.subquery == "")

        let noBang = host.findActivePlugin(forQuery: "calc 12 * 12")
        #expect(noBang == nil)

        // 3. Query plugin via queryPlugin
        let pluginItems = host.queryPlugin(id: "titik.plugin.math", subquery: "12 * 12")
        #expect(!pluginItems.isEmpty)
        let result = pluginItems.first!
        #expect(result.title == "144")
        #expect(result.scoreBoost > 0)

        // 4. Execute item action
        let executed = host.executeItem(pluginId: result.pluginId, itemId: result.id, actionPayload: result.actionPayload)
        #expect(executed, "Item execution should succeed")

        // 5. Hot reload check
        host.checkAndReloadModifiedPlugins()

        // 6. Unload plugin
        host.unloadPlugin(id: result.pluginId)
        #expect(host.loadedPlugins().isEmpty)
    }
}
