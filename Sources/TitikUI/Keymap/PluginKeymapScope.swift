import Foundation
import AppKit
import TitikKeymap

/// Declarative keymap authority that manages contextual keyboard shortcuts for active plugins.
///
/// `PluginKeymapScope` provides an isolated, dynamic keybinding environment scoped to plugin interactions.
/// Key features and architectural guarantees include:
/// - **Declarative Keymap Authority**: Maintains active keyboard combinations and their associated UI labels,
///   serving as the single source of truth for plugin shortcuts.
/// - **`@MainActor` Thread Safety**: All state mutations, registrations, and shortcut trigger invocations
///   are bound to `@MainActor`, ensuring thread-safe coordination with AppKit and SwiftUI UI components.
/// - **Parameterless Action Dispatch**: Registered actions are executed as parameterless `@MainActor () -> Void`
///   closures when an event matches a registered combination.
/// - **Dynamic Keycap Derivation**: Automatically projects registered bindings that define labels into
///   ordered `KeycapAction` models for rendering in HUD footers and cheat sheets.
@MainActor
public final class PluginKeymapScope {
    /// A single shortcut binding registration associating a `KeyCombination` with its metadata and action.
    public struct Binding: @unchecked Sendable {
        public let combination: KeyCombination
        public let shortcutText: String
        public let label: String?
        public let action: @MainActor () -> Void

        public init(combination: KeyCombination, shortcutText: String, label: String?, action: @escaping @MainActor () -> Void) {
            self.combination = combination
            self.shortcutText = shortcutText
            self.label = label
            self.action = action
        }
    }

    private var bindings: [KeyCombination: Binding] = [:]
    private var orderedCombinations: [KeyCombination] = []

    public typealias KeyCapturedHandler = @MainActor (KeyCombination) -> Void
    public typealias KeyModifierOnlyHandler = @MainActor (KeyModifier) -> Void
    public typealias KeyCaptureCancelledHandler = @MainActor () -> Void

    private var capturedHandler: KeyCapturedHandler?
    private var modifierOnlyHandler: KeyModifierOnlyHandler?
    private var cancelledHandler: KeyCaptureCancelledHandler?

    /// Begins interactive key capture mode for this plugin scope.
    public func startCapture(
        onCaptured: @escaping KeyCapturedHandler,
        onModifierOnly: KeyModifierOnlyHandler? = nil,
        onCancelled: KeyCaptureCancelledHandler? = nil
    ) {
        self.capturedHandler = onCaptured
        self.modifierOnlyHandler = onModifierOnly
        self.cancelledHandler = onCancelled
    }

    /// Terminates active key capture mode.
    public func stopCapture() {
        self.capturedHandler = nil
        self.modifierOnlyHandler = nil
        self.cancelledHandler = nil
    }

    /// Indicates whether the scope is currently capturing key combinations.
    public var isCapturing: Bool {
        capturedHandler != nil
    }

    /// Optional callback invoked when registered bindings change.
    @MainActor public var onChange: (@MainActor () -> Void)?

    /// Creates an empty plugin keymap scope.
    public init() {}

    /// Registers a keyboard shortcut with an optional display label and action handler.
    ///
    /// If the shortcut string parses into a valid `KeyCombination`, the binding is stored
    /// and its display order is preserved. If the shortcut is already registered, its binding is updated.
    ///
    /// - Parameters:
    ///   - shortcut: The string representation of the shortcut (e.g. `"cmd+enter"`, `"ctrl+n"`).
    ///   - label: An optional human-readable description used for keycap bar display (e.g. `"Open"`).
    ///   - action: The parameterless closure to execute on the main actor when triggered.
    public func register(
        _ shortcut: String,
        label: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        guard let combo = KeyCombination(string: shortcut) else {
            return
        }
        let binding = Binding(combination: combo, shortcutText: shortcut, label: label, action: action)
        bindings[combo] = binding
        if !orderedCombinations.contains(combo) {
            orderedCombinations.append(combo)
        }
        onChange?()
    }

    /// Unregisters an existing keyboard shortcut binding.
    ///
    /// - Parameter shortcut: The string representation of the shortcut to remove.
    public func unregister(_ shortcut: String) {
        guard let combo = KeyCombination(string: shortcut) else { return }
        let removed = bindings.removeValue(forKey: combo)
        orderedCombinations.removeAll { $0 == combo }
        if removed != nil {
            onChange?()
        }
    }

    /// Removes all registered shortcut bindings and resets the keycap order.
    public func removeAll() {
        bindings.removeAll()
        orderedCombinations.removeAll()
        onChange?()
    }

    /// Derives the ordered list of `KeycapAction` items for all registered shortcuts with labels.
    ///
    /// Only bindings configured with a non-nil `label` are included in the resulting array,
    /// preserving the insertion order of registration.
    public var keycaps: [KeycapAction] {
        orderedCombinations.compactMap { combo in
            guard let b = bindings[combo], let label = b.label else { return nil }
            return KeycapAction(shortcut: b.shortcutText, label: label)
        }
    }

    /// Intercepts and triggers any registered action matching the incoming key-down event.
    ///
    /// Resolves the event's modifier flags and keycode into a `KeyCombination`. If a matching
    /// binding is found, its parameterless action closure is dispatched immediately on the main actor.
    ///
    /// - Parameter event: The `NSEvent` representing the keyboard event to evaluate.
    /// - Returns: `true` if the event matched a registered binding and was consumed; otherwise `false`.
    public func trigger(event: NSEvent) -> Bool {
        let modifiers = KeyModifier.from(nsFlags: event.modifierFlags)
        let rawCode = UInt32(event.keyCode)

        if isCapturing {
            // If key is Escape (without modifiers): calls onCancelled?(), calls stopCapture(), returns true (consumed)
            if rawCode == Keycode.escape.rawValue && modifiers.isEmpty {
                let handler = cancelledHandler
                stopCapture()
                handler?()
                return true
            }

            let isModifierKey: Bool = {
                return rawCode == Keycode.command.rawValue ||
                       rawCode == Keycode.shift.rawValue ||
                       rawCode == Keycode.option.rawValue ||
                       rawCode == Keycode.control.rawValue ||
                       rawCode == 0x36 || // kVK_RightCommand
                       rawCode == 0x3C || // kVK_RightShift
                       rawCode == 0x3D || // kVK_RightOption
                       rawCode == 0x3E || // kVK_RightControl
                       rawCode == 0x3F || // kVK_Function
                       rawCode == 0x39    // kVK_CapsLock
            }()

            // If key is a lone modifier (Command, Shift, Option, Control, Fn): calls onModifierOnly?(modifiers), returns true
            if isModifierKey {
                modifierOnlyHandler?(modifiers)
                return true
            }

            // If key is a valid non-modifier Keycode: resolves KeyCombination(modifiers:key:), calls onCaptured(combo), calls stopCapture(), returns true
            guard let keycode = Keycode(rawValue: rawCode) else {
                // If unmappable: ignores and returns true (consumed)
                return true
            }

            let combo = KeyCombination(modifiers: modifiers, key: keycode)
            let handler = capturedHandler
            stopCapture()
            handler?(combo)
            return true
        }

        guard let keycode = Keycode(rawValue: rawCode) else {
            return false
        }
        let combo = KeyCombination(modifiers: modifiers, key: keycode)
        if let binding = bindings[combo] {
            binding.action()
            return true
        }
        return false
    }
}
