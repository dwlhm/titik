import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

@Suite("Web Search Service Tests")
struct WebSearchServiceTests {

    @Test("parseWebResults decodes uddg redirect URLs, strips tags, and extracts snippets")
    func test_parseWebResults_redirectTagsAndSnippet() {
        let html = """
        <div class="result">
        <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Farticle&rut=abc123">Example <b>Article</b></a>
        <a class="result__snippet" href="#">A short &amp; sweet snippet.</a>
        </div>
        <div class="result">
        <a class="result__a" href="https://example.org/page">Second &lt;Result&gt;</a>
        <a class="result__snippet" href="#">Second snippet text</a>
        </div>
        """

        let results = WebSearchService.parseWebResults(html: html)

        #expect(results.count == 2)
        #expect(results[0].urlString == "https://example.com/article")
        #expect(results[0].title == "Example Article")
        #expect(results[0].snippet == "A short & sweet snippet.")
        #expect(results[1].urlString == "https://example.org/page")
        #expect(results[1].title == "Second <Result>")
        #expect(results[1].snippet == "Second snippet text")
    }

    @Test("parseWebResults skips non-http URLs and caps results at five")
    func test_parseWebResults_skipsNonHTTPAndCapsAtFive() {
        var anchors = ""
        for i in 0..<7 {
            anchors += "<a class=\"result__a\" href=\"https://example.org/\(i)\">Result \(i)</a>"
            anchors += "<a class=\"result__snippet\" href=\"#\">Snippet \(i)</a>"
        }
        let html = anchors + "<a class=\"result__a\" href=\"javascript:void(0)\">Bad Link</a>"

        let results = WebSearchService.parseWebResults(html: html)

        #expect(results.count == 5)
        #expect(results.allSatisfy { $0.urlString.hasPrefix("https://") })
        #expect(results[0].urlString == "https://example.org/0")
    }

    @Test("parseImageResults extracts image fields from i.js JSON payload")
    func test_parseImageResults_extractsFields() {
        let json = """
        {"results":[
          {"title":"Photo One","image":"https://img.example.com/one.jpg","thumbnail":"https://img.example.com/one_t.jpg","url":"https://example.com/page1","width":800,"height":600},
          {"title":"Photo Two","image":"https://img.example.com/two.jpg"}
        ]}
        """

        let images = WebSearchService.parseImageResults(data: Data(json.utf8))

        #expect(images.count == 2)
        #expect(images[0].title == "Photo One")
        #expect(images[0].urlString == "https://img.example.com/one.jpg")
        #expect(images[0].thumbnailURLString == "https://img.example.com/one_t.jpg")
        #expect(images[0].sourcePageURLString == "https://example.com/page1")
        #expect(images[0].width == 800)
        #expect(images[0].height == 600)
        #expect(images[1].title == "Photo Two")
        #expect(images[1].thumbnailURLString == nil)
        #expect(images[1].width == nil)
    }

    @Test("extractVQD returns nil when the token is missing")
    func test_extractVQD_missingToken_returnsNil() {
        let withToken = "<script>vqd=\"4-123456789012345\"</script>"
        #expect(WebSearchService.extractVQD(from: withToken) == "4-123456789012345")

        let withoutToken = "<html><body>No token here</body></html>"
        #expect(WebSearchService.extractVQD(from: withoutToken) == nil)
    }
}
