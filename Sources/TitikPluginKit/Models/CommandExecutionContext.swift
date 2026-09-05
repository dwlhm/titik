import Foundation
import TitikCore

/// Runtime context passed to a plugin when executing a command.
public struct CommandExecutionContext: Sendable, Equatable {
    public let trigger: String
    public let mode: ShortcutExecutionMode
    public let rawInput: String

    public init(
        trigger: String,
        mode: ShortcutExecutionMode,
        rawInput: String = ""
    ) {
        self.trigger = trigger
        self.mode = mode
        self.rawInput = rawInput
    }
}
