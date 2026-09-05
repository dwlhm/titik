import Foundation
import Testing
import TitikCore

@Suite("ClipboardPersistence Tests")
struct ClipboardPersistenceTests {
    @Test("JSON Save and Load Roundtrip")
    func testSaveAndLoadRoundtrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_clipboard_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manager = ClipboardManager(maxCapacity: 10, storageURL: fileURL)
        manager.addItem("Test Item 1")
        manager.addItem("Test Item 2")

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Create a new manager instance pointing to the same file
        let reloadedManager = ClipboardManager(maxCapacity: 10, storageURL: fileURL)
        let reloadedItems = reloadedManager.getItems()

        #expect(reloadedItems.count == 2)
        #expect(reloadedItems[0].content == "Test Item 2")
        #expect(reloadedItems[1].content == "Test Item 1")
    }

    @Test("Pin and Unpin Item")
    func testPinAndUnpin() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_clipboard_pin_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manager = ClipboardManager(maxCapacity: 10, storageURL: fileURL)
        manager.addItem("Item 1")
        manager.addItem("Item 2")
        manager.addItem("Item 3")

        let itemsBefore = manager.getItems()
        let itemToPin = itemsBefore.first(where: { $0.content == "Item 1" })!

        // Pin Item 1 -> should become pinned and move to top
        manager.togglePin(id: itemToPin.id)

        var itemsAfterPin = manager.getItems()
        #expect(itemsAfterPin.count == 3)
        #expect(itemsAfterPin[0].content == "Item 1")
        #expect(itemsAfterPin[0].isPinned == true)

        // Add another item -> unpinned new item should be inserted after pinned item
        manager.addItem("Item 4")
        itemsAfterPin = manager.getItems()
        #expect(itemsAfterPin[0].content == "Item 1") // Item 1 remains pinned at top
        #expect(itemsAfterPin[1].content == "Item 4")

        // Unpin Item 1
        manager.togglePin(id: itemToPin.id)
        let itemsAfterUnpin = manager.getItems()
        let unpinnedItem = itemsAfterUnpin.first(where: { $0.content == "Item 1" })!
        #expect(unpinnedItem.isPinned == false)
    }

    @Test("Delete Item")
    func testDeleteItem() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_clipboard_delete_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let manager = ClipboardManager(maxCapacity: 10, storageURL: fileURL)
        manager.addItem("Item 1")
        manager.addItem("Item 2")

        let items = manager.getItems()
        let targetId = items[0].id

        manager.deleteItem(id: targetId)

        let remaining = manager.getItems()
        #expect(remaining.count == 1)
        #expect(remaining[0].content == "Item 1")

        // Verify disk persistence after deletion
        let reloaded = ClipboardManager(maxCapacity: 10, storageURL: fileURL)
        #expect(reloaded.getItems().count == 1)
        #expect(reloaded.getItems()[0].content == "Item 1")
    }

    @Test("Corrupt File Handling")
    func testCorruptFileHandling() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_clipboard_corrupt_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Write corrupt data
        try "CORRUPT_JSON_DATA".write(to: fileURL, atomically: true, encoding: .utf8)

        // Manager should initialize safely without crashing
        let manager = ClipboardManager(maxCapacity: 10, storageURL: fileURL)
        #expect(manager.getItems().isEmpty)
    }
}
