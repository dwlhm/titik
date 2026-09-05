import Foundation
import AppKit
import TitikCore
import TitikPluginKit

/// Built-in System Commands plugin exposing macOS system command search, execution, and shortcuts.
public final class SystemCommandsPlugin: TitikCommandPlugin, TitikStreamingPlugin, TitikGlobalSearchProvider, @unchecked Sendable {
    public static let id = "titik.builtin.system"
    public static let name = "System Commands"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    private let systemCommands: SystemCommands

    public var commands: [PluginCommandDefinition] {
        systemCommands.getAllCommands().map { cmd in
            PluginCommandDefinition(
                id: cmd.id,
                name: cmd.title,
                description: cmd.subtitle,
                triggers: ["cmd", cmd.id],
                arguments: [],
                defaultMode: .background
            )
        }
    }

    public required init(context: PluginContext) {
        self.context = context
        self.systemCommands = SystemCommands.shared
    }

    public init(context: PluginContext, systemCommands: SystemCommands = .shared) {
        self.context = context
        self.systemCommands = systemCommands
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        var targetId = invocation.action ?? (!invocation.primaryValue.isEmpty ? invocation.primaryValue : invocation.trigger)
        if targetId == "cmd" || targetId == Self.id {
            if !invocation.primaryValue.isEmpty {
                targetId = invocation.primaryValue
            }
        }
        if let argId = invocation.flag("id") {
            targetId = argId
        }

        let allCmds = systemCommands.getAllCommands()
        let resolvedId: String
        let resolvedTitle: String
        if let direct = systemCommands.findCommand(by: targetId) {
            resolvedId = direct.id
            resolvedTitle = direct.title
        } else if let prefixed = systemCommands.findCommand(by: "system.\(targetId)") {
            resolvedId = prefixed.id
            resolvedTitle = prefixed.title
        } else if let match = allCmds.first(where: {
            $0.id.replacingOccurrences(of: "system.", with: "") == targetId ||
            $0.title.localizedCaseInsensitiveContains(targetId)
        }) {
            resolvedId = match.id
            resolvedTitle = match.title
        } else {
            return CommandExecutionResult.failure(message: "System command '\(targetId)' not found")
        }

        let success = SystemCommands.shared.executeCommand(by: resolvedId)
        return CommandExecutionResult.success(
            message: "Executed \(resolvedTitle)",
            outputPayload: ["command": resolvedId, "executed": success ? "true" : "false"]
        )
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let argId = arguments["id"] ?? arguments["payload"] ?? arguments["0"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(
            trigger: context.trigger,
            action: id,
            primaryValue: argId,
            flags: [:],
            rawInput: context.rawInput
        )
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cmds = systemCommands.getAllCommands()

        if trimmed.isEmpty {
            let pluginItems = cmds.map { cmd in
                PluginItem(
                    id: "\(Self.id):\(cmd.id)",
                    title: cmd.title,
                    subtitle: cmd.subtitle,
                    category: "System Command",
                    actionPayload: cmd.id,
                    scoreBoost: 40,
                    pluginId: Self.id
                )
            }
            return .list(pluginItems)
        }

        var results: [PluginItem] = []
        for cmd in cmds {
            var bestScore: Int? = nil

            if let titleMatch = FuzzyMatcher.match(query: trimmed, target: cmd.title) {
                bestScore = titleMatch.score
            }

            for kw in cmd.keywords {
                if let kwMatch = FuzzyMatcher.match(query: trimmed, target: kw) {
                    let score = kwMatch.score - 10
                    bestScore = max(bestScore ?? score, score)
                }
            }

            if let score = bestScore {
                results.append(
                    PluginItem(
                        id: "\(Self.id):\(cmd.id)",
                        title: cmd.title,
                        subtitle: cmd.subtitle,
                        category: "System Command",
                        actionPayload: cmd.id,
                        scoreBoost: score + 40,
                        pluginId: Self.id
                    )
                )
            }
        }

        results.sort { $0.scoreBoost > $1.scoreBoost }
        return .list(results)
    }

    public func provideGlobalSearchResults(query: String) async -> [PluginItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let cmds = systemCommands.getAllCommands()
        var results: [PluginItem] = []

        for cmd in cmds {
            var bestScore: Int? = nil

            if let titleMatch = FuzzyMatcher.match(query: trimmed, target: cmd.title) {
                bestScore = titleMatch.score
            }

            for kw in cmd.keywords {
                if let kwMatch = FuzzyMatcher.match(query: trimmed, target: kw) {
                    let score = kwMatch.score - 10
                    bestScore = max(bestScore ?? score, score)
                }
            }

            if let score = bestScore {
                results.append(
                    PluginItem(
                        id: "\(Self.id):\(cmd.id)",
                        title: cmd.title,
                        subtitle: cmd.subtitle,
                        category: "System Command",
                        actionPayload: cmd.id,
                        scoreBoost: score + 40,
                        pluginId: Self.id
                    )
                )
            }
        }

        results.sort { $0.scoreBoost > $1.scoreBoost }
        return results
    }

    public func provideDefaultItems() async -> [PluginItem] {
        let cmds = systemCommands.getAllCommands()
        return cmds.prefix(4).map { cmd in
            PluginItem(
                id: "\(Self.id):\(cmd.id)",
                title: cmd.title,
                subtitle: cmd.subtitle,
                category: "System Command",
                actionPayload: cmd.id,
                scoreBoost: 90,
                pluginId: Self.id
            )
        }
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let systemCommandsPluginManifest = PluginManifest(
    id: SystemCommandsPlugin.id,
    name: SystemCommandsPlugin.name,
    version: SystemCommandsPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Execute macOS system commands",
    entrypoint: "SystemCommandsPlugin",
    triggers: ["cmd"]
)
