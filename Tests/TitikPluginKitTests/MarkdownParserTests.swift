import Testing
@testable import TitikPluginKit

@Suite("Markdown Parser Tests")
struct MarkdownParserTests {

    @Test("Pipe table with header, separator, and rows parses into a single table block")
    func test_tableParsing() {
        let markdown = """
        | Name | Value |
        | ---- | ----- |
        | alpha | 1 |
        | beta | 2 |
        """

        let blocks = MarkdownASTParser.parse(markdown)

        #expect(blocks.count == 1)
        guard case .table(let header, let rows) = blocks[0] else {
            Issue.record("Expected a table block, got \(blocks)")
            return
        }
        #expect(header == ["Name", "Value"])
        #expect(rows.count == 2)
        #expect(rows[0] == ["alpha", "1"])
        #expect(rows[1] == ["beta", "2"])
    }

    @Test("Malformed table without a separator degrades into a paragraph")
    func test_malformedTableDegradesToParagraph() {
        let markdown = """
        | just | one | line |
        """

        let blocks = MarkdownASTParser.parse(markdown)

        #expect(blocks.count == 1)
        guard case .paragraph(let text) = blocks[0] else {
            Issue.record("Expected a paragraph block, got \(blocks)")
            return
        }
        #expect(text.contains("just"))
    }

    @Test("Heading levels 4 through 6 parse with the correct level")
    func test_deepHeadingLevels() {
        let blocks = MarkdownASTParser.parse("#### Section\n##### Sub\n###### Deep")

        #expect(blocks.count == 3)
        guard case .heading(let level4, let text4) = blocks[0] else {
            Issue.record("Expected a heading block at index 0, got \(blocks)")
            return
        }
        #expect(level4 == 4)
        #expect(text4 == "Section")
        guard case .heading(let level5, let text5) = blocks[1] else {
            Issue.record("Expected a heading block at index 1, got \(blocks)")
            return
        }
        #expect(level5 == 5)
        #expect(text5 == "Sub")
        guard case .heading(let level6, let text6) = blocks[2] else {
            Issue.record("Expected a heading block at index 2, got \(blocks)")
            return
        }
        #expect(level6 == 6)
        #expect(text6 == "Deep")
    }

    @Test("Checked task list item parses as a bullet with the checked glyph")
    func test_taskListItemChecked() {
        let blocks = MarkdownASTParser.parse("- [x] done")

        #expect(blocks.count == 1)
        guard case .bulletItem(let text, let indent) = blocks[0] else {
            Issue.record("Expected a bullet item block, got \(blocks)")
            return
        }
        #expect(text == "☑ done")
        #expect(indent == 0)
    }

    @Test("Unchecked task list item parses with the unchecked glyph")
    func test_taskListItemUnchecked() {
        let blocks = MarkdownASTParser.parse("- [ ] pending work")

        #expect(blocks.count == 1)
        guard case .bulletItem(let text, _) = blocks[0] else {
            Issue.record("Expected a bullet item block, got \(blocks)")
            return
        }
        #expect(text == "☐ pending work")
    }

    @Test("Four-space-indented bullet parses with indent level 1")
    func test_nestedBulletIndent() {
        let markdown = "    - nested"

        let blocks = MarkdownASTParser.parse(markdown)

        #expect(blocks.count == 1)
        guard case .bulletItem(let text, let indent) = blocks[0] else {
            Issue.record("Expected a bullet item block, got \(blocks)")
            return
        }
        #expect(text == "nested")
        #expect(indent == 1)
    }

    @Test("Standalone image line parses into an image block")
    func test_imageParsing() {
        let blocks = MarkdownASTParser.parse("![alt](https://example.com/x.png)")

        #expect(blocks.count == 1)
        guard case .image(let url, let alt) = blocks[0] else {
            Issue.record("Expected an image block, got \(blocks)")
            return
        }
        #expect(url == "https://example.com/x.png")
        #expect(alt == "alt")
    }

    @Test("Streaming sanitizer removes the last unclosed bold marker")
    func test_sanitizerRemovesUnclosedBold() {
        let sanitized = TitikMarkdownView.sanitizeStreamingTail("hello **bold")

        #expect(!sanitized.contains("**"))
    }

    @Test("Streaming sanitizer strips a partial inline link at the tail")
    func test_sanitizerStripsPartialLink() {
        let sanitized = TitikMarkdownView.sanitizeStreamingTail("see [text](http://x")

        #expect(sanitized == "see ")
    }

    @Test("Streaming sanitizer leaves balanced text untouched")
    func test_sanitizerLeavesBalancedTextUntouched() {
        let input = "plain text with **bold** and [link](https://example.com)"

        let sanitized = TitikMarkdownView.sanitizeStreamingTail(input)

        #expect(sanitized == input)
    }
}
