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
        view.textStorage.delegate = context.coordinator
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
    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
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

        // Restyled while the edit is still open, so the new text never shows unstyled.
        nonisolated func textStorage(
            _ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { MarkdownStyler.style(textStorage, insideEdit: true) }
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            return UIAction { _ in Platform.open(url) }
        }
    }
}

/// The text view behind the editor: reads until tapped, then edits where the tap landed. Sizes itself to its
/// text and keeps the caret above the keyboard.
final class MarkdownUITextView: UITextView {
    var placeholder = "" {
        didSet { placeholderLabel.text = placeholder }
    }
    /// Whether the text may be edited at all (issues yes, pull requests no).
    var allowsEditing = true
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onEndEditing: () -> Void = {}

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

        inputAccessoryView = MarkdownKeyboardBar(textView: self)

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
        }
        return commands
    }

    @objc private func finishEditing() {
        _ = resignFirstResponder()
    }

    // MARK: Formatting from the keyboard bar

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

    /// Starts the current line with a list marker, unless it already has one.
    func prefixLine(_ marker: String) {
        let string = text as NSString
        let line = string.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let current = string.substring(with: line)
        guard !current.hasPrefix(marker) else { return }
        let caret = selectedRange.location
        guard let start = position(from: beginningOfDocument, offset: line.location),
              let range = textRange(from: start, to: start) else { return }
        replace(range, withText: marker)
        selectedRange = NSRange(location: caret + (marker as NSString).length, length: 0)
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

/// The bar above the keyboard while editing a description: Markdown shortcuts and Done. Built by hand rather
/// than as a toolbar, which folds Done into an overflow menu on a narrow iPhone; here the shortcuts scroll instead
/// and Done always stays in reach.
private final class MarkdownKeyboardBar: UIView {
    weak var textView: MarkdownUITextView?

    init(textView: MarkdownUITextView) {
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 58))
        autoresizingMask = .flexibleWidth
        backgroundColor = .clear

        let buttons = UIStackView(arrangedSubviews: [
            button("bold", .formatBold) { $0.wrapSelection("**", "**") },
            button("italic", .formatItalic) { $0.wrapSelection("_", "_") },
            button("chevron.left.forwardslash.chevron.right", .formatCode) { $0.wrapSelection("`", "`") },
            button("checklist", .formatChecklist) { $0.prefixLine("- [ ] ") },
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

        var doneConfiguration = UIButton.Configuration.prominentGlass()
        doneConfiguration.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        let done = UIButton(configuration: doneConfiguration, primaryAction: UIAction { [weak self] _ in
            _ = self?.textView?.resignFirstResponder()
        })
        done.tintColor = UIColor(Theme.accent)
        done.accessibilityLabel = String(localized: .done)
        done.translatesAutoresizingMaskIntoConstraints = false

        addSubview(capsule)
        addSubview(done)

        // The capsule hugs its buttons and gives way, scrolling, when the bar is too narrow for all of them.
        let hug = capsule.widthAnchor.constraint(equalTo: buttons.widthAnchor, constant: 12)
        hug.priority = .defaultHigh
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            capsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsule.heightAnchor.constraint(equalToConstant: 46),
            capsule.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -12),
            hug,

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
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 58)
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
}
#endif
