import Foundation
import Carbon
import TitikCore

public final class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyHandler: (@Sendable () -> Void)?
    private var currentCombination: KeyCombination?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x5449544B), id: 1) // 'TITK', 1

    public init() {}

    public func registerHotkey(
        combination: KeyCombination,
        handler: @escaping @Sendable () -> Void
    ) -> Bool {
        unregisterHotkey()

        self.hotkeyHandler = handler
        self.currentCombination = combination

        // Register with KeymapRegistry for conflict tracking
        try? KeymapRegistry.shared.register(
            combination: combination,
            identifier: "global.hotkey.toggle",
            action: handler
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            Logger.shared.error("Failed to install Carbon event handler: \(status)", subsystem: "Titik.HotkeyManager")
            return false
        }

        let carbonKey = combination.key.rawValue
        let carbonModifiers = combination.modifiers.carbonFlags

        let registerStatus = RegisterEventHotKey(
            carbonKey,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            Logger.shared.error("Failed to register Carbon EventHotKey (status: \(registerStatus))", subsystem: "Titik.HotkeyManager")
            return false
        }

        Logger.shared.info("Global hotkey registered: \(combination)", subsystem: "Titik.HotkeyManager")
        return true
    }

    public func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        if let combo = currentCombination {
            KeymapRegistry.shared.unregister(combination: combo)
            currentCombination = nil
        }
        hotkeyHandler = nil
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
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

        if status == noErr && hkID.id == hotKeyID.id && hkID.signature == hotKeyID.signature {
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyHandler?()
            }
        }
    }

    public func updateHotkey(modifier: String, key: String, handler: @escaping @Sendable () -> Void) -> Bool {
        guard let keycode = Keycode.fromString(key) else {
            Logger.shared.warn("Invalid hotkey key: '\(key)'", subsystem: "Titik.HotkeyManager")
            return false
        }
        let mod = KeyModifier.fromString(modifier)
        let combo = KeyCombination(modifiers: mod, key: keycode)
        return registerHotkey(combination: combo, handler: handler)
    }

    deinit {
        unregisterHotkey()
    }
}
