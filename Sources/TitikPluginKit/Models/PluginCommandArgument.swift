import Foundation

/// Represents a declared argument for a plugin command.
public struct PluginCommandArgument: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let isRequired: Bool
    public let defaultValue: String?

    public init(
        name: String,
        description: String,
        isRequired: Bool = false,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.description = description
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}
