#if os(macOS)
import AppKit

/// The editor in an AppKit text view, inside a page that scrolls: what the Mac's text system does differently from
/// iOS's.
extension EditorController: NSTextViewDelegate {
    func configureTextView() {
        let view = textView
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFontPanel = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        // Spelling is checked while you type in it, so text you only read isn't covered in red.
        view.isContinuousSpellCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.insertionPointColor = EditorTheme.accent
        // The system's selection colour, without changing the colour of the text.
        view.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        view.linkTextAttributes = [:]
        view.typingAttributes = MarkdownStyler.baseAttributes
        view.defaultParagraphStyle = EditorStyle.paragraph()
        view.delegate = self
    }

    // MARK: - What the shared editor asks of the text view

    var selection: NSRange { textView.selectedRange() }
    func setSelection(_ range: NSRange) { textView.setSelectedRange(range) }
    var selectedRanges: [NSRange] { textView.selectedRanges.map(\.rangeValue) }
    var isFocused: Bool { textView.window?.firstResponder === textView }
    /// The mouse button is down: nothing is revealed or hidden until it comes up.
    var isTracking: Bool { textView.isTrackingMouse }
    var isInWindow: Bool { textView.window != nil }
    var textOrigin: NSPoint { textView.textContainerOrigin }

    /// The page the text is in, which scrolls rather than the text.
    var hasScroller: Bool { textView.enclosingScrollView != nil }
    /// The part of the text you can see, in the text view's coordinates.
    var visibleRect: NSRect { textView.visibleRect }

    /// How far down the window a point of the text is, which scrolling the page changes.
    func screenY(_ y: CGFloat) -> CGFloat {
        -textView.convert(NSPoint(x: 0, y: y), to: nil).y
    }

    /// Scrolls the page down by `delta` points (up when negative). A page that isn't tall enough for it yet, because
    /// it is laid out again only in a moment, gets there once it is.
    func scrollPage(by delta: CGFloat) {
        guard let scrollView = textView.enclosingScrollView else { return }
        let clip = scrollView.contentView
        let target = clip.bounds.minY + (clip.isFlipped ? delta : -delta)
        func scroll() {
            let origin = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: clip.bounds.minX, y: target), size: clip.bounds.size)).origin
            guard abs(origin.y - clip.bounds.minY) > 0.5 else { return }
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
        }
        scroll()
        if abs(clip.bounds.minY - target) > 0.5 {
            DispatchQueue.main.async { scroll() }
        }
    }

    /// Keeps the line with the caret clear of what covers the page's edges, the toolbar above and the comment field
    /// below: the text view scrolls only into the visible part of the page, which runs under them.
    func scrollCaretIntoView() {
        guard isFocused, !isTracking, let scrollView = textView.enclosingScrollView else { return }
        let clip = scrollView.contentView
        guard clip.isFlipped else { return }
        let index = min(selection.upperBound, storage.length)
        var height = EditorStyle.lineHeight
        if index < storage.length {
            height = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil).height
        }
        let line = textView.convert(NSRect(x: 0, y: yPosition(of: index), width: 1, height: height), to: clip)
        let margin: CGFloat = 12
        let top = clip.bounds.minY + scrollView.contentInsets.top
        let bottom = clip.bounds.maxY - scrollView.contentInsets.bottom
        var delta: CGFloat = 0
        if line.maxY + margin > bottom {
            delta = line.maxY + margin - bottom
        } else if line.minY - margin < top {
            delta = line.minY - margin - top
        }
        if abs(delta) > 0.5 { scrollPage(by: delta) }
    }

    var isDarkAppearance: Bool {
        textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func textNeedsDisplay() { textView.needsDisplay = true }

    func updateEditability() {
        textView.isEditable = isEditable
        textView.isSelectable = true
    }

    func makeTextFirstResponder() {
        guard !isFocused else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Escape and ⌘↵: the text lets go of the keyboard, which saves it.
    func finishEditing() {
        guard isFocused else { return }
        textView.window?.makeFirstResponder(nil)
    }

    /// A text that came from elsewhere has nothing of the old one to undo.
    func clearUndo() {
        textView.breakUndoCoalescing()
        textView.undoManager?.removeAllActions(withTarget: textView)
        textView.undoManager?.removeAllActions(withTarget: storage)
    }

    /// Changes the text the way typing does, so it can be undone. Where the text is only read (a checkbox ticked in a
    /// preview) it is changed directly.
    func performEdit(_ range: NSRange, with string: String) -> Bool {
        guard textView.isEditable else {
            storage.replaceCharacters(in: range, with: string)
            textChanged()
            return true
        }
        guard textView.shouldChangeText(in: range, replacementString: string) else { return false }
        storage.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        return true
    }

    // MARK: - NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        selectionChanged()
        // After the text view's own scrolling, and once the page has the text's new height.
        DispatchQueue.main.async { [weak self] in self?.scrollCaretIntoView() }
    }

    func textDidChange(_ notification: Notification) {
        textChanged()
    }

    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue], toCharacterRanges newSelectedCharRanges: [NSValue]) -> [NSValue] {
        guard !isLoading, !selectsExactly, newSelectedCharRanges.count == 1, let old = oldSelectedCharRanges.first?.rangeValue else { return newSelectedCharRanges }
        let range = newSelectedCharRanges[0].rangeValue
        if range.length == 0 {
            return [NSValue(range: NSRange(location: snapCaret(range.location, from: old), length: 0))]
        }
        return [NSValue(range: expandSelection(range))]
    }

    /// No spelling marks in code, maths, links, addresses or hidden Markdown: they aren't prose.
    func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
        guard value != 0, affectedCharRange.upperBound <= storage.length, !document.lines.isEmpty else { return value }
        for index in affectedCharRange.location..<affectedCharRange.upperBound {
            if layoutManager.isHidden(index) || layoutManager.object(at: index) != nil { return 0 }
            if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont, font.isFixedPitch { return 0 }
        }
        let line = document.lines[document.lineIndex(containing: affectedCharRange.location)]
        for span in line.spans where NSIntersectionRange(span.range, affectedCharRange).length > 0 {
            switch span.kind {
            case .code, .math, .link, .autolink, .image, .html: return 0
            default: break
            }
        }
        switch line.kind {
        case .code, .fence, .math, .mathDelimiter, .tableDelimiter: return 0
        default: return value
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handleCommand(commandSelector)
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !isLoading, let replacement = replacementString else { return true }
        return shouldInsert(replacement, in: affectedCharRange)
    }

    /// Return, Tab, Backspace and Escape, as the text view sends them.
    func handleCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            return insertNewline()
        case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            insert("\n")
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            defer { lastDeleteBackward = CACurrentMediaTime() }
            return deleteBackward()
        case #selector(NSResponder.deleteForward(_:)):
            return deleteForward()
        case #selector(NSResponder.insertTab(_:)):
            return indent(by: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            return indent(by: -1)
        case #selector(NSResponder.moveUp(_:)):
            return moveUpIntoTitle()
        case #selector(NSResponder.moveLeft(_:)):
            return moveBackIntoTitle()
        case #selector(NSResponder.cancelOperation(_:)):
            if let escape = onEscape { escape() } else { finishEditing() }
            return true
        default:
            return false
        }
    }
}
#endif
