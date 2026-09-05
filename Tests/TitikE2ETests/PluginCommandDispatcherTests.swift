import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikSearch
@testable import TitikPlatform

@Suite("PluginCommandDispatcher Unit Tests")
struct PluginCommandDispatcherTests {

    @Test("Dispatch pluginCommand to registered command plugin executes with arguments")
    func testDispatchPluginCommandSuccess() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.dispatcher_plugin",
            name: "Dispatcher Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Test plugin for dispatcher execution",
            entrypoint: "MockDispatcherTestPlugin",
            triggers: ["testcmd", "tc"]
        )
        let plugin = MockDispatcherTestPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.test.dispatcher_plugin",
            arguments: ["command": "greet", "name": "World"]
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == true)
        #expect(result.message == "Hello, World!")
        #expect(result.outputPayload?["greeting"] == "Hello, World!")
    }

    @Test("Dispatch pluginCommand by bang trigger name resolves plugin and command")
    func testDispatchPluginCommandByTrigger() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.dispatcher_trigger",
            name: "Trigger Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Test trigger plugin",
            entrypoint: "MockDispatcherTestPlugin",
            triggers: ["testtrigger"]
        )
        let plugin = MockDispatcherTestPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let result = await dispatcher.dispatch(
            query: "!testtrigger greet \"Alice\"",
            mode: .background
        )

        #expect(result.isSuccess == true)
        #expect(result.message == "Hello, Alice!")
    }

    @Test("Dispatch non-existent plugin command returns failure message")
    func testDispatchNonExistentPluginFails() async {
        let host = PluginHost()
        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "nonexistent.plugin.id"
        )

        let result = await dispatcher.dispatch(action: action, mode: .palette)
        #expect(result.isSuccess == false)
        #expect(result.message?.contains("nonexistent.plugin.id") == true)
    }

    @Test("Dispatch quickLink target opens URL with scheme")
    func testDispatchQuickLink() async {
        let dispatcher = PluginCommandDispatcher.shared
        let action = ShortcutActionConfig(
            type: .quickLink,
            target: "https://apple.com"
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == true)
        #expect(result.message?.contains("apple.com") == true)
    }

    @Test("Dispatch rawQuery in background vs palette mode")
    func testDispatchRawQueryModes() async {
        let dispatcher = PluginCommandDispatcher.shared

        let paletteAction = ShortcutActionConfig(type: .rawQuery, target: "!emoji fire")
        let paletteResult = await dispatcher.dispatch(action: paletteAction, mode: .palette)
        #expect(paletteResult.isSuccess == true)

        let bgAction = ShortcutActionConfig(type: .rawQuery, target: "calc 2 + 2")
        let bgResult = await dispatcher.dispatch(action: bgAction, mode: .background)
        #expect(bgResult.isSuccess == true)
    }

    @Test("Dispatch systemCommand executes valid system action and fails on unknown")
    func testDispatchSystemCommand() async {
        let dispatcher = PluginCommandDispatcher.shared

        let validAction = ShortcutActionConfig(type: .systemCommand, target: "emptyTrash")
        let validResult = await dispatcher.dispatch(action: validAction, mode: .background)
        #expect(validResult.isSuccess == true)

        let invalidAction = ShortcutActionConfig(type: .systemCommand, target: "invalid_sys_cmd_xyz")
        let invalidResult = await dispatcher.dispatch(action: invalidAction, mode: .background)
        #expect(invalidResult.isSuccess == false)
        #expect(invalidResult.message?.contains("invalid_sys_cmd_xyz") == true)
    }

    @Test("Dispatch toggleWindow toggles window state")
    func testDispatchToggleWindow() async {
        let dispatcher = PluginCommandDispatcher.shared
        let action = ShortcutActionConfig(type: .toggleWindow, target: "toggle")

        let result = await dispatcher.dispatch(action: action, mode: .palette)
        #expect(result.isSuccess == true)
    }

    @Test("Concurrent dispatch isolation maintains data integrity across tasks")
    func testConcurrentDispatchIsolation() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.concurrent_plugin",
            name: "Concurrent Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Concurrent testing plugin",
            entrypoint: "MockDispatcherTestPlugin",
            triggers: ["concurrent"]
        )
        let plugin = MockDispatcherTestPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)

        await withTaskGroup(of: CommandExecutionResult.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let action = ShortcutActionConfig(
                        type: .pluginCommand,
                        target: "titik.test.concurrent_plugin",
                        arguments: ["command": "greet", "name": "User_\(i)"]
                    )
                    return await dispatcher.dispatch(action: action, mode: .background)
                }
            }

            var successCount = 0
            for await res in group {
                if res.isSuccess {
                    successCount += 1
                }
            }
            #expect(successCount == 20)
        }
    }
}

// MARK: - Test Mock Plugin for Dispatcher

private final class MockDispatcherTestPlugin: TitikCommandPlugin, @unchecked Sendable {
    static let id: String = "titik.test.dispatcher_plugin"
    static let name: String = "Dispatcher Test Plugin"
    static let version: String = "1.0.0"

    var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "greet",
                name: "Greet User",
                description: "Generates a greeting message",
                triggers: ["!greet", "greet"],
                arguments: [
                    PluginCommandArgument(name: "name", description: "Name of user", isRequired: true)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "status",
                name: "Check Status",
                description: "Returns active status",
                triggers: ["!status", "status"],
                arguments: [],
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
        case "greet":
            let name = arguments["name"] ?? arguments["0"] ?? arguments["args"] ?? "Friend"
            let greeting = "Hello, \(name)!"
            return CommandExecutionResult.success(
                message: greeting,
                outputPayload: ["greeting": greeting]
            )
        case "status":
            return CommandExecutionResult.success(
                message: "OK",
                outputPayload: ["status": "active"]
            )
        default:
            return CommandExecutionResult.failure(message: "Unknown command: \(id)")
        }
    }
}
