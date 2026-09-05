import Foundation

/// Defines whether a global shortcut executes in the background silently or brings up the palette HUD.
public enum ShortcutExecutionMode: String, Codable, Sendable, CaseIterable, Equatable {
    case background
    case palette

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "background", "bg", "silent":
            self = .background
        case "palette", "hud", "window", "interactive":
            self = .palette
        default:
            if let mode = ShortcutExecutionMode(rawValue: raw) {
                self = mode
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid shortcut execution mode: '\(raw)'. Expected 'background' or 'palette'."
                )
            }
        }
    }
}

/// The discrete action type triggered by a shortcut.
public enum ShortcutActionType: String, Codable, Sendable, CaseIterable, Equatable {
    case pluginCommand
    case appLaunch
    case quickLink
    case rawQuery
    case toggleWindow
    case systemCommand

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.lowercased().replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "plugincommand", "plugin_command", "plugin", "command":
            self = .pluginCommand
        case "applaunch", "app_launch", "app", "launch", "application":
            self = .appLaunch
        case "quicklink", "quick_link", "link", "url", "open_url":
            self = .quickLink
        case "rawquery", "raw_query", "query", "search", "bang":
            self = .rawQuery
        case "togglewindow", "toggle_window", "toggle", "hud":
            self = .toggleWindow
        case "systemcommand", "system_command", "system", "sys":
            self = .systemCommand
        default:
            if let val = ShortcutActionType(rawValue: raw) {
                self = val
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown shortcut action type: '\(raw)'."
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// Action payload and destination for a shortcut.
public struct ShortcutActionConfig: Codable, Sendable, Equatable {
    public var type: ShortcutActionType
    public var target: String
    public var arguments: [String: String]?

    public init(
        type: ShortcutActionType,
        target: String,
        arguments: [String: String]? = nil
    ) {
        self.type = type
        self.target = target
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey {
        case type
        case target
        case arguments
        case args
        case pluginId = "plugin_id"
        case command
        case appPath = "app_path"
        case url
        case commandId = "command_id"
    }

    public init(from decoder: Decoder) throws {
        // Shorthand string action decoding: e.g. "action": "!zen" or "action": "https://apple.com"
        if let singleContainer = try? decoder.singleValueContainer(),
           let rawString = try? singleContainer.decode(String.self) {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                self.type = .quickLink
            } else {
                self.type = .rawQuery
            }
            self.target = trimmed
            self.arguments = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Flexible target decoding: check target first, then known alias keys
        let decodedTarget: String
        if let t = try container.decodeIfPresent(String.self, forKey: .target) {
            decodedTarget = t
        } else if let p = try container.decodeIfPresent(String.self, forKey: .pluginId) {
            decodedTarget = p
        } else if let u = try container.decodeIfPresent(String.self, forKey: .url) {
            decodedTarget = u
        } else if let a = try container.decodeIfPresent(String.self, forKey: .appPath) {
            decodedTarget = a
        } else if let c = try container.decodeIfPresent(String.self, forKey: .command) {
            decodedTarget = c
        } else if let cid = try container.decodeIfPresent(String.self, forKey: .commandId) {
            decodedTarget = cid
        } else {
            decodedTarget = ""
        }
        self.target = decodedTarget

        // Flexible type decoding: optional, defaults based on target/url prefix
        if let decodedType = try container.decodeIfPresent(ShortcutActionType.self, forKey: .type) {
            self.type = decodedType
        } else if !decodedTarget.isEmpty {
            let trimmed = decodedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                self.type = .quickLink
            } else {
                self.type = .rawQuery
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ShortcutActionConfig requires either 'type' or a valid target/command/url."
                )
            )
        }

        // Flexible arguments decoding: supports dictionary or string array
        if let dict = (try? container.decodeIfPresent([String: String].self, forKey: .arguments)) ?? nil {
            self.arguments = dict
        } else if let dict = (try? container.decodeIfPresent([String: String].self, forKey: .args)) ?? nil {
            self.arguments = dict
        } else if let array = (try? container.decodeIfPresent([String].self, forKey: .args)) ?? nil {
            var map: [String: String] = [:]
            for (idx, item) in array.enumerated() {
                map[String(idx)] = item
            }
            map["args"] = array.joined(separator: " ")
            self.arguments = map
        } else if let array = (try? container.decodeIfPresent([String].self, forKey: .arguments)) ?? nil {
            var map: [String: String] = [:]
            for (idx, item) in array.enumerated() {
                map[String(idx)] = item
            }
            map["args"] = array.joined(separator: " ")
            self.arguments = map
        } else {
            self.arguments = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(arguments, forKey: .arguments)
    }
}

/// Configuration for a single global hotkey shortcut binding.
public struct ShortcutConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String?
    public var key: String
    public var modifiers: [String]
    public var mode: ShortcutExecutionMode?
    public var action: ShortcutActionConfig

    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        key: String,
        modifiers: [String] = [],
        mode: ShortcutExecutionMode? = nil,
        action: ShortcutActionConfig
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.modifiers = modifiers
        self.mode = mode
        self.action = action
    }

    /// Convenience initializer that parses key and modifiers from a shortcut string (e.g. "cmd+shift+k" or "opt+space").
    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        shortcut: String,
        mode: ShortcutExecutionMode? = nil,
        action: ShortcutActionConfig
    ) {
        let (parsedKey, parsedMods) = Self.parseKeyCombinationString(shortcut)
        self.id = id
        self.name = name
        self.key = parsedKey
        self.modifiers = parsedMods
        self.mode = mode
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case key
        case keys
        case shortcut
        case modifiers
        case mode
        case action
        case command
        case target
        case query
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.mode = try container.decodeIfPresent(ShortcutExecutionMode.self, forKey: .mode)

        // Resilient action decoding: nested action (object or shorthand string), or top-level command/target/query/url
        if container.contains(.action) {
            self.action = try container.decode(ShortcutActionConfig.self, forKey: .action)
        } else if let cmd = try container.decodeIfPresent(String.self, forKey: .command) {
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
            self.action = ShortcutActionConfig(type: type, target: trimmed)
        } else if let target = try container.decodeIfPresent(String.self, forKey: .target) {
            let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
            let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
            self.action = ShortcutActionConfig(type: type, target: trimmed)
        } else if let query = try container.decodeIfPresent(String.self, forKey: .query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
            self.action = ShortcutActionConfig(type: type, target: trimmed)
        } else if let url = try container.decodeIfPresent(String.self, forKey: .url) {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            self.action = ShortcutActionConfig(type: .quickLink, target: trimmed)
        } else {
            self.action = try container.decode(ShortcutActionConfig.self, forKey: .action)
        }

        // Resilient key & modifiers decoding
        if let rawKey = try container.decodeIfPresent(String.self, forKey: .key),
           let rawMods = try container.decodeIfPresent([String].self, forKey: .modifiers) {
            if rawKey.contains("+") || rawKey.contains(" ") {
                let (k, m) = Self.parseKeyCombinationString(rawKey)
                self.key = k
                self.modifiers = Array(Set(rawMods + m)).sorted()
            } else {
                self.key = rawKey
                self.modifiers = rawMods
            }
        } else if let rawKeys = try container.decodeIfPresent(String.self, forKey: .keys) {
            let (k, m) = Self.parseKeyCombinationString(rawKeys)
            self.key = k
            self.modifiers = m
        } else if let rawShortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) {
            let (k, m) = Self.parseKeyCombinationString(rawShortcut)
            self.key = k
            self.modifiers = m
        } else if let rawKey = try container.decodeIfPresent(String.self, forKey: .key) {
            let (k, m) = Self.parseKeyCombinationString(rawKey)
            self.key = k
            self.modifiers = m
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .key,
                in: container,
                debugDescription: "Shortcut must specify 'key' or 'keys' / 'shortcut'."
            )
        }

        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(self.modifiers.joined(separator: "_"))_\(self.key)"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encode(action, forKey: .action)
    }

    /// Formatted combination string such as "cmd+shift+k".
    public var keyCombinationString: String {
        if modifiers.isEmpty {
            return key
        }
        return "\(modifiers.joined(separator: "+"))+\(key)"
    }

    /// Parses a string like "cmd+shift+k", "⌘⇧K", "cmd++", "opt space" into key and normalized modifiers.
    public static func parseKeyCombinationString(_ string: String) -> (key: String, modifiers: [String]) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("", [])
        }

        var modifiers: [String] = []
        var remaining = trimmed

        // 1. Detect and extract modifier glyphs
        let glyphMap: [(glyph: Character, mod: String)] = [
            ("⌘", "cmd"),
            ("⌥", "opt"),
            ("⌃", "ctrl"),
            ("⇧", "shift")
        ]

        for (glyph, mod) in glyphMap {
            if remaining.contains(glyph) {
                if !modifiers.contains(mod) {
                    modifiers.append(mod)
                }
                remaining.removeAll { $0 == glyph }
            }
        }

        remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Protect trailing characters: "+", "-", "="
        var protectedKey: String? = nil

        if remaining == "+" || remaining == "-" || remaining == "=" {
            protectedKey = remaining
            remaining = ""
        } else if remaining.hasSuffix("++") {
            protectedKey = "+"
            remaining = String(remaining.dropLast(1))
        } else if remaining.hasSuffix("+-") {
            protectedKey = "-"
            remaining = String(remaining.dropLast(1))
        } else if remaining.hasSuffix("+=") {
            protectedKey = "="
            remaining = String(remaining.dropLast(1))
        } else if remaining.hasSuffix("--") {
            protectedKey = "-"
            remaining = String(remaining.dropLast(1))
        } else if remaining.hasSuffix(" +") {
            protectedKey = "+"
            remaining = String(remaining.dropLast(2))
        } else if remaining.hasSuffix(" -") {
            protectedKey = "-"
            remaining = String(remaining.dropLast(2))
        } else if remaining.hasSuffix(" =") {
            protectedKey = "="
            remaining = String(remaining.dropLast(2))
        }

        // 3. Tokenize remaining parts
        let separators = CharacterSet(charactersIn: "+- ")
        let rawTokens = remaining.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let modifierMap: [String: String] = [
            "cmd": "cmd", "command": "cmd", "super": "cmd", "meta": "cmd", "win": "cmd", "windows": "cmd",
            "opt": "opt", "option": "opt", "alt": "opt",
            "ctrl": "ctrl", "control": "ctrl",
            "shift": "shift",
            "fn": "fn", "function": "fn"
        ]

        var parsedKey: String = protectedKey ?? ""

        for (idx, rawToken) in rawTokens.enumerated() {
            let lower = rawToken.lowercased()
            if let canonicalMod = modifierMap[lower] {
                if !modifiers.contains(canonicalMod) {
                    modifiers.append(canonicalMod)
                }
            } else {
                if protectedKey == nil {
                    if idx == rawTokens.count - 1 || parsedKey.isEmpty {
                        parsedKey = lower
                    }
                }
            }
        }

        return (parsedKey, modifiers)
    }
}
