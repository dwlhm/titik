import Foundation

/// The result returned after executing a plugin command.
public struct CommandExecutionResult: Sendable, Equatable {
    public let isSuccess: Bool
    public let message: String?
    public let outputPayload: [String: String]?

    public init(
        isSuccess: Bool,
        message: String? = nil,
        outputPayload: [String: String]? = nil
    ) {
        self.isSuccess = isSuccess
        self.message = message
        self.outputPayload = outputPayload
    }

    public static func success(message: String? = nil, outputPayload: [String: String]? = nil) -> CommandExecutionResult {
        CommandExecutionResult(isSuccess: true, message: message, outputPayload: outputPayload)
    }

    public static func failure(message: String?, outputPayload: [String: String]? = nil) -> CommandExecutionResult {
        CommandExecutionResult(isSuccess: false, message: message, outputPayload: outputPayload)
    }
}
