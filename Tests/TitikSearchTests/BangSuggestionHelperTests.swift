import Testing
import Foundation
import TitikCore

@Suite("BangSuggestionHelper Tests")
struct BangSuggestionHelperTests {

    @Test("Suggestion suffix for prefixes")
    func testSuggestionSuffixPrefixes() {
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!e") == "moji")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!em") == "oji")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!emoj") == "i")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!f") == "ile")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!fi") == "le")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!a") == "pp")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!ap") == "p")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!cl") == "ip")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!cm") == "d")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!ca") == "lc")
    }

    @Test("Suggestion suffix returns nil for exact matches")
    func testSuggestionSuffixExactMatches() {
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!emoji") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!file") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!app") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!clip") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!cmd") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!calc") == nil)
    }

    @Test("Case-insensitive matching")
    func testCaseInsensitiveMatching() {
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!EMO") == "ji")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!Fil") == "e")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!APP") == nil)
    }

    @Test("Queries with spaces or subqueries return nil")
    func testQueriesWithSpacesReturnNil() {
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!emoji ") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!e test") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!file /path") == nil)
    }

    @Test("Empty, single exclamation mark, and non-bang queries return nil")
    func testInvalidOrNonBangQueriesReturnNil() {
        #expect(BangSuggestionHelper.suggestionSuffix(for: "") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "   ") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "emoji") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "calc") == nil)
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!unknown") == nil)
    }

    @Test("Full suggestion returns concatenated query and suffix")
    func testFullSuggestion() {
        #expect(BangSuggestionHelper.fullSuggestion(for: "!e") == "!emoji")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!em") == "!emoji")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!f") == "!file")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!a") == "!app")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!cl") == "!clip")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!cm") == "!cmd")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!ca") == "!calc")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!emoji") == nil)
        #expect(BangSuggestionHelper.fullSuggestion(for: "!") == nil)
        #expect(BangSuggestionHelper.fullSuggestion(for: "") == nil)
    }

    @Test("Plugin bangs suggestion suffix and full suggestion")
    func testPluginBangsSuggestion() {
        let pluginBangs = ["!math", "!calc"]
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!m", pluginBangs: pluginBangs) == "ath")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!mat", pluginBangs: pluginBangs) == "h")
        #expect(BangSuggestionHelper.fullSuggestion(for: "!m", pluginBangs: pluginBangs) == "!math")
        #expect(BangSuggestionHelper.suggestionSuffix(for: "!math", pluginBangs: pluginBangs) == nil)
    }
}
