import Testing
import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikPlatform

@Suite("AppLifecycle E2E Tests")
struct AppLifecycleE2ETests {
    @Test("App bootstrap and window toggle")
    @MainActor
    func testAppBootstrapAndWindowToggle() {
        let config = ConfigLoader.shared.load()
        #expect(config.window.width > 0)

        let windowController = WindowController()
        let dummyView = AnyView(Text("Test View"))
        windowController.setupWindow(contentView: dummyView, width: 720, height: 460)

        #expect(!windowController.isVisible)

        windowController.showWindow()
        #expect(windowController.isVisible)

        windowController.hideWindow()
        #expect(!windowController.isVisible)

        windowController.toggleWindow()
        #expect(windowController.isVisible)

        windowController.toggleWindow()
        #expect(!windowController.isVisible)
    }

    @Test("Keymap registration and unregistration lifecycle")
    func testKeymapRegistrationLifecycle() {
        let registry = KeymapRegistry()
        let combo = KeyCombination(modifiers: .command, key: .period)

        #expect(!registry.isRegistered(combination: combo))
        #expect(throws: Never.self) {
            try registry.register(combination: combo, identifier: "global.toggle", action: {})
        }
        #expect(registry.isRegistered(combination: combo))

        registry.unregister(identifier: "global.toggle")
        #expect(!registry.isRegistered(combination: combo))
    }

    @Test("Keyboard navigation lifecycle with active preview pane")
    @MainActor
    func testKeyboardNavigationLifecycleWithActivePreviewPane() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_e2e_nav_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("FolderA")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("FileB.swift")
        try "print(\"hello\")".write(to: testFile, atomically: true, encoding: .utf8)

        let orchestrator = UIOrchestrator()

        // Setting a path query (directory browsing)
        orchestrator.query = tempDir.path + "/"
        for _ in 0..<40 {
            if orchestrator.results.count == 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(orchestrator.results.count == 3)
        #expect(orchestrator.selectedIndex == 0)
        #expect(orchestrator.selectedItem?.title == "..")

        // Navigate forward through results
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.title == "FolderA")
        #expect(orchestrator.selectedItem?.hasRichPreview == true)

        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 2)
        #expect(orchestrator.selectedItem?.title == "FileB.swift")
        #expect(orchestrator.selectedItem?.hasRichPreview == true)

        // Clamping forward navigation
        orchestrator.selectNext()
        #expect(orchestrator.selectedIndex == 2)

        // Navigate backward
        orchestrator.selectPrevious()
        #expect(orchestrator.selectedIndex == 1)
        #expect(orchestrator.selectedItem?.title == "FolderA")

        // Test executing selected item and verify action invocation
        nonisolated(unsafe) var actionExecuted = false
        let executableItem = SearchItem(
            id: "exec-test",
            title: "ExecItem",
            subtitle: "Test Subtitle",
            category: .file,
            previewType: .text(testFile),
            action: {
                actionExecuted = true
                return true
            }
        )
        orchestrator.results = [executableItem]
        orchestrator.selectedIndex = 0

        #expect(orchestrator.selectedItem?.hasRichPreview == true)
        orchestrator.executeSelected()
        #expect(actionExecuted)
    }
}
