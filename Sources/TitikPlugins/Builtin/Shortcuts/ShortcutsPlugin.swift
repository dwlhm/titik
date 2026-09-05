import Foundation
import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikPluginKit
import TitikUI

private final class ShortcutsViewModelStorage: @unchecked Sendable {
    var instance: Any?
}

/// Built-in Shortcuts Inspector plugin exposing commands to list, filter, trigger, and inspect global hotkeys,
/// with interactive UI for creating, editing, and recording key combinations.
public final class ShortcutsPlugin: TitikPlugin, TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.builtin.shortcuts"
    public static let name = "Shortcuts Inspector"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    nonisolated public var pluginId: String { Self.id }
    public let keymapRegistry: KeymapRegistry
    public let hotkeyManager: HotkeyManager
    private let customShortcutManager: ShortcutManager?
    private let storage = ShortcutsViewModelStorage()

    @MainActor
    public var shortcutManager: ShortcutManager {
        customShortcutManager ?? ShortcutManager.shared
    }

    @MainActor
    public var viewModel: ShortcutsPluginViewModel {
        if let vm = storage.instance as? ShortcutsPluginViewModel {
            return vm
        }
        let vm = ShortcutsPluginViewModel(manager: shortcutManager)
        storage.instance = vm
        return vm
    }

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "list-shortcuts",
                name: "List Shortcuts",
                description: "Lists all active global shortcuts and their key combinations",
                triggers: ["list-shortcuts", "list", "all", "shortcuts", "shortcut", "keys", "hotkeys"],
                arguments: [
                    PluginCommandArgument(name: "filter", description: "Filter term for shortcuts", isRequired: false)
                ],
                defaultMode: .palette
            ),
            PluginCommandDefinition(
                id: "trigger-shortcut",
                name: "Trigger Shortcut",
                description: "Programmatically triggers a registered shortcut by identifier",
                triggers: ["trigger-shortcut", "trigger", "run"],
                arguments: [
                    PluginCommandArgument(name: "identifier", description: "Shortcut identifier", isRequired: true)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "inspect-conflicts",
                name: "Inspect Hotkey Conflicts",
                description: "Analyzes all registered key combinations for potential collisions",
                triggers: ["inspect-conflicts", "conflicts", "check"],
                arguments: [],
                defaultMode: .palette
            ),
            PluginCommandDefinition(
                id: "reload-shortcuts",
                name: "Reload Shortcuts",
                description: "Reloads all shortcuts and hotkey bindings from configuration",
                triggers: ["reload-shortcuts", "reload"],
                arguments: [],
                defaultMode: .background
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
        self.keymapRegistry = KeymapRegistry.shared
        self.hotkeyManager = HotkeyManager.shared
        self.customShortcutManager = nil
    }

    public init(
        context: PluginContext,
        keymapRegistry: KeymapRegistry = .shared,
        hotkeyManager: HotkeyManager = .shared,
        shortcutManager: ShortcutManager? = nil
    ) {
        self.context = context
        self.keymapRegistry = keymapRegistry
        self.hotkeyManager = hotkeyManager
        self.customShortcutManager = shortcutManager
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let action = invocation.action ?? invocation.trigger
        let normalizedId: String
        switch action.lowercased() {
        case "list-shortcuts", "list", "all", "shortcut", "shortcuts", "hotkeys", "keys":
            normalizedId = "list-shortcuts"
        case "trigger-shortcut", "trigger", "run":
            normalizedId = "trigger-shortcut"
        case "inspect-conflicts", "conflicts", "check":
            normalizedId = "inspect-conflicts"
        case "reload-shortcuts", "reload":
            normalizedId = "reload-shortcuts"
        default:
            normalizedId = action
        }

        switch normalizedId {
        case "list-shortcuts":
            let bindings = keymapRegistry.allBindings()
            let filter = invocation.flag("filter") ?? (!invocation.primaryValue.isEmpty ? invocation.primaryValue : nil)
            let filtered: [KeyBinding]
            if let f = filter?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
                filtered = bindings.filter {
                    $0.identifier.localizedCaseInsensitiveContains(f) ||
                    $0.combination.description.localizedCaseInsensitiveContains(f)
                }
            } else {
                filtered = bindings
            }

            let summary = filtered.map { "\($0.combination.description) -> \($0.identifier) [\($0.mode.rawValue)]" }.joined(separator: "\n")
            return CommandExecutionResult.success(
                message: "Found \(filtered.count) active shortcuts",
                outputPayload: [
                    "count": String(filtered.count),
                    "shortcuts": summary
                ]
            )

        case "trigger-shortcut":
            let targetId = invocation.flag("identifier") ?? (!invocation.primaryValue.isEmpty ? invocation.primaryValue : nil)
            guard let idToTrigger = targetId?.trimmingCharacters(in: .whitespacesAndNewlines), !idToTrigger.isEmpty else {
                return CommandExecutionResult.failure(message: "Missing shortcut identifier to trigger")
            }

            // 1. Check ShortcutManager active shortcuts by ID, name, or command target
            let match = await MainActor.run { () -> ShortcutConfig? in
                let all = self.shortcutManager.shortcuts
                return all.first { sc in
                    sc.id.lowercased() == idToTrigger.lowercased() ||
                    (sc.name?.lowercased() == idToTrigger.lowercased()) ||
                    sc.action.target.lowercased() == idToTrigger.lowercased() ||
                    sc.keyCombinationString.lowercased() == idToTrigger.lowercased()
                }
            }

            if let shortcut = match {
                if hotkeyManager.trigger(identifier: shortcut.id) {
                    return CommandExecutionResult.success(
                        message: "Triggered shortcut '\(shortcut.name ?? shortcut.action.target)'",
                        outputPayload: ["identifier": shortcut.id, "target": shortcut.action.target]
                    )
                } else {
                    await MainActor.run {
                        self.shortcutManager.dispatcher?(shortcut.action.target)
                    }
                    return CommandExecutionResult.success(
                        message: "Triggered shortcut '\(shortcut.name ?? shortcut.action.target)' via dispatcher",
                        outputPayload: ["identifier": shortcut.id, "target": shortcut.action.target]
                    )
                }
            }

            // 2. Fallback to HotkeyManager direct identifier
            if hotkeyManager.trigger(identifier: idToTrigger) {
                return CommandExecutionResult.success(
                    message: "Triggered shortcut '\(idToTrigger)'",
                    outputPayload: ["identifier": idToTrigger]
                )
            } else if let binding = keymapRegistry.find(identifier: idToTrigger) {
                await MainActor.run { binding.action() }
                return CommandExecutionResult.success(
                    message: "Triggered shortcut '\(idToTrigger)' via registry",
                    outputPayload: ["identifier": idToTrigger]
                )
            } else {
                return CommandExecutionResult.failure(message: "Shortcut '\(idToTrigger)' not found")
            }

        case "inspect-conflicts":
            let bindings = keymapRegistry.allBindings()
            var combos: [KeyCombination: [String]] = [:]
            for b in bindings {
                combos[b.combination, default: []].append(b.identifier)
            }

            let conflicts = combos.filter { $0.value.count > 1 }
            if conflicts.isEmpty {
                return CommandExecutionResult.success(
                    message: "Zero hotkey conflicts detected (\(bindings.count) total bindings checked)",
                    outputPayload: ["conflicts": "0", "total": String(bindings.count)]
                )
            } else {
                let conflictDetails = conflicts.map { "\($0.key.description): \($0.value.joined(separator: ", "))" }.joined(separator: "\n")
                return CommandExecutionResult.failure(
                    message: "Found \(conflicts.count) conflicting hotkey bindings",
                    outputPayload: ["conflicts": String(conflicts.count), "details": conflictDetails]
                )
            }

        case "reload-shortcuts":
            await MainActor.run {
                self.shortcutManager.reloadFromConfig()
                self.viewModel.loadRecommendations()
            }
            return CommandExecutionResult.success(
                message: "Shortcuts reloaded successfully",
                outputPayload: ["reloaded": "true"]
            )

        default:
            // Check if action matches a shortcut in ShortcutManager
            let match = await MainActor.run { () -> ShortcutConfig? in
                let all = self.shortcutManager.shortcuts
                return all.first { sc in
                    sc.id.lowercased() == action.lowercased() ||
                    (sc.name?.lowercased() == action.lowercased()) ||
                    sc.action.target.lowercased() == action.lowercased()
                }
            }
            if let shortcut = match {
                if hotkeyManager.trigger(identifier: shortcut.id) {
                    return CommandExecutionResult.success(
                        message: "Triggered shortcut '\(shortcut.name ?? shortcut.action.target)'",
                        outputPayload: ["identifier": shortcut.id, "target": shortcut.action.target]
                    )
                } else {
                    await MainActor.run {
                        self.shortcutManager.dispatcher?(shortcut.action.target)
                    }
                    return CommandExecutionResult.success(
                        message: "Triggered shortcut '\(shortcut.name ?? shortcut.action.target)' via dispatcher",
                        outputPayload: ["identifier": shortcut.id, "target": shortcut.action.target]
                    )
                }
            }

            if hotkeyManager.trigger(identifier: action) {
                return CommandExecutionResult.success(
                    message: "Triggered shortcut '\(action)'",
                    outputPayload: ["identifier": action]
                )
            } else if let binding = keymapRegistry.find(identifier: action) {
                await MainActor.run { binding.action() }
                return CommandExecutionResult.success(
                    message: "Triggered shortcut '\(action)' via registry",
                    outputPayload: ["identifier": action]
                )
            } else {
                return CommandExecutionResult.failure(message: "Unknown command: \(action)")
            }
        }
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        var flags: [String: FlagValue] = [:]
        for (k, v) in arguments {
            flags[k] = .string(v)
        }
        let primary = arguments["filter"] ?? arguments["identifier"] ?? arguments["0"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(
            trigger: context.trigger,
            action: id,
            primaryValue: primary,
            flags: flags,
            rawInput: context.rawInput
        )
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanQuery = trimmed

        let aliases = ["list-shortcuts", "list", "all"]
        for alias in aliases {
            if cleanQuery.lowercased() == alias {
                cleanQuery = ""
                break
            } else if cleanQuery.lowercased().hasPrefix(alias + " ") {
                cleanQuery = String(cleanQuery.dropFirst(alias.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let bindings = keymapRegistry.allBindings()
        let shortcuts = await MainActor.run { self.shortcutManager.shortcuts }

        let filtered: [KeyBinding]
        if cleanQuery.isEmpty {
            filtered = bindings
        } else {
            filtered = bindings.filter { binding in
                let sc = shortcuts.first { $0.id == binding.identifier || "shortcut:\($0.id)" == binding.identifier }
                let target = sc?.action.target ?? ""
                let name = sc?.name ?? ""
                return binding.identifier.localizedCaseInsensitiveContains(cleanQuery) ||
                    binding.combination.description.localizedCaseInsensitiveContains(cleanQuery) ||
                    binding.mode.rawValue.localizedCaseInsensitiveContains(cleanQuery) ||
                    target.localizedCaseInsensitiveContains(cleanQuery) ||
                    name.localizedCaseInsensitiveContains(cleanQuery)
            }
        }

        let items = filtered.map { binding in
            let modeBadge = binding.mode == .background ? "[bg]" : "[palette]"
            let sc = shortcuts.first { $0.id == binding.identifier || "shortcut:\($0.id)" == binding.identifier }
            let displayName: String
            if let name = sc?.name, !name.isEmpty {
                displayName = "\(name) (\(binding.identifier))"
            } else if let target = sc?.action.target, !target.isEmpty {
                displayName = "\(target) (\(binding.identifier))"
            } else {
                displayName = binding.identifier
            }

            let subtitle: String
            if let target = sc?.action.target, !target.isEmpty {
                subtitle = "\(modeBadge) \(target)"
            } else {
                subtitle = "\(modeBadge) \(binding.identifier)"
            }

            return PluginItem(
                id: "\(Self.id):\(binding.identifier)",
                title: "\(binding.combination.description) (\(displayName))",
                subtitle: subtitle,
                category: "Shortcuts",
                actionPayload: binding.identifier,
                scoreBoost: 500,
                pluginId: Self.id
            )
        }

        return .list(items)
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

@MainActor
extension ShortcutsPlugin: PluginUIRepresentable {
    public var customView: AnyView {
        AnyView(ShortcutsPluginView(viewModel: viewModel))
    }

    public var keymapScope: PluginKeymapScope {
        viewModel.keymapScope
    }

    public var onDismiss: (@MainActor () -> Void)? {
        get { viewModel.onDismiss }
        set { viewModel.onDismiss = newValue }
    }

    public func onActivated() {
        if case .create = viewModel.page { return }
        if case .edit = viewModel.page { return }
        viewModel.page = .list
        viewModel.stopListening()
        viewModel.duplicateWarning = nil
        viewModel.filterQuery = ""
        viewModel.selectedRowIndex = 0
        viewModel.updateKeymapScope()
    }

    public func handleSearchQuery(_ query: String) {
        if case .create = viewModel.page { return }
        if case .edit = viewModel.page { return }
        viewModel.filterQuery = query
    }

    public func submitQuery() {
        viewModel.submitQuery()
    }
}

public let shortcutsPluginManifest = PluginManifest(
    id: ShortcutsPlugin.id,
    name: ShortcutsPlugin.name,
    version: ShortcutsPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Inspect and trigger active global shortcuts",
    entrypoint: "ShortcutsPlugin",
    triggers: ["keys", "shortcut", "shortcuts"],
    permissions: ["keymap:read"]
)
