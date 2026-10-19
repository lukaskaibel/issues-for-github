#if os(macOS)
import AppKit
import SwiftUI

/// An issue description you can click into and type, like in Linear. The Markdown stays as text, so the
/// caret lands exactly where you click, but it is styled as you type: headings are larger, bold is bold,
/// code is monospaced, and the Markdown punctuation fades back. Changes are saved after a short pause and
/// when you leave the field.
struct MarkdownEditor: NSViewRepresentable {
    /// The text as it is in the model. Shown whenever you aren't in the middle of editing it.
    var text: String
    var placeholder: LocalizedStringResource
    var isEditable: Bool
    var onSave: (String) -> Void
    /// Whether the text is being typed in.
    var editing: Binding<Bool> = .constant(false)
    /// Takes the keyboard focus as soon as it is shown, with the caret at the end.
    var takesFocus = false

    /// How long typing has to pause before the text is saved.
    static let saveDelay: TimeInterval = 1.2

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.setUpStyling()
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.insertionPointColor = NSColor(Theme.accent)
        view.linkTextAttributes = [.foregroundColor: NSColor(Theme.accent), .cursor: NSCursor.pointingHand]
        view.typingAttributes = MarkdownStyler.baseAttributes
        view.string = Diff3.normalize(text)
        view.placeholder = String(localized: placeholder)
        view.isEditable = isEditable
        view.isSelectable = true
        view.onEndEditing = { [weak coordinator = context.coordinator] in coordinator?.saveNow() }
        view.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.editing.wrappedValue = focused
        }
        view.takesFocusWhenShown = takesFocus
        MarkdownStyler.style(view.textStorage)
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEditable
        let placeholder = String(localized: placeholder)
        if view.placeholder != placeholder {
            view.placeholder = placeholder
            view.needsDisplay = true
        }
        // Text from GitHub or another device replaces what is shown, unless you are typing in it.
        let incoming = Diff3.normalize(text)
        if view.string != incoming, !view.isFirstResponder, !context.coordinator.hasUnsavedChanges {
            view.string = incoming
            MarkdownStyler.style(view.textStorage)
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: MarkdownTextView, context: Context) -> CGSize? {
        var width = proposal.width ?? view.bounds.width
        if !width.isFinite || (proposal.width == nil && width <= 0) { width = view.bounds.width > 0 ? view.bounds.width : 600 }
        // Asked how narrow it can be (a proposal of zero, as the window's columns ask), the text wraps: answering
        // with the width it has now would keep the page from ever getting narrower than it is.
        width = max(width, 40)
        return CGSize(width: width, height: view.height(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        private(set) var hasUnsavedChanges = false
        private var pendingSave: DispatchWorkItem?
        private weak var textView: MarkdownTextView?

        init(parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? MarkdownTextView else { return }
            textView = view
            hasUnsavedChanges = true
            view.invalidateIntrinsicContentSize()
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.saveNow() }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + MarkdownEditor.saveDelay, execute: work)
        }

        func textDidEndEditing(_ notification: Notification) {
            saveNow()
        }

        func saveNow() {
            pendingSave?.cancel()
            pendingSave = nil
            guard hasUnsavedChanges, let view = textView else { return }
            hasUnsavedChanges = false
            parent.onSave(view.string)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}

/// The text view behind `MarkdownEditor`: sizes itself to its text, draws a placeholder, types Markdown by the
/// rules of `MarkdownEditing` (with ⌘B and the other shortcuts), and treats Escape and ⌘↵ as "done".
final class MarkdownTextView: NSTextView, NSTextStorageDelegate, MarkdownTextInput {
    var placeholder = ""
    var onEndEditing: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var takesFocusWhenShown = false
    var unwrapped: MarkdownUnwrapped?

    var isFirstResponder: Bool { window?.firstResponder === self }

    private var measured: (width: CGFloat, string: String, height: CGFloat)?
    private let styleAnimator = MarkdownStyleAnimator()

    func setUpStyling() {
        textStorage?.delegate = self
        styleAnimator.view = self
        styleAnimator.onFrame = { [weak self] in
            // A heading that grows changes the height without changing the text.
            self?.measured = nil
            self?.invalidateIntrinsicContentSize()
        }
    }

    // Restyled as part of the edit, before it is laid out, so the new text never shows unstyled.
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated { styleAnimator.restyle(textStorage, edited: editedRange) }
    }

    /// The height the text needs at a width, measured on a copy so the visible layout is left alone.
    func height(forWidth width: CGFloat) -> CGFloat {
        let width = max(width, 1)
        if let measured, measured.width == width, measured.string == string { return measured.height }
        guard let storage = textStorage else { return MarkdownStyler.lineHeight }
        let copy = NSTextStorage(attributedString: storage)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        copy.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let height = ceil(max(layout.usedRect(for: container).height, MarkdownStyler.lineHeight))
        measured = (width, string, height)
        return height
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        textContainer?.containerSize = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        var attributes = MarkdownStyler.baseAttributes
        attributes[.foregroundColor] = NSColor(Theme.textTertiary)
        NSAttributedString(string: placeholder, attributes: attributes).draw(at: textContainerOrigin)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesFocusWhenShown, let window else { return }
        takesFocusWhenShown = false
        // Once SwiftUI has finished putting the view in place.
        DispatchQueue.main.async { [weak self] in
            guard let self, window.makeFirstResponder(self) else { return }
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            isContinuousSpellCheckingEnabled = true
            needsDisplay = true
            onFocusChange(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isContinuousSpellCheckingEnabled = false
            onFocusChange(false)
        }
        return resigned
    }

    /// Escape finishes editing instead of opening the completion list.
    override func cancelOperation(_ sender: Any?) {
        finishEditing()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isFirstResponder, flags == .command, event.keyCode == 36 || event.keyCode == 76 {
            finishEditing()
            return true
        }
        if isFirstResponder, isEditable, !hasMarkedText(), formatShortcut(event, flags) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘B, ⌘I, ⌘E and ⌘⇧X for bold, italics, code and strikethrough, and ⌘⇧7, ⌘⇧8 and ⌘⇧9 for a numbered list,
    /// bullets and a checklist, as in Google Docs and Notion. The digits go by their key, whatever the layout.
    private func formatShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key, event.keyCode) {
        case (.command, "b", _): toggle(.bold)
        case (.command, "i", _): toggle(.italic)
        case (.command, "e", _): toggle(.code)
        case ([.command, .shift], "x", _): toggle(.strikethrough)
        case ([.command, .shift], _, 26): toggle(.ordered)
        case ([.command, .shift], _, 28): toggle(.bullet)
        case ([.command, .shift], _, 25): toggle(.checklist)
        default: return false
        }
        return true
    }

    // MARK: Typing Markdown

    var markdownState: MarkdownEditing.State {
        MarkdownEditing.State(string, selection: selectedRange())
    }

    func apply(_ state: MarkdownEditing.State) {
        let change = MarkdownEditing.difference(from: string, to: state.text)
        if change.range.length > 0 || !change.replacement.isEmpty, let storage = textStorage {
            breakUndoCoalescing()
            guard shouldChangeText(in: change.range, replacementString: change.replacement) else { return }
            styleAnimator.keep(storage, replacing: change.range, with: change.replacement)
            storage.replaceCharacters(in: change.range, with: change.replacement)
            didChangeText()
        }
        setSelectedRange(state.selection)
    }

    /// Whether the typing rules may change this keystroke: not while a word is being composed (Japanese, Chinese).
    private var acceptsRules: Bool { isEditable && !hasMarkedText() }

    override func insertNewline(_ sender: Any?) {
        guard acceptsRules, perform(MarkdownEditing.insertNewline) else { return super.insertNewline(sender) }
    }

    override func deleteBackward(_ sender: Any?) {
        guard acceptsRules, perform(MarkdownEditing.deleteBackward) else { return super.deleteBackward(sender) }
    }

    override func deleteForward(_ sender: Any?) {
        guard acceptsRules, perform(MarkdownEditing.deleteForward) else { return super.deleteForward(sender) }
    }

    /// Tab and ⇧Tab move a list item in and out; elsewhere they do what they always do.
    override func insertTab(_ sender: Any?) {
        guard acceptsRules, perform(MarkdownEditing.indent) else { return super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        guard acceptsRules, perform(MarkdownEditing.outdent) else { return super.insertBacktab(sender) }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if acceptsRules, replacementRange.location == NSNotFound, let typed = string as? String,
           perform({ MarkdownEditing.insert(typed, in: $0) }) {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    private func finishEditing() {
        onEndEditing()
        window?.makeFirstResponder(nil)
    }
}
#endif
