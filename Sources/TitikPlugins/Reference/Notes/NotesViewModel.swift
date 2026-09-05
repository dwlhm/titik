import Foundation
import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikPluginKit
import TitikUI

/// View model managing notes presentation state, folder setup, search filtering, and live editing.
@MainActor
public final class NotesViewModel: ObservableObject {
    public enum Mode: Equatable {
        case setup
        case list
        case editor(Note)
    }

    @Published public var mode: Mode = .list {
        didSet {
            updateKeymapScope()
        }
    }
    @Published public var notes: [Note] = []
    @Published public var selectedIndex: Int = 0
    @Published public var searchQuery: String = ""
    @Published public var config: NoteConfig

    public let keymapScope = PluginKeymapScope()
    public var onDismiss: (@MainActor () -> Void)?

    // Active Editor State
    @Published public var activeNoteTitle: String = ""
    @Published public var activeNoteContent: String = ""
    @Published public var activeNoteIsPinned: Bool = false
    @Published public var activeNoteId: UUID?

    public var isTitleFocused: Bool = false
    public var onTabFromTitle: (() -> Void)?
    public var onShiftTabFromContent: (() -> Void)?
    public var onToggleTask: (() -> Void)?

    // Setup State
    @Published public var manualPathInput: String = "" {
        didSet {
            if mode == .setup {
                updateKeymapScope()
            }
        }
    }
    @Published public var setupError: String?

    public var canCancelSetup: Bool {
        config.isConfigured
    }

    public let storage: NoteStorage
    public let templateEngine: NoteTemplateEngine
    public var configURL: URL?

    public init(storage: NoteStorage? = nil, config: NoteConfig? = nil, configURL: URL? = nil) {
        let loadedConfig = config ?? NoteConfig.load(from: configURL ?? NoteConfig.defaultConfigURL)
        self.config = loadedConfig
        self.configURL = configURL ?? loadedConfig.configURL
        let activeStorage = storage ?? NoteStorage(storageDirectoryPath: loadedConfig.storageDirectoryPath)
        self.storage = activeStorage
        self.templateEngine = NoteTemplateEngine(storage: activeStorage)

        if !loadedConfig.isConfigured {
            self.mode = .setup
        } else {
            self.mode = .list
            self.reloadNotes()
        }
        self.updateKeymapScope()
    }

    // MARK: - Data Reloading

    public func reloadNotes(searchQuery: String? = nil) {
        let results = storage.getAllNotes(searchQuery: searchQuery)
        self.notes = results
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }

    public func reloadTodoNotes(keyword: String? = nil) {
        let baseNotes = storage.getAllNotes(searchQuery: keyword)
        self.notes = baseNotes.filter { $0.todoStats != nil }.sorted {
            let p0 = $0.todoStats?.pending ?? 0
            let p1 = $1.todoStats?.pending ?? 0
            if p0 != p1 {
                return p0 > p1
            }
            return $0.updatedAt > $1.updatedAt
        }
        if selectedIndex >= self.notes.count {
            selectedIndex = max(0, self.notes.count - 1)
        }
    }

    // MARK: - Navigation & Routing

    public func handleSearchQuery(_ query: String) {
        guard config.isConfigured else {
            self.mode = .setup
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // 1. Template command: starts with "/"
        if trimmed.hasPrefix("/") {
            self.searchQuery = trimmed
            return
        }

        var normalized = trimmed
        if normalized.hasPrefix("!note ") {
            normalized = String(normalized.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if normalized.hasPrefix("!n ") {
            normalized = String(normalized.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if normalized == "!note" || normalized == "!n" {
            normalized = ""
        }

        // 2. Folder configuration sub-command: "folder", "config", "settings"
        if normalized == "folder" || normalized == "config" || normalized == "settings" ||
           trimmed == "!note folder" || trimmed == "!n folder" ||
           trimmed == "!note config" || trimmed == "!n config" ||
           trimmed == "!note settings" || trimmed == "!n settings" {
            self.searchQuery = normalized
            self.openFolderSetup()
            return
        }

        // 3. To-Do filter sub-command: "todo" or "todo <keyword>"
        if normalized == "todo" || normalized.hasPrefix("todo ") || trimmed == "!note todo" || trimmed == "!n todo" {
            self.mode = .list
            let keyword: String?
            if normalized == "todo" || trimmed == "!note todo" || trimmed == "!n todo" {
                keyword = nil
            } else {
                let kw = String(normalized.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                keyword = kw.isEmpty ? nil : kw
            }
            self.searchQuery = normalized
            self.reloadTodoNotes(keyword: keyword)
            return
        }

        // 3. Explicit "!note list" or "!note list <keyword>"
        if trimmed == "list" || normalized == "list" {
            self.mode = .list
            self.searchQuery = ""
            self.reloadNotes(searchQuery: nil)
            return
        } else if trimmed.hasPrefix("list ") || normalized.hasPrefix("list ") {
            self.mode = .list
            let rawKw = trimmed.hasPrefix("list ") ? String(trimmed.dropFirst(5)) : String(normalized.dropFirst(5))
            let keyword = rawKw.trimmingCharacters(in: .whitespaces)
            self.searchQuery = keyword
            self.reloadNotes(searchQuery: keyword)
            return
        }

        // 4. Default empty query: "!note " -> opens pinned, last opened, or creates new
        if trimmed.isEmpty || normalized.isEmpty {
            self.searchQuery = ""
            openDefaultNote()
            return
        }

        // 5. If in editor mode, do not abruptly reset mode = .list unless user explicitly typed "list" or "todo"
        if case .editor = mode {
            return
        }

        // 6. In-plugin search query fallback
        self.mode = .list
        self.searchQuery = trimmed
        self.reloadNotes(searchQuery: trimmed)
    }

    public func onActivated() {
        guard config.isConfigured else {
            self.mode = .setup
            return
        }
        if case .editor = mode {
            isTitleFocused = true
            return
        }
    }

    public func submitQuery() {
        guard config.isConfigured else {
            if !manualPathInput.trimmingCharacters(in: .whitespaces).isEmpty {
                configureDirectory(path: manualPathInput)
            }
            return
        }

        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") {
            if let note = templateEngine.createNoteFromCommand(input: trimmed) {
                openNote(note)
            }
            return
        }

        if case .list = mode {
            openSelectedNote()
        }
    }

    // MARK: - Note Actions

    public func createNewNote(title: String = "", content: String = "") {
        saveCurrentNote()
        let newNote = Note(
            id: UUID(),
            title: title.isEmpty ? "Untitled Note" : title,
            content: content,
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date(),
            lastOpenedAt: Date()
        )
        storage.saveNote(newNote)
        openNote(newNote)
    }

    /// Opens pinned note if exists, or last opened/updated note, or creates a new note.
    public func openDefaultNote() {
        if let pinned = storage.getPinnedNote() {
            openNote(pinned)
        } else if let last = storage.getLastOpenedNote() {
            openNote(last)
        } else {
            createNewNote()
        }
    }

    public func openNote(_ note: Note) {
        var updated = note
        updated.lastOpenedAt = Date()
        storage.saveNote(updated)

        self.activeNoteId = updated.id
        self.activeNoteTitle = updated.title
        self.activeNoteContent = updated.content
        self.activeNoteIsPinned = updated.isPinned
        self.mode = .editor(updated)
    }

    public func openSelectedNote() {
        guard selectedIndex >= 0 && selectedIndex < notes.count else { return }
        openNote(notes[selectedIndex])
    }

    public func saveCurrentNote() {
        guard let id = activeNoteId else { return }
        var note = storage.getNote(byId: id) ?? Note(id: id)
        note.title = activeNoteTitle
        note.content = activeNoteContent
        note.isPinned = activeNoteIsPinned
        note.updatedAt = Date()
        note.lastOpenedAt = Date()
        storage.saveNote(note)
    }

    public func toggleActiveTask() {
        if let onToggleTask = onToggleTask {
            onToggleTask()
            return
        }
        guard !activeNoteContent.isEmpty else {
            activeNoteContent = "- [ ] "
            saveCurrentNote()
            return
        }
        var lines = activeNoteContent.components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
        }) {
            lines[index] = Note.toggleCheckbox(in: lines[index])
        } else if !lines.isEmpty {
            lines[0] = Note.toggleCheckbox(in: lines[0])
        }
        activeNoteContent = lines.joined(separator: "\n")
        saveCurrentNote()
    }

    public func togglePinCurrentNote() {
        guard let id = activeNoteId else { return }
        let newPinState = !activeNoteIsPinned
        activeNoteIsPinned = newPinState
        storage.setPinned(noteId: id, isPinned: newPinState)
    }

    public func deleteCurrentNote() {
        guard let id = activeNoteId else { return }
        storage.deleteNote(noteId: id)
        activeNoteId = nil
        self.mode = .list
        reloadNotes()
    }

    public func exitEditor() {
        saveCurrentNote()
        self.mode = .list
        reloadNotes()
    }

    public func selectPrevious() {
        guard !notes.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    public func selectNext() {
        guard !notes.isEmpty else { return }
        selectedIndex = min(notes.count - 1, selectedIndex + 1)
    }

    public func togglePinSelectedNote() {
        guard selectedIndex >= 0 && selectedIndex < notes.count else { return }
        let note = notes[selectedIndex]
        storage.setPinned(noteId: note.id, isPinned: !note.isPinned)
        reloadNotes(searchQuery: searchQuery.isEmpty ? nil : searchQuery)
    }

    public func deleteSelectedNote() {
        guard selectedIndex >= 0 && selectedIndex < notes.count else { return }
        let note = notes[selectedIndex]
        storage.deleteNote(noteId: note.id)
        reloadNotes(searchQuery: searchQuery.isEmpty ? nil : searchQuery)
    }

    // MARK: - Setup Directory Configuration

    public func changeStorageFolder() {
        if case .editor = mode {
            saveCurrentNote()
        }
        openFolderSetup()
    }

    public func openFolderSetup() {
        manualPathInput = config.storageDirectoryPath ?? ""
        setupError = nil
        mode = .setup
    }

    public func configureDirectory(path: String, saveToDisk: Bool = true) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            config.storageDirectoryPath = path
            if saveToDisk {
                do {
                    try config.save(to: configURL)
                } catch {
                    // Non-fatal if config file cannot be written (e.g. sandbox or read-only test)
                }
            }
            storage.updateStorageDirectory(path)
            self.setupError = nil
            self.mode = .list
            reloadNotes()
        } catch {
            self.setupError = error.localizedDescription
        }
    }

    public func chooseFolderWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Notes Folder"
        if panel.runModal() == .OK, let url = panel.url {
            configureDirectory(path: url.path)
        }
    }

    public func useDefaultDirectory() {
        configureDirectory(path: NoteConfig.defaultNotesDirectory.path)
    }

    // MARK: - Keymap Scope Handling

    public func updateKeymapScope() {
        switch mode {
        case .list:
            keymapScope.removeAll()
            keymapScope.register("↑", label: "Navigate") { [weak self] in self?.selectPrevious() }
            keymapScope.register("↓") { [weak self] in self?.selectNext() }
            keymapScope.register("↵", label: "Open") { [weak self] in
                guard let self = self else { return }
                if !self.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.submitQuery()
                } else {
                    self.openSelectedNote()
                }
            }
            keymapScope.register("⌘N", label: "New") { [weak self] in self?.createNewNote() }
            keymapScope.register("⌘P", label: "Pin") { [weak self] in self?.togglePinSelectedNote() }
            keymapScope.register("⌘,", label: "Folder") { [weak self] in
                self?.openFolderSetup()
            }
            keymapScope.register("⌘⌫", label: "Delete") { [weak self] in self?.deleteSelectedNote() }
            keymapScope.register("esc", label: "Close") { [weak self] in self?.onDismiss?() }

        case .editor:
            keymapScope.removeAll()
            keymapScope.register("⌘N", label: "New") { [weak self] in self?.createNewNote() }
            keymapScope.register("⌘,", label: "Folder") { [weak self] in self?.changeStorageFolder() }
            keymapScope.register("⌘P", label: "Pin") { [weak self] in self?.togglePinCurrentNote() }
            keymapScope.register("⌘D", label: "Toggle Task") { [weak self] in self?.toggleActiveTask() }
            keymapScope.register("esc", label: "List") { [weak self] in self?.exitEditor() }

        case .setup:
            keymapScope.removeAll()
            let confirmLabel = manualPathInput.trimmingCharacters(in: .whitespaces).isEmpty ? "Use Default" : "Confirm"
            keymapScope.register("↵", label: confirmLabel) { [weak self] in
                guard let self = self else { return }
                let trimmed = self.manualPathInput.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    self.useDefaultDirectory()
                } else {
                    self.configureDirectory(path: trimmed)
                }
            }
            keymapScope.register("⌘D", label: "Default") { [weak self] in
                self?.useDefaultDirectory()
            }
            keymapScope.register("⌘O", label: "Browse") { [weak self] in
                self?.chooseFolderWithOpenPanel()
            }
            keymapScope.register("esc", label: "Close") { [weak self] in
                guard let self = self else { return }
                if self.canCancelSetup {
                    self.mode = .list
                    self.reloadNotes()
                } else {
                    self.onDismiss?()
                }
            }
        }
    }
}
