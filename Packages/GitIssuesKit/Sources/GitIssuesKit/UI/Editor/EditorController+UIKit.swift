#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// The editor in a UIKit text view, inside a page that scrolls: taps instead of clicks, the keyboard's Return and
/// Backspace as text, the bar above the keyboard, and an alert instead of a popover.
extension EditorController: UITextViewDelegate, UIGestureRecognizerDelegate, UITextDragDelegate {
    func configureTextView() {
        let view = textView
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.allowsEditingTextAttributes = false
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.dataDetectorTypes = []
        view.tintColor = EditorTheme.accent
        view.typingAttributes = MarkdownStyler.baseAttributes
        view.linkTextAttributes = [:]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = self
        view.textDragDelegate = self
        writingBar = WritingBar(editor: self)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    // MARK: - What the shared editor asks of the text view

    var selection: NSRange { textView.selectedRange }

    func setSelection(_ range: NSRange) {
        isSettingSelection = true
        textView.selectedRange = range
        isSettingSelection = false
    }

    var selectedRanges: [NSRange] { [textView.selectedRange] }
    var isFocused: Bool { textView.isFirstResponder }

    /// A finger is placing the caret or dragging a selection's handles: nothing is revealed or hidden until it
    /// lifts, so the text never moves under it.
    var isTracking: Bool {
        func active(_ view: UIView) -> Bool {
            (view.gestureRecognizers ?? []).contains { recognizer in
                recognizer !== textView.panGestureRecognizer && recognizer !== textView.pinchGestureRecognizer
                    && (recognizer.state == .began || recognizer.state == .changed)
            }
        }
        return active(textView) || textView.subviews.contains(where: active)
    }

    var isInWindow: Bool { textView.window != nil }
    var textOrigin: CGPoint { textView.textContainerOrigin }

    /// The page the text is in, which scrolls rather than the text.
    var scroller: UIScrollView? {
        var ancestor = textView.superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        return ancestor as? UIScrollView
    }

    var hasScroller: Bool { scroller != nil }

    /// The part of the text you can see, in the text view's coordinates.
    var visibleRect: CGRect {
        guard let scroller else { return textView.bounds }
        let visible = scroller.bounds.inset(by: scroller.adjustedContentInset)
        return scroller.convert(visible, to: textView).intersection(textView.bounds)
    }

    /// How far down the window a point of the text is, which scrolling the page changes.
    func screenY(_ y: CGFloat) -> CGFloat {
        textView.convert(CGPoint(x: 0, y: y), to: nil).y
    }

    /// Scrolls the page down by `delta` points (up when negative). A page that isn't tall enough for it yet, because
    /// SwiftUI lays it out again only in a moment, gets there once it is.
    func scrollPage(by delta: CGFloat) {
        guard let scroller else { return }
        let target = scroller.contentOffset.y + delta
        func scroll() {
            let lowest = -scroller.adjustedContentInset.top
            let highest = max(lowest, scroller.contentSize.height + scroller.adjustedContentInset.bottom - scroller.bounds.height)
            let y = min(max(target, lowest), highest)
            guard abs(y - scroller.contentOffset.y) > 0.5 else { return }
            scroller.contentOffset = CGPoint(x: scroller.contentOffset.x, y: y)
        }
        scroll()
        if abs(scroller.contentOffset.y - target) > 0.5 {
            DispatchQueue.main.async { scroll() }
        }
    }

    var isDarkAppearance: Bool { textView.traitCollection.userInterfaceStyle == .dark }

    /// Selected pictures and tables draw a ring of their own, in the text.
    func textNeedsDisplay() {
        let glyphs = layoutManager.glyphRange(forBoundingRect: textView.bounds.offsetBy(dx: -textOrigin.x, dy: -textOrigin.y), in: container)
        layoutManager.invalidateDisplay(forGlyphRange: glyphs)
    }

    func updateEditability() {
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.inputAccessoryView = isEditable ? writingBar : nil
    }

    func makeTextFirstResponder() {
        guard !isFocused else { return }
        _ = textView.becomeFirstResponder()
    }

    /// Done, ⌘↵ and Escape: the keyboard goes, which saves the text.
    func finishEditing() {
        guard isFocused else { return }
        _ = textView.resignFirstResponder()
    }

    /// Changes the text as one step to undo (see `EditorUndo+UIKit`).
    func performEdit(_ range: NSRange, with string: String) -> Bool {
        guard range.upperBound <= storage.length else { return false }
        storage.replaceCharacters(in: range, with: string)
        setSelection(NSRange(location: range.location + (string as NSString).length, length: 0))
        textChanged()
        return true
    }

    // MARK: - UITextViewDelegate

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isLoading else { return }
        let range = textView.selectedRange
        defer { previousSelection = textView.selectedRange }
        closeTypingStep(at: range)
        // The caret steps over bullets and pictures, and a selection takes Markdown whole, as on the Mac. Not while
        // a finger drags the selection's handles, which would make them jump.
        if !isSettingSelection, textView.markedTextRange == nil {
            let fixed = range.length == 0 ? NSRange(location: snapCaret(range.location, from: previousSelection), length: 0) : isTracking ? range : expandSelection(range)
            if fixed != range {
                setSelection(fixed)
                return
            }
        }
        selectionChanged()
        formatState.update(from: self)
        scrollCaretIntoView()
        if isTracking { waitForTrackingToEnd() }
    }

    /// Shows what is next to the caret once the finger lifts.
    private func waitForTrackingToEnd() {
        guard !isWaitingForTracking else { return }
        isWaitingForTracking = true
        func check() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                if self.isTracking { return check() }
                self.isWaitingForTracking = false
                let range = self.selection
                if range.length > 0 {
                    let expanded = self.expandSelection(range)
                    if expanded != range { self.setSelection(expanded) }
                }
                self.mouseTrackingEnded()
            }
        }
        check()
    }

    func textViewDidChange(_ textView: UITextView) {
        textChanged()
        formatState.update(from: self)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard !isLoading, !isPerformingEdit, textView.markedTextRange == nil else { return true }
        let selection = self.selection
        if text == "\n", range == selection {
            return !insertNewline()
        }
        if text.isEmpty, selection.length == 0, range.length > 0, range.upperBound == selection.location {
            return !deleteBackward()
        }
        if text == "\t", range == selection {
            return !indent(by: 1)
        }
        return shouldInsert(text, in: range)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        // Next time, the keyboard comes up again rather than the Format panel.
        if isShowingFormatPanel {
            textView.inputView = nil
            textView.inputAccessoryView = isEditable ? writingBar : nil
        }
    }

    /// Copy Code first in the menu of a selection in a code block.
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard range.location < storage.length, let block = document.line(containing: range.location)?.block,
              case .code = document.blocks[block].kind else { return nil }
        let start = document.blocks[block].range.location
        let copyCode = UIAction(title: String(localized: .copyCode), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copyCode(at: start) }
        return UIMenu(children: [copyCode] + suggestedActions)
    }

    // MARK: - Taps

    /// Taps on checkboxes, links and pictures are the editor's; everywhere else the text view places the caret.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === textView, !(gestureRecognizer is UIPanGestureRecognizer) else { return true }
        return touchHit(at: gestureRecognizer.location(in: textView)) != nil
    }

    /// What a finger hits: the thing under it, or a checkbox right next to it, which is smaller than a fingertip.
    func touchHit(at point: CGPoint) -> (Hit, CGPoint)? {
        if let hit = hitTest(point) { return (hit, point) }
        for offset in [CGPoint(x: 10, y: 0), CGPoint(x: -10, y: 0), CGPoint(x: 0, y: 8), CGPoint(x: 0, y: -8), CGPoint(x: 18, y: 0)] {
            let nearby = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            if let hit = hitTest(nearby), case .checkbox = hit { return (hit, nearby) }
        }
        return nil
    }

    /// The text view's own taps wait for this one, so a tap on a checkbox neither moves the caret nor brings up the
    /// keyboard.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer.view?.isDescendant(of: textView) == true
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let (hit, point) = touchHit(at: recognizer.location(in: textView)) else { return }
        handleTap(hit, at: point)
    }

    func handleTap(_ hit: Hit, at point: CGPoint) {
        switch hit {
        case .checkbox(let line):
            UISelectionFeedbackGenerator().selectionChanged()
            toggleCheckbox(line: line)
        case .link(let url):
            openLink(url)
        case .picture(let range, let url):
            // A tap shows the picture where it is on the web.
            if let url {
                openLink(url)
            } else if isEditable {
                makeTextFirstResponder()
                setSelection(range)
            }
        case .editLink(let range):
            editLink(at: range)
        case .block(_, let caret):
            openBlock(caret: caret, at: point)
        }
    }

    // MARK: - The keyboard

    /// Keeps the line being typed on visible, scrolling the page it sits in when the keyboard covers it.
    func scrollCaretIntoView() {
        guard isFocused, let range = textView.selectedTextRange, let scroller else { return }
        let caret = textView.caretRect(for: range.end)
        guard !caret.isNull, !caret.isInfinite else { return }
        let rect = textView.convert(caret, to: scroller).insetBy(dx: 0, dy: -24)
        scroller.scrollRectToVisible(rect, animated: true)
    }

    // MARK: - Dragging

    /// What a drag out of the text carries: its Markdown, never the text view's attributed text, which can't travel
    /// and would drop as nothing.
    func textDraggableView(_ textDraggableView: UIView & UITextDraggable, itemsForDrag dragRequest: UITextDragRequest) -> [UIDragItem] {
        let start = textView.offset(from: textView.beginningOfDocument, to: dragRequest.dragRange.start)
        let end = textView.offset(from: textView.beginningOfDocument, to: dragRequest.dragRange.end)
        guard end > start, end <= storage.length else { return [] }
        let markdown = nsText.substring(with: NSRange(location: start, length: end - start))
        return [UIDragItem(itemProvider: NSItemProvider(object: markdown as NSString))]
    }
}
#endif
