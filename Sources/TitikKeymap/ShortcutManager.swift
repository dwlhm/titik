import Foundation
import TitikCore

/// A central manager coordinating user-defined hotkey shortcuts, persistence to config.json,
/// conflict detection, and runtime dispatching.
@MainActor
public final class ShortcutManager: ObservableObject {
    public static let shared = ShortcutManager()

    @Published public var shortcuts: [ShortcutConfig] = []
    public var dispatcher: (@Sendable (String) -> Void)?
    public let configLoader: ConfigLoader
    public private(set) var registeredShortcutIds: Set<String> = []

    public init(configLoader: ConfigLoader = .shared) {
        self.configLoader = configLoader
        loadShortcuts()
    }

    /// Loads shortcuts from the currently active configuration.
    public func loadShortcuts() {
        self.shortcuts = configLoader.currentConfig.shortcuts
    }

    /// Adds a new shortcut binding, saves configuration, and registers the global hotkey.
    /// Transactional: Registers with HotkeyManager first; rolls back if persistence fails.
    /// - Parameter shortcut: The shortcut configuration to add.
    /// - Throws: `KeymapError.invalidCombination` or `KeymapError.duplicateBinding` if invalid or conflicting.
    public func addShortcut(_ shortcut: ShortcutConfig) throws {
        guard let combination = parseCombination(from: shortcut) else {
            throw KeymapError.invalidCombination(shortcut.keyCombinationString)
        }

        let duplicateCheck = isDuplicate(combination: combination)
        if duplicateCheck.isDuplicate {
            let existing = duplicateCheck.existingCommand ?? "existing shortcut"
            throw KeymapError.duplicateBinding(combination: combination, existingIdentifier: existing)
        }

        let currentDispatcher = self.dispatcher
        try HotkeyManager.shared.register(
            identifier: shortcut.id,
            combination: combination,
            mode: shortcut.mode ?? .background
        ) {
            currentDispatcher?(shortcut.action.target)
        }

        let originalShortcuts = shortcuts
        shortcuts.append(shortcut)
        configLoader.currentConfig.shortcuts = shortcuts
        do {
            try configLoader.save()
            registeredShortcutIds.insert(shortcut.id)
            Logger.shared.info("Added shortcut '\(shortcut.id)' (\(combination)) -> '\(shortcut.action.target)'", subsystem: "Titik.ShortcutManager")
        } catch {
            HotkeyManager.shared.unregister(combination: combination)
            HotkeyManager.shared.unregister(identifier: shortcut.id)
            shortcuts = originalShortcuts
            configLoader.currentConfig.shortcuts = originalShortcuts
            throw error
        }
    }

    /// Updates an existing shortcut binding by ID, saves configuration, and updates global hotkey registration.
    /// Transactional: Unregisters old binding, registers new binding, and rolls back if persistence fails.
    /// - Parameters:
    ///   - id: The unique ID of the shortcut to update.
    ///   - updated: The new shortcut configuration payload.
    /// - Throws: `KeymapError.notFound`, `KeymapError.invalidCombination`, or `KeymapError.duplicateBinding`.
    public func updateShortcut(id: String, updated: ShortcutConfig) throws {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else {
            throw KeymapError.notFound(identifier: id)
        }

        guard let newCombination = parseCombination(from: updated) else {
            throw KeymapError.invalidCombination(updated.keyCombinationString)
        }

        let duplicateCheck = isDuplicate(combination: newCombination, ignoringId: id)
        if duplicateCheck.isDuplicate {
            let existing = duplicateCheck.existingCommand ?? "existing shortcut"
            throw KeymapError.duplicateBinding(combination: newCombination, existingIdentifier: existing)
        }

        let oldShortcut = shortcuts[index]
        let oldCombination = parseCombination(from: oldShortcut)

        // Unregister old binding
        if let oldCombo = oldCombination {
            HotkeyManager.shared.unregister(combination: oldCombo)
        }
        HotkeyManager.shared.unregister(identifier: oldShortcut.id)
        registeredShortcutIds.remove(oldShortcut.id)

        // Register new binding
        let currentDispatcher = self.dispatcher
        do {
            try HotkeyManager.shared.register(
                identifier: updated.id,
                combination: newCombination,
                mode: updated.mode ?? .background
            ) {
                currentDispatcher?(updated.action.target)
            }
        } catch {
            // Rollback: restore old registration
            if let oldCombo = oldCombination {
                _ = try? HotkeyManager.shared.register(
                    identifier: oldShortcut.id,
                    combination: oldCombo,
                    mode: oldShortcut.mode ?? .background
                ) {
                    currentDispatcher?(oldShortcut.action.target)
                }
                registeredShortcutIds.insert(oldShortcut.id)
            }
            throw error
        }

        let originalShortcuts = shortcuts
        shortcuts[index] = updated
        configLoader.currentConfig.shortcuts = shortcuts
        do {
            try configLoader.save()
            registeredShortcutIds.insert(updated.id)
            Logger.shared.info("Updated shortcut '\(id)' to combo \(newCombination) -> '\(updated.action.target)'", subsystem: "Titik.ShortcutManager")
        } catch {
            // Rollback: unregister new and restore old
            HotkeyManager.shared.unregister(combination: newCombination)
            HotkeyManager.shared.unregister(identifier: updated.id)
            registeredShortcutIds.remove(updated.id)

            if let oldCombo = oldCombination {
                _ = try? HotkeyManager.shared.register(
                    identifier: oldShortcut.id,
                    combination: oldCombo,
                    mode: oldShortcut.mode ?? .background
                ) {
                    currentDispatcher?(oldShortcut.action.target)
                }
                registeredShortcutIds.insert(oldShortcut.id)
            }
            shortcuts = originalShortcuts
            configLoader.currentConfig.shortcuts = originalShortcuts
            throw error
        }
    }

    /// Deletes a shortcut binding by ID, unregisters the hotkey, and persists the configuration.
    /// - Parameter id: The unique ID of the shortcut to remove.
    public func deleteShortcut(id: String) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let shortcut = shortcuts[index]
        if let combo = parseCombination(from: shortcut) {
            HotkeyManager.shared.unregister(combination: combo)
        }
        HotkeyManager.shared.unregister(identifier: shortcut.id)
        registeredShortcutIds.remove(shortcut.id)

        shortcuts.remove(at: index)
        configLoader.currentConfig.shortcuts = shortcuts
        try? configLoader.save()

        Logger.shared.info("Deleted shortcut '\(id)'", subsystem: "Titik.ShortcutManager")
    }

    /// Reloads shortcuts from configuration and resynchronizes global hotkeys on demand.
    /// - Parameter config: Optional updated configuration; if nil, loads from configLoader.
    public func reloadFromConfig(_ config: Config? = nil) {
        // 1. Unregister all previously registered shortcuts to prevent orphans
        for id in registeredShortcutIds {
            HotkeyManager.shared.unregister(identifier: id)
        }
        for sc in shortcuts {
            if let combo = parseCombination(from: sc) {
                HotkeyManager.shared.unregister(combination: combo)
            }
            HotkeyManager.shared.unregister(identifier: sc.id)
        }
        registeredShortcutIds.removeAll()

        // 2. Load shortcuts
        if let cfg = config {
            self.shortcuts = cfg.shortcuts
        } else {
            let loaded = configLoader.load()
            self.shortcuts = loaded.shortcuts
        }

        // 3. Register hotkeys
        let currentDispatcher = self.dispatcher
        for shortcut in shortcuts {
            guard let combination = parseCombination(from: shortcut) else {
                Logger.shared.warn("Invalid shortcut combination '\(shortcut.keyCombinationString)' for '\(shortcut.id)'", subsystem: "Titik.ShortcutManager")
                continue
            }

            do {
                try HotkeyManager.shared.register(
                    identifier: shortcut.id,
                    combination: combination,
                    mode: shortcut.mode ?? .background
                ) {
                    currentDispatcher?(shortcut.action.target)
                }
                registeredShortcutIds.insert(shortcut.id)
            } catch {
                Logger.shared.warn("Failed to register shortcut '\(shortcut.id)': \(error)", subsystem: "Titik.ShortcutManager")
            }
        }

        Logger.shared.info("Reloaded \(shortcuts.count) shortcuts into ShortcutManager", subsystem: "Titik.ShortcutManager")
    }

    /// Synchronizes all shortcuts from configuration, registering each with HotkeyManager.
    /// - Parameter dispatcher: Callback to invoke when a shortcut is triggered with its target query string.
    public func syncAllShortcuts(dispatcher: @escaping @Sendable (String) -> Void) {
        self.dispatcher = dispatcher
        var config = configLoader.load()
        if config.shortcuts.isEmpty && !self.shortcuts.isEmpty {
            config.shortcuts = self.shortcuts
        } else {
            self.shortcuts = config.shortcuts
        }
        reloadFromConfig(config)
    }

    /// Checks if a key combination is already bound to another shortcut or system hotkey.
    /// Resolves duplicate IDs to their command names or target strings for clear feedback.
    /// - Parameters:
    ///   - combination: The key combination to test.
    ///   - ignoringId: Optional shortcut ID to exclude from conflict checking.
    /// - Returns: Tuple indicating whether duplicate exists and existing command/action string if found.
    public func isDuplicate(combination: KeyCombination, ignoringId: String? = nil) -> (isDuplicate: Bool, existingCommand: String?) {
        // Check KeymapRegistry bindings
        if let binding = KeymapRegistry.shared.find(combination: combination) {
            if let ignoringId = ignoringId {
                if binding.identifier != ignoringId && binding.identifier != "shortcut:\(ignoringId)" {
                    let name = resolveDisplayName(for: binding.identifier)
                    return (true, name)
                }
            } else {
                let name = resolveDisplayName(for: binding.identifier)
                return (true, name)
            }
        }

        // Check active in-memory shortcuts
        for sc in shortcuts {
            if let scCombo = parseCombination(from: sc), scCombo == combination {
                if let ignoringId = ignoringId, sc.id == ignoringId {
                    continue
                }
                let desc: String
                if let name = sc.name, !name.isEmpty {
                    desc = name
                } else if !sc.action.target.isEmpty {
                    desc = sc.action.target
                } else {
                    desc = sc.keyCombinationString
                }
                return (true, desc)
            }
        }

        return (false, nil)
    }

    private func resolveDisplayName(for identifier: String) -> String {
        let cleanId = identifier.hasPrefix("shortcut:") ? String(identifier.dropFirst(9)) : identifier
        if let match = shortcuts.first(where: { $0.id == cleanId || $0.id == identifier }) {
            if let name = match.name, !name.isEmpty {
                return name
            }
            if !match.action.target.isEmpty {
                return match.action.target
            }
        }
        return identifier
    }

    /// Parses a KeyCombination from a ShortcutConfig model.
    public func parseCombination(from shortcut: ShortcutConfig) -> KeyCombination? {
        if let combo = KeyCombination(string: shortcut.keyCombinationString) {
            return combo
        }
        if let keycode = Keycode.fromString(shortcut.key) {
            let mods = KeyModifier.fromString(shortcut.modifiers.joined(separator: "+"))
            return KeyCombination(modifiers: mods, key: keycode)
        }
        return nil
    }
}
