import Foundation

public struct CitationSource: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let index: Int
    public let title: String
    public let urlString: String
    public let snippet: String?
    public let faviconURLString: String?

    public init(
        id: String = UUID().uuidString,
        index: Int,
        title: String,
        urlString: String,
        snippet: String? = nil,
        faviconURLString: String? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.urlString = urlString
        self.snippet = snippet
        self.faviconURLString = faviconURLString
    }

    public var domain: String {
        guard let url = URL(string: urlString), let host = url.host else {
            return ""
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
