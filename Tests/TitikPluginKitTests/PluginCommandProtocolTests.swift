import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikPluginKit

@Suite("TitikPluginKit Command Protocol SDK Tests")
struct PluginCommandProtocolTests {

    @Test("PluginCommandDefinition serialization and property integrity")
    func testPluginCommandDefinitionModel() throws {
        let arg1 = PluginCommandArgument(
            name: "url",
            description: "Target URL to open",
            isRequired: true,
            defaultValue: nil
        )
        let arg2 = PluginCommandArgument(
            name: "profile",
            description: "Browser profile name",
            isRequired: false,
            defaultValue: "Default"
        )

        let def = PluginCommandDefinition(
            id: "open-url",
            name: "Open URL in Browser",
            description: "Opens the specified URL in a new browser tab",
            triggers: ["!open-url", "!url", "open-url"],
            arguments: [arg1, arg2],
            defaultMode: .background
        )

        #expect(def.id == "open-url")
        #expect(def.name == "Open URL in Browser")
        #expect(def.triggers.count == 3)
        #expect(def.arguments.count == 2)
        #expect(def.arguments[0].isRequired == true)
        #expect(def.arguments[1].defaultValue == "Default")
        #expect(def.defaultMode == .background)

        // JSON Encoding & Decoding round-trip
        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(PluginCommandDefinition.self, from: data)

        #expect(decoded.id == def.id)
        #expect(decoded.name == def.name)
        #expect(decoded.description == def.description)
        #expect(decoded.triggers == def.triggers)
        #expect(decoded.arguments == def.arguments)
        #expect(decoded.defaultMode == def.defaultMode)
    }

    @Test("PluginCommandArgument validation and defaults")
    func testPluginCommandArgumentDefaults() {
        let defaultArg = PluginCommandArgument(name: "query", description: "Search query")
        #expect(defaultArg.name == "query")
        #expect(defaultArg.description == "Search query")
        #expect(defaultArg.isRequired == false)
        #expect(defaultArg.defaultValue == nil)

        let requiredArg = PluginCommandArgument(
            name: "id",
            description: "Item identifier",
            isRequired: true,
            defaultValue: "root"
        )
        #expect(requiredArg.isRequired == true)
        #expect(requiredArg.defaultValue == "root")
    }

    @Test("CommandExecutionContext payload retention")
    func testCommandExecutionContext() {
        let bgContext = CommandExecutionContext(
            trigger: "hotkey",
            mode: .background,
            rawInput: "cmd+shift+z"
        )
        #expect(bgContext.trigger == "hotkey")
        #expect(bgContext.mode == .background)
        #expect(bgContext.rawInput == "cmd+shift+z")

        let paletteContext = CommandExecutionContext(
            trigger: "bang",
            mode: .palette,
            rawInput: "!zen https://github.com"
        )
        #expect(paletteContext.trigger == "bang")
        #expect(paletteContext.mode == .palette)
        #expect(paletteContext.rawInput == "!zen https://github.com")
    }

    @Test("CommandExecutionResult factory methods and equality")
    func testCommandExecutionResult() {
        let success = CommandExecutionResult.success(
            message: "Tab created successfully",
            outputPayload: ["tabId": "tab_987", "url": "https://apple.com"]
        )
        #expect(success.isSuccess == true)
        #expect(success.message == "Tab created successfully")
        #expect(success.outputPayload?["tabId"] == "tab_987")
        #expect(success.outputPayload?["url"] == "https://apple.com")

        let failure = CommandExecutionResult.failure(
            message: "Profile 'Unknown' does not exist",
            outputPayload: ["error_code": "404"]
        )
        #expect(failure.isSuccess == false)
        #expect(failure.message == "Profile 'Unknown' does not exist")
        #expect(failure.outputPayload?["error_code"] == "404")
    }

    @Test("TitikCommandPlugin protocol default implementation and mock execution")
    func testMockCommandPlugin() async throws {
        let context = PluginContext(pluginId: "titik.test.mock")
        let plugin = TestEchoCommandPlugin(context: context)

        #expect(plugin.pluginId == "titik.test.mock")
        #expect(plugin.commands.count == 2)
        #expect(plugin.commands[0].id == "echo")
        #expect(plugin.commands[1].id == "ping")

        let execContext = CommandExecutionContext(trigger: "unit_test", mode: .background)
        let echoResult = try await plugin.executeCommand(
            id: "echo",
            arguments: ["text": "Hello, Titik!"],
            context: execContext
        )

        #expect(echoResult.isSuccess == true)
        #expect(echoResult.message == "Echo: Hello, Titik!")
        #expect(echoResult.outputPayload?["echo"] == "Hello, Titik!")

        let pingResult = try await plugin.executeCommand(
            id: "ping",
            arguments: [:],
            context: execContext
        )
        #expect(pingResult.isSuccess == true)
        #expect(pingResult.message == "pong")
    }
}

// MARK: - Test Mock Plugin

private final class TestEchoCommandPlugin: TitikCommandPlugin, @unchecked Sendable {
    static let id: String = "titik.test.mock"
    static let name: String = "Mock Command Plugin"
    static let version: String = "1.0.0"

    var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "echo",
                name: "Echo Command",
                description: "Echoes input text back",
                triggers: ["!echo"],
                arguments: [
                    PluginCommandArgument(name: "text", description: "Text to echo", isRequired: true)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "ping",
                name: "Ping Command",
                description: "Pings server and returns pong",
                triggers: ["!ping"],
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
        case "echo":
            let text = arguments["text"] ?? arguments["0"] ?? ""
            return CommandExecutionResult.success(
                message: "Echo: \(text)",
                outputPayload: ["echo": text]
            )
        case "ping":
            return CommandExecutionResult.success(message: "pong")
        default:
            return CommandExecutionResult.failure(message: "Unknown command ID: \(id)")
        }
    }
}
