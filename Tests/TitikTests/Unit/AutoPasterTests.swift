import Foundation
import AppKit
import Testing
import TitikCore
import TitikUI
import TitikPlatform

@Suite("AutoPaster Tests")
@MainActor
struct AutoPasterTests {

    @Test("When accessibility checker returns false, pasteToActiveApp returns false and copies to pasteboard without hiding window")
    func testPasteToActiveAppWithoutAccessibility() {
        let originalChecker = AutoPaster.shared.accessibilityChecker
        defer { AutoPaster.shared.accessibilityChecker = originalChecker }

        AutoPaster.shared.accessibilityChecker = { false }

        let content = "test_untrusted_\(UUID().uuidString)"
        let result = AutoPaster.shared.pasteToActiveApp(content: content)

        #expect(!result)
        #expect(NSPasteboard.general.string(forType: .string) == content)
        #expect(ClipboardManager.shared.getItems().first?.content == content)
    }

    @Test("When accessibility checker returns true, pasteToActiveApp returns true and copies to pasteboard")
    func testPasteToActiveAppWithAccessibility() {
        let originalChecker = AutoPaster.shared.accessibilityChecker
        defer { AutoPaster.shared.accessibilityChecker = originalChecker }

        AutoPaster.shared.accessibilityChecker = { true }

        let content = "test_trusted_\(UUID().uuidString)"
        let result = AutoPaster.shared.pasteToActiveApp(content: content)

        #expect(result)
        #expect(NSPasteboard.general.string(forType: .string) == content)
        #expect(ClipboardManager.shared.getItems().first?.content == content)
    }

    @Test("UIOrchestrator retains activePluginUI and does not call reset when emoji selected without accessibility permission")
    func testEmojiSelectionWithoutAccessibility() {
        let originalChecker = AutoPaster.shared.accessibilityChecker
        defer { AutoPaster.shared.accessibilityChecker = originalChecker }

        AutoPaster.shared.accessibilityChecker = { false }

        let orchestrator = UIOrchestrator()
        orchestrator.performSearch("!emoji smile")

        #expect(orchestrator.activePluginUI != nil)

        let emoji = EmojiItem(emoji: "😄", name: "grinning face with smiling eyes", shortcode: ":smile:", category: .smileys, keywords: ["happy", "smile"])
        EmojiPlugin.shared.onSelectEmoji?(emoji)

        #expect(orchestrator.activePluginUI != nil)
        #expect(NSPasteboard.general.string(forType: .string) == "😄")
    }

    @Test("UIOrchestrator resets when emoji selected with accessibility permission")
    func testEmojiSelectionWithAccessibility() {
        let originalChecker = AutoPaster.shared.accessibilityChecker
        defer { AutoPaster.shared.accessibilityChecker = originalChecker }

        AutoPaster.shared.accessibilityChecker = { true }

        let orchestrator = UIOrchestrator()
        orchestrator.performSearch("!emoji smile")

        #expect(orchestrator.activePluginUI != nil)

        let emoji = EmojiItem(emoji: "😁", name: "beaming face", shortcode: ":grin:", category: .smileys, keywords: ["grin"])
        EmojiPlugin.shared.onSelectEmoji?(emoji)

        #expect(orchestrator.activePluginUI == nil)
        #expect(orchestrator.query.isEmpty)
        #expect(NSPasteboard.general.string(forType: .string) == "😁")
    }
}
