import Foundation
import Testing
import TitikCore
import TitikPlatform
import TitikSearch

@Suite("Autocomplete and Directory Navigation Tests")
@MainActor
struct AutocompleteAndDirectoryNavigationTests {

    @Test("Plain keyword autocomplete yields clean folder name with trailing slash and no parent prefix")
    func testPlainKeywordAutocompleteYieldsCleanFolder() {
        let fileBrowser = FileBrowser()
        let orchestrator = UIOrchestrator(fileBrowser: fileBrowser)

        let dirItem = SearchItem(
            id: "file:/Users/someone/project/partner-v2",
            title: "partner-v2",
            subtitle: "Folder",
            category: .directory,
            previewURL: URL(fileURLWithPath: "/Users/someone/project/partner-v2")
        )

        // 1. Direct formatAutocompletePath test
        let formatted = fileBrowser.formatAutocompletePath(for: dirItem, currentQuery: "partner")
        #expect(formatted == "partner-v2/")

        // 2. UIOrchestrator test
        orchestrator.results = [dirItem]
        orchestrator.selectedIndex = 0
        orchestrator.query = "partner"
        orchestrator.autocompleteSelected()

        #expect(orchestrator.query == "partner-v2/")
    }

    @Test("Tilde or short query autocomplete yields clean folder")
    func testTildeOrShortQueryAutocompleteYieldsCleanFolder() {
        let fileBrowser = FileBrowser()
        let orchestrator = UIOrchestrator(fileBrowser: fileBrowser)

        let dirItem = SearchItem(
            id: "file:/Users/someone/Documents",
            title: "Documents",
            subtitle: "Folder",
            category: .directory,
            previewURL: URL(fileURLWithPath: "/Users/someone/Documents")
        )

        // Query "Doc" -> "Documents/"
        let formattedShort = fileBrowser.formatAutocompletePath(for: dirItem, currentQuery: "Doc")
        #expect(formattedShort == "Documents/")

        orchestrator.query = "Doc"
        orchestrator.results = [dirItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "Documents/")

        // Query "~/Doc" -> "~/Documents/"
        let formattedTildeDoc = fileBrowser.formatAutocompletePath(for: dirItem, currentQuery: "~/Doc")
        #expect(formattedTildeDoc == "~/Documents/")

        orchestrator.query = "~/Doc"
        orchestrator.results = [dirItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "~/Documents/")

        // Query "~" -> "~/Documents/"
        let formattedTilde = fileBrowser.formatAutocompletePath(for: dirItem, currentQuery: "~")
        #expect(formattedTilde == "~/Documents/")

        orchestrator.query = "~"
        orchestrator.results = [dirItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "~/Documents/")
    }

    @Test("Directory session appends child folder and file cleanly")
    func testDirectorySessionAppendsCleanly() {
        let fileBrowser = FileBrowser()
        let orchestrator = UIOrchestrator(fileBrowser: fileBrowser)

        let childFolderItem = SearchItem(
            id: "file:/tmp/folder-a/folder-b",
            title: "folder-b",
            subtitle: "Folder",
            category: .directory,
            previewURL: URL(fileURLWithPath: "/tmp/folder-a/folder-b")
        )

        let childFileItem = SearchItem(
            id: "file:/tmp/folder-a/file.txt",
            title: "file.txt",
            subtitle: "10 KB",
            category: .file,
            previewURL: URL(fileURLWithPath: "/tmp/folder-a/file.txt")
        )

        // Autocomplete child folder in folder-a/
        let formattedDir = fileBrowser.formatAutocompletePath(for: childFolderItem, currentQuery: "folder-a/")
        #expect(formattedDir == "folder-a/folder-b/")

        orchestrator.query = "folder-a/"
        orchestrator.results = [childFolderItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "folder-a/folder-b/")

        // Autocomplete child file in folder-a/
        let formattedFile = fileBrowser.formatAutocompletePath(for: childFileItem, currentQuery: "folder-a/")
        #expect(formattedFile == "folder-a/file.txt")

        orchestrator.query = "folder-a/"
        orchestrator.results = [childFileItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "folder-a/file.txt")
    }

    @Test("Right arrow / Tab autocomplete on directory SearchItem appends slash and preserves prefix")
    func testDirectoryAutocompleteAppendsSlash() {
        let fileBrowser = FileBrowser()
        let orchestrator = UIOrchestrator(fileBrowser: fileBrowser)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let docURL = URL(fileURLWithPath: (home as NSString).appendingPathComponent("Documents"))

        let dirItem = SearchItem(
            id: "file:\(docURL.path)",
            title: "Documents",
            subtitle: "Folder",
            category: .directory,
            previewType: .directory(docURL, itemCount: 5),
            previewURL: docURL,
            autocompletePayload: "~/Documents/"
        )

        orchestrator.query = "~/Doc"
        orchestrator.results = [dirItem]
        orchestrator.selectedIndex = 0

        orchestrator.autocompleteSelected()

        #expect(orchestrator.query == "~/Documents/")
    }

    @Test("Recursive directory navigation through multi-level folders")
    func testRecursiveDirectoryNavigation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_recursive_test_\(UUID().uuidString)")
        let folderA = tempDir.appendingPathComponent("folder-a")
        let folderB = folderA.appendingPathComponent("folder-b")
        let folderC = folderB.appendingPathComponent("folder-c")

        try FileManager.default.createDirectory(at: folderC, withIntermediateDirectories: true)
        let fileInC = folderC.appendingPathComponent("innermost.txt")
        try "content".write(to: fileInC, atomically: true, encoding: .utf8)
        let fileInB = folderB.appendingPathComponent("middle.swift")
        try "print(2)".write(to: fileInB, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileBrowser = FileBrowser()

        // Level 1: folder-a/
        let level1 = fileBrowser.browseDirectory(path: folderA.path + "/")
        let level1Files = level1.filter { $0.title != ".." }
        #expect(level1Files.count == 1)
        #expect(level1Files[0].title == "folder-b")
        #expect(level1Files[0].category == .directory)
        #expect(level1Files[0].autocompletePayload?.hasSuffix("/") == true)

        // Level 2: folder-a/folder-b/
        let level2 = fileBrowser.browseDirectory(path: folderB.path + "/")
        let level2Files = level2.filter { $0.title != ".." }
        #expect(level2Files.count == 2)
        #expect(level2Files[0].title == "folder-c")
        #expect(level2Files[0].category == .directory)
        #expect(level2Files[1].title == "middle.swift")
        #expect(level2Files[1].category == .file)

        // Level 3: folder-a/folder-b/folder-c/
        let level3 = fileBrowser.browseDirectory(path: folderC.path + "/")
        let level3Files = level3.filter { $0.title != ".." }
        #expect(level3Files.count == 1)
        #expect(level3Files[0].title == "innermost.txt")
        #expect(level3Files[0].category == .file)
    }

    @Test("Sub-query live filtering inside directories")
    func testSubQueryLiveFiltering() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_filter_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileAlpha = tempDir.appendingPathComponent("alpha_test.swift")
        let fileBeta = tempDir.appendingPathComponent("beta_test.txt")
        let fileGamma = tempDir.appendingPathComponent("gamma.json")

        try "alpha".write(to: fileAlpha, atomically: true, encoding: .utf8)
        try "beta".write(to: fileBeta, atomically: true, encoding: .utf8)
        try "gamma".write(to: fileGamma, atomically: true, encoding: .utf8)

        let fileBrowser = FileBrowser()

        // Filter for "alp"
        let filteredAlpha = fileBrowser.browseDirectory(path: tempDir.path + "/alp")
        #expect(filteredAlpha.count == 1)
        #expect(filteredAlpha[0].title == "alpha_test.swift")

        // Filter for "test"
        let filteredTest = fileBrowser.browseDirectory(path: tempDir.path + "/test")
        #expect(filteredTest.count == 2)
        let titles = Set(filteredTest.map { $0.title })
        #expect(titles.contains("alpha_test.swift"))
        #expect(titles.contains("beta_test.txt"))
    }

    @Test("100% exact match slash transition seamlessly opens directory")
    func testExactMatchSlashTransition() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_exact_test_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("MyWorkspace")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let childFile = subDir.appendingPathComponent("Project.swift")
        try "// swift".write(to: childFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileBrowser = FileBrowser()

        // Before trailing slash: filtering in tempDir for "MyWorkspace"
        let beforeSlash = fileBrowser.browseDirectory(path: tempDir.path + "/MyWorkspace")
        #expect(!beforeSlash.isEmpty)
        #expect(beforeSlash[0].title == "MyWorkspace")

        // With trailing slash: directory session enters subDir
        let afterSlash = fileBrowser.browseDirectory(path: tempDir.path + "/MyWorkspace/")
        let afterSlashFiles = afterSlash.filter { $0.title != ".." }
        #expect(afterSlashFiles.count == 1)
        #expect(afterSlashFiles[0].title == "Project.swift")
        #expect(afterSlashFiles[0].category == .file)
    }

    @Test("Autocomplete on non-directory items (apps, system commands, bang shortcuts)")
    func testNonDirectoryAutocomplete() {
        let orchestrator = UIOrchestrator()

        // 1. Application autocomplete
        let appItem = SearchItem(
            id: "app:Safari",
            title: "Safari",
            subtitle: "Application",
            category: .application
        )
        orchestrator.query = "saf"
        orchestrator.results = [appItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "Safari")

        // 2. System Command autocomplete
        let cmdItem = SearchItem(
            id: "cmd:lock",
            title: "Lock Screen",
            subtitle: "System Command",
            category: .systemCommand
        )
        orchestrator.query = "loc"
        orchestrator.results = [cmdItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "Lock Screen")

        // 3. Bang item autocomplete
        let bangItem = SearchItem(
            id: "bang:file",
            title: "!file <path/name>",
            subtitle: "Search files or browse filesystem",
            category: .file,
            actionPayload: "!file ",
            autocompletePayload: "!file "
        )
        orchestrator.query = "!f"
        orchestrator.results = [bangItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "!file ")
    }

    @Test("Drill-up: deleting trailing slash returns to parent directory filtering")
    func testDrillUp() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_drillup_test_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("ChildFolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let childFile = subDir.appendingPathComponent("child.txt")
        try "child".write(to: childFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileBrowser = FileBrowser()

        // Child session
        let insideChild = fileBrowser.browseDirectory(path: subDir.path + "/")
        let insideChildFiles = insideChild.filter { $0.title != ".." }
        #expect(insideChildFiles.count == 1)
        #expect(insideChildFiles[0].title == "child.txt")

        // Drill up to parent filter
        let atParent = fileBrowser.browseDirectory(path: subDir.path)
        #expect(atParent.count == 1)
        #expect(atParent[0].title == "ChildFolder")
        #expect(atParent[0].category == .directory)
    }

    @Test("Root boundary blocks back navigation and omits parent item")
    func testRootBoundaryBlocksBack() {
        #expect(PathResolver.canGoBack(path: "folder-a/") == false)
        #expect(PathResolver.parentPath(of: "folder-a/") == nil)

        let orchestrator = UIOrchestrator()
        orchestrator.query = "folder-a/"
        orchestrator.goBack()
        #expect(orchestrator.query == "folder-a/")

        // Verifying browseDirectory with a relative root path does not include ".." item
        let fileBrowser = FileBrowser()
        let items = fileBrowser.browseDirectory(path: "folder-a/")
        #expect(!items.contains(where: { $0.title == ".." || $0.id == "file:.." }))
    }

    @Test("Subfolder allows back navigation and includes parent item")
    func testSubfolderAllowsBack() {
        #expect(PathResolver.canGoBack(path: "folder-a/folder-b/") == true)
        #expect(PathResolver.parentPath(of: "folder-a/folder-b/") == "folder-a/")

        let orchestrator = UIOrchestrator()
        orchestrator.query = "folder-a/folder-b/"
        orchestrator.goBack()
        #expect(orchestrator.query == "folder-a/")

        // Executing or autocompleting ".." parent item navigates back
        let parentItem = SearchItem(
            id: "file:..",
            title: "..",
            subtitle: "Parent Directory • Go back",
            category: .directory,
            actionPayload: "folder-a/",
            autocompletePayload: "folder-a/"
        )
        orchestrator.query = "folder-a/folder-b/"
        orchestrator.results = [parentItem]
        orchestrator.selectedIndex = 0
        orchestrator.executeSelected()
        #expect(orchestrator.query == "folder-a/")

        orchestrator.query = "folder-a/folder-b/"
        orchestrator.results = [parentItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "folder-a/")
    }

    @Test("Multi-level drill-down and drill-out clamped at root folder")
    func testMultiLevelNestingAndClampedBack() {
        let orchestrator = UIOrchestrator()
        orchestrator.query = "folder-a/folder-b/folder-c/"

        // 1st back: goes to folder-a/folder-b/
        orchestrator.goBack()
        #expect(orchestrator.query == "folder-a/folder-b/")

        // 2nd back: goes to folder-a/
        orchestrator.goBack()
        #expect(orchestrator.query == "folder-a/")

        // 3rd back: clamped at root boundary, does not navigate further
        orchestrator.goBack()
        #expect(orchestrator.query == "folder-a/")
    }

    @Test("Relative autocomplete produces clean paths without parent bloat")
    func testAutocompleteNoParentPathBloat() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_bloat_test_\(UUID().uuidString)")
        let folderA = tempDir.appendingPathComponent("folder-a")
        let folderB = folderA.appendingPathComponent("folder-b")
        let fileInA = folderA.appendingPathComponent("sample.txt")

        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        try "sample".write(to: fileInA, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileBrowser = FileBrowser()

        // Browsing with relative query "folder-a/"
        // (Simulate relative autocomplete payloads)
        let (basePath, _) = PathResolver.splitPathQuery("folder-a/")
        #expect(basePath == "folder-a/")

        // Subfolder item autocomplete payload
        let dirPayload = basePath + "folder-b/"
        #expect(dirPayload == "folder-a/folder-b/")

        // File item autocomplete payload
        let filePayload = basePath + "sample.txt"
        #expect(filePayload == "folder-a/sample.txt")

        // In UIOrchestrator: autocomplete on subfolder SearchItem sets clean query
        let orchestrator = UIOrchestrator(fileBrowser: fileBrowser)
        let subfolderItem = SearchItem(
            id: "file:folder-b",
            title: "folder-b",
            subtitle: "Folder",
            category: .directory,
            autocompletePayload: "folder-a/folder-b/"
        )
        orchestrator.query = "folder-a/"
        orchestrator.results = [subfolderItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()
        #expect(orchestrator.query == "folder-a/folder-b/")
    }

    @Test("Ephemeral in-memory directory navigation session lifecycle and zero cache invalidation")
    func testEphemeralDirectorySession() throws {
        let baseTempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_ephemeral_test_\(UUID().uuidString)")
        let tempPartnerURL = baseTempDir.appendingPathComponent("partner-v2")
        let srcURL = tempPartnerURL.appendingPathComponent("src")

        try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
        let file1URL = tempPartnerURL.appendingPathComponent("file1.txt")
        let file2URL = tempPartnerURL.appendingPathComponent("file2.json")
        let mainSwiftURL = srcURL.appendingPathComponent("main.swift")

        try "file1".write(to: file1URL, atomically: true, encoding: .utf8)
        try "file2".write(to: file2URL, atomically: true, encoding: .utf8)
        try "main".write(to: mainSwiftURL, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: baseTempDir) }

        let fileBrowser = FileBrowser()
        let orchestrator = UIOrchestrator(fileBrowser: fileBrowser)

        let partnerItem = SearchItem(
            id: "file:\(tempPartnerURL.path)",
            title: "partner-v2",
            subtitle: "Folder",
            category: .directory,
            previewURL: tempPartnerURL
        )

        orchestrator.results = [partnerItem]
        orchestrator.selectedIndex = 0
        orchestrator.autocompleteSelected()

        #expect(orchestrator.query == "partner-v2/")
        #expect(orchestrator.activeSession != nil)
        #expect(orchestrator.activeSession?.rootURL == tempPartnerURL)

        let resultTitles = orchestrator.results.map { $0.title }
        #expect(resultTitles.contains("file1.txt"))
        #expect(resultTitles.contains("file2.json"))
        #expect(resultTitles.contains("src"))

        // Select `src` and autocomplete
        if let srcIndex = orchestrator.results.firstIndex(where: { $0.title == "src" }) {
            orchestrator.selectedIndex = srcIndex
            orchestrator.autocompleteSelected()
        } else {
            Issue.record("src directory not found in results")
        }

        #expect(orchestrator.query == "partner-v2/src/")
        let srcResultTitles = orchestrator.results.map { $0.title }
        #expect(srcResultTitles.contains("main.swift"))
        #expect(srcResultTitles.contains(".."))

        // Call orchestrator.goBack() -> query == "partner-v2/"
        orchestrator.goBack()
        #expect(orchestrator.query == "partner-v2/")
        let backResultTitles = orchestrator.results.map { $0.title }
        #expect(backResultTitles.contains("file1.txt"))
        #expect(backResultTitles.contains("file2.json"))
        #expect(backResultTitles.contains("src"))

        // Call orchestrator.goBack() again -> clamped at root
        orchestrator.goBack()
        #expect(orchestrator.query == "partner-v2/")

        // Change orchestrator.query = "" -> activeSession invalidated
        orchestrator.query = ""
        #expect(orchestrator.activeSession == nil)
    }
}
