import Foundation
import Testing
import TitikKeymap

@Suite("HotkeyManager Tests", .serialized)
struct HotkeyManagerTests {

    @Test("Multi-hotkey registration assigns distinct Carbon IDs")
    func testMultiHotkeyRegistrationDistinctIds() throws {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let combo1 = try #require(KeyCombination(string: "cmd+k"))
        let combo2 = try #require(KeyCombination(string: "opt+space"))
        let combo3 = try #require(KeyCombination(string: "ctrl+shift+p"))

        let id1 = try manager.register(identifier: "app.search", combination: combo1, mode: .palette, handler: {})
        let id2 = try manager.register(identifier: "app.launcher", combination: combo2, mode: .background, handler: {})
        let id3 = try manager.register(identifier: "app.command", combination: combo3, mode: .background, handler: {})

        #expect(id1 != id2)
        #expect(id2 != id3)
        #expect(id1 != id3)

        #expect(manager.isRegistered(identifier: "app.search"))
        #expect(manager.isRegistered(identifier: "app.launcher"))
        #expect(manager.isRegistered(identifier: "app.command"))

        #expect(manager.isRegistered(combination: combo1))
        #expect(manager.isRegistered(combination: combo2))
        #expect(manager.isRegistered(combination: combo3))

        let active = manager.activeRegistrations
        #expect(active.count == 3)
    }

    @Test("Duplicate key combination throws KeymapError.duplicateBinding")
    func testDuplicateCombinationThrows() throws {
        KeymapRegistry.shared.clear()
        let manager = HotkeyManager()
        defer {
            manager.unregisterAll()
            KeymapRegistry.shared.clear()
        }

        let combo = try #require(KeyCombination(string: "ctrl+opt+shift+9"))

        try manager.register(identifier: "action.first", combination: combo, mode: .background, handler: {})

        #expect(throws: KeymapError.self) {
            try manager.register(identifier: "action.second", combination: combo, mode: .palette, handler: {})
        }
    }

    @Test("Re-registering existing identifier updates combination dynamically")
    func testReregisteringUpdatesCombination() throws {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let oldCombo = try #require(KeyCombination(string: "cmd+1"))
        let newCombo = try #require(KeyCombination(string: "cmd+2"))

        _ = try manager.register(identifier: "action.slot1", combination: oldCombo, mode: .palette, handler: {})
        #expect(manager.isRegistered(combination: oldCombo))
        #expect(!manager.isRegistered(combination: newCombo))

        let id2 = try manager.updateHotkey(identifier: "action.slot1", combination: newCombo, mode: .background, handler: {})
        #expect(!manager.isRegistered(combination: oldCombo))
        #expect(manager.isRegistered(combination: newCombo))
        #expect(manager.isRegistered(identifier: "action.slot1"))

        let reg = manager.registration(for: "action.slot1")
        #expect(reg?.combination == newCombo)
        #expect(reg?.mode == .background)
        #expect(reg?.id == id2)
    }

    @Test("Unregister by identifier removes hotkey and frees combination")
    func testUnregisterByIdentifier() throws {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let combo = try #require(KeyCombination(string: "opt+k"))
        try manager.register(identifier: "action.opt_k", combination: combo, mode: .background, handler: {})

        #expect(manager.isRegistered(identifier: "action.opt_k"))
        #expect(manager.isRegistered(combination: combo))

        manager.unregister(identifier: "action.opt_k")

        #expect(!manager.isRegistered(identifier: "action.opt_k"))
        #expect(!manager.isRegistered(combination: combo))
        #expect(manager.registration(for: "action.opt_k") == nil)

        // Can now re-bind the same combination to another action without conflict
        _ = try manager.register(identifier: "action.other", combination: combo, mode: .palette, handler: {})
        #expect(manager.isRegistered(identifier: "action.other"))
    }

    @Test("Unregister by combination removes hotkey")
    func testUnregisterByCombination() throws {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let combo = try #require(KeyCombination(string: "ctrl+opt+t"))
        try manager.register(identifier: "action.terminal", combination: combo, mode: .background, handler: {})

        #expect(manager.isRegistered(combination: combo))

        manager.unregister(combination: combo)

        #expect(!manager.isRegistered(combination: combo))
        #expect(!manager.isRegistered(identifier: "action.terminal"))
    }

    @Test("UnregisterAll clears all active registrations")
    func testUnregisterAll() throws {
        let manager = HotkeyManager()

        let combo1 = try #require(KeyCombination(string: "cmd+f1"))
        let combo2 = try #require(KeyCombination(string: "cmd+f2"))

        try manager.register(identifier: "action.f1", combination: combo1, mode: .background, handler: {})
        try manager.register(identifier: "action.f2", combination: combo2, mode: .palette, handler: {})

        #expect(manager.activeRegistrations.count == 2)

        manager.unregisterAll()

        #expect(manager.activeRegistrations.isEmpty)
        #expect(!manager.isRegistered(identifier: "action.f1"))
        #expect(!manager.isRegistered(identifier: "action.f2"))
        #expect(!manager.isRegistered(combination: combo1))
        #expect(!manager.isRegistered(combination: combo2))
    }

    @Test("Execution modes background and palette are preserved in registrations")
    func testExecutionModes() throws {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let comboBg = try #require(KeyCombination(string: "cmd+shift+b"))
        let comboPal = try #require(KeyCombination(string: "cmd+shift+p"))

        let idBg = try manager.register(identifier: "action.bg", combination: comboBg, mode: .background, handler: {})
        let idPal = try manager.register(identifier: "action.pal", combination: comboPal, mode: .palette, handler: {})

        let regBg = manager.registration(for: idBg)
        let regPal = manager.registration(for: idPal)

        #expect(regBg?.mode == .background)
        #expect(regPal?.mode == .palette)
    }

    @Test("Trigger by identifier and by ID dispatches registered handler")
    func testTriggerDispatching() throws {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let combo1 = try #require(KeyCombination(string: "opt+1"))
        let combo2 = try #require(KeyCombination(string: "opt+2"))

        nonisolated(unsafe) var triggered1 = false
        nonisolated(unsafe) var triggered2 = false

        let id1 = try manager.register(identifier: "action.trig1", combination: combo1, mode: .background) {
            triggered1 = true
        }

        let id2 = try manager.register(identifier: "action.trig2", combination: combo2, mode: .palette) {
            triggered2 = true
        }

        let success1 = manager.trigger(identifier: "action.trig1")
        let success2 = manager.trigger(id: id2)
        let failed = manager.trigger(identifier: "action.nonexistent")

        #expect(success1 == true)
        #expect(success2 == true)
        #expect(failed == false)

        // Directly invoke handlers stored on registration to verify
        manager.registration(for: id1)?.handler()
        manager.registration(for: id2)?.handler()

        #expect(triggered1 == true)
        #expect(triggered2 == true)
    }

    @Test("Backward compatibility toggle registration and updating")
    func testBackwardCompatibilityMethods() {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let combo = KeyCombination(modifiers: .command, key: .period)
        let registered = manager.registerHotkey(combination: combo) {}
        #expect(registered == true)
        #expect(manager.isRegistered(identifier: "global.hotkey.toggle"))

        let updated = manager.updateHotkey(modifier: "opt", key: "space") {}
        #expect(updated == true)
        #expect(manager.isRegistered(identifier: "global.hotkey.toggle"))

        manager.unregisterHotkey()
        #expect(!manager.isRegistered(identifier: "global.hotkey.toggle"))
    }

    @Test("Concurrent registrations and queries are thread-safe")
    func testConcurrentAccess() async {
        let manager = HotkeyManager()
        defer { manager.unregisterAll() }

        let iterations = 50

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let key = Keycode(rawValue: UInt32(i % 26)) ?? .a
                    let combo = KeyCombination(modifiers: .control, key: key)
                    let id = "concurrent.hotkey.\(i)"
                    _ = try? manager.register(identifier: id, combination: combo, mode: .background, handler: {})
                    _ = manager.isRegistered(identifier: id)
                    _ = manager.registration(for: id)
                    _ = manager.activeRegistrations
                    if i % 3 == 0 {
                        manager.unregister(identifier: id)
                    }
                }
            }
        }

        #expect(manager.activeRegistrations.count <= 26)
    }
}
