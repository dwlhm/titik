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
        bgGlassTint: String = "#14162838",
        borderColor: String = "#ffffff14",
        textPrimary: String = "#ffffff",
        textSecondary: String = "#cbd5e1",
        textMuted: String = "#94a3b8",
        accentColor: String = "#a5b4fc",
        selectionBg: String = "#a5b4fc2d",
        badgeBg: String = "#93c5fd33",
        cardBg: String = "#ffffff0c"
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
        self.bgGlassTint = try container.decodeIfPresent(String.self, forKey: .bgGlassTint) ?? "#14162838"
        self.borderColor = try container.decodeIfPresent(String.self, forKey: .borderColor) ?? "#ffffff14"
        self.textPrimary = try container.decodeIfPresent(String.self, forKey: .textPrimary) ?? "#ffffff"
        self.textSecondary = try container.decodeIfPresent(String.self, forKey: .textSecondary) ?? "#cbd5e1"
        self.textMuted = try container.decodeIfPresent(String.self, forKey: .textMuted) ?? "#94a3b8"
        self.accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? "#a5b4fc"
        self.selectionBg = try container.decodeIfPresent(String.self, forKey: .selectionBg) ?? "#a5b4fc2d"
        self.badgeBg = try container.decodeIfPresent(String.self, forKey: .badgeBg) ?? "#93c5fd33"
        self.cardBg = try container.decodeIfPresent(String.self, forKey: .cardBg) ?? "#ffffff0c"
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

public struct Config: Codable, Equatable, Sendable {
    public var window: WindowConfig
    public var animation: AnimationConfig
    public var hotkey: HotkeyConfig
    public var theme: ThemeConfig
    public var layout: LayoutConfig
    public var behaviors: BehaviorsConfig

    enum CodingKeys: String, CodingKey {
        case window
        case animation
        case hotkey
        case theme
        case layout
        case behaviors
    }

    public init(
        window: WindowConfig = WindowConfig(),
        animation: AnimationConfig = AnimationConfig(),
        hotkey: HotkeyConfig = HotkeyConfig(),
        theme: ThemeConfig = ThemeConfig(),
        layout: LayoutConfig = LayoutConfig(),
        behaviors: BehaviorsConfig = BehaviorsConfig()
    ) {
        self.window = window
        self.animation = animation
        self.hotkey = hotkey
        self.theme = theme
        self.layout = layout
        self.behaviors = behaviors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.window = try container.decodeIfPresent(WindowConfig.self, forKey: .window) ?? WindowConfig()
        self.animation = try container.decodeIfPresent(AnimationConfig.self, forKey: .animation) ?? AnimationConfig()
        self.hotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? HotkeyConfig()
        self.theme = try container.decodeIfPresent(ThemeConfig.self, forKey: .theme) ?? ThemeConfig()
        self.layout = try container.decodeIfPresent(LayoutConfig.self, forKey: .layout) ?? LayoutConfig()
        self.behaviors = try container.decodeIfPresent(BehaviorsConfig.self, forKey: .behaviors) ?? BehaviorsConfig()
    }
}
