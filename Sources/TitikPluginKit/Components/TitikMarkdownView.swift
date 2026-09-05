import Foundation
import SwiftUI
import AppKit
import TitikUI
@_exported import Markdown

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

    public static func parse(_ rawText: String) -> [MarkdownBlock] {
        // Sanitize raw dangerous HTML tags
        let sanitized = rawText
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)

        let document = Document(parsing: sanitized)
        var blocks: [MarkdownBlock] = []

        func parseList(list: ListItemContainer, indent: Int) -> [MarkdownBlock] {
            var listBlocks: [MarkdownBlock] = []
            var currentIndex = (list as? OrderedList).map { Int($0.startIndex) } ?? 1

            for item in list.listItems {
                var itemTextParts: [String] = []
                var nestedContainers: [ListItemContainer] = []

                for child in item.children {
                    if let p = child as? Paragraph {
                        let text = p.format().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            itemTextParts.append(text)
                        }
                    } else if let nestedList = child as? ListItemContainer {
                        nestedContainers.append(nestedList)
                    }
                }

                let rawItemText = itemTextParts.joined(separator: " ")
                let formattedText: String
                if item.checkbox == .checked {
                    formattedText = "☑ " + rawItemText
                } else if item.checkbox == .unchecked {
                    formattedText = "☐ " + rawItemText
                } else {
                    formattedText = rawItemText
                }

                if list is OrderedList {
                    listBlocks.append(.numberedItem(number: currentIndex, text: formattedText, indent: indent))
                    currentIndex += 1
                } else {
                    listBlocks.append(.bulletItem(text: formattedText, indent: indent))
                }

                for nested in nestedContainers {
                    listBlocks.append(contentsOf: parseList(list: nested, indent: indent + 1))
                }
            }

            return listBlocks
        }

        for child in document.children {
            switch child {
            case let h as Heading:
                blocks.append(.heading(level: h.level, text: h.plainText))

            case let p as Paragraph:
                // Check if paragraph is a single image
                if p.childCount == 1, let img = p.child(at: 0) as? Markdown.Image {
                    blocks.append(.image(url: img.source ?? "", alt: img.plainText))
                    continue
                }

                let trimmed = p.plainText.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check image regex fallback
                if let regex = imageLineRegex,
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let altRange = Range(match.range(at: 1), in: trimmed),
                   let urlRange = Range(match.range(at: 2), in: trimmed) {
                    blocks.append(.image(url: String(trimmed[urlRange]), alt: String(trimmed[altRange])))
                    continue
                }

                let text = p.format().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                // Check for LaTeX math blocks delimited by $$
                if text.contains("$$") {
                    let parts = text.components(separatedBy: "$$")
                    if parts.count >= 3 && parts.count % 2 == 1 {
                        for (idx, part) in parts.enumerated() {
                            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedPart.isEmpty else { continue }
                            if idx % 2 == 1 {
                                blocks.append(.math(text: trimmedPart))
                            } else {
                                blocks.append(.paragraph(text: trimmedPart))
                            }
                        }
                        continue
                    }
                }

                blocks.append(.paragraph(text: text))

            case let codeBlock as CodeBlock:
                let lang = codeBlock.language ?? ""
                let code = codeBlock.code

                // Check if this was an indented bullet item parsed as an indented code block
                if lang.isEmpty && (code.hasPrefix("- ") || code.hasPrefix("* ")) {
                    let indent = max(1, ((codeBlock.range?.lowerBound.column ?? 5) - 1) / 4)
                    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = String(trimmedCode.dropFirst(2))
                    if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                        blocks.append(.bulletItem(text: "☑ " + String(content.dropFirst(4)), indent: indent))
                    } else if content.hasPrefix("[ ] ") {
                        blocks.append(.bulletItem(text: "☐ " + String(content.dropFirst(4)), indent: indent))
                    } else {
                        blocks.append(.bulletItem(text: content, indent: indent))
                    }
                    continue
                }

                blocks.append(.codeBlock(language: lang, code: code))

            case let quote as BlockQuote:
                var quoteParts: [String] = []
                for qChild in quote.children {
                    if let p = qChild as? Paragraph {
                        quoteParts.append(p.format().trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        quoteParts.append(qChild.format().trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                var quoteText = quoteParts.joined(separator: "\n\n")
                if quoteText.isEmpty {
                    quoteText = quote.format().trimmingCharacters(in: .whitespacesAndNewlines)
                    if quoteText.hasPrefix("> ") {
                        quoteText = String(quoteText.dropFirst(2))
                    } else if quoteText.hasPrefix(">") {
                        quoteText = String(quoteText.dropFirst(1))
                    }
                }
                blocks.append(.quote(text: quoteText))

            case let table as Markdown.Table:
                let header = Array(table.head.cells.map { $0.plainText.trimmingCharacters(in: .whitespaces) })
                let rows = Array(table.body.rows.map { row in
                    Array(row.cells.map { $0.plainText.trimmingCharacters(in: .whitespaces) })
                })
                blocks.append(.table(header: header, rows: rows))

            case let list as UnorderedList:
                blocks.append(contentsOf: parseList(list: list, indent: 0))

            case let list as OrderedList:
                blocks.append(contentsOf: parseList(list: list, indent: 0))

            case is ThematicBreak:
                blocks.append(.divider)

            default:
                let text = child.format().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    blocks.append(.paragraph(text: text))
                }
            }
        }

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
                    Text("![\(alt)](\(urlString))")
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

        // Step 2: Safe native markdown parsing using AttributedString
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }

        return AttributedString(text)
    }
}
