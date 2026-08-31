import Foundation
import Testing
@testable import TitikPluginKit
@testable import AskAIPlugin

@Suite("AI Session Coordinator Tests")
struct AISessionCoordinatorTests {

    @Test("Appending turns updates history and message count")
    func test_conversationThread_appendTurn_updatesHistory() async {
        let coordinator = AISessionCoordinator(maxTokens: 8192, maxTurns: 10, systemPrompt: "You are a helpful assistant.")

        await coordinator.appendTurn(role: .user, content: "Hello!")
        await coordinator.appendTurn(role: .assistant, content: "Hi there, how can I help you?")

        let history = await coordinator.history()
        #expect(history.count == 3) // System + User + Assistant
        #expect(history[0].role == .system)
        #expect(history[1].role == .user)
        #expect(history[2].role == .assistant)
        let turns = await coordinator.turnCount
        #expect(turns == 2)
    }

    @Test("Exceeding maximum turns prunes oldest non-system turns FIFO")
    func test_conversationThread_exceedingMaxTurns_prunesOldestTurns() async {
        let coordinator = AISessionCoordinator(maxTokens: 8192, maxTurns: 4, systemPrompt: "System instruction")

        for i in 1...6 {
            await coordinator.appendTurn(role: .user, content: "Query \(i)")
        }

        let history = await coordinator.history()
        // Should have 1 system message + 4 latest turns
        #expect(history.count == 5)
        #expect(history[0].content == "System instruction")
        #expect(history[1].content == "Query 3")
        #expect(history[2].content == "Query 4")
        #expect(history[3].content == "Query 5")
        #expect(history[4].content == "Query 6")
    }

    @Test("Token budget over limit prunes oldest turns while preserving system prompt")
    func test_conversationThread_tokenBudgetOverLimit_prunesOldestWithSystemPreserved() async {
        // Create coordinator with a tight token budget (e.g. 50 tokens ~ 200 chars)
        let coordinator = AISessionCoordinator(maxTokens: 50, maxTurns: 10, systemPrompt: "Core system rule.")

        // Add 5 long messages (each ~100 chars -> ~25 tokens)
        for i in 1...5 {
            let content = "Long prompt message number \(i) with lots of descriptive text for testing token budgeting."
            await coordinator.appendTurn(role: .user, content: content)
        }

        let history = await coordinator.history()
        let totalTokens = await coordinator.totalEstimatedTokens

        #expect(history.first?.role == .system)
        #expect(history.first?.content == "Core system rule.")
        #expect(totalTokens <= 60, "Token budget should be pruned near limit")
        #expect(history.count < 6, "Old messages should have been pruned")
    }

    @Test("Reset clears all history while restoring system prompt")
    func test_conversationThread_reset_clearsAllHistory() async {
        let coordinator = AISessionCoordinator(maxTokens: 8192, maxTurns: 10, systemPrompt: "Persistent system prompt")

        await coordinator.appendTurn(role: .user, content: "Question 1")
        await coordinator.appendTurn(role: .assistant, content: "Answer 1")
        await coordinator.appendTurn(role: .user, content: "Question 2")

        let countBefore = (await coordinator.history()).count
        #expect(countBefore == 4)

        await coordinator.reset()

        let historyAfter = await coordinator.history()
        #expect(historyAfter.count == 1)
        #expect(historyAfter.first?.role == .system)
        #expect(historyAfter.first?.content == "Persistent system prompt")
    }
}
