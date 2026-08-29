import Testing
import TitikCore

@Suite("EmojiCatalog Tests")
struct EmojiCatalogTests {
    @Test("Search by shortcode")
    func testSearchByShortcode() {
        let catalog = EmojiCatalog.shared

        let fireResults = catalog.search(query: ":fire:")
        #expect(!fireResults.isEmpty)
        #expect(fireResults.first?.emoji == "🔥")

        let rocketResults = catalog.search(query: "rocket")
        #expect(!rocketResults.isEmpty)
        #expect(rocketResults.first?.emoji == "🚀")

        let thumbsUpResults = catalog.search(query: ":thumbsup:")
        #expect(!thumbsUpResults.isEmpty)
        #expect(thumbsUpResults.first?.emoji == "👍")
    }

    @Test("Search by name and keyword")
    func testSearchByNameAndKeyword() {
        let catalog = EmojiCatalog.shared

        let grinningResults = catalog.search(query: "Grinning Face")
        #expect(!grinningResults.isEmpty)
        #expect(grinningResults.contains { $0.emoji == "😀" })

        let aiResults = catalog.search(query: "ai")
        #expect(!aiResults.isEmpty)
        #expect(aiResults.contains { $0.emoji == "✨" || $0.emoji == "🤖" })

        let coffeeResults = catalog.search(query: "espresso")
        #expect(!coffeeResults.isEmpty)
        #expect(coffeeResults.first?.emoji == "☕")
    }

    @Test("Category filtering")
    func testCategoryFiltering() {
        let catalog = EmojiCatalog.shared

        let foodItems = catalog.search(query: "", category: .food)
        #expect(!foodItems.isEmpty)
        #expect(foodItems.allSatisfy { $0.category == .food })
        #expect(foodItems.contains { $0.emoji == "🍕" })

        let animalItems = catalog.search(query: "cat", category: .animals)
        #expect(!animalItems.isEmpty)
        #expect(animalItems.allSatisfy { $0.category == .animals })
        #expect(animalItems.contains { $0.emoji == "🐱" })

        // Searching food in animals category should be empty
        let pizzaInAnimals = catalog.search(query: "pizza", category: .animals)
        #expect(pizzaInAnimals.isEmpty)
    }

    @Test("Search by Unicode Hex")
    func testSearchByUnicodeHex() {
        let catalog = EmojiCatalog.shared

        let hexResults = catalog.search(query: "1F525")
        #expect(!hexResults.isEmpty)
        #expect(hexResults.contains { $0.emoji == "🔥" })

        let formattedHexResults = catalog.search(query: "U+1F680")
        #expect(!formattedHexResults.isEmpty)
        #expect(formattedHexResults.contains { $0.emoji == "🚀" })
    }

    @Test("Direct emoji character search")
    func testDirectEmojiSearch() {
        let catalog = EmojiCatalog.shared

        let directResults = catalog.search(query: "🎉")
        #expect(!directResults.isEmpty)
        #expect(directResults.first?.shortcode == ":tada:")
    }
}
