import Foundation
import AppKit

public enum PreviewType: Sendable, Equatable {
    case none
    case image(URL)
    case video(URL)
    case audio(URL)
    case pdf(URL)
    case code(URL, language: String?)
    case text(URL)
    case directory(URL, itemCount: Int)
    case fileMetadata(URL)
    case custom(detail: String)
}

public enum SearchCategory: String, Codable, CaseIterable, Sendable {
    case application = "Application"
    case systemCommand = "Command"
    case clipboard = "Clipboard"
    case calculator = "Calculator"
    case plugin = "Plugin"
    case custom = "Custom"
    case file = "File"
    case directory = "Folder"
    case emoji = "Emoji"

    public var badgeName: String {
        switch self {
        case .application: return "App"
        case .systemCommand: return "Command"
        case .clipboard: return "Clipboard"
        case .calculator: return "Math"
        case .plugin: return "Plugin"
        case .custom: return "Custom"
        case .file: return "File"
        case .directory: return "Folder"
        case .emoji: return "Emoji"
        }
    }
}

public struct ContextualAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let shortcut: String?
    public let icon: String
    public let action: @MainActor () -> Void

    public init(
        id: String,
        title: String,
        shortcut: String? = nil,
        icon: String,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.icon = icon
        self.action = action
    }
}

public struct SearchItem: Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: SearchCategory
    public let score: Int
    public let icon: NSImage?
    public let actionPayload: String
    public let action: @Sendable () -> Bool
    public let matchedIndices: [Int]
    public let previewDetail: String?
    public let previewType: PreviewType
    public let previewURL: URL?
    public let autocompletePayload: String?

    public var hasRichPreview: Bool {
        previewType != .none
    }

    public init(
        id: String,
        title: String,
        subtitle: String,
        category: SearchCategory,
        score: Int = 0,
        icon: NSImage? = nil,
        actionPayload: String = "",
        matchedIndices: [Int] = [],
        previewDetail: String? = nil,
        previewType: PreviewType = .none,
        previewURL: URL? = nil,
        autocompletePayload: String? = nil,
        action: @escaping @Sendable () -> Bool = { true }
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.score = score
        self.icon = icon
        self.actionPayload = actionPayload
        self.matchedIndices = matchedIndices
        self.previewDetail = previewDetail
        self.previewType = previewType
        self.previewURL = previewURL
        self.autocompletePayload = autocompletePayload
        self.action = action
    }
}
