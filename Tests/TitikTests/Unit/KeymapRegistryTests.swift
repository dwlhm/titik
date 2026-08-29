import Testing
import TitikKeymap

@Suite("KeymapRegistry Tests")
struct KeymapRegistryTests {
    @Test("Keycode string conversions")
    func testKeycodeConversions() {
        #expect(Keycode.fromString(".") == .period)
        #expect(Keycode.fromString("space") == .space)
        #expect(Keycode.fromString("k") == .k)
        #expect(Keycode.fromString("enter") == .returnKey)
        #expect(Keycode.fromString("esc") == .escape)
    }

    @Test("KeyModifier parsing")
    func testKeyModifierParsing() {
        let cmd = KeyModifier.fromString("cmd")
        #expect(cmd.contains(.command))
        #expect(!cmd.contains(.shift))

        let cmdShift = KeyModifier.fromString("cmd+shift")
        #expect(cmdShift.contains(.command))
        #expect(cmdShift.contains(.shift))
        #expect(!cmdShift.contains(.option))
    }

    @Test("KeyCombination creation")
    func testKeyCombinationCreation() {
        let combo = KeyCombination(string: "cmd+.")
        #expect(combo != nil)
        #expect(combo?.key == .period)
        #expect(combo?.modifiers.contains(.command) == true)
        #expect(combo?.description == "⌘.")
    }

    @Test("Duplicate registration throws error")
    func testDuplicateRegistrationThrows() throws {
        let registry = KeymapRegistry()
        let combo = KeyCombination(modifiers: .command, key: .k)

        try registry.register(combination: combo, identifier: "action.first", action: {})

        #expect(throws: KeymapError.self) {
            try registry.register(combination: combo, identifier: "action.second", action: {})
        }
    }

    @Test("Unregister key combination")
    func testUnregister() {
        let registry = KeymapRegistry()
        let combo = KeyCombination(modifiers: .command, key: .p)
        try? registry.register(combination: combo, identifier: "action.print", action: {})
        #expect(registry.isRegistered(combination: combo))

        registry.unregister(identifier: "action.print")
        #expect(!registry.isRegistered(combination: combo))
    }
}
