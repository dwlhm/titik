import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikPlatform

private typealias HotkeyTestMode = TitikCore.ShortcutExecutionMode

@Suite("E2E Hotkey Integration & KeymapRegistry Tests")
struct E2EHotkeyIntegrationTests {

    // MARK: - Feature 1: Multi-Hotkey Carbon Registration

    @Test("F01: Single hotkey registration and active verification")
    func test_f01_singleHotkeyRegistrationSuccess() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+k"))

        let flag = BooleanBox()
        try registry.register(combination: combo, identifier: "test.single.hotkey") {
            flag.set(true)
        }

        #expect(registry.isRegistered(combination: combo))
        let binding = registry.find(combination: combo)
        #expect(binding?.identifier == "test.single.hotkey")

        binding?.action()
        #expect(flag.get() == true)
    }

    @Test("F01: Register 5 distinct hotkey combinations simultaneously")
    func test_f01_multipleDistinctHotkeysRegistration() throws {
        let registry = KeymapRegistry()
        let combos = ["cmd+k", "opt+space", "ctrl+shift+t", "cmd+alt+p", "cmd+."]

        for (index, comboStr) in combos.enumerated() {
            let combo = try #require(KeyCombination(string: comboStr))
            try registry.register(combination: combo, identifier: "test.hotkey.\(index)") {}
        }

        let allBindings = registry.allBindings()
        #expect(allBindings.count == 5)

        for (index, comboStr) in combos.enumerated() {
            let combo = try #require(KeyCombination(string: comboStr))
            #expect(registry.isRegistered(combination: combo))
            let binding = registry.find(combination: combo)
            #expect(binding?.identifier == "test.hotkey.\(index)")
        }
    }

    @Test("F01: Hotkey handler invocation on simulated event dispatch")
    func test_f01_hotkeyHandlerInvocationOnEvent() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+shift+p"))

        let counter = CounterBox()
        try registry.register(combination: combo, identifier: "test.invoke.counter") {
            counter.increment()
        }

        for _ in 0..<5 {
            registry.find(combination: combo)?.action()
        }

        #expect(counter.count == 5)
    }

    @Test("F01: Hotkey registration query returns true for active and false for inactive")
    func test_f01_hotkeyRegistrationQuery() throws {
        let registry = KeymapRegistry()
        let comboActive = try #require(KeyCombination(string: "cmd+1"))
        let comboInactive = try #require(KeyCombination(string: "cmd+2"))

        try registry.register(combination: comboActive, identifier: "active.key") {}

        #expect(registry.isRegistered(combination: comboActive) == true)
        #expect(registry.isRegistered(combination: comboInactive) == false)
    }

    @Test("F01: Active registrations list matches count and contents")
    func test_f01_activeRegistrationsListMatchesCount() throws {
        let registry = KeymapRegistry()
        let combo1 = try #require(KeyCombination(string: "cmd+a"))
        let combo2 = try #require(KeyCombination(string: "cmd+b"))
        let combo3 = try #require(KeyCombination(string: "cmd+c"))

        try registry.register(combination: combo1, identifier: "id.a") {}
        try registry.register(combination: combo2, identifier: "id.b") {}
        try registry.register(combination: combo3, identifier: "id.c") {}

        let all = registry.allBindings()
        #expect(all.count == 3)
        let ids = Set(all.map { $0.identifier })
        #expect(ids == Set(["id.a", "id.b", "id.c"]))
    }

    // MARK: - Feature 2: Hotkey Unregistration & Dynamic Update

    @Test("F02: Unregistration by identifier frees combination")
    func test_f02_unregistrationByIdentifier() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+d"))

        try registry.register(combination: combo, identifier: "to.remove") {}
        #expect(registry.isRegistered(combination: combo) == true)

        registry.unregister(identifier: "to.remove")
        #expect(registry.isRegistered(combination: combo) == false)
        #expect(registry.find(combination: combo) == nil)
    }

    @Test("F02: Unregistration by combination frees identifier")
    func test_f02_unregistrationByCombination() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "opt+d"))

        try registry.register(combination: combo, identifier: "combo.remove") {}
        #expect(registry.isRegistered(combination: combo) == true)

        registry.unregister(combination: combo)
        #expect(registry.isRegistered(combination: combo) == false)
        #expect(registry.find(combination: combo) == nil)
    }

    @Test("F02: Unregister all clears entire keymap state")
    func test_f02_unregisterAllClearsEntireState() throws {
        let registry = KeymapRegistry()
        let combo1 = try #require(KeyCombination(string: "cmd+x"))
        let combo2 = try #require(KeyCombination(string: "cmd+y"))

        try registry.register(combination: combo1, identifier: "clear.1") {}
        try registry.register(combination: combo2, identifier: "clear.2") {}
        #expect(registry.allBindings().count == 2)

        registry.clear()
        #expect(registry.allBindings().isEmpty)
        #expect(registry.isRegistered(combination: combo1) == false)
        #expect(registry.isRegistered(combination: combo2) == false)
    }

    @Test("F02: Dynamic update rebinds identifier to new combination and releases old")
    func test_f02_dynamicUpdateKeyRebinding() throws {
        let registry = KeymapRegistry()
        let oldCombo = try #require(KeyCombination(string: "cmd+1"))
        let newCombo = try #require(KeyCombination(string: "cmd+2"))

        let activeAction = StringBox()
        try registry.register(combination: oldCombo, identifier: "rebinding.id") {
            activeAction.set("old")
        }

        #expect(registry.isRegistered(combination: oldCombo) == true)
        #expect(registry.isRegistered(combination: newCombo) == false)

        // Rebind same identifier to new combo
        try registry.register(combination: newCombo, identifier: "rebinding.id") {
            activeAction.set("new")
        }

        #expect(registry.isRegistered(combination: oldCombo) == false)
        #expect(registry.isRegistered(combination: newCombo) == true)

        registry.find(combination: newCombo)?.action()
        #expect(activeAction.get() == "new")
    }

    @Test("F02: Unregistering non-existent key completes safely without throwing")
    func test_f02_unregisteredKeyIgnoredGracefully() {
        let registry = KeymapRegistry()
        registry.unregister(identifier: "non.existent.id")
        if let combo = KeyCombination(string: "cmd+shift+9") {
            registry.unregister(combination: combo)
        }
        #expect(registry.allBindings().isEmpty)
    }

    // MARK: - Feature 3: KeymapRegistry Conflict Tracking

    @Test("F03: Duplicate combination with different identifier throws duplicateBinding conflict")
    func test_f03_duplicateCombinationThrowsConflict() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+k"))

        try registry.register(combination: combo, identifier: "first.binding") {}

        #expect(throws: KeymapError.self) {
            try registry.register(combination: combo, identifier: "second.binding") {}
        }
    }

    @Test("F03: Re-registering same combination with same identifier succeeds")
    func test_f03_reRegisterSameIdentifierUpdatesCombo() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "cmd+k"))

        let counter = CounterBox()
        try registry.register(combination: combo, identifier: "idempotent.binding") {
            counter.increment()
        }

        // Second registration with same ID overwrites action
        try registry.register(combination: combo, identifier: "idempotent.binding") {
            counter.increment()
            counter.increment()
        }

        registry.find(combination: combo)?.action()
        #expect(counter.count == 2)
    }

    @Test("F03: Conflict error description contains key combination and existing identifier")
    func test_f03_conflictErrorDescriptionFormatting() throws {
        let combo = try #require(KeyCombination(string: "cmd+opt+s"))
        let error = KeymapError.duplicateBinding(combination: combo, existingIdentifier: "existing.app")

        let desc = error.errorDescription ?? ""
        #expect(desc.contains("existing.app"))
        #expect(desc.contains("already bound"))
    }

    @Test("F03: Thread-safe concurrent registrations across parallel tasks")
    func test_f03_threadSafeConcurrentRegistrations() async throws {
        let registry = KeymapRegistry()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    let keyStr = "cmd+\(i % 10)"
                    if let combo = KeyCombination(string: keyStr) {
                        try? registry.register(combination: combo, identifier: "concurrent.\(i)") {}
                    }
                }
            }
        }

        let count = registry.allBindings().count
        #expect(count > 0 && count <= 10)
    }

    @Test("F03: Registry find returns exact binding with combination and action")
    func test_f03_registryFindAndLookup() throws {
        let registry = KeymapRegistry()
        let combo = try #require(KeyCombination(string: "ctrl+opt+cmd+l"))

        let flag = BooleanBox()
        try registry.register(combination: combo, identifier: "lookup.test") {
            flag.set(true)
        }

        let found = registry.find(combination: combo)
        #expect(found != nil)
        #expect(found?.identifier == "lookup.test")
        #expect(found?.combination == combo)
        found?.action()
        #expect(flag.get() == true)
    }

    // MARK: - Feature 4: Execution Mode Differentiation

    @Test("F04: Background execution mode value semantics")
    func test_f04_backgroundModeSemantics() {
        let mode = HotkeyTestMode.background
        #expect(mode.rawValue == "background")
    }

    @Test("F04: Palette execution mode value semantics")
    func test_f04_paletteModeSemantics() {
        let mode = HotkeyTestMode.palette
        #expect(mode.rawValue == "palette")
    }

    @Test("F04: Mode Codable round trip serialization")
    func test_f04_modeCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let bgData = try encoder.encode(HotkeyTestMode.background)
        let decodedBg = try decoder.decode(HotkeyTestMode.self, from: bgData)
        #expect(decodedBg == .background)

        let palData = try encoder.encode(HotkeyTestMode.palette)
        let decodedPal = try decoder.decode(HotkeyTestMode.self, from: palData)
        #expect(decodedPal == .palette)
    }

    @Test("F04: Mode CaseIterable contains all required variants")
    func test_f04_modeCaseIterableExhaustiveness() {
        let allCases = HotkeyTestMode.allCases
        #expect(allCases.contains(.background))
        #expect(allCases.contains(.palette))
        #expect(allCases.count == 2)
    }

    @Test("F04: RegisteredHotkey struct holds mode and metadata correctly")
    func test_f04_registeredHotkeyStructHoldsMode() throws {
        let combo = try #require(KeyCombination(string: "cmd+shift+z"))
        let flag = BooleanBox()

        let hotkey = RegisteredHotkey(
            id: 42,
            identifier: "titik.test.hotkey",
            combination: combo,
            mode: .background
        ) {
            flag.set(true)
        }

        #expect(hotkey.id == 42)
        #expect(hotkey.identifier == "titik.test.hotkey")
        #expect(hotkey.combination == combo)
        #expect(hotkey.mode == .background)

        hotkey.handler()
        #expect(flag.get() == true)
    }

    // MARK: - Feature 6: Key Combination String Parsing

    @Test("F06: Standard modifier plus key combinations parsing")
    func test_f06_standardModifierPlusKey() {
        let c1 = KeyCombination(string: "cmd+shift+k")
        #expect(c1 != nil)
        #expect(c1?.modifiers.contains(.command) == true)
        #expect(c1?.modifiers.contains(.shift) == true)
        #expect(c1?.key == .k)

        let c2 = KeyCombination(string: "opt+space")
        #expect(c2 != nil)
        #expect(c2?.modifiers.contains(.option) == true)
        #expect(c2?.key == .space)

        let c3 = KeyCombination(string: "ctrl+alt+t")
        #expect(c3 != nil)
        #expect(c3?.modifiers.contains(.control) == true)
        #expect(c3?.modifiers.contains(.option) == true)
        #expect(c3?.key == .t)
    }

    @Test("F06: Whitespace separated key combinations parsing")
    func test_f06_whitespaceSeparatedKeys() {
        let c1 = KeyCombination(string: "cmd space")
        #expect(c1 != nil)
        #expect(c1?.modifiers.contains(.command) == true)
        #expect(c1?.key == .space)

        let c2 = KeyCombination(string: "opt return")
        #expect(c2 != nil)
        #expect(c2?.modifiers.contains(.option) == true)
        #expect(c2?.key == .returnKey)
    }

    @Test("F06: Alias modifier names resolution (alt, ctrl, command, option)")
    func test_f06_aliasModifierNames() {
        let mAlt = KeyModifier.fromString("alt")
        #expect(mAlt.contains(.option))

        let mCtrl = KeyModifier.fromString("ctrl")
        #expect(mCtrl.contains(.control))

        let mOption = KeyModifier.fromString("option")
        #expect(mOption.contains(.option))

        let mCommand = KeyModifier.fromString("command")
        #expect(mCommand.contains(.command))
    }

    @Test("F06: Special symbol punctuation key parsing")
    func test_f06_specialSymbolKeys() {
        let cDot = KeyCombination(string: "cmd+.")
        #expect(cDot != nil)
        #expect(cDot?.key == .period)

        let cComma = KeyCombination(string: "ctrl+,")
        #expect(cComma != nil)
        #expect(cComma?.key == .comma)

        let cSlash = KeyCombination(string: "cmd+/")
        #expect(cSlash != nil)
        #expect(cSlash?.key == .slash)
    }

    @Test("F06: Display glyph description generation (macOS standard symbols)")
    func test_f06_displayGlyphGeneration() throws {
        let combo = try #require(KeyCombination(string: "cmd+shift+k"))
        let desc = combo.description
        #expect(desc.contains("⌘"))
        #expect(desc.contains("⇧"))
        #expect(desc.contains("K"))
    }

    @Test("F06: Empty and whitespace strings return nil gracefully")
    func test_f06_emptyOrWhitespaceKeyCombination() {
        #expect(KeyCombination(string: "") == nil)
        #expect(KeyCombination(string: "   ") == nil)
        #expect(KeyCombination(string: "+") == nil)
        #expect(KeyCombination(string: "invalid_key_xyz_123") == nil)
    }

    @Test("F06: Single key without modifiers parses as .none modifier")
    func test_f06_singleKeyWithoutModifiers() {
        let combo = KeyCombination(string: "space")
        #expect(combo != nil)
        #expect(combo?.modifiers == KeyModifier.none)
        #expect(combo?.key == .space)
    }
}

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
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

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""

    func set(_ v: String) {
        lock.lock()
        defer { lock.unlock() }
        _value = v
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
