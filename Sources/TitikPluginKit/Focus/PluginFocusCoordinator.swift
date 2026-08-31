import Foundation
import AppKit
import SwiftUI
import TitikKeymap

public enum FocusZone: String, CaseIterable, Sendable, Equatable {
    case input
    case body
    case mediaRail
    case citationTray
    case followUpBar
}

@MainActor
public final class PluginFocusCoordinator: ObservableObject {
    @Published public var currentZone: FocusZone = .input
    @Published public var selectedMediaIndex: Int = 0
    @Published public var selectedCitationIndex: Int = 0

    public var mediaCount: Int = 0 {
        didSet {
            clampIndices()
        }
    }
    public var citationCount: Int = 0 {
        didSet {
            clampIndices()
        }
    }
    public var hasFollowUpBar: Bool = true

    public var onCitationActivated: ((Int) -> Void)?
    public var onMediaActivated: ((Int) -> Void)?
    public var onSubmitFollowUp: ((String) -> Void)?

    public init(
        initialZone: FocusZone = .input,
        mediaCount: Int = 0,
        citationCount: Int = 0,
        hasFollowUpBar: Bool = true
    ) {
        self.currentZone = initialZone
        self.mediaCount = mediaCount
        self.citationCount = citationCount
        self.hasFollowUpBar = hasFollowUpBar
        clampIndices()
    }

    public var activeZones: [FocusZone] {
        var zones: [FocusZone] = [.input, .body]
        if mediaCount > 0 {
            zones.append(.mediaRail)
        }
        if citationCount > 0 {
            zones.append(.citationTray)
        }
        if hasFollowUpBar {
            zones.append(.followUpBar)
        }
        return zones
    }

    public func setZone(_ zone: FocusZone) {
        let available = activeZones
        if available.contains(zone) {
            currentZone = zone
        } else if let first = available.first {
            currentZone = first
        }
    }

    public func next() {
        let zones = activeZones
        guard !zones.isEmpty else { return }

        if let currentIndex = zones.firstIndex(of: currentZone) {
            let nextIndex = (currentIndex + 1) % zones.count
            currentZone = zones[nextIndex]
        } else {
            currentZone = zones.first ?? .input
        }
    }

    public func previous() {
        let zones = activeZones
        guard !zones.isEmpty else { return }

        if let currentIndex = zones.firstIndex(of: currentZone) {
            let prevIndex = (currentIndex - 1 + zones.count) % zones.count
            currentZone = zones[prevIndex]
        } else {
            currentZone = zones.last ?? .input
        }
    }

    public func clampIndices() {
        if mediaCount <= 0 {
            selectedMediaIndex = 0
        } else {
            selectedMediaIndex = max(0, min(selectedMediaIndex, mediaCount - 1))
        }

        if citationCount <= 0 {
            selectedCitationIndex = 0
        } else {
            selectedCitationIndex = max(0, min(selectedCitationIndex, citationCount - 1))
        }

        let zones = activeZones
        if !zones.contains(currentZone) {
            currentZone = zones.first ?? .input
        }
    }

    public func nextMedia() {
        guard mediaCount > 0 else { return }
        selectedMediaIndex = min(selectedMediaIndex + 1, mediaCount - 1)
    }

    public func previousMedia() {
        guard mediaCount > 0 else { return }
        selectedMediaIndex = max(selectedMediaIndex - 1, 0)
    }

    public func nextCitation() {
        guard citationCount > 0 else { return }
        selectedCitationIndex = min(selectedCitationIndex + 1, citationCount - 1)
    }

    public func previousCitation() {
        guard citationCount > 0 else { return }
        selectedCitationIndex = max(selectedCitationIndex - 1, 0)
    }

    public func handleOptionHotkey(number: Int) -> Bool {
        guard number >= 1 && number <= citationCount else {
            // Out of bounds hotkey ignored without error or focus jump
            return false
        }
        selectedCitationIndex = number - 1
        currentZone = .citationTray
        onCitationActivated?(selectedCitationIndex)
        return true
    }

    public func handleKeyDown(event: NSEvent) -> Bool {
        let code = UInt32(event.keyCode)
        let isShift = event.modifierFlags.contains(.shift)
        let isOption = event.modifierFlags.contains(.option)
        let isCommand = event.modifierFlags.contains(.command)

        // 1. Check Option + 1..9 for citations
        if isOption && !isCommand {
            let keyToNumber: [UInt32: Int] = [
                18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
            ]
            if let num = keyToNumber[code] {
                return handleOptionHotkey(number: num)
            }
        }

        // 2. Tab / Shift+Tab focus navigation
        if code == Keycode.tab.rawValue {
            if isShift {
                previous()
            } else {
                next()
            }
            return true
        }

        // 3. Zone-specific arrow / activation keys
        switch currentZone {
        case .mediaRail:
            if code == Keycode.leftArrow.rawValue {
                previousMedia()
                return true
            } else if code == Keycode.rightArrow.rawValue {
                nextMedia()
                return true
            } else if code == Keycode.returnKey.rawValue || code == Keycode.space.rawValue {
                onMediaActivated?(selectedMediaIndex)
                return true
            }

        case .citationTray:
            if code == Keycode.leftArrow.rawValue {
                previousCitation()
                return true
            } else if code == Keycode.rightArrow.rawValue {
                nextCitation()
                return true
            } else if code == Keycode.returnKey.rawValue || code == Keycode.space.rawValue {
                onCitationActivated?(selectedCitationIndex)
                return true
            }

        case .followUpBar:
            // Let the input field handle regular typing, return key sends follow up
            break

        case .input, .body:
            break
        }

        return false
    }
}
