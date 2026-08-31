import Foundation
import TitikCore
import TitikPluginKit

// MARK: - Gemini Direct Adapter (Unofficial / Untested)

public final class GeminiProvider: AIProvider, @unchecked Sendable {
    public let id: String = "gemini-direct"
    public let displayName: String = "Google Gemini Direct API (Unofficial/Untested)"
    public let isOfficial: Bool = false
    public let isUntested: Bool = true

    private let defaultEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse")!

    public init() {}

    public func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        let apiKey = options.apiKey ?? ""
        if apiKey.isEmpty {
            throw PluginError.unauthorized("Google Gemini API key is required. Press ⌘, to configure your API key.")
        }
        let model = options.model ?? "gemini-1.5-flash"
        let baseEndpoint = options.endpoint ?? URL(string: "https://generativelanguage.googleapis.com")!
        let endpointStr: String
        if baseEndpoint.path.contains("streamGenerateContent") {
            endpointStr = baseEndpoint.absoluteString
        } else {
            let base = baseEndpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            endpointStr = "\(base)/v1beta/models/\(model):streamGenerateContent?alt=sse"
        }
        var urlComponents = URLComponents(string: endpointStr)
        if !apiKey.isEmpty {
            var items = urlComponents?.queryItems ?? []
            items.removeAll(where: { $0.name == "key" })
            items.append(URLQueryItem(name: "key", value: apiKey))
            urlComponents?.queryItems = items
        }

        guard let requestURL = urlComponents?.url else {
            throw PluginError.networkError("Invalid Gemini request URL")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents = messages.map { msg -> [String: Any] in
            let role = msg.role == .assistant ? "model" : "user"
            return [
                "role": role,
                "parts": [["text": msg.content]]
            ]
        }

        let bodyDict: [String: Any] = ["contents": contents]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        Logger.shared.info("Gemini fetch: POST \(requestURL) [model: \(model)]", subsystem: "Titik.AskAI")

        let finalRequest = request
        let session = options.session ?? URLSession.shared

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: finalRequest)
                    if let http = response as? HTTPURLResponse {
                        Logger.shared.info("Gemini fetch response: HTTP \(http.statusCode) from \(requestURL)", subsystem: "Titik.AskAI")
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            continuation.finish(throwing: PluginError.networkError("Gemini API error (HTTP \(http.statusCode))"))
                            return
                        }
                    }

                    let parser = StructuredResponseParser()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        let output = parser.processChunk(Data([byte]))
                        for text in output.textDeltas { continuation.yield(.text(text)) }
                        for media in output.mediaAssets { continuation.yield(.media(media)) }
                        for citation in output.citations { continuation.yield(.citation(citation)) }
                    }
                    let finalOutput = parser.flush()
                    for text in finalOutput.textDeltas { continuation.yield(.text(text)) }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        Logger.shared.error("Gemini error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI Direct Adapter (Unofficial / Untested)

public final class OpenAIProvider: AIProvider, @unchecked Sendable {
    public let id: String = "openai-direct"
    public let displayName: String = "OpenAI Direct API (Unofficial/Untested)"
    public let isOfficial: Bool = false
    public let isUntested: Bool = true

    private let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    public init() {}

    public func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        guard let apiKey = options.apiKey, !apiKey.isEmpty else {
            throw PluginError.unauthorized("OpenAI API key is required. Press ⌘, to configure your API key.")
        }

        let baseEndpoint = options.endpoint ?? defaultEndpoint
        let endpointURL: URL
        if baseEndpoint.path.hasSuffix("/chat/completions") {
            endpointURL = baseEndpoint
        } else {
            let baseStr = baseEndpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            endpointURL = URL(string: "\(baseStr)/chat/completions") ?? baseEndpoint
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let formatted = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": options.model ?? "gpt-4o",
            "messages": formatted,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.shared.info("OpenAI fetch: POST \(endpointURL) [model: \(options.model ?? "gpt-4o")]", subsystem: "Titik.AskAI")

        let finalRequest = request
        let session = options.session ?? URLSession.shared

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: finalRequest)
                    if let http = response as? HTTPURLResponse {
                        Logger.shared.info("OpenAI fetch response: HTTP \(http.statusCode) from \(endpointURL)", subsystem: "Titik.AskAI")
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            continuation.finish(throwing: PluginError.networkError("OpenAI API error (HTTP \(http.statusCode))"))
                            return
                        }
                    }

                    let parser = StructuredResponseParser()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        let output = parser.processChunk(Data([byte]))
                        for text in output.textDeltas { continuation.yield(.text(text)) }
                        for media in output.mediaAssets { continuation.yield(.media(media)) }
                        for citation in output.citations { continuation.yield(.citation(citation)) }
                    }
                    let finalOutput = parser.flush()
                    for text in finalOutput.textDeltas { continuation.yield(.text(text)) }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        Logger.shared.error("OpenAI error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Claude Direct Adapter (Unofficial / Untested)

public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    public let id: String = "claude-direct"
    public let displayName: String = "Anthropic Claude Direct API (Unofficial/Untested)"
    public let isOfficial: Bool = false
    public let isUntested: Bool = true

    private let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init() {}

    public func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        guard let apiKey = options.apiKey, !apiKey.isEmpty else {
            throw PluginError.unauthorized("Anthropic API key is required. Press ⌘, to configure your API key.")
        }

        let baseEndpoint = options.endpoint ?? defaultEndpoint
        let endpointURL: URL
        if baseEndpoint.path.hasSuffix("/messages") {
            endpointURL = baseEndpoint
        } else {
            let baseStr = baseEndpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            endpointURL = URL(string: "\(baseStr)/messages") ?? baseEndpoint
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let nonSystem = messages.filter { $0.role != .system }
        let formatted = nonSystem.map { ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content] }

        var body: [String: Any] = [
            "model": options.model ?? "claude-3-5-sonnet-20241022",
            "messages": formatted,
            "max_tokens": options.maxTokens ?? 4096,
            "stream": true
        ]
        if let sys = messages.first(where: { $0.role == .system })?.content {
            body["system"] = sys
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.shared.info("Claude fetch: POST \(endpointURL) [model: \(options.model ?? "claude-3-5-sonnet-20241022")]", subsystem: "Titik.AskAI")

        let finalRequest = request
        let session = options.session ?? URLSession.shared

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: finalRequest)
                    if let http = response as? HTTPURLResponse {
                        Logger.shared.info("Claude fetch response: HTTP \(http.statusCode) from \(endpointURL)", subsystem: "Titik.AskAI")
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            continuation.finish(throwing: PluginError.networkError("Claude API error (HTTP \(http.statusCode))"))
                            return
                        }
                    }

                    let parser = StructuredResponseParser()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        let output = parser.processChunk(Data([byte]))
                        for text in output.textDeltas { continuation.yield(.text(text)) }
                        for media in output.mediaAssets { continuation.yield(.media(media)) }
                        for citation in output.citations { continuation.yield(.citation(citation)) }
                    }
                    let finalOutput = parser.flush()
                    for text in finalOutput.textDeltas { continuation.yield(.text(text)) }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        Logger.shared.error("Claude error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Ollama Local Adapter (Unofficial / Untested)

public final class OllamaProvider: AIProvider, @unchecked Sendable {
    public let id: String = "ollama-local"
    public let displayName: String = "Local Ollama Instance (Unofficial/Untested)"
    public let isOfficial: Bool = false
    public let isUntested: Bool = true

    private let defaultEndpoint = URL(string: "http://localhost:11434/api/chat")!

    public init() {}

    public func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        let baseEndpoint = options.endpoint ?? defaultEndpoint
        let endpointURL: URL
        if baseEndpoint.path.hasSuffix("/api/chat") {
            endpointURL = baseEndpoint
        } else {
            let baseStr = baseEndpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            endpointURL = URL(string: "\(baseStr)/api/chat") ?? baseEndpoint
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatted = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": options.model ?? "llama3",
            "messages": formatted,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.shared.info("Ollama fetch: POST \(endpointURL) [model: \(options.model ?? "llama3")]", subsystem: "Titik.AskAI")

        let finalRequest = request
        let session = options.session ?? URLSession.shared

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: finalRequest)
                    if let http = response as? HTTPURLResponse {
                        Logger.shared.info("Ollama fetch response: HTTP \(http.statusCode) from \(endpointURL)", subsystem: "Titik.AskAI")
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            continuation.finish(throwing: PluginError.networkError("Ollama connection error (HTTP \(http.statusCode))"))
                            return
                        }
                    }

                    let parser = StructuredResponseParser()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        let output = parser.processChunk(Data([byte]))
                        for text in output.textDeltas { continuation.yield(.text(text)) }
                        for media in output.mediaAssets { continuation.yield(.media(media)) }
                        for citation in output.citations { continuation.yield(.citation(citation)) }
                    }
                    let finalOutput = parser.flush()
                    for text in finalOutput.textDeltas { continuation.yield(.text(text)) }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        Logger.shared.error("Ollama error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
