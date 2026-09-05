import Foundation
import AppKit
import Testing
import TitikCore
import TitikUI
import TitikPlatform

@Suite("ToastManager Tests")
@MainActor
struct ToastManagerTests {

    @Test("ToastManager.shared.show sets currentToast with expected message, icon, type, duration")
    func testToastManagerShow() {
        ToastManager.shared.dismiss()
        #expect(ToastManager.shared.currentToast == nil)

        let msg = "Test message"
        let icon = "star.fill"
        ToastManager.shared.show(message: msg, icon: icon, type: .success, duration: 1.0)

        #expect(ToastManager.shared.currentToast != nil)
        #expect(ToastManager.shared.currentToast?.message == msg)
        #expect(ToastManager.shared.currentToast?.icon == icon)
        #expect(ToastManager.shared.currentToast?.type == .success)
        #expect(ToastManager.shared.currentToast?.duration == 1.0)
    }

    @Test("ToastManager.shared.dismiss sets currentToast to nil")
    func testToastManagerDismiss() {
        ToastManager.shared.show(message: "Will dismiss", icon: "xmark", type: .warning)
        #expect(ToastManager.shared.currentToast != nil)

        ToastManager.shared.dismiss()
        #expect(ToastManager.shared.currentToast == nil)
    }

    @Test("AutoPaster triggers ToastManager.shared.show with expected text when accessibilityChecker is false")
    func testAutoPasterTriggersToastOnAccessibilityFailure() {
        ToastManager.shared.dismiss()
        let originalChecker = AutoPaster.shared.accessibilityChecker
        defer {
            AutoPaster.shared.accessibilityChecker = originalChecker
            ToastManager.shared.dismiss()
        }

        AutoPaster.shared.accessibilityChecker = { false }

        let emoji = "🚀"
        let result = AutoPaster.shared.pasteToActiveApp(content: emoji)

        #expect(!result)
        #expect(ToastManager.shared.currentToast != nil)
        #expect(ToastManager.shared.currentToast?.message == "Copied \(emoji) to clipboard. Press ⌘V to paste.")
        #expect(ToastManager.shared.currentToast?.icon == "doc.on.clipboard")
        #expect(ToastManager.shared.currentToast?.type == .info)
    }
}
