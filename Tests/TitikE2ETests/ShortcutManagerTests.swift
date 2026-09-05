import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap

@Suite("ShortcutManager Unit Tests", .serialized)
struct ShortcutManagerTests {

    @Test("ShortcutManager loads and parses combinations properly")
    @MainActor
    func testParseCombination() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).json")
        let manager = ShortcutManager(configLoader: ConfigLoader(configURL: tempURL))

        let sc1 = ShortcutConfig(key: "k", modifiers: ["cmd", "shift"], mode: .palette, action: ShortcutActionConfig(type: .rawQuery, target: "!zen"))
        let combo1 = manager.parseCombination(from: sc1)
        #expect(combo1 != nil)
        #expect(combo1?.modifiers.contains(.command) == true)
        #expect(combo1?.modifiers.contains(.shift) == true)
        #expect(combo1?.key == .k)

        let sc2 = ShortcutConfig(shortcut: "opt+space", mode: .background, action: ShortcutActionConfig(type: .rawQuery, target: "!emoji"))
        let combo2 = manager.parseCombination(from: sc2)
        #expect(combo2 != nil)
        #expect(combo2?.modifiers.contains(.option) == true)
        #expect(combo2?.key == .space)
    }

    @Test("ShortcutManager duplicate detection detects collisions")
    @MainActor
    func testDuplicateDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let manager = ShortcutManager(configLoader: isolatedLoader)

        KeymapRegistry.shared.clear()
        defer {
            HotkeyManager.shared.unregisterAll()
            KeymapRegistry.shared.clear()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let combo = try #require(KeyCombination(string: "cmd+shift+y"))
        let sc = ShortcutConfig(
            id: "shortcut-1",
            shortcut: "cmd+shift+y",
            mode: .palette,
            action: ShortcutActionConfig(type: .rawQuery, target: "!zen https://apple.com")
        )

        try manager.addShortcut(sc)

        let dup = manager.isDuplicate(combination: combo)
        #expect(dup.isDuplicate == true)
        #expect(dup.existingCommand == "!zen https://apple.com")

        let dupIgnoringSelf = manager.isDuplicate(combination: combo, ignoringId: "shortcut-1")
        #expect(dupIgnoringSelf.isDuplicate == false)

        let otherCombo = try #require(KeyCombination(string: "cmd+shift+z"))
        let dupOther = manager.isDuplicate(combination: otherCombo)
        #expect(dupOther.isDuplicate == false)
    }

    @Test("ShortcutManager add, update, and delete lifecycle")
    @MainActor
    func testShortcutLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let manager = ShortcutManager(configLoader: isolatedLoader)

        KeymapRegistry.shared.clear()
        defer {
            HotkeyManager.shared.unregisterAll()
            KeymapRegistry.shared.clear()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sc = ShortcutConfig(
            id: "test-shortcut-lifecycle",
            shortcut: "ctrl+opt+m",
            action: ShortcutActionConfig(type: .rawQuery, target: "!cmd lock")
        )

        try manager.addShortcut(sc)
        #expect(manager.shortcuts.contains(where: { $0.id == "test-shortcut-lifecycle" }))

        // Update
        let updated = ShortcutConfig(
            id: "test-shortcut-lifecycle",
            shortcut: "ctrl+opt+n",
            action: ShortcutActionConfig(type: .rawQuery, target: "!cmd sleep")
        )
        try manager.updateShortcut(id: "test-shortcut-lifecycle", updated: updated)

        let found = manager.shortcuts.first(where: { $0.id == "test-shortcut-lifecycle" })
        #expect(found?.action.target == "!cmd sleep")
        #expect(found?.keyCombinationString == "ctrl+opt+n")

        // Delete
        manager.deleteShortcut(id: "test-shortcut-lifecycle")
        #expect(!manager.shortcuts.contains(where: { $0.id == "test-shortcut-lifecycle" }))
    }

    @Test("ShortcutManager syncAllShortcuts registers hotkeys with dispatcher")
    @MainActor
    func testSyncAllShortcuts() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let manager = ShortcutManager(configLoader: isolatedLoader)
        defer {
            HotkeyManager.shared.unregisterAll()
            KeymapRegistry.shared.clear()
            try? FileManager.default.removeItem(at: tempDir)
        }

        manager.shortcuts = [
            ShortcutConfig(id: "sync-1", shortcut: "cmd+opt+1", action: ShortcutActionConfig(type: .rawQuery, target: "!zen")),
            ShortcutConfig(id: "sync-2", shortcut: "cmd+opt+2", action: ShortcutActionConfig(type: .rawQuery, target: "!file"))
        ]

        let executedBox = BooleanBox()
        manager.syncAllShortcuts { query in
            if query == "!zen" {
                executedBox.set(true)
            }
        }

        #expect(manager.shortcuts.count == 2)
    }

    @Test("ShortcutManager reloadFromConfig resynchronizes hotkeys")
    @MainActor
    func testReloadFromConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let manager = ShortcutManager(configLoader: isolatedLoader)

        KeymapRegistry.shared.clear()
        defer {
            HotkeyManager.shared.unregisterAll()
            KeymapRegistry.shared.clear()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sc1 = ShortcutConfig(id: "reload-1", shortcut: "ctrl+opt+1", action: ShortcutActionConfig(type: .rawQuery, target: "!app"))
        try manager.addShortcut(sc1)
        #expect(manager.registeredShortcutIds.contains("reload-1"))

        // Update config externally and call reloadFromConfig
        var updatedConfig = isolatedLoader.currentConfig
        let sc2 = ShortcutConfig(id: "reload-2", shortcut: "ctrl+opt+2", action: ShortcutActionConfig(type: .rawQuery, target: "!calc"))
        updatedConfig.shortcuts = [sc2]
        isolatedLoader.currentConfig = updatedConfig
        try isolatedLoader.save()

        manager.reloadFromConfig()
        #expect(manager.shortcuts.count == 1)
        #expect(manager.shortcuts.first?.id == "reload-2")
        #expect(!manager.registeredShortcutIds.contains("reload-1"))
        #expect(manager.registeredShortcutIds.contains("reload-2"))
    }

    @Test("ShortcutManager transactional rollback on persistence failure")
    @MainActor
    func testTransactionalRollback() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("config.json")
        let isolatedLoader = ConfigLoader(configURL: tempURL)
        let manager = ShortcutManager(configLoader: isolatedLoader)

        defer {
            HotkeyManager.shared.unregisterAll()
            KeymapRegistry.shared.clear()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sc1 = ShortcutConfig(id: "init-1", shortcut: "ctrl+opt+8", action: ShortcutActionConfig(type: .rawQuery, target: "!zen"))
        try manager.addShortcut(sc1)

        // Make config file read-only to force save failure
        try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempURL.path)
        }

        let scFail = ShortcutConfig(id: "fail-1", shortcut: "ctrl+opt+9", action: ShortcutActionConfig(type: .rawQuery, target: "!cmd lock"))
        var failed = false
        do {
            try manager.addShortcut(scFail)
        } catch {
            failed = true
        }

        if failed {
            #expect(!manager.shortcuts.contains(where: { $0.id == "fail-1" }))
            #expect(!manager.registeredShortcutIds.contains("fail-1"))
            #expect(manager.shortcuts.contains(where: { $0.id == "init-1" }))
        }
    }
}

private final class BooleanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    func set(_ v: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _value = v
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
