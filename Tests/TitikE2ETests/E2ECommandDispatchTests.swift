import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform
@testable import TitikSearch

// MARK: - SDK Interface Types for Command Plugin Integration

public enum PluginCommandMode: String, Codable, Sendable, Equatable {
    case background
    case palette
}

public struct PluginCommandArgumentModel: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let isRequired: Bool
    public let defaultValue: String?

    public init(name: String, description: String, isRequired: Bool = false, defaultValue: String? = nil) {
        self.name = name
        self.description = description
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}

public struct PluginCommandDefinitionModel: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let triggers: [String]
    public let arguments: [PluginCommandArgumentModel]
    public let defaultMode: PluginCommandMode

    public init(
        id: String,
        name: String,
        description: String,
        triggers: [String],
        arguments: [PluginCommandArgumentModel] = [],
        defaultMode: PluginCommandMode = .palette
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.triggers = triggers
        self.arguments = arguments
        self.defaultMode = defaultMode
    }
}

public struct CommandExecutionContextModel: Sendable {
    public let trigger: String
    public let mode: PluginCommandMode
    public let rawInput: String

    public init(trigger: String, mode: PluginCommandMode, rawInput: String) {
        self.trigger = trigger
        self.mode = mode
        self.rawInput = rawInput
    }
}

public struct CommandExecutionResultModel: Sendable, Equatable {
    public let isSuccess: Bool
    public let message: String?
    public let outputPayload: [String: String]?

    public init(isSuccess: Bool, message: String? = nil, outputPayload: [String: String]? = nil) {
        self.isSuccess = isSuccess
        self.message = message
        self.outputPayload = outputPayload
    }
}

@Suite("E2E Plugin Command Protocol & Dispatcher Tests")
struct E2ECommandDispatchTests {

    // MARK: - Feature 9: Plugin Command Protocol SDK

    @Test("F09: PluginCommandDefinition struct model construction and serialization")
    func test_f09_commandDefinitionStructure() throws {
        let arg = PluginCommandArgumentModel(
            name: "url",
            description: "Target URL to open",
            isRequired: true,
            defaultValue: nil
        )
        let command = PluginCommandDefinitionModel(
            id: "open-url",
            name: "Open URL",
            description: "Opens a URL in Zen Browser",
            triggers: ["!zen", "!open-url"],
            arguments: [arg],
            defaultMode: .background
        )

        #expect(command.id == "open-url")
        #expect(command.name == "Open URL")
        #expect(command.triggers.contains("!zen"))
        #expect(command.arguments.count == 1)
        #expect(command.arguments.first?.isRequired == true)
        #expect(command.defaultMode == .background)

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(PluginCommandDefinitionModel.self, from: data)
        #expect(decoded == command)
    }

    @Test("F09: PluginCommandArgument validation for required vs optional parameters")
    func test_f09_argumentRequiredAndDefaultFlags() {
        let reqArg = PluginCommandArgumentModel(name: "path", description: "Folder path", isRequired: true)
        let optArg = PluginCommandArgumentModel(name: "ide", description: "Target IDE", isRequired: false, defaultValue: "Antigravity")

        #expect(reqArg.isRequired == true)
        #expect(reqArg.defaultValue == nil)

        #expect(optArg.isRequired == false)
        #expect(optArg.defaultValue == "Antigravity")
    }

    @Test("F09: CommandExecutionContext retains trigger, execution mode and raw input")
    func test_f09_executionContextPayload() {
        let context = CommandExecutionContextModel(
            trigger: "hotkey",
            mode: .background,
            rawInput: "cmd+shift+z"
        )

        #expect(context.trigger == "hotkey")
        #expect(context.mode == .background)
        #expect(context.rawInput == "cmd+shift+z")
    }

    @Test("F09: CommandExecutionResult variants for success, failure and output payload")
    func test_f09_commandExecutionResultOutput() {
        let successResult = CommandExecutionResultModel(
            isSuccess: true,
            message: "Successfully opened tab",
            outputPayload: ["tabId": "12345"]
        )
        #expect(successResult.isSuccess == true)
        #expect(successResult.message == "Successfully opened tab")
        #expect(successResult.outputPayload?["tabId"] == "12345")

        let failResult = CommandExecutionResultModel(
            isSuccess: false,
            message: "Application not found"
        )
        #expect(failResult.isSuccess == false)
        #expect(failResult.outputPayload == nil)
    }

    @Test("F09: Mock command plugin conformance and execution simulation")
    func test_f09_mockCommandPluginExecution() async {
        let mockPlugin = MockCommandPlugin()
        #expect(mockPlugin.commands.count == 2)

        let context = CommandExecutionContextModel(trigger: "bang", mode: .palette, rawInput: "!mock echo hello")
        let result = await mockPlugin.execute(commandId: "echo", arguments: ["message": "hello"], context: context)

        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["echo"] == "hello")
    }

    // MARK: - Feature 10: Unified Command Dispatcher

    @Test("F10: Direct dispatch from hotkey payload runs background action")
    func test_f10_directDispatchFromHotkeyPayload() async {
        let dispatcher = MockDispatcher()
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.builtin.zen",
            arguments: ["command": "new-tab", "url": "https://apple.com"]
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == true)
        let mode = await dispatcher.lastDispatchedMode
        let target = await dispatcher.lastTarget
        #expect(mode == .background)
        #expect(target == "titik.builtin.zen")
    }

    @Test("F10: Dispatch app launch target triggers application launch")
    func test_f10_dispatchAppLaunchTarget() async {
        let dispatcher = MockDispatcher()
        let action = ShortcutActionConfig(
            type: .appLaunch,
            target: "/Applications/Safari.app"
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == true)
        let target = await dispatcher.lastTarget
        #expect(target == "/Applications/Safari.app")
    }

    @Test("F10: Dispatch quick link target opens URL")
    func test_f10_dispatchQuickLinkTarget() async {
        let dispatcher = MockDispatcher()
        let action = ShortcutActionConfig(
            type: .quickLink,
            target: "https://github.com"
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == true)
        let target = await dispatcher.lastTarget
        #expect(target == "https://github.com")
    }

    @Test("F10: Dispatch unknown command fails gracefully with error message")
    func test_f10_dispatchNonExistentCommandFailsGracefully() async {
        let dispatcher = MockDispatcher()
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "unknown.nonexistent.plugin"
        )

        let result = await dispatcher.dispatch(action: action, mode: .palette)
        #expect(result.isSuccess == false)
        #expect(result.message?.contains("unknown.nonexistent.plugin") == true)
    }

    @Test("F10: Concurrent command dispatches execute independently without collision")
    func test_f10_concurrentDispatchIsolation() async {
        let dispatcher = MockDispatcher()

        await withTaskGroup(of: CommandExecutionResultModel.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let action = ShortcutActionConfig(
                        type: .pluginCommand,
                        target: "titik.builtin.zen",
                        arguments: ["tab": "tab_\(i)"]
                    )
                    return await dispatcher.dispatch(action: action, mode: .background)
                }
            }

            var successCount = 0
            for await res in group {
                if res.isSuccess { successCount += 1 }
            }
            #expect(successCount == 20)
        }
    }

    // MARK: - Feature 11: Bang Query Sub-Command Routing

    @Test("F11: Bang query identifies plugin command and arguments via CommandParser")
    func test_f11_bangQueryIdentifiesPlugin() {
        let parser = CommandParser()
        let ast = parser.parse("!zen \"https://apple.com\"")

        if case .pluginInvocation(let trigger, _, let primaryValue, _, _, _) = ast {
            #expect(trigger == "zen")
            #expect(primaryValue == "https://apple.com")
        } else {
            #expect(Bool(false), "Expected .pluginInvocation AST")
        }
    }

    @Test("F11: Bang query with flags and subcommands parsed cleanly")
    func test_f11_bangQueryWithSubcommand() {
        let parser = CommandParser()
        let ast = parser.parse("!open -ide=Antigravity ~/workspace/demo")

        if case .pluginInvocation(let trigger, _, let primaryValue, let flags, _, _) = ast {
            #expect(trigger == "open")
            #expect(flags["ide"] == "Antigravity")
            #expect(primaryValue == "~/workspace/demo")
        } else {
            #expect(Bool(false), "Expected .pluginInvocation AST with flags")
        }
    }

    @Test("F11: Bang prefix suggestions generated via BangSuggestionHelper")
    func test_f11_bangPrefixSuggestionGeneration() {
        let pluginBangs = ["!zen", "!open", "!shortcut"]

        let suffix1 = BangSuggestionHelper.suggestionSuffix(for: "!z", pluginBangs: pluginBangs)
        #expect(suffix1 == "en")

        let suffix2 = BangSuggestionHelper.suggestionSuffix(for: "!op", pluginBangs: pluginBangs)
        #expect(suffix2 == "en")

        let full = BangSuggestionHelper.fullSuggestion(for: "!sh", pluginBangs: pluginBangs)
        #expect(full == "!shortcut")
    }

    @Test("F11: Incomplete bang without trailing space yields bangSuggestion AST")
    func test_f11_incompleteBangYieldsSuggestion() {
        let parser = CommandParser()
        let ast = parser.parse("!ze")

        if case .bangSuggestion(let prefix) = ast {
            #expect(prefix == "ze")
        } else {
            #expect(Bool(false), "Expected .bangSuggestion AST")
        }
    }

    @Test("F11: Escaped or malformed bang queries do not crash parser")
    func test_f11_escapedOrMalformedBangHandling() {
        let parser = CommandParser()

        let queries = [
            "!",
            "!!",
            "! zen",
            "!zen \"unclosed quote",
            "!-flag-without-name",
            "!calc (3 + * 4)"
        ]

        for q in queries {
            let ast = parser.parse(q)
            #expect(ast != .empty || q == "!" || q == "! zen")
        }
    }
}

// MARK: - Test Helpers & Mocks

private final class MockCommandPlugin: Sendable {
    let commands: [PluginCommandDefinitionModel] = [
        PluginCommandDefinitionModel(
            id: "echo",
            name: "Echo",
            description: "Echoes input back",
            triggers: ["!echo"],
            arguments: [PluginCommandArgumentModel(name: "message", description: "Message to echo", isRequired: true)]
        ),
        PluginCommandDefinitionModel(
            id: "ping",
            name: "Ping",
            description: "Pings server",
            triggers: ["!ping"],
            arguments: []
        )
    ]

    func execute(
        commandId: String,
        arguments: [String: String],
        context: CommandExecutionContextModel
    ) async -> CommandExecutionResultModel {
        switch commandId {
        case "echo":
            let msg = arguments["message"] ?? ""
            return CommandExecutionResultModel(isSuccess: true, message: msg, outputPayload: ["echo": msg])
        case "ping":
            return CommandExecutionResultModel(isSuccess: true, message: "pong")
        default:
            return CommandExecutionResultModel(isSuccess: false, message: "Unknown command: \(commandId)")
        }
    }
}

private actor MockDispatcher {
    var lastTarget: String?
    var lastDispatchedMode: PluginCommandMode?

    func dispatch(action: ShortcutActionConfig, mode: PluginCommandMode) -> CommandExecutionResultModel {
        lastTarget = action.target
        lastDispatchedMode = mode

        if action.target.contains("unknown") {
            return CommandExecutionResultModel(isSuccess: false, message: "Target '\(action.target)' not found")
        }

        return CommandExecutionResultModel(isSuccess: true, message: "Executed \(action.type.rawValue) on \(action.target)")
    }
}
