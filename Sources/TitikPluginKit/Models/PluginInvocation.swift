import Foundation

/// Represents the value of a flag passed to a plugin invocation.
public enum FlagValue: Sendable, Equatable {
    /// A boolean flag (e.g. `--private`, `--force`).
    case boolean(Bool)
    /// A string-valued flag (e.g. `--profile work`).
    case string(String)

    /// Returns the string representation of the flag value.
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .boolean(let b): return b ? "true" : "false"
        }
    }

    /// Returns the boolean representation of the flag value.
    public var boolValue: Bool {
        switch self {
        case .boolean(let b): return b
        case .string(let s): return ["true", "1", "yes"].contains(s.lowercased())
        }
    }
}

/// Formalized AST representation of a parsed plugin invocation.
/// Single declarative source of truth for command parsing across all plugins.
public struct PluginInvocation: Sendable, Equatable {
    /// The plugin trigger name without bang prefix (e.g. "zen", "calc", "emoji").
    public let trigger: String
    /// An optional action or subcommand identifier (e.g. "new-tab", "profile").
    public let action: String?
    /// The primary unquoted argument or domain input payload.
    public let primaryValue: String
    /// Parsed flags mapped by flag name without leading dashes.
    public let flags: [String: FlagValue]
    /// Verbatim raw input query as entered by the user.
    public let rawInput: String

    /// Initializes a new plugin invocation.
    /// - Parameters:
    ///   - trigger: The trigger keyword (e.g. "zen").
    ///   - action: Optional subcommand/action name (e.g. "new-tab").
    ///   - primaryValue: The primary argument payload.
    ///   - flags: Map of parsed flags and their values.
    ///   - rawInput: Verbatim query string.
    public init(
        trigger: String,
        action: String? = nil,
        primaryValue: String = "",
        flags: [String: FlagValue] = [:],
        rawInput: String = ""
    ) {
        self.trigger = trigger
        self.action = action
        self.primaryValue = primaryValue
        self.flags = flags
        self.rawInput = rawInput
    }

    /// Retrieves the string value of a flag by name if present.
    /// - Parameter name: The flag name without dashes.
    /// - Returns: The string value if present, or nil.
    public func flag(_ name: String) -> String? {
        flags[name]?.stringValue
    }

    /// Checks whether a boolean flag is set to true.
    /// - Parameter name: The flag name without dashes.
    /// - Returns: `true` if the flag is present and evaluates to true; otherwise `false`.
    public func hasFlag(_ name: String) -> Bool {
        flags[name]?.boolValue ?? false
    }
}
