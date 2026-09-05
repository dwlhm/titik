import Foundation
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
        #expect(Keycode.fromString("f1") == .f1)
        #expect(Keycode.fromString("f12") == .f12)
        #expect(Keycode.fromString("up") == .upArrow)
        #expect(Keycode.fromString("down") == .downArrow)
        #expect(Keycode.fromString("left") == .leftArrow)
        #expect(Keycode.fromString("right") == .rightArrow)
        #expect(Keycode.fromString("↵") == .returnKey)
        #expect(Keycode.fromString("↑") == .upArrow)
        #expect(Keycode.fromString("↓") == .downArrow)
        #expect(Keycode.fromString("←") == .leftArrow)
        #expect(Keycode.fromString("→") == .rightArrow)
        #expect(Keycode.fromString("⇥") == .tab)
        #expect(Keycode.fromString("⌫") == .delete)
        #expect(Keycode.fromString("+") == .equal)
        #expect(Keycode.fromString("plus") == .equal)
        #expect(Keycode.fromString("␣") == .space)
        #expect(Keycode.fromString("⎋") == .escape)
        #expect(Keycode.fromString("{") == .leftBracket)
        #expect(Keycode.fromString("}") == .rightBracket)
        #expect(Keycode.fromString(":") == .semicolon)
        #expect(Keycode.fromString("\"") == .quote)
        #expect(Keycode.fromString("<") == .comma)
        #expect(Keycode.fromString(">") == .period)
        #expect(Keycode.fromString("?") == .slash)
        #expect(Keycode.fromString("~") == .grave)
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

        let allMods = KeyModifier.fromString("ctrl+alt+cmd+shift")
        #expect(allMods.contains(.control))
        #expect(allMods.contains(.option))
        #expect(allMods.contains(.command))
        #expect(allMods.contains(.shift))

        let glyphMods = KeyModifier.fromString("⌘⌥⌃⇧")
        #expect(glyphMods.contains(.command))
        #expect(glyphMods.contains(.option))
        #expect(glyphMods.contains(.control))
        #expect(glyphMods.contains(.shift))

        let winMod = KeyModifier.fromString("win")
        #expect(winMod.contains(.command))
    }

    @Test("KeyCombination creation and glyph parsing")
    func testKeyCombinationCreation() {
        let combo1 = KeyCombination(string: "cmd+.")
        #expect(combo1 != nil)
        #expect(combo1?.key == .period)
        #expect(combo1?.modifiers.contains(.command) == true)
        #expect(combo1?.description == "⌘.")

        let combo2 = KeyCombination(string: "opt+space")
        #expect(combo2 != nil)
        #expect(combo2?.key == .space)
        #expect(combo2?.modifiers.contains(.option) == true)
        #expect(combo2?.description == "⌥␣")

        let combo3 = KeyCombination(string: "⌘k")
        #expect(combo3 != nil)
        #expect(combo3?.key == .k)
        #expect(combo3?.modifiers.contains(.command) == true)

        let combo4 = KeyCombination(string: "f5")
        #expect(combo4 != nil)
        #expect(combo4?.key == .f5)
        #expect(combo4?.modifiers == KeyModifier.none)
    }

    @Test("KeyCombination Codable serialization roundtrip")
    func testKeyCombinationCodable() throws {
        let original = KeyCombination(modifiers: [.command, .shift], key: .k)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombination.self, from: data)
        #expect(decoded == original)
    }

    @Test("Duplicate registration throws error")
    func testDuplicateRegistrationThrows() throws {
        let registry = KeymapRegistry()
        let combo = KeyCombination(modifiers: .command, key: .k)

        try registry.register(combination: combo, identifier: "action.first", mode: .background, action: {})

        #expect(throws: KeymapError.self) {
            try registry.register(combination: combo, identifier: "action.second", mode: .palette, action: {})
        }
    }

    @Test("Re-registering same identifier updates combination without error")
    func testReregistrationUpdatesCombination() throws {
        let registry = KeymapRegistry()
        let combo1 = KeyCombination(modifiers: .command, key: .k)
        let combo2 = KeyCombination(modifiers: .command, key: .j)

        try registry.register(combination: combo1, identifier: "action.toggle", mode: .palette, action: {})
        #expect(registry.isRegistered(combination: combo1))

        try registry.register(combination: combo2, identifier: "action.toggle", mode: .palette, action: {})
        #expect(!registry.isRegistered(combination: combo1))
        #expect(registry.isRegistered(combination: combo2))
        #expect(registry.find(identifier: "action.toggle")?.combination == combo2)
    }

    @Test("Unregister by identifier and combination")
    func testUnregister() throws {
        let registry = KeymapRegistry()
        let combo1 = KeyCombination(modifiers: .command, key: .p)
        let combo2 = KeyCombination(modifiers: .option, key: .o)

        try registry.register(combination: combo1, identifier: "action.print", mode: .background, action: {})
        try registry.register(combination: combo2, identifier: "action.open", mode: .palette, action: {})

        #expect(registry.isRegistered(combination: combo1))
        #expect(registry.isRegistered(identifier: "action.print"))

        registry.unregister(identifier: "action.print")
        #expect(!registry.isRegistered(combination: combo1))
        #expect(!registry.isRegistered(identifier: "action.print"))

        registry.unregister(combination: combo2)
        #expect(!registry.isRegistered(combination: combo2))
        #expect(!registry.isRegistered(identifier: "action.open"))
    }

    @Test("Introspection and clear")
    func testIntrospectionAndClear() throws {
        let registry = KeymapRegistry()
        let combo1 = KeyCombination(modifiers: .command, key: .a)
        let combo2 = KeyCombination(modifiers: .command, key: .b)

        try registry.register(combination: combo1, identifier: "action.a", mode: .background, action: {})
        try registry.register(combination: combo2, identifier: "action.b", mode: .palette, action: {})

        let bindings = registry.allBindings()
        #expect(bindings.count == 2)

        let bindingA = registry.find(identifier: "action.a")
        #expect(bindingA?.mode == .background)
        #expect(bindingA?.combination == combo1)

        let bindingB = registry.find(combination: combo2)
        #expect(bindingB?.mode == .palette)
        #expect(bindingB?.identifier == "action.b")

        registry.clear()
        #expect(registry.allBindings().isEmpty)
        #expect(!registry.isRegistered(identifier: "action.a"))
        #expect(!registry.isRegistered(combination: combo2))
    }

    @Test("Concurrent registrations and queries are thread-safe")
    func testConcurrentAccess() async {
        let registry = KeymapRegistry()
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let key = Keycode(rawValue: UInt32(i % 26)) ?? .a
                    let combo = KeyCombination(modifiers: .command, key: key)
                    let id = "action.concurrent.\(i)"
                    try? registry.register(combination: combo, identifier: id, mode: .background, action: {})
                    _ = registry.find(identifier: id)
                    _ = registry.find(combination: combo)
                    _ = registry.allBindings()
                }
            }
        }

        #expect(registry.allBindings().count <= 26)
    }
}
