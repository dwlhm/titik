import Foundation
import AppKit
import SwiftUI
import TitikCore
import TitikPluginKit
import TitikUI

private final class NotesViewModelStorage: @unchecked Sendable {
    var instance: Any?
}

/// Out-of-process dynamic Notes plugin conforming to TitikPlugin, TitikCommandPlugin, and PluginUIRepresentable.
/// Explicitly does NOT conform to TitikGlobalSearchProvider, isolating notes strictly to the !note bang trigger.
public final class NotesPlugin: NSObject, TitikPlugin, TitikCommandPlugin, @unchecked Sendable {
    public static let id = "titik.plugin.notes"
    public static let name = "Notes"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    nonisolated public var pluginId: String { Self.id }

    private let storage = NotesViewModelStorage()

    @MainActor
    public var viewModel: NotesViewModel {
        if let vm = storage.instance as? NotesViewModel {
            return vm
        }
        let vm = NotesViewModel()
        storage.instance = vm
        return vm
    }

    public var commands: [PluginCommandDefinition] { [] }

    public required init(context: PluginContext) {
        self.context = context
        super.init()
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        CommandExecutionResult.success(message: "Notes interactive session")
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        CommandExecutionResult.success(message: "Notes interactive session")
    }

    public func onShutdown() {
        Task { @MainActor in
            if let vm = self.storage.instance as? NotesViewModel {
                vm.saveCurrentNote()
            }
        }
    }
}

// MARK: - PluginUIRepresentable Conformance

@MainActor
extension NotesPlugin: PluginUIRepresentable {
    public var customView: AnyView {
        AnyView(NotesView(viewModel: viewModel))
    }

    public var keymapScope: PluginKeymapScope { viewModel.keymapScope }

    public var onDismiss: (@MainActor @Sendable () -> Void)? {
        get { viewModel.onDismiss }
        set { viewModel.onDismiss = newValue }
    }

    public func onActivated() {
        viewModel.onActivated()
    }

    public func handleSearchQuery(_ query: String) {
        viewModel.handleSearchQuery(query)
    }

    public func submitQuery() {
        viewModel.submitQuery()
    }
}

// MARK: - Plugin Manifest

public let notesPluginManifest = PluginManifest(
    id: NotesPlugin.id,
    name: NotesPlugin.name,
    icon: "📝",
    version: NotesPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Flat-folder Markdown notes with live formatting and keyboard-first workflow",
    entrypoint: "NotesPlugin",
    triggers: ["note", "n"],
    permissions: ["filesystem:read", "filesystem:write"]
)
