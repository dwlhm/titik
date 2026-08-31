import Foundation
import TitikCore
import TitikPluginKit

public final class AntigravityProvider: AIProvider, @unchecked Sendable {
    public let id: String = "google-antigravity"
    public let displayName: String = "Google Antigravity Subscription (Official)"
    public let isOfficial: Bool = true
    public let isUntested: Bool = false

    private let defaultEndpoint = URL(string: "https://antigravity.google.com/v1/chat/stream")!

    public init() {}

    public func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error> {
        let token = options.subscriberToken ?? options.apiKey
        guard let validToken = token, !validToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PluginError.unauthorized("Google Antigravity subscriber token is required. Please configure your subscription in Titik preferences.")
        }

        let endpoint = options.endpoint ?? defaultEndpoint
        let session = options.session ?? URLSession.shared

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(validToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Titik/2.0 (macOS)", forHTTPHeaderField: "X-Antigravity-Client")

        let formattedMessages = messages.map { msg -> [String: String] in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        var bodyDict: [String: Any] = [
            "model": options.model ?? "antigravity-gemini-pro",
            "messages": formattedMessages,
            "stream": true
        ]
        if let temp = options.temperature {
            bodyDict["temperature"] = temp
        }
        if let maxTokens = options.maxTokens {
            bodyDict["max_tokens"] = maxTokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        Logger.shared.info("Google Antigravity fetch: POST \(endpoint) [model: \(options.model ?? "antigravity-gemini-pro"), messages: \(messages.count), bodyBytes: \(request.httpBody?.count ?? 0)]", subsystem: "Titik.AskAI")

        let finalRequest = request
        let activeSession = session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await activeSession.bytes(for: finalRequest)

                    if let httpResponse = response as? HTTPURLResponse {
                        Logger.shared.info("Google Antigravity fetch response: HTTP \(httpResponse.statusCode) from \(endpoint)", subsystem: "Titik.AskAI")

                        if httpResponse.statusCode == 429 {
                            let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            let retrySeconds = Double(retryAfterHeader ?? "") ?? 5.0
                            continuation.yield(.rateLimit(retryAfter: retrySeconds))
                            continuation.finish()
                            return
                        }

                        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                            continuation.finish(throwing: PluginError.unauthorized("Google Antigravity subscription credentials invalid or expired."))
                            return
                        }

                        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                            continuation.finish(throwing: PluginError.networkError("Google Antigravity service returned status code \(httpResponse.statusCode)"))
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
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
