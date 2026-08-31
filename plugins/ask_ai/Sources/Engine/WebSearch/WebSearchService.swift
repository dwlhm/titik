import Foundation
import TitikCore

/// A single organic web result returned by the search backend.
public struct WebSearchResult: Sendable, Equatable {
    public let title: String
    public let urlString: String
    public let snippet: String?

    public init(title: String, urlString: String, snippet: String? = nil) {
        self.title = title
        self.urlString = urlString
        self.snippet = snippet
    }
}

/// A single image result returned by the image search backend.
public struct WebImageResult: Sendable, Equatable {
    public let title: String
    public let urlString: String
    public let thumbnailURLString: String?
    public let sourcePageURLString: String?
    public let width: Int?
    public let height: Int?

    public init(
        title: String,
        urlString: String,
        thumbnailURLString: String? = nil,
        sourcePageURLString: String? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.title = title
        self.urlString = urlString
        self.thumbnailURLString = thumbnailURLString
        self.sourcePageURLString = sourcePageURLString
        self.width = width
        self.height = height
    }
}

/// Combined web and image results used to ground a user question.
public struct GroundedSearchResults: Sendable, Equatable {
    public let results: [WebSearchResult]
    public let images: [WebImageResult]

    public static let empty = GroundedSearchResults(results: [], images: [])

    public init(results: [WebSearchResult], images: [WebImageResult]) {
        self.results = results
        self.images = images
    }
}

/// Performs no-key web and image lookups against the DuckDuckGo HTML
/// endpoints. Search never throws: any internal failure is logged and
/// escaped as empty or partial results so the AI stream can proceed.
///
/// Test support: install a handler via `setStubHandler(_:)` to make
/// `search(_:)` return a canned `GroundedSearchResults` immediately,
/// bypassing all network access.
public actor WebSearchService {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private static let maxWebResults = 5
    private static let maxImageResults = 6

    private let session: URLSession
    private var stubHandler: (@Sendable (String) async -> GroundedSearchResults)?

    public init(session: URLSession = WebSearchService.makeSession()) {
        self.session = session
    }

    /// Installs (or removes, passing `nil`) the test stub consulted by
    /// `search(_:)` before any network call is made.
    public func setStubHandler(_ handler: (@Sendable (String) async -> GroundedSearchResults)?) {
        stubHandler = handler
    }

    /// Builds the default ephemeral session used by `init(session:)`.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Runs the web and image lookups concurrently. Never throws; failures
    /// are logged and degrade to empty or partial results. When a stub
    /// handler is installed, returns its result immediately instead.
    public func search(_ query: String) async -> GroundedSearchResults {
        if let stubHandler {
            return await stubHandler(query)
        }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            Logger.shared.warn("Web search skipped: empty query", subsystem: "Titik.AskAI")
            return .empty
        }

        async let webResults = fetchWebResults(cleanQuery)
        async let imageResults = fetchImageResults(cleanQuery)

        let web = await webResults
        let images = await imageResults
        return GroundedSearchResults(results: web, images: images)
    }

    // MARK: - Web Results

    private func fetchWebResults(_ query: String) async -> [WebSearchResult] {
        guard let url = makeURL(base: "https://html.duckduckgo.com/html/", query: query) else {
            Logger.shared.error("Web search: failed to build request URL", subsystem: "Titik.AskAI")
            return []
        }

        guard let html = await fetchString(url: url) else { return [] }
        return Self.parseWebResults(html: html)
    }

    /// Parses DuckDuckGo HTML results: `result__a` anchors paired with the
    /// following `result__snippet` elements.
    static func parseWebResults(html: String) -> [WebSearchResult] {
        let anchorRegex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*class="[^"]*result__a[^"]*"[^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let snippetRegex = try? NSRegularExpression(
            pattern: #"<\w+[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</\w+>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let hrefRegex = try? NSRegularExpression(pattern: #"href="([^"]*)""#, options: [.caseInsensitive])

        guard let anchorRegex, let hrefRegex else { return [] }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)

        var snippets: [String] = []
        if let snippetRegex {
            for match in snippetRegex.matches(in: html, options: [], range: fullRange) {
                guard let innerRange = Range(match.range(at: 1), in: html) else { continue }
                snippets.append(stripTags(String(html[innerRange])))
            }
        }

        var results: [WebSearchResult] = []
        let anchors = anchorRegex.matches(in: html, options: [], range: fullRange)
        for (index, match) in anchors.enumerated() where index < Self.maxWebResults {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let innerRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let attributes = String(html[attrsRange])
            let attrsNSRange = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
            guard let hrefMatch = hrefRegex.firstMatch(in: attributes, options: [], range: attrsNSRange),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: attributes) else {
                continue
            }

            let rawHref = String(attributes[hrefRange])
            let urlString = resolveRedirectURLString(rawHref)
            guard urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else {
                continue
            }

            let title = decodeEntities(stripTags(String(html[innerRange])))
            let snippet = index < snippets.count ? decodeEntities(snippets[index]) : nil

            results.append(WebSearchResult(
                title: title,
                urlString: urlString,
                snippet: snippet
            ))
            if results.count == Self.maxWebResults { break }
        }
        return results
    }

    /// DuckDuckGo wraps outbound links in `/l/?uddg=<percent-encoded>&rut=...`
    /// redirect URLs; decode the `uddg` parameter to recover the real URL.
    static func resolveRedirectURLString(_ href: String) -> String {
        guard let range = href.range(of: "uddg=") else { return href }
        let remainder = String(href[range.upperBound...])
        let encoded = remainder.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? remainder
        return encoded.removingPercentEncoding ?? encoded
    }

    // MARK: - Image Results

    private func fetchImageResults(_ query: String) async -> [WebImageResult] {
        var landingComponents = URLComponents(string: "https://duckduckgo.com/")
        landingComponents?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "iax", value: "images"),
            URLQueryItem(name: "ia", value: "images")
        ]
        guard let landingURL = landingComponents?.url else {
            Logger.shared.error("Image search: failed to build landing URL", subsystem: "Titik.AskAI")
            return []
        }

        guard let html = await fetchString(url: landingURL) else { return [] }
        guard let vqd = Self.extractVQD(from: html) else {
            Logger.shared.warn("Image search: vqd token missing, skipping images", subsystem: "Titik.AskAI")
            return []
        }

        var imageComponents = URLComponents(string: "https://duckduckgo.com/i.js")
        imageComponents?.queryItems = [
            URLQueryItem(name: "l", value: "wt-wt"),
            URLQueryItem(name: "o", value: "json"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "vqd", value: vqd),
            URLQueryItem(name: "f", value: ",,,"),
            URLQueryItem(name: "p", value: "1")
        ]
        guard let imageURL = imageComponents?.url else {
            Logger.shared.error("Image search: failed to build i.js URL", subsystem: "Titik.AskAI")
            return []
        }

        guard let data = await fetchData(url: imageURL) else { return [] }
        return Self.parseImageResults(data: data)
    }

    /// Extracts the `vqd` session token embedded in the DuckDuckGo page.
    static func extractVQD(from html: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"\bvqd=['"]?([\d-]+)['"]?"#, options: [])
        guard let regex else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[tokenRange])
    }

    /// Parses the JSON payload served by `duckduckgo.com/i.js`.
    static func parseImageResults(data: Data) -> [WebImageResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["results"] as? [[String: Any]] else {
            return []
        }

        var results: [WebImageResult] = []
        for entry in entries.prefix(Self.maxImageResults) {
            guard let urlString = entry["image"] as? String, !urlString.isEmpty else { continue }
            results.append(WebImageResult(
                title: entry["title"] as? String ?? "",
                urlString: urlString,
                thumbnailURLString: entry["thumbnail"] as? String,
                sourcePageURLString: entry["url"] as? String,
                width: entry["width"] as? Int,
                height: entry["height"] as? Int
            ))
            if results.count == Self.maxImageResults { break }
        }
        return results
    }

    // MARK: - Networking & Text Helpers

    private func makeURL(base: String, query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private func fetchString(url: URL) async -> String? {
        guard let data = await fetchData(url: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func fetchData(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Logger.shared.warn("Web search request failed for \(url.host ?? "?")", subsystem: "Titik.AskAI")
                return nil
            }
            return data
        } catch {
            Logger.shared.error("Web search request error: \(error.localizedDescription)", subsystem: "Titik.AskAI")
            return nil
        }
    }

    private static func stripTags(_ text: String) -> String {
        let regex = try? NSRegularExpression(pattern: #"<[^>]*>"#, options: [])
        guard let regex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#x27;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " ")
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode ampersands last so escaped entity names are not double-decoded.
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
    }
}
