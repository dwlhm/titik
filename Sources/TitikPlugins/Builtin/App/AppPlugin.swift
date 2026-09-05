import Foundation
import AppKit
import TitikCore
import TitikPluginKit

/// Built-in Applications plugin exposing application search, running app switching, and launch commands.
public final class AppPlugin: TitikCommandPlugin, TitikStreamingPlugin, TitikGlobalSearchProvider, @unchecked Sendable {
    public static let id = "titik.builtin.app"
    public static let name = "Applications"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    private let appLauncher: AppLauncher

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "launch",
                name: "Launch Application",
                description: "Launches an application by name or path",
                triggers: ["app", "launch"],
                arguments: [
                    PluginCommandArgument(name: "app", description: "Application name or path", isRequired: true)
                ],
                defaultMode: .background
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
        self.appLauncher = AppLauncher.shared
    }

    public init(context: PluginContext, appLauncher: AppLauncher = .shared) {
        self.context = context
        self.appLauncher = appLauncher
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let rawTarget = !invocation.primaryValue.isEmpty ? invocation.primaryValue : (invocation.action != "launch" ? (invocation.action ?? "") : "")
        let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            await self.context.summonHUD(query: "!app ")
            return CommandExecutionResult.success(
                message: "Summoned application list in HUD",
                outputPayload: ["action": "summonHUD", "query": "!app "]
            )
        }

        let expanded = PathResolver.expandPath(target)
        if FileManager.default.fileExists(atPath: expanded) {
            let success = appLauncher.launchApp(at: expanded)
            return CommandExecutionResult.success(
                message: "Launched application at \(expanded)",
                outputPayload: ["app": target, "path": expanded, "launched": success ? "true" : "false"]
            )
        }

        let apps = appLauncher.getApplications()
        let clean = target.lowercased().replacingOccurrences(of: ".app", with: "")
        if let match = apps.first(where: {
            $0.name.lowercased() == clean ||
            $0.bundleURL.deletingPathExtension().lastPathComponent.lowercased() == clean ||
            $0.path.lowercased().contains(clean)
        }) {
            let success = appLauncher.launchApp(at: match.path)
            return CommandExecutionResult.success(
                message: "Launched \(match.name)",
                outputPayload: ["app": match.name, "path": match.path, "launched": success ? "true" : "false"]
            )
        }

        return CommandExecutionResult.failure(message: "Application '\(target)' not found")
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let primary = arguments["app"] ?? arguments["payload"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(trigger: "app", action: id, primaryValue: primary, rawInput: context.rawInput)
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(invocation: PluginInvocation) async throws -> PluginCanvas {
        try await onQuery(invocation.primaryValue)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = await appLauncher.getApplicationsAsync()

        if trimmed.isEmpty {
            let items = apps.map { app in
                PluginItem(
                    id: "\(Self.id):\(app.path)",
                    title: app.name,
                    subtitle: app.path,
                    category: "Application",
                    actionPayload: app.name,
                    scoreBoost: 50,
                    pluginId: Self.id
                )
            }
            return .list(items)
        }

        var matched: [PluginItem] = []
        for app in apps {
            if let match = FuzzyMatcher.match(query: trimmed, target: app.name) {
                matched.append(
                    PluginItem(
                        id: "\(Self.id):\(app.path)",
                        title: app.name,
                        subtitle: app.path,
                        category: "Application",
                        actionPayload: app.name,
                        scoreBoost: match.score + 50,
                        pluginId: Self.id
                    )
                )
            }
        }

        matched.sort { $0.scoreBoost > $1.scoreBoost }
        return .list(matched)
    }

    public func provideGlobalSearchResults(query: String) async -> [PluginItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let apps = appLauncher.getApplications()
        var results: [PluginItem] = []
        for app in apps {
            if let match = FuzzyMatcher.match(query: trimmed, target: app.name) {
                results.append(
                    PluginItem(
                        id: "\(Self.id):\(app.path)",
                        title: app.name,
                        subtitle: app.path,
                        category: "Application",
                        actionPayload: app.path,
                        scoreBoost: match.score + 50,
                        pluginId: Self.id
                    )
                )
            }
        }
        results.sort { $0.scoreBoost > $1.scoreBoost }
        return results
    }

    public func provideDefaultItems() async -> [PluginItem] {
        let runningApps = appLauncher.getRunningApplications()
        return runningApps.map { app in
            PluginItem(
                id: "\(Self.id):running:\(app.bundleURL.path)",
                title: app.name,
                subtitle: "Running Application • Press Enter to switch",
                category: "Application",
                actionPayload: app.path,
                scoreBoost: 200,
                pluginId: Self.id
            )
        }
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let appPluginManifest = PluginManifest(
    id: AppPlugin.id,
    name: AppPlugin.name,
    version: AppPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Search and launch applications",
    entrypoint: "AppPlugin",
    triggers: ["app"]
)
