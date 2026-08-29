import Foundation
import Testing
import TitikPlugins

@Suite("PluginHost Tests")
struct PluginHostTests {
    @Test("Load non-existent plugin fails gracefully")
    func testLoadNonExistentPluginFailsGracefully() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let success = host.loadPlugin(at: "/tmp/non_existent_plugin_12345.dylib")
        #expect(!success)
    }

    @Test("Load real math plugin")
    func testLoadRealMathPluginIfPresent() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let mathPluginPath = "plugins/math_plugin/math.dylib"
        if FileManager.default.fileExists(atPath: mathPluginPath) {
            let loaded = host.loadPlugin(at: mathPluginPath)
            #expect(loaded)

            let results = host.queryAll(query: "25 * 4")
            #expect(!results.isEmpty)
            #expect(results.first?.title == "100")
        }
    }
}
