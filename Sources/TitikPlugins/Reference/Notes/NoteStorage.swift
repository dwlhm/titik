import Foundation

/// Thread-safe storage layer managing flat Markdown notes and templates on disk.
public final class NoteStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var directoryPath: String?
    private var notesCache: [Note] = []
    private var idToFilename: [UUID: String] = [:]

    public init(storageDirectoryPath: String? = nil) {
        self.directoryPath = storageDirectoryPath
        reloadNotes()
    }

    /// Resolves the file URL for the storage directory.
    public var directoryURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let path = directoryPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Updates the configured storage directory and reloads notes.
    public func updateStorageDirectory(_ newPath: String?) {
        lock.lock()
        self.directoryPath = newPath
        lock.unlock()
        reloadNotes()
    }

    /// Rescans the storage directory and refreshes in-memory cache.
    public func reloadNotes() {
        lock.lock()
        defer { lock.unlock() }

        guard let path = directoryPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notesCache = []
            idToFilename = [:]
            return
        }

        let expanded = (path as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expanded)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            notesCache = []
            idToFilename = [:]
            return
        }

        guard let contents = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            notesCache = []
            idToFilename = [:]
            return
        }

        var loadedNotes: [Note] = []
        var filenameMap: [UUID: String] = [:]
        var seenPinned = false

        for fileURL in contents where fileURL.pathExtension.lowercased() == "md" {
            let filename = fileURL.lastPathComponent
            // Skip files in templates subdirectory if encountered
            if fileURL.deletingPathExtension().lastPathComponent.lowercased() == "templates" {
                continue
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            var note = Note.fromMarkdown(text, defaultTitle: fileURL.deletingPathExtension().lastPathComponent, filename: filename)
            note.filename = filename

            // Enforce single pinned note guarantee: only the first pinned note encountered stays pinned
            if note.isPinned {
                if seenPinned {
                    note.isPinned = false
                } else {
                    seenPinned = true
                }
            }

            loadedNotes.append(note)
            filenameMap[note.id] = filename
        }

        self.notesCache = loadedNotes
        self.idToFilename = filenameMap
    }

    /// Retrieves all notes, optionally filtered by a search query against title and content.
    /// The pinned note is strictly locked at index 0 if it matches (or if query is nil/empty).
    public func getAllNotes(searchQuery: String? = nil) -> [Note] {
        lock.lock()
        defer { lock.unlock() }

        let all = notesCache

        guard let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return sortNotesWithPinnedFirst(all)
        }

        let lowerQuery = query.lowercased()
        let filtered = all.filter { note in
            note.title.lowercased().contains(lowerQuery) ||
            note.content.lowercased().contains(lowerQuery)
        }

        return sortNotesWithPinnedFirst(filtered)
    }

    public func getNote(byId id: UUID) -> Note? {
        lock.lock()
        defer { lock.unlock() }
        return notesCache.first(where: { $0.id == id })
    }

    /// Returns the active pinned note if one exists.
    public func getPinnedNote() -> Note? {
        lock.lock()
        defer { lock.unlock() }
        return notesCache.first(where: { $0.isPinned })
    }

    /// Returns the last opened or updated note.
    public func getLastOpenedNote() -> Note? {
        lock.lock()
        defer { lock.unlock() }
        return notesCache.max(by: {
            max($0.lastOpenedAt, $0.updatedAt) < max($1.lastOpenedAt, $1.updatedAt)
        })
    }

    /// Saves a note to disk and updates in-memory cache.
    /// If `isPinned` is true, automatically unpins all other notes to satisfy the single pinned invariant.
    public func saveNote(_ note: Note) {
        lock.lock()
        defer { lock.unlock() }

        var noteToSave = note

        // If this note is pinned, unpin all others
        if noteToSave.isPinned {
            for i in 0..<notesCache.count {
                if notesCache[i].id != noteToSave.id && notesCache[i].isPinned {
                    notesCache[i].isPinned = false
                    writeNoteToDisk(notesCache[i])
                }
            }
        }

        let filename = resolveFilename(for: noteToSave)
        noteToSave.filename = filename

        if let index = notesCache.firstIndex(where: { $0.id == noteToSave.id }) {
            notesCache[index] = noteToSave
        } else {
            notesCache.append(noteToSave)
        }

        idToFilename[noteToSave.id] = filename
        writeNoteToDisk(noteToSave)
    }

    /// Toggles or updates the pinned state of a specific note.
    public func setPinned(noteId: UUID, isPinned: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if isPinned {
            // Unpin all notes except target
            for i in 0..<notesCache.count {
                if notesCache[i].id != noteId && notesCache[i].isPinned {
                    notesCache[i].isPinned = false
                    writeNoteToDisk(notesCache[i])
                }
            }
        }

        if let index = notesCache.firstIndex(where: { $0.id == noteId }) {
            notesCache[index].isPinned = isPinned
            writeNoteToDisk(notesCache[index])
        }
    }

    /// Deletes a note from disk and memory cache.
    public func deleteNote(noteId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard let dirURL = resolvedDirectoryURL() else { return }

        if let filename = idToFilename[noteId] {
            let fileURL = dirURL.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: fileURL)
            idToFilename.removeValue(forKey: noteId)
        }

        notesCache.removeAll(where: { $0.id == noteId })
    }

    // MARK: - Templates Management

    public func templatesDirectoryURL() -> URL? {
        guard let dir = resolvedDirectoryURL() else { return nil }
        return dir.appendingPathComponent("templates", isDirectory: true)
    }

    public func listTemplates() -> [String] {
        guard let tmplDir = templatesDirectoryURL(),
              FileManager.default.fileExists(atPath: tmplDir.path),
              let files = try? FileManager.default.contentsOfDirectory(at: tmplDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    public func getTemplate(named name: String) -> String? {
        guard let tmplDir = templatesDirectoryURL() else { return nil }
        let fileURL = tmplDir.appendingPathComponent("\(name).md")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveTemplate(named name: String, content: String) {
        guard let tmplDir = templatesDirectoryURL() else { return }
        if !FileManager.default.fileExists(atPath: tmplDir.path) {
            try? FileManager.default.createDirectory(at: tmplDir, withIntermediateDirectories: true)
        }
        let fileURL = tmplDir.appendingPathComponent("\(name).md")
        try? Data(content.utf8).write(to: fileURL, options: .atomic)
    }

    // MARK: - Private Helpers

    private func resolvedDirectoryURL() -> URL? {
        guard let path = directoryPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    private func resolveFilename(for note: Note) -> String {
        if let existing = idToFilename[note.id], !existing.isEmpty {
            return existing
        }

        let cleanTitle = sanitizeFilename(note.title)
        let baseName = cleanTitle.isEmpty ? "Untitled" : cleanTitle
        var candidate = "\(baseName).md"

        // Avoid collision with other note IDs
        if let collisionId = idToFilename.first(where: { $0.value.lowercased() == candidate.lowercased() && $0.key != note.id })?.key {
            _ = collisionId
            candidate = "\(baseName)-\(note.id.uuidString.prefix(8)).md"
        }

        return candidate
    }

    private func sanitizeFilename(_ title: String) -> String {
        var sanitized = title
            .replacingOccurrences(of: "[/\\\\?%*|\":<>]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 64 {
            sanitized = String(sanitized.prefix(64))
        }
        return sanitized
    }

    private func writeNoteToDisk(_ note: Note) {
        guard let dirURL = resolvedDirectoryURL() else { return }
        let filename = idToFilename[note.id] ?? resolveFilename(for: note)
        idToFilename[note.id] = filename

        let fileURL = dirURL.appendingPathComponent(filename)
        let markdown = note.toMarkdown()
        try? Data(markdown.utf8).write(to: fileURL, options: .atomic)
    }

    private func sortNotesWithPinnedFirst(_ list: [Note]) -> [Note] {
        var pinned: [Note] = []
        var unpinned: [Note] = []

        for note in list {
            if note.isPinned {
                pinned.append(note)
            } else {
                unpinned.append(note)
            }
        }

        unpinned.sort {
            max($0.lastOpenedAt, $0.updatedAt) > max($1.lastOpenedAt, $1.updatedAt)
        }

        return pinned + unpinned
    }
}
