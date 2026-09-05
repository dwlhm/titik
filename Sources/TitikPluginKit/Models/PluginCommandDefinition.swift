import Foundation
import TitikCore

/// Declares a discrete executable command exposed by a Titik plugin.
public struct PluginCommandDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let triggers: [String]
    public let arguments: [PluginCommandArgument]
    public let defaultMode: ShortcutExecutionMode

    public init(
        id: String,
        name: String,
        description: String,
        triggers: [String] = [],
        arguments: [PluginCommandArgument] = [],
        defaultMode: ShortcutExecutionMode = .palette
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.triggers = triggers
        self.arguments = arguments
        self.defaultMode = defaultMode
    }
}
