import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikPluginKit
import TitikUI

/// Recommendation model describing a suggested bang command for the shortcuts editor.
public struct BangRecommendation: Identifiable, Sendable, Hashable {
    public let id: String
    public let bang: String
    public let title: String
    public let description: String
    public let example: String
    public let iconName: String?

    public init(
        id: String,
        bang: String,
        title: String,
        description: String,
        example: String,
        iconName: String? = nil
    ) {
        self.id = id
        self.bang = bang
        self.title = title
        self.description = description
        self.example = example
        self.iconName = iconName
    }
}

/// Navigation page state for the shortcuts inspector/creator UI.
public enum ShortcutPage: Equatable, Sendable {
    case list
    case create
    case edit(ShortcutConfig)
}

/// Interactive focusable form fields in the shortcuts creator/editor.
public enum ShortcutFormField: Hashable, CaseIterable, Sendable {
    case command
    case name
    case keyString
    case recordButton
    case saveButton
    case cancelButton
}

/// View model driving the interactive shortcuts list, creation, editing, conflict validation, and key capture.
@MainActor
public final class ShortcutsPluginViewModel: ObservableObject {
    public static var searchBridge: (@MainActor (String) async -> [BangRecommendation])?

    @Published public var page: ShortcutPage = .list {
        didSet {
            updateKeymapScope()
            updateRecommendations(for: formCommand)
        }
    }
    public let keymapScope = PluginKeymapScope()
    public var onDismiss: (@MainActor () -> Void)?

    @Published public var formFocusedField: ShortcutFormField = .command
    @Published public var selectedRecommendationIndex: Int = 0
    @Published public var isListeningForKey: Bool = false
    @Published public var capturePrompt: String = "Press key combination on your keyboard. Press Esc to cancel."
    @Published public var formCommand: String = "" {
        didSet {
            updateRecommendations(for: formCommand)
        }
    }
    @Published public var formName: String = ""
    @Published public var formKeyString: String = ""
    @Published public var formCombination: KeyCombination?
    @Published public var filterQuery: String = "" {
        didSet {
            selectedRowIndex = 0
        }
    }
    @Published public var duplicateWarning: String?
    @Published public var selectedRowIndex: Int = 0
    @Published public var recommendations: [BangRecommendation] = []
    @Published public var activeRecommendations: [BangRecommendation] = [] {
        didSet {
            clampSelectedRecommendationIndex()
        }
    }
    private var lastSuggestedName: String?
    private var activeSearchTask: Task<Void, Never>?
    public let manager: ShortcutManager

    public init(manager: ShortcutManager = .shared) {
        self.manager = manager
        loadRecommendations()
        updateRecommendations(for: formCommand)
        updateKeymapScope()
    }

    /// Icon resolver for plugin identifiers.
    public static func iconForPlugin(id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("app") {
            return "app.badge"
        } else if lower.contains("cmd") || lower.contains("system") {
            return "gearshape.fill"
        } else if lower.contains("zen") {
            return "globe"
        } else if lower.contains("file") {
            return "folder.fill"
        } else if lower.contains("calc") {
            return "function"
        } else if lower.contains("clip") {
            return "clipboard.fill"
        } else if lower.contains("emoji") {
            return "face.smiling"
        } else if lower.contains("notes") || lower.contains("note") {
            return "note.text"
        } else if lower.contains("shortcut") || lower.contains("key") {
            return "command"
        } else if lower.contains("launcher") {
            return "rocket.fill"
        } else {
            return "puzzlepiece.extension.fill"
        }
    }

    private static let defaultBangRecommendations: [BangRecommendation] = [
        BangRecommendation(
            id: "app",
            bang: "!app",
            title: "App Launcher",
            description: "Launch installed applications",
            example: "!app",
            iconName: "app.badge"
        ),
        BangRecommendation(
            id: "zen",
            bang: "!zen",
            title: "Zen Browser",
            description: "Open URL or search tabs",
            example: "!zen https://github.com",
            iconName: "globe"
        ),
        BangRecommendation(
            id: "cmd-lock",
            bang: "!cmd lock",
            title: "Lock Screen",
            description: "Lock macOS screen immediately",
            example: "!cmd lock",
            iconName: "gearshape.fill"
        ),
        BangRecommendation(
            id: "cmd-sleep",
            bang: "!cmd sleep",
            title: "Sleep Mac",
            description: "Put macOS to sleep",
            example: "!cmd sleep",
            iconName: "gearshape.fill"
        ),
        BangRecommendation(
            id: "file",
            bang: "!file",
            title: "File Browser",
            description: "Browse filesystem or search files",
            example: "!file ~",
            iconName: "folder.fill"
        ),
        BangRecommendation(
            id: "emoji",
            bang: "!emoji",
            title: "Emoji Picker",
            description: "Search and paste emojis",
            example: "!emoji",
            iconName: "face.smiling"
        ),
        BangRecommendation(
            id: "clip",
            bang: "!clip",
            title: "Clipboard",
            description: "Search clipboard history",
            example: "!clip",
            iconName: "clipboard.fill"
        ),
        BangRecommendation(
            id: "calc",
            bang: "!calc",
            title: "Calculator",
            description: "Evaluate math expressions",
            example: "!calc 42 * 1024",
            iconName: "function"
        ),
        BangRecommendation(
            id: "notes",
            bang: "!notes",
            title: "Notes",
            description: "Create and manage quick notes",
            example: "!notes",
            iconName: "note.text"
        ),
        BangRecommendation(
            id: "shortcut",
            bang: "!shortcut",
            title: "Shortcuts Inspector",
            description: "Manage global shortcuts",
            example: "!shortcut",
            iconName: "command"
        ),
        BangRecommendation(
            id: "plugin",
            bang: "!plugin",
            title: "Plugin Manager",
            description: "List and manage plugins",
            example: "!plugin",
            iconName: "puzzlepiece.extension.fill"
        )
    ]

    /// Loads built-in and dynamically registered native plugin bang recommendations.
    public func loadRecommendations() {
        if PluginHost.shared.allNativePlugins().isEmpty {
            for entry in BuiltinPluginRegistry.all {
                let plugin = entry.factory(PluginContext(pluginId: entry.id))
                PluginHost.shared.registerNativePlugin(plugin, manifest: entry.manifest)
            }
        }

        var recs = Self.defaultBangRecommendations
        appendLoadedPluginRecommendations(to: &recs)
        self.recommendations = recs
    }

    private func appendLoadedPluginRecommendations(to recs: inout [BangRecommendation]) {
        let loadedPlugins = PluginHost.shared.allNativePlugins()
        for native in loadedPlugins {
            let pluginIcon = Self.iconForPlugin(id: native.manifest.id)
            if let commandPlugin = native.plugin as? (any TitikCommandPlugin) {
                let mainTrigger = native.manifest.triggers.first ?? ""
                for cmd in commandPlugin.commands {
                    let exampleStr: String
                    if !mainTrigger.isEmpty {
                        exampleStr = cmd.id == mainTrigger ? "!\(mainTrigger)" : "!\(mainTrigger) \(cmd.id)"
                    } else {
                        exampleStr = "!\(cmd.id)"
                    }
                    let recId = "\(native.manifest.id):\(cmd.id)"
                    if !recs.contains(where: { $0.id == recId || $0.example == exampleStr }) {
                        recs.append(
                            BangRecommendation(
                                id: recId,
                                bang: exampleStr,
                                title: cmd.name,
                                description: cmd.description,
                                example: exampleStr,
                                iconName: pluginIcon
                            )
                        )
                    }
                }
            }

            for bang in native.manifest.normalizedBangs {
                let clean = bang.lowercased()
                if !recs.contains(where: { $0.id == clean || $0.bang == "!" + clean || $0.example == "!" + clean }) {
                    recs.append(
                        BangRecommendation(
                            id: "\(native.manifest.id):\(clean)",
                            bang: "!\(clean)",
                            title: native.manifest.name,
                            description: native.manifest.description,
                            example: "!\(clean)",
                            iconName: pluginIcon
                        )
                    )
                }
            }
        }
    }

    private struct PluginMatch {
        let manifest: PluginManifest
        let plugin: any TitikPlugin
        let bang: String
        let subquery: String
    }

    private func findPluginAndBang(
        for query: String
    ) -> PluginMatch? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatted = trimmed.hasPrefix("!") ? trimmed : "!" + trimmed
        let lower = formatted.lowercased()

        for native in PluginHost.shared.allNativePlugins() {
            for bang in native.manifest.normalizedBangs {
                let exactBang = "!" + bang.lowercased()
                let bangPrefix = exactBang + " "
                if lower == exactBang {
                    return PluginMatch(manifest: native.manifest, plugin: native.plugin, bang: bang, subquery: "")
                } else if lower.hasPrefix(bangPrefix) {
                    let subquery = String(formatted.dropFirst(bangPrefix.count)).trimmingCharacters(in: .whitespaces)
                    return PluginMatch(manifest: native.manifest, plugin: native.plugin, bang: bang, subquery: subquery)
                }
            }
        }
        return nil
    }

    private func clampSelectedRecommendationIndex() {
        if !activeRecommendations.isEmpty {
            selectedRecommendationIndex = min(max(0, selectedRecommendationIndex), activeRecommendations.count - 1)
        } else {
            selectedRecommendationIndex = 0
        }
    }

    /// Updates active recommendations based on the command input string.
    public func updateRecommendations(for input: String) {
        activeSearchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed == "!" {
            if let bridge = Self.searchBridge {
                activeSearchTask = Task { @MainActor [weak self] in
                    let bridgeRecs = await bridge(input)
                    guard !Task.isCancelled, let self = self, self.formCommand == input else { return }
                    var combined = self.recommendations
                    for rec in bridgeRecs where !combined.contains(where: {
                        $0.example == rec.example || $0.id == rec.id
                    }) {
                        combined.append(rec)
                    }
                    self.activeRecommendations = combined
                    self.clampSelectedRecommendationIndex()
                }
            } else {
                self.activeRecommendations = recommendations
                self.clampSelectedRecommendationIndex()
            }
            return
        }

        activeSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self = self, self.formCommand == input else { return }

            var resolved: [BangRecommendation] = []
            if let target = self.findPluginAndBang(for: trimmed) {
                resolved = await self.resolvePluginInternalRecommendations(
                    manifest: target.manifest,
                    plugin: target.plugin,
                    bang: target.bang,
                    subquery: target.subquery
                )
            } else if trimmed.hasPrefix("!") {
                let cleanQuery = String(trimmed.dropFirst()).lowercased()
                resolved = self.recommendations.filter { rec in
                    rec.bang.lowercased().hasPrefix(trimmed.lowercased()) ||
                    rec.example.lowercased().hasPrefix(trimmed.lowercased()) ||
                    rec.title.localizedCaseInsensitiveContains(cleanQuery) ||
                    rec.description.localizedCaseInsensitiveContains(cleanQuery) ||
                    (FuzzyMatcher.match(query: cleanQuery, target: rec.title) != nil) ||
                    (FuzzyMatcher.match(query: trimmed, target: rec.bang) != nil)
                }
            } else {
                resolved = await self.resolveGlobalPluginRecommendations(query: trimmed)
            }

            var combined: [BangRecommendation] = []
            for rec in resolved where !combined.contains(where: {
                $0.example == rec.example || $0.id == rec.id
            }) {
                combined.append(rec)
            }

            if let bridge = Self.searchBridge {
                let bridgeRecs = await bridge(input)
                guard !Task.isCancelled, self.formCommand == input else { return }
                for rec in bridgeRecs where !combined.contains(where: {
                    $0.example == rec.example || $0.id == rec.id
                }) {
                    combined.append(rec)
                }
            }

            guard !Task.isCancelled, self.formCommand == input else { return }
            self.activeRecommendations = combined
            self.clampSelectedRecommendationIndex()
        }
    }

    private func resolvePluginInternalRecommendations(
        manifest: PluginManifest,
        plugin: any TitikPlugin,
        bang: String,
        subquery: String
    ) async -> [BangRecommendation] {
        if let streaming = plugin as? (any TitikStreamingPlugin) {
            do {
                let canvas = try await streaming.onQuery(subquery)
                if case .list(let items) = canvas {
                    return items.map { item in
                        formatPluginItem(item, manifest: manifest, bang: bang, subquery: subquery)
                    }
                }
            } catch {}
        }

        if let cmdPlugin = plugin as? (any TitikCommandPlugin) {
            let matching: [PluginCommandDefinition]
            if subquery.isEmpty {
                matching = cmdPlugin.commands
            } else {
                matching = cmdPlugin.commands.filter { cmd in
                    cmd.id.localizedCaseInsensitiveContains(subquery) ||
                    cmd.name.localizedCaseInsensitiveContains(subquery) ||
                    cmd.description.localizedCaseInsensitiveContains(subquery) ||
                    cmd.triggers.contains { $0.localizedCaseInsensitiveContains(subquery) }
                }
            }
            return matching.map { cmd in
                let cmdExample = cmd.id == bang ? "!\(bang)" : "!\(bang) \(cmd.id)"
                return BangRecommendation(
                    id: "\(manifest.id):\(cmd.id)",
                    bang: "!\(bang)",
                    title: cmd.name,
                    description: cmd.description,
                    example: cmdExample,
                    iconName: Self.iconForPlugin(id: manifest.id)
                )
            }
        }

        return []
    }

    private func formatPluginItem(
        _ item: PluginItem,
        manifest: PluginManifest,
        bang: String,
        subquery: String
    ) -> BangRecommendation {
        let exampleCmd: String
        let recId: String
        if manifest.id == "titik.builtin.app" {
            exampleCmd = "!app \(item.title)"
            recId = "app:\(item.title.lowercased())"
        } else if item.actionPayload.hasPrefix("!") {
            exampleCmd = item.actionPayload.trimmingCharacters(in: .whitespaces)
            recId = "\(manifest.id):\(item.id)"
        } else if item.actionPayload.isEmpty || item.actionPayload == item.title {
            exampleCmd = subquery.isEmpty ? "!\(bang)" : "!\(bang) \(item.title)"
            recId = "\(manifest.id):\(item.id)"
        } else {
            exampleCmd = "!\(bang) \(item.actionPayload)"
            recId = "\(manifest.id):\(item.id)"
        }
        return BangRecommendation(
            id: recId,
            bang: "!\(bang)",
            title: item.title,
            description: item.subtitle.isEmpty ? manifest.description : item.subtitle,
            example: exampleCmd,
            iconName: Self.iconForCategory(item.category) ?? Self.iconForPlugin(id: manifest.id)
        )
    }

    private func resolveGlobalPluginRecommendations(query: String) async -> [BangRecommendation] {
        var recs: [BangRecommendation] = []
        for native in PluginHost.shared.allNativePlugins() {
            guard let provider = native.plugin as? (any TitikGlobalSearchProvider) else { continue }
            let items = await provider.provideGlobalSearchResults(query: query)
            let primaryBang = native.manifest.triggers.first ?? native.manifest.normalizedBangs.first ?? ""
            for item in items.prefix(10) {
                let exampleCmd = formatGlobalCommand(item: item, primaryBang: primaryBang)
                let recId = "\(native.manifest.id):\(item.id)"
                if !recs.contains(where: { $0.id == recId || $0.example == exampleCmd }) {
                    recs.append(
                        BangRecommendation(
                            id: recId,
                            bang: primaryBang.isEmpty ? "" : "!\(primaryBang)",
                            title: item.title,
                            description: item.subtitle.isEmpty ? native.manifest.description : item.subtitle,
                            example: exampleCmd,
                            iconName: Self.iconForCategory(item.category) ?? Self.iconForPlugin(id: native.manifest.id)
                        )
                    )
                }
            }
        }
        return recs
    }

    private func formatGlobalCommand(item: PluginItem, primaryBang: String) -> String {
        if item.actionPayload.hasPrefix("!") {
            return item.actionPayload.trimmingCharacters(in: .whitespaces)
        } else if item.actionPayload.isEmpty || item.actionPayload == item.title {
            return primaryBang.isEmpty ? item.title : "!\(primaryBang) \(item.title)"
        } else {
            return primaryBang.isEmpty ? item.actionPayload : "!\(primaryBang) \(item.actionPayload)"
        }
    }

    public static func iconForCategory(_ category: String) -> String? {
        let lower = category.lowercased()
        if lower.contains("app") {
            return "app.badge"
        } else if lower.contains("command") || lower.contains("system") {
            return "gearshape.fill"
        } else if lower.contains("browser") || lower.contains("web") || lower.contains("zen") {
            return "globe"
        } else if lower.contains("folder") || lower.contains("file") || lower.contains("directory") {
            return "folder.fill"
        } else if lower.contains("clipboard") {
            return "doc.on.clipboard.fill"
        } else if lower.contains("calc") || lower.contains("math") {
            return "function"
        } else if lower.contains("emoji") {
            return "face.smiling"
        } else if lower.contains("note") {
            return "note.text"
        }
        return nil
    }

    /// Applies a recommendation to the shortcut form.
    public func applyRecommendation(_ rec: BangRecommendation) {
        self.formCommand = rec.example
        let trimmedName = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName == lastSuggestedName {
            self.formName = rec.title
            self.lastSuggestedName = rec.title
        }
    }

    /// Dynamically filters recommendations matching user input in formCommand.
    public func dynamicRecommendations() -> [BangRecommendation] {
        return activeRecommendations
    }

    /// Returns shortcuts matching the current filter query.
    public func filteredShortcuts() -> [ShortcutConfig] {
        let all = manager.shortcuts
        let cleanQuery = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanQuery.isEmpty {
            return all
        }
        return all.filter { sc in
            sc.action.target.localizedCaseInsensitiveContains(cleanQuery) ||
            sc.keyCombinationString.localizedCaseInsensitiveContains(cleanQuery) ||
            (sc.name?.localizedCaseInsensitiveContains(cleanQuery) ?? false) ||
            sc.key.localizedCaseInsensitiveContains(cleanQuery)
        }
    }

    /// Prepares state to create a new shortcut.
    public func startCreate() {
        stopListening()
        self.page = .create
        self.formCommand = ""
        self.formName = ""
        self.formKeyString = ""
        self.formCombination = nil
        self.duplicateWarning = nil
        self.lastSuggestedName = nil
        self.formFocusedField = .command
        self.selectedRecommendationIndex = 0
    }

    /// Prepares state to edit an existing shortcut.
    public func startEdit(shortcut: ShortcutConfig) {
        stopListening()
        self.page = .edit(shortcut)
        self.formCommand = shortcut.action.target
        self.formName = shortcut.name ?? ""
        self.formKeyString = shortcut.keyCombinationString
        self.formCombination = manager.parseCombination(from: shortcut)
        self.duplicateWarning = nil
        self.lastSuggestedName = nil
        self.formFocusedField = .command
        self.selectedRecommendationIndex = 0
    }

    /// Cancels form creation/edit and returns to list page.
    public func cancelForm() {
        stopListening()
        self.duplicateWarning = nil
        self.page = .list
    }

    // MARK: - Form Keyboard Navigation & Focus Traversal

    /// Advances keyboard focus to the next form field or button in cyclic order.
    public func nextFormField() {
        let all = ShortcutFormField.allCases
        guard let idx = all.firstIndex(of: formFocusedField) else {
            formFocusedField = .command
            return
        }
        let nextIdx = (idx + 1) % all.count
        formFocusedField = all[nextIdx]
    }

    /// Moves keyboard focus to the previous form field or button in reverse cyclic order.
    public func previousFormField() {
        let all = ShortcutFormField.allCases
        guard let idx = all.firstIndex(of: formFocusedField) else {
            formFocusedField = .command
            return
        }
        let prevIdx = (idx - 1 + all.count) % all.count
        formFocusedField = all[prevIdx]
    }

    /// Selects the next item in the dynamic recommendations list with boundary clamping.
    public func selectNextRecommendation() {
        guard !activeRecommendations.isEmpty else {
            selectedRecommendationIndex = 0
            return
        }
        if selectedRecommendationIndex < activeRecommendations.count - 1 {
            selectedRecommendationIndex += 1
        }
    }

    /// Selects the previous item in the dynamic recommendations list with boundary clamping.
    public func selectPreviousRecommendation() {
        guard !activeRecommendations.isEmpty else {
            selectedRecommendationIndex = 0
            return
        }
        if selectedRecommendationIndex > 0 {
            selectedRecommendationIndex -= 1
        }
    }

    /// Injects the currently highlighted recommendation into the command and name fields.
    public func injectSelectedRecommendation() {
        guard !activeRecommendations.isEmpty,
              selectedRecommendationIndex >= 0,
              selectedRecommendationIndex < activeRecommendations.count else {
            return
        }
        applyRecommendation(activeRecommendations[selectedRecommendationIndex])
    }

    /// Contextual Enter key action handler depending on the currently focused field.
    public func handleFormEnter() {
        switch formFocusedField {
        case .command:
            if !activeRecommendations.isEmpty,
               selectedRecommendationIndex >= 0,
               selectedRecommendationIndex < activeRecommendations.count {
                injectSelectedRecommendation()
            } else {
                saveCurrentForm()
            }
        case .name, .keyString, .saveButton:
            saveCurrentForm()
        case .recordButton:
            if isListeningForKey {
                stopListening()
            } else {
                startListening()
            }
        case .cancelButton:
            cancelForm()
        }
    }

    /// Updates manual key string input and synchronizes parsed combination and conflict warning.
    public func updateFormKeyString(_ newString: String) {
        self.formKeyString = newString
        if let combo = KeyCombination(string: newString) {
            self.formCombination = combo
            validateCombination(combo)
        } else {
            self.formCombination = nil
            self.duplicateWarning = nil
        }
    }

    /// Validates whether a combination is available or conflicting.
    public func validateCombination(_ combo: KeyCombination) {
        let ignoringId: String?
        if case .edit(let sc) = page {
            ignoringId = sc.id
        } else {
            ignoringId = nil
        }
        let dup = manager.isDuplicate(combination: combo, ignoringId: ignoringId)
        if dup.isDuplicate {
            self.duplicateWarning = "Already assigned to '\(dup.existingCommand ?? "another command")'"
        } else {
            self.duplicateWarning = nil
        }
    }

    /// Starts interactive key recording mode via standard PluginKeymapScope API.
    public func startListening() {
        self.isListeningForKey = true
        self.capturePrompt = "Press key combination on your keyboard. Press Esc to cancel."
        keymapScope.startCapture(
            onCaptured: { [weak self] combo in
                guard let self = self else { return }
                self.formCombination = combo
                self.formKeyString = combo.description
                self.isListeningForKey = false
                self.validateCombination(combo)
            },
            onModifierOnly: { [weak self] _ in
                guard let self = self else { return }
                self.capturePrompt = "Hold modifier(s) and press a key (e.g. ⌘ + Letter)"
            },
            onCancelled: { [weak self] in
                guard let self = self else { return }
                self.isListeningForKey = false
                self.capturePrompt = "Press key combination on your keyboard. Press Esc to cancel."
            }
        )
    }

    /// Stops interactive key recording mode.
    public func stopListening() {
        self.isListeningForKey = false
        self.capturePrompt = "Press key combination on your keyboard. Press Esc to cancel."
        keymapScope.stopCapture()
    }

    /// Records a key combination captured directly.
    public func recordCombination(modifiers: KeyModifier, key: Keycode) {
        let combo = KeyCombination(modifiers: modifiers, key: key)
        self.formCombination = combo
        self.formKeyString = combo.description
        self.isListeningForKey = false
        validateCombination(combo)
    }

    /// Validates and saves the current shortcut form to ShortcutManager.
    public func saveCurrentForm() {
        stopListening()
        let trimmedCommand = formCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            duplicateWarning = "Command cannot be empty"
            return
        }

        let combo = formCombination ?? KeyCombination(string: formKeyString)
        guard let validCombo = combo else {
            duplicateWarning = "Invalid key combination"
            return
        }

        validateCombination(validCombo)
        if duplicateWarning != nil {
            return
        }

        let (parsedKey, parsedMods) = ShortcutConfig.parseKeyCombinationString(formKeyString)
        let keyStr = parsedKey.isEmpty ? validCombo.key.displayGlyph.lowercased() : parsedKey
        let modsList = parsedMods.isEmpty ? validCombo.modifiers.displayGlyphs.map { String($0) } : parsedMods
        let trimmedName = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        let optName = trimmedName.isEmpty ? nil : trimmedName

        commitShortcut(name: optName, key: keyStr, modifiers: modsList, command: trimmedCommand)
    }

    private func commitShortcut(name: String?, key: String, modifiers: [String], command: String) {
        switch page {
        case .create:
            let config = ShortcutConfig(
                name: name,
                key: key,
                modifiers: modifiers,
                action: ShortcutActionConfig(type: .rawQuery, target: command)
            )
            do {
                try manager.addShortcut(config)
                ToastManager.shared.show(message: "Shortcut added", icon: "checkmark.circle.fill", type: .success)
                self.page = .list
            } catch {
                duplicateWarning = error.localizedDescription
            }

        case .edit(let existing):
            var updated = existing
            updated.name = name
            updated.key = key
            updated.modifiers = modifiers
            updated.action.target = command
            do {
                try manager.updateShortcut(id: existing.id, updated: updated)
                ToastManager.shared.show(message: "Shortcut updated", icon: "checkmark.circle.fill", type: .success)
                self.page = .list
            } catch {
                duplicateWarning = error.localizedDescription
            }

        case .list:
            break
        }
    }

    /// Deletes a shortcut by ID via ShortcutManager.
    public func deleteShortcut(id: String) {
        manager.deleteShortcut(id: id)
        let count = filteredShortcuts().count
        if count == 0 {
            selectedRowIndex = 0
        } else if selectedRowIndex >= count {
            selectedRowIndex = count - 1
        }
        ToastManager.shared.show(message: "Shortcut deleted", icon: "trash", type: .info)
    }

    /// Reloads shortcuts from disk configuration.
    public func reload() {
        manager.reloadFromConfig()
        loadRecommendations()
        let count = filteredShortcuts().count
        if selectedRowIndex >= count {
            selectedRowIndex = max(0, count - 1)
        }
        ToastManager.shared.show(message: "Shortcuts reloaded", icon: "arrow.clockwise", type: .info)
    }

    public var footerKeycaps: [KeycapAction] {
        switch page {
        case .list:
            return [
                KeycapAction(shortcut: "↑↓", label: "Navigate"),
                KeycapAction(shortcut: "↵", label: "Trigger"),
                KeycapAction(shortcut: "⌘N", label: "New"),
                KeycapAction(shortcut: "⌘E", label: "Edit"),
                KeycapAction(shortcut: "⌘⌫", label: "Delete"),
                KeycapAction(shortcut: "⌘R", label: "Reload"),
                KeycapAction(shortcut: "esc", label: "Close")
            ]
        case .create, .edit:
            var actions: [KeycapAction] = [
                KeycapAction(shortcut: "⇥", label: "Next Field"),
                KeycapAction(shortcut: "⇧⇥", label: "Prev Field")
            ]
            if formFocusedField == .command {
                if !activeRecommendations.isEmpty {
                    actions.append(KeycapAction(shortcut: "↑↓", label: "Navigate"))
                    actions.append(KeycapAction(shortcut: "↵", label: "Select"))
                } else {
                    actions.append(KeycapAction(shortcut: "↵", label: "Save"))
                }
            } else {
                switch formFocusedField {
                case .recordButton:
                    actions.append(KeycapAction(shortcut: "↵", label: isListeningForKey ? "Stop" : "Record"))
                case .cancelButton:
                    actions.append(KeycapAction(shortcut: "↵", label: "Cancel"))
                default:
                    actions.append(KeycapAction(shortcut: "↵", label: "Save"))
                }
            }
            actions.append(KeycapAction(shortcut: "esc", label: "Cancel"))
            return actions
        }
    }

    /// Triggers the selected shortcut.
    public func triggerShortcut(_ shortcut: ShortcutConfig) {
        if !HotkeyManager.shared.trigger(identifier: shortcut.id) {
            manager.dispatcher?(shortcut.action.target)
        }
        ToastManager.shared.show(message: "Triggered \(shortcut.action.target)", icon: "play.fill", type: .success)
    }

    // MARK: - Keymap Scope Handling

    public func updateKeymapScope() {
        keymapScope.removeAll()
        switch page {
        case .list:
            setupListKeymapScope()
        case .create, .edit:
            registerFormKeymaps()
        }
    }

    private func setupListKeymapScope() {
        keymapScope.register("↑", label: "Navigate") { [weak self] in
            guard let self = self else { return }
            if self.selectedRowIndex > 0 {
                self.selectedRowIndex -= 1
            }
        }
        keymapScope.register("↓", label: "Navigate") { [weak self] in
            guard let self = self else { return }
            let list = self.filteredShortcuts()
            if self.selectedRowIndex < list.count - 1 {
                self.selectedRowIndex += 1
            }
        }
        keymapScope.register("↵", label: "Trigger") { [weak self] in
            guard let self = self else { return }
            let list = self.filteredShortcuts()
            if self.selectedRowIndex >= 0 && self.selectedRowIndex < list.count {
                self.triggerShortcut(list[self.selectedRowIndex])
            }
        }
        keymapScope.register("⌘N", label: "New") { [weak self] in self?.startCreate() }
        keymapScope.register("cmd+n", label: "New") { [weak self] in self?.startCreate() }
        keymapScope.register("⌘E", label: "Edit") { [weak self] in
            guard let self = self else { return }
            let list = self.filteredShortcuts()
            if self.selectedRowIndex >= 0 && self.selectedRowIndex < list.count {
                self.startEdit(shortcut: list[self.selectedRowIndex])
            }
        }
        keymapScope.register("⌘⌫", label: "Delete") { [weak self] in
            guard let self = self else { return }
            let list = self.filteredShortcuts()
            if self.selectedRowIndex >= 0 && self.selectedRowIndex < list.count {
                self.deleteShortcut(id: list[self.selectedRowIndex].id)
            }
        }
        keymapScope.register("⌘R", label: "Reload") { [weak self] in
            self?.reload()
        }
        keymapScope.register("esc", label: "Close") { [weak self] in
            self?.onDismiss?()
        }
    }

    private func registerFormKeymaps() {
        keymapScope.register("tab", label: "Next Field") { [weak self] in
            self?.nextFormField()
        }
        keymapScope.register("shift+tab", label: "Previous Field") { [weak self] in
            self?.previousFormField()
        }
        keymapScope.register("↑", label: "Previous Recommendation") { [weak self] in
            guard let self = self else { return }
            if self.formFocusedField == .command {
                self.selectPreviousRecommendation()
            }
        }
        keymapScope.register("↓", label: "Next Recommendation") { [weak self] in
            guard let self = self else { return }
            if self.formFocusedField == .command {
                self.selectNextRecommendation()
            }
        }
        keymapScope.register("↵", label: "Select / Save") { [weak self] in
            self?.handleFormEnter()
        }
        keymapScope.register("esc", label: "Cancel") { [weak self] in
            self?.cancelForm()
        }
    }

    /// Submits the current view action (triggers selected row in list, or saves form).
    public func submitQuery() {
        switch page {
        case .list:
            let list = filteredShortcuts()
            if selectedRowIndex >= 0 && selectedRowIndex < list.count {
                triggerShortcut(list[selectedRowIndex])
            }
        case .create, .edit:
            handleFormEnter()
        }
    }
}

/// Main root view container for ShortcutsPlugin.
public struct ShortcutsPluginView: View {
    @ObservedObject public var viewModel: ShortcutsPluginViewModel
    @ObservedObject private var shortcutManager = ShortcutManager.shared

    public init(viewModel: ShortcutsPluginViewModel) {
        self.viewModel = viewModel
        self._shortcutManager = ObservedObject(wrappedValue: viewModel.manager)
    }

    public var body: some View {
        ZStack {
            switch viewModel.page {
            case .list:
                ShortcutsMainListView(viewModel: viewModel)
                    .transition(.opacity)
            case .create, .edit:
                ShortcutFormView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: viewModel.page)
    }
}

/// Main list view rendering all registered shortcuts, filtering, and add button.
public struct ShortcutsMainListView: View {
    @ObservedObject public var viewModel: ShortcutsPluginViewModel
    @ObservedObject private var shortcutManager = ShortcutManager.shared

    public init(viewModel: ShortcutsPluginViewModel) {
        self.viewModel = viewModel
        self._shortcutManager = ObservedObject(wrappedValue: viewModel.manager)
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header bar
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)

                Text("Shortcuts")
                    .font(Theme.fontPreviewTitle)
                    .foregroundColor(Theme.textPrimary)

                let count = viewModel.filteredShortcuts().count
                Text("\(count)")
                    .font(Theme.fontBadge)
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.18))
                    .clipShape(Capsule())

                Spacer()

                // Reload button
                Button {
                    viewModel.reload()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Reload")
                            .font(Theme.fontFooterLabel)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(Theme.textSecondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Reload shortcuts from disk (⌘R)")

                // Add Shortcut button
                Button {
                    viewModel.startCreate()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add Shortcut")
                            .font(Theme.fontFooterLabel)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.2))
                    .foregroundColor(Theme.accent)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 4)

            // Search/Filter Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)

                TextField("Filter shortcuts...", text: $viewModel.filterQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.fontRowTitle)
                    .foregroundColor(Theme.textPrimary)

                if !viewModel.filterQuery.isEmpty {
                    Button {
                        viewModel.filterQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )

            // Shortcut list / Empty state
            let items = viewModel.filteredShortcuts()
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "keyboard")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textMuted.opacity(0.5))

                    Text(
                        viewModel.filterQuery.isEmpty
                            ? "No shortcuts configured"
                            : "No shortcuts matching \"\(viewModel.filterQuery)\""
                    )
                        .font(Theme.fontPreviewTitle)
                        .foregroundColor(Theme.textSecondary)

                    if viewModel.filterQuery.isEmpty {
                        Text("Assign global hotkeys to execute quick actions and bang commands instantly.")
                            .font(Theme.fontPreviewBody)
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)

                        Button {
                            viewModel.startCreate()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Create Shortcut")
                            }
                            .font(Theme.fontFooterLabel)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.accent)
                            .foregroundColor(Color.black)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, shortcut in
                            let isSelected = viewModel.selectedRowIndex == index
                            ShortcutRowView(
                                shortcut: shortcut,
                                isSelected: isSelected,
                                onSelect: {
                                    viewModel.selectedRowIndex = index
                                },
                                onEdit: {
                                    viewModel.selectedRowIndex = index
                                    viewModel.startEdit(shortcut: shortcut)
                                },
                                onDelete: {
                                    viewModel.deleteShortcut(id: shortcut.id)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Row view displaying individual shortcut details and edit/delete actions.
private struct ShortcutRowView: View {
    let shortcut: ShortcutConfig
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Target command & Name
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(shortcut.action.target)
                        .font(Theme.fontCode)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.textPrimary)

                    if let name = shortcut.name, !name.isEmpty {
                        Text("• \(name)")
                            .font(Theme.fontRowSubtitle)
                            .foregroundColor(Theme.textMuted)
                    }
                }

                Text("Plugin Command Query")
                    .font(Theme.fontRowSubtitle)
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            // Key combination badge
            KeycapBadgeView(shortcut: shortcut)

            // Action buttons
            HStack(spacing: 4) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Edit Shortcut")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.categoryCustom)
                        .frame(width: 26, height: 26)
                        .background(Theme.categoryCustom.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Delete Shortcut")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Theme.selectionBg
                : (isHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Theme.accent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { isHovered = $0 }
    }
}

/// Visual badge rendering formatted keycaps for a ShortcutConfig.
public struct KeycapBadgeView: View {
    let shortcut: ShortcutConfig

    public init(shortcut: ShortcutConfig) {
        self.shortcut = shortcut
    }

    public var body: some View {
        let combo = KeyCombination(string: shortcut.keyCombinationString)
        let displayString = combo?.description ?? shortcut.keyCombinationString

        HStack(spacing: 3) {
            Text(displayString)
                .font(Theme.fontKeycap)
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
        )
    }
}

/// Interactive row item for a command recommendation inside ShortcutFormView.
public struct ShortcutSuggestionRow: View {
    public let rec: BangRecommendation
    public let isSelected: Bool
    public let onSelect: () -> Void
    @State private var isHovered: Bool = false

    public init(rec: BangRecommendation, isSelected: Bool = false, onSelect: @escaping () -> Void) {
        self.rec = rec
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Leading icon in accent tinted rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.accent.opacity(0.35) : Theme.accent.opacity(0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: rec.iconName ?? "terminal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.accent)
                }

                // Title and description/path
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.95))
                        .lineLimit(1)
                    Text(rec.description)
                        .font(Theme.fontFooterLabel)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Trailing monospace command badge
                Text(rec.example)
                    .font(Theme.fontCode)
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Theme.selectionBg : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.7) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Form view for creating and editing shortcuts with recommendations and key listening.
public struct ShortcutFormView: View {
    @ObservedObject public var viewModel: ShortcutsPluginViewModel
    @FocusState private var focusedField: ShortcutFormField?

    public init(viewModel: ShortcutsPluginViewModel) {
        self.viewModel = viewModel
    }

    private var isEditing: Bool {
        if case .edit = viewModel.page { return true }
        return false
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Bar
            HStack(spacing: 10) {
                Button {
                    viewModel.cancelForm()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(Theme.fontFooterLabel)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(Theme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Text(isEditing ? "Edit Shortcut" : "New Shortcut")
                    .font(Theme.fontPreviewTitle)
                    .foregroundColor(Theme.textPrimary)

                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Command Section with Dynamic Recommendations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMAND TO EXECUTE")
                            .font(Theme.fontBadge)
                            .foregroundColor(Theme.textMuted)

                        HStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12))
                                .foregroundColor(focusedField == .command ? Theme.accent : Theme.accent.opacity(0.8))

                            TextField(
                                "!<bang> <command> (e.g. !app, !zen https://github.com, !cmd lock)",
                                text: $viewModel.formCommand
                            )
                            .focused($focusedField, equals: .command)
                            .textFieldStyle(.plain)
                            .font(Theme.fontCode)
                            .foregroundColor(Theme.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(focusedField == .command ? Theme.accent : Color.white.opacity(0.15), lineWidth: focusedField == .command ? 1.5 : 1)
                        )

                        // Dynamic vertical suggestions dropdown card
                        if !viewModel.activeRecommendations.isEmpty {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("SUGGESTIONS (\(viewModel.activeRecommendations.count))")
                                        .font(Theme.fontBadge)
                                        .foregroundColor(Theme.textMuted)
                                    Spacer()
                                    Text("↑↓ Navigate • ↵ Insert")
                                        .font(Theme.fontFooterLabel)
                                        .foregroundColor(Theme.textMuted)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.03))

                                Divider()
                                    .background(Color.white.opacity(0.08))

                                ScrollViewReader { proxy in
                                    ScrollView(.vertical, showsIndicators: true) {
                                        VStack(spacing: 2) {
                                            ForEach(Array(viewModel.activeRecommendations.enumerated()), id: \.element.id) { idx, rec in
                                                ShortcutSuggestionRow(
                                                    rec: rec,
                                                    isSelected: viewModel.selectedRecommendationIndex == idx
                                                ) {
                                                    viewModel.selectedRecommendationIndex = idx
                                                    viewModel.applyRecommendation(rec)
                                                }
                                                .id(rec.id)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .frame(maxHeight: 180)
                                    .onChange(of: viewModel.selectedRecommendationIndex) { newIndex in
                                        guard newIndex >= 0, newIndex < viewModel.activeRecommendations.count else { return }
                                        let targetId = viewModel.activeRecommendations[newIndex].id
                                        proxy.scrollTo(targetId)
                                    }
                                }
                            }
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .padding(.top, 4)
                        }
                    }

                    // 2. Shortcut Name (Optional) Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SHORTCUT NAME (OPTIONAL)")
                            .font(Theme.fontBadge)
                            .foregroundColor(Theme.textMuted)

                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                                .font(.system(size: 12))
                                .foregroundColor(focusedField == .name ? Theme.accent : Theme.textMuted)

                            TextField("e.g. Lock Mac, Open Swift Docs", text: $viewModel.formName)
                                .focused($focusedField, equals: .name)
                                .textFieldStyle(.plain)
                                .font(Theme.fontRowTitle)
                                .foregroundColor(Theme.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(focusedField == .name ? Theme.accent : Color.white.opacity(0.15), lineWidth: focusedField == .name ? 1.5 : 1)
                        )
                    }

                    // 3. Key Combination Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KEY COMBINATION")
                            .font(Theme.fontBadge)
                            .foregroundColor(Theme.textMuted)

                        HStack(spacing: 10) {
                            // Manual typing text field
                            HStack(spacing: 6) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 12))
                                    .foregroundColor(focusedField == .keyString ? Theme.accent : Theme.textMuted)

                                TextField("e.g. cmd+shift+k, opt+space", text: Binding(
                                    get: { viewModel.formKeyString },
                                    set: { viewModel.updateFormKeyString($0) }
                                ))
                                .focused($focusedField, equals: .keyString)
                                .textFieldStyle(.plain)
                                .font(Theme.fontCode)
                                .foregroundColor(Theme.textPrimary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(focusedField == .keyString ? Theme.accent : Color.white.opacity(0.15), lineWidth: focusedField == .keyString ? 1.5 : 1)
                            )

                            // Record Keys Button
                            Button {
                                if viewModel.isListeningForKey {
                                    viewModel.stopListening()
                                } else {
                                    viewModel.startListening()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if viewModel.isListeningForKey {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        Text("Listening...")
                                            .font(Theme.fontFooterLabel)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Color.white)
                                    } else {
                                        Image(systemName: "record.circle")
                                            .font(.system(size: 12))
                                        Text("Record Keys")
                                            .font(Theme.fontFooterLabel)
                                            .fontWeight(.medium)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    viewModel.isListeningForKey ? Color.red.opacity(0.3) : Theme.accent.opacity(0.18)
                                )
                                .foregroundColor(viewModel.isListeningForKey ? Color.white : Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            focusedField == .recordButton
                                                ? Theme.accent
                                                : (viewModel.isListeningForKey ? Color.red : Theme.accent.opacity(0.4)),
                                            lineWidth: focusedField == .recordButton ? 2 : 1
                                        )
                                )
                                .shadow(color: focusedField == .recordButton ? Theme.accent.opacity(0.5) : Color.clear, radius: 4)
                            }
                            .buttonStyle(.plain)
                            .focusable()
                            .focused($focusedField, equals: .recordButton)
                        }

                        if viewModel.isListeningForKey {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                Text(viewModel.capturePrompt)
                                    .font(Theme.fontFooterLabel)
                            }
                            .foregroundColor(Theme.accent)
                            .padding(.top, 2)
                        }

                        // Visual Keycap Preview
                        HStack(spacing: 8) {
                            Text("Visual Preview:")
                                .font(Theme.fontFooterLabel)
                                .foregroundColor(Theme.textMuted)

                            if let combo = viewModel.formCombination {
                                HStack(spacing: 4) {
                                    Text(combo.description)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.textPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Theme.accent.opacity(0.6), lineWidth: 1)
                                        )
                                }
                            } else {
                                Text("None (type combination or click Record Keys)")
                                    .font(Theme.fontFooterLabel)
                                    .foregroundColor(Theme.textMuted)
                            }
                        }
                        .padding(.top, 4)

                        // Duplicate Warning Banner
                        if let warning = viewModel.duplicateWarning {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.categoryCustom)

                                Text(warning)
                                    .font(Theme.fontFooterLabel)
                                    .foregroundColor(Theme.textPrimary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.categoryCustom.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.categoryCustom.opacity(0.4), lineWidth: 1)
                            )
                            .padding(.top, 4)
                        }
                    }

                    // 4. Save & Action Buttons
                    HStack(spacing: 10) {
                        Button {
                            viewModel.saveCurrentForm()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text(isEditing ? "Update Shortcut" : "Save Shortcut")
                                    .font(Theme.fontFooterLabel)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.accent)
                            .foregroundColor(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(focusedField == .saveButton ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .shadow(color: focusedField == .saveButton ? Theme.accent.opacity(0.6) : Color.clear, radius: 6)
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedField, equals: .saveButton)

                        Button {
                            viewModel.cancelForm()
                        } label: {
                            Text("Cancel")
                                .font(Theme.fontFooterLabel)
                                .foregroundColor(focusedField == .cancelButton ? Theme.textPrimary : Theme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(focusedField == .cancelButton ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(focusedField == .cancelButton ? Theme.accent : Color.clear, lineWidth: 1.5)
                                )
                                .shadow(color: focusedField == .cancelButton ? Theme.accent.opacity(0.3) : Color.clear, radius: 4)
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedField, equals: .cancelButton)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            viewModel.formFocusedField = .command
            focusedField = .command
            DispatchQueue.main.async {
                focusedField = .command
            }
        }
        .onChange(of: viewModel.page) { page in
            switch page {
            case .create, .edit:
                viewModel.formFocusedField = .command
                focusedField = .command
                DispatchQueue.main.async {
                    focusedField = .command
                }
            default:
                break
            }
        }
        .onChange(of: viewModel.formFocusedField) { newField in
            if focusedField != newField {
                focusedField = newField
            }
        }
        .onChange(of: focusedField) { newField in
            if let newField = newField, viewModel.formFocusedField != newField {
                viewModel.formFocusedField = newField
            }
        }
    }
}
