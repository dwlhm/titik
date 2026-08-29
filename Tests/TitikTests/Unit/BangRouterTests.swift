import Foundation
import Testing
import TitikCore
import TitikPlugins
import TitikSearch

@Suite("BangRouter Tests")
struct BangRouterTests {
    @Test("Bang suggestions on empty bang query")
    func testEmptyBangSuggestions() {
        let engine = SearchEngine.shared
        let results = engine.search(query: "!")

        #expect(!results.isEmpty)
        #expect(results.contains { $0.id == "bang:emoji" })
        #expect(results.contains { $0.id == "bang:file" })
        #expect(results.contains { $0.id == "bang:app" })
        #expect(results.contains { $0.id == "bang:clip" })
        #expect(results.contains { $0.id == "bang:cmd" })
    }

    @Test("Bang prefix suggestions without space")
    func testBangPrefixSuggestionsWithoutSpace() {
        let engine = SearchEngine.shared
        let eSuggestions = engine.search(query: "!e")
        #expect(eSuggestions.contains { $0.id == "bang:emoji" })

        let emojiSuggestions = engine.search(query: "!em")
        #expect(emojiSuggestions.contains { $0.id == "bang:emoji" })

        let fileSuggestions = engine.search(query: "!fi")
        #expect(fileSuggestions.contains { $0.id == "bang:file" })
    }

    @Test("Emoji bang routing")
    func testEmojiBangRouting() {
        let engine = SearchEngine.shared
        let results = engine.search(query: "!emoji fire")

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .emoji })
        #expect(results.first?.actionPayload == "🔥")

        let allEmojiResults = engine.search(query: "!emoji ")
        #expect(!allEmojiResults.isEmpty)
        #expect(allEmojiResults.allSatisfy { $0.category == .emoji })
    }

    @Test("App bang routing")
    func testAppBangRouting() {
        let engine = SearchEngine.shared
        let results = engine.search(query: "!app")

        #expect(results.allSatisfy { $0.category == .application })
    }

    @Test("Clipboard bang routing")
    func testClipboardBangRouting() {
        let manager = ClipboardManager.shared
        manager.addItem("Bang clipboard test item unique_123")

        let engine = SearchEngine.shared
        let results = engine.search(query: "!clip unique_123")

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .clipboard })
        #expect(results.contains { $0.actionPayload.contains("unique_123") })
    }

    @Test("Command bang routing")
    func testCommandBangRouting() {
        let engine = SearchEngine.shared
        let results = engine.search(query: "!cmd lock")

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .systemCommand })
    }

    @Test("Calc bang routing")
    func testCalcBangRouting() {
        let engine = SearchEngine.shared
        let results = engine.search(query: "!calc 25 * 4")

        #expect(!results.isEmpty)
        #expect(results.first?.category == .calculator)
        #expect(results.first?.title == "100")
    }

    @Test("Plugin defined short-bang and space activation")
    func testPluginDefinedShortBangAndSpaceActivation() {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let mathPluginPath = "plugins/math_plugin/math.dylib"
        if FileManager.default.fileExists(atPath: mathPluginPath) {
            _ = host.loadPlugin(at: mathPluginPath)
            let engine = SearchEngine(pluginHost: host)

            // 1. Bang query without space returns suggestions, not evaluated math
            let suggestions = engine.search(query: "!calc")
            #expect(suggestions.contains { $0.title.hasPrefix("!calc") })

            // 2. Bang query with trailing space and subquery activates plugin
            let activeResults = engine.search(query: "!calc 25 * 4")
            #expect(!activeResults.isEmpty)
            #expect(activeResults.first?.title == "100")

            // 3. Name bang query with trailing space also activates plugin
            let nameBangResults = engine.search(query: "!math 25 * 4")
            #expect(!nameBangResults.isEmpty)
            #expect(nameBangResults.first?.title == "100")

            // 4. Query without '!' goes to regular search
            let generalResults = engine.search(query: "calc 25 * 4")
            #expect(generalResults.first?.title == "100")
        }
    }

    @Test("Unknown bang fallback")
    func testUnknownBangFallback() {
        let engine = SearchEngine.shared
        // Searching "!something" should fallback to searching all providers for "something"
        let results = engine.search(query: "!unknownNonExistentQueryXYZ123")
        #expect(results.isEmpty)
    }
}
