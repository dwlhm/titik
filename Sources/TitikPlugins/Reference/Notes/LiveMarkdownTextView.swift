import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikPluginKit
import TitikUI

/// AppKit NSTextView wrapper delivering live, in-place WYSIWYG Markdown resolution without preview or edit-mode toggles.
public struct LiveMarkdownTextView: NSViewRepresentable {
    @Binding public var text: String
    public var isFocused: Bool
    public var onSave: (() -> Void)?
    public var onPinToggle: (() -> Void)?
    public var onExit: (() -> Void)?
    public var onShiftTab: (() -> Void)?
    public var onToggleTask: (() -> Void)?
    public var onRegisterToggleTask: ((@escaping () -> Void) -> Void)?

    public init(
        text: Binding<String>,
        isFocused: Bool = false,
        onSave: (() -> Void)? = nil,
        onPinToggle: (() -> Void)? = nil,
        onExit: (() -> Void)? = nil,
        onShiftTab: (() -> Void)? = nil,
        onToggleTask: (() -> Void)? = nil,
        onRegisterToggleTask: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self._text = text
        self.isFocused = isFocused
        self.onSave = onSave
        self.onPinToggle = onPinToggle
        self.onExit = onExit
        self.onShiftTab = onShiftTab
        self.onToggleTask = onToggleTask
        self.onRegisterToggleTask = onRegisterToggleTask
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(Theme.accent)
        textView.delegate = context.coordinator

        textView.onSave = onSave
        textView.onPinToggle = onPinToggle
        textView.onExit = onExit
        textView.onShiftTab = onShiftTab
        textView.onToggleTask = onToggleTask ?? { [weak textView] in
            textView?.toggleTaskAtCurrentLine()
        }

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyMarkdownAttributes(to: textView.textStorage)

        onRegisterToggleTask?({ [weak textView] in
            textView?.toggleTaskAtCurrentLine()
        })

        scrollView.documentView = textView

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownNSTextView else { return }
        textView.onSave = onSave
        textView.onPinToggle = onPinToggle
        textView.onExit = onExit
        textView.onShiftTab = onShiftTab
        if let onToggleTask = onToggleTask {
            textView.onToggleTask = onToggleTask
        }
        onRegisterToggleTask?({ [weak textView] in
            textView?.toggleTaskAtCurrentLine()
        })

        if isFocused && nsView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(textView)
            }
        }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyMarkdownAttributes(to: textView.textStorage)
            textView.selectedRanges = selectedRanges
        }
    }

    // MARK: - Coordinator & Text Storage Styling

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LiveMarkdownTextView
        weak var textView: MarkdownNSTextView?
        private var isFormatting = false

        init(_ parent: LiveMarkdownTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard !isFormatting, let tv = notification.object as? NSTextView else { return }
            let current = tv.string
            parent.text = current
            applyMarkdownAttributes(to: tv.textStorage)
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isFormatting, let tv = notification.object as? NSTextView else { return }
            applyMarkdownAttributes(to: tv.textStorage)
        }

        @MainActor
        public func applyMarkdownAttributes(to storage: NSTextStorage?) {
            guard let storage = storage, !isFormatting else { return }
            isFormatting = true
            defer { isFormatting = false }

            let rawString = storage.string
            let fullRange = NSRange(location: 0, length: (rawString as NSString).length)
            guard fullRange.length > 0 else { return }

            // Ensure TitikPluginKit's MarkdownASTParser parses document structure
            _ = MarkdownASTParser.parse(rawString)

            let selectedRange = textView?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
            let activeLineRange: NSRange
            if selectedRange.location != NSNotFound && selectedRange.location <= (rawString as NSString).length {
                activeLineRange = (rawString as NSString).lineRange(for: selectedRange)
            } else {
                activeLineRange = NSRange(location: NSNotFound, length: 0)
            }

            storage.beginEditing()

            // 1. Base typography
            let baseFont = NSFont.systemFont(ofSize: 14, weight: .regular)
            let baseColor = NSColor.white.withAlphaComponent(0.92)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4

            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: baseColor,
                .paragraphStyle: paragraphStyle
            ], range: fullRange)

            let nsString = rawString as NSString

            // Apply markdown syntax formatting
            applyHeadings(nsString: nsString, storage: storage, fullRange: fullRange, activeLineRange: activeLineRange)
            applyInlineStyles(nsString: nsString, storage: storage, fullRange: fullRange, activeLineRange: activeLineRange)
            applyCheckboxes(nsString: nsString, storage: storage, fullRange: fullRange)
            applyBlockQuotes(nsString: nsString, storage: storage, fullRange: fullRange, activeLineRange: activeLineRange)

            storage.endEditing()
        }

        private func styleDelimiter(range: NSRange, in storage: NSTextStorage, activeLineRange: NSRange) {
            let isActive = activeLineRange.location != NSNotFound && NSIntersectionRange(activeLineRange, range).length > 0
            if isActive {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .regular), range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.35), range: range)
            } else {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.001), range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            }
        }

        private func applyHeadings(
            nsString: NSString,
            storage: NSTextStorage,
            fullRange: NSRange,
            activeLineRange: NSRange
        ) {
            applyPattern(
                pattern: #"^(#{1,6}\s+)(.*)$"#,
                options: [.anchorsMatchLines],
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                let delimStr = nsString.substring(with: match.range(at: 1))
                let level = delimStr.filter { $0 == "#" }.count
                let headingFont: NSFont
                switch level {
                case 1: headingFont = NSFont.boldSystemFont(ofSize: 20)
                case 2: headingFont = NSFont.boldSystemFont(ofSize: 17)
                case 3: headingFont = NSFont.boldSystemFont(ofSize: 15)
                default: headingFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
                }
                styleDelimiter(range: match.range(at: 1), in: storage, activeLineRange: activeLineRange)
                if match.range(at: 2).length > 0 {
                    storage.addAttribute(.font, value: headingFont, range: match.range(at: 2))
                    storage.addAttribute(.foregroundColor, value: NSColor.white, range: match.range(at: 2))
                }
            }
        }

        private func applyInlineStyles(
            nsString: NSString,
            storage: NSTextStorage,
            fullRange: NSRange,
            activeLineRange: NSRange
        ) {
            let italicFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: 14, weight: .regular),
                toHaveTrait: .italicFontMask
            )
            // Bold: **text** or __text__
            applyPattern(
                pattern: #"(\*{2}|_{2})([^*_]+)(\*{2}|_{2})"#,
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                styleDelimiter(range: match.range(at: 1), in: storage, activeLineRange: activeLineRange)
                if match.range(at: 2).length > 0 {
                    storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: match.range(at: 2))
                    storage.addAttribute(.foregroundColor, value: NSColor.white, range: match.range(at: 2))
                }
                styleDelimiter(range: match.range(at: 3), in: storage, activeLineRange: activeLineRange)
            }

            // Italic: *text* or _text_
            applyPattern(
                pattern: #"(?<!\*|_|\w)(\*|_)([^*_]+)(\*|_)(?!\*|_|\w)"#,
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                styleDelimiter(range: match.range(at: 1), in: storage, activeLineRange: activeLineRange)
                if match.range(at: 2).length > 0 {
                    storage.addAttribute(.font, value: italicFont, range: match.range(at: 2))
                    storage.addAttribute(.foregroundColor, value: NSColor.white, range: match.range(at: 2))
                }
                styleDelimiter(range: match.range(at: 3), in: storage, activeLineRange: activeLineRange)
            }

            applyCodeStyles(nsString: nsString, storage: storage, fullRange: fullRange, activeLineRange: activeLineRange)
        }

        private func applyCodeStyles(
            nsString: NSString,
            storage: NSTextStorage,
            fullRange: NSRange,
            activeLineRange: NSRange
        ) {
            let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            // Monospace inline code: `code`
            applyPattern(
                pattern: #"(`)([^`]+)(`)"#,
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                styleDelimiter(range: match.range(at: 1), in: storage, activeLineRange: activeLineRange)
                if match.range(at: 2).length > 0 {
                    storage.addAttribute(.font, value: codeFont, range: match.range(at: 2))
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor(white: 0.25, alpha: 0.45),
                        range: match.range(at: 2)
                    )
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1.0),
                        range: match.range(at: 2)
                    )
                }
                styleDelimiter(range: match.range(at: 3), in: storage, activeLineRange: activeLineRange)
            }
        }

        private func applyCheckboxes(
            nsString: NSString,
            storage: NSTextStorage,
            fullRange: NSRange
        ) {
            applyPattern(
                pattern: #"^(\s*-\s+)\[ \]"#,
                options: [.anchorsMatchLines],
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: match.range)
            }
            applyPattern(
                pattern: #"^(\s*-\s+)\[[xX]\]"#,
                options: [.anchorsMatchLines],
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: match.range)
            }
        }

        private func applyBlockQuotes(
            nsString: NSString,
            storage: NSTextStorage,
            fullRange: NSRange,
            activeLineRange: NSRange
        ) {
            let italicFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: 14, weight: .regular),
                toHaveTrait: .italicFontMask
            )
            applyPattern(
                pattern: #"^(>\s+)(.*)$"#,
                options: [.anchorsMatchLines],
                nsString: nsString,
                storage: storage,
                fullRange: fullRange
            ) { match in
                styleDelimiter(range: match.range(at: 1), in: storage, activeLineRange: activeLineRange)
                if match.range(at: 2).length > 0 {
                    storage.addAttribute(.font, value: italicFont, range: match.range(at: 2))
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.white.withAlphaComponent(0.75),
                        range: match.range(at: 2)
                    )
                }
            }
        }

        private func applyPattern(
            pattern: String,
            options: NSRegularExpression.Options = [],
            nsString: NSString,
            storage: NSTextStorage,
            fullRange: NSRange,
            handler: (NSTextCheckingResult) -> Void
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: nsString as String, options: [], range: fullRange)
            for match in matches {
                handler(match)
            }
        }
    }
}

// MARK: - MarkdownNSTextView Custom Subclass

final class MarkdownNSTextView: NSTextView {
    var onSave: (() -> Void)?
    var onPinToggle: (() -> Void)?
    var onExit: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var onToggleTask: (() -> Void)?

    private static let emptyTaskRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^\s*-\s+\[ \]\s*$"#)
    }()

    private static let taskLineRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^\s*-\s+\[([ xX])\]"#)
    }()

    private static let checkboxClickRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(\s*-\s+)(\[[ xX]\])"#)
    }()

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        self.onToggleTask = { [weak self] in
            self?.toggleTaskAtCurrentLine()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.onToggleTask = { [weak self] in
            self?.toggleTaskAtCurrentLine()
        }
    }

    public func toggleTaskAtCurrentLine() {
        let nsString = string as NSString
        guard nsString.length > 0 else {
            let initialTask = "- [ ] "
            if shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: initialTask) {
                replaceCharacters(in: NSRange(location: 0, length: 0), with: initialTask)
                didChangeText()
                setSelectedRange(NSRange(location: initialTask.utf16.count, length: 0))
            }
            return
        }

        let sel = selectedRange()
        let charLoc = sel.location != NSNotFound ? min(sel.location, max(0, nsString.length - 1)) : 0
        let lineRange = nsString.lineRange(for: NSRange(location: charLoc, length: 0))
        let fullLine = nsString.substring(with: lineRange)

        var lineContent = fullLine
        var newlineSuffix = ""
        if lineContent.hasSuffix("\r\n") {
            newlineSuffix = "\r\n"
            lineContent = String(lineContent.dropLast(2))
        } else if lineContent.hasSuffix("\n") || lineContent.hasSuffix("\r") {
            newlineSuffix = String(lineContent.suffix(1))
            lineContent = String(lineContent.dropLast(1))
        }

        let toggledLine = Note.toggleCheckbox(in: lineContent) + newlineSuffix
        if shouldChangeText(in: lineRange, replacementString: toggledLine) {
            replaceCharacters(in: lineRange, with: toggledLine)
            didChangeText()

            let diff = (toggledLine as NSString).length - lineRange.length
            let newCursor = min(max(lineRange.location, sel.location + diff), (string as NSString).length)
            setSelectedRange(NSRange(location: newCursor, length: 0))
        }
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0 else {
            super.copy(sender)
            return
        }
        let raw = (string as NSString).substring(with: range)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(raw, forType: .string)
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0 else {
            return super.writeSelection(to: pboard, types: types)
        }
        let raw = (string as NSString).substring(with: range)
        pboard.clearContents()
        pboard.setString(raw, forType: .string)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let code = UInt32(event.keyCode)

        if modifiers == .command && code == Keycode.s.rawValue {
            onSave?()
            return true
        }

        if modifiers == .command && code == Keycode.p.rawValue {
            onPinToggle?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let code = UInt32(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if code == Keycode.escape.rawValue {
            onExit?()
            return
        }

        if code == Keycode.tab.rawValue && modifiers.contains(.shift) {
            if let onShiftTab = onShiftTab {
                onShiftTab()
                return
            }
        }

        // Intercept Return key (code == Keycode.returnKey.rawValue or 36)
        if code == Keycode.returnKey.rawValue || code == 36 {
            let activeModifiers = modifiers.subtracting([.capsLock])
            if activeModifiers.isEmpty {
                let sel = selectedRange()
                let nsString = string as NSString
                if sel.location != NSNotFound {
                    let charLoc = min(sel.location, max(0, nsString.length - 1))
                    let lineRange = nsString.lineRange(for: NSRange(location: charLoc, length: 0))
                    let fullLine = nsString.substring(with: lineRange)
                    var lineWithoutNewline = fullLine
                    if lineWithoutNewline.hasSuffix("\r\n") {
                        lineWithoutNewline.removeLast(2)
                    } else if lineWithoutNewline.hasSuffix("\n") || lineWithoutNewline.hasSuffix("\r") {
                        lineWithoutNewline.removeLast(1)
                    }

                    let emptyRange = NSRange(location: 0, length: (lineWithoutNewline as NSString).length)

                    // If matches empty task prefix: ^\s*-\s+\[ \]\s*$ (user pressed Return on empty - [ ] ):
                    if Self.emptyTaskRegex?.firstMatch(in: lineWithoutNewline, options: [], range: emptyRange) != nil {
                        let prefixLength = (lineWithoutNewline as NSString).length
                        let rangeToClear = NSRange(location: lineRange.location, length: prefixLength)
                        if shouldChangeText(in: rangeToClear, replacementString: "") {
                            replaceCharacters(in: rangeToClear, with: "")
                            didChangeText()
                            setSelectedRange(NSRange(location: lineRange.location, length: 0))
                        }
                        return
                    }

                    // If line has - [ ] <text> or - [x] <text>:
                    if Self.taskLineRegex?.firstMatch(in: lineWithoutNewline, options: [], range: emptyRange) != nil {
                        let insertText = "\n- [ ] "
                        if shouldChangeText(in: sel, replacementString: insertText) {
                            replaceCharacters(in: sel, with: insertText)
                            didChangeText()
                            setSelectedRange(NSRange(location: sel.location + (insertText as NSString).length, length: 0))
                        }
                        return
                    }
                }
            }
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let origin = self.textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)

        let nsString = self.string as NSString
        guard nsString.length > 0 else {
            super.mouseDown(with: event)
            return
        }

        var fraction: CGFloat = 0.0
        let charIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )

        if charIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: charLoc(for: charIndex, total: nsString.length), length: 0))
            let lineStr = nsString.substring(with: lineRange)
            let lineNsString = lineStr as NSString

            let lineBounds = NSRange(location: 0, length: lineNsString.length)
            if let match = Self.checkboxClickRegex?.firstMatch(in: lineStr, options: [], range: lineBounds) {
                let boxLocalRange = match.range(at: 2)
                let boxGlobalRange = NSRange(location: lineRange.location + boxLocalRange.location, length: boxLocalRange.length)

                let glyphRange = layoutManager.glyphRange(forCharacterRange: boxGlobalRange, actualCharacterRange: nil)
                var boxRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                boxRect.origin.x += origin.x
                boxRect.origin.y += origin.y

                let hitBox = boxRect.insetBy(dx: -4, dy: -2)
                let hitByChar = (charIndex >= boxGlobalRange.location && charIndex < boxGlobalRange.location + boxGlobalRange.length)

                if hitBox.contains(point) || hitByChar {
                    let currentBox = nsString.substring(with: boxGlobalRange)
                    let newBox = (currentBox == "[ ]") ? "[x]" : "[ ]"
                    if shouldChangeText(in: boxGlobalRange, replacementString: newBox) {
                        replaceCharacters(in: boxGlobalRange, with: newBox)
                        didChangeText()
                    }
                    return
                }
            }
        }

        super.mouseDown(with: event)
    }

    private func charLoc(for index: Int, total: Int) -> Int {
        min(max(0, index), max(0, total - 1))
    }

    override func insertBacktab(_ sender: Any?) {
        if let onShiftTab = onShiftTab {
            onShiftTab()
        } else {
            super.insertBacktab(sender)
        }
    }
}
