import Foundation

/// Renders grounded search results into the WEB CONTEXT block appended to
/// the user turn so the model can cite sources and embed images.
public enum GroundedContextBuilder {
    private static let maxSources = 5
    private static let maxImages = 6
    private static let maxSnippetLength = 200

    /// Builds the WEB CONTEXT block. Returns `nil` when there is nothing to
    /// ground on (both lists empty), signalling that no context should be
    /// injected into the prompt.
    public static func buildContext(from results: GroundedSearchResults) -> String? {
        guard !results.results.isEmpty || !results.images.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("---")
        lines.append("WEB CONTEXT — live search results retrieved for this question. You may cite these sources and reference these images using the token format defined in your instructions.")

        if !results.results.isEmpty {
            lines.append("Web sources:")
            for (index, result) in results.results.prefix(maxSources).enumerated() {
                lines.append("[\(index + 1)] \(result.title) — \(result.urlString)")
                if let snippet = result.snippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                    lines.append("    \(String(snippet.prefix(maxSnippetLength)))")
                }
            }
        }

        if !results.images.isEmpty {
            lines.append("Supporting images (image URLs):")
            for image in results.images.prefix(maxImages) {
                lines.append("- \(image.title): \(image.urlString)")
            }
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }
}
