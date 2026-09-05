import Foundation
import SwiftUI
import AppKit
import TitikCore
import TitikPluginKit
import TitikUI
import TitikKeymap

/// Built-in emoji picker plugin exposing search via !emoji and !e.
public final class EmojiPlugin: TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.builtin.emoji"
    public static let name = "Emoji Picker"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    nonisolated public var pluginId: String { Self.id }
    @MainActor public lazy var keymapScope = PluginKeymapScope()
    @MainActor public var onDismiss: (@MainActor () -> Void)?

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "copy",
                name: "Copy and Paste Emoji",
                description: "Copies emoji to clipboard and pastes into active app",
                triggers: ["emoji", "e", "copy"],
                arguments: [
                    PluginCommandArgument(name: "emoji", description: "Emoji character or search term", isRequired: true)
                ],
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
        let rawTarget = !invocation.primaryValue.isEmpty ? invocation.primaryValue : (invocation.action != "copy" ? (invocation.action ?? "") : "")
        let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return CommandExecutionResult.failure(message: "Missing emoji argument")
        }

        let emojiToCopy: String
        let catalog = EmojiCatalog.shared
        if catalog.allEmojis.contains(where: { $0.emoji == target }) {
            emojiToCopy = target
        } else if let match = catalog.search(query: target).first {
            emojiToCopy = match.emoji
        } else {
            emojiToCopy = target
        }

        ClipboardManager.shared.copyToPasteboard(emojiToCopy)

        // Synthesize paste (Cmd+V) if event creation succeeds
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        return CommandExecutionResult.success(
            message: "Copied and pasted \(emojiToCopy)",
            outputPayload: ["emoji": emojiToCopy]
        )
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let primary = arguments["emoji"] ?? arguments["payload"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(trigger: "emoji", action: id, primaryValue: primary, rawInput: context.rawInput)
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(invocation: PluginInvocation) async throws -> PluginCanvas {
        try await onQuery(invocation.primaryValue)
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

@MainActor
extension EmojiPlugin: PluginUIRepresentable {
    public var customView: AnyView {
        AnyView(EmojiGridView(plugin: TitikUI.EmojiPlugin.shared))
    }

    public func onActivated() {
        keymapScope.removeAll()
        keymapScope.register("↵", label: "Paste") { TitikUI.EmojiPlugin.shared.submitQuery() }
        keymapScope.register("⇥", label: "Category") { TitikUI.EmojiPlugin.shared.nextCategory() }
        keymapScope.register("⇧⇥") { TitikUI.EmojiPlugin.shared.previousCategory() }
        keymapScope.register("←") { TitikUI.EmojiPlugin.shared.moveSelection(deltaX: -1, deltaY: 0, columns: 8) }
        keymapScope.register("→") { TitikUI.EmojiPlugin.shared.moveSelection(deltaX: 1, deltaY: 0, columns: 8) }
        keymapScope.register("↑") { TitikUI.EmojiPlugin.shared.moveSelection(deltaX: 0, deltaY: -1, columns: 8) }
        keymapScope.register("↓") { TitikUI.EmojiPlugin.shared.moveSelection(deltaX: 0, deltaY: 1, columns: 8) }
        keymapScope.register("esc", label: "Close") { [weak self] in self?.onDismiss?() }

        TitikUI.EmojiPlugin.shared.onSelectEmoji = { [weak self] emoji in
            let success = AutoPaster.shared.pasteToActiveApp(content: emoji.emoji)
            if success {
                self?.onDismiss?()
            }
        }
    }

    public func handleSearchQuery(_ query: String) {
        TitikUI.EmojiPlugin.shared.handleSearchQuery(query)
    }

    public func submitQuery() {
        TitikUI.EmojiPlugin.shared.submitQuery()
    }

    public func handleAction(actionId: String, payload: String) -> Bool {
        TitikUI.EmojiPlugin.shared.handleAction(actionId: actionId, payload: payload)
    }

    public func scrollTo(targetId: String, anchor: UnitPoint) {
        TitikUI.EmojiPlugin.shared.scrollTo(targetId: targetId, anchor: anchor)
    }
}

public let emojiPluginManifest = PluginManifest(
    id: EmojiPlugin.id,
    name: EmojiPlugin.name,
    version: EmojiPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Search and copy emojis via bang",
    entrypoint: "EmojiPlugin",
    triggers: ["emoji", "e"]
)
