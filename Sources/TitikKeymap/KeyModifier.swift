import Foundation
import AppKit
import Carbon

public struct KeyModifier: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifier(rawValue: 1 << 0)
    public static let option  = KeyModifier(rawValue: 1 << 1)
    public static let control = KeyModifier(rawValue: 1 << 2)
    public static let shift   = KeyModifier(rawValue: 1 << 3)
    public static let none: KeyModifier = []

    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option)  { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift)   { flags |= UInt32(shiftKey) }
        return flags
    }

    public var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option)  { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift)   { flags.insert(.shift) }
        return flags
    }

    public static func from(carbonFlags: UInt32) -> KeyModifier {
        var mod: KeyModifier = []
        if (carbonFlags & UInt32(cmdKey)) != 0 { mod.insert(.command) }
        if (carbonFlags & UInt32(optionKey)) != 0 { mod.insert(.option) }
        if (carbonFlags & UInt32(controlKey)) != 0 { mod.insert(.control) }
        if (carbonFlags & UInt32(shiftKey)) != 0 { mod.insert(.shift) }
        return mod
    }

    public static func from(nsFlags: NSEvent.ModifierFlags) -> KeyModifier {
        var mod: KeyModifier = []
        if nsFlags.contains(.command) { mod.insert(.command) }
        if nsFlags.contains(.option)  { mod.insert(.option) }
        if nsFlags.contains(.control) { mod.insert(.control) }
        if nsFlags.contains(.shift)   { mod.insert(.shift) }
        return mod
    }

    public static func fromString(_ str: String) -> KeyModifier {
        var mod: KeyModifier = []
        let parts = str.lowercased().components(separatedBy: CharacterSet(charactersIn: "+,|- "))
        for part in parts {
            let clean = part.trimmingCharacters(in: .whitespaces)
            switch clean {
            case "cmd", "command", "super":
                mod.insert(.command)
            case "alt", "opt", "option":
                mod.insert(.option)
            case "ctrl", "control":
                mod.insert(.control)
            case "shift":
                mod.insert(.shift)
            default:
                break
            }
        }
        return mod
    }

    public var displayGlyphs: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}
