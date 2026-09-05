import Foundation

public struct WindowConfig: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var cornerRadius: Double
    public var borderWidth: Double
    public var blurMaterial: String

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case cornerRadius = "corner_radius"
        case borderWidth = "border_width"
        case blurMaterial = "blur_material"
    }

    public init(
        width: Double = 720,
        height: Double = 460,
        cornerRadius: Double = 16.0,
        borderWidth: Double = 1.0,
        blurMaterial: String = "hud"
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.blurMaterial = blurMaterial
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 720
        self.height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 460
        self.cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 16.0
        self.borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 1.0
        self.blurMaterial = try container.decodeIfPresent(String.self, forKey: .blurMaterial) ?? "hud"
    }
}

public struct AnimationConfig: Codable, Equatable, Sendable {
    public var springStiffness: Double
    public var springDamping: Double
    public var springMass: Double
    public var windowOpenDuration: Double

    enum CodingKeys: String, CodingKey {
        case springStiffness = "spring_stiffness"
        case springDamping = "spring_damping"
        case springMass = "spring_mass"
        case windowOpenDuration = "window_open_duration"
    }

    public init(
        springStiffness: Double = 320.0,
        springDamping: Double = 28.0,
        springMass: Double = 1.0,
        windowOpenDuration: Double = 0.18
    ) {
        self.springStiffness = springStiffness
        self.springDamping = springDamping
        self.springMass = springMass
        self.windowOpenDuration = windowOpenDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.springStiffness = try container.decodeIfPresent(Double.self, forKey: .springStiffness) ?? 320.0
        self.springDamping = try container.decodeIfPresent(Double.self, forKey: .springDamping) ?? 28.0
        self.springMass = try container.decodeIfPresent(Double.self, forKey: .springMass) ?? 1.0
        self.windowOpenDuration = try container.decodeIfPresent(Double.self, forKey: .windowOpenDuration) ?? 0.18
    }
}

public struct HotkeyConfig: Codable, Equatable, Sendable {
    public var modifier: String
    public var key: String

    enum CodingKeys: String, CodingKey {
        case modifier
        case key
    }

    public init(modifier: String = "cmd", key: String = ".") {
        self.modifier = modifier
        self.key = key
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.modifier = try container.decodeIfPresent(String.self, forKey: .modifier) ?? "cmd"
        self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? "."
    }
}

public struct ThemeConfig: Codable, Equatable, Sendable {
    public var bgGlassTint: String
    public var borderColor: String
    public var textPrimary: String
    public var textSecondary: String
    public var textMuted: String
    public var accentColor: String
    public var selectionBg: String
    public var badgeBg: String
    public var cardBg: String

    enum CodingKeys: String, CodingKey {
        case bgGlassTint = "bg_glass_tint"
        case borderColor = "border_color"
        case textPrimary = "text_primary"
        case textSecondary = "text_secondary"
        case textMuted = "text_muted"
        case accentColor = "accent_color"
        case selectionBg = "selection_bg"
        case badgeBg = "badge_bg"
        case cardBg = "card_bg"
    }

    public init(
        bgGlassTint: String = "#0e101a24",
        borderColor: String = "#ffffff26",
        textPrimary: String = "#ffffff",
        textSecondary: String = "#cbd5e1",
        textMuted: String = "#94a3b8",
        accentColor: String = "#a5b4fc",
        selectionBg: String = "#a5b4fc2d",
        badgeBg: String = "#93c5fd33",
        cardBg: String = "#ffffff0f"
    ) {
        self.bgGlassTint = bgGlassTint
        self.borderColor = borderColor
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.accentColor = accentColor
        self.selectionBg = selectionBg
        self.badgeBg = badgeBg
        self.cardBg = cardBg
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bgGlassTint = try container.decodeIfPresent(String.self, forKey: .bgGlassTint) ?? "#0e101a24"
        self.borderColor = try container.decodeIfPresent(String.self, forKey: .borderColor) ?? "#ffffff26"
        self.textPrimary = try container.decodeIfPresent(String.self, forKey: .textPrimary) ?? "#ffffff"
        self.textSecondary = try container.decodeIfPresent(String.self, forKey: .textSecondary) ?? "#cbd5e1"
        self.textMuted = try container.decodeIfPresent(String.self, forKey: .textMuted) ?? "#94a3b8"
        self.accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? "#a5b4fc"
        self.selectionBg = try container.decodeIfPresent(String.self, forKey: .selectionBg) ?? "#a5b4fc2d"
        self.badgeBg = try container.decodeIfPresent(String.self, forKey: .badgeBg) ?? "#93c5fd33"
        self.cardBg = try container.decodeIfPresent(String.self, forKey: .cardBg) ?? "#ffffff0f"
    }
}

public struct LayoutConfig: Codable, Equatable, Sendable {
    public var splitRatio: Double
    public var itemHeight: Double
    public var searchBarHeight: Double
    public var footerHeight: Double
    public var fontSizeSearch: Double
    public var fontSizeTitle: Double
    public var fontSizeSubtitle: Double
    public var fontSizeBadge: Double
    public var fontSizePreview: Double

    enum CodingKeys: String, CodingKey {
        case splitRatio = "split_ratio"
        case itemHeight = "item_height"
        case searchBarHeight = "search_bar_height"
        case footerHeight = "footer_height"
        case fontSizeSearch = "font_size_search"
        case fontSizeTitle = "font_size_title"
        case fontSizeSubtitle = "font_size_subtitle"
        case fontSizeBadge = "font_size_badge"
        case fontSizePreview = "font_size_preview"
    }

    public init(
        splitRatio: Double = 0.60,
        itemHeight: Double = 44.0,
        searchBarHeight: Double = 56.0,
        footerHeight: Double = 36.0,
        fontSizeSearch: Double = 18,
        fontSizeTitle: Double = 15,
        fontSizeSubtitle: Double = 12,
        fontSizeBadge: Double = 10,
        fontSizePreview: Double = 13
    ) {
        self.splitRatio = splitRatio
        self.itemHeight = itemHeight
        self.searchBarHeight = searchBarHeight
        self.footerHeight = footerHeight
        self.fontSizeSearch = fontSizeSearch
        self.fontSizeTitle = fontSizeTitle
        self.fontSizeSubtitle = fontSizeSubtitle
        self.fontSizeBadge = fontSizeBadge
        self.fontSizePreview = fontSizePreview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.splitRatio = try container.decodeIfPresent(Double.self, forKey: .splitRatio) ?? 0.60
        self.itemHeight = try container.decodeIfPresent(Double.self, forKey: .itemHeight) ?? 44.0
        self.searchBarHeight = try container.decodeIfPresent(Double.self, forKey: .searchBarHeight) ?? 56.0
        self.footerHeight = try container.decodeIfPresent(Double.self, forKey: .footerHeight) ?? 36.0
        self.fontSizeSearch = try container.decodeIfPresent(Double.self, forKey: .fontSizeSearch) ?? 18
        self.fontSizeTitle = try container.decodeIfPresent(Double.self, forKey: .fontSizeTitle) ?? 15
        self.fontSizeSubtitle = try container.decodeIfPresent(Double.self, forKey: .fontSizeSubtitle) ?? 12
        self.fontSizeBadge = try container.decodeIfPresent(Double.self, forKey: .fontSizeBadge) ?? 10
        self.fontSizePreview = try container.decodeIfPresent(Double.self, forKey: .fontSizePreview) ?? 13
    }
}

public struct BehaviorsConfig: Codable, Equatable, Sendable {
    public var autoHideOnBlur: Bool
    public var maxClipboardHistory: Int
    public var showPreviewPane: Bool
    public var excludedApps: [String]

    enum CodingKeys: String, CodingKey {
        case autoHideOnBlur = "auto_hide_on_blur"
        case maxClipboardHistory = "max_clipboard_history"
        case showPreviewPane = "show_preview_pane"
        case excludedApps = "excluded_apps"
    }

    public init(
        autoHideOnBlur: Bool = true,
        maxClipboardHistory: Int = 100,
        showPreviewPane: Bool = true,
        excludedApps: [String] = []
    ) {
        self.autoHideOnBlur = autoHideOnBlur
        self.maxClipboardHistory = maxClipboardHistory
        self.showPreviewPane = showPreviewPane
        self.excludedApps = excludedApps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.autoHideOnBlur = try container.decodeIfPresent(Bool.self, forKey: .autoHideOnBlur) ?? true
        self.maxClipboardHistory = try container.decodeIfPresent(Int.self, forKey: .maxClipboardHistory) ?? 100
        self.showPreviewPane = try container.decodeIfPresent(Bool.self, forKey: .showPreviewPane) ?? true
        self.excludedApps = try container.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
    }
}

/// Plugin whitelist configuration.
/// Only plugin IDs explicitly listed here are ever loaded by the runtime.
/// absent → never loaded. true → enabled. false → disabled.
public struct PluginsConfig: Codable, Equatable, Sendable {
    public static let defaultRegistrations: [String: Bool] = [
        "titik.system.plugin": true,
        "titik.builtin.app": true,
        "titik.builtin.file": true,
        "titik.builtin.clipboard": true,
        "titik.builtin.system": true,
        "titik.builtin.calculator": true,
        "titik.builtin.emoji": true,
        "titik.plugin.zen": true,
        "titik.builtin.launcher": true,
        "titik.builtin.shortcuts": true
    ]

    /// Maps plugin reverse-DNS ID to its enabled state.
    public var registrations: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case registrations = "plugins"
    }

    public init(registrations: [String: Bool] = Self.defaultRegistrations) {
        self.registrations = registrations
    }

    public init(from decoder: Decoder) throws {
        var rawDict: [String: Bool]? = nil
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let dict = try? container.decodeIfPresent([String: Bool].self, forKey: .registrations) {
            rawDict = dict
        } else if let single = try? decoder.singleValueContainer(),
                  let dict = try? single.decode([String: Bool].self) {
            rawDict = dict
        }

        if let decoded = rawDict {
            var merged = Self.defaultRegistrations
            for (k, v) in decoded {
                merged[k] = v
            }
            self.registrations = merged
        } else {
            self.registrations = Self.defaultRegistrations
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(registrations)
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var window: WindowConfig
    public var animation: AnimationConfig
    public var hotkey: HotkeyConfig
    public var theme: ThemeConfig
    public var layout: LayoutConfig
    public var behaviors: BehaviorsConfig
    public var plugins: PluginsConfig
    public var shortcuts: [ShortcutConfig]

    enum CodingKeys: String, CodingKey {
        case window
        case animation
        case hotkey
        case theme
        case layout
        case behaviors
        case plugins
        case shortcuts
    }

    public init(
        window: WindowConfig = WindowConfig(),
        animation: AnimationConfig = AnimationConfig(),
        hotkey: HotkeyConfig = HotkeyConfig(),
        theme: ThemeConfig = ThemeConfig(),
        layout: LayoutConfig = LayoutConfig(),
        behaviors: BehaviorsConfig = BehaviorsConfig(),
        plugins: PluginsConfig = PluginsConfig(),
        shortcuts: [ShortcutConfig] = []
    ) {
        self.window = window
        self.animation = animation
        self.hotkey = hotkey
        self.theme = theme
        self.layout = layout
        self.behaviors = behaviors
        self.plugins = plugins
        self.shortcuts = shortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.window = try container.decodeIfPresent(WindowConfig.self, forKey: .window) ?? WindowConfig()
        self.animation = try container.decodeIfPresent(AnimationConfig.self, forKey: .animation) ?? AnimationConfig()
        self.hotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? HotkeyConfig()
        self.theme = try container.decodeIfPresent(ThemeConfig.self, forKey: .theme) ?? ThemeConfig()
        self.layout = try container.decodeIfPresent(LayoutConfig.self, forKey: .layout) ?? LayoutConfig()
        self.behaviors = try container.decodeIfPresent(BehaviorsConfig.self, forKey: .behaviors) ?? BehaviorsConfig()
        self.plugins = try container.decodeIfPresent(PluginsConfig.self, forKey: .plugins) ?? PluginsConfig()

        // Resilient shortcuts decoding: skips malformed entries without failing overall config decoding
        var decodedShortcuts: [ShortcutConfig] = []
        if let list = try? container.decodeIfPresent([SafeShortcutDecoder].self, forKey: .shortcuts) {
            decodedShortcuts = list.compactMap { $0.shortcut }
        } else if let dict = try? container.decodeIfPresent([String: SafeShortcutDictDecoder].self, forKey: .shortcuts) {
            decodedShortcuts = dict.values.compactMap { $0.shortcut }.sorted { $0.id < $1.id }
        }
        self.shortcuts = decodedShortcuts
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(window, forKey: .window)
        try container.encode(animation, forKey: .animation)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(theme, forKey: .theme)
        try container.encode(layout, forKey: .layout)
        try container.encode(behaviors, forKey: .behaviors)
        try container.encode(plugins, forKey: .plugins)
        try container.encode(shortcuts, forKey: .shortcuts)
    }
}

/// Helper wrapper that safely decodes a `ShortcutConfig` from a list and catches individual decoding errors.
private struct SafeShortcutDecoder: Decodable {
    let shortcut: ShortcutConfig?

    init(from decoder: Decoder) throws {
        do {
            self.shortcut = try ShortcutConfig(from: decoder)
        } catch {
            Logger.shared.warn(
                "Skipping malformed shortcut config entry: \(error.localizedDescription)",
                subsystem: "Titik.Config"
            )
            self.shortcut = nil
        }
    }
}

/// Helper wrapper that safely decodes a dictionary entry for shortcuts:
/// - Supports values that are full `ShortcutConfig` objects (e.g. `{"id": "toggle", ...}`).
/// - Supports values that are simple command strings (e.g. `{"cmd+shift+k": "!zen"}`),
///   creating a `ShortcutConfig` with key combination from key and target from value.
private struct SafeShortcutDictDecoder: Decodable {
    let shortcut: ShortcutConfig?

    init(from decoder: Decoder) throws {
        let dictKey = decoder.codingPath.last?.stringValue ?? ""

        // 1. Value is full ShortcutConfig object
        if let fullShortcut = try? ShortcutConfig(from: decoder) {
            self.shortcut = fullShortcut
            return
        }

        // 2. Value is an object where key combination comes from dictionary key if not present in object
        if let container = try? decoder.container(keyedBy: ShortcutConfig.CodingKeys.self) {
            let (key, mods) = ShortcutConfig.parseKeyCombinationString(dictKey)
            if !key.isEmpty {
                let name = try? container.decodeIfPresent(String.self, forKey: .name)
                let mode = try? container.decodeIfPresent(ShortcutExecutionMode.self, forKey: .mode)
                let action: ShortcutActionConfig?
                if container.contains(.action) {
                    action = try? container.decode(ShortcutActionConfig.self, forKey: .action)
                } else if let cmd = try? container.decodeIfPresent(String.self, forKey: .command) {
                    let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                    let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
                    action = ShortcutActionConfig(type: type, target: trimmed)
                } else if let target = try? container.decodeIfPresent(String.self, forKey: .target) {
                    let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
                    let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
                    action = ShortcutActionConfig(type: type, target: trimmed)
                } else if let query = try? container.decodeIfPresent(String.self, forKey: .query) {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
                    action = ShortcutActionConfig(type: type, target: trimmed)
                } else if let url = try? container.decodeIfPresent(String.self, forKey: .url) {
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    action = ShortcutActionConfig(type: .quickLink, target: trimmed)
                } else {
                    action = nil
                }

                if let action = action {
                    let id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? "\(mods.joined(separator: "_"))_\(key)"
                    self.shortcut = ShortcutConfig(
                        id: id,
                        name: name,
                        key: key,
                        modifiers: mods,
                        mode: mode,
                        action: action
                    )
                    return
                }
            }
        }

        // 3. Value is a simple command string, key is key combination
        if let single = try? decoder.singleValueContainer(),
           let commandString = try? single.decode(String.self) {
            let trimmed = commandString.trimmingCharacters(in: .whitespacesAndNewlines)
            let type: ShortcutActionType = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? .quickLink : .rawQuery
            let action = ShortcutActionConfig(type: type, target: trimmed)
            let (key, mods) = ShortcutConfig.parseKeyCombinationString(dictKey)
            if !key.isEmpty {
                let id = "\(mods.joined(separator: "_"))_\(key)"
                self.shortcut = ShortcutConfig(
                    id: id,
                    key: key,
                    modifiers: mods,
                    action: action
                )
                return
            }
        }

        Logger.shared.warn(
            "Skipping malformed shortcut dictionary entry for key '\(dictKey)'",
            subsystem: "Titik.Config"
        )
        self.shortcut = nil
    }
}


