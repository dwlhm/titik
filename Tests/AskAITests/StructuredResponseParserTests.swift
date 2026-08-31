import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

@Suite("Structured Response & SSE Parser Tests")
struct StructuredResponseParserTests {

    @Test("Standard SSE chunks accumulate text correctly")
    func test_sseParser_standardChunks_accumulatesTextCorrectly() {
        let parser = StructuredResponseParser()

        let chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello \"}}]}\n\n"
        let chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\"world of \"}}]}\n\n"
        let chunk3 = "data: {\"choices\":[{\"delta\":{\"content\":\"Titik!\"}}]}\n\n"

        let out1 = parser.processStringChunk(chunk1)
        let out2 = parser.processStringChunk(chunk2)
        let out3 = parser.processStringChunk(chunk3)

        let allText = (out1.textDeltas + out2.textDeltas + out3.textDeltas).joined()
        #expect(allText == "Hello world of Titik!")
    }

    @Test("Responses and Anthropic typed SSE events produce text and completion")
    func test_sseParser_typedProviderEvents() {
        let parser = StructuredResponseParser()
        let responses = parser.processStringChunk("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Responses \"}\n")
        let messages = parser.processStringChunk("data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"and Messages\"}}\n")
        let done = parser.processStringChunk("data: {\"type\":\"message_stop\"}\n")

        #expect((responses.textDeltas + messages.textDeltas).joined() == "Responses and Messages")
        #expect(done.isDone)
    }

    @Test("Multibyte UTF-8 code point split across network chunk boundaries reconstructs cleanly")
    func test_sseParser_multibyteUTF8SplitAcrossChunks_reconstructsCleanly() {
        let parser = StructuredResponseParser()

        // 🚀 emoji is 4 bytes: [0xF0, 0x9F, 0x9A, 0x80]
        // "data: Fast 🚀 App\n\n"
        let prefix = "data: Fast ".data(using: .utf8)!
        let emojiBytes = Data([0xF0, 0x9F, 0x9A, 0x80])
        let suffix = " App\n\n".data(using: .utf8)!

        // Chunk 1 has prefix + first 2 bytes of emoji
        var chunk1 = prefix
        chunk1.append(emojiBytes.prefix(2))

        // Chunk 2 has remaining 2 bytes of emoji + suffix
        var chunk2 = emojiBytes.suffix(2)
        chunk2.append(suffix)

        let out1 = parser.processChunk(chunk1)
        let out2 = parser.processChunk(chunk2)

        let combined = (out1.textDeltas + out2.textDeltas).joined()
        #expect(combined == "Fast 🚀 App")
    }

    @Test("Empty lines and ping/comment lines are ignored silently")
    func test_sseParser_emptyLinesAndPingComments_ignoredSilently() {
        let parser = StructuredResponseParser()

        let payload = """
        : ping
        : keepalive 12345

        data: {\"choices\":[{\"delta\":{\"content\":\"Valid content\"}}]}

        : another comment

        data: [DONE]
        """

        let out = parser.processStringChunk(payload)
        let flushed = parser.flush()

        let allText = (out.textDeltas + flushed.textDeltas).joined()
        #expect(allText == "Valid content")
        #expect(flushed.isDone == true || out.isDone == true)
    }

    @Test("Inline media tokens are extracted into MediaAsset objects and cleaned from body")
    func test_sseParser_inlineMediaTokens_extractsMediaAssets() {
        let parser = StructuredResponseParser()

        let rawText = "Here is a diagram: [[media:diagram:title=Architecture&content=A-->B]] and an image [[media:image:url=https://example.com/demo.png&title=Demo+Image]]."

        let (cleaned, media, _) = parser.extractInlineTokens(from: rawText)

        #expect(!cleaned.contains("[[media:"))
        #expect(cleaned.contains("Here is a diagram:"))
        #expect(cleaned.contains("and an image"))

        #expect(media.count == 2)
        let diagram = media.first { $0.type == .diagram }
        #expect(diagram?.title == "Architecture")
        #expect(diagram?.content == "A-->B")

        let image = media.first { $0.type == .image }
        #expect(image?.title == "Demo Image")
        #expect(image?.urlString == "https://example.com/demo.png")
    }

    @Test("Inline citations and footnote links are extracted and numbered")
    func test_sseParser_inlineCitations_extractsAndNumbersFootnotes() {
        let parser = StructuredResponseParser()

        let rawText = """
        According to research[[cite:index=1&url=https://arxiv.org/abs/1234&title=Attention+Paper]], transformers scale well.
        Other sources confirm this[^2].

        [^2]: https://openai.com/research "OpenAI Scaling Laws"
        """

        let (cleaned, _, citations) = parser.extractInlineTokens(from: rawText)

        #expect(cleaned.contains("[1]"))
        #expect(!cleaned.contains("[[cite:"))

        #expect(citations.count == 2)
        let cite1 = citations.first { $0.index == 1 }
        #expect(cite1?.urlString == "https://arxiv.org/abs/1234")
        #expect(cite1?.title == "Attention Paper")

        let cite2 = citations.first { $0.index == 2 }
        #expect(cite2?.urlString == "https://openai.com/research")
        #expect(cite2?.title == "OpenAI Scaling Laws")
    }

    @Test("AIFormatPrompt example tokens round-trip through inline token extraction")
    func test_parser_aiFormatPromptExampleTokens_roundTrip() {
        let parser = StructuredResponseParser()

        #expect(AIFormatPrompt.text.contains("[[cite:index=1&url=https://example.com/article&title=Example Article]]"))
        #expect(AIFormatPrompt.text.contains("[[media:image:url=https://example.com/photo.jpg&title=Example Photo]]"))

        let rawText = """
        Quick summary of the findings. See [[cite:index=1&url=https://example.com/article&title=Example Article]] for details.
        [[media:image:url=https://example.com/photo.jpg&title=Example Photo]]
        """

        let (cleaned, media, citations) = parser.extractInlineTokens(from: rawText)

        #expect(citations.count == 1)
        #expect(citations.first?.index == 1)
        #expect(citations.first?.urlString == "https://example.com/article")
        #expect(citations.first?.title == "Example Article")

        #expect(media.count == 1)
        #expect(media.first?.type == .image)
        #expect(media.first?.urlString == "https://example.com/photo.jpg")
        #expect(media.first?.title == "Example Photo")

        #expect(!cleaned.contains("[[cite:"))
        #expect(!cleaned.contains("[[media:"))
        #expect(cleaned.contains("[1]"))
    }

    @Test("Plain text error and HTML payloads are detected and emitted as errors")
    func test_sseParser_detectsPlainTextAndHTMLErrors() {
        let parser = StructuredResponseParser()

        let out1 = parser.processStringChunk("404 Not Found\n")
        #expect(out1.textDeltas.first?.hasPrefix("Error: Server returned '404 Not Found'") == true)

        let out2 = parser.processStringChunk("Cannot POST /v1/chat\n")
        #expect(out2.textDeltas.first?.hasPrefix("Error: Server returned 'Cannot POST /v1/chat'") == true)

        let out3 = parser.processStringChunk("<!DOCTYPE html><html><body>Error</body></html>\n")
        #expect(out3.textDeltas.first?.hasPrefix("Error: Server returned '<!DOCTYPE") == true)
    }
}
