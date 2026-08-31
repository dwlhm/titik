import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

@Suite("Search Query Resolver Tests")
struct SearchQueryResolverTests {

    @Test("First-turn informational query passes through unchanged")
    func test_resolve_firstTurn_passthrough() {
        let query = "what is the swift 6 strict concurrency model"
        let resolved = SearchQueryResolver.resolve(query: query, hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil)
        #expect(resolved == query)
    }

    @Test("Follow-up query merges with the previous user turn")
    func test_resolve_followUp_mergesLastUserTurn() {
        let prior = "compare swift concurrency with goroutines for backend servers"
        let followUp = "what about error handling performance"
        let resolved = SearchQueryResolver.resolve(query: followUp, hasPriorTurns: true, lastUserTurn: prior, lastAssistantTurn: "Some long answer")

        #expect(resolved != nil)
        #expect(resolved?.hasPrefix(prior) == true)
        #expect(resolved?.hasSuffix(followUp) == true)
    }

    @Test("Non-informational queries are skipped")
    func test_resolve_nonInformationalQueries_returnsNil() {
        #expect(SearchQueryResolver.resolve(query: "thanks", hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil) == nil)
        #expect(SearchQueryResolver.resolve(query: "terima kasih", hasPriorTurns: true, lastUserTurn: "compare swift concurrency with goroutines", lastAssistantTurn: nil) == nil)
        #expect(SearchQueryResolver.resolve(query: "ok", hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil) == nil)
        #expect(SearchQueryResolver.resolve(query: "hi", hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil) == nil)
    }

    @Test("Empty and very short queries are skipped")
    func test_resolve_emptyAndShortQueries_returnsNil() {
        #expect(SearchQueryResolver.resolve(query: "   ", hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil) == nil)
        #expect(SearchQueryResolver.resolve(query: "", hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil) == nil)
        #expect(SearchQueryResolver.resolve(query: "swift 6", hasPriorTurns: false, lastUserTurn: nil, lastAssistantTurn: nil) == nil)
    }
}
