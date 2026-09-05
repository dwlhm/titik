import Foundation
import Testing
import TitikPlugins
import TitikPluginKit

private final class MockLifecycleE2EPlugin: TitikStreamingPlugin, @unchecked Sendable {
    static let id = "titik.plugin.test"
    static let name = "test"
    static let version = "1.0.0"
    static let sdkVersion = 2

    let context: PluginContext
    init(context: PluginContext) {
        self.context = context
    }
    func onQuery(_ query: String) async throws -> PluginCanvas {
        return .list([
            PluginItem(
                id: "item1",
                title: "Test Item",
                subtitle: "Sub",
                category: "Test",
                actionPayload: "action"
            )
        ])
    }
}

@Suite("PluginLifecycle E2E Tests")
struct PluginLifecycleE2ETests {
    @Test("Native plugin full lifecycle")
    func testDynamicPluginFullLifecycle() async throws {
        let host = PluginHost()
        defer { host.shutdownAll() }

        #expect(host.loadedManifests().isEmpty)

        let manifest = PluginManifest(
            id: "titik.plugin.test",
            name: "test",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Test plugin",
            entrypoint: "MockLifecycleE2EPlugin",
            triggers: ["!test", "!t"]
        )
        let context = PluginContext(pluginId: manifest.id)
        let plugin = MockLifecycleE2EPlugin(context: context)
        host.registerNativePlugin(plugin, manifest: manifest)

        let loaded = host.loadedManifests()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "titik.plugin.test")

        let activeShort = host.findActivePlugin(command: "t")
        #expect(activeShort != nil)
        #expect(activeShort?.id == "titik.plugin.test")

        host.unloadPlugin(id: "titik.plugin.test")
        #expect(host.loadedManifests().isEmpty)
    }
}

