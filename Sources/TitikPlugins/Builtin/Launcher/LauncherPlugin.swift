import Foundation
import AppKit
import TitikCore
import TitikPluginKit

/// Built-in App and Project Launcher plugin exposing commands for launching apps and opening IDE projects.
public final class LauncherPlugin: TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.builtin.launcher"
    public static let name = "App & Project Launcher"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    private let appLauncher: AppLauncher

    public static let supportedIDEs = [
        "Antigravity",
        "Visual Studio Code",
        "VS Code",
        "Cursor",
        "Xcode",
        "Sublime Text",
        "IntelliJ IDEA",
        "WebStorm",
        "PyCharm",
        "Fleet"
    ]

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "launch-app",
                name: "Launch Application",
                description: "Launches an application by name or path",
                triggers: ["launch-app", "launch"],
                arguments: [
                    PluginCommandArgument(name: "app", description: "Application name or bundle path", isRequired: true)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "open-project",
                name: "Open Project in IDE",
                description: "Opens a project directory in Antigravity, VS Code, or Cursor",
                triggers: ["open-project", "project", "open", "o"],
                arguments: [
                    PluginCommandArgument(name: "path", description: "Project directory path", isRequired: true),
                    PluginCommandArgument(name: "ide", description: "Target IDE (e.g. Antigravity, VS Code, Cursor)", isRequired: false)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "open-path",
                name: "Open Path in Finder",
                description: "Opens a directory or file in Finder or default application",
                triggers: ["open-path", "path", "finder"],
                arguments: [
                    PluginCommandArgument(name: "path", description: "File or directory path", isRequired: true)
                ],
                defaultMode: .background
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
        self.appLauncher = AppLauncher.shared
    }

    public init(context: PluginContext, appLauncher: AppLauncher) {
        self.context = context
        self.appLauncher = appLauncher
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let action = invocation.action ?? invocation.trigger
        let normalizedId: String
        switch action.lowercased() {
        case "launch-app", "app", "launch":
            normalizedId = "launch-app"
        case "open-project", "project", "open", "o":
            normalizedId = "open-project"
        case "open-path", "path", "finder":
            normalizedId = "open-path"
        default:
            normalizedId = action
        }

        switch normalizedId {
        case "launch-app":
            let appName = invocation.flag("app") ?? (!invocation.primaryValue.isEmpty ? invocation.primaryValue : nil)
            guard let target = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
                return CommandExecutionResult.failure(message: "Missing application name argument")
            }

            let expanded = PathResolver.expandPath(target)
            if FileManager.default.fileExists(atPath: expanded) {
                let success = appLauncher.launchApp(at: expanded)
                return CommandExecutionResult.success(
                    message: "Launched application at \(expanded)",
                    outputPayload: ["app": target, "path": expanded, "launched": success ? "true" : "false"]
                )
            }

            // Search by name
            let apps = appLauncher.getApplications()
            let clean = target.lowercased().replacingOccurrences(of: ".app", with: "")
            if let match = apps.first(where: {
                $0.name.lowercased() == clean ||
                $0.bundleURL.deletingPathExtension().lastPathComponent.lowercased() == clean ||
                $0.path.lowercased().contains(clean)
            }) {
                let success = appLauncher.launchApp(at: match.path)
                return CommandExecutionResult.success(
                    message: "Launched \(match.name)",
                    outputPayload: ["app": match.name, "path": match.path, "launched": success ? "true" : "false"]
                )
            }

            return CommandExecutionResult.failure(message: "Application '\(target)' not found")

        case "open-project":
            let rawPath = invocation.flag("path") ?? (!invocation.primaryValue.isEmpty ? invocation.primaryValue : nil)
            guard let targetPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !targetPath.isEmpty else {
                return CommandExecutionResult.failure(message: "Missing project path argument")
            }

            let expandedPath = PathResolver.expandPath(targetPath)
            let ide = invocation.flag("ide") ?? "Antigravity"

            let ideAppURL = resolveIDEAppURL(ide: ide)
            let opened = openPathWithIDE(path: expandedPath, ideAppURL: ideAppURL)

            return CommandExecutionResult.success(
                message: "Opened \(expandedPath) in \(ide)",
                outputPayload: [
                    "path": expandedPath,
                    "ide": ide,
                    "opened": opened ? "true" : "false"
                ]
            )

        case "open-path":
            let rawPath = invocation.flag("path") ?? (!invocation.primaryValue.isEmpty ? invocation.primaryValue : nil)
            guard let targetPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !targetPath.isEmpty else {
                return CommandExecutionResult.failure(message: "Missing path argument")
            }

            let expandedPath = PathResolver.expandPath(targetPath)
            let url = URL(fileURLWithPath: expandedPath)
            let success = NSWorkspace.shared.open(url)

            return CommandExecutionResult.success(
                message: "Opened path at \(expandedPath)",
                outputPayload: ["path": expandedPath, "opened": success ? "true" : "false"]
            )

        default:
            return CommandExecutionResult.failure(message: "Unknown command: \(action)")
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
        let primary = arguments["app"] ?? arguments["path"] ?? arguments["0"] ?? arguments["args"] ?? ""
        let invocation = PluginInvocation(
            trigger: context.trigger,
            action: id,
            primaryValue: primary,
            flags: flags,
            rawInput: context.rawInput
        )
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func resolveIDEAppURL(ide: String) -> URL? {
        let apps = appLauncher.getApplications()
        let cleanIde = ide.lowercased()

        if let match = apps.first(where: {
            $0.name.lowercased() == cleanIde ||
            $0.name.lowercased().contains(cleanIde) ||
            $0.path.lowercased().contains(cleanIde)
        }) {
            return match.bundleURL
        }

        // Check common IDE bundle IDs
        let bundleIds: [String: String] = [
            "antigravity": "com.google.antigravity",
            "vscode": "com.microsoft.VSCode",
            "vs code": "com.microsoft.VSCode",
            "visual studio code": "com.microsoft.VSCode",
            "cursor": "com.todesktop.230313mzl4w4u92",
            "xcode": "com.apple.dt.Xcode"
        ]

        if let bundleId = bundleIds[cleanIde],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }

        return nil
    }

    private func openPathWithIDE(path: String, ideAppURL: URL?) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        if let ideURL = ideAppURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            let sema = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var success = false

            NSWorkspace.shared.open([fileURL], withApplicationAt: ideURL, configuration: config) { app, error in
                if error == nil {
                    success = true
                }
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 2.0)
            return success
        } else {
            return NSWorkspace.shared.open(fileURL)
        }
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let items = commands.map { cmd in
                PluginItem(
                    id: "\(Self.id):\(cmd.id)",
                    title: cmd.name,
                    subtitle: cmd.description,
                    category: "Launcher",
                    actionPayload: "!open \(cmd.id) ",
                    scoreBoost: 500,
                    pluginId: Self.id
                )
            }
            return .list(items)
        }

        var items: [PluginItem] = []

        // If path query
        if PathResolver.isPathQuery(trimmed) {
            let expanded = PathResolver.expandPath(trimmed)
            items.append(
                PluginItem(
                    id: "\(Self.id):project:\(expanded)",
                    title: "Open Project '\((expanded as NSString).lastPathComponent)'",
                    subtitle: "Open in Antigravity / IDE • \(expanded)",
                    category: "Launcher",
                    actionPayload: expanded,
                    scoreBoost: 600,
                    pluginId: Self.id
                )
            )
        }

        // Search matching applications
        let appMatches = appLauncher.searchApplications(query: trimmed)
        for app in appMatches.prefix(10) {
            items.append(
                PluginItem(
                    id: "\(Self.id):app:\(app.id)",
                    title: "Launch \(app.title)",
                    subtitle: app.subtitle,
                    category: "Application",
                    actionPayload: app.actionPayload,
                    scoreBoost: app.score,
                    pluginId: Self.id
                )
            )
        }

        return .list(items)
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let launcherPluginManifest = PluginManifest(
    id: LauncherPlugin.id,
    name: LauncherPlugin.name,
    version: LauncherPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Launch applications and open IDE projects",
    entrypoint: "LauncherPlugin",
    triggers: ["open", "o", "project"],
    permissions: ["workspace:launch"]
)
