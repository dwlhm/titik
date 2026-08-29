import Foundation
import TitikCore

public enum KeymapError: Error, Equatable, LocalizedError {
    case duplicateBinding(combination: KeyCombination, existingIdentifier: String)
    case notFound(identifier: String)

    public var errorDescription: String? {
        switch self {
        case .duplicateBinding(let combo, let id):
            return "Key combination '\(combo)' is already bound to action '\(id)'"
        case .notFound(let id):
            return "Key binding with identifier '\(id)' not found"
        }
    }
}

public struct KeyBinding: Sendable {
    public let identifier: String
    public let combination: KeyCombination
    public let action: @Sendable () -> Void

    public init(identifier: String, combination: KeyCombination, action: @escaping @Sendable () -> Void) {
        self.identifier = identifier
        self.combination = combination
        self.action = action
    }
}

public final class KeymapRegistry: @unchecked Sendable {
    public static let shared = KeymapRegistry()

    private let lock = NSLock()
    private var bindingsByCombo: [KeyCombination: KeyBinding] = [:]
    private var bindingsById: [String: KeyCombination] = [:]

    public init() {}

    public func register(
        combination: KeyCombination,
        identifier: String,
        action: @escaping @Sendable () -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if let existing = bindingsByCombo[combination] {
            if existing.identifier != identifier {
                Logger.shared.warn("Conflict: Combination '\(combination)' already bound to '\(existing.identifier)'", subsystem: "Titik.Keymap")
                throw KeymapError.duplicateBinding(combination: combination, existingIdentifier: existing.identifier)
            }
        }

        // Remove previous combo for this identifier if re-registering
        if let previousCombo = bindingsById[identifier] {
            bindingsByCombo.removeValue(forKey: previousCombo)
        }

        let binding = KeyBinding(identifier: identifier, combination: combination, action: action)
        bindingsByCombo[combination] = binding
        bindingsById[identifier] = combination
        Logger.shared.debug("Registered key combination '\(combination)' for '\(identifier)'", subsystem: "Titik.Keymap")
    }

    public func unregister(identifier: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let combo = bindingsById.removeValue(forKey: identifier) else { return }
        bindingsByCombo.removeValue(forKey: combo)
        Logger.shared.debug("Unregistered key binding for '\(identifier)'", subsystem: "Titik.Keymap")
    }

    public func unregister(combination: KeyCombination) {
        lock.lock()
        defer { lock.unlock() }

        guard let binding = bindingsByCombo.removeValue(forKey: combination) else { return }
        bindingsById.removeValue(forKey: binding.identifier)
        Logger.shared.debug("Unregistered key combination '\(combination)'", subsystem: "Titik.Keymap")
    }

    public func find(combination: KeyCombination) -> KeyBinding? {
        lock.lock()
        defer { lock.unlock() }
        return bindingsByCombo[combination]
    }

    public func isRegistered(combination: KeyCombination) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return bindingsByCombo[combination] != nil
    }

    public func allBindings() -> [KeyBinding] {
        lock.lock()
        defer { lock.unlock() }
        return Array(bindingsByCombo.values)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        bindingsByCombo.removeAll()
        bindingsById.removeAll()
    }
}
