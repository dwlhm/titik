import Foundation
import AppKit
import SwiftUI
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikUI
@testable import TitikParser

@Suite("NotesPlugin Unit & Integration Tests")
struct NotesPluginTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("titik-notes-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeKeyEvent(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent? {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ) else {
            return nil
        }
        return event
    }

    // 1. First-time setup state
    @Test("Displays setup CTA when unconfigured and transitions once directory is set")
    @MainActor
    func testFirstTimeSetupState() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let unconfiguredConfig = NoteConfig(storageDirectoryPath: nil, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: nil)
        let viewModel = NotesViewModel(storage: storage, config: unconfiguredConfig, configURL: tempConfigURL)

        #expect(viewModel.mode == .setup)

        // Configure directory
        viewModel.configureDirectory(path: tempDir.path)
        #expect(viewModel.mode == .list)
        #expect(viewModel.config.isConfigured == true)
        #expect(viewModel.config.storageDirectoryPath == tempDir.path)
        #expect(FileManager.default.fileExists(atPath: tempConfigURL.path))
    }

    // 2. Flat storage integrity
    @Test("Reads and writes flat .md files with YAML frontmatter")
    func testFlatStorageIntegrity() throws {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let note = Note(
            id: UUID(),
            title: "Architecture Decisions",
            content: "## Section 1\nImportant details here.",
            isPinned: false
        )

        storage.saveNote(note)

        // Verify file exists on disk as a flat .md file
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let mdFiles = files.filter { $0.pathExtension == "md" }
        #expect(mdFiles.count == 1)

        let fileData = try Data(contentsOf: mdFiles[0])
        guard let rawContent = String(data: fileData, encoding: .utf8) else {
            Issue.record("Expected non-nil rawContent from UTF-8 data")
            return
        }
        #expect(rawContent.contains("id: \(note.id.uuidString)"))
        #expect(rawContent.contains("title: \"Architecture Decisions\""))
        #expect(rawContent.contains("isPinned: false"))
        #expect(rawContent.contains("## Section 1"))

        // Rescan from new storage instance
        let newStorage = NoteStorage(storageDirectoryPath: tempDir.path)
        let loaded = newStorage.getAllNotes()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == note.id)
        #expect(loaded[0].title == "Architecture Decisions")
        #expect(loaded[0].content == "## Section 1\nImportant details here.")
    }

    // 3. Isolated search
    @Test("NotesPlugin does NOT conform to TitikGlobalSearchProvider")
    func testIsolatedSearch() {
        let plugin = NotesPlugin(context: PluginContext(pluginId: NotesPlugin.id))
        #expect((plugin as Any) is TitikPlugin)
        #expect((plugin as Any) is TitikCommandPlugin)
        #expect(!((plugin as Any) is TitikGlobalSearchProvider))
    }

    // 4. Search filtering
    @Test("Filters notes matching keyword across both title and content")
    func testSearchFiltering() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let note1 = Note(title: "Grocery Shopping", content: "Apples, bananas, and milk")
        let note2 = Note(title: "Project Phoenix", content: "Weekly sync meeting notes")
        let note3 = Note(title: "Swift Concurrency", content: "Check actor reentrancy and sendable")

        storage.saveNote(note1)
        storage.saveNote(note2)
        storage.saveNote(note3)

        // Match by title
        let titleMatch = storage.getAllNotes(searchQuery: "Grocery")
        #expect(titleMatch.count == 1)
        #expect(titleMatch[0].id == note1.id)

        // Match by body content
        let contentMatch = storage.getAllNotes(searchQuery: "bananas")
        #expect(contentMatch.count == 1)
        #expect(contentMatch[0].id == note1.id)

        // Case insensitive match in content
        let caseInsensitive = storage.getAllNotes(searchQuery: "ACTOR")
        #expect(caseInsensitive.count == 1)
        #expect(caseInsensitive[0].id == note3.id)

        // No match
        let noMatch = storage.getAllNotes(searchQuery: "nonexistent")
        #expect(noMatch.isEmpty)
    }

    // 5. Single-pinned note invariant
    @Test("Enforces single pinned note guarantee: pinning note B unpins note A")
    func testSinglePinnedNoteInvariant() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let noteA = Note(title: "Note A", content: "Content A", isPinned: true)
        storage.saveNote(noteA)

        #expect(storage.getPinnedNote()?.id == noteA.id)

        let noteB = Note(title: "Note B", content: "Content B", isPinned: false)
        storage.saveNote(noteB)

        // Pin note B
        storage.setPinned(noteId: noteB.id, isPinned: true)

        let all = storage.getAllNotes()
        let pinnedNotes = all.filter { $0.isPinned }
        #expect(pinnedNotes.count == 1)
        #expect(pinnedNotes[0].id == noteB.id)

        let reloadedA = storage.getNote(byId: noteA.id)
        #expect(reloadedA?.isPinned == false)
    }

    // 6. Default routing
    @Test("Default routing opens pinned note, last opened note, or creates new note")
    @MainActor
    func testDefaultRouting() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let config = NoteConfig(storageDirectoryPath: tempDir.path, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config, configURL: tempConfigURL)

        // When folder is empty, !note creates a new blank note
        viewModel.handleSearchQuery("")
        if case .editor(let note) = viewModel.mode {
            #expect(!note.id.uuidString.isEmpty)
        } else {
            Issue.record("Expected editor mode with new note")
        }

        // Now save a pinned note and trigger !note again
        let pinned = Note(title: "Pinned Note", content: "Important", isPinned: true)
        storage.saveNote(pinned)
        viewModel.handleSearchQuery("")

        if case .editor(let note) = viewModel.mode {
            #expect(note.id == pinned.id)
            #expect(note.title == "Pinned Note")
        } else {
            Issue.record("Expected editor mode with pinned note")
        }
    }

    // 7. !note list order
    @Test("!note list places pinned note strictly at index 0")
    func testListOrderPinnedFirst() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let note1 = Note(title: "Alpha", content: "A", isPinned: false, updatedAt: Date().addingTimeInterval(100))
        let note2 = Note(title: "Beta (Pinned)", content: "B", isPinned: true, updatedAt: Date().addingTimeInterval(10))
        let note3 = Note(title: "Gamma", content: "C", isPinned: false, updatedAt: Date().addingTimeInterval(200))

        storage.saveNote(note1)
        storage.saveNote(note2)
        storage.saveNote(note3)

        let list = storage.getAllNotes()
        #expect(list.count == 3)
        #expect(list[0].id == note2.id)
        #expect(list[0].isPinned == true)
    }

    // 8. Template parsing
    @Test("Template engine parses flags and substitutes placeholders")
    func testTemplateParsingAndGeneration() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let engine = NoteTemplateEngine(storage: storage)

        let command = "!note /meeting --title \"Sprint Sync\" --b \"Discuss roadmap\""
        let parsed = NoteTemplateEngine.parseCommand(input: command)

        #expect(parsed != nil)
        #expect(parsed?.templateName == "meeting")
        #expect(parsed?.title == "Sprint Sync")
        #expect(parsed?.parameters["b"] == "Discuss roadmap")

        let note = engine.createNoteFromCommand(input: command)
        #expect(note != nil)
        #expect(note?.title == "Sprint Sync")
        #expect(note?.content.contains("# Sprint Sync") == true)
        #expect(note?.content.contains("Discuss roadmap") == true)
        #expect(note?.content.contains("## Action Items") == true)

        guard let unwrappedNote = note else {
            Issue.record("Expected non-nil note")
            return
        }

        // Verify note was stored
        let saved = storage.getNote(byId: unwrappedNote.id)
        #expect(saved != nil)
    }

    // 9. Markdown parsing with TitikPluginKit's MarkdownASTParser
    @Test("MarkdownASTParser decomposes markdown blocks without external dependencies")
    func testMarkdownASTParsing() {
        let markdown = """
        # Titik Notes Heading

        This is a paragraph with **bold** text and `inline code`.

        - [ ] Pending task
        - [x] Completed task

        ```swift
        let x = 42
        ```
        """

        let blocks = MarkdownASTParser.parse(markdown)
        #expect(!blocks.isEmpty)

        let hasHeading = blocks.contains(where: {
            if case .heading(let level, let text) = $0 {
                return level == 1 && text.contains("Titik Notes Heading")
            }
            return false
        })
        #expect(hasHeading)

        let hasCode = blocks.contains(where: {
            if case .codeBlock(let lang, let code) = $0 {
                return lang == "swift" && code.contains("let x = 42")
            }
            return false
        })
        #expect(hasCode)
    }

    // 10. Persistence round-trip
    @Test("Note frontmatter and body round-trip cleanly")
    func testNotePersistenceRoundTrip() {
        let id = UUID()
        let now = Date()
        let note = Note(
            id: id,
            title: "Frontmatter \"Test\"",
            content: "Body line 1\nBody line 2\n\n- item 1\n- item 2",
            isPinned: true,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now
        )

        let md = note.toMarkdown()
        let restored = Note.fromMarkdown(md)

        #expect(restored.id == note.id)
        #expect(restored.title == note.title)
        #expect(restored.content == note.content)
        #expect(restored.isPinned == note.isPinned)
        #expect(abs(restored.createdAt.timeIntervalSince(now)) < 1.0)
    }

    // 11. Title and Content fields in Note and NotesViewModel
    @Test("Title and Content fields in Note and NotesViewModel update and persist accurately")
    @MainActor
    func testTitleAndContentFields() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let config = NoteConfig(storageDirectoryPath: tempDir.path, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config, configURL: tempConfigURL)

        let initialNote = Note(title: "Initial Title", content: "Initial Body Markdown")
        storage.saveNote(initialNote)

        viewModel.openNote(initialNote)
        #expect(viewModel.activeNoteTitle == "Initial Title")
        #expect(viewModel.activeNoteContent == "Initial Body Markdown")

        // Edit Title and Content
        viewModel.activeNoteTitle = "Updated Title"
        viewModel.activeNoteContent = "Updated **Bold** Body"
        viewModel.saveCurrentNote()

        let reloaded = storage.getNote(byId: initialNote.id)
        #expect(reloaded?.title == "Updated Title")
        #expect(reloaded?.content == "Updated **Bold** Body")
    }

    // 12. Dynamic footerKeycaps in list and editor modes
    @Test("NotesPlugin exposes dynamic footerKeycaps according to active mode")
    @MainActor
    func testFooterKeycaps() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let plugin = NotesPlugin(context: PluginContext(pluginId: NotesPlugin.id))
        plugin.viewModel.configureDirectory(path: tempDir.path, saveToDisk: false)

        // List mode keycaps
        plugin.viewModel.mode = .list
        let listKeycaps = plugin.footerKeycaps
        #expect(listKeycaps == [
            KeycapAction(shortcut: "↑", label: "Navigate"),
            KeycapAction(shortcut: "↵", label: "Open"),
            KeycapAction(shortcut: "⌘N", label: "New"),
            KeycapAction(shortcut: "⌘P", label: "Pin"),
            KeycapAction(shortcut: "⌘,", label: "Folder"),
            KeycapAction(shortcut: "⌘⌫", label: "Delete"),
            KeycapAction(shortcut: "esc", label: "Close")
        ])

        // Editor mode keycaps
        let note = Note(title: "Sample", content: "Body")
        plugin.viewModel.openNote(note)
        let editorKeycaps = plugin.footerKeycaps
        #expect(editorKeycaps == [
            KeycapAction(shortcut: "⌘N", label: "New"),
            KeycapAction(shortcut: "⌘,", label: "Folder"),
            KeycapAction(shortcut: "⌘P", label: "Pin"),
            KeycapAction(shortcut: "⌘D", label: "Toggle Task"),
            KeycapAction(shortcut: "esc", label: "List")
        ])
    }

    // 13. createNewNote functionality
    @Test("createNewNote switches mode to editor and stores note immediately")
    @MainActor
    func testCreateNewNote() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let config = NoteConfig(storageDirectoryPath: tempDir.path, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config, configURL: tempConfigURL)

        #expect(viewModel.mode == .list)
        viewModel.createNewNote(title: "Meeting Notes", content: "- Action item 1")

        if case .editor(let note) = viewModel.mode {
            #expect(note.title == "Meeting Notes")
            #expect(note.content == "- Action item 1")
            #expect(viewModel.activeNoteTitle == "Meeting Notes")
            #expect(viewModel.activeNoteContent == "- Action item 1")

            let saved = storage.getNote(byId: note.id)
            #expect(saved != nil)
            #expect(saved?.title == "Meeting Notes")
        } else {
            Issue.record("Expected editor mode after createNewNote")
        }
    }

    // 14. Space-delimited bang activation contract (ADR 5)
    @Test("!note without space parses as .bangSuggestion; !note with space parses as .command and activates NotesPlugin")
    @MainActor
    func testNoteBangActivationContract() {
        let parser = CommandParser()
        let astNoSpace = parser.parse("!note")
        #expect(astNoSpace == .bangSuggestion(prefix: "note"))

        let astWithSpace = parser.parse("!note ")
        #expect(astWithSpace == .pluginInvocation(
            trigger: "note", action: nil, primaryValue: "", flags: [:], booleanFlags: [], rawTail: ""
        ))

        PluginManager.shared.reindex()
        let host = PluginHost.shared
        host.registerNativePlugin(NotesPlugin(context: PluginContext(pluginId: NotesPlugin.id)), manifest: notesPluginManifest)
        let manifest = host.findActivePlugin(command: "note")
        #expect(manifest != nil)
        #expect(manifest?.id == NotesPlugin.id)

        if let m = manifest, let native = host.getNativePlugin(id: m.id) {
            let ui = native as? (any PluginUIRepresentable)
            #expect(ui != nil)
            #expect(ui?.pluginId == NotesPlugin.id)
        }
    }

    // 15. Delimiter styling on active vs inactive lines
    @Test("Delimiter attributes are styled with font size 0.001 and clear color on inactive lines, subtle font and color on active lines")
    @MainActor
    func testDelimiterAttributesActiveVsInactive() {
        var textBinding = "## Heading 2\nLine two with **bold** text."
        let binding = Binding<String>(get: { textBinding }, set: { textBinding = $0 })
        let liveView = LiveMarkdownTextView(text: binding)
        let coordinator = liveView.makeCoordinator()

        let textStorage = NSTextStorage(string: textBinding)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 400, height: 1000))
        layoutManager.addTextContainer(textContainer)
        let textView = MarkdownNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000), textContainer: textContainer)
        coordinator.textView = textView

        // Case 1: Cursor on Line 2 (location: 20) -> Line 1 delimiter "## " is inactive
        textView.setSelectedRange(NSRange(location: 20, length: 0))
        coordinator.applyMarkdownAttributes(to: textStorage)

        let inactiveFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let inactiveColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(inactiveFont != nil)
        #expect(abs((inactiveFont?.pointSize ?? 0) - 0.001) < 0.0001)
        #expect(inactiveColor == NSColor.clear)

        // Case 2: Cursor moved to Line 1 (location: 4) -> Line 1 delimiter "## " becomes active
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        coordinator.applyMarkdownAttributes(to: textStorage)

        let activeFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let activeColor = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(activeFont != nil)
        #expect(abs((activeFont?.pointSize ?? 0) - 13.0) < 0.1)
        #expect(activeColor == NSColor.white.withAlphaComponent(0.35))

        // On line 2, bold delimiter "**" should now be inactive
        let nsString = textStorage.string as NSString
        let boldDelimRange = nsString.range(of: "**")
        #expect(boldDelimRange.location != NSNotFound)
        let boldDelimFont = textStorage.attribute(.font, at: boldDelimRange.location, effectiveRange: nil) as? NSFont
        let boldDelimColor = textStorage.attribute(.foregroundColor, at: boldDelimRange.location, effectiveRange: nil) as? NSColor
        #expect(abs((boldDelimFont?.pointSize ?? 0) - 0.001) < 0.0001)
        #expect(boldDelimColor == NSColor.clear)
    }

    // 16. Raw Markdown preservation on copy
    @Test("Copying from MarkdownNSTextView writes the raw Markdown string to pasteboard")
    @MainActor
    func testMarkdownNSTextViewPreservesRawMarkdownOnCopy() {
        let text = "## Heading\nSome **bold** and `code` text."
        let textStorage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 400, height: 1000))
        layoutManager.addTextContainer(textContainer)
        let textView = MarkdownNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000), textContainer: textContainer)

        let boldRange = (text as NSString).range(of: "**bold**")
        #expect(boldRange.location != NSNotFound)

        // 1. Test copy(_ sender:)
        textView.setSelectedRange(boldRange)
        textView.copy(nil)
        let pbString = NSPasteboard.general.string(forType: .string)
        #expect(pbString == "**bold**")

        // 2. Test writeSelection(to:types:)
        let customPb = NSPasteboard(name: NSPasteboard.Name("titik.test.notes.copy.\(UUID().uuidString)"))
        let wrote = textView.writeSelection(to: customPb, types: [.string])
        #expect(wrote == true)
        #expect(customPb.string(forType: .string) == "**bold**")
    }

    // 17. firstLineSnippet strips markdown syntax
    @Test("firstLineSnippet strips markdown syntax and returns clean preview")
    @MainActor
    func testFirstLineSnippetStripsMarkdown() {
        let headingText = "# Main Heading\nSecond line"
        #expect(NotesView.firstLineSnippet(content: headingText) == "Main Heading")

        let styledText = "Text with **bold** and *italic* and `code` formatting"
        #expect(NotesView.firstLineSnippet(content: styledText) == "Text with bold and italic and code formatting")

        let complexMarkdown = "### Section 1: **Important** update with `token`"
        #expect(NotesView.firstLineSnippet(content: complexMarkdown) == "Section 1: Important update with token")

        let emptyText = ""
        #expect(NotesView.firstLineSnippet(content: emptyText) == "")
    }

    // 18. Strict clean triggers
    @Test("Notes plugin manifest triggers are strictly note and n")
    func testStrictBangTriggers() {
        #expect(notesPluginManifest.triggers == ["note", "n"])
    }

    // 19. Todo stats computation
    @Test("Computes todo stats accurately for empty, zero, mixed, and complete checklists")
    func testTodoStatsComputation() {
        // No checkboxes
        let plainNote = Note(content: "Just plain text\nNo todos here")
        #expect(plainNote.todoStats == nil)

        // Mixed checkboxes
        let mixedContent = """
        # Tasks
        - [ ] Buy groceries
        - [x] Walk the dog
        - [X] Review pull request
        - [ ] Write tests
        """
        let mixedNote = Note(content: mixedContent)
        let stats = mixedNote.todoStats
        #expect(stats != nil)
        #expect(stats?.total == 4)
        #expect(stats?.completed == 2)
        #expect(stats?.pending == 2)
        #expect(stats?.isAllDone == false)
        #expect(stats?.progressFraction == 0.5)

        // 100% completed
        let allDoneContent = """
        - [x] Task 1
        - [X] Task 2
        """
        let allDoneNote = Note(content: allDoneContent)
        let allDoneStats = allDoneNote.todoStats
        #expect(allDoneStats != nil)
        #expect(allDoneStats?.total == 2)
        #expect(allDoneStats?.completed == 2)
        #expect(allDoneStats?.pending == 0)
        #expect(allDoneStats?.isAllDone == true)
        #expect(allDoneStats?.progressFraction == 1.0)
    }

    // 20. Checkbox toggle helper
    @Test("Note.toggleCheckbox toggles between unchecked, checked, and adds checkbox to plain line")
    func testToggleCheckboxHelper() {
        #expect(Note.toggleCheckbox(in: "- [ ] Buy milk") == "- [x] Buy milk")
        #expect(Note.toggleCheckbox(in: "- [x] Buy milk") == "- [ ] Buy milk")
        #expect(Note.toggleCheckbox(in: "- [X] Buy milk") == "- [ ] Buy milk")
        #expect(Note.toggleCheckbox(in: "  - [ ] Indented task") == "  - [x] Indented task")
        #expect(Note.toggleCheckbox(in: "  - [x] Indented task") == "  - [ ] Indented task")
        #expect(Note.toggleCheckbox(in: "Plain line without task") == "- [ ] Plain line without task")
        #expect(Note.toggleCheckbox(in: "") == "- [ ] ")
    }

    // 21. Keymap ⌘D Toggle Task registration
    @Test("keymapScope contains ⌘D with label Toggle Task in editor mode")
    @MainActor
    func testKeymapToggleTaskRegistration() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let note = Note(title: "Task Note", content: "- [ ] Task 1")
        storage.saveNote(note)

        let config = NoteConfig(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config)
        viewModel.openNote(note)

        if case .editor(let currentNote) = viewModel.mode {
            #expect(currentNote.id == note.id)
        } else {
            #expect(Bool(false), "Expected editor mode")
        }
        let keycaps = viewModel.keymapScope.keycaps
        let toggleKeycap = keycaps.first(where: { $0.shortcut == "⌘D" })
        #expect(toggleKeycap != nil)
        #expect(toggleKeycap?.label == "Toggle Task")
    }

    // 22. Todo search filter
    @Test("Filters notes containing tasks and sorts pending tasks first")
    @MainActor
    func testTodoSearchFilter() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let note1 = Note(title: "Plain Note", content: "No tasks here")
        let note2 = Note(title: "Done Note", content: "- [x] Finished item")
        let note3 = Note(title: "Pending Note", content: "- [ ] Task 1\n- [ ] Task 2")
        let note4 = Note(title: "Single Pending", content: "- [ ] Task A\n- [x] Task B")

        storage.saveNote(note1)
        storage.saveNote(note2)
        storage.saveNote(note3)
        storage.saveNote(note4)

        let config = NoteConfig(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config)

        // Filter by "todo"
        viewModel.handleSearchQuery("todo")
        #expect(viewModel.mode == .list)
        #expect(viewModel.notes.count == 3) // note2, note3, note4 (note1 excluded)
        #expect(viewModel.notes[0].title == "Pending Note") // 2 pending
        #expect(viewModel.notes[1].title == "Single Pending") // 1 pending
        #expect(viewModel.notes[2].title == "Done Note") // 0 pending

        // Bang trigger query "!n todo"
        viewModel.handleSearchQuery("!n todo")
        #expect(viewModel.notes.count == 3)
        #expect(viewModel.notes[0].title == "Pending Note")

        // Bang trigger query "!note todo"
        viewModel.handleSearchQuery("!note todo")
        #expect(viewModel.notes.count == 3)
        #expect(viewModel.notes[0].title == "Pending Note")
    }

    // 23. Return continuation in MarkdownNSTextView
    @Test("Pressing return continues task prefix or exits task mode on empty item")
    @MainActor
    func testReturnContinuation() {
        let textStorage = NSTextStorage(string: "- [ ] Task 1")
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 400, height: 1000))
        layoutManager.addTextContainer(textContainer)
        let textView = MarkdownNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000), textContainer: textContainer)

        // 1. Return at end of non-empty task item inserts \n- [ ]
        textView.setSelectedRange(NSRange(location: 12, length: 0))
        guard let returnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            Issue.record("Expected non-nil return event")
            return
        }
        textView.keyDown(with: returnEvent)
        #expect(textView.string == "- [ ] Task 1\n- [ ] ")

        // 2. Return on empty task item clears prefix and exits task mode
        guard let returnEvent2 = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            Issue.record("Expected non-nil return event 2")
            return
        }
        textView.keyDown(with: returnEvent2)
        #expect(textView.string == "- [ ] Task 1\n")
    }

    // 24. Template command stripping with !n
    @Test("NoteTemplateEngine parses command with !n prefix")
    func testTemplateEnginePrefixStripping() {
        let cmd = NoteTemplateEngine.parseCommand(input: "!n /meeting --title \"Weekly Standup\"")
        #expect(cmd != nil)
        #expect(cmd?.templateName == "meeting")
        #expect(cmd?.title == "Weekly Standup")

        let cmdNoSpace = NoteTemplateEngine.parseCommand(input: "!n/todo --title \"Quick Task\"")
        #expect(cmdNoSpace != nil)
        #expect(cmdNoSpace?.templateName == "todo")
        #expect(cmdNoSpace?.title == "Quick Task")
    }

    // 25. Cursor-aware task toggling
    @Test("Cursor-aware task toggling toggles only the line at cursor position")
    @MainActor
    func testCursorAwareTaskToggling() {
        let initialText = "- [ ] Task 1\n- [ ] Task 2\n- [ ] Task 3"
        let textStorage = NSTextStorage(string: initialText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 400, height: 1000))
        layoutManager.addTextContainer(textContainer)
        let textView = MarkdownNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000), textContainer: textContainer)

        // Line 1 is "- [ ] Task 1\n" (indices 0..<13)
        // Line 2 is "- [ ] Task 2\n" (indices 13..<26)
        // Line 3 is "- [ ] Task 3" (indices 26..<38)

        // Place cursor at line 2 (e.g., inside "Task 2")
        let task2Location = (initialText as NSString).range(of: "Task 2").location
        textView.setSelectedRange(NSRange(location: task2Location, length: 0))

        textView.toggleTaskAtCurrentLine()

        // Verify ONLY line 2 is toggled while line 1 and line 3 remain unchanged
        let expectedTextAfterLine2Toggle = "- [ ] Task 1\n- [x] Task 2\n- [ ] Task 3"
        #expect(textView.string == expectedTextAfterLine2Toggle)

        // Toggle again on line 2 -> reverts back to unchecked
        textView.toggleTaskAtCurrentLine()
        #expect(textView.string == initialText)

        // Place cursor at line 3 (inside "Task 3")
        let task3Location = (initialText as NSString).range(of: "Task 3").location
        textView.setSelectedRange(NSRange(location: task3Location, length: 0))

        textView.toggleTaskAtCurrentLine()

        // Verify ONLY line 3 is toggled while line 1 and line 2 remain unchanged
        let expectedTextAfterLine3Toggle = "- [ ] Task 1\n- [ ] Task 2\n- [x] Task 3"
        #expect(textView.string == expectedTextAfterLine3Toggle)
    }

    // 26. NotesViewModel.toggleActiveTask invokes onToggleTask closure
    @Test("NotesViewModel toggleActiveTask dispatches to registered onToggleTask closure")
    @MainActor
    func testViewModelOnToggleTaskInvoked() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let config = NoteConfig(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config)

        var invoked = false
        viewModel.onToggleTask = {
            invoked = true
        }

        viewModel.toggleActiveTask()
        #expect(invoked == true)
    }

    // 27. Setup keymap triggers
    @Test("Setup mode keymap triggers: Return, Cmd+D, and Esc")
    @MainActor
    func testSetupKeymapTriggers() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let unconfiguredConfig = NoteConfig(storageDirectoryPath: nil, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: nil)
        let viewModel = NotesViewModel(storage: storage, config: unconfiguredConfig, configURL: tempConfigURL)

        #expect(viewModel.mode == .setup)
        #expect(viewModel.canCancelSetup == false)

        // 1. Trigger "↵" with empty manualPathInput -> calls useDefaultDirectory()
        guard let returnEvent = makeKeyEvent(keyCode: Keycode.returnKey.rawValue) else {
            Issue.record("Expected non-nil return event")
            return
        }
        let handledReturn = viewModel.keymapScope.trigger(event: returnEvent)
        #expect(handledReturn == true)
        #expect(viewModel.mode == .list)
        #expect(viewModel.config.isConfigured == true)
        #expect(viewModel.config.storageDirectoryPath == NoteConfig.defaultNotesDirectory.path)
        #expect(FileManager.default.fileExists(atPath: tempConfigURL.path))

        // 2. Trigger "⌘D" -> calls useDefaultDirectory()
        viewModel.openFolderSetup()
        #expect(viewModel.mode == .setup)
        #expect(viewModel.canCancelSetup == true)

        guard let cmdDEvent = makeKeyEvent(keyCode: Keycode.d.rawValue, modifierFlags: [.command]) else {
            Issue.record("Expected non-nil Cmd+D event")
            return
        }
        let handledCmdD = viewModel.keymapScope.trigger(event: cmdDEvent)
        #expect(handledCmdD == true)
        #expect(viewModel.mode == .list)
        #expect(viewModel.config.isConfigured == true)

        // 3. Trigger "esc" when canCancelSetup is true -> reverts to .list
        viewModel.openFolderSetup()
        #expect(viewModel.mode == .setup)
        #expect(viewModel.canCancelSetup == true)

        guard let escEvent = makeKeyEvent(keyCode: Keycode.escape.rawValue) else {
            Issue.record("Expected non-nil Esc event")
            return
        }
        let handledEsc = viewModel.keymapScope.trigger(event: escEvent)
        #expect(handledEsc == true)
        #expect(viewModel.mode == .list)

        // 4. Trigger "esc" when canCancelSetup is false -> calls onDismiss
        let tempConfigURL2 = tempDir.appendingPathComponent("notes_config2.json")
        let unconfigured2 = NoteConfig(storageDirectoryPath: nil, configURL: tempConfigURL2)
        let storage2 = NoteStorage(storageDirectoryPath: nil)
        let viewModel2 = NotesViewModel(storage: storage2, config: unconfigured2, configURL: tempConfigURL2)
        var dismissed = false
        viewModel2.onDismiss = {
            dismissed = true
        }
        let handledEsc2 = viewModel2.keymapScope.trigger(event: escEvent)
        #expect(handledEsc2 == true)
        #expect(dismissed == true)
    }

    // 28. List mode keymap trigger: Cmd+, opens folder setup
    @Test("List mode keymap trigger: Cmd+, opens folder setup")
    @MainActor
    func testListKeymapFolderTrigger() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let config = NoteConfig(storageDirectoryPath: tempDir.path, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config, configURL: tempConfigURL)

        #expect(viewModel.mode == .list)

        guard let cmdCommaEvent = makeKeyEvent(keyCode: Keycode.comma.rawValue, modifierFlags: [.command]) else {
            Issue.record("Expected non-nil Cmd+, event")
            return
        }
        let handledCmdComma = viewModel.keymapScope.trigger(event: cmdCommaEvent)
        #expect(handledCmdComma == true)
        #expect(viewModel.mode == .setup)
        #expect(viewModel.manualPathInput == tempDir.path)
        #expect(viewModel.canCancelSetup == true)
    }

    // 29. Sub-command routing for folder configuration
    @Test("Sub-command routing: !note folder, !n config, folder, and settings switch to .setup")
    @MainActor
    func testFolderSubcommandRouting() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let config = NoteConfig(storageDirectoryPath: tempDir.path, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config, configURL: tempConfigURL)

        #expect(viewModel.mode == .list)

        // Query "!note folder"
        viewModel.handleSearchQuery("!note folder")
        #expect(viewModel.mode == .setup)
        #expect(viewModel.searchQuery == "folder")

        // Revert back to list
        viewModel.mode = .list

        // Query "!n config"
        viewModel.handleSearchQuery("!n config")
        #expect(viewModel.mode == .setup)
        #expect(viewModel.searchQuery == "config")

        // Revert back to list
        viewModel.mode = .list

        // Query "folder"
        viewModel.handleSearchQuery("folder")
        #expect(viewModel.mode == .setup)
        #expect(viewModel.searchQuery == "folder")

        // Revert back to list
        viewModel.mode = .list

        // Query "settings"
        viewModel.handleSearchQuery("settings")
        #expect(viewModel.mode == .setup)
        #expect(viewModel.searchQuery == "settings")
    }

    // 30. Disk persistence after configuring directory
    @Test("Creates and persists notes to disk after directory configuration")
    @MainActor
    func testDiskPersistenceAfterDefaultDirectory() throws {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let tempConfigURL = tempDir.appendingPathComponent("notes_config.json")
        let unconfiguredConfig = NoteConfig(storageDirectoryPath: nil, configURL: tempConfigURL)
        let storage = NoteStorage(storageDirectoryPath: nil)
        let viewModel = NotesViewModel(storage: storage, config: unconfiguredConfig, configURL: tempConfigURL)

        #expect(viewModel.mode == .setup)
        viewModel.configureDirectory(path: tempDir.path)
        #expect(viewModel.mode == .list)
        #expect(viewModel.config.isConfigured == true)
        #expect(viewModel.config.storageDirectoryPath == tempDir.path)

        let noteTitle = "Persistence Verification \(UUID().uuidString)"
        let noteContent = "Testing persistent storage after default onboarding."
        viewModel.createNewNote(title: noteTitle, content: noteContent)

        guard let noteId = viewModel.activeNoteId else {
            Issue.record("Expected activeNoteId after creating note")
            return
        }

        // Verify storage contains note
        let loadedFromVM = viewModel.storage.getNote(byId: noteId)
        #expect(loadedFromVM != nil)
        #expect(loadedFromVM?.title == noteTitle)
        #expect(loadedFromVM?.content == noteContent)

        // Verify file exists on disk as a .md file
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let mdFiles = files.filter { $0.pathExtension == "md" }
        #expect(mdFiles.contains(where: {
            guard let content = try? String(contentsOf: $0, encoding: .utf8) else { return false }
            return content.contains(noteId.uuidString)
        }))

        // Re-create NoteStorage pointing to tempDir.path
        let newStorage = NoteStorage(storageDirectoryPath: tempDir.path)
        let reloadedNote = newStorage.getNote(byId: noteId)
        #expect(reloadedNote != nil)
        #expect(reloadedNote?.title == noteTitle)
        #expect(reloadedNote?.content == noteContent)
    }

    // 31. changeStorageFolder flushes active note changes before entering setup
    @Test("changeStorageFolder flushes active note changes before switching to setup mode")
    @MainActor
    func testChangeStorageFolderFlushesActiveNote() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let config = NoteConfig(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config)

        let initialNote = Note(title: "Initial Title", content: "Initial Body")
        storage.saveNote(initialNote)

        viewModel.openNote(initialNote)
        if case .editor(let currentNote) = viewModel.mode {
            #expect(currentNote.id == initialNote.id)
        } else {
            Issue.record("Expected editor mode after opening note")
        }

        // Modify in-memory active title and content without calling saveCurrentNote explicitly
        viewModel.activeNoteTitle = "Updated Title"
        viewModel.activeNoteContent = "Updated Body with new content"

        // Trigger changeStorageFolder
        viewModel.changeStorageFolder()

        // Verify mode transitioned to setup
        #expect(viewModel.mode == .setup)

        // Verify storage contains updated note content flushed by changeStorageFolder
        let persisted = storage.getNote(byId: initialNote.id)
        #expect(persisted != nil)
        #expect(persisted?.title == "Updated Title")
        #expect(persisted?.content == "Updated Body with new content")
    }

    // 32. Editor mode keymap trigger: Cmd+N creates a new note
    @Test("Editor mode keymap trigger: Cmd+N creates a new note")
    @MainActor
    func testEditorModeCmdNTrigger() {
        let tempDir = makeTempDir()
        defer { cleanup(dir: tempDir) }

        let storage = NoteStorage(storageDirectoryPath: tempDir.path)
        let config = NoteConfig(storageDirectoryPath: tempDir.path)
        let viewModel = NotesViewModel(storage: storage, config: config)

        let initialNote = Note(title: "Initial Note", content: "Existing content")
        storage.saveNote(initialNote)
        viewModel.openNote(initialNote)

        if case .editor(let currentNote) = viewModel.mode {
            #expect(currentNote.id == initialNote.id)
        } else {
            Issue.record("Expected editor mode after openNote")
        }
        #expect(viewModel.activeNoteId == initialNote.id)

        // Modify in-progress content to ensure dirty edits are saved
        viewModel.activeNoteContent = "Existing content with edits"

        guard let cmdNEvent = makeKeyEvent(keyCode: Keycode.n.rawValue, modifierFlags: [.command]) else {
            Issue.record("Expected non-nil Cmd+N event")
            return
        }

        let handled = viewModel.keymapScope.trigger(event: cmdNEvent)
        #expect(handled == true)

        // Verify that in editor mode, a new note is created and opened
        if case .editor(let newNote) = viewModel.mode {
            #expect(newNote.id != initialNote.id)
            #expect(viewModel.activeNoteId == newNote.id)
            #expect(newNote.title == "Untitled Note")
        } else {
            Issue.record("Expected editor mode with new note")
        }

        // Verify original note was saved with dirty in-progress edits
        let savedInitial = storage.getNote(byId: initialNote.id)
        #expect(savedInitial?.content == "Existing content with edits")
    }
}
