import Foundation
import TitikPluginKit

public struct ProviderOptions: Sendable {
    public var apiKey: String?
    public var subscriberToken: String?
    public var endpoint: URL?
    public var model: String?
    public var temperature: Double?
    public var maxTokens: Int?
    public var session: URLSession?

    public init(
        apiKey: String? = nil,
        subscriberToken: String? = nil,
        endpoint: URL? = nil,
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        session: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.subscriberToken = subscriberToken
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.session = session
    }
}

public enum ProviderStreamChunk: Sendable, Equatable {
    case text(String)
    case media(MediaAsset)
    case citation(CitationSource)
    case rateLimit(retryAfter: TimeInterval)
    case done
}

public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isOfficial: Bool { get }
    var isUntested: Bool { get }

    func streamChat(
        messages: [ChatMessage],
        options: ProviderOptions
    ) async throws -> AsyncThrowingStream<ProviderStreamChunk, Error>
}
