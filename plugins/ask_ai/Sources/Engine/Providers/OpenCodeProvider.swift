import Foundation
import TitikCore
import TitikPluginKit

public final class OpenCodeProvider: AIProvider, @unchecked Sendable {
    public let id: String = "opencode"
    public let displayName: String = "OpenCode (Official)"
    public let isOfficial: Bool = true
    public let isUntested: Bool = false

    /// OpenCode Go exposes different wire protocols depending on the model.
    /// Keep the base URL here and select the route from the requested model.
    public static let defaultEndpoint = URL(string: "https://opencode.ai/zen/go/v1")!
    public static let defaultModel = "glm-5.3-flash"

    private enum APIFormat {
        case chatCompletions
        case responses
        case messages

        var route: String {
            switch self {
            case .chatCompletions: return "chat/completions"
            case .responses: return "responses"
            case .messages: return "messages"
            }
        }
    }

    private static let responsesModels: Set<String> = [
        "grok-4.6", "gpt-5.6-luna", "muse-spark-1.2-contributor"
    ]

    private static let messagesModels: Set<String> = [
        "minimax-m3", "minimax-m2.7", "minimax-m2.5",
        "qwen3.8-max", "qwen3.8-flash", "qwen3.7-max",
        "qwen3.7-plus", "qwen3.6-plus"
    ]

    public init() {}

    public func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        let model = Self.normalizedModel(options.model ?? Self.defaultModel)
        let apiFormat = Self.format(for: options.endpoint, model: model)
        let endpointURL = Self.endpointURL(for: options.endpoint, model: model)

        let isLocal = endpointURL.host == "localhost" || endpointURL.host == "127.0.0.1"
        let apiKey = options.apiKey ?? ""
        if !isLocal && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PluginError.unauthorized("OpenCode API key is required. Press ⌘, to configure your API key.")
        }

        let session = options.session ?? URLSession.shared

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if apiFormat == .messages {
            if !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let formattedMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        var bodyDict: [String: Any]
        switch apiFormat {
        case .chatCompletions:
            bodyDict = ["model": model, "messages": formattedMessages, "stream": true]
        case .responses:
            bodyDict = ["model": model, "input": formattedMessages, "stream": true]
        case .messages:
            let nonSystemMessages = messages.filter { $0.role != .system }
            bodyDict = [
                "model": model,
                "messages": nonSystemMessages.map { [
                    "role": $0.role == .assistant ? "assistant" : "user",
                    "content": $0.content
                ] },
                "max_tokens": options.maxTokens ?? 4096,
                "stream": true
            ]
            if let system = messages.first(where: { $0.role == .system })?.content {
                bodyDict["system"] = system
            }
        }
        if let temp = options.temperature {
            bodyDict["temperature"] = temp
        }
        if let maxTokens = options.maxTokens {
            bodyDict["max_tokens"] = maxTokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        Logger.shared.info("OpenCode fetch: POST \(endpointURL) [model: \(model), format: \(apiFormat.route), messages: \(messages.count), bodyBytes: \(request.httpBody?.count ?? 0)]", subsystem: "Titik.AskAI")

        let finalRequest = request
        let activeSession = session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await activeSession.bytes(for: finalRequest)

                    if let httpResponse = response as? HTTPURLResponse {
                        Logger.shared.info("OpenCode fetch response: HTTP \(httpResponse.statusCode) from \(endpointURL)", subsystem: "Titik.AskAI")

                        if httpResponse.statusCode == 429 {
                            let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            let retrySeconds = Double(retryAfterHeader ?? "") ?? 3.0
                            continuation.yield(.rateLimit(retryAfter: retrySeconds))
                            continuation.finish()
                            return
                        }

                        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                            continuation.finish(throwing: PluginError.unauthorized("OpenCode authentication failed (HTTP \(httpResponse.statusCode)). Check that this is an OpenCode Go API key."))
                            return
                        }

                        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                            var responseBody = Data()
                            for try await byte in bytes {
                                responseBody.append(byte)
                            }
                            let detail = String(data: responseBody, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let suffix = detail.map { $0.isEmpty ? "" : ": \($0)" } ?? ""
                            continuation.finish(throwing: PluginError.networkError("OpenCode server returned status code \(httpResponse.statusCode)\(suffix)"))
                            return
                        }
                    }

                    let parser = StructuredResponseParser()

                    for try await byte in bytes {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        let data = Data([byte])
                        let output = parser.processChunk(data)

                        for text in output.textDeltas {
                            continuation.yield(.text(text))
                        }
                        for media in output.mediaAssets {
                            continuation.yield(.media(media))
                        }
                        for citation in output.citations {
                            continuation.yield(.citation(citation))
                        }
                        if let retry = output.rateLimitRetryAfter {
                            continuation.yield(.rateLimit(retryAfter: retry))
                        }
                        if output.isDone {
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }
                    }

                    let finalOutput = parser.flush()
                    for text in finalOutput.textDeltas {
                        continuation.yield(.text(text))
                    }
                    for media in finalOutput.mediaAssets {
                        continuation.yield(.media(media))
                    }
                    for citation in finalOutput.citations {
                        continuation.yield(.citation(citation))
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        Logger.shared.debug("OpenCode stream cancelled for \(endpointURL)", subsystem: "Titik.AskAI")
                        continuation.finish()
                    } else {
                        Logger.shared.error("OpenCode error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func normalizedModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("opencode-go/") {
            return String(trimmed.dropFirst("opencode-go/".count))
        }
        return trimmed
    }

    private static func format(for model: String) -> APIFormat {
        if responsesModels.contains(model) { return .responses }
        if messagesModels.contains(model) { return .messages }
        return .chatCompletions
    }

    private static func format(for endpoint: URL?, model: String) -> APIFormat {
        guard let endpoint else { return format(for: model) }
        let path = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("/chat/completions") { return .chatCompletions }
        if path.hasSuffix("/responses") { return .responses }
        if path.hasSuffix("/messages") { return .messages }
        return format(for: model)
    }

    public static func endpointURL(for endpoint: URL?, model: String) -> URL {
        let base = endpoint ?? defaultEndpoint
        let format = format(for: normalizedModel(model))
        let route = format.route
        var path = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let knownRoutes = ["chat/completions", "responses", "messages"]

        // A complete route supplied by the user is authoritative, which also
        // allows custom gateways to expose only one of the three protocols.
        if knownRoutes.contains(where: { path.hasSuffix($0) }) {
            return base
        }
        if path.hasSuffix("/models") {
            path = String(path.dropLast("/models".count))
        }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var basePath = path
        if basePath.isEmpty {
            basePath = ""
        } else if basePath.hasSuffix("/v1") {
            basePath = "/" + basePath
        } else if base.host == "opencode.ai" && basePath.hasSuffix("/go") {
            basePath = "/" + basePath + "/v1"
        } else {
            basePath = "/" + basePath
        }
        components?.path = "\(basePath)/\(route)".replacingOccurrences(of: "//", with: "/")
        return components?.url ?? base
    }

    public static func modelsEndpoint(for endpoint: URL?) -> URL {
        let base = endpoint ?? defaultEndpoint
        let path = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if path.hasSuffix("/models") {
            return base
        }
        if path.hasSuffix("/chat/completions") || path.hasSuffix("/responses") || path.hasSuffix("/messages") {
            let routeSuffix = path.hasSuffix("/chat/completions") ? "/chat/completions" : (path.hasSuffix("/responses") ? "/responses" : "/messages")
            components?.path = "/" + String(path.dropLast(routeSuffix.count)) + "/models"
        } else if path.isEmpty {
            components?.path = "/models"
        } else if path.hasSuffix("/v1") {
            components?.path = "/" + path + "/models"
        } else if base.host == "opencode.ai" && path.hasSuffix("/go") {
            components?.path = "/" + path + "/v1/models"
        } else {
            components?.path = "/" + path + "/models"
        }
        return components?.url ?? base
    }
}
