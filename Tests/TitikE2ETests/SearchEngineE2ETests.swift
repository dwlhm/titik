import Testing
import Foundation
import TitikCore
import TitikParser
import TitikPlugins
import TitikPluginKit
import TitikSearch

@Suite("SearchEngine E2E Tests")
struct SearchEngineE2ETests {
    let searchEngine: SearchEngine

    init() {
        let host = PluginHost()
        for entry in BuiltinPluginRegistry.all {
            let plugin = entry.factory(PluginContext(pluginId: entry.id))
            host.registerNativePlugin(plugin, manifest: entry.manifest)
        }
        self.searchEngine = SearchEngine(pluginHost: host)
    }

    @Test("Empty query returns curated defaults with running apps")
    func testEmptyQueryReturnsCuratedDefaults() {
        let items = searchEngine.search(query: "")
        #expect(!items.isEmpty, "Default query must return items")

        let categories = Set(items.map { $0.category })
        #expect(categories.contains(.application) || categories.contains(.systemCommand))

        // Default items (apps, system commands, clipboard) should not force rich preview pane
        for item in items {
            if item.category == .application || item.category == .systemCommand || item.category == .clipboard {
                #expect(item.hasRichPreview == false)
            }
        }
    }

    @Test("Path search returns directory items with rich preview enabled")
    func testPathSearchReturnsDirectoryItems() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let sampleFile = tempDir.appendingPathComponent("sample.txt")
        try "test content".write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let items = searchEngine.search(query: tempDir.path)
        #expect(!items.isEmpty, "Path search on temp directory should return directory contents")

        guard let firstItem = items.first else {
            #expect(Bool(false), "Expected at least one item")
            return
        }
        #expect(firstItem.category == .directory || firstItem.category == .file)
        #expect(firstItem.hasRichPreview == true)
        #expect(firstItem.previewURL != nil)
    }

    @Test("File command prefix search")
    func testFileCommandPrefixSearch() {
        let items = searchEngine.search(query: "file:~")
        #expect(!items.isEmpty)
        if let first = items.first {
            #expect(first.category == .directory || first.category == .file)
        }
    }

    @Test("Math query evaluation")
    func testMathQueryEvaluation() {
        let items = searchEngine.search(query: "25 * 4")
        #expect(!items.isEmpty)

        guard let topItem = items.first else {
            #expect(Bool(false), "Expected math result item")
            return
        }
        #expect(topItem.category == .calculator)
        #expect(topItem.title == "100")
        #expect(topItem.hasRichPreview == false)
    }

    @Test("Command prefix search")
    func testCommandPrefixSearch() {
        let appItems = searchEngine.search(query: "app:finder")
        for item in appItems {
            #expect(item.category == .application)
            #expect(item.hasRichPreview == false)
        }

        let cmdItems = searchEngine.search(query: "cmd:lock")
        for item in cmdItems {
            #expect(item.category == .systemCommand)
            #expect(item.hasRichPreview == false)
        }
    }

    @Test("Result score ordering")
    func testScoreOrdering() {
        let items = searchEngine.search(query: "term")
        guard items.count >= 2 else { return }

        for i in 0..<(items.count - 1) {
            #expect(items[i].score >= items[i + 1].score, "Results must be sorted descending by score")
        }
    }
}

