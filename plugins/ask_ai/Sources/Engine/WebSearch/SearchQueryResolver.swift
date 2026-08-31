import Foundation

/// Decides whether a user query warrants a web search and produces the
/// effective search query (merging follow-ups with their prior turn).
public enum SearchQueryResolver {
    private static let stopPhrases: Set<String> = [
        "thanks", "thank you", "terima kasih", "makasih",
        "yes", "no", "ok", "oke", "sip", "lanjut", "continue",
        "got it", "siap", "baik", "hello", "hi", "hai"
    ]

    private static let maxPriorTurnLength = 120
    private static let maxQueryLength = 200

    /// Resolves the effective search query. Returns `nil` when the query is
    /// not informational and the search should be skipped.
    /// - Parameters:
    ///   - query: The normalized user query.
    ///   - hasPriorTurns: Whether this is a follow-up in an existing conversation.
    ///   - lastUserTurn: Content of the previous user turn, if any.
    ///   - lastAssistantTurn: Content of the previous assistant turn (reserved
    ///     for future use; not included in the query).
    public static func resolve(
        query: String,
        hasPriorTurns: Bool,
        lastUserTurn: String?,
        lastAssistantTurn: String?
    ) -> String? {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return nil }

        let wordCount = normalized.split(separator: " ").count
        if wordCount <= 2 { return nil }
        if stopPhrases.contains(normalized.lowercased()) { return nil }

        guard hasPriorTurns else { return normalized }

        guard let prior = lastUserTurn.map(normalize), !prior.isEmpty else {
            return normalized
        }

        let truncatedPrior = truncateToWholeWords(prior, limit: maxPriorTurnLength)
        let combined = truncatedPrior + " " + normalized
        return String(combined.prefix(maxQueryLength))
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func truncateToWholeWords(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var result = ""
        for word in text.split(separator: " ") {
            let candidate = result.isEmpty ? String(word) : result + " " + word
            if candidate.count > limit { break }
            result = candidate
        }
        return result.isEmpty ? String(text.prefix(limit)) : result
    }
}
