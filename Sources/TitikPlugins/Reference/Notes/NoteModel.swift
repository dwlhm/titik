import Foundation

/// Data model representing a single Note with YAML frontmatter metadata and Markdown body.
public struct Note: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date
    public var filename: String?

    public init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        filename: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.filename = filename
    }

    private static func makeFractionFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func makeStandardFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    public static func formatDate(_ date: Date) -> String {
        makeFractionFormatter().string(from: date)
    }

    public static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeFractionFormatter().date(from: trimmed) ?? makeStandardFormatter().date(from: trimmed)
    }

    /// Serializes the note to a Markdown string with YAML frontmatter.
    public func toMarkdown() -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(id.uuidString)")
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        lines.append("title: \"\(escapedTitle)\"")
        lines.append("isPinned: \(isPinned ? "true" : "false")")
        lines.append("createdAt: \(Self.formatDate(createdAt))")
        lines.append("updatedAt: \(Self.formatDate(updatedAt))")
        lines.append("lastOpenedAt: \(Self.formatDate(lastOpenedAt))")
        lines.append("---")
        lines.append("")
        lines.append(content)
        return lines.joined(separator: "\n")
    }

    /// Parses a Markdown string (with or without YAML frontmatter) into a `Note`.
    public static func fromMarkdown(_ raw: String, defaultTitle: String = "Untitled", filename: String? = nil) -> Note {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            // No frontmatter present
            let lines = raw.components(separatedBy: .newlines)
            var derivedTitle = defaultTitle
            if let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                var clean = firstNonEmpty.trimmingCharacters(in: .whitespaces)
                if clean.hasPrefix("#") {
                    clean = clean.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
                }
                if !clean.isEmpty {
                    derivedTitle = clean
                }
            }
            return Note(
                id: UUID(),
                title: derivedTitle,
                content: raw,
                isPinned: false,
                createdAt: Date(),
                updatedAt: Date(),
                lastOpenedAt: Date(),
                filename: filename
            )
        }

        let searchStartIndex = raw.index(raw.startIndex, offsetBy: 3)
        guard let closingRange = raw.range(of: "\n---", range: searchStartIndex..<raw.endIndex) else {
            return Note(
                id: UUID(),
                title: defaultTitle,
                content: raw,
                isPinned: false,
                createdAt: Date(),
                updatedAt: Date(),
                lastOpenedAt: Date(),
                filename: filename
            )
        }

        let frontmatterText = String(raw[searchStartIndex..<closingRange.lowerBound])
        var body = String(raw[closingRange.upperBound...])
        if body.hasPrefix("\r\n\r\n") {
            body.removeFirst(4)
        } else if body.hasPrefix("\n\n") {
            body.removeFirst(2)
        } else if body.hasPrefix("\r\n") {
            body.removeFirst(2)
        } else if body.hasPrefix("\n") {
            body.removeFirst()
        }

        var noteId: UUID?
        var noteTitle: String?
        var noteIsPinned = false
        var noteCreatedAt: Date?
        var noteUpdatedAt: Date?
        var noteLastOpenedAt: Date?

        for line in frontmatterText.components(separatedBy: .newlines) {
            let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
            guard !lineTrimmed.isEmpty, let colonIndex = lineTrimmed.firstIndex(of: ":") else { continue }
            let key = lineTrimmed[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            var val = lineTrimmed[lineTrimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val.removeFirst()
                val.removeLast()
                val = val.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            }

            switch key {
            case "id":
                noteId = UUID(uuidString: val)
            case "title":
                noteTitle = val
            case "ispinned":
                let lower = val.lowercased()
                noteIsPinned = (lower == "true" || lower == "yes" || lower == "1")
            case "createdat":
                noteCreatedAt = parseDate(val)
            case "updatedat":
                noteUpdatedAt = parseDate(val)
            case "lastopenedat":
                noteLastOpenedAt = parseDate(val)
            default:
                break
            }
        }

        let now = Date()
        return Note(
            id: noteId ?? UUID(),
            title: noteTitle ?? defaultTitle,
            content: body,
            isPinned: noteIsPinned,
            createdAt: noteCreatedAt ?? now,
            updatedAt: noteUpdatedAt ?? now,
            lastOpenedAt: noteLastOpenedAt ?? now,
            filename: filename
        )
    }
}

// MARK: - Todo Task Tracking & Helpers

public struct TodoStats: Equatable, Sendable {
    public let total: Int
    public let completed: Int
    public var pending: Int { total - completed }
    public var isAllDone: Bool { total > 0 && completed == total }
    public var progressFraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    public init(total: Int, completed: Int) {
        self.total = total
        self.completed = completed
    }
}

extension Note {
    private static let todoRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^\s*-\s+\[([ xX])\]"#)
    }()

    private static let uncheckedRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(\s*-\s+)\[ \]"#)
    }()

    private static let checkedRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(\s*-\s+)\[[xX]\]"#)
    }()

    /// Computes task checklist statistics for this note, or returns nil if no checkboxes exist.
    public var todoStats: TodoStats? {
        let lines = content.components(separatedBy: .newlines)
        var total = 0
        var completed = 0

        guard let regex = Self.todoRegex else { return nil }

        for line in lines {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = regex.firstMatch(in: line, options: [], range: range) {
                total += 1
                let markRange = match.range(at: 1)
                let mark = nsLine.substring(with: markRange)
                if mark == "x" || mark == "X" {
                    completed += 1
                }
            }
        }

        guard total > 0 else { return nil }
        return TodoStats(total: total, completed: completed)
    }

    /// Toggles a markdown checkbox in the given line:
    /// - If line contains `^\s*-\s+\[ \]`, replaces with `- [x]`.
    /// - If line contains `^\s*-\s+\[[xX]\]`, replaces with `- [ ]`.
    /// - If no checkbox, prepends `- [ ] `.
    public static func toggleCheckbox(in line: String) -> String {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        if let match = uncheckedRegex?.firstMatch(in: line, options: [], range: fullRange) {
            let prefixRange = match.range(at: 1)
            let prefix = nsLine.substring(with: prefixRange)
            let remainder = nsLine.substring(from: match.range.location + match.range.length)
            return "\(prefix)[x]\(remainder)"
        } else if let match = checkedRegex?.firstMatch(in: line, options: [], range: fullRange) {
            let prefixRange = match.range(at: 1)
            let prefix = nsLine.substring(with: prefixRange)
            let remainder = nsLine.substring(from: match.range.location + match.range.length)
            return "\(prefix)[ ]\(remainder)"
        } else {
            return "- [ ] " + line
        }
    }
}

