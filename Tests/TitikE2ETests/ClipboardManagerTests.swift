import Foundation
import Testing
import TitikCore

@Suite("ClipboardManager Tests")
struct ClipboardManagerTests {
    @Test("Add item and deduplication / promotion")
    func testAddItemAndDeduplication() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_clipboard_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manager = ClipboardManager(maxCapacity: 3, storageURL: fileURL)
        manager.addItem("First item")
        manager.addItem("Second item")
        manager.addItem("First item") // Re-copy should promote to top

        let items = manager.getItems()
        #expect(items.count == 2)
        #expect(items[0].content == "First item")
        #expect(items[1].content == "Second item")
    }

    @Test("Capacity eviction at max items")
    func testCapacityEviction() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_clipboard_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manager = ClipboardManager(maxCapacity: 3, storageURL: fileURL)
        manager.addItem("Item 1")
        manager.addItem("Item 2")
        manager.addItem("Item 3")
        manager.addItem("Item 4")

        let items = manager.getItems()
        #expect(items.count == 3)
        #expect(items[0].content == "Item 4")
        #expect(items[1].content == "Item 3")
        #expect(items[2].content == "Item 2")
    }

    @Test("Single-line preview generation")
    func testPreviewGeneration() {
        let multiline = "Line 1 is the main title\nLine 2 is details\nLine 3"
        let item = ClipboardItem(content: multiline)
        #expect(item.lineCount == 3)
        #expect(item.preview == "Line 1 is the main title")
    }
}
