import Foundation
import AppKit
import TitikCore
@_exported import enum TitikCore.FuzzyMatcher
@_exported import struct TitikCore.FuzzyMatchResult
import TitikParser
import TitikPlugins
import TitikPluginKit

public final class SearchEngine: @unchecked Sendable {
    public static let shared = SearchEngine()

    private let appLauncher: AppLauncher
    private let systemCommands: SystemCommands
    private let clipboardManager: ClipboardManager
    private let pluginHost: PluginHost
    private let fileBrowser: FileBrowser
    private let parser: CommandParser

    public init(
        appLauncher: AppLauncher = .shared,
        systemCommands: SystemCommands = .shared,
        clipboardManager: ClipboardManager = .shared,
        pluginHost: PluginHost = .shared,
        fileBrowser: FileBrowser = .shared,
        parser: CommandParser = CommandParser()
    ) {
        self.appLauncher = appLauncher
        self.systemCommands = systemCommands
        self.clipboardManager = clipboardManager
        self.pluginHost = pluginHost
        self.fileBrowser = fileBrowser
        self.parser = parser
    }

    public func search(query: String) -> [SearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Path search check using PathResolver
        if PathResolver.isPathQuery(trimmed) {
            return fileBrowser.browseDirectory(path: trimmed)
        }

        let ast = parser.parse(query)
        var items: [SearchItem] = []

        switch ast {
        case .empty:
            items = getDefaultItems()

        case .bangSuggestion(let prefix):
            let suggestions = getBangSuggestions()
            if prefix.isEmpty {
                return suggestions
            }
            let lower = "!" + prefix.lowercased()
            let filtered = suggestions.filter { item in
                let titleWord = item.title.components(separatedBy: " ").first?.lowercased() ?? item.title.lowercased()
                let payloadWord = item.actionPayload.trimmingCharacters(in: .whitespaces).lowercased()
                return titleWord.hasPrefix(lower) || payloadWord.hasPrefix(lower) || item.id.lowercased().contains(lower)
            }
            return filtered.isEmpty ? searchAllProviders(query: prefix) : filtered

        case .expression(let exprAST):
            // Math evaluation result
            if let mathItem = evaluateMath(exprAST, rawQuery: trimmed, scoreBoost: 500) {
                items.append(mathItem)
            }
            // Also search other items in background with lower priority
            items.append(contentsOf: searchApplications(query: trimmed))
            items.append(contentsOf: searchSystemCommands(query: trimmed))

        case .command(let name, let args, _):
            if let manifest = pluginHost.findActivePlugin(command: name) {
                let subquery = args.joined(separator: " ")
                nonisolated(unsafe) var pluginItems: [PluginItem] = []
                let sema = DispatchSemaphore(value: 0)
                Task {
                    let (_, stream) = pluginHost.query(pluginId: manifest.id, query: subquery)
                    for await response in stream {
                        if case .listResult(_, let items) = response {
                            pluginItems = items
                        }
                    }
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + .milliseconds(1500))

                return pluginItems.map { pItem in
                    let searchCategory: SearchCategory
                    if manifest.id == "titik.builtin.emoji" || pItem.category.lowercased() == "emoji" {
                        searchCategory = .emoji
                    } else {
                        searchCategory = .plugin
                    }
                    return SearchItem(
                        id: "\(manifest.id):\(pItem.id)",
                        title: pItem.title,
                        subtitle: pItem.subtitle,
                        category: searchCategory,
                        score: pItem.scoreBoost + 500,
                        actionPayload: pItem.actionPayload,
                        previewDetail: "\(pItem.title)\n\(pItem.subtitle)",
                        action: { [weak self] in
                            if pItem.pluginId == "titik.system.plugin" || manifest.id == "titik.system.plugin" {
                                if pItem.actionPayload == "reload" {
                                    PluginManager.shared.reindex()
                                    return true
                                }
                            }
                            if !pItem.actionPayload.isEmpty {
                                self?.clipboardManager.copyToPasteboard(pItem.actionPayload)
                                return true
                            }
                            return false
                        }
                    )
                }
            }

            let argQuery = args.joined(separator: " ")
            switch name.lowercased() {
            case "app", "apps", "application":
                items = searchApplications(query: argQuery)
            case "cmd", "sys", "system", "command":
                items = searchSystemCommands(query: argQuery)
            case "clip", "clipboard", "cb":
                items = searchClipboard(query: argQuery)
            case "emoji", "emojis", "e":
                if argQuery.isEmpty {
                    var emojiResults: [SearchItem] = []
                    if let bangEmoji = getBangSuggestions().first(where: { $0.id == "bang:emoji" }) {
                        let bangItem = SearchItem(
                            id: bangEmoji.id,
                            title: bangEmoji.title,
                            subtitle: bangEmoji.subtitle,
                            category: bangEmoji.category,
                            score: 200,
                            actionPayload: bangEmoji.actionPayload,
                            autocompletePayload: bangEmoji.autocompletePayload
                        )
                        emojiResults.append(bangItem)
                    }
                    emojiResults.append(contentsOf: searchEmojis(query: ""))
                    return emojiResults
                } else {
                    return searchEmojis(query: argQuery)
                }
            case "file", "f", "open", "folder", "browse", "find", "dir":
                if argQuery.isEmpty {
                    items = fileBrowser.browseDirectory(path: "~")
                } else if PathResolver.isPathQuery(argQuery) {
                    items = fileBrowser.browseDirectory(path: argQuery)
                } else {
                    let fileSearchResults = fileBrowser.searchFiles(query: argQuery)
                    if fileSearchResults.isEmpty {
                        items = fileBrowser.browseDirectory(path: argQuery)
                    } else {
                        items = fileSearchResults
                    }
                }
            case "calc", "math", "calculate":
                let mathAST = parser.parse(argQuery)
                if case .expression(let expr) = mathAST,
                   let mathItem = evaluateMath(expr, rawQuery: argQuery, scoreBoost: 600) {
                    items.append(mathItem)
                }
            default:
                // General search with this query
                items = searchAllProviders(query: trimmed)
            }

        case .raw(let rawQuery):
            // Check if it can be evaluated as math
            let mathAST = parser.parse("= " + rawQuery)
            if case .expression(let expr) = mathAST,
               let mathItem = evaluateMath(expr, rawQuery: rawQuery, scoreBoost: 300) {
                items.append(mathItem)
            }

            items.append(contentsOf: searchAllProviders(query: rawQuery))
        }

        // Sort descending by score
        items.sort { $0.score > $1.score }
        return items
    }

    public func getBangSuggestions() -> [SearchItem] {
        var suggestions: [SearchItem] = [
            SearchItem(
                id: "bang:emoji",
                title: "!emoji",
                subtitle: "Search & paste emojis with interactive grid",
                category: .emoji,
                score: 100,
                actionPayload: "!emoji ",
                autocompletePayload: "!emoji "
            ),
            SearchItem(
                id: "bang:file",
                title: "!file <path/name>",
                subtitle: "Search files or browse filesystem",
                category: .file,
                score: 95,
                actionPayload: "!file ",
                autocompletePayload: "!file "
            ),
            SearchItem(
                id: "bang:app",
                title: "!app <name>",
                subtitle: "Scope search to applications",
                category: .application,
                score: 90,
                actionPayload: "!app ",
                autocompletePayload: "!app "
            ),
            SearchItem(
                id: "bang:clip",
                title: "!clip <query>",
                subtitle: "Search clipboard history",
                category: .clipboard,
                score: 85,
                actionPayload: "!clip ",
                autocompletePayload: "!clip "
            ),
            SearchItem(
                id: "bang:cmd",
                title: "!cmd <command>",
                subtitle: "Scope search to system commands",
                category: .systemCommand,
                score: 80,
                actionPayload: "!cmd ",
                autocompletePayload: "!cmd "
            )
        ]

        let nativePlugins = pluginHost.allNativePlugins()
        for native in nativePlugins {
            for bang in native.manifest.normalizedBangs {
                let clean = bang.lowercased()
                suggestions.append(
                    SearchItem(
                        id: "bang:\(native.manifest.id):\(clean)",
                        title: "!\(clean) <query>",
                        subtitle: native.manifest.description,
                        category: .plugin,
                        score: 75,
                        actionPayload: "!\(clean) ",
                        autocompletePayload: "!\(clean) "
                    )
                )
            }
        }

        return suggestions
    }

    public func searchEmojis(query: String) -> [SearchItem] {
        let emojis = EmojiCatalog.shared.search(query: query)
        return emojis.map { emoji in
            SearchItem(
                id: "emoji:\(emoji.emoji)",
                title: "\(emoji.emoji)  \(emoji.name)",
                subtitle: "\(emoji.shortcode) • \(emoji.category.rawValue)",
                category: .emoji,
                score: 75,
                actionPayload: emoji.emoji,
                previewDetail: "Emoji: \(emoji.emoji)\nName: \(emoji.name)\nShortcode: \(emoji.shortcode)\nCategory: \(emoji.category.rawValue)\nUnicode: \(emoji.unicodeHex)\nKeywords: \(emoji.keywords.joined(separator: ", "))",
                action: { [weak self] in
                    self?.clipboardManager.copyToPasteboard(emoji.emoji)
                    return true
                }
            )
        }
    }

    private func searchAllProviders(query: String) -> [SearchItem] {
        var results: [SearchItem] = []
        results.append(contentsOf: searchApplications(query: query))
        results.append(contentsOf: searchSystemCommands(query: query))
        results.append(contentsOf: searchClipboard(query: query))
        results.append(contentsOf: fileBrowser.searchFiles(query: query))
        return results
    }

    private func getDefaultItems() -> [SearchItem] {
        var items: [SearchItem] = []

        // Running Applications
        let runningApps = appLauncher.getRunningApplications()
        for app in runningApps {
            items.append(
                SearchItem(
                    id: "running:\(app.bundleURL.path)",
                    title: app.name,
                    subtitle: "Running Application • Press Enter to switch",
                    category: .application,
                    score: 200,
                    icon: app.icon,
                    actionPayload: app.path,
                    previewDetail: "Running Application: \(app.name)\nPath: \(app.path)",
                    previewType: .none,
                    previewURL: app.bundleURL,
                    action: { [weak self] in
                        self?.appLauncher.activateRunningApp(bundleURL: app.bundleURL, processIdentifier: app.processIdentifier) ?? false
                    }
                )
            )
        }

        // System Commands
        let cmds = systemCommands.getAllCommands()
        for cmd in cmds.prefix(4) {
            items.append(
                SearchItem(
                    id: cmd.id,
                    title: cmd.title,
                    subtitle: cmd.subtitle,
                    category: .systemCommand,
                    score: 90,
                    actionPayload: cmd.id,
                    previewDetail: "macOS System Command: \(cmd.title)\n\(cmd.subtitle)",
                    previewType: .none,
                    action: { cmd.action() }
                )
            )
        }

        // Recent Clipboard Items
        let clips = clipboardManager.getItems()
        for clip in clips.prefix(3) {
            items.append(
                SearchItem(
                    id: "clip:\(clip.id.uuidString)",
                    title: clip.preview,
                    subtitle: "Copied (\(clip.lineCount) lines)",
                    category: .clipboard,
                    score: 80,
                    actionPayload: clip.content,
                    previewDetail: clip.content,
                    previewType: .none,
                    action: { [weak self] in
                        self?.clipboardManager.copyToPasteboard(clip.content)
                        return true
                    }
                )
            )
        }

        return items
    }

    private func searchApplications(query: String) -> [SearchItem] {
        let apps = appLauncher.getApplications()
        var results: [SearchItem] = []

        for app in apps {
            if query.isEmpty {
                results.append(
                    SearchItem(
                        id: "app:\(app.path)",
                        title: app.name,
                        subtitle: app.path,
                        category: .application,
                        score: 50,
                        icon: app.icon,
                        actionPayload: app.path,
                        previewDetail: "Application: \(app.name)\nPath: \(app.path)",
                        action: { [weak self] in
                            self?.appLauncher.launchApp(at: app.path) ?? false
                        }
                    )
                )
            } else if let match = FuzzyMatcher.match(query: query, target: app.name) {
                results.append(
                    SearchItem(
                        id: "app:\(app.path)",
                        title: app.name,
                        subtitle: app.path,
                        category: .application,
                        score: match.score + 50, // Base app preference bonus
                        icon: app.icon,
                        actionPayload: app.path,
                        matchedIndices: match.matchedIndices,
                        previewDetail: "Application: \(app.name)\nPath: \(app.path)",
                        action: { [weak self] in
                            self?.appLauncher.launchApp(at: app.path) ?? false
                        }
                    )
                )
            }
        }
        return results
    }

    private func searchSystemCommands(query: String) -> [SearchItem] {
        let cmds = systemCommands.getAllCommands()
        var results: [SearchItem] = []

        for cmd in cmds {
            if query.isEmpty {
                results.append(
                    SearchItem(
                        id: cmd.id,
                        title: cmd.title,
                        subtitle: cmd.subtitle,
                        category: .systemCommand,
                        score: 40,
                        actionPayload: cmd.id,
                        previewDetail: "macOS System Command: \(cmd.title)\n\(cmd.subtitle)",
                        action: { cmd.action() }
                    )
                )
                continue
            }

            var bestScore: Int? = nil
            var bestIndices: [Int] = []

            if let titleMatch = FuzzyMatcher.match(query: query, target: cmd.title) {
                bestScore = titleMatch.score
                bestIndices = titleMatch.matchedIndices
            }

            for kw in cmd.keywords {
                if let kwMatch = FuzzyMatcher.match(query: query, target: kw) {
                    let score = kwMatch.score - 10
                    if bestScore == nil || score > bestScore! {
                        bestScore = score
                    }
                }
            }

            if let score = bestScore {
                results.append(
                    SearchItem(
                        id: cmd.id,
                        title: cmd.title,
                        subtitle: cmd.subtitle,
                        category: .systemCommand,
                        score: score + 40,
                        actionPayload: cmd.id,
                        matchedIndices: bestIndices,
                        previewDetail: "macOS System Command: \(cmd.title)\n\(cmd.subtitle)",
                        action: { cmd.action() }
                    )
                )
            }
        }
        return results
    }

    private func searchClipboard(query: String) -> [SearchItem] {
        let items = clipboardManager.getItems()
        var results: [SearchItem] = []

        for clip in items {
            if query.isEmpty {
                results.append(
                    SearchItem(
                        id: "clip:\(clip.id.uuidString)",
                        title: clip.preview,
                        subtitle: "\(clip.lineCount) line(s)",
                        category: .clipboard,
                        score: 30,
                        actionPayload: clip.content,
                        previewDetail: clip.content,
                        action: { [weak self] in
                            self?.clipboardManager.copyToPasteboard(clip.content)
                            return true
                        }
                    )
                )
            } else if let match = FuzzyMatcher.match(query: query, target: clip.content) {
                results.append(
                    SearchItem(
                        id: "clip:\(clip.id.uuidString)",
                        title: clip.preview,
                        subtitle: "\(clip.lineCount) line(s)",
                        category: .clipboard,
                        score: match.score + 20,
                        actionPayload: clip.content,
                        matchedIndices: match.matchedIndices,
                        previewDetail: clip.content,
                        action: { [weak self] in
                            self?.clipboardManager.copyToPasteboard(clip.content)
                            return true
                        }
                    )
                )
            }
        }
        return results
    }

    private func evaluateMath(_ ast: MathExpressionAST, rawQuery: String, scoreBoost: Int) -> SearchItem? {
        do {
            let result = try MathEvaluator.evaluate(ast)
            let formatted = MathEvaluator.formatResult(result)
            return SearchItem(
                id: "math:result",
                title: formatted,
                subtitle: "\(rawQuery)  (Press Enter to copy)",
                category: .calculator,
                score: scoreBoost + 200,
                actionPayload: formatted,
                previewDetail: "Expression: \(rawQuery)\nResult: \(formatted)",
                action: { [weak self] in
                    self?.clipboardManager.copyToPasteboard(formatted)
                    return true
                }
            )
        } catch {
            return nil
        }
    }
}
