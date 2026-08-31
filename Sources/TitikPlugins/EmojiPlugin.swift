import Foundation
import TitikCore
import TitikPluginKit

/// Built-in emoji picker plugin exposing search via !emoji and !e.
public final class EmojiPlugin: TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.builtin.emoji"
    public static let name = "Emoji Picker"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext

    public required init(context: PluginContext) {
        self.context = context
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results: [EmojiItem]
        if trimmed.isEmpty {
            results = Array(EmojiCatalog.shared.allEmojis.prefix(50))
        } else {
            results = EmojiCatalog.shared.search(query: trimmed)
        }

        let items = results.map { emoji in
            PluginItem(
                id: "emoji:\(emoji.emoji)",
                title: "\(emoji.emoji)  \(emoji.name)",
                subtitle: "\(emoji.shortcode) • \(emoji.category.rawValue)",
                category: "Emoji",
                actionPayload: emoji.emoji,
                scoreBoost: 500,
                pluginId: Self.id
            )
        }
        return PluginCanvas.list(items)
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let emojiPluginManifest = PluginManifest(
    id: EmojiPlugin.id,
    name: EmojiPlugin.name,
    version: EmojiPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Search and copy emojis via bang",
    entrypoint: "EmojiPlugin",
    triggers: ["!emoji", "!e"]
)
