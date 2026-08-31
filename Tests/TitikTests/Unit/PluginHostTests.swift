import Foundation
import Testing
import TitikPlugins

@Suite("PluginHost Tests")
struct PluginHostTests {
    @Test("Load non-existent plugin fails gracefully")
    func testLoadNonExistentPluginFailsGracefully() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let success = host.loadPlugin(at: "/tmp/non_existent_plugin_12345.titikplugin")
        #expect(!success)
    }

    @Test("Loaded manifests starts empty")
    func testLoadedManifestsStartsEmpty() {
        let host = PluginHost()
        defer { host.shutdownAll() }
        #expect(host.loadedManifests().isEmpty)
    }
}

