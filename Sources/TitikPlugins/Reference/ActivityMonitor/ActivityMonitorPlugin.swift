import Foundation
import AppKit
import SwiftUI
import TitikCore
import TitikPluginKit
import TitikUI

private final class ActivityMonitorViewModelStorage: @unchecked Sendable {
    var instance: Any?
}

/// Out-of-process dynamic Activity Monitor plugin conforming to TitikPlugin and PluginUIRepresentable.
public final class ActivityMonitorPlugin: NSObject, TitikPlugin, TitikCommandPlugin, @unchecked Sendable {
    public static let id = "titik.plugin.activitymonitor"
    public static let name = "Activity Monitor"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    nonisolated public var pluginId: String { Self.id }

    private let storage = ActivityMonitorViewModelStorage()

    @MainActor
    public var viewModel: ActivityMonitorViewModel {
        if let vm = storage.instance as? ActivityMonitorViewModel {
            return vm
        }
        let vm = ActivityMonitorViewModel()
        storage.instance = vm
        return vm
    }

    /// Zero out-of-the-box command definitions; interactive dynamic HUD replaces standard text commands.
    public var commands: [PluginCommandDefinition] { [] }

    public required init(context: PluginContext) {
        self.context = context
        super.init()
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        CommandExecutionResult.success(message: "Activity Monitor interactive session")
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        CommandExecutionResult.success(message: "Activity Monitor interactive session")
    }

    public func onShutdown() {
        Task { @MainActor in
            if let vm = self.storage.instance as? ActivityMonitorViewModel {
                vm.stop()
            }
        }
    }
}

// MARK: - PluginUIRepresentable Conformance

@MainActor
extension ActivityMonitorPlugin: PluginUIRepresentable {
    public var customView: AnyView {
        AnyView(ActivityMonitorView(viewModel: viewModel))
    }

    public var keymapScope: PluginKeymapScope { viewModel.keymapScope }

    public var onDismiss: (@MainActor @Sendable () -> Void)? {
        get { viewModel.onDismiss }
        set { viewModel.onDismiss = newValue }
    }

    public func handleSearchQuery(_ query: String) {
        viewModel.searchQuery = query
    }

    public func submitQuery() {
        if viewModel.pendingConfirmation != nil {
            viewModel.confirmPendingAction()
        }
    }
}

// MARK: - Plugin Manifest

public let activityMonitorPluginManifest = PluginManifest(
    id: ActivityMonitorPlugin.id,
    name: ActivityMonitorPlugin.name,
    icon: "📊",
    version: ActivityMonitorPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "System activity monitor and keyboard-first process manager",
    entrypoint: "ActivityMonitorPlugin",
    triggers: ["activity", "top", "ps"],
    permissions: ["process:signal", "system:metrics"]
)
