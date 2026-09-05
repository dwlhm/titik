import Foundation
import TitikCore
import TitikPluginKit
import TitikKeymap

/// First-party plugin exposing the plugin management system via !plugin.
/// Only supported command: !plugin reload
public final class PluginSystemPlugin: TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.system.plugin"
    public static let name = "Plugin System"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "reload",
                name: "Reload Plugins",
                description: "Reload and reindex all plugins from config and disk",
                triggers: ["plugin", "reload"],
                arguments: [],
                defaultMode: .background
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        await MainActor.run {
            ShortcutManager.shared.reloadFromConfig()
        }
        return CommandExecutionResult.success(
            message: "Plugins and shortcuts reloaded",
            outputPayload: ["action": "reload"]
        )
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let invocation = PluginInvocation(
            trigger: context.trigger,
            action: id,
            primaryValue: arguments["0"] ?? arguments["args"] ?? "",
            flags: [:],
            rawInput: context.rawInput
        )
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "reload":
            return .list([
                PluginItem(
                    id: "plugin.system.reload",
                    title: "Reload Plugins",
                    subtitle: "Re-read config.json and rescan ~/.config/titik/plugins/",
                    category: "System",
                    actionPayload: "reload",
                    scoreBoost: 500
                )
            ])
        default:
            return .list([
                PluginItem(
                    id: "plugin.system.hint",
                    title: "!plugin reload",
                    subtitle: "Reload and reindex all plugins from config and disk",
                    category: "System",
                    actionPayload: "",
                    scoreBoost: 100
                )
            ])
        }
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

/// The manifest used when registering PluginSystemPlugin at startup.
public let pluginSystemManifest = PluginManifest(
    id: PluginSystemPlugin.id,
    name: PluginSystemPlugin.name,
    version: PluginSystemPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Manage and reload Titik plugins",
    entrypoint: "PluginSystemPlugin",
    triggers: ["plugin"]
)
