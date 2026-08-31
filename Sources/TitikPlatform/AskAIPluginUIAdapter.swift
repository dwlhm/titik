import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikUI
import TitikPluginKit
import AskAIPlugin

@MainActor
public final class AskAIPluginUIAdapter: ObservableObject, PluginUIRepresentable {
    public let pluginId: String
    public let streamingPlugin: any TitikStreamingPlugin
    public let focusCoordinator: PluginFocusCoordinator

    @Published public var customCanvasView: AnyView? = nil
    @Published public var text: String = ""
    @Published public var mediaAssets: [MediaAsset] = []
    @Published public var citations: [CitationSource] = []
    @Published public var isStreaming: Bool = false
    @Published public var rateLimitRetryAfter: TimeInterval? = nil

    private var activeStreamTask: Task<Void, Never>?
    private var lastQuery: String = ""
    private var pendingQuery: String = ""

    public init(pluginId: String = AskAIPlugin.id, plugin: any TitikStreamingPlugin) {
        self.pluginId = pluginId
        self.streamingPlugin = plugin
        self.focusCoordinator = PluginFocusCoordinator(
            initialZone: .input,
            mediaCount: 0,
            citationCount: 0,
            hasFollowUpBar: true
        )

        setupFocusCallbacks()
        setupNotificationObservers()
    }

    private func setupFocusCallbacks() {
        focusCoordinator.onCitationActivated = { [weak self] index in
            guard let self = self, index >= 0 && index < self.citations.count else { return }
            let cite = self.citations[index]
            if let url = URLSanitizer.sanitize(cite.urlString) {
                NSWorkspace.shared.open(url)
            }
        }

        focusCoordinator.onMediaActivated = { [weak self] index in
            guard let self = self, index >= 0 && index < self.mediaAssets.count else { return }
            let asset = self.mediaAssets[index]
            if let urlStr = asset.urlString, let url = URLSanitizer.sanitize(urlStr) {
                NSWorkspace.shared.open(url)
            }
        }

        focusCoordinator.onSubmitFollowUp = { [weak self] query in
            self?.submitFollowUp(query)
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .askAISelectPrompt,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let prompt = notification.object as? String
            Task { @MainActor [weak self] in
                if let prompt = prompt {
                    self?.startQuery("!ask \(prompt)")
                }
            }
        }
    }

    public var customView: AnyView {
        AnyView(
            AskAIAdapterContainerView(adapter: self)
        )
    }

    public func handleSearchQuery(_ query: String) {
        if query == lastQuery { return }
        lastQuery = query

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || query == "settings" || query == "config" {
            pendingQuery = ""
            startQuery(query)
        } else {
            pendingQuery = query
        }
    }

    public func submitQuery() {
        if !pendingQuery.isEmpty {
            let queryToSubmit = pendingQuery
            startQuery(queryToSubmit)
        }
    }

    public func submitFollowUp(_ followUp: String) {
        let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        startQuery(trimmed)
    }

    public func openSetupWizard() {
        cancelActiveStream()
        pendingQuery = ""
        let context: PluginContext
        let currentType: AIProviderType
        if let askAI = streamingPlugin as? AskAIPlugin {
            context = askAI.context
            currentType = askAI.providerType
        } else {
            context = PluginContext(pluginId: pluginId)
            let saved = (try? context.keychain.getSecret(forKey: "AI_ACTIVE_PROVIDER")) ?? AIProviderType.openCode.rawValue
            currentType = AIProviderType(rawValue: saved) ?? .openCode
        }

        let onboardingView = AskAIOnboardingView(
            context: context,
            selectedProvider: currentType,
            onSelectPrompt: { [weak self] prompt in
                Task { @MainActor [weak self] in
                    self?.startQuery("!ask \(prompt)")
                }
            },
            onSaveSuccess: { [weak self] newType in
                Task { @MainActor [weak self] in
                    if let askAI = self?.streamingPlugin as? AskAIPlugin {
                        askAI.setProviderType(newType)
                    }
                    self?.customCanvasView = nil
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.customCanvasView = nil
                }
            }
        )
        self.customCanvasView = AnyView(onboardingView)
        self.isStreaming = false
    }

    private func startQuery(_ rawQuery: String) {
        cancelActiveStream()

        self.customCanvasView = nil
        self.isStreaming = true
        self.text = ""
        self.mediaAssets = []
        self.citations = []
        self.rateLimitRetryAfter = nil
        self.focusCoordinator.mediaCount = 0
        self.focusCoordinator.citationCount = 0

        activeStreamTask = Task { [weak self, streamingPlugin] in
            do {
                let canvas = try await streamingPlugin.onQuery(rawQuery)
                if case .customView(let view) = canvas {
                    await MainActor.run {
                        guard let self = self else { return }
                        self.customCanvasView = view
                        self.isStreaming = false
                    }
                    return
                }

                if case .streaming(let emitter) = canvas {
                    for await event in await emitter.stream() {
                        if Task.isCancelled { break }
                        await MainActor.run {
                            guard let self = self else { return }
                            switch event {
                            case .textDelta(let delta):
                                self.text += delta
                            case .media(let media):
                                self.mediaAssets.append(media)
                                self.focusCoordinator.mediaCount = self.mediaAssets.count
                            case .citation(let citation):
                                self.citations.append(citation)
                                self.focusCoordinator.citationCount = self.citations.count
                            case .rateLimit(let retry):
                                self.rateLimitRetryAfter = retry
                            case .error(let err):
                                self.text = "Error: \(err)"
                                self.isStreaming = false
                            case .finished:
                                self.isStreaming = false
                            case .progress:
                                break
                            }
                        }
                    }
                    await MainActor.run {
                        self?.isStreaming = false
                    }
                } else if case .empty = canvas {
                    await MainActor.run {
                        self?.isStreaming = false
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self?.text = "Error: \(error.localizedDescription)"
                        self?.isStreaming = false
                    }
                }
            }
        }
    }

    public func cancelActiveStream() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isStreaming = false
        Task { [streamingPlugin] in
            await streamingPlugin.cancelActiveStream()
        }
    }

    public func handleKeyDown(event: NSEvent) -> Bool {
        let flags = KeyModifier.from(nsFlags: event.modifierFlags)
        let isCommand = flags.contains(.command)
        let isOption = flags.contains(.option)
        let code = UInt32(event.keyCode)

        if (isCommand && (code == Keycode.comma.rawValue || code == Keycode.m.rawValue)) ||
           (isOption && code == Keycode.s.rawValue) {
            openSetupWizard()
            return true
        }

        return focusCoordinator.handleKeyDown(event: event)
    }
}

public typealias NativeStreamingPluginAdapter = AskAIPluginUIAdapter

private struct AskAIAdapterContainerView: View {
    @ObservedObject var adapter: AskAIPluginUIAdapter

    var body: some View {
        if let customView = adapter.customCanvasView {
            customView
        } else {
            AskAIContainerView(
                text: adapter.text,
                mediaAssets: adapter.mediaAssets,
                citations: adapter.citations,
                isStreaming: adapter.isStreaming,
                rateLimitRetryAfter: adapter.rateLimitRetryAfter,
                focusCoordinator: adapter.focusCoordinator,
                onFollowUpSubmit: { followUp in
                    adapter.submitFollowUp(followUp)
                },
                onCitationSelect: { citation in
                    if let url = URLSanitizer.sanitize(citation.urlString) {
                        NSWorkspace.shared.open(url)
                    }
                },
                onMediaSelect: { index in
                    if index >= 0 && index < adapter.mediaAssets.count {
                        let asset = adapter.mediaAssets[index]
                        if let urlStr = asset.urlString, let url = URLSanitizer.sanitize(urlStr) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                },
                onOpenSetupWizard: {
                    adapter.openSetupWizard()
                }
            )
        }
    }
}
