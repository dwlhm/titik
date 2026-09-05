import Testing
import TitikCore

@Suite("FuzzyMatcher Tests")
struct FuzzyMatcherTests {
    @Test("Prefix match bonus")
    func testPrefixBonus() {
        let match1 = FuzzyMatcher.match(query: "saf", target: "Safari")
        let match2 = FuzzyMatcher.match(query: "saf", target: "Unsafe")

        #expect(match1 != nil)
        #expect(match2 != nil)
        #expect((match1?.score ?? 0) > (match2?.score ?? 0), "Prefix match should score higher than mid-word match")
    }

    @Test("Word boundary match bonus")
    func testBoundaryBonus() {
        let matchBoundary = FuzzyMatcher.match(query: "vc", target: "Visual Studio Code")
        let matchNoBoundary = FuzzyMatcher.match(query: "vc", target: "Advocate")

        #expect(matchBoundary != nil)
        #expect(matchNoBoundary != nil)
        #expect((matchBoundary?.score ?? 0) > (matchNoBoundary?.score ?? 0), "Word boundary match should score higher")
    }

    @Test("Consecutive match bonus")
    func testConsecutiveBonus() {
        let matchConsecutive = FuzzyMatcher.match(query: "term", target: "Terminal")
        let matchScattered = FuzzyMatcher.match(query: "term", target: "The Remote Manager")

        #expect(matchConsecutive != nil)
        #expect(matchScattered != nil)
        #expect((matchConsecutive?.score ?? 0) > (matchScattered?.score ?? 0), "Consecutive match should score higher")
    }

    @Test("Exact match bonus")
    func testExactMatchBonus() {
        let matchExact = FuzzyMatcher.match(query: "Music", target: "Music")
        let matchSub = FuzzyMatcher.match(query: "Music", target: "Apple Music App")

        #expect(matchExact != nil)
        #expect(matchSub != nil)
        #expect((matchExact?.score ?? 0) > (matchSub?.score ?? 0), "Exact full match should score highest")
    }

    @Test("Non matching query returns nil")
    func testNonMatch() {
        let nonMatch = FuzzyMatcher.match(query: "xyz", target: "Safari")
        #expect(nonMatch == nil)
    }

    @Test("Negative score returns nil")
    func testNegativeScoreReturnsNil() {
        let target = "u" + String(repeating: "a", count: 1000) + "b"
        let match = FuzzyMatcher.match(query: "ub", target: target)
        #expect(match == nil)
    }
}
