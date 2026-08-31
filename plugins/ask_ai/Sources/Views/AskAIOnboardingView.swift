import SwiftUI
import AppKit
import TitikUI
import TitikPluginKit

// MARK: - Unified AI Provider Catalog

public enum AIProviderType: String, CaseIterable, Identifiable, Sendable {
    case openCode = "opencode"
    case gemini = "gemini"
    case openAI = "openai"
    case claude = "claude"
    case ollama = "ollama"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openCode: return "OpenCode"
        case .gemini: return "Google Gemini"
        case .openAI: return "OpenAI"
        case .claude: return "Anthropic Claude"
        case .ollama: return "Local Ollama"
        }
    }

    public var iconName: String {
        switch self {
        case .openCode: return "bolt.fill"
        case .gemini: return "sparkles"
        case .openAI: return "brain.head.profile"
        case .claude: return "bubble.left.and.bubble.right.fill"
        case .ollama: return "desktopcomputer"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .openCode: return OpenCodeProvider.defaultEndpoint.absoluteString
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .openAI: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .ollama: return "http://localhost:11434"
        }
    }

    public var defaultModel: String? {
        switch self {
        case .openCode: return OpenCodeProvider.defaultModel
        case .ollama: return nil
        default: return nil
        }
    }

    public var keychainKeyName: String {
        switch self {
        case .openCode: return "OPENCODE_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        case .openAI: return "OPENAI_API_KEY"
        case .claude: return "ANTHROPIC_API_KEY"
        case .ollama: return "OLLAMA_ENDPOINT"
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .openCode: return "Enter OpenCode API Key"
        case .gemini: return "AIzaSy..."
        case .openAI: return "sk-..."
        case .claude: return "sk-ant-..."
        case .ollama: return "llama3.2 (Model name)"
        }
    }

    public var keyLabel: String {
        switch self {
        case .ollama: return "Default Model Name:"
        default: return "API Key:"
        }
    }

    public var portalURL: URL? {
        switch self {
        case .openCode: return URL(string: "https://opencode.ai/auth")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .ollama: return URL(string: "https://ollama.com")
        }
    }

    public func createProvider() -> AIProvider {
        switch self {
        case .openCode:
            return OpenCodeProvider()
        case .gemini:
            return GeminiProvider()
        case .openAI:
            return OpenAIProvider()
        case .claude:
            return ClaudeProvider()
        case .ollama:
            return OllamaProvider()
        }
    }
}

// MARK: - Live Connection Tester

public struct ProviderConnectionTester: Sendable {
    public static func testConnection(
        provider: AIProviderType,
        apiKey: String,
        endpointURL: URL?
    ) async -> (isConnected: Bool, message: String) {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 6.0
        sessionConfig.timeoutIntervalForResource = 6.0
        let session = URLSession(configuration: sessionConfig)

        do {
            switch provider {
            case .openCode:
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = endpointURL?.absoluteString ?? OpenCodeProvider.defaultEndpoint.absoluteString
                let isLocal = endpointURL?.host == "127.0.0.1" || endpointURL?.host == "localhost"
                if !isLocal && trimmed.isEmpty {
                    return (false, "API key is required")
                }
                guard let url = URL(string: base).map({ OpenCodeProvider.modelsEndpoint(for: $0) }) else {
                    return (false, "Invalid URL")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                if !trimmed.isEmpty {
                    request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
                }
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return (true, "Endpoint reachable (key checked on first request)")
                    } else if http.statusCode == 401 || http.statusCode == 403 {
                        return (false, "Invalid OpenCode API Key (HTTP \(http.statusCode))")
                    } else {
                        return (false, "OpenCode returned HTTP \(http.statusCode)")
                    }
                }
                return (true, "Endpoint reachable (key checked on first request)")

            case .gemini:
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return (false, "API key is required")
                }
                let base = endpointURL?.absoluteString ?? "https://generativelanguage.googleapis.com"
                guard let url = URL(string: "\(base)/v1beta/models?key=\(trimmed)") else {
                    return (false, "Invalid URL")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return (true, "Connected (Ready)")
                    } else if http.statusCode == 400 || http.statusCode == 403 || http.statusCode == 401 {
                        return (false, "Invalid Gemini API Key (HTTP \(http.statusCode))")
                    } else {
                        return (false, "HTTP \(http.statusCode)")
                    }
                }
                return (true, "Connected (Ready)")

            case .openAI:
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return (false, "API key is required")
                }
                let base = endpointURL?.absoluteString ?? "https://api.openai.com/v1"
                let targetURL = base.hasSuffix("/models") ? base : (base.hasSuffix("/") ? "\(base)models" : "\(base)/models")
                guard let url = URL(string: targetURL) else {
                    return (false, "Invalid URL")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return (true, "Connected (Ready)")
                    } else if http.statusCode == 401 {
                        return (false, "Invalid OpenAI API Key (HTTP 401)")
                    } else {
                        return (false, "HTTP \(http.statusCode)")
                    }
                }
                return (true, "Connected (Ready)")

            case .claude:
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return (false, "API key is required")
                }
                let base = endpointURL?.absoluteString ?? "https://api.anthropic.com/v1"
                let targetURL = base.hasSuffix("/models") ? base : (base.hasSuffix("/") ? "\(base)models" : "\(base)/models")
                guard let url = URL(string: targetURL) else {
                    return (false, "Invalid URL")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(trimmed, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return (true, "Connected (Ready)")
                    } else if http.statusCode == 401 {
                        return (false, "Invalid Claude API Key (HTTP 401)")
                    } else {
                        return (false, "HTTP \(http.statusCode)")
                    }
                }
                return (true, "Connected (Ready)")

            case .ollama:
                let base = endpointURL?.absoluteString ?? "http://localhost:11434"
                guard let url = URL(string: "\(base)/api/version") else {
                    return (false, "Invalid URL")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return (true, "Connected (Ready)")
                    } else {
                        return (false, "Ollama returned HTTP \(http.statusCode)")
                    }
                }
                return (true, "Connected (Ready)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Notification for Prompt Selection

public extension Notification.Name {
    static let askAISelectPrompt = Notification.Name("AskAISelectPromptNotification")
}

// MARK: - Ask AI Setup / Onboarding View

public struct AskAIOnboardingView: View, @unchecked Sendable {
    public let context: PluginContext
    @State public var selectedProvider: AIProviderType
    @State private var apiKey: String = ""
    @State private var modelText: String = ""
    @State private var endpointText: String = ""
    @State private var isTesting: Bool = false
    @State private var statusMessage: String = ""
    @State private var isSaved: Bool = false

    public let onSelectPrompt: (@Sendable (String) -> Void)?
    public let onSaveSuccess: (@Sendable (AIProviderType) -> Void)?
    public let onDismiss: (@Sendable () -> Void)?

    public static let starterPrompts = [
        "Explain quantum entanglement with diagrams",
        "Map of Mount Fuji",
        "Summarize recent tech breakthroughs",
        "How do Swift 6 actors prevent data races?"
    ]

    nonisolated public init(
        context: PluginContext,
        selectedProvider: AIProviderType = .openCode,
        onSelectPrompt: (@Sendable (String) -> Void)? = nil,
        onSaveSuccess: (@Sendable (AIProviderType) -> Void)? = nil,
        onDismiss: (@Sendable () -> Void)? = nil
    ) {
        self.context = context
        _selectedProvider = State(initialValue: selectedProvider)
        self.onSelectPrompt = onSelectPrompt
        self.onSaveSuccess = onSaveSuccess
        self.onDismiss = onDismiss
    }

    public var body: some View {
        TitikGlassCard(cornerRadius: 14, padding: 14) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Welcome to Ask AI — Setup Wizard")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Choose your preferred AI backend, configure credentials, or start searching instantly.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()

                        if (try? context.keychain.getSecret(forKey: "AI_ONBOARDING_COMPLETED")) == "true" {
                            Button(action: {
                                onDismiss?()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Back to Chat")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white.opacity(0.85))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Provider Tab Switcher via TitikSegmentedPillBar
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose your AI Provider:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))

                        TitikSegmentedPillBar(
                            items: AIProviderType.allCases,
                            selection: $selectedProvider,
                            title: { $0.displayName },
                            iconName: { $0.iconName },
                            onSelect: { newProvider in
                                loadCredentials(for: newProvider)
                            }
                        )
                    }

                    // Configuration Form Card
                    VStack(alignment: .leading, spacing: 10) {
                        // API Key / Model Field via TitikFormField
                        TitikFormField(
                            label: selectedProvider.keyLabel,
                            placeholder: selectedProvider.keyPlaceholder,
                            text: $apiKey,
                            isSecure: selectedProvider != .ollama,
                            isMonospaced: true,
                            helperLinkLabel: selectedProvider.portalURL != nil ? "Get API Key" : nil,
                            helperLinkURL: selectedProvider.portalURL
                        )

                        // Endpoint URL Field via TitikFormField
                        TitikFormField(
                            label: "Endpoint URL (Optional):",
                            placeholder: selectedProvider.defaultEndpoint,
                            text: $endpointText,
                            isSecure: false,
                            isMonospaced: true
                        )

                        if let defaultModel = selectedProvider.defaultModel {
                            TitikFormField(
                                label: "Model ID (Optional):",
                                placeholder: defaultModel,
                                text: $modelText,
                                isSecure: false,
                                isMonospaced: true
                            )
                        }

                        // Action Buttons & Live Status Badge
                        HStack(spacing: 10) {
                            Button(action: testCurrentConnection) {
                                HStack(spacing: 5) {
                                    if isTesting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                    }
                                    Text("Test Connection")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isTesting)

                            Button(action: saveAndConnect) {
                                HStack(spacing: 5) {
                                    Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down.fill")
                                    Text(isSaved ? "Saved & Connected" : "Save & Connect")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.green.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if !statusMessage.isEmpty {
                                TitikStatusBadge(statusMessage: statusMessage)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    // Quick Start Example Prompts via TitikChipGroup
                    TitikChipGroup(
                        title: "💡 Quick-Start Example Prompts (Click to ask):",
                        chips: Self.starterPrompts,
                        onSelect: { prompt in
                            handlePromptClick(prompt)
                        }
                    )
                }
            }
        }
        .onAppear {
            loadCredentials(for: selectedProvider)
        }
        .onChange(of: selectedProvider) { newProvider in
            loadCredentials(for: newProvider)
        }
    }

    private func loadCredentials(for provider: AIProviderType) {
        statusMessage = ""
        isSaved = false
        if let key = try? context.keychain.getSecret(forKey: provider.keychainKeyName) {
            apiKey = key
        } else {
            apiKey = ""
        }
        if let endpoint = try? context.keychain.getSecret(forKey: "AI_ENDPOINT_\(provider.rawValue)") {
            endpointText = endpoint
        } else {
            endpointText = ""
        }
        if let model = try? context.keychain.getSecret(forKey: "AI_MODEL_\(provider.rawValue)") {
            modelText = model
        } else {
            modelText = ""
        }
    }

    private func testCurrentConnection() {
        isTesting = true
        statusMessage = "🟡 Testing connection..."
        let provider = selectedProvider
        let currentKey = apiKey
        let customURL = endpointText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines))

        Task {
            let result = await ProviderConnectionTester.testConnection(
                provider: provider,
                apiKey: currentKey,
                endpointURL: customURL
            )
            await MainActor.run {
                self.isTesting = false
                if result.isConnected {
                    self.statusMessage = "🟢 \(result.message)"
                } else {
                    self.statusMessage = "🔴 Offline: \(result.message)"
                }
            }
        }
    }

    private func saveAndConnect() {
        let provider = selectedProvider
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if !trimmedKey.isEmpty {
                try context.keychain.setSecret(trimmedKey, forKey: provider.keychainKeyName)
            } else if provider != .ollama {
                try? context.keychain.deleteSecret(forKey: provider.keychainKeyName)
            }
            try context.keychain.setSecret(provider.rawValue, forKey: "AI_ACTIVE_PROVIDER")

            if !trimmedEndpoint.isEmpty {
                try context.keychain.setSecret(trimmedEndpoint, forKey: "AI_ENDPOINT_\(provider.rawValue)")
            } else {
                try? context.keychain.deleteSecret(forKey: "AI_ENDPOINT_\(provider.rawValue)")
            }

            let trimmedModel = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModel.isEmpty {
                try context.keychain.setSecret(trimmedModel, forKey: "AI_MODEL_\(provider.rawValue)")
            } else {
                try? context.keychain.deleteSecret(forKey: "AI_MODEL_\(provider.rawValue)")
            }

            try context.keychain.setSecret("true", forKey: "AI_ONBOARDING_COMPLETED")

            self.isSaved = true
            self.statusMessage = "🟢 Saved (test connection before use)"
            onSaveSuccess?(provider)
            onDismiss?()
        } catch {
            self.statusMessage = "🔴 Save Error: \(error.localizedDescription)"
        }
    }

    private func handlePromptClick(_ prompt: String) {
        if let onSelectPrompt = onSelectPrompt {
            onSelectPrompt(prompt)
        }
        NotificationCenter.default.post(name: .askAISelectPrompt, object: prompt)
    }
}
