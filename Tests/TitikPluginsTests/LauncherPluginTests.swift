import Foundation
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform

@Suite("LauncherPlugin Unit & Integration Tests")
struct LauncherPluginTests {

    func makePlugin() -> LauncherPlugin {
        LauncherPlugin(context: PluginContext(pluginId: LauncherPlugin.id))
    }

    // MARK: - Manifest & Commands

    @Test("Manifest metadata matches specification")
    func testManifestMetadata() {
        #expect(launcherPluginManifest.id == "titik.builtin.launcher")
        #expect(launcherPluginManifest.name == "App & Project Launcher")
        #expect(launcherPluginManifest.triggers.contains("open"))
        #expect(launcherPluginManifest.normalizedBangs.contains("open"))
        #expect(launcherPluginManifest.permissions.contains("workspace:launch"))
    }

    @Test("Plugin declares launch-app, open-project, and open-path commands")
    func testDeclaredCommands() {
        let plugin = makePlugin()
        let commandIds = plugin.commands.map(\.id)

        #expect(commandIds.contains("launch-app"))
        #expect(commandIds.contains("open-project"))
        #expect(commandIds.contains("open-path"))
    }

    // MARK: - Command Execution

    @Test("launch-app validates missing app argument")
    func testLaunchAppMissingArg() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "launch-app",
            arguments: [:],
            context: context
        )

        #expect(result.isSuccess == false)
        #expect(result.message?.contains("Missing application name") == true)
    }

    @Test("launch-app with non-existent app name returns actionable error")
    func testLaunchAppNonExistent() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "launch-app",
            arguments: ["app": "NonExistentApp_\(UUID().uuidString)"],
            context: context
        )

        #expect(result.isSuccess == false)
        #expect(result.message?.contains("not found") == true)
    }

    @Test("open-project expands tilde and constructs IDE launch parameters")
    func testOpenProjectExecution() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "open-project",
            arguments: [
                "path": "~/project/titik",
                "ide": "Antigravity"
            ],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["ide"] == "Antigravity")
        #expect(result.outputPayload?["path"]?.contains("project/titik") == true)
        #expect(result.outputPayload?["path"]?.hasPrefix("~") == false)
    }

    @Test("open-project validates missing path argument")
    func testOpenProjectMissingPath() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "open-project",
            arguments: [:],
            context: context
        )

        #expect(result.isSuccess == false)
        #expect(result.message?.contains("Missing project path") == true)
    }

    @Test("open-path executes for existing system path")
    func testOpenPathExecution() async throws {
        let plugin = makePlugin()
        let context = CommandExecutionContext(trigger: "test", mode: .background)
        let result = try await plugin.executeCommand(
            id: "open-path",
            arguments: ["path": "/System/Applications"],
            context: context
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["path"] == "/System/Applications")
    }

    // MARK: - Query / Canvas Streaming

    @Test("onQuery with empty query returns available commands")
    func testOnQueryEmpty() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(items.count >= 3)
        #expect(items.contains { $0.id.contains("launch-app") })
        #expect(items.contains { $0.id.contains("open-project") })
        #expect(items.contains { $0.id.contains("open-path") })
    }

    @Test("onQuery with path returns open project action item")
    func testOnQueryPath() async throws {
        let plugin = makePlugin()
        let canvas = try await plugin.onQuery("~/dev/myproject")

        guard case .list(let items) = canvas else {
            #expect(Bool(false), "Expected .list canvas")
            return
        }

        #expect(!items.isEmpty)
        #expect(items.first?.category == "Launcher")
    }

    // MARK: - Dispatcher Integration

    @Test("PluginCommandDispatcher dispatches open bang query")
    func testDispatcherIntegration() async {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let plugin = makePlugin()
        host.registerNativePlugin(plugin, manifest: launcherPluginManifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let result = await dispatcher.dispatch(
            query: "!open open-project /tmp",
            mode: .background
        )

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["path"] == "/tmp")
    }
}
