import Foundation
import AppKit
import TitikCore
import TitikKeymap
import TitikPluginKit
import TitikPlugins
import TitikSearch
import TitikParser

/// A unified command dispatcher coordinating execution across global hotkeys,
/// palette search bang queries, contextual actions, and background silent tasks.
public final class PluginCommandDispatcher: @unchecked Sendable {
    public static let shared = PluginCommandDispatcher()

    private let pluginHost: PluginHost
    private let appLauncher: AppLauncher
    private let systemCommands: SystemCommands
    private let clipboardManager: ClipboardManager
    private let searchEngine: SearchEngine
    private let parser: CommandParser
    public let timeoutNanoseconds: UInt64

    public init(
        pluginHost: PluginHost = .shared,
        appLauncher: AppLauncher = .shared,
        systemCommands: SystemCommands = .shared,
        clipboardManager: ClipboardManager = .shared,
        searchEngine: SearchEngine = .shared,
        parser: CommandParser = CommandParser(),
        timeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        self.pluginHost = pluginHost
        self.appLauncher = appLauncher
        self.systemCommands = systemCommands
        self.clipboardManager = clipboardManager
        self.searchEngine = searchEngine
        self.parser = parser
        self.timeoutNanoseconds = timeoutNanoseconds

        setupSearchEngineBridge()
    }

    private func setupSearchEngineBridge() {
        SearchEngine.pluginCommandDispatcher = { [weak self] pluginId, payload in
            guard let self = self else { return false }
            let targetPlugin: (any TitikCommandPlugin)?
            if let cmdPlugin = self.pluginHost.getNativePlugin(id: pluginId) as? (any TitikCommandPlugin) {
                targetPlugin = cmdPlugin
            } else if let manifest = self.pluginHost.findActivePlugin(command: pluginId),
                      let cmdPlugin = self.pluginHost.getNativePlugin(id: manifest.id) as? (any TitikCommandPlugin) {
                targetPlugin = cmdPlugin
            } else {
                targetPlugin = nil
            }

            guard let cmdPlugin = targetPlugin else {
                return false
            }

            Task {
                let invocation = PluginInvocation(trigger: pluginId, action: payload, primaryValue: payload, flags: [:], rawInput: payload)
                let ctx = CommandExecutionContext(trigger: "search", mode: .background, rawInput: payload)
                _ = try? await cmdPlugin.executeCommand(invocation: invocation, context: ctx)
            }
            return true
        }
    }

    // MARK: - Primary Dispatch API

    /// Dispatches a configured shortcut action with presentation mode awareness.
    @discardableResult
    public func dispatch(
        action: ShortcutActionConfig,
        mode: ShortcutExecutionMode = .background,
        rawInput: String = ""
    ) async -> CommandExecutionResult {
        Logger.shared.info("Dispatching action type: \(action.type.rawValue), target: \(action.target), mode: \(mode.rawValue)", subsystem: "Titik.Dispatcher")

        // Handle palette window presentation if requested
        if mode == .palette {
            await MainActor.run {
                WindowController.shared.showWindow()
                if action.type == .rawQuery {
                    UIOrchestrator.shared.query = action.target
                } else if !rawInput.isEmpty {
                    UIOrchestrator.shared.query = rawInput
                }
            }
        }

        switch action.type {
        case .pluginCommand:
            return await dispatchPluginCommand(
                target: action.target,
                arguments: action.arguments ?? [:],
                mode: mode,
                rawInput: rawInput.isEmpty ? action.target : rawInput
            )

        case .appLaunch:
            return await dispatchAppLaunch(target: action.target)

        case .quickLink:
            return await dispatchQuickLink(target: action.target)

        case .rawQuery:
            if mode == .palette {
                return CommandExecutionResult.success(message: "Opened palette with query: \(action.target)")
            } else {
                let items = searchEngine.search(query: action.target)
                if let first = items.first {
                    _ = first.action()
                    return CommandExecutionResult.success(
                        message: first.title,
                        outputPayload: ["result": first.actionPayload.isEmpty ? first.title : first.actionPayload]
                    )
                }
                return CommandExecutionResult.success(message: "Executed query: \(action.target)")
            }

        case .toggleWindow:
            await MainActor.run {
                WindowController.shared.toggleWindow()
            }
            return CommandExecutionResult.success(message: "Toggled window")

        case .systemCommand:
            return await dispatchSystemCommand(target: action.target)
        }
    }

    /// Dispatches a plugin command directly by plugin ID or command trigger.
    @discardableResult
    public func dispatch(
        pluginId: String,
        commandId: String? = nil,
        arguments: [String: String] = [:],
        mode: ShortcutExecutionMode = .background,
        rawInput: String = ""
    ) async -> CommandExecutionResult {
        var mergedArgs = arguments
        if let cid = commandId, mergedArgs["command"] == nil {
            mergedArgs["command"] = cid
        }
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: pluginId,
            arguments: mergedArgs
        )
        return await dispatch(action: action, mode: mode, rawInput: rawInput)
    }

    /// Dispatches a raw query or bang command string (e.g. "!zen -new-tab https://apple.com").
    @discardableResult
    public func dispatch(
        query: String,
        mode: ShortcutExecutionMode = .background
    ) async -> CommandExecutionResult {
        return await dispatchQuery(query, mode: mode)
    }

    // MARK: - Private Action Executors

    private func dispatchQuery(
        _ query: String,
        mode: ShortcutExecutionMode
    ) async -> CommandExecutionResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CommandExecutionResult.failure(message: "Empty query")
        }

        let cleanQuery = trimmed.hasPrefix("!") ? trimmed : ("!" + trimmed)
        let firstWord = trimmed.hasPrefix("!") ? String(trimmed.dropFirst()).components(separatedBy: .whitespaces).first ?? "" : (trimmed.components(separatedBy: .whitespaces).first ?? "")
        let cleanCommandName = firstWord.trimmingCharacters(in: CharacterSet(charactersIn: "!"))

        if let manifest = pluginHost.findActivePlugin(command: cleanCommandName) {
            let native = pluginHost.getNativePlugin(id: manifest.id)
            guard let cmdPlugin = native as? (any TitikCommandPlugin) else {
                return CommandExecutionResult.failure(message: "Plugin '\(manifest.id)' does not support command execution")
            }

            let knownSubcommands = Set(cmdPlugin.commands.flatMap { [$0.id.lowercased()] + $0.triggers.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "!")) } })
            let ast = parser.parse(cleanQuery, knownSubcommands: knownSubcommands)

            let invocation: PluginInvocation
            if case .pluginInvocation(_, let action, let primaryValue, let flags, let booleanFlags, _) = ast {
                var flagValues: [String: FlagValue] = [:]
                for b in booleanFlags {
                    flagValues[b] = .boolean(true)
                }
                for (k, v) in flags {
                    if !booleanFlags.contains(k) {
                        flagValues[k] = .string(v)
                    }
                }

                // Resolve effective action if not matched by segment parser
                var resolvedAction = action
                if resolvedAction == nil {
                    if let matchingCmd = cmdPlugin.commands.first(where: {
                        $0.id.lowercased() == cleanCommandName.lowercased() ||
                        $0.triggers.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "!")) }.contains(cleanCommandName.lowercased())
                    }) {
                        resolvedAction = matchingCmd.id
                    }
                }

                invocation = PluginInvocation(
                    trigger: manifest.id,
                    action: resolvedAction,
                    primaryValue: primaryValue,
                    flags: flagValues,
                    rawInput: trimmed
                )
            } else {
                invocation = PluginInvocation(
                    trigger: manifest.id,
                    action: nil,
                    primaryValue: "",
                    flags: [:],
                    rawInput: trimmed
                )
            }

            let context = CommandExecutionContext(
                trigger: "dispatcher",
                mode: mode,
                rawInput: trimmed
            )

            return await executeInvocationWithTimeout(
                plugin: cmdPlugin,
                invocation: invocation,
                context: context
            )
        } else {
            let action = ShortcutActionConfig(type: .rawQuery, target: trimmed)
            return await dispatch(action: action, mode: mode, rawInput: trimmed)
        }
    }

    private func dispatchPluginCommand(
        target: String,
        arguments: [String: String],
        mode: ShortcutExecutionMode,
        rawInput: String,
        timeout: TimeInterval? = nil
    ) async -> CommandExecutionResult {
        // 1. Resolve plugin instance
        var targetPluginId = target
        var resolvedPlugin: (any TitikPlugin)? = pluginHost.getNativePlugin(id: target)

        if resolvedPlugin == nil {
            let cleanTarget = target.trimmingCharacters(in: CharacterSet(charactersIn: "!"))
            if let manifest = pluginHost.findActivePlugin(command: cleanTarget) {
                targetPluginId = manifest.id
                resolvedPlugin = pluginHost.getNativePlugin(id: manifest.id)
            }
        }

        if resolvedPlugin == nil {
            // Search all native plugins for matching command or trigger
            for native in pluginHost.allNativePlugins() {
                if let cmdPlugin = native.plugin as? (any TitikCommandPlugin) {
                    if cmdPlugin.commands.contains(where: {
                        $0.id == target ||
                        $0.triggers.contains(target) ||
                        $0.triggers.contains("!" + target)
                    }) {
                        targetPluginId = native.manifest.id
                        resolvedPlugin = native.plugin
                        break
                    }
                }
            }
        }

        guard let plugin = resolvedPlugin else {
            return CommandExecutionResult.failure(message: "Target '\(target)' not found")
        }

        guard let commandPlugin = plugin as? (any TitikCommandPlugin) else {
            return CommandExecutionResult.failure(message: "Plugin '\(targetPluginId)' does not support command execution")
        }

        // 2. Resolve command ID
        let commandId: String
        if let explicitId = arguments["command"] ?? arguments["command_id"] ?? arguments["id"] {
            commandId = explicitId
        } else if let matchingCmd = commandPlugin.commands.first(where: { $0.id == target || $0.triggers.contains(target) }) {
            commandId = matchingCmd.id
        } else if let firstCmd = commandPlugin.commands.first {
            commandId = firstCmd.id
        } else {
            commandId = target
        }

        var flagValues: [String: FlagValue] = [:]
        for (k, v) in arguments {
            if k == "command" || k == "command_id" || k == "id" { continue }
            if ["true", "false"].contains(v.lowercased()) {
                flagValues[k] = .boolean(v.lowercased() == "true")
            } else {
                flagValues[k] = .string(v)
            }
        }

        let primaryValue = arguments["args"] ?? ""
        let invocation = PluginInvocation(
            trigger: targetPluginId,
            action: commandId,
            primaryValue: primaryValue,
            flags: flagValues,
            rawInput: rawInput.isEmpty ? target : rawInput
        )

        let context = CommandExecutionContext(
            trigger: "dispatcher",
            mode: mode,
            rawInput: rawInput
        )

        return await executeInvocationWithTimeout(
            plugin: commandPlugin,
            invocation: invocation,
            context: context,
            timeout: timeout
        )
    }

    private func executeInvocationWithTimeout(
        plugin: any TitikCommandPlugin,
        invocation: PluginInvocation,
        context: CommandExecutionContext,
        timeout: TimeInterval? = nil
    ) async -> CommandExecutionResult {
        let timeoutNanos = timeout.map { UInt64($0 * 1_000_000_000) } ?? self.timeoutNanoseconds
        let timeoutSeconds = Double(timeoutNanos) / 1_000_000_000.0
        let result: CommandExecutionResult = await withCheckedContinuation { continuation in
            let lock = NSLock()
            nonisolated(unsafe) var hasResumed = false
            nonisolated(unsafe) var cmdTask: Task<Void, Never>?
            nonisolated(unsafe) var timerTask: Task<Void, Never>?

            let resumeOnce: @Sendable (CommandExecutionResult) -> Void = { res in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: res)
            }

            cmdTask = Task {
                do {
                    let res = try await plugin.executeCommand(
                        invocation: invocation,
                        context: context
                    )
                    timerTask?.cancel()
                    resumeOnce(res)
                } catch {
                    timerTask?.cancel()
                    resumeOnce(CommandExecutionResult.failure(message: error.localizedDescription))
                }
            }

            timerTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    cmdTask?.cancel()
                    resumeOnce(CommandExecutionResult.failure(message: "Plugin runtime error: Command execution timed out after \(timeoutSeconds)s"))
                } catch {
                    // Timer cancelled because command finished first
                }
            }
        }
        return result
    }

    private func dispatchAppLaunch(target: String) async -> CommandExecutionResult {
        let expandedPath = (target as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            let success = appLauncher.launchApp(at: expandedPath)
            if success {
                return CommandExecutionResult.success(message: "Launched application at \(expandedPath)")
            } else {
                return CommandExecutionResult.failure(message: "Failed to launch application at \(expandedPath)")
            }
        }

        // Search by application name
        let apps = appLauncher.getApplications()
        let cleanTarget = target.lowercased().replacingOccurrences(of: ".app", with: "")
        if let match = apps.first(where: {
            $0.name.lowercased() == cleanTarget ||
            $0.bundleURL.deletingPathExtension().lastPathComponent.lowercased() == cleanTarget ||
            $0.path.lowercased().contains(cleanTarget)
        }) {
            let success = appLauncher.launchApp(at: match.path)
            if success {
                return CommandExecutionResult.success(message: "Launched \(match.name)")
            } else {
                return CommandExecutionResult.failure(message: "Failed to launch \(match.name)")
            }
        }

        return CommandExecutionResult.failure(message: "Application '\(target)' not found")
    }

    private func dispatchQuickLink(target: String) async -> CommandExecutionResult {
        var urlString = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.contains("://") && !urlString.hasPrefix("mailto:") && !urlString.hasPrefix("file:") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString), url.scheme != nil else {
            return CommandExecutionResult.failure(message: "Invalid URL '\(target)'")
        }

        let opened = NSWorkspace.shared.open(url)
        if !opened {
            Logger.shared.warn("NSWorkspace.open returned false for \(url.absoluteString) (may occur in headless/CI)", subsystem: "Titik.Dispatcher")
        }
        return CommandExecutionResult.success(message: "Opened quick link: \(url.absoluteString)")
    }

    private func dispatchSystemCommand(target: String) async -> CommandExecutionResult {
        let allCmds = systemCommands.getAllCommands()
        let normalizedTarget = target.lowercased().filter { $0.isLetter || $0.isNumber }
        let cleanTargetWithoutPrefix = normalizedTarget.hasPrefix("system") ? String(normalizedTarget.dropFirst(6)) : normalizedTarget

        if let match = allCmds.first(where: { cmd in
            let normId = cmd.id.lowercased().filter { $0.isLetter || $0.isNumber }
            let normIdWithoutPrefix = normId.hasPrefix("system") ? String(normId.dropFirst(6)) : normId
            let normTitle = cmd.title.lowercased().filter { $0.isLetter || $0.isNumber }

            return normId == normalizedTarget ||
                   normIdWithoutPrefix == cleanTargetWithoutPrefix ||
                   normTitle == normalizedTarget ||
                   cmd.keywords.contains(where: { $0.lowercased().filter { $0.isLetter || $0.isNumber } == cleanTargetWithoutPrefix })
        }) {
            let success = await MainActor.run {
                match.action()
            }
            return CommandExecutionResult.success(message: "Executed system command: \(match.title)")
        }

        return CommandExecutionResult.failure(message: "System command '\(target)' not found")
    }
}
