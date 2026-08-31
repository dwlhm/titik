import SwiftUI
import Testing
@testable import TitikPluginKit

@Suite("TitikPluginKit UI Components Suite Tests")
@MainActor
struct ComponentSuiteTests {

    @Test("TitikStatusBadge parses status strings and styles accurately")
    func test_statusBadge_parsing() {
        let connectedBadge = TitikStatusBadge(statusMessage: "🟢 Connected (Ready)")
        #expect(connectedBadge.style.color == .green)
        #expect(!connectedBadge.isTesting)

        let offlineBadge = TitikStatusBadge(statusMessage: "🔴 Offline: Network failure")
        #expect(offlineBadge.style.color == .red)
        #expect(!offlineBadge.isTesting)

        let testingBadge = TitikStatusBadge(statusMessage: "🟡 Testing connection...")
        #expect(testingBadge.style.color == .yellow)
        #expect(testingBadge.isTesting)
    }

    @Test("TitikSegmentedPillBar instantiates with generic items")
    func test_segmentedPillBar_initialization() {
        enum Tab: String, CaseIterable, Identifiable, Sendable {
            case general = "General"
            case advanced = "Advanced"

            var id: String { rawValue }
        }

        var selectedTab = Tab.general
        let binding = Binding(get: { selectedTab }, set: { selectedTab = $0 })

        let pillBar = TitikSegmentedPillBar(
            items: Tab.allCases,
            selection: binding,
            title: { $0.rawValue },
            iconName: { _ in "gear" }
        )

        #expect(pillBar.items.count == 2)
        #expect(pillBar.title(Tab.general) == "General")
        #expect(pillBar.iconName?(Tab.advanced) == "gear")
    }

    @Test("TitikFormField and TitikSecureField configure properly")
    func test_formField_initialization() {
        var textVal = "secret"
        let binding = Binding(get: { textVal }, set: { textVal = $0 })

        let formField = TitikFormField(
            label: "API Key:",
            placeholder: "Enter key",
            text: binding,
            isSecure: true,
            isMonospaced: true,
            helperLinkLabel: "Get Key",
            helperLinkURL: URL(string: "https://example.com")
        )

        #expect(formField.label == "API Key:")
        #expect(formField.placeholder == "Enter key")
        #expect(formField.isSecure == true)
        #expect(formField.isMonospaced == true)
        #expect(formField.helperLinkLabel == "Get Key")
    }

    @Test("TitikChipGroup initializes with chips")
    func test_chipGroup_initialization() {
        var selectedChip: String? = nil
        let chips = ["Item 1", "Item 2", "Item 3"]

        let chipGroup = TitikChipGroup(
            title: "Quick Prompts",
            chips: chips,
            onSelect: { selectedChip = $0 }
        )

        #expect(chipGroup.title == "Quick Prompts")
        #expect(chipGroup.chips.count == 3)
        chipGroup.onSelect("Item 2")
        #expect(selectedChip == "Item 2")
    }
}
