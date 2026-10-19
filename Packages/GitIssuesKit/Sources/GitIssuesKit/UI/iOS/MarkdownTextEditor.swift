#if os(iOS)
import SwiftUI
import UIKit

/// An issue description to tap into and edit, like in Linear. The Markdown stays as text, so the caret lands
/// exactly where you tap, but it is styled as you type with the same styler as the Mac. Links open with a tap
/// while you are reading. Changes are saved after a short pause and when you leave the field.
struct MarkdownTextEditor: View {
    var text: String
    var placeholder: LocalizedStringResource
    var isEditable: Bool
    var onSave: (String) -> Void
    /// Whether the description is being edited right now.
    var editing: Binding<Bool> = .constant(false)
    @State private var height: CGFloat = MarkdownStyler.lineHeight

    var body: some View {
        MarkdownTextViewBridge(text: text, placeholder: String(localized: placeholder), isEditable: isEditable, onSave: onSave, height: $height, editing: editing)
            .frame(height: max(height, MarkdownStyler.lineHeight))
            .accessibilityLabel(.description)
            .accessibilityIdentifier("issue-description")
    }
}

private struct MarkdownTextViewBridge: UIViewRepresentable {
    var text: String
    var placeholder: String
    var isEditable: Bool
    var onSave: (String) -> Void
    @Binding var height: CGFloat
    @Binding var editing: Bool

    /// How long typing has to pause before the text is saved.
    static let saveDelay: TimeInterval = 1.2

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.isEditable = false
        view.isSelectable = true
        view.allowsEditing = isEditable
        view.tintColor = UIColor(Theme.accent)
        view.linkTextAttributes = [.foregroundColor: UIColor(Theme.accent)]
        view.typingAttributes = MarkdownStyler.baseAttributes
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setMarkdown(Diff3.normalize(text))
        view.placeholder = placeholder
        view.onHeightChange = { [binding = $height] value in
            DispatchQueue.main.async {
                if abs(binding.wrappedValue - value) > 0.5 { binding.wrappedValue = value }
            }
        }
        view.onEndEditing = { [weak coordinator = context.coordinator] in coordinator?.saveNow() }
        return view
    }

    func updateUIView(_ view: MarkdownUITextView, context: Context) {
        context.coordinator.parent = self
        view.allowsEditing = isEditable
        if view.placeholder != placeholder { view.placeholder = placeholder }
        // Text from GitHub or another device replaces what is shown, unless you are typing in it.
        let incoming = Diff3.normalize(text)
        if view.text != incoming, !view.isFirstResponder, !context.coordinator.hasUnsavedChanges {
            view.setMarkdown(incoming)
        }
        view.reportHeight()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextViewBridge
        private(set) var hasUnsavedChanges = false
        private var pendingSave: DispatchWorkItem?

        init(parent: MarkdownTextViewBridge) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            hasUnsavedChanges = true
            pendingView = textView
            (textView as? MarkdownUITextView)?.textDidChange()
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let textView else { return }
                self?.save(textView.text)
            }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + MarkdownTextViewBridge.saveDelay, execute: work)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.editing = true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? MarkdownUITextView)?.scrollCaretIntoView()
            (textView as? MarkdownUITextView)?.updateKeyboardBar(animated: true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.editing = false
            save(textView.text)
            (textView as? MarkdownUITextView)?.endEditingMode()
        }

        func saveNow() {
            guard let view = pendingView else { return }
            save(view.text)
        }

        private weak var pendingView: UITextView?

        private func save(_ text: String) {
            pendingSave?.cancel()
            pendingSave = nil
            guard hasUnsavedChanges else { return }
            hasUnsavedChanges = false
            parent.onSave(text)
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            return UIAction { _ in Platform.open(url) }
        }
    }
}

/// The text view behind the editor: reads until tapped, then edits where the tap landed. Sizes itself to its
/// text, keeps the caret above the keyboard, and types Markdown by the rules of `MarkdownEditing`.
final class MarkdownUITextView: UITextView, NSTextStorageDelegate, MarkdownTextInput {
    var placeholder = "" {
        didSet { placeholderLabel.text = placeholder }
    }
    /// Whether the text may be edited at all (issues yes, pull requests no).
    var allowsEditing = true
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onEndEditing: () -> Void = {}
    var unwrapped: MarkdownUnwrapped?
    private let styleAnimator = MarkdownStyleAnimator()
    private var keyboardBar: MarkdownKeyboardBar?

    private let placeholderLabel = UILabel()
    private var lastHeight: CGFloat = 0
    /// Decides which taps start editing. A separate object, since the text view is already the delegate of
    /// its own gesture recognizers and answering for those would break selection.
    private lazy var tapDecider = TapDecider(textView: self)

    /// The text, kept here: a text view doesn't hold on to a text storage it was given.
    private let storage: NSTextStorage

    /// A TextKit 1 text view, so the styler's layout and measuring work the same as on the Mac.
    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        self.storage = storage
        super.init(frame: .zero, textContainer: container)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    private func setUp() {
        placeholderLabel.textColor = UIColor(Theme.textTertiary)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = tapDecider
        addGestureRecognizer(tap)

        storage.delegate = self
        styleAnimator.view = self
        styleAnimator.onFrame = { [weak self] in self?.reportHeight() }

        let bar = MarkdownKeyboardBar(textView: self)
        keyboardBar = bar
        inputAccessoryView = bar

        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (view: MarkdownUITextView, _) in
            view.restyle()
        }
    }

    func setMarkdown(_ markdown: String) {
        text = markdown
        restyle()
    }

    /// Styles the whole text again, for a new appearance or text size.
    func restyle() {
        styleAnimator.stop()
        let selection = selectedRange
        typingAttributes = MarkdownStyler.baseAttributes
        MarkdownStyler.style(textStorage)
        placeholderLabel.font = MarkdownStyler.baseAttributes[.font] as? UIFont
        placeholderLabel.textColor = UIColor(Theme.textTertiary)
        selectedRange = selection
        textDidChange()
    }

    func textDidChange() {
        placeholderLabel.isHidden = !text.isEmpty
        setNeedsLayout()
        reportHeight()
        updateKeyboardBar(animated: true)
    }

    // Restyled as part of the edit, before it is laid out, so the new text never shows unstyled.
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated { styleAnimator.restyle(textStorage, edited: editedRange) }
    }

    func reportHeight() {
        guard bounds.width > 0 else { return }
        let height = ceil(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
        if abs(height - lastHeight) > 0.5 {
            lastHeight = height
            onHeightChange(height)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = placeholderLabel.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: size.height)
        reportHeight()
    }

    // MARK: Tap to edit

    /// Whether a tap here should start editing: not on a link, and only while reading.
    fileprivate func startsEditing(at point: CGPoint) -> Bool {
        allowsEditing && !isEditable && link(at: point) == nil
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        beginEditing(at: recognizer.location(in: self))
    }

    override func accessibilityActivate() -> Bool {
        guard allowsEditing, !isEditable else { return super.accessibilityActivate() }
        beginEditing(at: nil)
        return true
    }

    private func beginEditing(at point: CGPoint?) {
        isEditable = true
        becomeFirstResponder()
        if let point, let position = closestPosition(to: point) {
            selectedTextRange = textRange(from: position, to: position)
        } else {
            selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        updateKeyboardBar(animated: false)
    }

    func endEditingMode() {
        isEditable = false
    }

    private func link(at point: CGPoint) -> URL? {
        guard !text.isEmpty else { return nil }
        let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < textStorage.length else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        return textStorage.attribute(.link, at: index, effectiveRange: nil) as? URL
    }

    /// Keeps the line being typed on visible, scrolling the screen it sits in when the keyboard covers it.
    func scrollCaretIntoView() {
        guard isFirstResponder, let range = selectedTextRange else { return }
        let caret = caretRect(for: range.end)
        guard !caret.isNull, !caret.isInfinite else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scrollView = ancestor as? UIScrollView else { return }
        let rect = convert(caret, to: scrollView).insetBy(dx: 0, dy: -24)
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onEndEditing() }
        return resigned
    }

    /// With a keyboard, ⌘↵ and Escape leave the description, as on the Mac. Escape stays with the text while a
    /// word is still being composed, as in Japanese or Chinese input.
    override var keyCommands: [UIKeyCommand]? {
        guard isEditable, isFirstResponder else { return super.keyCommands }
        let done = UIKeyCommand(title: String(localized: .done), action: #selector(finishEditing), input: "\r", modifierFlags: .command)
        done.wantsPriorityOverSystemBehavior = true
        var commands = (super.keyCommands ?? []) + [done]
        if markedTextRange == nil {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(finishEditing))
            escape.wantsPriorityOverSystemBehavior = true
            commands.append(escape)
            // ⌘B and ⌘I come from the system's Format menu, through toggleBoldface and toggleItalics.
            commands += [
                UIKeyCommand(title: String(localized: .formatCode), action: #selector(formatCode), input: "e", modifierFlags: .command),
                UIKeyCommand(title: String(localized: .formatStrikethrough), action: #selector(formatStrikethrough), input: "x", modifierFlags: [.command, .shift]),
                UIKeyCommand(title: String(localized: .formatNumberedList), action: #selector(formatNumberedList), input: "7", modifierFlags: [.command, .shift]),
                UIKeyCommand(title: String(localized: .formatBulletedList), action: #selector(formatBulletedList), input: "8", modifierFlags: [.command, .shift]),
                UIKeyCommand(title: String(localized: .formatChecklist), action: #selector(formatChecklist), input: "9", modifierFlags: [.command, .shift]),
            ]
            let indent = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentItem))
            let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentItem))
            indent.wantsPriorityOverSystemBehavior = true
            outdent.wantsPriorityOverSystemBehavior = true
            commands += [indent, outdent]
        }
        return commands
    }

    @objc private func finishEditing() {
        _ = resignFirstResponder()
    }

    // MARK: Typing Markdown

    var markdownState: MarkdownEditing.State {
        MarkdownEditing.State(text ?? "", selection: selectedRange)
    }

    func apply(_ state: MarkdownEditing.State) {
        let change = MarkdownEditing.difference(from: text ?? "", to: state.text)
        if change.range.length > 0 || !change.replacement.isEmpty,
           let start = position(from: beginningOfDocument, offset: change.range.location),
           let end = position(from: start, offset: change.range.length),
           let range = textRange(from: start, to: end) {
            styleAnimator.keep(textStorage, replacing: change.range, with: change.replacement)
            replace(range, withText: change.replacement)
        }
        selectedRange = state.selection
        updateKeyboardBar(animated: true)
    }

    /// Whether the typing rules may change this keystroke: not while a word is being composed (Japanese, Chinese).
    private var acceptsRules: Bool { isEditable && markedTextRange == nil }

    override func insertText(_ text: String) {
        let rule: (MarkdownEditing.State) -> MarkdownEditing.State? = text == "\n"
            ? MarkdownEditing.insertNewline(in:)
            : { MarkdownEditing.insert(text, in: $0) }
        guard acceptsRules, perform(rule) else { return super.insertText(text) }
    }

    override func deleteBackward() {
        guard acceptsRules, perform(MarkdownEditing.deleteBackward) else { return super.deleteBackward() }
    }

    override func toggleBoldface(_ sender: Any?) {
        toggle(.bold)
    }

    override func toggleItalics(_ sender: Any?) {
        toggle(.italic)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(toggleBoldface(_:)), #selector(toggleItalics(_:)): isEditable
        // Markdown has no underline.
        case #selector(toggleUnderline(_:)): false
        default: super.canPerformAction(action, withSender: sender)
        }
    }

    @objc private func formatCode() { toggle(.code) }
    @objc private func formatStrikethrough() { toggle(.strikethrough) }
    @objc private func formatNumberedList() { toggle(.ordered) }
    @objc private func formatBulletedList() { toggle(.bullet) }
    @objc private func formatChecklist() { toggle(.checklist) }

    /// Tab and ⇧Tab move a list item in and out; elsewhere Tab types a tab, as before.
    @objc private func indentItem() {
        if !perform(MarkdownEditing.indent) { insertText("\t") }
    }

    @objc private func outdentItem() {
        perform(MarkdownEditing.outdent)
    }

    func updateKeyboardBar(animated: Bool) {
        guard isFirstResponder else { return }
        keyboardBar?.update(MarkdownEditing.context(in: markdownState), animated: animated && window != nil)
    }

    // MARK: Links from the keyboard bar

    /// Wraps the selection in Markdown, or inserts the marks with the caret between them.
    func wrapSelection(_ prefix: String, _ suffix: String, placeholder: String = "") {
        guard let range = selectedTextRange else { return }
        let selected = text(in: range) ?? ""
        let inner = selected.isEmpty ? placeholder : selected
        replace(range, withText: prefix + inner + suffix)
        // Text positions count UTF-16 units, so an emoji in the selection counts as two.
        if let start = position(from: range.start, offset: prefix.utf16.count),
           let end = position(from: start, offset: inner.utf16.count) {
            selectedTextRange = textRange(from: start, to: end)
        }
    }

}

private final class TapDecider: NSObject, UIGestureRecognizerDelegate {
    weak var textView: MarkdownUITextView?

    init(textView: MarkdownUITextView) {
        self.textView = textView
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let textView else { return false }
        return MainActor.assumeIsolated { textView.startsEditing(at: touch.location(in: textView)) }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// The bar above the keyboard while editing a description. On its left, buttons for where the caret is come and
/// go: the styles it is in (a tap takes one off), the checkbox of its line, moving a list item in or out, and
/// opening the link it is on. Then the Markdown shortcuts, which scroll on a narrow iPhone, and Done. Built by hand
/// rather than as a toolbar, which folds Done into an overflow menu on a narrow iPhone; here Done always stays in
/// reach.
private final class MarkdownKeyboardBar: UIView {
    /// The buttons for where the caret is, in the order they stand in.
    private enum QuickAction: CaseIterable {
        case bold, italic, strikethrough, code, checkbox, outdent, indent, openLink

        var style: MarkdownSyntax.Style? {
            switch self {
            case .bold: .bold
            case .italic: .italic
            case .strikethrough: .strikethrough
            case .code: .code
            default: nil
            }
        }
    }

    weak var textView: MarkdownUITextView?
    /// Without glass while it is empty: glass appears by getting its effect, not by fading in.
    private let quickCapsule = UIVisualEffectView(effect: nil)
    private var quickButtons: [QuickAction: UIButton] = [:]
    private var shown: [QuickAction] = []
    private var isChecked = false

    init(textView: MarkdownUITextView) {
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 58))
        autoresizingMask = .flexibleWidth
        backgroundColor = .clear

        let buttons = UIStackView(arrangedSubviews: [
            button("bold", .formatBold) { $0.toggle(.bold) },
            button("italic", .formatItalic) { $0.toggle(.italic) },
            button("chevron.left.forwardslash.chevron.right", .formatCode) { $0.toggle(.code) },
            button("list.bullet", .formatBulletedList) { $0.toggle(.bullet) },
            button("checklist", .formatChecklist) { $0.toggle(.checklist) },
            button("link", .formatLink) { $0.wrapSelection("[", "](https://)", placeholder: String(localized: .linkTextPlaceholder)) },
        ])
        buttons.axis = .horizontal
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(buttons)

        let capsule = UIVisualEffectView(effect: UIGlassEffect())
        capsule.cornerConfiguration = .capsule()
        capsule.clipsToBounds = true
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(scroll)

        let quick = UIStackView(arrangedSubviews: QuickAction.allCases.map { action in
            let button = quickButton(action)
            quickButtons[action] = button
            return button
        })
        quick.axis = .horizontal
        quick.spacing = 2
        quick.alignment = .center
        quick.translatesAutoresizingMaskIntoConstraints = false
        quickCapsule.cornerConfiguration = .capsule()
        quickCapsule.clipsToBounds = true
        quickCapsule.isHidden = true
        quickCapsule.contentView.addSubview(quick)

        // The buttons for where the caret is first, pushing the shortcuts along when they come.
        let row = UIStackView(arrangedSubviews: [quickCapsule, capsule])
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        var doneConfiguration = UIButton.Configuration.prominentGlass()
        doneConfiguration.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        let done = UIButton(configuration: doneConfiguration, primaryAction: UIAction { [weak self] _ in
            _ = self?.textView?.resignFirstResponder()
        })
        done.tintColor = UIColor(Theme.accent)
        done.accessibilityLabel = String(localized: .done)
        done.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        addSubview(done)

        // The capsule hugs its buttons and gives way, scrolling, when the bar is too narrow for all of them.
        let hug = capsule.widthAnchor.constraint(equalTo: buttons.widthAnchor, constant: 12)
        hug.priority = .defaultHigh
        // Room for a button or so of the shortcuts, whatever comes on the left.
        let squeeze = capsule.widthAnchor.constraint(greaterThanOrEqualToConstant: 58)
        squeeze.priority = .required - 1
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -12),
            capsule.heightAnchor.constraint(equalToConstant: 46),
            quickCapsule.heightAnchor.constraint(equalToConstant: 46),
            hug,
            squeeze,

            done.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: 46),
            done.heightAnchor.constraint(equalToConstant: 46),

            scroll.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),

            buttons.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            buttons.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),

            quick.leadingAnchor.constraint(equalTo: quickCapsule.contentView.leadingAnchor, constant: 5),
            quick.trailingAnchor.constraint(equalTo: quickCapsule.contentView.trailingAnchor, constant: -5),
            quick.centerYAnchor.constraint(equalTo: quickCapsule.contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 58)
    }

    /// Shows the buttons for where the caret is now, those that come growing in and those that go shrinking away.
    func update(_ context: MarkdownEditing.Context, animated: Bool) {
        var actions = QuickAction.allCases.filter { $0.style.map(context.styles.contains) ?? false }
        if context.isChecklist { actions.append(.checkbox) }
        if context.canOutdent { actions.append(.outdent) }
        if context.canIndent { actions.append(.indent) }
        if context.link != nil { actions.append(.openLink) }
        // As many as a narrow iPhone has room for beside the shortcuts.
        actions = Array(actions.prefix(5))
        if context.isChecklist, context.isChecked != isChecked {
            isChecked = context.isChecked
            updateCheckbox()
        }
        guard actions != shown else { return }
        for action in actions where !shown.contains(action) {
            quickButtons[action]?.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        }
        shown = actions
        let changes = { [self] in
            for (action, button) in quickButtons {
                let visible = actions.contains(action)
                // A stack view counts hiding twice as twice; only change what changed.
                if button.isHidden == visible { button.isHidden = !visible }
                button.alpha = visible ? 1 : 0
                button.transform = visible ? .identity : CGAffineTransform(scaleX: 0.4, y: 0.4)
            }
            if quickCapsule.isHidden == !actions.isEmpty {
                quickCapsule.isHidden = actions.isEmpty
                quickCapsule.effect = actions.isEmpty ? nil : UIGlassEffect()
            }
            layoutIfNeeded()
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else { return changes() }
        UIView.animate(springDuration: Theme.keyboardBarSpring.duration, bounce: Theme.keyboardBarSpring.bounce,
                       initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: changes)
    }

    private func button(_ symbol: String, _ label: LocalizedStringResource, _ action: @escaping (MarkdownUITextView) -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        configuration.baseForegroundColor = .label
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            guard let view = self?.textView else { return }
            action(view)
        })
        button.accessibilityLabel = String(localized: label)
        button.widthAnchor.constraint(equalToConstant: 46).isActive = true
        return button
    }

    /// A button for where the caret is. A style the caret is in shows as on, tinted, and a tap turns it off.
    private func quickButton(_ action: QuickAction) -> UIButton {
        let symbol: String
        let label: LocalizedStringResource
        switch action {
        case .bold: (symbol, label) = ("bold", .formatBold)
        case .italic: (symbol, label) = ("italic", .formatItalic)
        case .strikethrough: (symbol, label) = ("strikethrough", .formatStrikethrough)
        case .code: (symbol, label) = ("chevron.left.forwardslash.chevron.right", .formatCode)
        case .checkbox: (symbol, label) = ("square", .formatCheckbox)
        case .outdent: (symbol, label) = ("decrease.indent", .formatOutdent)
        case .indent: (symbol, label) = ("increase.indent", .formatIndent)
        case .openLink: (symbol, label) = ("arrow.up.right.square", .formatOpenLink)
        }
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        if action.style != nil {
            configuration.baseForegroundColor = UIColor(Theme.accent)
            configuration.background.backgroundColor = UIColor(Theme.accent).withAlphaComponent(0.16)
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.perform(action)
        })
        button.accessibilityLabel = String(localized: label)
        if action.style != nil { button.accessibilityTraits.insert(.selected) }
        if action == .checkbox { button.accessibilityValue = String(localized: .checkboxUnchecked) }
        button.isHidden = true
        button.alpha = 0
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
        return button
    }

    private func updateCheckbox() {
        guard let button = quickButtons[.checkbox] else { return }
        button.configuration?.image = UIImage(systemName: isChecked ? "checkmark.square.fill" : "square", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        button.configuration?.baseForegroundColor = isChecked ? UIColor(Theme.accent) : .label
        button.accessibilityValue = String(localized: isChecked ? .checkboxChecked : .checkboxUnchecked)
    }

    private func perform(_ action: QuickAction) {
        guard let textView else { return }
        if let style = action.style { return textView.toggle(style) }
        switch action {
        case .checkbox: textView.perform(MarkdownEditing.toggleCheckbox)
        case .outdent: textView.perform(MarkdownEditing.outdent)
        case .indent: textView.perform(MarkdownEditing.indent)
        case .openLink:
            if let link = MarkdownEditing.context(in: textView.markdownState).link { Platform.open(link) }
        default: break
        }
    }
}
#endif
