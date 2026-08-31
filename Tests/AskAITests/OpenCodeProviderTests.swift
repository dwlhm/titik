import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

final class OpenCodeMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        OpenCodeMockURLProtocol.lock.lock()
        let handler = OpenCodeMockURLProtocol.requestHandler
        OpenCodeMockURLProtocol.lock.unlock()

        guard let handler = handler else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("OpenCode Provider Tests", .serialized)
struct OpenCodeProviderTests {

    private func makeMockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        OpenCodeMockURLProtocol.lock.lock()
        OpenCodeMockURLProtocol.requestHandler = handler
        OpenCodeMockURLProtocol.lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("OpenCode provider has correct official status and metadata")
    func test_openCodeProvider_metadata() {
        let provider = OpenCodeProvider()
        #expect(provider.id == "opencode")
        #expect(provider.isOfficial == true)
        #expect(provider.isUntested == false)
        #expect(provider.displayName.contains("Official"))
    }

    @Test("OpenCode Go normalizes config model IDs and selects the documented route")
    func test_openCodeProvider_modelRouting() {
        #expect(OpenCodeProvider.normalizedModel("opencode-go/glm-5.2") == "glm-5.2")
        #expect(OpenCodeProvider.endpointURL(for: nil, model: "glm-5.2").path.hasSuffix("/v1/chat/completions"))
        #expect(OpenCodeProvider.endpointURL(for: nil, model: "gpt-5.6-luna").path.hasSuffix("/v1/responses"))
        #expect(OpenCodeProvider.endpointURL(for: nil, model: "qwen3.7-plus").path.hasSuffix("/v1/messages"))
        #expect(OpenCodeProvider.modelsEndpoint(for: URL(string: "https://opencode.ai/zen/go/v1/chat/completions")!).path.hasSuffix("/v1/models"))
    }

    @Test("OpenCode provider streams chunks and parses citations")
    func test_openCodeProvider_validEndpoint_streamsChunksAndCitations() async throws {
        let ssePayload = """
        data: {"choices":[{"delta":{"content":"Swift 6 introduces "}}]}

        data: {"choices":[{"delta":{"content":"strict concurrency.[[cite:index=1&url=https://swift.org&title=Swift.org]]"}}]}

        data: {"media":[{"type":"image","title":"Swift Logo","url":"https://swift.org/logo.png"}]}

        data: [DONE]

        """

        let session = makeMockSession { req in
            let res = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (res, ssePayload.data(using: .utf8)!)
        }

        let provider = OpenCodeProvider()
        let options = ProviderOptions(apiKey: "mock-opencode-key", session: session)
        let messages = [ChatMessage(role: .user, content: "Tell me about Swift 6")]

        let stream = try await provider.streamChat(messages: messages, options: options)

        var textCollected = ""
        var citationsCollected: [CitationSource] = []
        var mediaCollected: [MediaAsset] = []

        for try await chunk in stream {
            switch chunk {
            case .text(let t):
                textCollected += t
            case .citation(let c):
                citationsCollected.append(c)
            case .media(let m):
                mediaCollected.append(m)
            case .rateLimit, .done:
                break
            }
        }

        #expect(textCollected.contains("Swift 6 introduces strict concurrency."))
        #expect(citationsCollected.count == 1)
        #expect(citationsCollected.first?.urlString == "https://swift.org")
        #expect(mediaCollected.count == 1)
        #expect(mediaCollected.first?.title == "Swift Logo")
    }

    @Test("OpenCode provider handles HTTP 429 rate limit correctly")
    func test_openCodeProvider_rateLimit429() async throws {
        let session = makeMockSession { req in
            let res = HTTPURLResponse(
                url: req.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "5"]
            )!
            return (res, Data())
        }

        let provider = OpenCodeProvider()
        let options = ProviderOptions(apiKey: "key", session: session)
        let stream = try await provider.streamChat(messages: [ChatMessage(role: .user, content: "hi")], options: options)

        var gotRateLimit = false
        var retrySeconds: TimeInterval = 0

        for try await chunk in stream {
            if case .rateLimit(let s) = chunk {
                gotRateLimit = true
                retrySeconds = s
            }
        }

        #expect(gotRateLimit == true)
        #expect(retrySeconds == 5.0)
    }

    @Test("OpenCode Go uses Anthropic-compatible headers for Messages models")
    func test_openCodeProvider_messagesModel_usesAnthropicProtocol() async throws {
        var observedRequest: URLRequest?
        let session = makeMockSession { req in
            observedRequest = req
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data("data: [DONE]\n".utf8))
        }

        let provider = OpenCodeProvider()
        let options = ProviderOptions(
            apiKey: "go-key",
            model: "opencode-go/qwen3.7-plus",
            session: session
        )
        let stream = try await provider.streamChat(
            messages: [ChatMessage(role: .user, content: "hello")],
            options: options
        )
        for try await _ in stream {}

        #expect(observedRequest?.url?.path.hasSuffix("/v1/messages") == true)
        #expect(observedRequest?.value(forHTTPHeaderField: "x-api-key") == "go-key")
        #expect(observedRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(observedRequest?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test("OpenCode provider throws unauthorized on HTTP 401")
    func test_openCodeProvider_unauthorized401() async {
        let session = makeMockSession { req in
            let res = HTTPURLResponse(
                url: req.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (res, Data())
        }

        let provider = OpenCodeProvider()
        let options = ProviderOptions(apiKey: "invalid_key", session: session)

        do {
            let stream = try await provider.streamChat(messages: [ChatMessage(role: .user, content: "hi")], options: options)
            for try await _ in stream {}
            Issue.record("Expected unauthorized error")
        } catch let error as PluginError {
            if case .unauthorized = error {
                #expect(Bool(true))
            } else {
                Issue.record("Unexpected PluginError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
