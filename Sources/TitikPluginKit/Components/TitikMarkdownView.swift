import SwiftUI
import AppKit
import TitikUI

public enum MarkdownBlock: Identifiable, Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String, code: String)
    case quote(text: String)
    case bulletItem(text: String, indent: Int)
    case numberedItem(number: Int, text: String, indent: Int)
    case table(header: [String], rows: [[String]])
    case image(url: String, alt: String)
    case math(text: String)
    case divider

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level):\(text.prefix(32))"
        case .paragraph(let text): return "p:\(text.prefix(32))"
        case .codeBlock(let lang, let code): return "code:\(lang):\(code.prefix(32))"
        case .quote(let text): return "q:\(text.prefix(32))"
        case .bulletItem(let text, let indent): return "b\(indent):\(text.prefix(32))"
        case .numberedItem(let num, let text, let indent): return "n\(num)i\(indent):\(text.prefix(32))"
        case .table(let header, let rows): return "t:\(header.joined(separator: " ").prefix(32)):\(rows.count)"
        case .image(let url, _): return "img:\(url.prefix(32))"
        case .math(let text): return "m:\(text.prefix(32))"
        case .divider: return "hr"
        }
    }
}

public struct MarkdownASTParser: Sendable {
    private static let imageLineRegex = try? NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)$"#
    )
    private static let tableSeparatorPattern = #"^\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?$"#

    private static func indentLevel(of line: String) -> Int {
        var spaces = 0
        var tabs = 0
        for character in line {
            if character == " " {
                spaces += 1
            } else if character == "\t" {
                tabs += 1
            } else {
                break
            }
        }
        return max(0, spaces / 4 + tabs)
    }

    public static func parse(_ rawText: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        // Sanitize raw dangerous HTML tags
        let sanitized = rawText
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)

        let lines = sanitized.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLang = ""
        var codeAccumulator: [String] = []
        var inMathBlock = false
        var mathAccumulator: [String] = []
        var paragraphAccumulator: [String] = []
        var tableAccumulator: [String] = []

        func flushParagraph() {
            if !paragraphAccumulator.isEmpty {
                let joined = paragraphAccumulator.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    blocks.append(.paragraph(text: joined))
                }
                paragraphAccumulator.removeAll()
            }
        }

        func splitTableRow(_ line: String) -> [String] {
            var content = line
            if content.hasPrefix("|") { content.removeFirst() }
            if content.hasSuffix("|") { content.removeLast() }
            return content.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }

        func flushTable() {
            guard !tableAccumulator.isEmpty else { return }
            let isWellFormed = tableAccumulator.count >= 2
                && tableAccumulator[1].range(of: tableSeparatorPattern, options: .regularExpression) != nil
            if isWellFormed {
                let header = splitTableRow(tableAccumulator[0])
                let rows = tableAccumulator.dropFirst(2).map(splitTableRow)
                blocks.append(.table(header: header, rows: rows))
            } else {
                for line in tableAccumulator {
                    paragraphAccumulator.append(line)
                }
            }
            tableAccumulator.removeAll()
        }

        for line in lines {
            let indent = indentLevel(of: line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block fence
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Close code block
                    blocks.append(.codeBlock(language: codeLang, code: codeAccumulator.joined(separator: "\n")))
                    codeAccumulator.removeAll()
                    codeLang = ""
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                codeAccumulator.append(line)
                continue
            }

            // Math block fence $$
            if trimmed == "$$" || trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count > 2 {
                if inMathBlock {
                    blocks.append(.math(text: mathAccumulator.joined(separator: "\n")))
                    mathAccumulator.removeAll()
                    inMathBlock = false
                } else if trimmed == "$$" {
                    flushParagraph()
                    inMathBlock = true
                } else {
                    flushParagraph()
                    let mathText = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.math(text: mathText))
                }
                continue
            }

            if inMathBlock {
                mathAccumulator.append(line)
                continue
            }

            // Tables: accumulate consecutive lines starting with |
            if trimmed.hasPrefix("|") {
                flushParagraph()
                tableAccumulator.append(trimmed)
                continue
            }
            flushTable()

            // Empty line flushes paragraph
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // Headings (longest hash prefix first)
            if trimmed.hasPrefix("###### ") {
                flushParagraph()
                blocks.append(.heading(level: 6, text: String(trimmed.dropFirst(7))))
                continue
            } else if trimmed.hasPrefix("##### ") {
                flushParagraph()
                blocks.append(.heading(level: 5, text: String(trimmed.dropFirst(6))))
                continue
            } else if trimmed.hasPrefix("#### ") {
                flushParagraph()
                blocks.append(.heading(level: 4, text: String(trimmed.dropFirst(5))))
                continue
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
                continue
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
                continue
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(text: String(trimmed.dropFirst(2))))
                continue
            }

            // Standalone image line
            if let regex = imageLineRegex, let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ) {
                flushParagraph()
                let alt = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
                let url = String(trimmed[Range(match.range(at: 2), in: trimmed)!])
                blocks.append(.image(url: url, alt: alt))
                continue
            }

            // Bullet list (with task-list and nesting support)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let text = String(trimmed.dropFirst(2))
                if text.hasPrefix("[ ] ") {
                    blocks.append(.bulletItem(text: "☐ " + String(text.dropFirst(4)), indent: indent))
                } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                    blocks.append(.bulletItem(text: "☑ " + String(text.dropFirst(4)), indent: indent))
                } else {
                    blocks.append(.bulletItem(text: text, indent: indent))
                }
                continue
            }

            // Numbered list (e.g. "1. ")
            if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(trimmed[match])
                let numStr = prefix.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                let num = Int(numStr) ?? 1
                let text = String(trimmed[match.upperBound...])
                blocks.append(.numberedItem(number: num, text: text, indent: indent))
                continue
            }

            // Standard line in paragraph
            paragraphAccumulator.append(trimmed)
        }

        // Auto-close open code fence safely
        if inCodeBlock {
            blocks.append(.codeBlock(language: codeLang, code: codeAccumulator.joined(separator: "\n")))
        }
        // Auto-close open math block safely
        if inMathBlock {
            blocks.append(.math(text: mathAccumulator.joined(separator: "\n")))
        }
        flushTable()
        flushParagraph()

        return blocks
    }
}

private struct AsyncImageView: View {
    let urlString: String
    let alt: String
    @State private var nsImage: NSImage?
    @State private var state: AsyncImageState = .loading

    private enum AsyncImageState { case loading, loaded, failed }

    var body: some View {
        Group {
            if state == .loaded, let img = nsImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .cornerRadius(8)
                    .clipped()
            } else if state == .failed {
                VStack(alignment: .center, spacing: 6) {
                    Image(systemName: "photo")
                        .foregroundColor(Color.white.opacity(0.4))
                        .font(.system(size: 24))
                    Text("!\([alt])(\(urlString))")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
        }
        .task {
            guard let url = URL(string: urlString) else { state = .failed; return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = NSImage(data: data) {
                    await MainActor.run { nsImage = img; state = .loaded }
                } else {
                    await MainActor.run { state = .failed }
                }
            } catch {
                await MainActor.run { state = .failed }
            }
        }
        .accessibilityLabel(alt)
    }
}

public struct TitikMarkdownView: View {
    public let text: String
    public let onCitationClick: ((Int) -> Void)?
    public let isStreaming: Bool

    public init(text: String, onCitationClick: ((Int) -> Void)? = nil, isStreaming: Bool = false) {
        self.text = text
        self.onCitationClick = onCitationClick
        self.isStreaming = isStreaming
    }

    nonisolated static func sanitizeStreamingTail(_ text: String) -> String {
        var result = text

        // Remove the last unclosed ** bold marker
        let doubleStarCount = result.components(separatedBy: "**").count - 1
        if doubleStarCount % 2 == 1, let range = result.range(of: "**", options: .backwards) {
            result.removeSubrange(range)
        }

        // Remove the last unmatched standalone * (excluding those inside ** pairs)
        let totalStarCount = result.components(separatedBy: "*").count - 1
        let pairedStarCount = (result.components(separatedBy: "**").count - 1) * 2
        let singleStarCount = totalStarCount - pairedStarCount
        if singleStarCount % 2 == 1 {
            for index in result.indices.reversed() where result[index] == "*" {
                let previousIndex = result.index(before: index)
                let nextIndex = result.index(after: index)
                let previousIsStar = index > result.startIndex && result[previousIndex] == "*"
                let nextIsStar = nextIndex < result.endIndex && result[nextIndex] == "*"
                if !previousIsStar && !nextIsStar {
                    result.remove(at: index)
                    break
                }
            }
        }

        // Remove the last unmatched backtick (the parser auto-closes fences)
        let backtickCount = result.components(separatedBy: "`").count - 1
        if backtickCount % 2 == 1, let range = result.range(of: "`", options: .backwards) {
            result.removeSubrange(range)
        }

        // Strip a partial inline link like [text](http
        if result.range(of: #"[^\[]*\[[^\]]*\]\([^)\s]*$"#, options: .regularExpression) != nil,
           let bracket = result.range(of: "[", options: .backwards) {
            result.removeSubrange(bracket.lowerBound...)
        }

        return result
    }

    public var body: some View {
        let rendered = isStreaming ? Self.sanitizeStreamingTail(text) : text
        let blocks = MarkdownASTParser.parse(rendered)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<blocks.count, id: \.self) { idx in
                renderBlock(blocks[idx])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(renderInlineMarkdown(content))
                .font(headingFont(for: level))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, level == 1 ? 8 : 4)

        case .paragraph(let content):
            Text(renderInlineMarkdown(content))
                .font(.system(size: 13.5, weight: .regular))
                .foregroundColor(Color.white.opacity(0.92))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let lang, let code):
            VStack(alignment: .leading, spacing: 4) {
                if !lang.isEmpty {
                    HStack {
                        Text(lang.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.9, blue: 1.0))
                        .padding(10)
                }
            }
            .background(Color.black.opacity(0.45))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 3)
                Text(renderInlineMarkdown(content))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.8))
                    .italic()
            }
            .padding(.vertical, 2)

        case .bulletItem(let content, let indent):
            let isTask = content.hasPrefix("☑ ") || content.hasPrefix("☐ ")
            let glyph = isTask ? String(content.prefix(1)) : "•"
            let itemText = isTask ? String(content.dropFirst(2)) : content
            HStack(alignment: .top, spacing: 6) {
                Text(glyph)
                    .foregroundColor(Color.white.opacity(0.6))
                    .font(.system(size: 13, weight: .bold))
                Text(renderInlineMarkdown(itemText))
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.92))
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .numberedItem(let num, let content, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .foregroundColor(Color.white.opacity(0.6))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(renderInlineMarkdown(content))
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.92))
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .table(let header, let rows):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<header.count, id: \.self) { col in
                        Text(renderInlineMarkdown(header[col]))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        if col < header.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 1)
                        }
                    }
                }
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(0..<rows[rowIndex].count, id: \.self) { col in
                            Text(renderInlineMarkdown(rows[rowIndex][col]))
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            if col < rows[rowIndex].count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 1)
                            }
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

        case .image(let url, let alt):
            AsyncImageView(urlString: url, alt: alt)

        case .math(let content):
            HStack {
                Spacer()
                Text(content)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.5))
                    .padding(8)
                Spacer()
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)

        case .divider:
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.vertical, 4)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 18, weight: .bold)
        case 2: return .system(size: 15.5, weight: .bold)
        case 3: return .system(size: 14, weight: .semibold)
        case 4: return .system(size: 13, weight: .semibold)
        default: return .system(size: 12.5, weight: .semibold)
        }
    }

    private func renderInlineMarkdown(_ input: String) -> AttributedString {
        // Step 1: Convert citation markers [N] or [^N] into bold **[N]**
        var text = input
        if let regex = try? NSRegularExpression(pattern: #"\[\^?(\d+)\]"#, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "**[$1]**")
        }

        let nsAttr = NSMutableAttributedString(string: text)
        let baseFont = NSFont.systemFont(ofSize: 13.5)
        nsAttr.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: nsAttr.length))

        // Step 2: Define patterns in priority order (code spans first to protect inner content)
        let codeAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)]
        let boldAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13.5)]
        let italicFont: NSFont = {
            let descriptor = NSFont.systemFont(ofSize: 13.5).fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: 13.5) ?? NSFont.systemFont(ofSize: 13.5)
        }()
        let italicAttrs: [NSAttributedString.Key: Any] = [.font: italicFont]
        let linkAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let strikeAttrs: [NSAttributedString.Key: Any] = [.strikethroughStyle: NSUnderlineStyle.single.rawValue]

        let patterns: [(regex: NSRegularExpression, attrs: [NSAttributedString.Key: Any])] = [
            (try! NSRegularExpression(pattern: #"`([^`]+)`"#), codeAttrs),
            (try! NSRegularExpression(pattern: #"\*\*([^\*]+)\*\*"#), boldAttrs),
            (try! NSRegularExpression(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#), italicAttrs),
            (try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#), linkAttrs),
            (try! NSRegularExpression(pattern: #"~~([^~]+)~~"#), strikeAttrs),
        ]

        // Step 3: Collect all matches across all patterns
        var allMatches: [(fullRange: NSRange, contentRange: NSRange, patternIndex: Int)] = []
        for (index, pattern) in patterns.enumerated() {
            pattern.regex.enumerateMatches(in: text, range: NSRange(location: 0, length: text.utf16.count)) { result, _, _ in
                guard let result = result else { return }
                allMatches.append((result.range, result.range(at: 1), index))
            }
        }

        // Step 4: Sort by start position, then filter out overlapping matches
        allMatches.sort { $0.fullRange.location < $1.fullRange.location }

        var filtered: [(NSRange, NSRange, Int)] = []
        var lastEnd = 0
        for match in allMatches {
            if match.fullRange.location >= lastEnd {
                filtered.append(match)
                lastEnd = match.fullRange.location + match.fullRange.length
            }
        }

        // Step 5: Build ranges list (full range, content range, attributes)
        struct AttrRange {
            let fullRange: NSRange
            let contentRange: NSRange
            let attributes: [NSAttributedString.Key: Any]
        }
        let ranges: [AttrRange] = filtered.map { match in
            AttrRange(fullRange: match.0, contentRange: match.1, attributes: patterns[match.2].attrs)
        }

        // Step 6: Process from back to front so index shifts don't affect earlier matches
        let sortedRanges = ranges.sorted { $0.fullRange.location > $1.fullRange.location }
        for r in sortedRanges {
            nsAttr.addAttributes(r.attributes, range: r.contentRange)
            // Delete closing delimiter first, then opening (reverse order preserves earlier indices)
            nsAttr.deleteCharacters(in: NSRange(location: r.fullRange.location + r.fullRange.length - 2, length: 2))
            nsAttr.deleteCharacters(in: NSRange(location: r.fullRange.location, length: 2))
        }

        return AttributedString(nsAttr)
    }
}
