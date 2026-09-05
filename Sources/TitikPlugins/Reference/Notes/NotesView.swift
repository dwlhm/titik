import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikUI

public struct NotesView: View {
    @ObservedObject public var viewModel: NotesViewModel

    private enum FocusField: Hashable {
        case title
        case content
    }

    @FocusState private var focusedField: FocusField?

    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch viewModel.mode {
            case .setup:
                setupCTAView
            case .list:
                notesListView
            case .editor:
                editorView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.springInteractive, value: viewModel.mode)
        .onAppear {
            if case .editor = viewModel.mode {
                focusedField = .title
            }
            viewModel.onTabFromTitle = {
                focusedField = .content
            }
            viewModel.onShiftTabFromContent = {
                focusedField = .title
            }
        }
        .onChange(of: viewModel.mode) { [oldMode = viewModel.mode] newMode in
            if case .editor = newMode, case .editor = oldMode {
                return // Already in editor; preserve user's active focus!
            }
            if case .editor = newMode {
                focusedField = .title
            }
        }
        .onChange(of: focusedField) { newField in
            viewModel.isTitleFocused = (newField == .title)
        }
    }

    // MARK: - Setup CTA View

    private var setupCTAView: some View {
        VStack(spacing: 20) {
            if viewModel.canCancelSetup {
                HStack {
                    Button(action: {
                        viewModel.mode = .list
                        viewModel.reloadNotes()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back to Notes")
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            Spacer()

            VStack(spacing: 8) {
                Text("📝")
                    .font(.system(size: 44))

                Text(viewModel.canCancelSetup ? "Change Notes Folder" : "Welcome to Titik Notes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                if viewModel.canCancelSetup, let currentPath = viewModel.config.storageDirectoryPath {
                    Text("Current folder: \(currentPath)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                }

                Text("Choose a folder to store your Markdown notes flatly.\nCompatible with Obsidian, Logseq, and plain text files.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.chooseFolderWithOpenPanel()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text("Choose Folder...")
                            shortcutBadge("⌘O")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        viewModel.useDefaultDirectory()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Use Default (~/.config/titik/notes)")
                            shortcutBadge("↵")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Text("Press ↵ to quickly initialize default folder")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textMuted)

                HStack(spacing: 8) {
                    TextField("Or enter custom directory path...", text: $viewModel.manualPathInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    Button(action: {
                        viewModel.configureDirectory(path: viewModel.manualPathInput)
                    }) {
                        Text("Confirm")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.manualPathInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(maxWidth: 440)

                if let error = viewModel.setupError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.9))
                }
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - List Mode View

    private var notesListView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 6) {
                    Text("📝")
                    Text("Notes")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                }

                Spacer()

                if !viewModel.searchQuery.isEmpty {
                    Text("Filter: \"\(viewModel.searchQuery)\"")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.accent)
                }

                Text("\(viewModel.notes.count) note\(viewModel.notes.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)

                Button(action: {
                    viewModel.openFolderSetup()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Folder")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Change Notes Folder (⌘,)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.12))

            // Notes list
            if viewModel.notes.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "note.text")
                        .font(.system(size: 32))
                        .foregroundColor(Color.white.opacity(0.3))
                    Text(viewModel.searchQuery.isEmpty ? "No notes found in folder" : "No notes matching \"\(viewModel.searchQuery)\"")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                    Text("Type `!note ` or press ↵ to create a new note")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textMuted.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(viewModel.notes.enumerated()), id: \.element.id) { index, note in
                                noteRow(note: note, index: index)
                                    .id(note.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < viewModel.notes.count {
                            withAnimation(Theme.springInteractive) {
                                proxy.scrollTo(viewModel.notes[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private func noteRow(note: Note, index: Int) -> some View {
        let isSelected = (index == viewModel.selectedIndex)
        let snippet = firstLineSnippet(content: note.content)

        return HStack(spacing: 10) {
            // Pin indicator
            if note.isPinned {
                Text("📌")
                    .font(.system(size: 12))
            } else {
                Text("  ")
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(note.title.isEmpty ? "Untitled Note" : note.title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if let stats = note.todoStats {
                        HStack(spacing: 4) {
                            Image(systemName: stats.isAllDone ? "checkmark.circle.fill" : "checklist")
                                .font(.system(size: 11))
                            Text("\(stats.completed)/\(stats.total)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(stats.isAllDone ? .green : .orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (stats.isAllDone ? Color.green : Color.orange).opacity(0.12)
                        )
                        .cornerRadius(4)
                    }

                    Text(formattedRelativeDate(note.updatedAt))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }

                if !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Theme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedIndex = index
            viewModel.openSelectedNote()
        }
    }

    // MARK: - Editor Mode View

    private var editorView: some View {
        VStack(spacing: 0) {
            // Editor header
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.exitEditor()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("List")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                ZStack(alignment: .leading) {
                    if viewModel.activeNoteTitle.isEmpty {
                        Text("Note Title")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.textMuted.opacity(0.6))
                    }
                    TextField("Note Title", text: $viewModel.activeNoteTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .focused($focusedField, equals: .title)
                        .onSubmit {
                            focusedField = .content
                        }
                        .onChange(of: viewModel.activeNoteTitle) { _ in
                            viewModel.saveCurrentNote()
                        }
                }

                Spacer()

                if let stats = Note(content: viewModel.activeNoteContent).todoStats {
                    HStack(spacing: 4) {
                        Image(systemName: stats.isAllDone ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 11))
                        Text("\(stats.completed)/\(stats.total) tasks")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(stats.isAllDone ? .green : Theme.textMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }

                Button(action: {
                    viewModel.changeStorageFolder()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Folder")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Change Notes Folder (⌘,)")

                Button(action: {
                    viewModel.togglePinCurrentNote()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.activeNoteIsPinned ? "pin.fill" : "pin")
                            .foregroundColor(viewModel.activeNoteIsPinned ? .orange : Theme.textMuted)
                        Text(viewModel.activeNoteIsPinned ? "Pinned" : "Pin")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.deleteCurrentNote()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.12))

            // Live Markdown Text Area
            LiveMarkdownTextView(
                text: $viewModel.activeNoteContent,
                isFocused: focusedField == .content,
                onSave: {
                    viewModel.saveCurrentNote()
                },
                onPinToggle: {
                    viewModel.togglePinCurrentNote()
                },
                onExit: {
                    viewModel.exitEditor()
                },
                onShiftTab: {
                    focusedField = .title
                },
                onRegisterToggleTask: { action in
                    viewModel.onToggleTask = action
                }
            )
            .focused($focusedField, equals: .content)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.activeNoteContent) { _ in
                viewModel.saveCurrentNote()
            }
        }
    }

    // MARK: - Helpers

    static func firstLineSnippet(content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("---") {
                var cleaned = trimmed
                cleaned = cleaned.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                cleaned = cleaned.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
                cleaned = cleaned.replacingOccurrences(of: #"(?<!\*)\*([^*]+)\*(?!\*)"#, with: "$1", options: .regularExpression)
                cleaned = cleaned.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
                return cleaned
            }
        }
        return ""
    }

    func firstLineSnippet(content: String) -> String {
        Self.firstLineSnippet(content: content)
    }

    private func formattedRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.textPrimary.opacity(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}
