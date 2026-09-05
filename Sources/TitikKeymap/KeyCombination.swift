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
        guard !trimmed.isEmpty, trimmed != "+" else { return nil }

        // 1. Check if string contains symbol glyphs like "⌘K" or "⌥Space"
        let glyphChars: Set<Character> = ["⌘", "⌥", "⌃", "⇧"]
        if trimmed.contains(where: { glyphChars.contains($0) }) {
            let glyphPart = String(trimmed.filter { glyphChars.contains($0) })
            let rawRest = String(trimmed.filter { !glyphChars.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
            let restPart = (rawRest == "+" || rawRest == "-" || rawRest == "=") ? rawRest : rawRest.trimmingCharacters(in: CharacterSet(charactersIn: "+- \t"))
            if let k = Keycode.fromString(restPart) {
                let m = KeyModifier.fromString(glyphPart)
                self.modifiers = m
                self.key = k
                return
            }
        }

        // 2. Split by '+', '-', or whitespace
        let separators = CharacterSet(charactersIn: "+- \t")
        var tokens = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }

        // Handle cases where the key itself is "-" or "+" that got stripped at the end
        if (trimmed.hasSuffix("+-") || trimmed.hasSuffix("--") || trimmed.hasSuffix(" -")) && (tokens.last != "-" && tokens.last != "minus") {
            tokens.append("-")
        } else if (trimmed.hasSuffix("++") || trimmed.hasSuffix("-+") || trimmed.hasSuffix(" +")) && (tokens.last != "+" && tokens.last != "plus" && tokens.last != "equal") {
            tokens.append("+")
        }

        if tokens.count > 1, let keyPart = tokens.last {
            let modParts = tokens.dropLast().joined(separator: "+")
            guard let k = Keycode.fromString(keyPart) else { return nil }
            let m = KeyModifier.fromString(modParts)
            self.modifiers = m
            self.key = k
            return
        }

        if let k = Keycode.fromString(trimmed) {
            self.modifiers = .none
            self.key = k
            return
        }

        return nil
    }

    public var description: String {
        return "\(modifiers.displayGlyphs)\(key.displayGlyph)"
    }
}

extension KeyCombination: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let combo = KeyCombination(string: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid key combination string: '\(string)'"
            )
        }
        self = combo
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
