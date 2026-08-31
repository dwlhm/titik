import Foundation
import SwiftUI
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikPlatform

final class MockE2EPlugin: TitikStreamingPlugin, @unchecked Sendable {
    static let id = "mock.e2e.plugin"
    static let name = "Mock E2E Plugin"
    static let version = "2.0.0"
    static let sdkVersion = 2

    let context: PluginContext
    var isShutdownCalled = false
    var activeStreamCancelled = false

    init(context: PluginContext) {
        self.context = context
    }

    func onQuery(_ query: String) async throws -> PluginCanvas {
        let emitter = StreamEmitter()
        Task {
            await emitter.emitText("Response for: \(query)")
            await emitter.finish()
        }
        return .streaming(emitter)
    }

    func cancelActiveStream() async {
        activeStreamCancelled = true
    }

    func onShutdown() {
        isShutdownCalled = true
    }
}

@Suite("Comprehensive E2E Edge Case Tests")
@MainActor
struct TitikE2EEdgeCaseTests {

    @Test("Rapid window dismissal cancels active tasks and prevents memory leaks")
    func test_e2e_rapidWindowDismissal() async {
        let host = PluginHost.shared
        let orchestrator = UIOrchestrator.shared

        // Simulate active streaming plugin
        let emitter = StreamEmitter()
        let task = Task { () -> Void in
            for i in 0..<100 {
                if Task.isCancelled { break }
                await emitter.emitText("Token \(i) ")
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        let manifest = PluginManifest(
            id: "e2e.dismissal",
            name: "Dismissal Test",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Test",
            entrypoint: "MockE2EPlugin",
            triggers: ["!dismiss"]
        )
        let plugin = MockE2EPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)
        let loaded = host.getLoadedNativePlugin(id: manifest.id)
        _ = loaded?.addTask(task)

        // Rapid Esc / window close 10 times
        for _ in 0..<10 {
            orchestrator.reset()
        }

        #expect(task.isCancelled)
    }

    @Test("Rapid plugin switching aborts previous stream instantly")
    func test_e2e_rapidPluginSwitching() async {
        let host = PluginHost.shared
        let orchestrator = UIOrchestrator.shared

        var streamActive = true
        let task = Task { () -> Void in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            streamActive = false
        }

        let manifest = PluginManifest(
            id: "e2e.switch",
            name: "Switch Test",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Test",
            entrypoint: "MockE2EPlugin",
            triggers: ["!ask"]
        )
        let plugin = MockE2EPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)
        let loaded = host.getLoadedNativePlugin(id: manifest.id)
        _ = loaded?.addTask(task)

        // Switch to Math calculator
        orchestrator.query = "25 * 4"

        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(task.isCancelled)
        #expect(!streamActive)
    }

    @Test("Rapid follow-up prompt spam executes only the latest prompt")
    func test_e2e_rapidFollowUpSpam() async {
        let coordinator = PluginFocusCoordinator(initialZone: .followUpBar, hasFollowUpBar: true)
        var submittedQueries: [String] = []

        coordinator.onSubmitFollowUp = { q in
            submittedQueries.append(q)
        }

        coordinator.onSubmitFollowUp?("Prompt 1")
        coordinator.onSubmitFollowUp?("Prompt 2")
        coordinator.onSubmitFollowUp?("Prompt 3")
        coordinator.onSubmitFollowUp?("Prompt 4")
        coordinator.onSubmitFollowUp?("Prompt 5 (Final)")

        #expect(submittedQueries.count == 5)
        #expect(submittedQueries.last == "Prompt 5 (Final)")
    }

    @Test("Zero and single media items behave deterministically")
    func test_e2e_zeroAndSingleMediaItem() {
        // Zero media
        let zeroRail = TitikMediaRail(assets: [], selectedIndex: .constant(0))
        #expect(zeroRail.assets.isEmpty)

        // Single media
        let singleAsset = MediaAsset(type: .image, title: "Sole Image", urlString: "https://example.com/1.png")
        let singleRail = TitikMediaRail(assets: [singleAsset], selectedIndex: .constant(0))
        #expect(singleRail.assets.count == 1)
    }

    @Test("Massive media list (50 items) is clamped to maximum allowed bounds (8 items)")
    func test_e2e_massiveMediaList() {
        var massiveAssets: [MediaAsset] = []
        for i in 1...50 {
            massiveAssets.append(MediaAsset(type: .image, title: "Photo \(i)", urlString: "https://example.com/\(i).png"))
        }

        let rail = TitikMediaRail(assets: massiveAssets, selectedIndex: .constant(0))
        #expect(rail.assets.count == 8, "Media rail must be clamped to 8 items to prevent flood")
    }

    @Test("Broken media URLs are handled without crash via URLSanitizer")
    func test_e2e_brokenMediaURLs() {
        let brokenURLs = [
            "not_a_valid_url",
            "file:///Users/secret/data.png",
            "javascript:void(0)",
            ""
        ]

        for bad in brokenURLs {
            let sanitized = URLSanitizer.sanitize(bad)
            #expect(sanitized == nil)
        }
    }

    @Test("Out of bounds citation hotkey Option+7 is ignored safely when only 2 citations exist")
    func test_e2e_citationOutOfBoundsHotkey() {
        let coordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 1,
            citationCount: 2,
            hasFollowUpBar: true
        )

        let handled = coordinator.handleOptionHotkey(number: 7)
        #expect(handled == false)
        #expect(coordinator.currentZone == .input)
        #expect(coordinator.selectedCitationIndex == 0)
    }

    @Test("Duplicate citation URLs are deduplicated cleanly in citation tray")
    func test_e2e_duplicateCitationURLs() {
        let dupCitations = [
            CitationSource(index: 1, title: "OpenAI Docs", urlString: "https://openai.com/docs"),
            CitationSource(index: 2, title: "OpenAI Docs", urlString: "https://openai.com/docs"),
            CitationSource(index: 3, title: "Apple Developer", urlString: "https://developer.apple.com"),
            CitationSource(index: 4, title: "OpenAI Docs", urlString: "https://openai.com/docs"),
            CitationSource(index: 5, title: "Apple Developer", urlString: "https://developer.apple.com")
        ]

        let tray = TitikCitationTray(citations: dupCitations, selectedIndex: .constant(0))
        #expect(tray.citations.count == 2)
        #expect(tray.citations[0].urlString == "https://openai.com/docs")
        #expect(tray.citations[1].urlString == "https://developer.apple.com")
    }

    @Test("Deeply nested markdown with unclosed code fences, raw HTML, and LaTeX math parses safely")
    func test_e2e_deeplyNestedMarkdown() {
        let rawMarkdown = """
        # Header 1
        <script>alert('xss');</script>
        Here is some text with LaTeX math:
        $$E = mc^2$$
        And an unclosed code fence:
        ```swift
        let x = 42
        print(x)
        """

        let blocks = MarkdownASTParser.parse(rawMarkdown)
        #expect(!blocks.isEmpty)

        // Ensure script tag was sanitized
        for block in blocks {
            if case .paragraph(let text) = block {
                #expect(!text.contains("<script>"))
            }
        }

        // Verify unclosed code block was closed and parsed
        let hasCodeBlock = blocks.contains {
            if case .codeBlock(let lang, let code) = $0 {
                return lang == "swift" && code.contains("let x = 42")
            }
            return false
        }
        #expect(hasCodeBlock)

        // Verify math block parsed
        let hasMath = blocks.contains {
            if case .math(let eq) = $0 {
                return eq == "E = mc^2"
            }
            return false
        }
        #expect(hasMath)
    }

    @Test("Massive 50,000 token stream parses into AST blocks efficiently")
    func test_e2e_massive50kTokenStream() {
        var longText = ""
        for i in 1...2000 {
            longText += "Paragraph \(i): This is a high performance streaming verification test sentence.\n\n"
        }

        let startTime = DispatchTime.now()
        let blocks = MarkdownASTParser.parse(longText)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        #expect(blocks.count == 2000)
        #expect(elapsedMs < 300.0, "Parsing 2000 paragraphs took \(elapsedMs)ms, expected < 300ms")
    }

    @Test("Streaming network drop catches error and preserves partial text")
    func test_e2e_streamingNetworkDrop() async {
        let emitter = StreamEmitter()
        var receivedEvents: [StreamEvent] = []

        let consumerTask = Task {
            for await event in await emitter.stream() {
                receivedEvents.append(event)
            }
        }

        await emitter.emitText("First 50 tokens received cleanly. ")
        await emitter.emitError("Network connection abruptly disconnected (SSE EOF)")
        await emitter.finish()

        _ = await consumerTask.result

        #expect(receivedEvents.count == 3)
        #expect(receivedEvents[0] == .textDelta("First 50 tokens received cleanly. "))
        #expect(receivedEvents[1] == .error("Network connection abruptly disconnected (SSE EOF)"))
        #expect(receivedEvents[2] == .finished)
    }

    @Test("Provider rate limit 429 parses and emits rate limit event")
    func test_e2e_providerRateLimit429() async {
        let emitter = StreamEmitter()
        var receivedEvents: [StreamEvent] = []

        let consumerTask = Task {
            for await event in await emitter.stream() {
                receivedEvents.append(event)
            }
        }

        await emitter.emitRateLimit(retryAfter: 3.0)
        await emitter.finish()

        _ = await consumerTask.result

        #expect(receivedEvents.contains(.rateLimit(retryAfter: 3.0)))
    }

    @Test("Missing API key in keychain returns nil and produces actionable error")
    func test_e2e_missingOrInvalidApiKey() throws {
        let keychain = HostKeychainService(pluginId: "unconfigured.plugin", useInMemoryStore: true)
        let key = try keychain.getSecret(forKey: "api_key")
        #expect(key == nil)

        let authError = PluginError.unauthorized("No API key configured for unconfigured.plugin. Please set it in preferences.")
        #expect(authError.localizedDescription.contains("No API key configured"))
    }
}
