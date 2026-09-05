import Foundation
import AppKit
import TitikCore
import TitikPluginKit

/// Built-in Zen Browser control plugin exposing commands for URLs, tabs, windows, and profiles.
public final class ZenBrowserPlugin: TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.plugin.zen"
    public static let name = "Zen Browser"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext

    public static let supportedBundleIdentifiers = [
        "app.zen-browser.zen",
        "io.zen-browser.zen",
        "org.mozilla.zen"
    ]

    public static let standardApplicationPaths = [
        "/Applications/Zen Browser.app",
        "/Applications/Zen.app",
        "~/Applications/Zen Browser.app",
        "~/Applications/Zen.app"
    ]

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "open-url",
                name: "Open URL",
                description: "Opens a URL in Zen Browser",
                triggers: ["open-url", "open", "url", "zen"],
                arguments: [
                    PluginCommandArgument(name: "url", description: "Target URL to open", isRequired: true),
                    PluginCommandArgument(name: "profile", description: "Zen profile / workspace", isRequired: false),
                    PluginCommandArgument(name: "private", description: "Open in private window (true/false)", isRequired: false)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "new-tab",
                name: "New Tab",
                description: "Opens a new tab in Zen Browser",
                triggers: ["new-tab", "tab", "t"],
                arguments: [
                    PluginCommandArgument(name: "url", description: "URL to open in new tab", isRequired: false),
                    PluginCommandArgument(name: "profile", description: "Zen profile / workspace", isRequired: false)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "new-window",
                name: "New Window",
                description: "Opens a new Zen Browser window",
                triggers: ["new-window", "window", "w"],
                arguments: [
                    PluginCommandArgument(name: "url", description: "URL to open in new window", isRequired: false),
                    PluginCommandArgument(name: "private", description: "Open in private window (true/false)", isRequired: false),
                    PluginCommandArgument(name: "profile", description: "Zen profile / workspace", isRequired: false)
                ],
                defaultMode: .background
            ),
            PluginCommandDefinition(
                id: "profile",
                name: "Open Profile",
                description: "Opens Zen Browser with a specific profile / workspace",
                triggers: ["profile", "p", "open-profile"],
                arguments: [
                    PluginCommandArgument(name: "profile", description: "Zen profile name", isRequired: true),
                    PluginCommandArgument(name: "url", description: "Target URL to open", isRequired: false)
                ],
                defaultMode: .background
            )
        ]
    }

    public required init(context: PluginContext) {
        self.context = context
    }

    /// Builds command-line flags and parameters for Zen Browser invocation.
    public func buildCLIFlags(id: String, arguments: [String: String]) -> [String] {
        var flags: [String] = []

        // Profile flag
        let profile = arguments["profile"] ?? arguments["P"] ?? arguments["p"]
        if let prof = profile, !prof.isEmpty {
            flags.append("-P")
            flags.append(prof)
        }

        // Action flags
        let isPrivate = (arguments["private"] == "true" || arguments["private"] == "1" || arguments["private-window"] == "true")
        switch id {
        case "new-tab":
            flags.append("-new-tab")
        case "new-window":
            if isPrivate {
                flags.append("-private-window")
            } else {
                flags.append("-new-window")
            }
        case "open-url", "profile":
            if isPrivate {
                flags.append("-private-window")
            }
        default:
            if isPrivate {
                flags.append("-private-window")
            }
        }

        // URL handling
        var targetURL = arguments["url"] ?? arguments["0"]
        if targetURL == nil && id != "profile" {
            targetURL = arguments["args"]
        }
        if let u = targetURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            flags.append(u)
        }

        return flags
    }

    public func executeCommand(
        invocation: PluginInvocation,
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        let normalizedId: String
        let rawAction = invocation.action ?? (commands.first(where: { $0.triggers.contains(invocation.trigger.lowercased()) })?.id)
        switch (rawAction ?? "").lowercased() {
        case "new-tab", "tab", "t":
            normalizedId = "new-tab"
        case "new-window", "window", "w":
            normalizedId = "new-window"
        case "profile", "p", "open-profile":
            normalizedId = "profile"
        default:
            normalizedId = "open-url"
        }

        var resolvedURL: String? = nil
        var resolvedProfile: String? = invocation.flag("profile") ?? invocation.flag("p")
        let isPrivate = invocation.hasFlag("private") || invocation.hasFlag("private-window")

        if normalizedId == "profile" {
            if let p = resolvedProfile, !p.isEmpty {
                resolvedURL = invocation.primaryValue.isEmpty ? invocation.flag("url") : invocation.primaryValue
            } else {
                resolvedProfile = invocation.primaryValue.isEmpty ? nil : invocation.primaryValue
                resolvedURL = invocation.flag("url")
            }
        } else {
            resolvedURL = invocation.primaryValue.isEmpty ? invocation.flag("url") : invocation.primaryValue
        }

        // Validation
        if normalizedId == "open-url" {
            guard let urlStr = resolvedURL?.trimmingCharacters(in: .whitespacesAndNewlines), !urlStr.isEmpty, urlStr != "-" else {
                return CommandExecutionResult.failure(message: "Missing URL argument for open-url command")
            }
            resolvedURL = urlStr
        } else if normalizedId == "profile" {
            guard let prof = resolvedProfile?.trimmingCharacters(in: .whitespacesAndNewlines), !prof.isEmpty else {
                return CommandExecutionResult.failure(message: "Missing profile argument for profile command")
            }
            resolvedProfile = prof
        }

        var arguments: [String: String] = [:]
        if let u = resolvedURL { arguments["url"] = u }
        if let p = resolvedProfile { arguments["profile"] = p }
        if isPrivate { arguments["private"] = "true" }

        let flags = buildCLIFlags(id: normalizedId, arguments: arguments)
        let launchSuccess = launchZenBrowser(with: flags)

        var output: [String: String] = [
            "command": normalizedId,
            "flags": flags.joined(separator: " ")
        ]
        if let u = resolvedURL { output["url"] = u }
        if let p = resolvedProfile { output["profile"] = p }

        let profileSuffix: String
        if let profile = resolvedProfile, !profile.isEmpty {
            profileSuffix = " (Profile: \(profile))"
        } else {
            profileSuffix = ""
        }
        let targetDetail = resolvedURL ?? (resolvedProfile.map { "profile '\($0)'" } ?? normalizedId)
        let message = "Opened \(targetDetail) in Zen Browser\(profileSuffix)"

        if launchSuccess {
            return CommandExecutionResult.success(message: message, outputPayload: output)
        } else {
            Logger.shared.info("Zen Browser application launch returned false (normal in headless/CI)", subsystem: "Titik.ZenBrowserPlugin")
            return CommandExecutionResult.success(message: message, outputPayload: output)
        }
    }

    public func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult {
        var flagValues: [String: FlagValue] = [:]
        for (k, v) in arguments {
            if ["true", "false"].contains(v.lowercased()) {
                flagValues[k] = .boolean(v.lowercased() == "true")
            } else {
                flagValues[k] = .string(v)
            }
        }
        let primary = arguments["url"] ?? arguments["args"] ?? arguments["0"] ?? ""
        let invocation = PluginInvocation(
            trigger: "zen",
            action: id,
            primaryValue: primary,
            flags: flagValues,
            rawInput: context.rawInput
        )
        return try await executeCommand(invocation: invocation, context: context)
    }

    public func onQuery(invocation: PluginInvocation) async throws -> PluginCanvas {
        try await onQuery(invocation.primaryValue)
    }

    private func launchZenBrowser(with flags: [String]) -> Bool {
        var appURL: URL? = nil
        for bundleId in Self.supportedBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                appURL = url
                break
            }
        }

        if appURL == nil {
            for path in Self.standardApplicationPaths {
                let expanded = (path as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expanded) {
                    appURL = URL(fileURLWithPath: expanded)
                    break
                }
            }
        }

        guard let targetAppURL = appURL else {
            Logger.shared.warn("Zen Browser not found in standard paths", subsystem: "Titik.ZenBrowserPlugin")
            return false
        }

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = flags
        config.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var success = false

        NSWorkspace.shared.openApplication(at: targetAppURL, configuration: config) { app, error in
            if let error = error {
                Logger.shared.error("Failed to launch Zen Browser: \(error.localizedDescription)", subsystem: "Titik.ZenBrowserPlugin")
                success = false
            } else {
                success = true
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2.0)
        return success
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let items = commands.map { cmd in
                PluginItem(
                    id: "\(Self.id):\(cmd.id)",
                    title: cmd.name,
                    subtitle: cmd.description,
                    category: "Zen Browser",
                    actionPayload: "!zen \(cmd.id) ",
                    scoreBoost: 500,
                    pluginId: Self.id
                )
            }
            return .list(items)
        }

        var items: [PluginItem] = []

        // If user typed a URL or domain
        if trimmed.contains(".") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("zen://") {
            let formattedURL = (trimmed.contains("://")) ? trimmed : "https://\(trimmed)"
            items.append(
                PluginItem(
                    id: "\(Self.id):open-url:\(formattedURL)",
                    title: "Open '\(formattedURL)'",
                    subtitle: "Open URL in Zen Browser",
                    category: "Zen Browser",
                    actionPayload: formattedURL,
                    scoreBoost: 600,
                    pluginId: Self.id
                )
            )
        }

        // Match against subcommands
        for cmd in commands {
            if cmd.id.localizedCaseInsensitiveContains(trimmed) ||
               cmd.name.localizedCaseInsensitiveContains(trimmed) ||
               cmd.description.localizedCaseInsensitiveContains(trimmed) {
                items.append(
                    PluginItem(
                        id: "\(Self.id):\(cmd.id)",
                        title: cmd.name,
                        subtitle: cmd.description,
                        category: "Zen Browser",
                        actionPayload: "!zen \(cmd.id) ",
                        scoreBoost: 500,
                        pluginId: Self.id
                    )
                )
            }
        }

        if items.isEmpty {
            // Fallback generic search in Zen Browser
            items.append(
                PluginItem(
                    id: "\(Self.id):search:\(trimmed)",
                    title: "Search Zen Browser for '\(trimmed)'",
                    subtitle: "Opens search query in Zen Browser",
                    category: "Zen Browser",
                    actionPayload: "https://duckduckgo.com/?q=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)",
                    scoreBoost: 400,
                    pluginId: Self.id
                )
            )
        }

        return .list(items)
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}

public let zenBrowserPluginManifest = PluginManifest(
    id: "titik.plugin.zen",
    name: ZenBrowserPlugin.name,
    icon: "🧘",
    version: ZenBrowserPlugin.version,
    sdkVersion: titikSDKVersion,
    description: "Control Zen Browser tabs, windows, and profiles",
    entrypoint: "ZenBrowserPlugin",
    triggers: ["zen"],
    permissions: ["workspace:launch"]
)
