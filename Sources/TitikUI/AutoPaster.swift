import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import TitikCore

/// Automated pasteboard transfer coordinator that injects text into previously active applications.
///
/// `AutoPaster` coordinates transferring generated or selected content (e.g. emoji, snippets, notes)
/// directly into the user's previously focused application.
///
/// ### Key Responsibilities & Behaviors:
/// - **Automated Pasteboard Transfers via CGEvent**: Copies content to the system pasteboard (`NSPasteboard.general`)
///   via `ClipboardManager`, re-activates the target `NSRunningApplication`, and synthesizes a synthetic
///   `⌘V` key sequence using CoreGraphics `CGEvent` posted to the `.cghidEventTap`.
/// - **Graceful Fallback When Accessibility Permission Is Missing**: When macOS Accessibility (`AXIsProcessTrusted`)
///   is not granted, `AutoPaster` avoids failing silently or attempting restricted event posting. Instead, it copies
///   the text to the clipboard and displays an informative toast notification prompting the user to press `⌘V` manually.
/// - **Decoupled Window Closure**: Window dismissal is decoupled through the injectable `windowCloser` closure,
///   enabling seamless hiding of the Titik UI across window management architectures and headless unit test environments.
@MainActor
public final class AutoPaster {
    /// Shared singleton instance.
    public static let shared = AutoPaster()

    /// The application that was active prior to opening the Titik palette HUD.
    public var lastActiveApplication: NSRunningApplication?

    /// Closure used to query macOS Accessibility permissions. Defaults to `AXIsProcessTrusted()`.
    public var accessibilityChecker: () -> Bool = { AXIsProcessTrusted() }

    /// Decoupled window dismissal closure invoked before re-activating the target application.
    public var windowCloser: (@MainActor () -> Void)? = { NSApp.keyWindow?.orderOut(nil) }

    /// Initializes an `AutoPaster` instance with an optional custom accessibility check closure.
    /// - Parameter accessibilityChecker: Closure returning whether the process has accessibility permissions.
    public init(accessibilityChecker: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibilityChecker = accessibilityChecker
    }

    /// Transfers content to the pasteboard and automatically pastes it into the last active application.
    ///
    /// If accessibility permissions are granted, closes the Titik window, reactivates `lastActiveApplication`,
    /// and synthesizes a `⌘V` key-down/key-up event after a 100ms delay.
    ///
    /// If accessibility permissions are missing, retains the content on the pasteboard and displays
    /// a guidance toast instructing the user to paste manually.
    ///
    /// - Parameter content: The text string to transfer and paste.
    /// - Returns: `true` if automated paste synthesis was initiated; `false` if accessibility permissions
    ///   were missing and the manual copy fallback was used.
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
        if let closer = windowCloser {
            closer()
        } else {
            NSApp.keyWindow?.orderOut(nil)
        }

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
