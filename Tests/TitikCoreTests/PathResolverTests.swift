import Foundation
import Testing
import TitikCore

@Suite("PathResolver Tests")
struct PathResolverTests {
    let fm = FileManager.default
    var home: String { fm.homeDirectoryForCurrentUser.path }
    var pwd: String { fm.currentDirectoryPath }

    @Test("Tilde expansion")
    func testTildeExpansion() {
        #expect(PathResolver.expandPath("~") == home)
        #expect(PathResolver.expandPath("~/") == home + "/")
        #expect(PathResolver.expandPath("~/Documents") == (home as NSString).appendingPathComponent("Documents"))
        #expect(PathResolver.expandPath("~/Downloads/file.txt") == (home as NSString).appendingPathComponent("Downloads/file.txt"))
    }

    @Test("Relative path expansion")
    func testRelativePathExpansion() {
        #expect(PathResolver.expandPath("./Sources") == (pwd as NSString).appendingPathComponent("Sources"))
        #expect(PathResolver.expandPath("./") == pwd)
        #expect(PathResolver.expandPath("../") == URL(fileURLWithPath: pwd).deletingLastPathComponent().path)
        #expect(PathResolver.expandPath("Sources/TitikUI") == (pwd as NSString).appendingPathComponent("Sources/TitikUI"))
    }

    @Test("Path query detection")
    func testIsPathQuery() {
        #expect(PathResolver.isPathQuery("~") == true)
        #expect(PathResolver.isPathQuery("~/") == true)
        #expect(PathResolver.isPathQuery("~/Documents") == true)
        #expect(PathResolver.isPathQuery("/Applications") == true)
        #expect(PathResolver.isPathQuery("./Sources") == true)
        #expect(PathResolver.isPathQuery("../") == true)
        #expect(PathResolver.isPathQuery("folder-a/folder-b/") == true)
        #expect(PathResolver.isPathQuery("folder-a/sub") == true)

        #expect(PathResolver.isPathQuery("Safari") == false)
        #expect(PathResolver.isPathQuery("calculator") == false)
        #expect(PathResolver.isPathQuery("") == false)
    }

    @Test("Directory session detection")
    func testIsDirectorySession() {
        #expect(PathResolver.isDirectorySession("~") == true)
        #expect(PathResolver.isDirectorySession("/") == true)
        #expect(PathResolver.isDirectorySession("~/") == true)
        #expect(PathResolver.isDirectorySession("~/Documents/") == true)
        #expect(PathResolver.isDirectorySession("folder-a/folder-b/") == true)
        #expect(PathResolver.isDirectorySession("./Sources/") == true)

        #expect(PathResolver.isDirectorySession("~/Documents") == false)
        #expect(PathResolver.isDirectorySession("folder-a/folder-b/sub") == false)
        #expect(PathResolver.isDirectorySession("file.swift") == false)
    }

    @Test("Path query splitting")
    func testSplitPathQuery() {
        // Directory session: subFilter is empty
        let sessionSplit = PathResolver.splitPathQuery("folder-a/folder-b/folder-c/")
        #expect(sessionSplit.basePath == "folder-a/folder-b/folder-c/")
        #expect(sessionSplit.subFilter == "")

        let tildeSession = PathResolver.splitPathQuery("~/Documents/")
        #expect(tildeSession.basePath == "~/Documents/")
        #expect(tildeSession.subFilter == "")

        // SubFilter splitting
        let subSplit = PathResolver.splitPathQuery("folder-a/folder-b/sub")
        #expect(subSplit.basePath == "folder-a/folder-b/")
        #expect(subSplit.subFilter == "sub")

        let tildeSubSplit = PathResolver.splitPathQuery("~/Doc")
        #expect(tildeSubSplit.basePath == "~/")
        #expect(tildeSubSplit.subFilter == "Doc")

        // No slash
        let noSlashSplit = PathResolver.splitPathQuery("Documents")
        #expect(noSlashSplit.basePath == "")
        #expect(noSlashSplit.subFilter == "Documents")
    }

    @Test("Path contraction")
    func testContractPath() {
        // Preserves tilde
        let docPath = (home as NSString).appendingPathComponent("Documents")
        #expect(PathResolver.contractPath(docPath, originalQuery: "~/Doc") == "~/Documents")
        #expect(PathResolver.contractPath(home, originalQuery: "~") == "~")

        // Preserves relative path inside pwd
        let sourcesPath = (pwd as NSString).appendingPathComponent("Sources/TitikCore")
        #expect(PathResolver.contractPath(sourcesPath, originalQuery: "Sources/") == "Sources/TitikCore")
        #expect(PathResolver.contractPath(sourcesPath, originalQuery: "./Sources/") == "./Sources/TitikCore")

        // Absolute query keeps absolute
        #expect(PathResolver.contractPath("/Applications/Safari.app", originalQuery: "/Applications/") == "/Applications/Safari.app")
    }

    @Test("Can go back boundary check")
    func testCanGoBack() {
        #expect(PathResolver.canGoBack(path: "folder-a/") == false)
        #expect(PathResolver.canGoBack(path: "folder-a") == false)
        #expect(PathResolver.canGoBack(path: "folder-a/folder-b/") == true)
        #expect(PathResolver.canGoBack(path: "folder-a/folder-b/folder-c/") == true)

        #expect(PathResolver.canGoBack(path: "~") == false)
        #expect(PathResolver.canGoBack(path: "~/") == false)
        #expect(PathResolver.canGoBack(path: "~/Documents/") == false)
        #expect(PathResolver.canGoBack(path: "~/Documents") == false)
        #expect(PathResolver.canGoBack(path: "~/Documents/Projects/") == true)

        #expect(PathResolver.canGoBack(path: "/") == false)
        #expect(PathResolver.canGoBack(path: "/usr/") == false)
        #expect(PathResolver.canGoBack(path: "/usr/local/") == true)
        #expect(PathResolver.canGoBack(path: "/usr/local/bin/") == true)

        #expect(PathResolver.canGoBack(path: "") == false)
        #expect(PathResolver.canGoBack(path: "./") == false)
        #expect(PathResolver.canGoBack(path: "../") == false)
    }

    @Test("Parent path computation")
    func testParentPath() {
        #expect(PathResolver.parentPath(of: "folder-a/") == nil)
        #expect(PathResolver.parentPath(of: "folder-a/folder-b/") == "folder-a/")
        #expect(PathResolver.parentPath(of: "folder-a/folder-b/folder-c/") == "folder-a/folder-b/")

        #expect(PathResolver.parentPath(of: "~/Documents/") == nil)
        #expect(PathResolver.parentPath(of: "~/Documents/Projects/") == "~/Documents/")
        #expect(PathResolver.parentPath(of: "~/Documents/Projects/App/") == "~/Documents/Projects/")

        #expect(PathResolver.parentPath(of: "/usr/") == nil)
        #expect(PathResolver.parentPath(of: "/usr/local/") == "/usr/")
        #expect(PathResolver.parentPath(of: "/usr/local/bin/") == "/usr/local/")
    }
}
