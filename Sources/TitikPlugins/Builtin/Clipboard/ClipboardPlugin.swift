import Foundation
import AppKit
import TitikCore
import TitikPluginKit

/// Built-in Clipboard History plugin exposing clipboard search, recent history, and copy commands.
public final class ClipboardPlugin: TitikCommandPlugin, TitikStreamingPlugin, TitikGlobalSearchProvider, @unchecked Sendable {
    public static let id = "titik.builtin.clipboard"
    public static let name = "Clipboard History"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    private let clipboardManager: ClipboardManager

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "copy",
                name: "Copy to Clipboard",
                description: "Copy content or history item to system clipboard",
                triggers: ["clip", "copy"],
                arguments: [
                    PluginCommandArgument(name: "text", description: "Text content to copy", isRequired: true)
                ],
                defaultMode: .background
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
        self.clipboardManager = ClipboardManager.shared
    }

    public init(context: PluginContext, clipboardManager: ClipboardManager = .shared) {
        self.context = context
        self.clipboardManager = clipboardManager
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let text = invocation.primaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return CommandExecutionResult.failure(message: "Missing text argument to copy")
        }

        clipboardManager.copyToPasteboard(text)
        return CommandExecutionResult.success(
            message: "Copied to clipboard",
            outputPayload: ["text": text]
        )
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let primary = arguments["text"] ?? arguments["payload"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(trigger: "clip", action: id, primaryValue: primary, rawInput: context.rawInput)
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(invocation: PluginInvocation) async throws -> PluginCanvas {
        try await onQuery(invocation.primaryValue)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = clipboardManager.getItems()

        if trimmed.isEmpty {
            let pluginItems = items.map { clip in
                PluginItem(
                    id: "\(Self.id):\(clip.id.uuidString)",
                    title: clip.preview,
                    subtitle: "\(clip.lineCount) line(s)",
                    category: "Clipboard",
                    actionPayload: clip.content,
                    scoreBoost: 30,
                    pluginId: Self.id
                )
            }
            return .list(pluginItems)
        }

        var matched: [PluginItem] = []
        for clip in items {
            if let match = FuzzyMatcher.match(query: trimmed, target: clip.content), match.score > 0 {
                matched.append(
                    PluginItem(
                        id: "\(Self.id):\(clip.id.uuidString)",
                        title: clip.preview,
                        subtitle: "\(clip.lineCount) line(s)",
                        category: "Clipboard",
                        actionPayload: clip.content,
                        scoreBoost: match.score + 20,
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

        let items = clipboardManager.getItems()
        var results: [PluginItem] = []
        for clip in items {
            if let match = FuzzyMatcher.match(query: trimmed, target: clip.content), match.score > 0 {
                results.append(
                    PluginItem(
                        id: "\(Self.id):\(clip.id.uuidString)",
                        title: clip.preview,
                        subtitle: "\(clip.lineCount) line(s)",
                        category: "Clipboard",
                        actionPayload: clip.content,
                        scoreBoost: match.score + 20,
                        pluginId: Self.id
                    )
                )
            }
        }
        results.sort { $0.scoreBoost > $1.scoreBoost }
        return results
    }

    public func provideDefaultItems() async -> [PluginItem] {
        let clips = clipboardManager.getItems()
        return clips.prefix(3).map { clip in
            PluginItem(
                id: "\(Self.id):\(clip.id.uuidString)",
                title: clip.preview,
                subtitle: "Copied (\(clip.lineCount) lines)",
                category: "Clipboard",
                actionPayload: clip.content,
                scoreBoost: 80,
                pluginId: Self.id
            )
        }
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let clipboardPluginManifest = PluginManifest(
    id: ClipboardPlugin.id,
    name: ClipboardPlugin.name,
    version: ClipboardPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Search and manage clipboard history",
    entrypoint: "ClipboardPlugin",
    triggers: ["clip"]
)
