import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikParser
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikSearch
@testable import TitikPlatform

@Suite("Adversarial Bang Routing & Command Execution Tests")
struct AdversarialBangAndCommandTests {

    // MARK: - 1. Bang Query Fuzzing & Lexical Edge Cases

    @Test("Adversarial: Empty bangs, spaces, and repeated bangs do not crash parser or dispatcher")
    func testFuzzEmptyAndRepeatedBangs() async {
        let parser = CommandParser()
        let dispatcher = PluginCommandDispatcher.shared

        let edgeQueries = [
            "!",
            "! ",
            "!   \t  \n  ",
            "!!",
            "!!!",
            "!!!!zen",
            "!zen!",
            "!123",
            "!_zen",
            "!-open",
            "!@#$%",
            "!\u{0000}",
            "!\u{200B}zen", // Zero-width space
            "!zen🔥 https://apple.com",
            "!open\t/path/to/dir",
            "!zen\nhttps://apple.com"
        ]

        for query in edgeQueries {
            _ = parser.parse(query)
            _ = await dispatcher.dispatch(query: query, mode: .background)
        }
    }

    @Test("Adversarial: Complex flag injection and quote combinations")
    func testFuzzFlagsAndQuotes() async {
        let parser = CommandParser()
        let testCases: [(query: String, expectedName: String?)] = [
            ("!zen --new-tab \"https://example.com/search?q=hello world&lang=en\"", "zen"),
            ("!open --ide=\"Visual Studio Code\" '/Users/user/My Project'", "open"),
            ("!zen -P=Work -private=true https://slack.com", "zen"),
            ("!zen -p Work --private-window \"https://github.com\"", "zen"),
            ("!open -ide=Antigravity -p=/tmp/test", "open"),
            ("!zen ---triple-dash-flag https://apple.com", "zen"),
            ("!open -ide=\"\" /tmp", "open"),
            ("!zen \"unclosed quote https://apple.com", "zen"),
            ("!zen 'single unclosed quote", "zen"),
            ("!zen \"escaped \\\" quotes \\\" inside\"", "zen"),
            ("!open '/Users/user/Documents/Test (Special & Chars)'", "open")
        ]

        for (query, expectedName) in testCases {
            let ast = parser.parse(query)
            if case .command(let name, _, _) = ast {
                if let exp = expectedName {
                    #expect(name == exp)
                }
            } else if case .bangSuggestion(let prefix) = ast {
                if let exp = expectedName {
                    #expect(prefix.contains(exp))
                }
            }
        }
    }

    // MARK: - 2. PluginCommandDispatcher Edge Cases & Error Paths

    @Test("Adversarial: Non-existent plugin target fails gracefully with descriptive error")
    func testDispatchNonExistentPlugin() async {
        let dispatcher = PluginCommandDispatcher.shared
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "com.invalid.nonexistent_plugin_\(UUID().uuidString)"
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == false)
        #expect(result.message?.contains("not found") == true)
    }

    @Test("Adversarial: Non-conforming plugin without command interface fails gracefully")
    func testDispatchNonCommandPlugin() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.plain_plugin",
            name: "Plain Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Plugin without command support",
            entrypoint: "MockPlainPlugin",
            triggers: ["plain"]
        )
        let plainPlugin = MockPlainPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plainPlugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.test.plain_plugin"
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == false)
        #expect(result.message?.contains("does not support command execution") == true)
    }

    @Test("Adversarial: Missing required arguments returns failure from command plugins")
    func testMissingRequiredArguments() async {
        let host = PluginHost()
        let zenPlugin = ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))
        host.registerNativePlugin(zenPlugin, manifest: zenBrowserPluginManifest)

        let launcherPlugin = LauncherPlugin(context: PluginContext(pluginId: LauncherPlugin.id))
        host.registerNativePlugin(launcherPlugin, manifest: launcherPluginManifest)

        let shortcutsPlugin = ShortcutsPlugin(context: PluginContext(pluginId: ShortcutsPlugin.id))
        host.registerNativePlugin(shortcutsPlugin, manifest: shortcutsPluginManifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)

        // 1. Zen open-url with missing URL
        let zenResult = await dispatcher.dispatch(
            pluginId: ZenBrowserPlugin.id,
            commandId: "open-url",
            arguments: [:],
            mode: .background,
            rawInput: "!zen open-url"
        )
        #expect(zenResult.isSuccess == false)
        #expect(zenResult.message?.contains("Missing URL") == true)

        // 2. Zen profile command with missing profile argument
        let zenProfileResult = await dispatcher.dispatch(
            pluginId: ZenBrowserPlugin.id,
            commandId: "profile",
            arguments: [:],
            mode: .background,
            rawInput: "!zen profile"
        )
        #expect(zenProfileResult.isSuccess == false)
        #expect(zenProfileResult.message?.contains("Missing profile") == true)

        // 3. Launcher launch-app with missing app name
        let launcherAppResult = await dispatcher.dispatch(
            pluginId: LauncherPlugin.id,
            commandId: "launch-app",
            arguments: [:],
            mode: .background,
            rawInput: "!open launch-app"
        )
        #expect(launcherAppResult.isSuccess == false)
        #expect(launcherAppResult.message?.contains("Missing application name") == true)

        // 4. Launcher open-project with missing path via bang invocation
        let launcherProjBangResult = await dispatcher.dispatch(
            query: "!open open-project",
            mode: .background
        )
        #expect(launcherProjBangResult.isSuccess == false)
        #expect(launcherProjBangResult.message?.contains("Missing project path") == true)

        // 5. Shortcuts trigger-shortcut with missing identifier
        let shortcutsResult = await dispatcher.dispatch(
            pluginId: ShortcutsPlugin.id,
            commandId: "trigger-shortcut",
            arguments: [:],
            mode: .background,
            rawInput: "!shortcut trigger"
        )
        #expect(shortcutsResult.isSuccess == false)
        #expect(shortcutsResult.message?.contains("Missing shortcut identifier") == true)
    }

    @Test("Adversarial: Throwing plugin commands are caught safely without crashing")
    func testThrowingPluginCommandHandled() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.throwing_plugin",
            name: "Throwing Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Plugin that throws errors",
            entrypoint: "MockThrowingPlugin",
            triggers: ["throw"]
        )
        let plugin = MockThrowingPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.test.throwing_plugin",
            arguments: ["command": "fail"]
        )

        let result = await dispatcher.dispatch(action: action, mode: .background)
        #expect(result.isSuccess == false)
        #expect(result.message?.contains("Intentional simulated error") == true)
    }

    @Test("Adversarial: Command execution timeout triggers and cancels hanging task")
    func testCommandExecutionTimeout() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.hanging_plugin",
            name: "Hanging Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Plugin that hangs indefinitely",
            entrypoint: "MockHangingPlugin",
            triggers: ["hang"]
        )
        let plugin = MockHangingPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host, timeoutNanoseconds: 500_000_000)
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.test.hanging_plugin",
            arguments: ["command": "sleepForever"]
        )

        let startTime = Date()
        let result = await dispatcher.dispatch(action: action, mode: .background)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(result.isSuccess == false)
        #expect(result.message?.contains("timed out") == true)
        #expect(elapsed >= 0.3 && elapsed <= 5.0)
    }

    // MARK: - 3. Real-World Workflows & Integration

    @Test("Adversarial: Zen Browser launch arguments and URL variations")
    func testZenBrowserLaunchArgumentsRobustness() async {
        let plugin = ZenBrowserPlugin(context: PluginContext(pluginId: ZenBrowserPlugin.id))

        // 1. Basic URL
        let flags1 = plugin.buildCLIFlags(id: "open-url", arguments: ["url": "https://apple.com"])
        #expect(flags1 == ["https://apple.com"])

        // 2. Profile + New Tab + URL
        let flags2 = plugin.buildCLIFlags(id: "new-tab", arguments: [
            "profile": "Work Profile",
            "url": "https://slack.com"
        ])
        #expect(flags2 == ["-P", "Work Profile", "-new-tab", "https://slack.com"])

        // 3. Private Window with Profile
        let flags3 = plugin.buildCLIFlags(id: "new-window", arguments: [
            "profile": "Personal",
            "private": "true",
            "url": "https://duckduckgo.com"
        ])
        #expect(flags3 == ["-P", "Personal", "-private-window", "https://duckduckgo.com"])

        // 4. Profile only command
        let flags4 = plugin.buildCLIFlags(id: "profile", arguments: ["profile": "Development"])
        #expect(flags4 == ["-P", "Development"])
    }

    @Test("Adversarial: App and Project Launcher path resolution and IDE detection")
    func testLauncherPluginPathResolution() async throws {
        let launcher = LauncherPlugin(context: PluginContext(pluginId: LauncherPlugin.id))

        // 1. Test non-existent IDE resolution returns nil safely
        let nonExistentURL = launcher.resolveIDEAppURL(ide: "NonExistentIDE_\(UUID().uuidString)")
        #expect(nonExistentURL == nil)

        // 2. Open Project with tilde path
        let ctx = CommandExecutionContext(trigger: "test", mode: .background, rawInput: "!open ~/test-workspace")
        let result = try await launcher.executeCommand(
            id: "open-project",
            arguments: ["path": "~/test-workspace", "ide": "Antigravity"],
            context: ctx
        )
        #expect(result.isSuccess == true)
        #expect(result.outputPayload?["ide"] == "Antigravity")
        #expect(result.outputPayload?["path"]?.hasPrefix("/") == true)
        #expect(result.outputPayload?["path"]?.hasSuffix("test-workspace") == true)
    }

    @Test("Adversarial: Shortcuts Inspector listing, filtering, and conflict detection")
    func testShortcutsInspectorConflictDetection() async throws {
        let registry = KeymapRegistry()
        let combo1 = try #require(KeyCombination(string: "cmd+k"))
        let combo2 = try #require(KeyCombination(string: "cmd+k"))

        try registry.register(combination: combo1, identifier: "shortcut.one") {}

        // KeymapRegistry detects and rejects duplicate combination bindings
        #expect(throws: KeymapError.self) {
            try registry.register(combination: combo2, identifier: "shortcut.two") {}
        }

        let plugin = ShortcutsPlugin(
            context: PluginContext(pluginId: ShortcutsPlugin.id),
            keymapRegistry: registry
        )

        // 1. List shortcuts
        let listResult = try await plugin.executeCommand(
            id: "list-shortcuts",
            arguments: [:],
            context: CommandExecutionContext(trigger: "test", mode: .palette, rawInput: "!shortcut")
        )
        #expect(listResult.isSuccess == true)
        #expect(listResult.outputPayload?["count"] == "1")

        // 2. Inspect conflicts on clean registry returns 0 conflicts
        let conflictResult = try await plugin.executeCommand(
            id: "inspect-conflicts",
            arguments: [:],
            context: CommandExecutionContext(trigger: "test", mode: .palette, rawInput: "!shortcut conflicts")
        )
        #expect(conflictResult.isSuccess == true)
        #expect(conflictResult.outputPayload?["conflicts"] == "0")
    }

    @Test("Adversarial: High concurrency dispatcher stress under 50 simultaneous tasks")
    func testHighConcurrencyDispatcherStress() async {
        let host = PluginHost()
        let manifest = PluginManifest(
            id: "titik.test.stress",
            name: "Stress Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Stress test plugin",
            entrypoint: "MockStressCommandPlugin",
            triggers: ["stress"]
        )
        let plugin = MockStressCommandPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let dispatcher = PluginCommandDispatcher(pluginHost: host)

        await withTaskGroup(of: CommandExecutionResult.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let action = ShortcutActionConfig(
                        type: .pluginCommand,
                        target: "titik.test.stress",
                        arguments: ["command": "echo", "seq": "\(i)"]
                    )
                    return await dispatcher.dispatch(action: action, mode: .background)
                }
            }

            var successCount = 0
            for await res in group {
                if res.isSuccess {
                    successCount += 1
                }
            }
            #expect(successCount == 50)
        }
    }
}

// MARK: - Mock Support Plugins for Adversarial Suite

private final class MockPlainPlugin: TitikPlugin, @unchecked Sendable {
    static let id = "titik.test.plain_plugin"
    static let name = "Plain Plugin"
    static let version = "1.0.0"

    init(context: PluginContext) {}
    func onShutdown() {}
}

private final class MockThrowingPlugin: TitikCommandPlugin, @unchecked Sendable {
    static let id = "titik.test.throwing_plugin"
    static let name = "Throwing Plugin"
    static let version = "1.0.0"

    var commands: [PluginCommandDefinition] {
        [PluginCommandDefinition(id: "fail", name: "Fail", description: "Throws error", triggers: ["fail"])]
    }

    init(context: PluginContext) {}

    func executeCommand(id: String, arguments: [String: String], context: CommandExecutionContext) async throws -> CommandExecutionResult {
        throw NSError(domain: "TitikTestError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Intentional simulated error"])
    }
}

private final class MockHangingPlugin: TitikCommandPlugin, @unchecked Sendable {
    static let id = "titik.test.hanging_plugin"
    static let name = "Hanging Plugin"
    static let version = "1.0.0"

    var commands: [PluginCommandDefinition] {
        [PluginCommandDefinition(id: "sleepForever", name: "Sleep", description: "Hangs", triggers: ["sleep"])]
    }

    init(context: PluginContext) {}

    func executeCommand(id: String, arguments: [String: String], context: CommandExecutionContext) async throws -> CommandExecutionResult {
        // Sleep longer than dispatcher timeout (10s)
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return CommandExecutionResult.success(message: "Done sleeping")
    }
}

private final class MockStressCommandPlugin: TitikCommandPlugin, @unchecked Sendable {
    static let id = "titik.test.stress"
    static let name = "Stress Plugin"
    static let version = "1.0.0"

    var commands: [PluginCommandDefinition] {
        [PluginCommandDefinition(id: "echo", name: "Echo", description: "Echos input", triggers: ["echo"])]
    }

    init(context: PluginContext) {}

    func executeCommand(id: String, arguments: [String: String], context: CommandExecutionContext) async throws -> CommandExecutionResult {
        let seq = arguments["seq"] ?? "0"
        return CommandExecutionResult.success(message: "Echo seq: \(seq)", outputPayload: ["seq": seq])
    }
}
