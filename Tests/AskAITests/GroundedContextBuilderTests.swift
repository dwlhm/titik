import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

@Suite("Grounded Context Builder Tests")
struct GroundedContextBuilderTests {

    @Test("buildContext returns nil when both result lists are empty")
    func test_buildContext_emptyResults_returnsNil() {
        #expect(GroundedContextBuilder.buildContext(from: .empty) == nil)
    }

    @Test("buildContext includes source headers, index, URL, and snippet")
    func test_buildContext_withWebResults_containsExpectedSections() {
        let results = GroundedSearchResults(
            results: [
                WebSearchResult(title: "Example Article", urlString: "https://example.com/article", snippet: "A useful snippet."),
                WebSearchResult(title: "Second Source", urlString: "https://example.org/page", snippet: "Another snippet.")
            ],
            images: []
        )

        let context = GroundedContextBuilder.buildContext(from: results)

        #expect(context != nil)
        #expect(context?.contains("WEB CONTEXT") == true)
        #expect(context?.contains("Web sources:") == true)
        #expect(context?.contains("[1] Example Article — https://example.com/article") == true)
        #expect(context?.contains("A useful snippet.") == true)
        #expect(context?.contains("[2] Second Source — https://example.org/page") == true)
        #expect(context?.contains("Supporting images (image URLs):") == false)
    }

    @Test("buildContext omits the web sources section when only images are present")
    func test_buildContext_imagesOnly_omitsWebSourcesSection() {
        let results = GroundedSearchResults(
            results: [],
            images: [
                WebImageResult(title: "Example Photo", urlString: "https://example.com/photo.jpg")
            ]
        )

        let context = GroundedContextBuilder.buildContext(from: results)

        #expect(context != nil)
        #expect(context?.contains("Supporting images (image URLs):") == true)
        #expect(context?.contains("- Example Photo: https://example.com/photo.jpg") == true)
        #expect(context?.contains("Web sources:") == false)
    }
}
