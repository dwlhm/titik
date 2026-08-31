import Foundation
import SwiftUI
import TitikCore
import TitikPluginKit

public final class AskAIPlugin: TitikStreamingPlugin, @unchecked Sendable {
    public static let id: String = "com.titik.plugin.ask_ai"
    public static let name: String = "Ask AI"
    public static let version: String = "1.0.0"
    public static let sdkVersion: Int = 2

    public let context: PluginContext
    public let sessionCoordinator: AISessionCoordinator

    private let webSearchService: WebSearchService
    private var currentProviderType: AIProviderType
    private var currentProvider: AIProvider
    private var activeStreamTask: Task<Void, Never>?
    private let lock = NSLock()

    /// Protocol conformance witness for `TitikPlugin`'s exact
    /// `init(context:)` requirement.
    public convenience init(context: PluginContext) {
        self.init(context: context, webSearchService: WebSearchService())
    }

    public init(context: PluginContext, webSearchService: WebSearchService = WebSearchService()) {
        self.context = context
        self.webSearchService = webSearchService
        self.sessionCoordinator = AISessionCoordinator(maxTokens: 8192, maxTurns: 10, systemPrompt: AIFormatPrompt.text)
        let savedProviderId = (try? context.keychain.getSecret(forKey: "AI_ACTIVE_PROVIDER")) ?? AIProviderType.openCode.rawValue
        let providerType = AIProviderType(rawValue: savedProviderId) ?? .openCode
        self.currentProviderType = providerType
        self.currentProvider = providerType.createProvider()
    }

    public var providerType: AIProviderType {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentProviderType
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            currentProviderType = newValue
            currentProvider = newValue.createProvider()
        }
    }

    public var provider: AIProvider {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentProvider
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            currentProvider = newValue
        }
    }

    public func setProviderType(_ newType: AIProviderType) {
        lock.lock()
        defer { lock.unlock() }
        self.currentProviderType = newType
        self.currentProvider = newType.createProvider()
    }

    public func setProvider(_ newProvider: AIProvider) {
        lock.lock()
        defer { lock.unlock() }
        self.currentProvider = newProvider
    }

    private func setActiveTask(_ task: Task<Void, Never>?) {
        lock.lock()
        defer { lock.unlock() }
        self.activeStreamTask = task
    }

    private func takeActiveTask() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        let task = self.activeStreamTask
        self.activeStreamTask = nil
        return task
    }

    public var hasCompletedOnboarding: Bool {
        if (try? context.keychain.getSecret(forKey: "AI_ONBOARDING_COMPLETED")) == "true" {
            // The completion marker is shared by the plugin, but credentials
            // belong to the selected provider. Do not hide setup when the
            // active provider has no usable credential.
            let activeKey = (try? context.keychain.getSecret(forKey: providerType.keychainKeyName)) ?? nil
            if providerType == .ollama {
                let endpoint = (try? context.keychain.getSecret(forKey: "AI_ENDPOINT_\(providerType.rawValue)")) ?? nil
                return !(activeKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
                    !(endpoint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            return !(activeKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let activeKey = (try? context.keychain.getSecret(forKey: providerType.keychainKeyName)) ?? nil
        return !(activeKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let cleanQuery = stripTriggerPrefix(from: query)
        Logger.shared.info("AskAI query: '\(cleanQuery)' [provider: \(self.providerType.displayName)]", subsystem: "Titik.AskAI")
        if cleanQuery == "settings" || cleanQuery == "config" {
            let activeType = self.providerType
            let onboardingView = AskAIOnboardingView(
                context: context,
                selectedProvider: activeType,
                onSelectPrompt: { prompt in
                    NotificationCenter.default.post(
                        name: .askAISelectPrompt,
                        object: prompt
                    )
                },
                onSaveSuccess: { [weak self] newType in
                    self?.setProviderType(newType)
                }
            )
            return .customView(AnyView(onboardingView))
        }

        if cleanQuery.isEmpty {
            if !hasCompletedOnboarding {
                let activeType = self.providerType
                let onboardingView = AskAIOnboardingView(
                    context: context,
                    selectedProvider: activeType,
                    onSelectPrompt: { prompt in
                        NotificationCenter.default.post(
                            name: .askAISelectPrompt,
                            object: prompt
                        )
                    },
                    onSaveSuccess: { [weak self] newType in
                        self?.setProviderType(newType)
                    }
                )
                return .customView(AnyView(onboardingView))
            } else {
                let readyView = await MainActor.run {
                    let coordinator = PluginFocusCoordinator(
                        initialZone: .input,
                        mediaCount: 0,
                        citationCount: 0,
                        hasFollowUpBar: true
                    )
                    return AskAIContainerView(
                        text: "",
                        focusCoordinator: coordinator,
                        onFollowUpSubmit: { followUp in
                            NotificationCenter.default.post(
                                name: .askAISelectPrompt,
                                object: followUp
                            )
                        },
                        onOpenSetupWizard: {
                            NotificationCenter.default.post(
                                name: .askAISelectPrompt,
                                object: "settings"
                            )
                        }
                    )
                }
                return .customView(AnyView(readyView))
            }
        }

        await cancelActiveStream()

        let emitter = StreamEmitter()

        // Append user turn
        await sessionCoordinator.appendTurn(role: .user, content: cleanQuery)

        // Web search is disabled only when explicitly turned off in preferences
        let webSearchEnabled = (try? context.keychain.getSecret(forKey: "AI_WEB_SEARCH_ENABLED")) != "false"

        let history = await sessionCoordinator.history()
        let hasPriorTurns = history.filter { $0.role != .system }.count > 1
        let userTurns = history.filter { $0.role == .user }
        let lastUserTurn: String? = userTurns.count >= 2 ? userTurns[userTurns.count - 2].content : nil
        let lastAssistantTurn: String? = history.last(where: { $0.role == .assistant })?.content

        // Build a request-local history copy with the grounded web context
        // injected into the last user turn. The coordinator history stays
        // clean so the context block does not bloat future turns.
        var requestHistory = history
        if webSearchEnabled,
           let resolvedQuery = SearchQueryResolver.resolve(
               query: cleanQuery,
               hasPriorTurns: hasPriorTurns,
               lastUserTurn: lastUserTurn,
               lastAssistantTurn: lastAssistantTurn
           ) {
            let grounded = await webSearchService.search(resolvedQuery)
            if let contextBlock = GroundedContextBuilder.buildContext(from: grounded) {
                if let lastIndex = requestHistory.indices.last, requestHistory[lastIndex].role == .user {
                    let original = requestHistory[lastIndex]
                    requestHistory[lastIndex] = ChatMessage(
                        id: original.id,
                        role: original.role,
                        content: original.content + "\n\n" + contextBlock,
                        timestamp: original.timestamp,
                        mediaAssets: original.mediaAssets,
                        citations: original.citations
                    )
                }
            }
        }

        // Read secrets from Keychain for active provider
        let activeProvType = self.providerType
        let activeKey = try? context.keychain.getSecret(forKey: activeProvType.keychainKeyName)
        let antigravityToken = try? context.keychain.getSecret(forKey: "ANTIGRAVITY_TOKEN")
        let customEndpointStr = try? context.keychain.getSecret(forKey: "AI_ENDPOINT_\(activeProvType.rawValue)")
        let customEndpoint = (customEndpointStr != nil && !customEndpointStr!.isEmpty) ? URL(string: customEndpointStr!) : nil
        let configuredModel = try? context.keychain.getSecret(forKey: "AI_MODEL_\(activeProvType.rawValue)")

        let options = ProviderOptions(
            apiKey: activeKey,
            subscriberToken: antigravityToken,
            endpoint: customEndpoint,
            model: configuredModel
        )

        let activeProv = self.provider

        let task = Task { [weak self, weak emitter, requestHistory, options, activeProv] in
            guard let emitter = emitter else { return }

            var accumulatedText = ""
            var accumulatedMedia: [MediaAsset] = []
            var accumulatedCitations: [CitationSource] = []

            do {
                let stream = try await activeProv.streamChat(messages: requestHistory, options: options)

                for try await chunk in stream {
                    if Task.isCancelled { break }

                    switch chunk {
                    case .text(let text):
                        accumulatedText += text
                        await emitter.emitText(text)

                    case .media(let media):
                        accumulatedMedia.append(media)
                        await emitter.emitMedia(media)

                    case .citation(let citation):
                        accumulatedCitations.append(citation)
                        await emitter.emitCitation(citation)

                    case .rateLimit(let retryAfter):
                        await emitter.emitRateLimit(retryAfter: retryAfter)

                    case .done:
                        break
                    }
                }

                if !Task.isCancelled {
                    if let self = self {
                        await self.sessionCoordinator.appendTurn(
                            role: .assistant,
                            content: accumulatedText,
                            mediaAssets: accumulatedMedia,
                            citations: accumulatedCitations
                        )
                    }
                    await emitter.finish()
                }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    Logger.shared.debug("AskAI stream cancelled", subsystem: "Titik.AskAI")
                } else {
                    Logger.shared.error("AskAI stream error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
                    if !Task.isCancelled {
                        await emitter.emitError(error.localizedDescription)
                        await emitter.finish()
                    }
                }
            }
        }

        setActiveTask(task)

        return .streaming(emitter)
    }

    public func cancelActiveStream() async {
        let task = takeActiveTask()
        task?.cancel()
    }

    public func onShutdown() {
        Task {
            await cancelActiveStream()
            await sessionCoordinator.reset()
        }
    }

    private func stripTriggerPrefix(from raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("!ask ") {
            str = String(str.dropFirst(5))
        } else if str == "!ask" {
            return ""
        } else if str.hasPrefix("!ai ") {
            str = String(str.dropFirst(4))
        } else if str == "!ai" {
            return ""
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
