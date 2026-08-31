import Foundation
import Testing
@testable import TitikPluginKit

@Suite("Focus Ring & Keyboard Navigation Tests")
@MainActor
struct FocusRingTests {

    @Test("Cyclic progression traverses all active focus zones")
    func test_focusRing_cyclicProgression_input_body_media_citations_followup() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 3,
            citationCount: 2,
            hasFollowUpBar: true
        )

        #expect(coordinator.currentZone == .input)

        coordinator.next()
        #expect(coordinator.currentZone == .body)

        coordinator.next()
        #expect(coordinator.currentZone == .mediaRail)

        coordinator.next()
        #expect(coordinator.currentZone == .citationTray)

        coordinator.next()
        #expect(coordinator.currentZone == .followUpBar)

        // Cycles back to input
        coordinator.next()
        #expect(coordinator.currentZone == .input)
    }

    @Test("Empty media rail skips media zone cleanly")
    func test_focusRing_emptyMediaRail_skipsMediaZoneCleanly() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 0,
            citationCount: 3,
            hasFollowUpBar: true
        )

        #expect(coordinator.currentZone == .input)

        coordinator.next()
        #expect(coordinator.currentZone == .body)

        // MediaRail is empty -> jumps straight to citationTray
        coordinator.next()
        #expect(coordinator.currentZone == .citationTray)

        coordinator.next()
        #expect(coordinator.currentZone == .followUpBar)
    }

    @Test("Empty citation tray skips citation zone cleanly")
    func test_focusRing_emptyCitationTray_skipsCitationZoneCleanly() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 2,
            citationCount: 0,
            hasFollowUpBar: true
        )

        #expect(coordinator.currentZone == .input)

        coordinator.next()
        #expect(coordinator.currentZone == .body)

        coordinator.next()
        #expect(coordinator.currentZone == .mediaRail)

        // Citations empty -> jumps straight to followUpBar
        coordinator.next()
        #expect(coordinator.currentZone == .followUpBar)
    }

    @Test("Shift+Tab reverses focus order deterministically")
    func test_focusRing_shiftTab_reversesFocusOrderDeterministically() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 2,
            citationCount: 2,
            hasFollowUpBar: true
        )

        #expect(coordinator.currentZone == .input)

        coordinator.previous()
        #expect(coordinator.currentZone == .followUpBar)

        coordinator.previous()
        #expect(coordinator.currentZone == .citationTray)

        coordinator.previous()
        #expect(coordinator.currentZone == .mediaRail)

        coordinator.previous()
        #expect(coordinator.currentZone == .body)

        coordinator.previous()
        #expect(coordinator.currentZone == .input)
    }

    @Test("Media rail left arrow at zero remains clamped to zero")
    func test_mediaRail_leftArrowAtZero_clampedToZero() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .mediaRail,
            mediaCount: 4,
            citationCount: 2,
            hasFollowUpBar: true
        )

        coordinator.selectedMediaIndex = 0
        coordinator.previousMedia()
        #expect(coordinator.selectedMediaIndex == 0)
        coordinator.previousMedia()
        #expect(coordinator.selectedMediaIndex == 0)
    }

    @Test("Media rail right arrow at max index remains clamped to max")
    func test_mediaRail_rightArrowAtMax_clampedToMaxIndex() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .mediaRail,
            mediaCount: 4,
            citationCount: 2,
            hasFollowUpBar: true
        )

        coordinator.selectedMediaIndex = 3
        coordinator.nextMedia()
        #expect(coordinator.selectedMediaIndex == 3)
        coordinator.nextMedia()
        #expect(coordinator.selectedMediaIndex == 3)
    }

    @Test("Citation tray out of bounds hotkey is ignored safely")
    func test_citationTray_outOfBoundsHotkey_ignoredSafely() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 2,
            citationCount: 2,
            hasFollowUpBar: true
        )

        // Valid hotkey Option+2 activates citation 2 (index 1)
        let handledValid = coordinator.handleOptionHotkey(number: 2)
        #expect(handledValid == true)
        #expect(coordinator.selectedCitationIndex == 1)
        #expect(coordinator.currentZone == .citationTray)

        // Out of bounds hotkey Option+7 ignored without state change or focus jump
        coordinator.setZone(.input)
        let handledInvalid = coordinator.handleOptionHotkey(number: 7)
        #expect(handledInvalid == false)
        #expect(coordinator.currentZone == .input)
    }
}
