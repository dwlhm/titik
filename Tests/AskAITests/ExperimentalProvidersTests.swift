import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

@Suite("Experimental / Unofficial Providers Tests")
struct ExperimentalProvidersTests {

    @Test("All experimental providers are explicitly flagged as unofficial and untested")
    func test_experimentalProviders_flaggedAsUntested() {
        let providers: [AIProvider] = [
            GeminiProvider(),
            OpenAIProvider(),
            ClaudeProvider(),
            OllamaProvider()
        ]

        for provider in providers {
            #expect(provider.isOfficial == false, "\(provider.displayName) must not be marked as official")
            #expect(provider.isUntested == true, "\(provider.displayName) must be explicitly flagged as untested")
            #expect(provider.displayName.contains("Unofficial/Untested"), "\(provider.displayName) name must denote unofficial status")
        }
    }

    @Test("OpenAI direct adapter validates required API key")
    func test_openAIProvider_requiresKey() async {
        let provider = OpenAIProvider()
        let options = ProviderOptions(apiKey: nil)

        do {
            _ = try await provider.streamChat(messages: [ChatMessage(role: .user, content: "hi")], options: options)
            Issue.record("Expected unauthorized error for OpenAI missing API key")
        } catch let error as PluginError {
            if case .unauthorized(let msg) = error {
                #expect(msg.contains("API key is required"))
            } else {
                Issue.record("Unexpected PluginError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Claude direct adapter validates required API key")
    func test_claudeProvider_requiresKey() async {
        let provider = ClaudeProvider()
        let options = ProviderOptions(apiKey: "")

        do {
            _ = try await provider.streamChat(messages: [ChatMessage(role: .user, content: "hi")], options: options)
            Issue.record("Expected unauthorized error for Claude missing API key")
        } catch let error as PluginError {
            if case .unauthorized(let msg) = error {
                #expect(msg.contains("API key is required"))
            } else {
                Issue.record("Unexpected PluginError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Gemini direct adapter validates required API key")
    func test_geminiProvider_requiresKey() async {
        let provider = GeminiProvider()
        let options = ProviderOptions(apiKey: "")

        do {
            _ = try await provider.streamChat(messages: [ChatMessage(role: .user, content: "hi")], options: options)
            Issue.record("Expected unauthorized error for Gemini missing API key")
        } catch let error as PluginError {
            if case .unauthorized(let msg) = error {
                #expect(msg.contains("API key is required"))
            } else {
                Issue.record("Unexpected PluginError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Gemini direct adapter validates ID and structure")
    func test_geminiProvider_properties() {
        let provider = GeminiProvider()
        #expect(provider.id == "gemini-direct")
    }

    @Test("Ollama local adapter validates ID and structure")
    func test_ollamaProvider_properties() {
        let provider = OllamaProvider()
        #expect(provider.id == "ollama-local")
    }
}
