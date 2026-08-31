import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikUI
import TitikSearch
import TitikPlugins
import TitikParser
import TitikPluginKit

@MainActor
public final class UIOrchestrator: ObservableObject {
    public static let shared = UIOrchestrator()

    @Published public var query: String = "" {
        didSet {
            performSearch(query)
        }
    }
    @Published public var results: [SearchItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var boundaryBounceOffset: CGFloat = 0
    @Published public var activePluginUI: (any PluginUIRepresentable)? = nil
    @Published public var activeSession: DirectoryNavigationSession? = nil

    @Published public var isActionPaletteVisible: Bool = false
    @Published public var selectedActionIndex: Int = 0
    @Published public var currentActions: [ContextualAction] = []

    private let searchEngine: SearchEngine
    private let fileBrowser: FileBrowser
    private let commandParser = CommandParser()
    private nonisolated(unsafe) var keyMonitor: Any?

    public init(searchEngine: SearchEngine = .shared, fileBrowser: FileBrowser = .shared) {
        self.searchEngine = searchEngine
        self.fileBrowser = fileBrowser
        WindowController.shared.onWindowClosed = {
            PluginHost.shared.cancelAllActiveTasks()
        }
        performSearch("")
        setupKeyMonitor()
    }

    @MainActor
    public func moveCaretToEnd() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.setSelectedRange(NSRange(location: query.utf16.count, length: 0))
        }
    }

    @MainActor
    public func goBack() {
        if let session = activeSession {
            if query == session.rootQueryPrefix {
                // Clamped at session root! Do not navigate back.
                return
            } else if let parent = PathResolver.parentPath(of: query) {
                query = parent
                selectedIndex = 0
                DispatchQueue.main.async { [weak self] in
                    self?.moveCaretToEnd()
                }
                return
            }
        } else if let parent = PathResolver.parentPath(of: query) {
            query = parent
            selectedIndex = 0
            DispatchQueue.main.async { [weak self] in
                self?.moveCaretToEnd()
            }
        }
    }

    public func performSearch(_ q: String) {
        if let session = activeSession {
            if q.hasPrefix(session.rootQueryPrefix) {
                let sub = String(q.dropFirst(session.rootQueryPrefix.count))
                let (subDir, filter) = PathResolver.splitPathQuery(sub)
                let targetURL = subDir.isEmpty ? session.rootURL : URL(fileURLWithPath: (session.rootURL.path as NSString).appendingPathComponent(subDir))
                self.activePluginUI = nil
                self.results = fileBrowser.browseDirectory(
                    targetURL: targetURL,
                    rootURL: session.rootURL,
                    displayPrefix: session.rootQueryPrefix + subDir,
                    filter: filter
                )
                self.selectedIndex = 0
                return
            } else {
                // Session invalidated
                self.activeSession = nil
            }
        }

        let ast = commandParser.parse(q)

        switch ast {
        case .command(let name, let args, _) where ["emoji", "emojis", "e"].contains(name.lowercased()):
            let subquery = args.joined(separator: " ")
            let plugin = EmojiPlugin.shared
            plugin.onSelectEmoji = { [weak self] emoji in
                let success = AutoPaster.shared.pasteToActiveApp(content: emoji.emoji)
                if success {
                    self?.reset()
                }
            }
            plugin.handleSearchQuery(subquery)
            self.activePluginUI = plugin
            self.results = []
            self.selectedIndex = 0
            return

        default:
            PluginHost.shared.cancelAllActiveTasks()
            self.activePluginUI = nil
            let items = searchEngine.search(query: q)
            self.results = items
            self.selectedIndex = 0
        }
    }

    public var selectedItem: SearchItem? {
        guard !results.isEmpty, selectedIndex >= 0, selectedIndex < results.count else {
            return nil
        }
        return results[selectedIndex]
    }

    public func selectNext() {
        guard !results.isEmpty else { return }
        if selectedIndex < results.count - 1 {
            selectedIndex += 1
        } else if selectedIndex == results.count - 1 {
            triggerBoundaryBounce(direction: -1)
        }
    }

    public func selectPrevious() {
        guard !results.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else if selectedIndex == 0 {
            triggerBoundaryBounce(direction: 1)
        }
    }

    public func triggerBoundaryBounce(direction: CGFloat) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
            boundaryBounceOffset = direction * 5.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                self?.boundaryBounceOffset = 0
            }
        }
    }

    public func executeSelected() {
        if let plugin = activePluginUI {
            plugin.submitQuery()
            return
        }

        guard let item = selectedItem else { return }
        Logger.shared.info("Executing item: \(item.title) (\(item.category))", subsystem: "Titik.Orchestrator")

        if item.title == ".." || item.id == "file:.." {
            self.goBack()
            return
        }

        if item.id == "bang:emoji" || item.id == "plugin:emoji" || item.actionPayload == "!emoji" || item.actionPayload == "!emoji " || (item.category == .emoji && item.id.hasPrefix("bang:")) {
            self.query = "!emoji "
            return
        } else if item.id.hasPrefix("bang:") || item.actionPayload.hasPrefix("!") {
            self.query = item.actionPayload.hasSuffix(" ") ? item.actionPayload : (item.actionPayload + " ")
            return
        }

        let success = item.action()
        if success {
            WindowController.shared.hideWindow()
        }
    }

    public func copySelected() {
        guard let item = selectedItem else { return }
        let payload = item.actionPayload.isEmpty ? item.title : item.actionPayload
        ClipboardManager.shared.copyToPasteboard(payload)
        Logger.shared.info("Copied payload to clipboard: \(payload)", subsystem: "Titik.Orchestrator")
    }

    public func reset() {
        PluginHost.shared.cancelAllActiveTasks()
        activeSession = nil
        query = ""
        selectedIndex = 0
        activePluginUI = nil
        hideActionPalette()
        performSearch("")
    }

    public func revealSelectedInFinder() {
        guard let item = selectedItem else { return }
        let path = item.previewURL?.path ?? item.actionPayload
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            Logger.shared.info("Revealed item in Finder: \(path)", subsystem: "Titik.Orchestrator")
        }
    }

    public func autocompleteSelected() {
        guard let item = selectedItem else { return }

        if item.title == ".." || item.id == "file:.." {
            self.goBack()
            return
        }

        if item.category == .directory {
            if activeSession == nil {
                if let url = item.previewURL ?? (item.actionPayload.isEmpty ? nil : URL(fileURLWithPath: item.actionPayload)) {
                    let sessionQuery: String
                    if let payload = item.autocompletePayload, !payload.isEmpty {
                        sessionQuery = payload.hasSuffix("/") ? payload : (payload + "/")
                    } else {
                        let formatted = fileBrowser.formatAutocompletePath(for: item, currentQuery: query)
                        sessionQuery = formatted.hasSuffix("/") ? formatted : (formatted + "/")
                    }
                    self.activeSession = DirectoryNavigationSession(rootQueryPrefix: sessionQuery, rootURL: url)
                    self.query = sessionQuery
                    DispatchQueue.main.async { [weak self] in self?.moveCaretToEnd() }
                    return
                }
            } else if let session = activeSession {
                self.query = item.autocompletePayload ?? (session.rootQueryPrefix + item.title + "/")
                DispatchQueue.main.async { [weak self] in self?.moveCaretToEnd() }
                return
            }

            if query.hasPrefix("!file ") {
                let sub = String(query.dropFirst(6))
                query = "!file " + fileBrowser.formatAutocompletePath(for: item, currentQuery: sub)
            } else {
                query = fileBrowser.formatAutocompletePath(for: item, currentQuery: query)
            }
        } else if item.category == .file {
            if query.hasPrefix("!file ") {
                let sub = String(query.dropFirst(6))
                query = "!file " + fileBrowser.formatAutocompletePath(for: item, currentQuery: sub)
            } else if let customPayload = item.autocompletePayload, !customPayload.isEmpty {
                query = customPayload
            } else {
                query = fileBrowser.formatAutocompletePath(for: item, currentQuery: query)
            }
        } else if let customPayload = item.autocompletePayload, !customPayload.isEmpty {
            query = customPayload
        } else if item.category == .application || item.category == .systemCommand || item.category == .plugin || item.category == .custom {
            query = item.title
        } else if item.category == .calculator {
            query = item.actionPayload.isEmpty ? item.title : item.actionPayload
        } else if item.category == .emoji {
            query = item.actionPayload.isEmpty ? item.title : item.actionPayload
        } else {
            query = item.title
        }

        DispatchQueue.main.async { [weak self] in
            self?.moveCaretToEnd()
        }
    }

    // MARK: - Action Palette (Cmd + K)

    public func toggleActionPalette() {
        if isActionPaletteVisible {
            hideActionPalette()
        } else {
            if let item = selectedItem {
                currentActions = actionsForItem(item)
                selectedActionIndex = 0
                isActionPaletteVisible = !currentActions.isEmpty
            } else if let plugin = activePluginUI as? EmojiPlugin, let emoji = plugin.selectedEmoji {
                currentActions = actionsForEmoji(emoji)
                selectedActionIndex = 0
                isActionPaletteVisible = !currentActions.isEmpty
            }
        }
    }

    public func hideActionPalette() {
        isActionPaletteVisible = false
        selectedActionIndex = 0
        currentActions = []
    }

    public func executeSelectedAction() {
        guard isActionPaletteVisible, selectedActionIndex >= 0, selectedActionIndex < currentActions.count else { return }
        let action = currentActions[selectedActionIndex]
        hideActionPalette()
        action.action()
    }

    public func selectNextAction() {
        guard !currentActions.isEmpty else { return }
        if selectedActionIndex < currentActions.count - 1 {
            selectedActionIndex += 1
        }
    }

    public func selectPreviousAction() {
        guard !currentActions.isEmpty else { return }
        if selectedActionIndex > 0 {
            selectedActionIndex -= 1
        }
    }

    public func actionsForItem(_ item: SearchItem) -> [ContextualAction] {
        switch item.category {
        case .application:
            return [
                ContextualAction(id: "app.open", title: "Open Application", shortcut: "↵", icon: "arrow.up.forward.app") { [weak self] in
                    self?.executeSelected()
                },
                ContextualAction(id: "app.reveal", title: "Show in Finder", shortcut: "⌘O", icon: "folder") { [weak self] in
                    self?.revealSelectedInFinder()
                },
                ContextualAction(id: "app.copyPath", title: "Copy Path", shortcut: "⌘C", icon: "doc.on.doc") { [weak self] in
                    self?.copySelected()
                }
            ]

        case .file, .directory:
            return [
                ContextualAction(id: "file.open", title: "Open", shortcut: "↵", icon: "arrow.up.forward") { [weak self] in
                    self?.executeSelected()
                },
                ContextualAction(id: "file.reveal", title: "Show in Finder", shortcut: "⌘O", icon: "folder") { [weak self] in
                    self?.revealSelectedInFinder()
                },
                ContextualAction(id: "file.copyPath", title: "Copy Path", shortcut: "⌘C", icon: "doc.on.doc") { [weak self] in
                    self?.copySelected()
                },
                ContextualAction(id: "file.terminal", title: "Open in Terminal", shortcut: "⌥T", icon: "terminal") { [weak self] in
                    guard let self = self, let item = self.selectedItem else { return }
                    let path = item.previewURL?.path ?? item.actionPayload
                    if !path.isEmpty {
                        let folder = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path
                        NSWorkspace.shared.open(URL(fileURLWithPath: folder), configuration: NSWorkspace.OpenConfiguration())
                    }
                    WindowController.shared.hideWindow()
                },
                ContextualAction(id: "file.trash", title: "Move to Trash", shortcut: "⌘⌫", icon: "trash") { [weak self] in
                    guard let self = self, let item = self.selectedItem else { return }
                    let path = item.previewURL?.path ?? item.actionPayload
                    if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                        try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                    }
                    self.performSearch(self.query)
                }
            ]

        case .clipboard:
            let rawId = item.id.replacingOccurrences(of: "clip:", with: "")
            let uuid = UUID(uuidString: rawId)
            let currentItem = uuid.flatMap { id in ClipboardManager.shared.getItems().first(where: { $0.id == id }) }
            let isPinned = currentItem?.isPinned ?? false

            return [
                ContextualAction(id: "clip.paste", title: "Paste to Active App", shortcut: "↵", icon: "doc.on.clipboard") {
                    AutoPaster.shared.pasteToActiveApp(content: item.actionPayload)
                },
                ContextualAction(id: "clip.copy", title: "Copy to Clipboard", shortcut: "⌘C", icon: "doc.on.doc") { [weak self] in
                    self?.copySelected()
                },
                ContextualAction(id: "clip.pin", title: isPinned ? "Unpin Item" : "Pin Item", shortcut: "⌘P", icon: isPinned ? "pin.slash" : "pin") { [weak self] in
                    guard let self = self, let id = uuid else { return }
                    ClipboardManager.shared.togglePin(id: id)
                    self.performSearch(self.query)
                },
                ContextualAction(id: "clip.delete", title: "Delete Item", shortcut: "⌥⌫", icon: "trash") { [weak self] in
                    guard let self = self, let id = uuid else { return }
                    ClipboardManager.shared.deleteItem(id: id)
                    self.performSearch(self.query)
                }
            ]

        case .emoji:
            let emojiChar = item.actionPayload
            let matched = EmojiCatalog.shared.allEmojis.first(where: { $0.emoji == emojiChar })
            return [
                ContextualAction(id: "emoji.paste", title: "Paste to Active App", shortcut: "↵", icon: "arrow.right.doc.on.clipboard") {
                    AutoPaster.shared.pasteToActiveApp(content: emojiChar)
                },
                ContextualAction(id: "emoji.copy", title: "Copy Emoji", shortcut: "⌘C", icon: "doc.on.doc") {
                    ClipboardManager.shared.copyToPasteboard(emojiChar)
                    WindowController.shared.hideWindow()
                },
                ContextualAction(id: "emoji.copyShortcode", title: "Copy Shortcode (\(matched?.shortcode ?? ""))", shortcut: "⌥C", icon: "text.quote") {
                    if let shortcode = matched?.shortcode {
                        ClipboardManager.shared.copyToPasteboard(shortcode)
                    }
                    WindowController.shared.hideWindow()
                },
                ContextualAction(id: "emoji.copyHex", title: "Copy Unicode Hex (\(matched?.unicodeHex ?? ""))", shortcut: "⌥U", icon: "number") {
                    if let hex = matched?.unicodeHex {
                        ClipboardManager.shared.copyToPasteboard(hex)
                    }
                    WindowController.shared.hideWindow()
                }
            ]

        case .calculator, .systemCommand, .plugin, .custom:
            return [
                ContextualAction(id: "item.execute", title: "Execute", shortcut: "↵", icon: "play.fill") { [weak self] in
                    self?.executeSelected()
                },
                ContextualAction(id: "item.copy", title: "Copy Payload", shortcut: "⌘C", icon: "doc.on.doc") { [weak self] in
                    self?.copySelected()
                }
            ]
        }
    }

    public func actionsForEmoji(_ emoji: EmojiItem) -> [ContextualAction] {
        return [
            ContextualAction(id: "emoji.paste", title: "Paste to Active App", shortcut: "↵", icon: "arrow.right.doc.on.clipboard") {
                AutoPaster.shared.pasteToActiveApp(content: emoji.emoji)
            },
            ContextualAction(id: "emoji.copy", title: "Copy Emoji", shortcut: "⌘C", icon: "doc.on.doc") {
                ClipboardManager.shared.copyToPasteboard(emoji.emoji)
                WindowController.shared.hideWindow()
            },
            ContextualAction(id: "emoji.copyShortcode", title: "Copy Shortcode (\(emoji.shortcode))", shortcut: "⌥C", icon: "text.quote") {
                ClipboardManager.shared.copyToPasteboard(emoji.shortcode)
                WindowController.shared.hideWindow()
            },
            ContextualAction(id: "emoji.copyHex", title: "Copy Unicode Hex (\(emoji.unicodeHex))", shortcut: "⌥U", icon: "number") {
                ClipboardManager.shared.copyToPasteboard(emoji.unicodeHex)
                WindowController.shared.hideWindow()
            }
        ]
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard WindowController.shared.isVisible else { return event }

            let code = UInt32(event.keyCode)

            // 1. Action Palette mode navigation
            if self.isActionPaletteVisible {
                switch code {
                case Keycode.downArrow.rawValue:
                    self.selectNextAction()
                    return nil
                case Keycode.upArrow.rawValue:
                    self.selectPreviousAction()
                    return nil
                case Keycode.returnKey.rawValue:
                    self.executeSelectedAction()
                    return nil
                case Keycode.escape.rawValue:
                    self.hideActionPalette()
                    return nil
                case Keycode.k.rawValue:
                    if event.modifierFlags.contains(.command) {
                        self.hideActionPalette()
                        return nil
                    }
                default:
                    break
                }
                return event
            }

            // 2. Cmd+K trigger
            if event.modifierFlags.contains(.command) && code == Keycode.k.rawValue {
                self.toggleActionPalette()
                return nil
            }

            // 3. Active Plugin UI mode navigation
            if let plugin = self.activePluginUI {
                if code == Keycode.escape.rawValue {
                    WindowController.shared.hideWindow()
                    return nil
                }
                if code == Keycode.returnKey.rawValue {
                    plugin.submitQuery()
                    return nil
                }
                if plugin.handleKeyDown(event: event) {
                    return nil
                }
                return event
            }

            // 4. Standard List navigation
            switch code {
            case Keycode.downArrow.rawValue:
                self.selectNext()
                return nil

            case Keycode.upArrow.rawValue:
                self.selectPrevious()
                return nil

            case Keycode.returnKey.rawValue:
                self.executeSelected()
                return nil

            case Keycode.tab.rawValue:
                self.autocompleteSelected()
                return nil

            case Keycode.leftArrow.rawValue:
                if PathResolver.canGoBack(path: self.query) {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        let selectedRange = textView.selectedRange()
                        let isAtStart = selectedRange.location == 0
                        if isAtStart || self.query.isEmpty {
                            self.goBack()
                            return nil
                        }
                    } else {
                        self.goBack()
                        return nil
                    }
                }

            case Keycode.rightArrow.rawValue:
                if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                    let selectedRange = textView.selectedRange()
                    let isAtEnd = selectedRange.length == 0 && selectedRange.location == textView.string.utf16.count
                    let isAllSelected = selectedRange.length > 0 && selectedRange.location == 0 && selectedRange.length == textView.string.utf16.count
                    if isAtEnd || isAllSelected || self.query.isEmpty {
                        self.autocompleteSelected()
                        return nil
                    }
                } else {
                    self.autocompleteSelected()
                    return nil
                }

            case Keycode.escape.rawValue:
                WindowController.shared.hideWindow()
                return nil

            case Keycode.c.rawValue:
                if event.modifierFlags.contains(.command) {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                       textView.selectedRange().length > 0 {
                        return event
                    }
                    self.copySelected()
                    return nil
                }

            case Keycode.o.rawValue, Keycode.r.rawValue:
                if event.modifierFlags.contains(.command) {
                    self.revealSelectedInFinder()
                    return nil
                }

            default:
                break
            }

            // Ctrl+N / Ctrl+P navigation
            if event.modifierFlags.contains(.control) {
                if code == Keycode.n.rawValue {
                    self.selectNext()
                    return nil
                } else if code == Keycode.p.rawValue {
                    self.selectPrevious()
                    return nil
                }
            }

            return event
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

@MainActor
public struct MainContentView: View {
    @ObservedObject public var orchestrator: UIOrchestrator
    @ObservedObject private var toastManager: ToastManager

    public init(orchestrator: UIOrchestrator? = nil, toastManager: ToastManager = .shared) {
        self.orchestrator = orchestrator ?? UIOrchestrator.shared
        self.toastManager = toastManager
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 12) {
                // Search Bar
                SearchBarView(
                    text: $orchestrator.query,
                    onSubmit: {
                        orchestrator.executeSelected()
                    },
                    onCancel: {
                        WindowController.shared.hideWindow()
                    }
                )

                // Center Content: Plugin UI or Standard Results List + Preview Pane
                GeometryReader { geo in
                    if let pluginUI = orchestrator.activePluginUI {
                        PluginContainerView(pluginUI: pluginUI)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .transition(.opacity)
                    } else {
                        let hasPreview = orchestrator.selectedItem?.hasRichPreview == true
                        let spacing: CGFloat = 12
                        let previewWidth = geo.size.width * 0.45 - spacing
                        let listWidth = hasPreview ? (geo.size.width * 0.55) : geo.size.width

                        HStack(spacing: spacing) {
                            ResultsListView(
                                items: orchestrator.results,
                                selectedIndex: $orchestrator.selectedIndex,
                                boundaryBounceOffset: orchestrator.boundaryBounceOffset,
                                onSelect: { _ in
                                    orchestrator.executeSelected()
                                }
                            )
                            .frame(width: listWidth, height: geo.size.height)

                            if hasPreview {
                                PreviewPaneView(item: orchestrator.selectedItem)
                                     .frame(width: previewWidth, height: geo.size.height)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .animation(Theme.springInteractive, value: orchestrator.selectedItem?.hasRichPreview)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Footer
                FooterView(
                    isPluginActive: orchestrator.activePluginUI != nil,
                    isActionPaletteActive: orchestrator.isActionPaletteVisible,
                    isCategoryDirectory: orchestrator.selectedItem?.category == .directory,
                    canGoBack: PathResolver.canGoBack(path: orchestrator.query)
                )
            }
            .padding(16)
            .frame(width: 720, height: 460)

            // Action Palette Overlay
            if orchestrator.isActionPaletteVisible {
                ActionPaletteView(
                    actions: orchestrator.currentActions,
                    selectedIndex: $orchestrator.selectedActionIndex,
                    onSelect: { action in
                        orchestrator.executeSelectedAction()
                    },
                    onDismiss: {
                        orchestrator.hideActionPalette()
                    }
                )
            }

            // Toast Notification Overlay
            if let toast = toastManager.currentToast {
                VStack {
                    Spacer()
                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .padding(.bottom, 24)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(100)
            }
        }
        .hudGlassBackground(cornerRadius: 16)
    }
}
