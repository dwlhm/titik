import Foundation
import Carbon
import TitikCore

/// A thread-safe global hotkey manager that coordinates multiple Carbon `EventHotKey` registrations,
/// dynamic re-binding, unregistration, conflict checking, and execution mode dispatching.
public final class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()

    private struct HotkeyRecord {
        let registration: RegisteredHotkey
        let hotKeyRef: EventHotKeyRef?
    }

    private let lock = NSLock()
    private var recordsByCarbonId: [UInt32: HotkeyRecord] = [:]
    private var carbonIdByIdentifier: [String: UInt32] = [:]
    private var carbonIdByCombination: [KeyCombination: UInt32] = [:]
    private var nextCarbonId: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    /// Carbon OSType signature for Titik ('TITK' = 0x5449544B).
    public let signature = OSType(0x5449544B)

    private struct CarbonRefBox<T>: @unchecked Sendable {
        let value: T
    }

    public init() {}

    @discardableResult
    private static func runOnMain<T: Sendable>(_ block: @Sendable () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync {
                block()
            }
        }
    }

    // MARK: - Registration APIs

    /// Registers a new global hotkey or updates an existing binding under the same identifier.
    ///
    /// - Parameters:
    ///   - identifier: Unique identifier for the hotkey action (e.g. "titik.toggle").
    ///   - combination: Key combination (modifiers + keycode).
    ///   - mode: Execution presentation mode (`.background` or `.palette`).
    ///   - handler: Closure to execute when the hotkey is triggered.
    /// - Returns: The allocated Carbon `UInt32` hotkey ID.
    /// - Throws: `KeymapError.duplicateBinding` if combination is already registered to a different identifier.
    @discardableResult
    public func register(
        identifier: String,
        combination: KeyCombination,
        mode: ShortcutExecutionMode = .background,
        handler: @escaping @Sendable () -> Void
    ) throws -> UInt32 {
        // 1. Check self internal combination registration
        lock.lock()
        if let existingId = carbonIdByCombination[combination],
           let existingRecord = recordsByCarbonId[existingId] {
            if existingRecord.registration.identifier != identifier {
                lock.unlock()
                throw KeymapError.duplicateBinding(combination: combination, existingIdentifier: existingRecord.registration.identifier)
            }
        }
        lock.unlock()

        // 2. Check and register with KeymapRegistry for conflict tracking
        try? KeymapRegistry.shared.register(
            combination: combination,
            identifier: identifier,
            mode: mode,
            action: handler
        )

        // 2. State setup under lock
        lock.lock()
        var oldRef: EventHotKeyRef?
        if let existingCarbonId = carbonIdByIdentifier[identifier],
           let oldRecord = recordsByCarbonId.removeValue(forKey: existingCarbonId) {
            carbonIdByCombination.removeValue(forKey: oldRecord.registration.combination)
            oldRef = oldRecord.hotKeyRef
        }

        let id = allocateNextCarbonIdLocked()
        let needsHandler = (eventHandlerRef == nil)
        lock.unlock()

        // 3. Unregister previous Carbon ref on main thread if present
        if let oldRef = oldRef {
            let refBox = CarbonRefBox(value: oldRef)
            Self.runOnMain {
                UnregisterEventHotKey(refBox.value)
            }
        }

        // 4. Ensure event handler installed on main thread
        var newHandlerRef: EventHandlerRef?
        if needsHandler {
            let selfPtrBox = CarbonRefBox(value: Unmanaged.passUnretained(self).toOpaque())
            let handlerBox = Self.runOnMain { () -> CarbonRefBox<EventHandlerRef?> in
                guard let target = GetApplicationEventTarget() else { return CarbonRefBox(value: nil) }
                var eventType = EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard),
                    eventKind: UInt32(kEventHotKeyPressed)
                )
                var handlerRef: EventHandlerRef?
                let status = InstallEventHandler(
                    target,
                    { (_, event, userData) -> OSStatus in
                        guard let userData = userData, let event = event else { return noErr }
                        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                        manager.handleHotKeyEvent(event)
                        return noErr
                    },
                    1,
                    &eventType,
                    selfPtrBox.value,
                    &handlerRef
                )
                if status != noErr {
                    Logger.shared.warn(
                        "InstallEventHandler returned status \(status) (may occur in headless/CI test environments)",
                        subsystem: "Titik.HotkeyManager"
                    )
                }
                return CarbonRefBox(value: handlerRef)
            }
            newHandlerRef = handlerBox.value
        }

        // 5. Register with Carbon EventHotKey API on main thread
        let carbonKey = combination.key.rawValue
        let carbonModifiers = combination.modifiers.carbonFlags
        let hotKeyID = EventHotKeyID(signature: signature, id: id)

        let (status, registeredRefBox) = Self.runOnMain { () -> (OSStatus, CarbonRefBox<EventHotKeyRef?>) in
            guard let target = GetApplicationEventTarget() else { return (OSStatus(-1), CarbonRefBox(value: nil)) }
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(
                carbonKey,
                carbonModifiers,
                hotKeyID,
                target,
                0,
                &ref
            )
            return (st, CarbonRefBox(value: ref))
        }
        let hotKeyRef = registeredRefBox.value

        if status != noErr {
            Logger.shared.warn(
                "RegisterEventHotKey returned status \(status) for '\(identifier)' (\(combination)). In-memory mapping active for headless/CI compatibility.",
                subsystem: "Titik.HotkeyManager"
            )
        }

        // 6. Record registration under lock
        lock.lock()
        if let installed = newHandlerRef, eventHandlerRef == nil {
            eventHandlerRef = installed
        }

        let registration = RegisteredHotkey(
            id: id,
            identifier: identifier,
            combination: combination,
            mode: mode,
            handler: handler
        )

        let record = HotkeyRecord(registration: registration, hotKeyRef: hotKeyRef)
        recordsByCarbonId[id] = record
        carbonIdByIdentifier[identifier] = id
        carbonIdByCombination[combination] = id
        lock.unlock()

        Logger.shared.info(
            "Registered global hotkey '\(identifier)' [id: \(id), combo: \(combination), mode: \(mode.rawValue)]",
            subsystem: "Titik.HotkeyManager"
        )

        return id
    }

    /// Dynamically updates an existing hotkey or registers it if absent.
    @discardableResult
    public func updateHotkey(
        identifier: String,
        combination: KeyCombination,
        mode: ShortcutExecutionMode = .background,
        handler: @escaping @Sendable () -> Void
    ) throws -> UInt32 {
        return try register(
            identifier: identifier,
            combination: combination,
            mode: mode,
            handler: handler
        )
    }

    // MARK: - Unregistration APIs

    /// Unregisters the hotkey bound to the specified identifier.
    public func unregister(identifier: String) {
        lock.lock()
        let oldRecord: HotkeyRecord?
        if let carbonId = carbonIdByIdentifier.removeValue(forKey: identifier) {
            oldRecord = recordsByCarbonId.removeValue(forKey: carbonId)
            if let record = oldRecord {
                carbonIdByCombination.removeValue(forKey: record.registration.combination)
            }
        } else {
            oldRecord = nil
        }
        lock.unlock()

        if let record = oldRecord, let ref = record.hotKeyRef {
            let refBox = CarbonRefBox(value: ref)
            Self.runOnMain {
                UnregisterEventHotKey(refBox.value)
            }
        }

        KeymapRegistry.shared.unregister(identifier: identifier)
        Logger.shared.info("Unregistered hotkey for identifier '\(identifier)'", subsystem: "Titik.HotkeyManager")
    }

    /// Unregisters the hotkey bound to the specified key combination.
    public func unregister(combination: KeyCombination) {
        lock.lock()
        let oldRecord: HotkeyRecord?
        if let carbonId = carbonIdByCombination.removeValue(forKey: combination) {
            oldRecord = recordsByCarbonId.removeValue(forKey: carbonId)
            if let record = oldRecord {
                carbonIdByIdentifier.removeValue(forKey: record.registration.identifier)
            }
        } else {
            oldRecord = nil
        }
        lock.unlock()

        if let record = oldRecord, let ref = record.hotKeyRef {
            let refBox = CarbonRefBox(value: ref)
            Self.runOnMain {
                UnregisterEventHotKey(refBox.value)
            }
        }

        KeymapRegistry.shared.unregister(combination: combination)
        Logger.shared.info("Unregistered hotkey for combination '\(combination)'", subsystem: "Titik.HotkeyManager")
    }

    /// Unregisters all registered hotkeys and clears all mappings.
    public func unregisterAll() {
        lock.lock()
        let records = Array(recordsByCarbonId.values)
        recordsByCarbonId.removeAll()
        carbonIdByIdentifier.removeAll()
        carbonIdByCombination.removeAll()
        lock.unlock()

        let refsBoxes = records.compactMap { $0.hotKeyRef.map { CarbonRefBox(value: $0) } }
        if !refsBoxes.isEmpty {
            Self.runOnMain {
                for box in refsBoxes {
                    UnregisterEventHotKey(box.value)
                }
            }
        }

        KeymapRegistry.shared.clear()
        Logger.shared.info("Unregistered all global hotkeys", subsystem: "Titik.HotkeyManager")
    }

    // MARK: - Introspection & Queries

    /// Returns whether a hotkey with the specified identifier is active.
    public func isRegistered(identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return carbonIdByIdentifier[identifier] != nil
    }

    /// Returns whether a hotkey with the specified key combination is active.
    public func isRegistered(combination: KeyCombination) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return carbonIdByCombination[combination] != nil
    }

    /// Returns all currently registered active hotkeys.
    public var activeRegistrations: [RegisteredHotkey] {
        lock.lock()
        defer { lock.unlock() }
        return recordsByCarbonId.values.map(\.registration)
    }

    /// Looks up registration metadata by identifier.
    public func registration(for identifier: String) -> RegisteredHotkey? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = carbonIdByIdentifier[identifier] else { return nil }
        return recordsByCarbonId[id]?.registration
    }

    /// Looks up registration metadata by Carbon ID.
    public func registration(for id: UInt32) -> RegisteredHotkey? {
        lock.lock()
        defer { lock.unlock() }
        return recordsByCarbonId[id]?.registration
    }

    /// Looks up registration metadata by key combination.
    public func registration(for combination: KeyCombination) -> RegisteredHotkey? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = carbonIdByCombination[combination] else { return nil }
        return recordsByCarbonId[id]?.registration
    }

    // MARK: - Trigger & Dispatch

    /// Programmatically triggers the action registered for an identifier.
    @discardableResult
    public func trigger(identifier: String) -> Bool {
        lock.lock()
        guard let id = carbonIdByIdentifier[identifier],
              let record = recordsByCarbonId[id] else {
            lock.unlock()
            return false
        }
        let registration = record.registration
        lock.unlock()

        dispatchRegistration(registration)
        return true
    }

    /// Programmatically triggers the action registered for a Carbon ID.
    @discardableResult
    public func trigger(id: UInt32) -> Bool {
        lock.lock()
        guard let record = recordsByCarbonId[id] else {
            lock.unlock()
            return false
        }
        let registration = record.registration
        lock.unlock()

        dispatchRegistration(registration)
        return true
    }

    /// Carbon event callback processor.
    public func handleHotKeyEvent(_ event: EventRef?) {
        guard let event = event else { return }
        var hkID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hkID
        )

        guard status == noErr, hkID.signature == signature else { return }

        lock.lock()
        guard let record = recordsByCarbonId[hkID.id] else {
            lock.unlock()
            return
        }
        let registration = record.registration
        lock.unlock()

        Logger.shared.debug(
            "Carbon hotkey triggered: '\(registration.identifier)' [id: \(hkID.id), mode: \(registration.mode.rawValue)]",
            subsystem: "Titik.HotkeyManager"
        )

        dispatchRegistration(registration)
    }

    private func dispatchRegistration(_ registration: RegisteredHotkey) {
        switch registration.mode {
        case .palette:
            DispatchQueue.main.async {
                registration.handler()
            }
        case .background:
            DispatchQueue.global(qos: .userInitiated).async {
                registration.handler()
            }
        }
    }

    // MARK: - Private Helpers

    private func allocateNextCarbonIdLocked() -> UInt32 {
        var id = nextCarbonId
        while recordsByCarbonId[id] != nil || id == 0 {
            nextCarbonId = nextCarbonId &+ 1
            if nextCarbonId == 0 { nextCarbonId = 1 }
            id = nextCarbonId
        }
        nextCarbonId = nextCarbonId &+ 1
        return id
    }

    // MARK: - Backward Compatibility APIs

    /// Legacy toggle registration helper for single hotkey callers.
    @discardableResult
    public func registerHotkey(
        combination: KeyCombination,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        do {
            _ = try register(
                identifier: "global.hotkey.toggle",
                combination: combination,
                mode: .palette,
                handler: handler
            )
            return true
        } catch {
            Logger.shared.error("Failed to register toggle hotkey: \(error)", subsystem: "Titik.HotkeyManager")
            return false
        }
    }

    /// Legacy unregistration helper.
    public func unregisterHotkey() {
        unregister(identifier: "global.hotkey.toggle")
    }

    /// Legacy string modifier + key helper.
    @discardableResult
    public func updateHotkey(
        modifier: String,
        key: String,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        guard let keycode = Keycode.fromString(key) else {
            Logger.shared.warn("Invalid hotkey key: '\(key)'", subsystem: "Titik.HotkeyManager")
            return false
        }
        let mod = KeyModifier.fromString(modifier)
        let combo = KeyCombination(modifiers: mod, key: keycode)
        return registerHotkey(combination: combo, handler: handler)
    }

    deinit {
        unregisterAll()
        lock.lock()
        let handlerRef = eventHandlerRef
        eventHandlerRef = nil
        lock.unlock()

        if let handlerRef = handlerRef {
            let handlerBox = CarbonRefBox(value: handlerRef)
            Self.runOnMain {
                RemoveEventHandler(handlerBox.value)
            }
        }
    }
}
