import Foundation
import AppKit
import TitikCore
import TitikPluginKit

/// Built-in File Browser plugin exposing filesystem browsing, path navigation, and file search.
public final class FileBrowserPlugin: TitikCommandPlugin, TitikStreamingPlugin, TitikGlobalSearchProvider, @unchecked Sendable {
    public static let id = "titik.builtin.file"
    public static let name = "File Browser"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    private let fileBrowser: FileBrowser

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "browse",
                name: "Browse Files",
                description: "Browse filesystem directory or search files",
                triggers: ["file", "browse", "open"],
                arguments: [
                    PluginCommandArgument(name: "path", description: "Directory path or search query", isRequired: false)
                ],
                defaultMode: .palette
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
        self.fileBrowser = FileBrowser.shared
    }

    public init(context: PluginContext, fileBrowser: FileBrowser = .shared) {
        self.context = context
        self.fileBrowser = fileBrowser
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let targetPath = invocation.primaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else {
            return CommandExecutionResult.failure(message: "Missing path argument")
        }

        let expanded = PathResolver.expandPath(targetPath)
        let url = URL(fileURLWithPath: expanded)
        let opened = NSWorkspace.shared.open(url)

        return CommandExecutionResult.success(
            message: "Opened \(expanded)",
            outputPayload: ["path": expanded, "opened": opened ? "true" : "false"]
        )
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let primary = arguments["path"] ?? arguments["payload"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(trigger: "file", action: id, primaryValue: primary, rawInput: context.rawInput)
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(invocation: PluginInvocation) async throws -> PluginCanvas {
        try await onQuery(invocation.primaryValue)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchItems: [SearchItem]

        if trimmed.isEmpty {
            searchItems = fileBrowser.browseDirectory(path: "~")
        } else if PathResolver.isPathQuery(trimmed) {
            searchItems = fileBrowser.browseDirectory(path: trimmed)
        } else {
            let fileSearchResults = fileBrowser.searchFiles(query: trimmed)
            if fileSearchResults.isEmpty {
                searchItems = fileBrowser.browseDirectory(path: trimmed)
            } else {
                searchItems = fileSearchResults
            }
        }

        let pluginItems = searchItems.map { item in
            PluginItem(
                id: item.id.hasPrefix(Self.id) ? item.id : "\(Self.id):\(item.id)",
                title: item.title,
                subtitle: item.subtitle,
                category: item.category.rawValue,
                actionPayload: item.actionPayload,
                scoreBoost: item.score,
                pluginId: Self.id
            )
        }

        return .list(pluginItems)
    }

    public func provideGlobalSearchResults(query: String) async -> [PluginItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let searchItems: [SearchItem]
        if PathResolver.isPathQuery(trimmed) {
            searchItems = fileBrowser.browseDirectory(path: trimmed)
        } else {
            searchItems = fileBrowser.searchFiles(query: trimmed)
        }

        return searchItems.map { item in
            PluginItem(
                id: item.id.hasPrefix(Self.id) ? item.id : "\(Self.id):\(item.id)",
                title: item.title,
                subtitle: item.subtitle,
                category: item.category.rawValue,
                actionPayload: item.actionPayload,
                scoreBoost: item.score,
                pluginId: Self.id
            )
        }
    }

    public func provideDefaultItems() async -> [PluginItem] {
        return []
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let fileBrowserPluginManifest = PluginManifest(
    id: FileBrowserPlugin.id,
    name: FileBrowserPlugin.name,
    version: FileBrowserPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Search files and browse filesystem",
    entrypoint: "FileBrowserPlugin",
    triggers: ["file"]
)
