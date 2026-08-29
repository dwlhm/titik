import Foundation
import Testing
import TitikCore

@Suite("FileBrowser Tests")
struct FileBrowserTests {
    let fileBrowser = FileBrowser()

    @Test("Tilde and path expansion")
    func testTildeExpansion() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(fileBrowser.expandPath("~") == home)
        #expect(fileBrowser.expandPath("~/Documents") == home + "/Documents")
        #expect(fileBrowser.expandPath("/Applications") == "/Applications")
    }

    @Test("File extension classification for preview types")
    func testFileExtensionClassification() {
        let imageURL = URL(fileURLWithPath: "/tmp/photo.jpg")
        #expect(fileBrowser.determinePreviewType(for: imageURL, isDirectory: false) == .image(imageURL))

        let videoURL = URL(fileURLWithPath: "/tmp/movie.mp4")
        #expect(fileBrowser.determinePreviewType(for: videoURL, isDirectory: false) == .video(videoURL))

        let audioURL = URL(fileURLWithPath: "/tmp/song.mp3")
        #expect(fileBrowser.determinePreviewType(for: audioURL, isDirectory: false) == .audio(audioURL))

        let pdfURL = URL(fileURLWithPath: "/tmp/doc.pdf")
        #expect(fileBrowser.determinePreviewType(for: pdfURL, isDirectory: false) == .pdf(pdfURL))

        let swiftURL = URL(fileURLWithPath: "/tmp/main.swift")
        #expect(fileBrowser.determinePreviewType(for: swiftURL, isDirectory: false) == .code(swiftURL, language: "swift"))

        let txtURL = URL(fileURLWithPath: "/tmp/notes.txt")
        #expect(fileBrowser.determinePreviewType(for: txtURL, isDirectory: false) == .text(txtURL))

        let zipURL = URL(fileURLWithPath: "/tmp/archive.zip")
        let zipPreviewType = fileBrowser.determinePreviewType(for: zipURL, isDirectory: false)
        #expect(zipPreviewType == .fileMetadata(zipURL))
        let zipItem = SearchItem(
            id: "file:\(zipURL.path)",
            title: "archive.zip",
            subtitle: zipURL.path,
            category: .file,
            previewType: zipPreviewType,
            previewURL: zipURL
        )
        #expect(zipItem.hasRichPreview == true)

        let binURL = URL(fileURLWithPath: "/tmp/data.bin")
        let binPreviewType = fileBrowser.determinePreviewType(for: binURL, isDirectory: false)
        #expect(binPreviewType == .fileMetadata(binURL))
        let binItem = SearchItem(
            id: "file:\(binURL.path)",
            title: "data.bin",
            subtitle: binURL.path,
            category: .file,
            previewType: binPreviewType,
            previewURL: binURL
        )
        #expect(binItem.hasRichPreview == true)

        let dirURL = URL(fileURLWithPath: "/tmp")
        if case .directory(let url, _) = fileBrowser.determinePreviewType(for: dirURL, isDirectory: true) {
            #expect(url == dirURL)
        } else {
            Issue.record("Expected .directory preview type")
        }
    }

    @Test("Browse directory contents and ordering")
    func testDirectoryBrowsing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_browse_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("ZFolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let fileA = tempDir.appendingPathComponent("AFile.swift")
        try "print(1)".write(to: fileA, atomically: true, encoding: .utf8)

        let fileB = tempDir.appendingPathComponent("BFile.png")
        try "png".write(to: fileB, atomically: true, encoding: .utf8)

        let items = fileBrowser.browseDirectory(path: tempDir.path)
        #expect(items.count == 3)

        // Folders first
        #expect(items[0].category == .directory)
        #expect(items[0].title == "ZFolder")
        #expect(items[0].hasRichPreview == true)

        // Files alphabetically after folders
        #expect(items[1].category == .file)
        #expect(items[1].title == "AFile.swift")
        #expect(items[1].hasRichPreview == true)

        #expect(items[2].category == .file)
        #expect(items[2].title == "BFile.png")
        #expect(items[2].hasRichPreview == true)
    }

    @Test("Search files in specified directories")
    func testSearchFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("titik_search_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetFile = tempDir.appendingPathComponent("SpecialTitikDocument.pdf")
        try "fake pdf".write(to: targetFile, atomically: true, encoding: .utf8)

        let results = fileBrowser.searchFiles(query: "SpecialTitik", directories: [tempDir])
        #expect(!results.isEmpty)
        #expect(results.first?.title == "SpecialTitikDocument.pdf")
        #expect(results.first?.category == .file)
        #expect(results.first?.hasRichPreview == true)
    }
}
