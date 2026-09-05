import Foundation
import Testing
import TitikPlugins

@Suite("PluginHost Tests")
struct PluginHostTests {
    @Test("Load non-existent plugin fails gracefully")
    func testLoadNonExistentPluginFailsGracefully() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let nonExistentPath = FileManager.default.temporaryDirectory.appendingPathComponent("non_existent_plugin_\(UUID().uuidString).titikplugin").path
        let success = host.loadPlugin(at: nonExistentPath)
        #expect(!success)
    }

    @Test("Loaded manifests starts empty")
    func testLoadedManifestsStartsEmpty() {
        let host = PluginHost()
        defer { host.shutdownAll() }
        #expect(host.loadedManifests().isEmpty)
    }
}

