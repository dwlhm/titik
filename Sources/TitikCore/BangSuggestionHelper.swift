import Foundation

public enum BangSuggestionHelper {
    public static let canonicalBangs: [String] = [
        "!emoji",
        "!file",
        "!app",
        "!clip",
        "!cmd",
        "!calc"
    ]

    public static func suggestionSuffix(for query: String, pluginBangs: [String] = []) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!"), !trimmed.contains(" ") else {
            return nil
        }
        let lower = trimmed.lowercased()
        guard lower.count > 1 else {
            return nil
        }
        let allBangs = canonicalBangs + pluginBangs
        for bang in allBangs {
            let normalized = bang.hasPrefix("!") ? bang.lowercased() : ("!" + bang.lowercased())
            if normalized.hasPrefix(lower) && normalized.count > lower.count {
                let suffixIndex = normalized.index(normalized.startIndex, offsetBy: lower.count)
                return String(normalized[suffixIndex...])
            }
        }
        return nil
    }

    public static func fullSuggestion(for query: String, pluginBangs: [String] = []) -> String? {
        guard let suffix = suggestionSuffix(for: query, pluginBangs: pluginBangs) else { return nil }
        return query + suffix
    }
}
