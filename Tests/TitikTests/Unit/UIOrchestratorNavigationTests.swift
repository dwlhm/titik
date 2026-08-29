import Testing
import Foundation
import TitikCore
import TitikPlatform

@Suite("UIOrchestrator Navigation Tests")
@MainActor
struct UIOrchestratorNavigationTests {

    @Test("Arrow navigation bounds and clamping")
    func testArrowNavigationBounds() {
        let orchestrator = UIOrchestrator()
        let items = [
            SearchItem(id: "1", title: "First Item", subtitle: "Sub 1", category: .application),
            SearchItem(id: "2", title: "Second Item", subtitle: "Sub 2", category: .application),
            SearchItem(id: "3", title: "Third Item", subtitle: "Sub 3", category: .application)
        ]
        orchestrator.results = items
        orchestrator.selectedIndex = 0

        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.id == "1")

        // Navigate forward
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.id == "2")

        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 2)
        #expect(orchestrator.selectedItem?.id == "3")

        // Clamp at results.count - 1
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 2)
        #expect(orchestrator.selectedItem?.id == "3")

        // Navigate backward
        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.id == "2")

        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.id == "1")

        // Clamp at 0
        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.id == "1")

        // Empty results edge case
        orchestrator.results = []
        orchestrator.selectedIndex = 0
        orchestrator.selectNext()
        orchestrator.selectPrevious()
        #expect(orchestrator.selectedItem == nil)
    }

    @Test("Navigation across preview state transitions")
    func testNavigationAcrossPreviewStateTransitions() {
        let orchestrator = UIOrchestrator()
        let item1 = SearchItem(
            id: "app-1",
            title: "Terminal",
            subtitle: "Application",
            category: .application,
            previewType: .none
        )
        let item2 = SearchItem(
            id: "file-img",
            title: "photo.png",
            subtitle: "~/Pictures/photo.png",
            category: .file,
            previewType: .image(URL(fileURLWithPath: "/tmp/photo.png"))
        )
        let item3 = SearchItem(
            id: "cmd-1",
            title: "Lock Screen",
            subtitle: "System Command",
            category: .systemCommand,
            previewType: .none
        )
        let item4 = SearchItem(
            id: "file-code",
            title: "main.swift",
            subtitle: "~/Projects/main.swift",
            category: .file,
            previewType: .code(URL(fileURLWithPath: "/tmp/main.swift"), language: "swift")
        )

        orchestrator.results = [item1, item2, item3, item4]
        orchestrator.selectedIndex = 0

        // Step 0: Non-rich item (app)
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.id == "app-1")
        #expect(orchestrator.selectedItem?.hasRichPreview == false)

        // Step 1: Rich preview item (image)
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.id == "file-img")
        #expect(orchestrator.selectedItem?.hasRichPreview == true)

        // Step 2: Non-rich item (command)
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 2)
        #expect(orchestrator.selectedItem?.id == "cmd-1")
        #expect(orchestrator.selectedItem?.hasRichPreview == false)

        // Step 3: Rich preview item (code)
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 3)
        #expect(orchestrator.selectedItem?.id == "file-code")
        #expect(orchestrator.selectedItem?.hasRichPreview == true)

        // Step 4: Reverse to non-rich item (command)
        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 2)
        #expect(orchestrator.selectedItem?.id == "cmd-1")
        #expect(orchestrator.selectedItem?.hasRichPreview == false)

        // Step 5: Reverse to rich item (image)
        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.id == "file-img")
        #expect(orchestrator.selectedItem?.hasRichPreview == true)
    }

    @Test("Query change resets selection index")
    func testQueryResetSelection() {
        let orchestrator = UIOrchestrator()
        orchestrator.results = [
            SearchItem(id: "1", title: "App A", subtitle: "", category: .application),
            SearchItem(id: "2", title: "App B", subtitle: "", category: .application),
            SearchItem(id: "3", title: "App C", subtitle: "", category: .application)
        ]
        orchestrator.selectedIndex = 2
        #expect(orchestrator.selectedIndex == 2)

        // Changing query invokes performSearch which resets selectedIndex to 0
        orchestrator.query = "app:"
        #expect(orchestrator.selectedIndex == 0)
    }

    @Test("Mixed preview types sequential navigation and state stability")
    func testMixedPreviewTypesSequentialNavigation() {
        let orchestrator = UIOrchestrator()
        let items = [
            SearchItem(id: "app-1", title: "Safari", subtitle: "Application", category: .application, previewType: .none),
            SearchItem(id: "img-1", title: "logo.png", subtitle: "~/logo.png", category: .file, previewType: .image(URL(fileURLWithPath: "/tmp/logo.png"))),
            SearchItem(id: "calc-1", title: "42", subtitle: "Calculation", category: .calculator, previewType: .none),
            SearchItem(id: "pdf-1", title: "manual.pdf", subtitle: "~/manual.pdf", category: .file, previewType: .pdf(URL(fileURLWithPath: "/tmp/manual.pdf"))),
            SearchItem(id: "clip-1", title: "Copied text", subtitle: "Clipboard", category: .clipboard, previewType: .custom(detail: "Copied text content")),
            SearchItem(id: "dir-1", title: "Projects", subtitle: "~/Projects", category: .directory, previewType: .directory(URL(fileURLWithPath: "/tmp/Projects"), itemCount: 5))
        ]
        orchestrator.results = items
        orchestrator.selectedIndex = 0

        let expectedPreviews = [false, true, false, true, true, true]

        for i in 0..<items.count {
            #expect(orchestrator.selectedIndex == i)
            #expect(orchestrator.selectedItem?.id == items[i].id)
            #expect(orchestrator.selectedItem?.hasRichPreview == expectedPreviews[i])
            if i < items.count - 1 {
                orchestrator.selectNext()
            }
        }

        // Navigate backwards
        for i in stride(from: items.count - 1, through: 0, by: -1) {
            #expect(orchestrator.selectedIndex == i)
            #expect(orchestrator.selectedItem?.id == items[i].id)
            #expect(orchestrator.selectedItem?.hasRichPreview == expectedPreviews[i])
            if i > 0 {
                orchestrator.selectPrevious()
            }
        }
    }

    @Test("Results replacement preserves view model stability")
    func testResultsReplacementStability() {
        let orchestrator = UIOrchestrator()
        let initialItems = [
            SearchItem(id: "1", title: "Item 1", subtitle: "", category: .application),
            SearchItem(id: "2", title: "Item 2", subtitle: "", category: .file, previewType: .image(URL(fileURLWithPath: "/tmp/2.png"))),
            SearchItem(id: "3", title: "Item 3", subtitle: "", category: .application)
        ]
        orchestrator.results = initialItems
        orchestrator.selectedIndex = 2
        #expect(orchestrator.selectedItem?.id == "3")
        #expect(orchestrator.selectedItem?.hasRichPreview == false)

        // New search results
        let newItems = [
            SearchItem(id: "10", title: "New 1", subtitle: "", category: .file, previewType: .code(URL(fileURLWithPath: "/tmp/main.swift"), language: "swift")),
            SearchItem(id: "11", title: "New 2", subtitle: "", category: .application)
        ]
        orchestrator.results = newItems
        orchestrator.selectedIndex = 0

        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.id == "10")
        #expect(orchestrator.selectedItem?.hasRichPreview == true)

        // Navigate to second
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.id == "11")
        #expect(orchestrator.selectedItem?.hasRichPreview == false)
    }

    @Test("Rapid multi-step navigation and clamping under repeated key strokes")
    func testRapidMultiStepNavigation() {
        let orchestrator = UIOrchestrator()
        let items = (0..<50).map { i in
            SearchItem(id: "item-\(i)", title: "Item \(i)", subtitle: "Sub \(i)", category: .application)
        }
        orchestrator.results = items
        orchestrator.selectedIndex = 0

        // Rapid forward navigation (e.g. holding down arrow key)
        for _ in 0..<30 {
            orchestrator.selectNext()
        }
        #expect(orchestrator.selectedIndex == 30)
        #expect(orchestrator.selectedItem?.id == "item-30")

        // Rapid forward beyond bounds
        for _ in 0..<30 {
            orchestrator.selectNext()
        }
        #expect(orchestrator.selectedIndex == 49)
        #expect(orchestrator.selectedItem?.id == "item-49")

        // Rapid backward navigation
        for _ in 0..<20 {
            orchestrator.selectPrevious()
        }
        #expect(orchestrator.selectedIndex == 29)
        #expect(orchestrator.selectedItem?.id == "item-29")

        // Rapid backward beyond top
        for _ in 0..<50 {
            orchestrator.selectPrevious()
        }
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.id == "item-0")
    }

    @Test("Boundary bounce at top edge")
    func testBoundaryBounceAtTop() {
        let orchestrator = UIOrchestrator()
        let items = [
            SearchItem(id: "1", title: "Item 1", subtitle: "", category: .application),
            SearchItem(id: "2", title: "Item 2", subtitle: "", category: .application)
        ]
        orchestrator.results = items
        orchestrator.selectedIndex = 0
        orchestrator.boundaryBounceOffset = 0

        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.boundaryBounceOffset > 0)
    }

    @Test("Boundary bounce at bottom edge")
    func testBoundaryBounceAtBottom() {
        let orchestrator = UIOrchestrator()
        let items = [
            SearchItem(id: "1", title: "Item 1", subtitle: "", category: .application),
            SearchItem(id: "2", title: "Item 2", subtitle: "", category: .application)
        ]
        orchestrator.results = items
        orchestrator.selectedIndex = 1
        orchestrator.boundaryBounceOffset = 0

        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.boundaryBounceOffset < 0)
    }

    @Test("No boundary bounce during intermediate navigation")
    func testNoBoundaryBounceDuringIntermediateNavigation() {
        let orchestrator = UIOrchestrator()
        let items = [
            SearchItem(id: "1", title: "Item 1", subtitle: "", category: .application),
            SearchItem(id: "2", title: "Item 2", subtitle: "", category: .application),
            SearchItem(id: "3", title: "Item 3", subtitle: "", category: .application)
        ]
        orchestrator.results = items
        orchestrator.selectedIndex = 0
        orchestrator.boundaryBounceOffset = 0

        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.boundaryBounceOffset == 0)

        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.boundaryBounceOffset == 0)
    }

    @Test("Execute selected bang emoji item sets query and activates plugin without closing window")
    func testExecuteSelectedBangEmojiNavigates() {
        let orchestrator = UIOrchestrator()
        let bangEmojiItem = SearchItem(
            id: "bang:emoji",
            title: "!emoji",
            subtitle: "Search & paste emojis with interactive grid",
            category: .emoji,
            score: 100,
            actionPayload: "!emoji "
        )
        orchestrator.results = [bangEmojiItem]
        orchestrator.selectedIndex = 0

        orchestrator.executeSelected()

        #expect(orchestrator.query == "!emoji ")
        #expect(orchestrator.activePluginUI != nil)
    }

    @Test("Space-delimited plugin activation and uncommitted prefix suggestions in UIOrchestrator")
    func testSpaceDelimitedPluginActivationInUIOrchestrator() {
        let orchestrator = UIOrchestrator()

        // Uncommitted queries do not activate plugin UI
        orchestrator.performSearch("!e")
        #expect(orchestrator.activePluginUI == nil)
        #expect(!orchestrator.results.isEmpty)

        orchestrator.performSearch("!emoji")
        #expect(orchestrator.activePluginUI == nil)
        #expect(!orchestrator.results.isEmpty)

        // Committed queries with trailing space activate plugin UI
        orchestrator.performSearch("!e ")
        #expect(orchestrator.activePluginUI != nil)
        #expect(orchestrator.results.isEmpty)

        orchestrator.performSearch("!emoji ")
        #expect(orchestrator.activePluginUI != nil)
        #expect(orchestrator.results.isEmpty)
    }

    @Test("Execute selected bang file item sets query to bang payload")
    func testExecuteSelectedBangFileNavigates() {
        let orchestrator = UIOrchestrator()
        let bangFileItem = SearchItem(
            id: "bang:file",
            title: "!file <path/name>",
            subtitle: "Search files or browse filesystem",
            category: .file,
            score: 95,
            actionPayload: "!file "
        )
        orchestrator.results = [bangFileItem]
        orchestrator.selectedIndex = 0

        orchestrator.executeSelected()

        #expect(orchestrator.query == "!file ")
    }
}

