import Foundation
import TitikCore
import TitikPluginKit

public struct BuiltinPluginEntry: Sendable {
    public let id: String
    public let manifest: PluginManifest
    public let factory: @Sendable (PluginContext) -> any TitikPlugin

    public init(id: String, manifest: PluginManifest, factory: @escaping @Sendable (PluginContext) -> any TitikPlugin) {
        self.id = id
        self.manifest = manifest
        self.factory = factory
    }
}

public enum BuiltinPluginRegistry {
    public static let all: [BuiltinPluginEntry] = [
        BuiltinPluginEntry(
            id: PluginSystemPlugin.id,
            manifest: pluginSystemManifest,
            factory: { PluginSystemPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: EmojiPlugin.id,
            manifest: emojiPluginManifest,
            factory: { EmojiPlugin(context: $0) }
        )
    ]
}
