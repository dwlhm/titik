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
            id: AppPlugin.id,
            manifest: appPluginManifest,
            factory: { AppPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: FileBrowserPlugin.id,
            manifest: fileBrowserPluginManifest,
            factory: { FileBrowserPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: ClipboardPlugin.id,
            manifest: clipboardPluginManifest,
            factory: { ClipboardPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: SystemCommandsPlugin.id,
            manifest: systemCommandsPluginManifest,
            factory: { SystemCommandsPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: CalculatorPlugin.id,
            manifest: calculatorPluginManifest,
            factory: { CalculatorPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: EmojiPlugin.id,
            manifest: emojiPluginManifest,
            factory: { EmojiPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: LauncherPlugin.id,
            manifest: launcherPluginManifest,
            factory: { LauncherPlugin(context: $0) }
        ),
        BuiltinPluginEntry(
            id: ShortcutsPlugin.id,
            manifest: shortcutsPluginManifest,
            factory: { ShortcutsPlugin(context: $0) }
        )
    ]
}
