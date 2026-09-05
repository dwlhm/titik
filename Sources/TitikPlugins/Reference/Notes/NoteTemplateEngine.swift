import Foundation

/// Represents a parsed CLI-style template command: `/template --title <val> --<param> <val>`.
public struct ParsedTemplateCommand: Equatable, Sendable {
    public let templateName: String
    public let title: String?
    public let parameters: [String: String]

    public init(templateName: String, title: String? = nil, parameters: [String: String] = [:]) {
        self.templateName = templateName
        self.title = title
        self.parameters = parameters
    }
}

/// Template engine responsible for parsing template commands, flag tokenization, and placeholder substitution.
public final class NoteTemplateEngine: Sendable {
    public let storage: NoteStorage

    public init(storage: NoteStorage) {
        self.storage = storage
    }

    /// Parses a raw command string into a `ParsedTemplateCommand`.
    /// Accepts forms like:
    /// - `!note /meeting --title "Sprint Sync" --b "Discuss roadmap"`
    /// - `/meeting --title "Sprint Sync" --b "Discuss roadmap"`
    /// - `/meeting --title Sprint Sync --b Discuss roadmap`
    public static func parseCommand(input: String) -> ParsedTemplateCommand? {
        var str = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if str.hasPrefix("!notes ") {
            str = String(str.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("!note ") {
            str = String(str.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("!notes") {
            str = String(str.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("!note") {
            str = String(str.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("!n ") {
            str = String(str.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("!n") {
            str = String(str.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        guard str.hasPrefix("/") else { return nil }
        str.removeFirst() // Drop '/'

        let parts = str.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let namePart = parts.first, !namePart.isEmpty else { return nil }
        let templateName = String(namePart)

        let flagsString = parts.count > 1 ? String(parts[1]) : ""
        let (extractedTitle, parameters) = parseFlags(flagsString)

        return ParsedTemplateCommand(
            templateName: templateName,
            title: extractedTitle,
            parameters: parameters
        )
    }

    /// Tokenizes CLI-style flags: `--<key> <value>` with support for quotes and unquoted values.
    public static func parseFlags(_ flagsString: String) -> (title: String?, parameters: [String: String]) {
        guard !flagsString.isEmpty else { return (nil, [:]) }

        let pattern = #"--([a-zA-Z0-9_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (nil, [:]) }

        let nsString = flagsString as NSString
        let matches = regex.matches(in: flagsString, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return (nil, [:]) }

        var title: String?
        var parameters: [String: String] = [:]

        for i in 0..<matches.count {
            let match = matches[i]
            let keyRange = match.range(at: 1)
            let key = nsString.substring(with: keyRange)

            let valStart = match.range.location + match.range.length
            let valEnd: Int
            if i + 1 < matches.count {
                valEnd = matches[i + 1].range.location
            } else {
                valEnd = nsString.length
            }

            var val = nsString.substring(with: NSRange(location: valStart, length: valEnd - valStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove enclosing quotes if present
            if (val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2) ||
               (val.hasPrefix("'") && val.hasSuffix("'") && val.count >= 2) {
                val.removeFirst()
                val.removeLast()
            }

            parameters[key] = val
            if key.lowercased() == "title" {
                title = val
            }
        }

        return (title, parameters)
    }

    /// Resolves the raw template content (from storage custom templates or built-in defaults).
    public func resolveTemplateContent(templateName: String) -> String {
        if let custom = storage.getTemplate(named: templateName) {
            return custom
        }

        switch templateName.lowercased() {
        case "meeting":
            return """
            # {{title}}

            **Date**: {{date}} {{time}}

            ## Attendees
            - 

            ## Agenda & Discussion
            {{b}}

            ## Action Items
            - [ ] 
            """
        case "daily", "standup":
            return """
            # Daily Standup - {{date}}

            ## Yesterday
            - 

            ## Today
            {{b}}

            ## Blockers
            - None
            """
        case "todo", "task":
            return """
            # {{title}}

            - [ ] {{b}}
            """
        default:
            return """
            # {{title}}

            {{b}}
            """
        }
    }

    /// Applies parameter substitutions (`{{title}}`, `{{date}}`, `{{time}}`, `{{key}}`) to template body.
    public static func substitutePlaceholders(
        template: String,
        title: String,
        parameters: [String: String],
        now: Date = Date()
    ) -> String {
        var result = template

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: now)

        result = result.replacingOccurrences(of: "{{title}}", with: title)
        result = result.replacingOccurrences(of: "{{date}}", with: dateString)
        result = result.replacingOccurrences(of: "{{time}}", with: timeString)
        result = result.replacingOccurrences(of: "{{datetime}}", with: "\(dateString) \(timeString)")

        for (key, val) in parameters {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: val)
        }

        // Clean up remaining empty {{b}} or similar placeholders if not provided
        result = result.replacingOccurrences(of: "{{b}}", with: "")

        return result
    }

    /// Parses a template command string, substitutes placeholders, creates the Note, and saves it.
    @discardableResult
    public func createNoteFromCommand(input: String) -> Note? {
        guard let parsed = Self.parseCommand(input: input) else { return nil }

        let resolvedTitle: String
        if let customTitle = parsed.title, !customTitle.isEmpty {
            resolvedTitle = customTitle
        } else {
            resolvedTitle = parsed.templateName.capitalized
        }

        let rawTemplate = resolveTemplateContent(templateName: parsed.templateName)
        let substituted = Self.substitutePlaceholders(
            template: rawTemplate,
            title: resolvedTitle,
            parameters: parsed.parameters
        )

        let now = Date()
        let note = Note(
            id: UUID(),
            title: resolvedTitle,
            content: substituted,
            isPinned: false,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now
        )

        storage.saveNote(note)
        return note
    }
}
