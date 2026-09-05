import Foundation

/// Protocol for plugins that expose discrete, parameterized executable commands.
public protocol TitikCommandPlugin: TitikPlugin {
    /// List of executable command definitions exposed by this plugin.
    var commands: [PluginCommandDefinition] { get }

    /// Executes a command by ID with the given arguments and execution context.
    func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult

    /// Executes a command using a formalized plugin invocation AST and execution context.
    func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult
}

public extension TitikCommandPlugin {
    var commands: [PluginCommandDefinition] { [] }

    /// Default implementation converting the structured invocation into `(id, arguments, context)`
    /// for backward compatibility with existing command plugins.
    func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        var arguments: [String: String] = [:]
        for (key, val) in invocation.flags {
            if let str = val.stringValue {
                arguments[key] = str
            }
        }
        if !invocation.primaryValue.isEmpty {
            arguments["args"] = invocation.primaryValue
        }
        let commandId = invocation.action ?? commands.first?.id ?? invocation.trigger
        return try await executeCommand(id: commandId, arguments: arguments, context: context)
    }

    func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        return .failure(message: "Command '\(id)' not implemented")
    }
}
