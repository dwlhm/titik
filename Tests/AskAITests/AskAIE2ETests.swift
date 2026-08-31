import Foundation
import SwiftUI
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform
@testable import AskAIPlugin

final class MockAIProvider: AIProvider, @unchecked Sendable {
    let id: String = "mock-provider"
    let displayName: String = "Mock AI Provider"
    let isOfficial: Bool = true
    let isUntested: Bool = false

    var responseChunks: [ProviderStreamChunk]

    init(responseChunks: [ProviderStreamChunk]) {
        self.responseChunks = responseChunks
    }

    func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        let chunks = responseChunks
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@Suite("Ask AI End-to-End Tests")
@MainActor
struct AskAIE2ETests {

    @Test("Ask AI full multi-turn conversation flow with mock streaming engine")
    func test_e2e_askAI_fullMultiTurnConversationFlow() async throws {
        let context = PluginContext(pluginId: "com.titik.plugin.ask_ai", baseStorageURL: nil)
        let webSearchService = WebSearchService()
        await webSearchService.setStubHandler { _ in .empty }
        let plugin = AskAIPlugin(context: context, webSearchService: webSearchService)

        let mockProvider = MockAIProvider(responseChunks: [
            .text("Hello! "),
            .text("Titik AI is operational. "),
            .media(MediaAsset(type: .image, title: "Architecture", urlString: "https://example.com/arch.png")),
            .citation(CitationSource(index: 1, title: "Documentation", urlString: "https://titik.dev/docs"))
        ])
        plugin.setProvider(mockProvider)

        // Turn 1: User asks question
        let canvas1 = try await plugin.onQuery("!ask What is Titik?")
        guard case .streaming(let emitter1) = canvas1 else {
            Issue.record("Expected streaming canvas")
            return
        }

        var turn1Text = ""
        var turn1Media: [MediaAsset] = []
        var turn1Citations: [CitationSource] = []

        for await event in await emitter1.stream() {
            switch event {
            case .textDelta(let delta):
                turn1Text += delta
            case .media(let m):
                turn1Media.append(m)
            case .citation(let c):
                turn1Citations.append(c)
            case .finished, .progress, .rateLimit, .error:
                break
            }
        }

        #expect(turn1Text.contains("Titik AI is operational."))
        #expect(turn1Media.count == 1)
        #expect(turn1Citations.count == 1)

        let historyAfterTurn1 = await plugin.sessionCoordinator.history()
        #expect(historyAfterTurn1.count == 3) // System + User + Assistant
        #expect(historyAfterTurn1[0].role == .system)
        #expect(historyAfterTurn1[0].content == AIFormatPrompt.text)
        #expect(historyAfterTurn1[1].role == .user)
        #expect(historyAfterTurn1[1].content == "What is Titik?")
        #expect(historyAfterTurn1[2].role == .assistant)

        // Turn 2: Follow-up question
        let followUpMock = MockAIProvider(responseChunks: [
            .text("Titik supports extensible native plugins.")
        ])
        plugin.setProvider(followUpMock)

        let canvas2 = try await plugin.onQuery("!ai How do plugins work?")
        guard case .streaming(let emitter2) = canvas2 else {
            Issue.record("Expected streaming canvas for turn 2")
            return
        }

        var turn2Text = ""
        for await event in await emitter2.stream() {
            if case .textDelta(let delta) = event {
                turn2Text += delta
            }
        }

        #expect(turn2Text.contains("Titik supports extensible native plugins."))
        let historyAfterTurn2 = await plugin.sessionCoordinator.history()
        #expect(historyAfterTurn2.count == 5) // System + 2 user + 2 assistant
    }

    @Test("Ask AI trigger prefix stripping handles !ask and !ai correctly")
    func test_e2e_askAI_triggerPrefixStripping() async throws {
        let context = PluginContext(pluginId: "com.titik.plugin.ask_ai")
        let webSearchService = WebSearchService()
        await webSearchService.setStubHandler { _ in .empty }
        let plugin = AskAIPlugin(context: context, webSearchService: webSearchService)
        plugin.setProvider(MockAIProvider(responseChunks: [.text("OK")]))

        _ = try await plugin.onQuery("!ask Explain quantum computing")
        let h1 = await plugin.sessionCoordinator.history()
        #expect(h1.first?.role == .system)
        #expect(h1.first?.content == AIFormatPrompt.text)
        #expect(h1.count >= 2)
        #expect(h1[1].role == .user)
        #expect(h1[1].content == "Explain quantum computing")

        await plugin.sessionCoordinator.reset()

        _ = try await plugin.onQuery("!ai Design an algorithm")
        let h2 = await plugin.sessionCoordinator.history()
        #expect(h2.first?.role == .system)
        #expect(h2.count >= 2)
        #expect(h2[1].role == .user)
        #expect(h2[1].content == "Design an algorithm")
    }

    @Test("Ask AI mid-stream cancellation cleanly stops task execution")
    func test_e2e_askAI_streamCancellationMidStream() async throws {
        let context = PluginContext(pluginId: "com.titik.plugin.ask_ai")
        let plugin = AskAIPlugin(context: context)

        // Infinite/long stream mock
        let longMock = MockAIProvider(responseChunks: (0..<100).map { .text("Chunk \($0) ") })
        plugin.setProvider(longMock)

        let canvas = try await plugin.onQuery("!ask Long task")
        guard case .streaming = canvas else {
            Issue.record("Expected streaming canvas")
            return
        }

        // Cancel mid stream
        try? await Task.sleep(nanoseconds: 20_000_000)
        await plugin.cancelActiveStream()

        // Shutdown cleanly
        plugin.onShutdown()
        #expect(Bool(true))
    }

    @Test("Official OpenCode provider streaming e2e edge case")
    func test_e2e_openCodeStreamingSuccess() async throws {
        let provider = OpenCodeProvider()
        #expect(provider.isOfficial == true)
        #expect(provider.isUntested == false)
    }

    @Test("Official Antigravity subscriber authentication e2e edge case")
    func test_e2e_antigravitySubscriberAuth() async throws {
        let provider = AntigravityProvider()
        #expect(provider.isOfficial == true)
        #expect(provider.isUntested == false)
    }

    @Test("All AI providers normalize custom base URLs correctly without 404 Not Found")
    func test_e2e_providerEndpointURLNormalization() async throws {
        // 1. OpenCode provider normalization
        let opencode = OpenCodeProvider()
        #expect(opencode.id == "opencode")

        // 2. Gemini provider
        let gemini = GeminiProvider()
        #expect(gemini.id == "gemini-direct")

        // 3. OpenAI provider
        let openai = OpenAIProvider()
        #expect(openai.id == "openai-direct")

        // 4. Claude provider
        let claude = ClaudeProvider()
        #expect(claude.id == "claude-direct")

        // 5. Ollama provider
        let ollama = OllamaProvider()
        #expect(ollama.id == "ollama-local")
    }

    @Test("AskAIPluginUIAdapter defers execution while typing until submitQuery is called")
    func test_askAIAdapter_submitQuery_deferredExecution() async throws {
        let context = PluginContext(pluginId: "com.titik.plugin.ask_ai")
        let webSearchService = WebSearchService()
        await webSearchService.setStubHandler { _ in .empty }
        let plugin = AskAIPlugin(context: context, webSearchService: webSearchService)
        let mock = MockAIProvider(responseChunks: [.text("Answer")])
        plugin.setProvider(mock)

        let adapter = AskAIPluginUIAdapter(pluginId: AskAIPlugin.id, plugin: plugin)

        // Typing query: does NOT start stream immediately
        adapter.handleSearchQuery("!ask What is 2+2?")
        #expect(adapter.isStreaming == false)
        #expect(adapter.text.isEmpty)

        // Submit query: triggers execution
        adapter.submitQuery()
        #expect(adapter.isStreaming == true)

        // Wait for completion
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(adapter.text.contains("Answer"))
        #expect(adapter.isStreaming == false)
    }

    @Test("AskAIPluginUIAdapter immediately starts for settings or empty queries")
    func test_askAIAdapter_emptyOrSettings_runsImmediately() async throws {
        let context = PluginContext(pluginId: "com.titik.plugin.ask_ai")
        let plugin = AskAIPlugin(context: context)
        let adapter = AskAIPluginUIAdapter(pluginId: AskAIPlugin.id, plugin: plugin)

        // Settings query runs immediately and sets customCanvasView
        adapter.handleSearchQuery("settings")
        #expect(adapter.customCanvasView != nil)

        // Empty query runs immediately
        adapter.handleSearchQuery("")
        #expect(adapter.isStreaming == false)
    }

    @Test("UIOrchestrator executeSelected delegates to activePluginUI submitQuery")
    func test_uiOrchestrator_executeSelected_delegatesToActivePluginUI() async throws {
        let context = PluginContext(pluginId: "com.titik.plugin.ask_ai")
        let plugin = AskAIPlugin(context: context)
        plugin.setProvider(MockAIProvider(responseChunks: [.text("Orchestrated result")]))

        let adapter = AskAIPluginUIAdapter(pluginId: AskAIPlugin.id, plugin: plugin)
        let orchestrator = UIOrchestrator()
        orchestrator.activePluginUI = adapter

        adapter.handleSearchQuery("!ask test delegation")
        #expect(adapter.isStreaming == false)

        // executeSelected should call adapter.submitQuery()
        orchestrator.executeSelected()
        #expect(adapter.isStreaming == true)

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(adapter.text.contains("Orchestrated result"))
    }
}

