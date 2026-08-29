import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import TitikCore
import TitikUI

@MainActor
public final class AutoPaster {
    public static let shared = AutoPaster()

    public var lastActiveApplication: NSRunningApplication?
    public var accessibilityChecker: () -> Bool = { AXIsProcessTrusted() }

    public init(accessibilityChecker: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibilityChecker = accessibilityChecker
    }

    @discardableResult
    public func pasteToActiveApp(content: String) -> Bool {
        // 1. Set string on NSPasteboard.general
        ClipboardManager.shared.copyToPasteboard(content)

        guard accessibilityChecker() else {
            ToastManager.shared.show(
                message: "Copied \(content) to clipboard. Press ⌘V to paste.",
                icon: "doc.on.clipboard",
                type: .info
            )
            Logger.shared.warn(
                "Accessibility permission not granted; clipboard updated for manual Cmd+V",
                subsystem: "Titik.AutoPaster"
            )
            return false
        }

        // 2. Hide Titik window
        WindowController.shared.hideWindow()

        // 3. Re-activate target application
        if let targetApp = lastActiveApplication {
            targetApp.activate(options: .activateIgnoringOtherApps)
        }

        // 4. Synthesize Cmd+V after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.synthesizeCmdV()
        }
        return true
    }

    private func synthesizeCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Virtual key 0x09 is 'V' (kVK_ANSI_V)
        let vKeyCode: CGKeyCode = 0x09

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            Logger.shared.error("Failed to create CGEvent for paste synthesis", subsystem: "Titik.AutoPaster")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        Logger.shared.debug("Synthesized Cmd+V to active application", subsystem: "Titik.AutoPaster")
    }
}
