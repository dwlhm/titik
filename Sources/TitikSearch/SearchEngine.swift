import Foundation
import AppKit
import TitikCore
@_exported import enum TitikCore.FuzzyMatcher
@_exported import struct TitikCore.FuzzyMatchResult
import TitikParser
import TitikPlugins
import TitikPluginKit
import TitikKeymap

public final class SearchEngine: @unchecked Sendable {
    public static let shared = SearchEngine()
    public nonisolated(unsafe) static var pluginCommandDispatcher: (@Sendable (_ pluginId: String, _ payload: String) -> Bool)?

    private let pluginHost: PluginHost
    private let parser: CommandParser

    public init(
        pluginHost: PluginHost = .shared,
        parser: CommandParser = CommandParser()
    ) {
        self.pluginHost = pluginHost
        self.parser = parser

        // Auto-register default built-in plugins if host has no registered plugins yet
        if pluginHost.allNativePlugins().isEmpty {
            for entry in BuiltinPluginRegistry.all {
                let plugin = entry.factory(PluginContext(pluginId: entry.id))
                pluginHost.registerNativePlugin(plugin, manifest: entry.manifest)
            }
        }
    }

    public func search(query: String) -> [SearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

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
            let cleanPrefix = prefix.lowercased()
            let lower = "!" + cleanPrefix

            let isShortPrefix = cleanPrefix.count == 1
            if !isShortPrefix, let manifest = pluginHost.findActivePlugin(command: cleanPrefix) {
                let queried = queryPluginSync(manifest: manifest, subquery: "")
                if !queried.isEmpty {
                    return queried
                }
            }

            let filtered = suggestions.filter { item in
                let titleWord = item.title.components(separatedBy: " ").first?.lowercased() ?? item.title.lowercased()
                let payloadWord = item.actionPayload.trimmingCharacters(in: .whitespaces).lowercased()
                return titleWord.hasPrefix(lower) || payloadWord.hasPrefix(lower) || item.id == "bang:\(cleanPrefix)"
            }
            return filtered.isEmpty ? searchAllGlobalProviders(query: prefix) : filtered

        case .expression, .raw:
            items = searchAllGlobalProviders(query: trimmed)

        case .command(let name, let args, _):
            if let manifest = pluginHost.findActivePlugin(command: name) {
                let subquery = args.joined(separator: " ")
                return queryPluginSync(manifest: manifest, subquery: subquery)
            }
            items = searchAllGlobalProviders(query: trimmed)

        case .pluginInvocation(let trigger, let action, let primaryValue, let flags, let booleanFlags, _):
            if let manifest = pluginHost.findActivePlugin(command: trigger) {
                var effectiveAction = action
                var effectivePrimary = primaryValue
                var effectiveFlags = flags
                var effectiveBoolFlags = booleanFlags

                if action == nil, let cmdPlugin = pluginHost.getNativePlugin(id: manifest.id) as? (any TitikCommandPlugin) {
                    let knownSubcommands = Set(cmdPlugin.commands.flatMap { [$0.id.lowercased()] + $0.triggers.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "!")) } })
                    if !knownSubcommands.isEmpty {
                        let reAst = parser.parse(query, knownSubcommands: knownSubcommands)
                        if case .pluginInvocation(_, let reAction, let rePrimary, let reFlags, let reBoolFlags, _) = reAst {
                            effectiveAction = reAction
                            effectivePrimary = rePrimary
                            effectiveFlags = reFlags
                            effectiveBoolFlags = reBoolFlags
                        }
                    }
                }

                var flagValues: [String: FlagValue] = [:]
                for b in effectiveBoolFlags {
                    flagValues[b] = .boolean(true)
                }
                for (k, v) in effectiveFlags {
                    if !effectiveBoolFlags.contains(k) {
                        flagValues[k] = .string(v)
                    }
                }

                let invocation = PluginInvocation(
                    trigger: trigger,
                    action: effectiveAction,
                    primaryValue: effectivePrimary,
                    flags: flagValues,
                    rawInput: query
                )
                return queryPluginSync(manifest: manifest, invocation: invocation)
            }
            items = searchAllGlobalProviders(query: trimmed)
        }

        // Sort descending by score
        items.sort { $0.score > $1.score }
        return items
    }

    public func searchAsync(query: String) async -> [SearchItem] {
        if Task.isCancelled { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let ast = parser.parse(query)
        var items: [SearchItem] = []

        switch ast {
        case .empty:
            items = await getDefaultItemsAsync()

        case .bangSuggestion(let prefix):
            if Task.isCancelled { return [] }
            let suggestions = getBangSuggestions()
            if prefix.isEmpty {
                return suggestions
            }
            let cleanPrefix = prefix.lowercased()
            let lower = "!" + cleanPrefix

            let isShortPrefix = cleanPrefix.count == 1
            if !isShortPrefix, let manifest = pluginHost.findActivePlugin(command: cleanPrefix) {
                let queried = await queryPluginAsync(manifest: manifest, subquery: "")
                if !queried.isEmpty {
                    return queried
                }
            }

            let filtered = suggestions.filter { item in
                let titleWord = item.title.components(separatedBy: " ").first?.lowercased() ?? item.title.lowercased()
                let payloadWord = item.actionPayload.trimmingCharacters(in: .whitespaces).lowercased()
                return titleWord.hasPrefix(lower) || payloadWord.hasPrefix(lower) || item.id == "bang:\(cleanPrefix)"
            }
            return filtered.isEmpty ? await searchAllGlobalProvidersAsync(query: prefix) : filtered

        case .expression, .raw:
            items = await searchAllGlobalProvidersAsync(query: trimmed)

        case .command(let name, let args, _):
            if let manifest = pluginHost.findActivePlugin(command: name) {
                let subquery = args.joined(separator: " ")
                return await queryPluginAsync(manifest: manifest, subquery: subquery)
            }
            items = await searchAllGlobalProvidersAsync(query: trimmed)

        case .pluginInvocation(let trigger, let action, let primaryValue, let flags, let booleanFlags, _):
            if let manifest = pluginHost.findActivePlugin(command: trigger) {
                var effectiveAction = action
                var effectivePrimary = primaryValue
                var effectiveFlags = flags
                var effectiveBoolFlags = booleanFlags

                if action == nil, let cmdPlugin = pluginHost.getNativePlugin(id: manifest.id) as? (any TitikCommandPlugin) {
                    let knownSubcommands = Set(cmdPlugin.commands.flatMap { [$0.id.lowercased()] + $0.triggers.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "!")) } })
                    if !knownSubcommands.isEmpty {
                        let reAst = parser.parse(query, knownSubcommands: knownSubcommands)
                        if case .pluginInvocation(_, let reAction, let rePrimary, let reFlags, let reBoolFlags, _) = reAst {
                            effectiveAction = reAction
                            effectivePrimary = rePrimary
                            effectiveFlags = reFlags
                            effectiveBoolFlags = reBoolFlags
                        }
                    }
                }

                var flagValues: [String: FlagValue] = [:]
                for b in effectiveBoolFlags {
                    flagValues[b] = .boolean(true)
                }
                for (k, v) in effectiveFlags {
                    if !effectiveBoolFlags.contains(k) {
                        flagValues[k] = .string(v)
                    }
                }

                let invocation = PluginInvocation(
                    trigger: trigger,
                    action: effectiveAction,
                    primaryValue: effectivePrimary,
                    flags: flagValues,
                    rawInput: query
                )
                return await queryPluginAsync(manifest: manifest, invocation: invocation)
            }
            items = await searchAllGlobalProvidersAsync(query: trimmed)
        }

        if Task.isCancelled { return [] }
        // Sort descending by score
        items.sort { $0.score > $1.score }
        return items
    }

    public func getBangSuggestions() -> [SearchItem] {
        var suggestions: [SearchItem] = []
        let nativePlugins = pluginHost.allNativePlugins()

        for native in nativePlugins {
            let manifest = native.manifest
            let searchCategory = categoryForPlugin(id: manifest.id)
            let baseScore = scoreForPlugin(id: manifest.id)

            for bang in manifest.normalizedBangs {
                let clean = bang.lowercased()
                let bangId = "bang:\(clean)"
                if !suggestions.contains(where: { $0.id == bangId || $0.id == "bang:\(manifest.id):\(clean)" }) {
                    suggestions.append(
                        SearchItem(
                            id: bangId,
                            title: "!\(clean)",
                            subtitle: manifest.description,
                            category: searchCategory,
                            score: baseScore,
                            actionPayload: "!\(clean) ",
                            autocompletePayload: "!\(clean) "
                        )
                    )
                }
            }

            if let cmdPlugin = native.plugin as? (any TitikCommandPlugin) {
                for cmd in cmdPlugin.commands {
                    for trigger in cmd.triggers {
                        let cleanTrigger = trigger.trimmingCharacters(in: CharacterSet(charactersIn: "!")).lowercased()
                        let bangId = "bang:\(manifest.id):\(cmd.id):\(cleanTrigger)"
                        if !suggestions.contains(where: { $0.id == bangId || $0.id == "bang:\(cleanTrigger)" }) {
                            let argNames = cmd.arguments.map(\.name).joined(separator: ", ")
                            let argHint = argNames.isEmpty ? "" : " <\(argNames)>"
                            suggestions.append(
                                SearchItem(
                                    id: bangId,
                                    title: "!\(cleanTrigger)\(argHint)",
                                    subtitle: "\(cmd.name) — \(cmd.description)",
                                    category: searchCategory,
                                    score: baseScore - 5,
                                    actionPayload: "!\(cleanTrigger) ",
                                    autocompletePayload: "!\(cleanTrigger) "
                                )
                            )
                        }
                    }
                }
            }
        }

        suggestions.sort { $0.score > $1.score }
        return suggestions
    }

    public func searchAllGlobalProvidersAsync(query: String) async -> [SearchItem] {
        if Task.isCancelled { return [] }
        let plugins = pluginHost.allNativePlugins()

        let allPluginItems: [(PluginItem, PluginManifest)] = await withTaskGroup(of: [(PluginItem, PluginManifest)].self) { group in
            for loaded in plugins {
                guard let provider = loaded.plugin as? (any TitikGlobalSearchProvider) else { continue }
                let manifest = loaded.manifest
                group.addTask {
                    if Task.isCancelled { return [] }
                    let items = await provider.provideGlobalSearchResults(query: query)
                    if Task.isCancelled { return [] }
                    return items.map { ($0, manifest) }
                }
            }
            var accumulated: [(PluginItem, PluginManifest)] = []
            for await results in group {
                if Task.isCancelled { return [] }
                accumulated.append(contentsOf: results)
            }
            return accumulated
        }

        if Task.isCancelled { return [] }
        return allPluginItems.flatMap { item, manifest in
            mapPluginItems([item], manifest: manifest)
        }
    }

    public func searchAllGlobalProviders(query: String) -> [SearchItem] {
        nonisolated(unsafe) var allPluginItems: [(PluginItem, PluginManifest)] = []
        let sema = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                await withTaskGroup(of: [(PluginItem, PluginManifest)].self) { group in
                    for loaded in self.pluginHost.allNativePlugins() {
                        guard let provider = loaded.plugin as? (any TitikGlobalSearchProvider) else { continue }
                        let manifest = loaded.manifest
                        group.addTask {
                            let items = await provider.provideGlobalSearchResults(query: query)
                            return items.map { ($0, manifest) }
                        }
                    }
                    for await results in group {
                        allPluginItems.append(contentsOf: results)
                    }
                }
                sema.signal()
            }
        }
        _ = sema.wait(timeout: .now() + .milliseconds(1500))

        return allPluginItems.flatMap { item, manifest in
            mapPluginItems([item], manifest: manifest)
        }
    }

    public func getDefaultItemsAsync() async -> [SearchItem] {
        if Task.isCancelled { return [] }
        let plugins = pluginHost.allNativePlugins()

        let allPluginItems: [(PluginItem, PluginManifest)] = await withTaskGroup(of: [(PluginItem, PluginManifest)].self) { group in
            for loaded in plugins {
                guard let provider = loaded.plugin as? (any TitikGlobalSearchProvider) else { continue }
                let manifest = loaded.manifest
                group.addTask {
                    if Task.isCancelled { return [] }
                    let items = await provider.provideDefaultItems()
                    if Task.isCancelled { return [] }
                    return items.map { ($0, manifest) }
                }
            }
            var accumulated: [(PluginItem, PluginManifest)] = []
            for await results in group {
                if Task.isCancelled { return [] }
                accumulated.append(contentsOf: results)
            }
            return accumulated
        }

        if Task.isCancelled { return [] }
        return allPluginItems.flatMap { item, manifest in
            mapPluginItems([item], manifest: manifest)
        }
    }

    public func getDefaultItems() -> [SearchItem] {
        nonisolated(unsafe) var allPluginItems: [(PluginItem, PluginManifest)] = []
        let sema = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                await withTaskGroup(of: [(PluginItem, PluginManifest)].self) { group in
                    for loaded in self.pluginHost.allNativePlugins() {
                        guard let provider = loaded.plugin as? (any TitikGlobalSearchProvider) else { continue }
                        let manifest = loaded.manifest
                        group.addTask {
                            let items = await provider.provideDefaultItems()
                            return items.map { ($0, manifest) }
                        }
                    }
                    for await results in group {
                        allPluginItems.append(contentsOf: results)
                    }
                }
                sema.signal()
            }
        }
        _ = sema.wait(timeout: .now() + .milliseconds(1500))

        return allPluginItems.flatMap { item, manifest in
            mapPluginItems([item], manifest: manifest)
        }
    }

    public func queryPluginAsync(manifest: PluginManifest, invocation: PluginInvocation) async -> [SearchItem] {
        if Task.isCancelled { return [] }
        let local = pluginHost.getNativePlugin(id: manifest.id)

        if let streaming = local as? (any TitikStreamingPlugin) {
            if let canvas = try? await streaming.onQuery(invocation: invocation) {
                if Task.isCancelled { return [] }
                if case .list(let listItems) = canvas {
                    return mapPluginItems(listItems, manifest: manifest)
                }
            }
            return []
        } else if let cmdPlugin = local as? (any TitikCommandPlugin) {
            let filterTerm = invocation.action ?? invocation.primaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let items: [PluginItem]
            if filterTerm.isEmpty {
                items = cmdPlugin.commands.map { cmd in
                    PluginItem(
                        id: cmd.id,
                        title: cmd.name,
                        subtitle: cmd.description,
                        category: "Plugin",
                        actionPayload: cmd.id,
                        scoreBoost: 500,
                        pluginId: manifest.id
                    )
                }
            } else {
                let matching = cmdPlugin.commands.filter {
                    $0.id.localizedCaseInsensitiveContains(filterTerm) ||
                    $0.name.localizedCaseInsensitiveContains(filterTerm) ||
                    $0.description.localizedCaseInsensitiveContains(filterTerm) ||
                    $0.triggers.contains(where: { $0.localizedCaseInsensitiveContains(filterTerm) })
                }
                let chosen = matching.isEmpty ? (cmdPlugin.commands.isEmpty ? [] : [cmdPlugin.commands[0]]) : matching
                items = chosen.map { cmd in
                    PluginItem(
                        id: cmd.id,
                        title: cmd.name,
                        subtitle: cmd.description,
                        category: "Plugin",
                        actionPayload: cmd.id,
                        scoreBoost: 500,
                        pluginId: manifest.id
                    )
                }
            }
            return mapPluginItems(items, manifest: manifest)
        } else {
            var items: [PluginItem] = []
            let (_, stream) = pluginHost.query(pluginId: manifest.id, query: invocation.primaryValue)
            for await response in stream {
                if Task.isCancelled { return [] }
                if case .listResult(_, let resItems) = response {
                    items = resItems
                }
            }
            return mapPluginItems(items, manifest: manifest)
        }
    }

    public func queryPluginAsync(manifest: PluginManifest, subquery: String) async -> [SearchItem] {
        let invocation = PluginInvocation(
            trigger: manifest.triggers.first ?? "",
            action: nil,
            primaryValue: subquery,
            flags: [:],
            rawInput: subquery
        )
        return await queryPluginAsync(manifest: manifest, invocation: invocation)
    }

    public func queryPluginSync(manifest: PluginManifest, invocation: PluginInvocation) -> [SearchItem] {
        let local = pluginHost.getNativePlugin(id: manifest.id)
        if let streaming = local as? (any TitikStreamingPlugin) {
            nonisolated(unsafe) var items: [PluginItem] = []
            let sema = DispatchSemaphore(value: 0)
            Task.detached(priority: .userInitiated) {
                if let canvas = try? await streaming.onQuery(invocation: invocation) {
                    if case .list(let listItems) = canvas {
                        items = listItems
                    }
                }
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + .seconds(3))
            return mapPluginItems(items, manifest: manifest)
        } else if let cmdPlugin = local as? (any TitikCommandPlugin) {
            let filterTerm = invocation.action ?? invocation.primaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let items: [PluginItem]
            if filterTerm.isEmpty {
                items = cmdPlugin.commands.map { cmd in
                    PluginItem(
                        id: cmd.id,
                        title: cmd.name,
                        subtitle: cmd.description,
                        category: "Plugin",
                        actionPayload: cmd.id,
                        scoreBoost: 500,
                        pluginId: manifest.id
                    )
                }
            } else {
                let matching = cmdPlugin.commands.filter {
                    $0.id.localizedCaseInsensitiveContains(filterTerm) ||
                    $0.name.localizedCaseInsensitiveContains(filterTerm) ||
                    $0.description.localizedCaseInsensitiveContains(filterTerm) ||
                    $0.triggers.contains(where: { $0.localizedCaseInsensitiveContains(filterTerm) })
                }
                let chosen = matching.isEmpty ? (cmdPlugin.commands.isEmpty ? [] : [cmdPlugin.commands[0]]) : matching
                items = chosen.map { cmd in
                    PluginItem(
                        id: cmd.id,
                        title: cmd.name,
                        subtitle: cmd.description,
                        category: "Plugin",
                        actionPayload: cmd.id,
                        scoreBoost: 500,
                        pluginId: manifest.id
                    )
                }
            }
            return mapPluginItems(items, manifest: manifest)
        } else {
            nonisolated(unsafe) var items: [PluginItem] = []
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    let (_, stream) = self.pluginHost.query(pluginId: manifest.id, query: invocation.primaryValue)
                    for await response in stream {
                        if case .listResult(_, let resItems) = response {
                            items = resItems
                        }
                    }
                    sema.signal()
                }
            }
            _ = sema.wait(timeout: .now() + .milliseconds(1500))
            return mapPluginItems(items, manifest: manifest)
        }
    }

    private func queryPluginSync(manifest: PluginManifest, subquery: String) -> [SearchItem] {
        let invocation = PluginInvocation(
            trigger: manifest.triggers.first ?? "",
            action: nil,
            primaryValue: subquery,
            flags: [:],
            rawInput: subquery
        )
        return queryPluginSync(manifest: manifest, invocation: invocation)
    }

    private func mapPluginItems(_ pluginItems: [PluginItem], manifest: PluginManifest) -> [SearchItem] {
        return pluginItems.map { pItem in
            let searchCategory = categoryForPluginItem(pItem, manifestId: manifest.id)
            let itemId = pItem.id.hasPrefix("\(manifest.id):") ? pItem.id : "\(manifest.id):\(pItem.id)"

            var previewURL: URL? = nil
            var previewType: PreviewType = .none
            var icon: NSImage? = nil
            let payload = pItem.actionPayload

            if searchCategory == .application {
                if payload.hasSuffix(".app") {
                    icon = AppLauncher.shared.icon(forPath: payload)
                }
            } else if searchCategory == .file || searchCategory == .directory {
                if !payload.isEmpty && (payload.hasPrefix("/") || payload.hasPrefix("~")) {
                    let expanded = PathResolver.expandPath(payload)
                    let url = URL(fileURLWithPath: expanded)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
                        previewURL = url
                        previewType = FileBrowser.shared.determinePreviewType(for: url, isDirectory: isDir.boolValue, countItems: false)
                        icon = AppLauncher.shared.icon(forPath: expanded)
                    }
                }
            }

            return SearchItem(
                id: itemId,
                title: pItem.title,
                subtitle: pItem.subtitle,
                category: searchCategory,
                score: pItem.scoreBoost,
                icon: icon,
                actionPayload: pItem.actionPayload,
                previewDetail: "\(pItem.title)\n\(pItem.subtitle)",
                previewType: previewType,
                previewURL: previewURL,
                action: { [weak self] in
                    if let dispatcher = SearchEngine.pluginCommandDispatcher,
                       dispatcher(manifest.id, pItem.actionPayload) {
                        return true
                    }

                    if let cmdPlugin = self?.pluginHost.getNativePlugin(id: manifest.id) as? (any TitikCommandPlugin) {
                        let sema = DispatchSemaphore(value: 0)
                        Task {
                            let ctx = CommandExecutionContext(trigger: "search", mode: .background, rawInput: pItem.actionPayload)
                            _ = try? await cmdPlugin.executeCommand(id: pItem.actionPayload, arguments: [:], context: ctx)
                            sema.signal()
                        }
                        _ = sema.wait(timeout: .now() + .seconds(2))
                        return true
                    }

                    if !pItem.actionPayload.isEmpty {
                        ClipboardManager.shared.copyToPasteboard(pItem.actionPayload)
                        return true
                    }
                    return false
                }
            )
        }
    }

    private func categoryForPlugin(id: String) -> SearchCategory {
        let lastPart = id.components(separatedBy: ".").last ?? id
        if let direct = SearchCategory(rawValue: lastPart) ?? SearchCategory.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(lastPart) == .orderedSame }) {
            return direct
        }
        let lower = lastPart.lowercased()
        if lower == "app" { return .application }
        if lower == "system" { return .systemCommand }
        if lower == "math" { return .calculator }
        return .plugin
    }

    private func scoreForPlugin(id: String) -> Int {
        let category = categoryForPlugin(id: id)
        return scoreForCategory(category)
    }

    private func scoreForCategory(_ category: SearchCategory) -> Int {
        switch category {
        case .emoji: return 100
        case .file: return 95
        case .application: return 90
        case .clipboard: return 85
        case .systemCommand: return 80
        case .calculator: return 75
        default: return 70
        }
    }

    private func categoryForPluginItem(_ pItem: PluginItem, manifestId: String) -> SearchCategory {
        if let direct = SearchCategory(rawValue: pItem.category) ?? SearchCategory.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(pItem.category) == .orderedSame }) {
            return direct
        }
        let lower = pItem.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "app" || lower == "application" { return .application }
        if lower == "system command" || lower == "command" || lower == "system" { return .systemCommand }
        if lower == "math" || lower == "calculator" { return .calculator }
        if lower == "directory" || lower == "folder" { return .directory }
        return categoryForPlugin(id: manifestId)
    }
}
