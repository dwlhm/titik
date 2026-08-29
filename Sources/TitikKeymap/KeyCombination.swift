import Foundation

public struct KeyCombination: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let modifiers: KeyModifier
    public let key: Keycode

    public init(modifiers: KeyModifier, key: Keycode) {
        self.modifiers = modifiers
        self.key = key
    }

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Split by '+' or whitespace if multiple parts, or parse prefix modifiers
        let components = trimmed.components(separatedBy: "+")
        if components.count > 1 {
            let keyPart = components.last!.trimmingCharacters(in: .whitespaces)
            let modParts = components.dropLast().joined(separator: "+")
            guard let k = Keycode.fromString(keyPart) else { return nil }
            let m = KeyModifier.fromString(modParts)
            self.modifiers = m
            self.key = k
        } else {
            // Might be something like "cmd ." or single key
            let sub = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if sub.count > 1 {
                let keyPart = sub.last!
                let modParts = sub.dropLast().joined(separator: "+")
                guard let k = Keycode.fromString(keyPart) else { return nil }
                let m = KeyModifier.fromString(modParts)
                self.modifiers = m
                self.key = k
            } else if let k = Keycode.fromString(trimmed) {
                self.modifiers = .none
                self.key = k
            } else {
                return nil
            }
        }
    }

    public var description: String {
        return "\(modifiers.displayGlyphs)\(key.displayGlyph)"
    }
}
