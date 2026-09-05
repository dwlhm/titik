import Foundation
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform

@Suite("ZenBrowserPlugin Unit & Integration Tests")
struct ZenBrowserPluginTests {

    func makePlugin() -> ZenBrowserPlugin {
        ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))
    }

    // MARK: - Manifest & Commands

    @Test("Manifest metadata matches specification")
    func testManifestMetadata() {
        #expect(zenBrowserPluginManifest.id == "titik.plugin.zen")
        #expect(zenBrowserPluginManifest.name == "Zen Browser")
        #expect(zenBrowserPluginManifest.triggers.contains("zen"))
        #expect(zenBrowserPluginManifest.normalizedBangs.contains("zen"))
        #expect(zenBrowserPluginManifest.permissions.contains("workspace:launch"))
    }

    @Test("Plugin declares all required commands")
    func testDeclaredCommands() {
        let plugin = makePlugin()
        let commandIds = plugin.commands.map(\.id)

        #expect(commandIds.contains("open-url"))
        #expect(commandIds.contains("new-tab"))
        #expect(commandIds.contains("new-window"))
        #expect(commandIds.contains("profile"))
    }

    // MARK: - Command Execution & CLI Flag Building

    @Test("open-url command builds correct URL and profile flags")
    func testOpenURLFlags() async throws {
        let plugin = makePlugin()
        let flags = plugin.buildCLIFlags(
            id: "open-url",
            arguments: [
                "url": "https://apple.com",
                "profile": "Work"
            ]
        )

        #expect(flags.contains("-P"))
        #expect(flags.contains("Work"))
        #expect(flags.contains("https://apple.com"))

        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "open-url",
            arguments: ["url": "https://apple.com", "profile": "Work"],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["url"] == "https://apple.com")
        #expect(result.outputPayload?["profile"] == "Work")
        #expect(result.outputPayload?["flags"]?.contains("-P Work") == true)
    }

    @Test("open-url fails when URL is missing")
    func testOpenURLMissingFails() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "open-url",
            arguments: [:],
            context: context
        )

        #expect(result.isSuccess == false)
        #expect(result.message?.contains("Missing URL") == true)
    }

    @Test("new-tab command builds new-tab flag")
    func testNewTabFlags() async throws {
        let plugin = makePlugin()
        let flags = plugin.buildCLIFlags(
            id: "new-tab",
            arguments: ["url": "https://github.com"]
        )

        #expect(flags.contains("-new-tab"))
        #expect(flags.contains("https://github.com"))

        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "new-tab",
            arguments: ["url": "https://github.com"],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["command"] == "new-tab")
    }

    @Test("new-window command builds new-window and private-window flags")
    func testNewWindowFlags() async throws {
        let plugin = makePlugin()

        let normalFlags = plugin.buildCLIFlags(
            id: "new-window",
            arguments: ["url": "https://news.ycombinator.com"]
        )
        #expect(normalFlags.contains("-new-window"))
        #expect(normalFlags.contains("https://news.ycombinator.com"))

        let privateFlags = plugin.buildCLIFlags(
            id: "new-window",
            arguments: ["url": "https://news.ycombinator.com", "private": "true"]
        )
        #expect(privateFlags.contains("-private-window"))
        #expect(!privateFlags.contains("-new-window"))
    }

    @Test("profile command builds profile arguments and validates required parameter")
    func testProfileCommand() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)

        // Missing profile
        let failResult = try await plugin.executeCommand(
            id: "profile",
            arguments: [:],
            context: context
        )
        #expect(failResult.isSuccess == false)
        #expect(failResult.message?.contains("Missing profile") == true)

        // Valid profile
        let successResult = try await plugin.executeCommand(
            id: "profile",
            arguments: ["profile": "Personal", "url": "https://zen-browser.app"],
            context: context
        )
        #expect(successResult.isSuccess == true)
        #expect(successResult.outputPayload?["profile"] == "Personal")
        #expect(successResult.outputPayload?["flags"]?.contains("-P Personal") == true)
    }

    // MARK: - Query / Canvas Streaming

    @Test("onQuery with empty query returns all subcommands")
    func testOnQueryEmpty() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count == 4)
        #expect(items.contains { $0.id.contains("open-url") })
        #expect(items.contains { $0.id.contains("new-tab") })
        #expect(items.contains { $0.id.contains("new-window") })
        #expect(items.contains { $0.id.contains("profile") })
    }

    @Test("onQuery with URL query returns open URL item")
    func testOnQueryURL() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("https://swift.org")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(!items.isEmpty)
        #expect(items.contains { $0.actionPayload == "https://swift.org" })
    }

    @Test("onQuery with subcommand filter returns matching commands")
    func testOnQuerySubcommand() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("tab")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(!items.isEmpty)
        #expect(items.contains { $0.title.contains("New Tab") })
    }

    // MARK: - Dispatcher Integration

    @Test("PluginCommandDispatcher dispatches zen bang query")
    func testDispatcherIntegration() async {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let plugin = makePlugin()
        host.registerNativePlugin(plugin, manifest: zenBrowserPluginManifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let result = await dispatcher.dispatch(
            query: "!zen open-url https://developer.apple.com",
            mode: .background
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["url"]?.contains("developer.apple.com") == true)
    }

    @Test("PluginHost loads ZenBrowser dynamic bundle and cancels active stream without crash")
    func testDynamicBundleLoadingAndCancelStream() async throws {
        let bundlePath = "bin/plugins/ZenBrowser.bundle"
        guard FileManager.default.fileExists(atPath: bundlePath) else { return }

        let host = PluginHost()
        defer { host.shutdownAll() }

        let bundleURL = URL(fileURLWithPath: bundlePath)
        let loadedPlugin = try host.loadNativePluginBundle(at: bundleURL)
        #expect(loadedPlugin.pluginId == "titik.plugin.zen")
        host.cancelAllActiveTasks()
    }
}
