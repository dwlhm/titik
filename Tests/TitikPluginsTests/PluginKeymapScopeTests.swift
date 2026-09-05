import Foundation
import AppKit
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikUI

@Suite("PluginKeymapScope Tests")
struct PluginKeymapScopeTests {

    private func makeKeyEvent(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    @Test("PluginKeymapScope registers, derives keycaps, and triggers bindings")
    @MainActor
    func testScopeRegistrationAndTrigger() {
        let scope = PluginKeymapScope()
        var triggered = false

        scope.register("cmd+k", label: "Palette") {
            triggered = true
        }

        #expect(scope.keycaps.count == 1)
        #expect(scope.keycaps.first?.shortcut == "cmd+k")
        #expect(scope.keycaps.first?.label == "Palette")

        let event = makeKeyEvent(keyCode: Keycode.k.rawValue, modifierFlags: [.command])
        let handled = scope.trigger(event: event)
        #expect(handled == true)
        #expect(triggered == true)

        let unhandledEvent = makeKeyEvent(keyCode: Keycode.j.rawValue, modifierFlags: [.command])
        let unhandled = scope.trigger(event: unhandledEvent)
        #expect(unhandled == false)
    }

    @Test("PluginKeymapScope startCapture and onCaptured combo")
    @MainActor
    func testKeyCaptureSuccess() {
        let scope = PluginKeymapScope()
        #expect(scope.isCapturing == false)

        var capturedCombo: KeyCombination? = nil
        scope.startCapture(
            onCaptured: { combo in
                capturedCombo = combo
            }
        )

        #expect(scope.isCapturing == true)

        // Press Cmd + Shift + K
        let event = makeKeyEvent(keyCode: Keycode.k.rawValue, modifierFlags: [.command, .shift])
        let consumed = scope.trigger(event: event)

        #expect(consumed == true)
        #expect(scope.isCapturing == false)
        #expect(capturedCombo != nil)
        #expect(capturedCombo?.key == .k)
        #expect(capturedCombo?.modifiers.contains(.command) == true)
        #expect(capturedCombo?.modifiers.contains(.shift) == true)
    }

    @Test("PluginKeymapScope onModifierOnly prompt without stopping capture")
    @MainActor
    func testKeyCaptureModifierOnly() {
        let scope = PluginKeymapScope()
        var modifierCaptured: KeyModifier? = nil

        scope.startCapture(
            onCaptured: { _ in },
            onModifierOnly: { mods in
                modifierCaptured = mods
            }
        )

        #expect(scope.isCapturing == true)

        // Press Command alone
        let cmdEvent = makeKeyEvent(keyCode: Keycode.command.rawValue, modifierFlags: [.command])
        let consumed = scope.trigger(event: cmdEvent)

        #expect(consumed == true)
        #expect(scope.isCapturing == true) // Still capturing
        #expect(modifierCaptured?.contains(.command) == true)

        scope.stopCapture()
        #expect(scope.isCapturing == false)
    }

    @Test("PluginKeymapScope onCancelled on Escape without modifiers")
    @MainActor
    func testKeyCaptureCancelledOnEscape() {
        let scope = PluginKeymapScope()
        var cancelled = false
        var captured: KeyCombination? = nil

        scope.startCapture(
            onCaptured: { combo in
                captured = combo
            },
            onCancelled: {
                cancelled = true
            }
        )

        #expect(scope.isCapturing == true)

        // Press Escape (no modifiers)
        let escEvent = makeKeyEvent(keyCode: Keycode.escape.rawValue, modifierFlags: [])
        let consumed = scope.trigger(event: escEvent)

        #expect(consumed == true)
        #expect(scope.isCapturing == false)
        #expect(cancelled == true)
        #expect(captured == nil)
    }

    @Test("PluginKeymapScope captures Escape with modifiers as combination")
    @MainActor
    func testKeyCaptureEscapeWithModifier() {
        let scope = PluginKeymapScope()
        var cancelled = false
        var captured: KeyCombination? = nil

        scope.startCapture(
            onCaptured: { combo in
                captured = combo
            },
            onCancelled: {
                cancelled = true
            }
        )

        // Press Shift + Escape
        let shiftEscEvent = makeKeyEvent(keyCode: Keycode.escape.rawValue, modifierFlags: [.shift])
        let consumed = scope.trigger(event: shiftEscEvent)

        #expect(consumed == true)
        #expect(scope.isCapturing == false)
        #expect(cancelled == false)
        #expect(captured != nil)
        #expect(captured?.key == .escape)
        #expect(captured?.modifiers.contains(.shift) == true)
    }
}
