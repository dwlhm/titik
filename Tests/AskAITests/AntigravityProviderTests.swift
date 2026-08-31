import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

final class AntigravityMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        AntigravityMockURLProtocol.lock.lock()
        let handler = AntigravityMockURLProtocol.requestHandler
        AntigravityMockURLProtocol.lock.unlock()

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

@Suite("Google Antigravity Provider Tests", .serialized)
struct AntigravityProviderTests {

    private func makeMockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        AntigravityMockURLProtocol.lock.lock()
        AntigravityMockURLProtocol.requestHandler = handler
        AntigravityMockURLProtocol.lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AntigravityMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("Antigravity provider metadata confirms official support")
    func test_antigravityProvider_metadata() {
        let provider = AntigravityProvider()
        #expect(provider.id == "google-antigravity")
        #expect(provider.isOfficial == true)
        #expect(provider.isUntested == false)
        #expect(provider.displayName.contains("Google Antigravity"))
    }

    @Test("Antigravity provider throws unauthorized when subscriber token is missing")
    func test_antigravityProvider_missingToken_throwsUnauthorized() async {
        let provider = AntigravityProvider()
        let options = ProviderOptions(apiKey: nil, subscriberToken: nil)
        let messages = [ChatMessage(role: .user, content: "Hello Antigravity")]

        do {
            _ = try await provider.streamChat(messages: messages, options: options)
            Issue.record("Expected unauthorized error for missing token")
        } catch let error as PluginError {
            if case .unauthorized(let msg) = error {
                #expect(msg.contains("subscriber token is required"))
            } else {
                Issue.record("Unexpected PluginError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Antigravity provider authenticates with subscriber token and streams response")
    func test_antigravityProvider_validSubscription_authenticatesAndStreams() async throws {
        var authorizationHeaderSent: String? = nil
        var clientHeaderSent: String? = nil

        let ssePayload = """
        data: {"choices":[{"delta":{"content":"Connected to Google Antigravity bridge. "}}]}

        data: {"choices":[{"delta":{"content":"Your workspace is ready."}}]}

        data: [DONE]

        """

        let session = makeMockSession { req in
            authorizationHeaderSent = req.value(forHTTPHeaderField: "Authorization")
            clientHeaderSent = req.value(forHTTPHeaderField: "X-Antigravity-Client")

            let res = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (res, ssePayload.data(using: .utf8)!)
        }

        let provider = AntigravityProvider()
        let options = ProviderOptions(
            subscriberToken: "antigravity-subscriber-valid-jwt-token",
            session: session
        )
        let messages = [ChatMessage(role: .user, content: "Initialize subscription")]

        let stream = try await provider.streamChat(messages: messages, options: options)

        var textOutput = ""
        for try await chunk in stream {
            if case .text(let t) = chunk {
                textOutput += t
            }
        }

        #expect(authorizationHeaderSent == "Bearer antigravity-subscriber-valid-jwt-token")
        #expect(clientHeaderSent?.contains("Titik") == true)
        #expect(textOutput.contains("Connected to Google Antigravity bridge."))
        #expect(textOutput.contains("Your workspace is ready."))
    }

    @Test("Antigravity provider handles rate limit 429 with retry-after header")
    func test_antigravityProvider_rateLimit429_handlesRetryAfter() async throws {
        let session = makeMockSession { req in
            let res = HTTPURLResponse(
                url: req.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "10"]
            )!
            return (res, Data())
        }

        let provider = AntigravityProvider()
        let options = ProviderOptions(subscriberToken: "valid-sub-token", session: session)
        let stream = try await provider.streamChat(messages: [ChatMessage(role: .user, content: "ping")], options: options)

        var retrySeconds: TimeInterval = 0
        for try await chunk in stream {
            if case .rateLimit(let s) = chunk {
                retrySeconds = s
            }
        }

        #expect(retrySeconds == 10.0)
    }
}
