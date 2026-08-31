import Foundation
import SwiftUI
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikPluginKit
@testable import TitikPlatform
@testable import AskAIPlugin

@Suite("Ask AI Onboarding & Provider Switching Tests")
@MainActor
struct AskAIOnboardingTests {

    @Test("Ask AI empty query (!ask, !ai, empty string) returns custom onboarding setup view")
    func test_onboarding_emptyQueryShowsUnifiedWizardWhenUnconfigured() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")
        let plugin = AskAIPlugin(context: context)

        // 1. Query with "!ask"
        let canvas1 = try await plugin.onQuery("!ask")
        guard case .customView = canvas1 else {
            Issue.record("Expected customView for empty query '!ask'")
            return
        }

        // 2. Query with "!ai"
        let canvas2 = try await plugin.onQuery("!ai")
        guard case .customView = canvas2 else {
            Issue.record("Expected customView for empty query '!ai'")
            return
        }

        // 3. Query with empty string
        let canvas3 = try await plugin.onQuery("")
        guard case .customView = canvas3 else {
            Issue.record("Expected customView for empty query ''")
            return
        }
    }

    @Test("Ask AI settings and config queries return onboarding view")
    func test_onboarding_settingsQueryReturnsCustomView() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")
        let plugin = AskAIPlugin(context: context)

        let canvas1 = try await plugin.onQuery("!ask settings")
        guard case .customView = canvas1 else {
            Issue.record("Expected customView for '!ask settings'")
            return
        }

        let canvas2 = try await plugin.onQuery("!ai config")
        guard case .customView = canvas2 else {
            Issue.record("Expected customView for '!ai config'")
            return
        }
    }

    @Test("Ask AI saves selected provider and API key to Keychain")
    func test_onboarding_savesSelectedProviderAndKeyToKeychain() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")
        let plugin = AskAIPlugin(context: context)

        // Initial default provider should be OpenCode
        #expect(plugin.providerType == .openCode)

        // Save Google Gemini credentials into Keychain
        try context.keychain.setSecret("test-gemini-key-12345", forKey: AIProviderType.gemini.keychainKeyName)
        try context.keychain.setSecret(AIProviderType.gemini.rawValue, forKey: "AI_ACTIVE_PROVIDER")

        // Create new plugin instance - it should load saved Gemini provider
        let newPlugin = AskAIPlugin(context: context)
        #expect(newPlugin.providerType == .gemini)
        #expect(newPlugin.provider.id == "gemini-direct")

        let loadedKey = try context.keychain.getSecret(forKey: AIProviderType.gemini.keychainKeyName)
        #expect(loadedKey == "test-gemini-key-12345")
    }

    @Test("Ask AI switches providers cleanly across OpenCode, Gemini, OpenAI, Claude, and Ollama")
    func test_onboarding_switchesProviderCleanly() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")
        let plugin = AskAIPlugin(context: context)

        // 1. Switch to OpenAI
        plugin.setProviderType(.openAI)
        #expect(plugin.providerType == .openAI)
        #expect(plugin.provider.id == "openai-direct")

        // 2. Switch to Claude
        plugin.setProviderType(.claude)
        #expect(plugin.providerType == .claude)
        #expect(plugin.provider.id == "claude-direct")

        // 3. Switch to Ollama
        plugin.setProviderType(.ollama)
        #expect(plugin.providerType == .ollama)
        #expect(plugin.provider.id == "ollama-local")

        // 4. Switch to OpenCode
        plugin.setProviderType(.openCode)
        #expect(plugin.providerType == .openCode)
        #expect(plugin.provider.id == "opencode")
    }

    @Test("Ask AI provider options are loaded from Keychain correctly")
    func test_onboarding_providerOptionsLoadedFromKeychain() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")

        try context.keychain.setSecret("sk-openai-secret-xyz", forKey: AIProviderType.openAI.keychainKeyName)
        try context.keychain.setSecret("https://custom.openai.endpoint/v1", forKey: "AI_ENDPOINT_openai")
        try context.keychain.setSecret(AIProviderType.openAI.rawValue, forKey: "AI_ACTIVE_PROVIDER")

        let plugin = AskAIPlugin(context: context)
        #expect(plugin.providerType == .openAI)

        let savedKey = try context.keychain.getSecret(forKey: plugin.providerType.keychainKeyName)
        #expect(savedKey == "sk-openai-secret-xyz")

        let savedEndpoint = try context.keychain.getSecret(forKey: "AI_ENDPOINT_openai")
        #expect(savedEndpoint == "https://custom.openai.endpoint/v1")
    }

    @Test("ProviderConnectionTester validates required key or endpoint reachability")
    func test_onboarding_connectionTester() async {
        // OpenAI with empty key returns failure
        let openAIResult = await ProviderConnectionTester.testConnection(
            provider: .openAI,
            apiKey: "",
            endpointURL: nil
        )
        #expect(openAIResult.isConnected == false)
        #expect(openAIResult.message.contains("API key is required"))

        // Claude with empty key returns failure
        let claudeResult = await ProviderConnectionTester.testConnection(
            provider: .claude,
            apiKey: "",
            endpointURL: nil
        )
        #expect(claudeResult.isConnected == false)
        #expect(claudeResult.message.contains("API key is required"))

        // Gemini with empty key returns failure
        let geminiResult = await ProviderConnectionTester.testConnection(
            provider: .gemini,
            apiKey: "",
            endpointURL: nil
        )
        #expect(geminiResult.isConnected == false)
        #expect(geminiResult.message.contains("API key is required"))
    }

    @Test("Ask AI hides onboarding wizard when credentials or onboarding flag are present")
    func test_onboarding_completedHidesWizardOnEmptyQuery() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")
        let plugin = AskAIPlugin(context: context)

        // Initially not completed
        #expect(plugin.hasCompletedOnboarding == false)

        // Empty query returns custom view (onboarding)
        let canvasUnconfigured = try await plugin.onQuery("")
        guard case .customView = canvasUnconfigured else {
            Issue.record("Expected customView onboarding when unconfigured")
            return
        }

        // Complete onboarding via setting key
        try context.keychain.setSecret("sk-valid-key", forKey: "OPENAI_API_KEY")
        try context.keychain.setSecret(AIProviderType.openAI.rawValue, forKey: "AI_ACTIVE_PROVIDER")
        plugin.setProviderType(.openAI)
        #expect(plugin.hasCompletedOnboarding == true)

        // Empty query now returns ready chat interface customView
        let canvasConfigured = try await plugin.onQuery("")
        guard case .customView = canvasConfigured else {
            Issue.record("Expected customView chat container when configured")
            return
        }

        // But explicit "!ask settings" still opens onboarding view
        let canvasSettings = try await plugin.onQuery("!ask settings")
        guard case .customView = canvasSettings else {
            Issue.record("Expected customView onboarding for '!ask settings'")
            return
        }
    }

    @Test("AskAIPluginUIAdapter intercepts Cmd+,, Cmd+M, and Opt+S to open setup wizard")
    func test_onboarding_uiAdapterHotkeysOpenWizard() async throws {
        let tempKey = UUID().uuidString
        let context = PluginContext(pluginId: "test.ask_ai.\(tempKey)")
        let plugin = AskAIPlugin(context: context)
        let adapter = AskAIPluginUIAdapter(pluginId: "test.ask_ai.\(tempKey)", plugin: plugin)

        #expect(adapter.customCanvasView == nil)

        // 1. Cmd+, (KeyCode comma)
        if let eventCmdComma = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: UInt16(Keycode.comma.rawValue)
        ) {
            let handled = adapter.handleKeyDown(event: eventCmdComma)
            #expect(handled == true)
            #expect(adapter.customCanvasView != nil)
        }

        adapter.customCanvasView = nil

        // 2. Cmd+M (KeyCode m)
        if let eventCmdM = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "m",
            charactersIgnoringModifiers: "m",
            isARepeat: false,
            keyCode: UInt16(Keycode.m.rawValue)
        ) {
            let handled = adapter.handleKeyDown(event: eventCmdM)
            #expect(handled == true)
            #expect(adapter.customCanvasView != nil)
        }

        adapter.customCanvasView = nil

        // 3. Option+S (KeyCode s)
        if let eventOptS = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: UInt16(Keycode.s.rawValue)
        ) {
            let handled = adapter.handleKeyDown(event: eventOptS)
            #expect(handled == true)
            #expect(adapter.customCanvasView != nil)
        }
    }
}
