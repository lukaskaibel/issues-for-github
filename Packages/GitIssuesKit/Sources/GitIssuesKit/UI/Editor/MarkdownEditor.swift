import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// GitHub-flavoured Markdown, read and edited in the same place, as in Notebook: always drawn the way GitHub draws it
/// (tables, checklists, code, Mermaid diagrams, maths, alerts and pictures included), with the Markdown showing only
/// next to the caret. A click puts the caret where it lands, and a click into a table, a diagram or a formula opens
/// its source with a preview. It is as tall as its text.
///
/// For a text that is saved as you go (a description), pass `onSave`: it gets the text after a short pause in typing,
/// when you leave the text and when you tick a checkbox. For a draft kept elsewhere (a new comment), pass it as
/// `draft:`, which follows every change.
struct MarkdownEditor: View {
    var text: String
    var placeholder: LocalizedStringResource?
    var isEditable = true
    /// Where the text is only read: whether its checkboxes still tick (saved with `onSave`).
    var allowsChecking = false
    var onSave: ((String) -> Void)?
    var onChange: ((String) -> Void)?
    /// A draft, read afresh at every update: SwiftUI updates the view again for other reasons (its height, say) with
    /// the `text` it had then, which may be a few keys behind the typing.
    var draft: Binding<String>?
    /// Whether it is being typed in.
    var editing: Binding<Bool> = .constant(false)
    /// Takes the keyboard focus as soon as it is shown, with the caret at the end.
    var takesFocus = false
    /// ⌘↵; without it, ⌘↵ finishes editing as Escape does.
    var onSubmit: (() -> Void)?
    /// Escape; without it, Escape finishes editing.
    var onEscape: (() -> Void)?
    /// What ⌘↵ does, in the list of shortcuts on iPad.
    var submitTitle: LocalizedStringResource = .done
    /// The title above the text, which the keys go to and from as to and from the line above.
    var titleLink: TitleLink?
    /// What VoiceOver calls it, and how UI tests find it.
    var accessibilityLabel: LocalizedStringResource?
    var accessibilityIdentifier: String?

    /// How long typing has to pause before the text is saved.
    static let saveDelay: TimeInterval = 1.2

    @State private var checkboxes = MarkdownCheckboxes()

    var body: some View {
        #if os(macOS)
        MarkdownEditorView(configuration: self, checkboxes: checkboxes)
            .overlay(alignment: .topLeading) { CheckboxAccessibility(checkboxes: checkboxes) }
        #else
        SizedMarkdownEditor(configuration: self, checkboxes: checkboxes)
        #endif
    }
}

extension MarkdownEditor {
    /// A draft kept elsewhere, such as a new comment: it follows every change, and a change made to it from outside
    /// (cleared once sent) shows at once.
    init(
        draft: Binding<String>,
        placeholder: LocalizedStringResource? = nil,
        editing: Binding<Bool> = .constant(false),
        takesFocus: Bool = false,
        onSubmit: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil,
        submitTitle: LocalizedStringResource = .done,
        titleLink: TitleLink? = nil,
        accessibilityLabel: LocalizedStringResource? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            text: draft.wrappedValue, placeholder: placeholder, onChange: { draft.wrappedValue = $0 }, draft: draft,
            editing: editing, takesFocus: takesFocus, onSubmit: onSubmit, onEscape: onEscape, submitTitle: submitTitle,
            titleLink: titleLink, accessibilityLabel: accessibilityLabel, accessibilityIdentifier: accessibilityIdentifier
        )
    }

    /// The text as it is now: a draft's current value, else the text given.
    var currentText: String { draft?.wrappedValue ?? text }
}

/// A title field above a Markdown editor (an issue's title over its description), which the keys go between as between
/// lines, as in Notebook: Tab, ↓ on the title's last line and → at its end go to the start of the text; ↑ on the text's
/// first line, and ← or Delete at its very start, go back to the end of the title.
@MainActor
final class TitleLink {
    /// Puts the caret at the start of the text; set by the editor.
    var enterText: () -> Void = {}
    /// Puts the caret at the end of the title; set by the title.
    var enterTitle: () -> Void = {}
    #if os(macOS)
    /// A view behind the title, in the window whose field editor the title is typed in.
    weak var titleView: NSView?
    #endif
}

/// Where the checkboxes are drawn in the text, and how to tick one.
@MainActor
@Observable
final class MarkdownCheckboxes {
    var places: [EditorController.CheckboxPlace] = []
    var areTickable = false
    @ObservationIgnored var toggle: (Int) -> Void = { _ in }
}

/// The checkboxes drawn in the text, as VoiceOver sees them: each with its item's text, ticked or not, and ticked by
/// activating it. They let every touch and click through to the text, where the box is drawn.
private struct CheckboxAccessibility: View {
    var checkboxes: MarkdownCheckboxes

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(checkboxes.places) { place in
                Color.clear
                    .frame(width: place.frame.width, height: place.frame.height)
                    .offset(x: place.frame.minX, y: place.frame.minY)
                    .accessibilityElement()
                    .accessibilityLabel(place.label)
                    .accessibilityValue(Text(place.isChecked ? .checkboxChecked : .checkboxUnchecked))
                    .accessibilityAddTraits(checkboxes.areTickable ? .isButton : [])
                    .accessibilityAction { if checkboxes.areTickable { checkboxes.toggle(place.line) } }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Markdown that is only read, as GitHub draws it: comments, a pull request's description. Its text can be selected
/// and copied, and its links open.
struct MarkdownText: View {
    var text: String
    /// Given, its checkboxes tick; it gets the whole text with one box changed.
    var onChange: ((String) -> Void)?

    var body: some View {
        MarkdownEditor(text: text, isEditable: false, allowsChecking: onChange != nil, onSave: onChange)
    }
}

/// Keeps the editor and the model in step: saves after a pause, takes in text that changed elsewhere, and reports
/// whether the text is being typed in, or puts the caret in it when `editing` is set from outside.
@MainActor
final class MarkdownEditorCoordinator {
    var configuration: MarkdownEditor
    let editor: EditorController
    let checkboxes: MarkdownCheckboxes
    private var refreshingCheckboxes = false
    private(set) var hasUnsavedChanges = false
    private var pendingSave: DispatchWorkItem?
    /// The model's text, as far as the editor knows: what it was given or last handed back.
    private var known: String

    /// What `editing` was when last seen, to tell when it is set from outside.
    private var seenEditing = false

    init(configuration: MarkdownEditor, checkboxes: MarkdownCheckboxes) {
        self.configuration = configuration
        self.checkboxes = checkboxes
        editor = EditorController(isEditable: configuration.isEditable)
        editor.allowsChecking = configuration.allowsChecking
        editor.onSubmit = configuration.onSubmit
        editor.onEscape = configuration.onEscape
        editor.submitTitle = configuration.submitTitle
        known = Diff3.normalize(configuration.currentText)
        link(configuration.titleLink)
        editor.load(text: known)
        editor.textView.placeholder = configuration.placeholder.map { String(localized: $0) } ?? ""
        editor.onTextChange = { [weak self] in self?.textChanged() }
        editor.onFocusChange = { [weak self] focused in self?.focusChanged(focused) }
        seenEditing = configuration.editing.wrappedValue
        editor.onLayoutChange = { [weak self] in self?.refreshCheckboxes() }
        checkboxes.toggle = { [weak editor] line in editor?.toggleCheckbox(line: line) }
        applyAccessibility()
        refreshCheckboxes()
    }

    /// Once the text has settled after a change, where its checkboxes are now.
    private func refreshCheckboxes() {
        guard !refreshingCheckboxes else { return }
        refreshingCheckboxes = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshingCheckboxes = false
            let places = editor.checkboxPlaces()
            let tickable = editor.isEditable || editor.allowsChecking
            if checkboxes.places != places { checkboxes.places = places }
            if checkboxes.areTickable != tickable { checkboxes.areTickable = tickable }
        }
    }

    /// The keys go between the text and the title above it, when it has one; only editable text is gone into.
    private func link(_ titleLink: TitleLink?) {
        guard let titleLink, configuration.isEditable else {
            editor.onBackToTitle = nil
            return
        }
        titleLink.enterText = { [weak editor] in editor?.enterFromTitle() }
        editor.onBackToTitle = { [weak titleLink] in titleLink?.enterTitle() }
    }

    private func applyAccessibility() {
        let view = editor.textView
        #if os(macOS)
        if let label = configuration.accessibilityLabel { view.setAccessibilityLabel(String(localized: label)) }
        if let identifier = configuration.accessibilityIdentifier { view.setAccessibilityIdentifier(identifier) }
        #else
        if let label = configuration.accessibilityLabel { view.accessibilityLabel = String(localized: label) }
        if let identifier = configuration.accessibilityIdentifier { view.accessibilityIdentifier = identifier }
        #endif
    }

    func update(_ configuration: MarkdownEditor) {
        self.configuration = configuration
        editor.isEditable = configuration.isEditable
        if editor.allowsChecking != configuration.allowsChecking {
            editor.allowsChecking = configuration.allowsChecking
            refreshCheckboxes()
        }
        editor.onSubmit = configuration.onSubmit
        editor.onEscape = configuration.onEscape
        editor.submitTitle = configuration.submitTitle
        link(configuration.titleLink)
        let placeholder = configuration.placeholder.map { String(localized: $0) } ?? ""
        if editor.textView.placeholder != placeholder { editor.textView.placeholder = placeholder }
        applyAccessibility()
        // `editing` set from outside puts the caret at the end of the text, or takes the focus away.
        let wanted = configuration.editing.wrappedValue
        if wanted != seenEditing {
            seenEditing = wanted
            DispatchQueue.main.async { [editor] in
                guard editor.isInWindow, wanted != editor.isFocused else { return }
                if wanted {
                    editor.makeTextFirstResponder()
                    editor.setSelection(NSRange(location: editor.storage.length, length: 0))
                } else {
                    editor.finishEditing()
                }
            }
        }
        let incoming = Diff3.normalize(configuration.currentText)
        guard incoming != known else { return }
        if configuration.onChange != nil {
            // While SwiftUI updates the view, a draft can still read as it was a few keys ago. Looked at again once
            // the update is over, it is either what was typed (nothing to do) or changed from outside: sent, or put
            // back. That shows at once.
            DispatchQueue.main.async { [weak self] in self?.takeDraft() }
            return
        }
        known = incoming
        // Text that is saved as you go takes in what came from GitHub or another device unless you are typing in it.
        if !editor.isFocused && !hasUnsavedChanges {
            editor.reload(text: incoming)
        }
    }

    private func takeDraft() {
        let incoming = Diff3.normalize(configuration.currentText)
        guard incoming != known else { return }
        known = incoming
        editor.reload(text: incoming)
    }

    private func textChanged() {
        let text = editor.text
        if let onChange = configuration.onChange {
            known = text
            onChange(text)
        }
        guard configuration.onSave != nil else { return }
        hasUnsavedChanges = true
        pendingSave?.cancel()
        // A checkbox ticked while you aren't typing is saved at once.
        guard editor.isFocused else { return saveNow() }
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MarkdownEditor.saveDelay, execute: work)
    }

    /// The editor goes away: what was typed is saved, and the Format menu knows nothing is being typed in it now.
    func dismantle() {
        MarkdownFocus.shared.focusChanged(editor.textView, to: false)
        saveNow()
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        known = editor.text
        configuration.onSave?(editor.text)
    }

    private func focusChanged(_ focused: Bool) {
        if configuration.editing.wrappedValue != focused { configuration.editing.wrappedValue = focused }
        // A constant binding stays as it is.
        seenEditing = configuration.editing.wrappedValue
        if !focused { saveNow() }
    }
}

#if os(macOS)
private struct MarkdownEditorView: NSViewRepresentable {
    var configuration: MarkdownEditor
    var checkboxes: MarkdownCheckboxes

    func makeCoordinator() -> MarkdownEditorCoordinator {
        MarkdownEditorCoordinator(configuration: configuration, checkboxes: checkboxes)
    }

    func makeNSView(context: Context) -> MarkdownTextView {
        let editor = context.coordinator.editor
        editor.onHeightChange = { [weak view = editor.textView] in view?.invalidateIntrinsicContentSize() }
        editor.textView.takesFocusWhenShown = configuration.takesFocus
        return editor.textView
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.update(configuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: MarkdownTextView, context: Context) -> CGSize? {
        var width = proposal.width ?? view.bounds.width
        if !width.isFinite || (proposal.width == nil && width <= 0) { width = view.bounds.width > 0 ? view.bounds.width : 600 }
        // Asked how narrow it can be (a proposal of zero, as the window's columns ask), the text wraps: answering
        // with the width it has now would keep the page from ever getting narrower than it is.
        width = max(width, 40)
        return CGSize(width: width, height: context.coordinator.editor.contentHeight(forWidth: width))
    }

    static func dismantleNSView(_ view: MarkdownTextView, coordinator: MarkdownEditorCoordinator) {
        coordinator.dismantle()
    }
}
#else
/// UIKit tells the height of the text once it is laid out at its width; the frame follows.
private struct SizedMarkdownEditor: View {
    var configuration: MarkdownEditor
    var checkboxes: MarkdownCheckboxes
    @State private var height = EditorStyle.lineHeight

    var body: some View {
        MarkdownEditorView(configuration: configuration, checkboxes: checkboxes, height: $height)
            .frame(height: max(height, EditorStyle.lineHeight))
            .overlay(alignment: .topLeading) { CheckboxAccessibility(checkboxes: checkboxes) }
    }
}

private struct MarkdownEditorView: UIViewRepresentable {
    var configuration: MarkdownEditor
    var checkboxes: MarkdownCheckboxes
    @Binding var height: CGFloat

    func makeCoordinator() -> MarkdownEditorCoordinator {
        MarkdownEditorCoordinator(configuration: configuration, checkboxes: checkboxes)
    }

    func makeUIView(context: Context) -> MarkdownTextView {
        let editor = context.coordinator.editor
        let view = editor.textView
        view.onHeightChange = { [binding = $height] value in
            DispatchQueue.main.async {
                if abs(binding.wrappedValue - value) > 0.5 { binding.wrappedValue = value }
            }
        }
        editor.onHeightChange = { [weak view] in view?.reportHeight() }
        if configuration.takesFocus {
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.textView.window != nil else { return }
                editor.makeTextFirstResponder()
                editor.setSelection(NSRange(location: editor.storage.length, length: 0))
            }
        }
        return view
    }

    func updateUIView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.update(configuration)
        view.reportHeight()
    }

    static func dismantleUIView(_ view: MarkdownTextView, coordinator: MarkdownEditorCoordinator) {
        coordinator.dismantle()
    }
}
#endif
