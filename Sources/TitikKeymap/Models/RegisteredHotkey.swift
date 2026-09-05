import Foundation

/// Represents a currently active registered global hotkey.
public struct RegisteredHotkey: Sendable {
    /// Unique Carbon event hotkey ID.
    public let id: UInt32

    /// Unique logical identifier (e.g. "titik.toggle", "plugin.zen.new_tab").
    public let identifier: String

    /// Physical key combination bound to this hotkey.
    public let combination: KeyCombination

    /// Execution presentation mode (background silent or palette HUD).
    public let mode: ShortcutExecutionMode

    /// Action handler executed when the hotkey is triggered.
    public let handler: @Sendable () -> Void

    public init(
        id: UInt32,
        identifier: String,
        combination: KeyCombination,
        mode: ShortcutExecutionMode,
        handler: @escaping @Sendable () -> Void
    ) {
        self.id = id
        self.identifier = identifier
        self.combination = combination
        self.mode = mode
        self.handler = handler
    }
}
