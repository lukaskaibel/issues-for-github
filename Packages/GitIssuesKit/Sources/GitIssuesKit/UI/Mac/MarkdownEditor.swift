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
    var placeholder: String
    var isEditable: Bool
    var onSave: (String) -> Void

    /// How long typing has to pause before the text is saved.
    static let saveDelay: TimeInterval = 1.2

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.textStorage?.delegate = context.coordinator
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
        view.placeholder = placeholder
        view.isEditable = isEditable
        view.isSelectable = true
        view.onEndEditing = { [weak coordinator = context.coordinator] in coordinator?.saveNow() }
        MarkdownStyler.style(view.textStorage)
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEditable
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
        if !width.isFinite || width <= 0 { width = view.bounds.width > 0 ? view.bounds.width : 600 }
        return CGSize(width: width, height: view.height(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
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

        // Restyled while the edit is still open, so the new text never shows unstyled.
        nonisolated func textStorage(
            _ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { MarkdownStyler.style(textStorage, insideEdit: true) }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}

/// The text view behind `MarkdownEditor`: sizes itself to its text, draws a placeholder, and treats
/// Escape and ⌘↵ as "done".
final class MarkdownTextView: NSTextView {
    var placeholder = ""
    var onEndEditing: () -> Void = {}

    var isFirstResponder: Bool { window?.firstResponder === self }

    private var measured: (width: CGFloat, string: String, height: CGFloat)?

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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            isContinuousSpellCheckingEnabled = true
            needsDisplay = true
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { isContinuousSpellCheckingEnabled = false }
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
        return super.performKeyEquivalent(with: event)
    }

    private func finishEditing() {
        onEndEditing()
        window?.makeFirstResponder(nil)
    }
}
#endif
