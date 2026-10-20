#if os(iOS)
import UIKit

/// The text view of a Markdown editor on iPhone and iPad: UIKit's, on the same TextKit 1 storage and layout manager as
/// the Mac's, so Markdown is styled, laid out and drawn by the same code. It doesn't scroll itself: it is as tall as its
/// text, in a page that scrolls. Typing, taps and the pasteboard go through the `EditorController`.
@MainActor
final class MarkdownTextView: UITextView {
    weak var controller: EditorController?

    var placeholder = "" {
        didSet { placeholderLabel.text = placeholder }
    }
    /// Called when the text needs another height.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    private let placeholderLabel = UILabel()
    private var lastHeight: CGFloat = 0
    private var laidOutWidth: CGFloat = 0

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
        updatePlaceholderStyle()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (view: MarkdownTextView, _) in
            view.updatePlaceholderStyle()
            view.controller?.restyleAll()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updatePlaceholderStyle() {
        placeholderLabel.font = EditorStyle.body
        placeholderLabel.textColor = EditorTheme.textTertiary
    }

    /// Where the text container starts, as `NSTextView.textContainerOrigin`.
    var textContainerOrigin: CGPoint { CGPoint(x: textContainerInset.left, y: textContainerInset.top) }

    /// The editor's record of changes, which undo and redo go through (see `EditorUndo+UIKit`).
    override var undoManager: UndoManager? { controller?.undoStack ?? super.undoManager }

    // MARK: - Size

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = placeholderLabel.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: 0, y: (EditorStyle.lineHeight - size.height) / 2 - 1, width: bounds.width, height: size.height)
        reportHeight()
        if laidOutWidth != bounds.width {
            laidOutWidth = bounds.width
            controller?.onLayoutChange()
        }
    }

    func reportHeight() {
        guard bounds.width > 0, let controller else { return }
        let height = controller.contentHeight(forWidth: bounds.width)
        if abs(height - lastHeight) > 0.5 {
            lastHeight = height
            onHeightChange(height)
        }
    }

    /// The text was set from outside.
    func textDidLoad() {
        placeholderLabel.isHidden = !text.isEmpty
        setNeedsLayout()
        reportHeight()
    }

    /// You changed the text.
    func textDidChangeContent() {
        placeholderLabel.isHidden = !text.isEmpty
        reportHeight()
    }

    // MARK: - Caret

    /// A caret as tall as the text it is in, not as the line, which is taller than the font.
    override func caretRect(for position: UITextPosition) -> CGRect {
        let rect = super.caretRect(for: position)
        guard let controller, !rect.isNull, !rect.isInfinite else { return rect }
        return controller.caretRect(proposed: rect)
    }

    /// A picture selected whole shows the ring the layout manager draws around it, not the text's selection.
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        if let controller {
            let start = offset(from: beginningOfDocument, to: range.start)
            let length = offset(from: range.start, to: range.end)
            if controller.isWholeObject(NSRange(location: start, length: length)) { return [] }
        }
        return super.selectionRects(for: range)
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { controller?.focusChanged(to: true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { controller?.focusChanged(to: false) }
        return result
    }

    // MARK: - Pasteboard

    override func copy(_ sender: Any?) {
        if controller?.copySelection(cut: false) != true { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if controller?.copySelection(cut: true) != true { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        if controller?.pasteText() != true { super.paste(sender) }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Bold and italic are Markdown: a text view without rich text would leave them out (and ⌘B, ⌘I with them).
        if action == #selector(toggleBoldface(_:)) || action == #selector(toggleItalics(_:)) { return isEditable }
        if action == #selector(toggleUnderline(_:)) { return false }
        if Self.formatActions.contains(action) { return isEditable && isFirstResponder }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: - Formatting, from the keyboard's shortcuts, the edit menu and the Format menu

    override func toggleBoldface(_ sender: Any?) { controller?.toggle(.bold) }
    override func toggleItalics(_ sender: Any?) { controller?.toggle(.italic) }
    // Markdown has no underline.
    override func toggleUnderline(_ sender: Any?) {}

    static let formatActions: Set<Selector> = [
        #selector(toggleInlineCode(_:)), #selector(toggleStrikethrough(_:)), #selector(makeTitle(_:)), #selector(makeHeading(_:)),
        #selector(makeSubheading(_:)), #selector(makeBody(_:)), #selector(makeBulletedList(_:)), #selector(makeNumberedList(_:)),
        #selector(makeChecklist(_:)), #selector(makeQuote(_:)), #selector(markChecked(_:)), #selector(addLink(_:)),
        #selector(indentLines(_:)), #selector(outdentLines(_:)),
    ]

    @objc func toggleInlineCode(_ sender: Any?) { controller?.toggle(.code) }
    @objc func toggleStrikethrough(_ sender: Any?) { controller?.toggle(.strikethrough) }
    @objc func makeTitle(_ sender: Any?) { controller?.setLineFormat(.heading(1)) }
    @objc func makeHeading(_ sender: Any?) { controller?.setLineFormat(.heading(2)) }
    @objc func makeSubheading(_ sender: Any?) { controller?.setLineFormat(.heading(3)) }
    @objc func makeBody(_ sender: Any?) { controller?.setLineFormat(.body) }
    @objc func makeBulletedList(_ sender: Any?) { controller?.setLineFormat(.bullets) }
    @objc func makeNumberedList(_ sender: Any?) { controller?.setLineFormat(.numbered) }
    @objc func makeChecklist(_ sender: Any?) { controller?.setLineFormat(.checklist) }
    @objc func makeQuote(_ sender: Any?) { controller?.setLineFormat(.quote) }
    @objc func markChecked(_ sender: Any?) { controller?.toggleChecked() }
    @objc func addLink(_ sender: Any?) { controller?.insertLink() }
    @objc func indentLines(_ sender: Any?) { controller?.indent(by: 1) }
    @objc func outdentLines(_ sender: Any?) { controller?.indent(by: -1) }

    // MARK: - Keys of a hardware keyboard

    /// The Format menu's shortcuts, as on the Mac; Shift-Tab un-nests a list item; ⌘↵ sends or finishes and Escape
    /// finishes, as on the Mac. Escape stays with the text while a word is still being composed, as in Japanese or
    /// Chinese input.
    override var keyCommands: [UIKeyCommand]? {
        guard isEditable, isFirstResponder else { return super.keyCommands }
        var commands = super.keyCommands ?? []
        commands += FormatShortcut.groups.joined().map(\.keyCommand)
        let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentLines(_:)))
        outdent.wantsPriorityOverSystemBehavior = true
        commands.append(outdent)
        let done = UIKeyCommand(title: String(localized: controller?.submitTitle ?? .done), action: #selector(submit), input: "\r", modifierFlags: .command)
        done.wantsPriorityOverSystemBehavior = true
        commands.append(done)
        if markedTextRange == nil {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(finish))
            escape.wantsPriorityOverSystemBehavior = true
            commands.append(escape)
        }
        // ↑ on the first line and ← at the very start go to the title above the text, as on the Mac.
        if controller?.onBackToTitle != nil {
            var inputs: [String] = []
            if controller?.isCaretOnFirstLine == true { inputs.append(UIKeyCommand.inputUpArrow) }
            if selectedRange == NSRange(location: 0, length: 0) { inputs.append(UIKeyCommand.inputLeftArrow) }
            for input in inputs {
                let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(backToTitle))
                command.wantsPriorityOverSystemBehavior = true
                commands.append(command)
            }
        }
        return commands
    }

    @objc private func backToTitle() {
        guard let controller else { return }
        _ = controller.moveUpIntoTitle() || controller.moveBackIntoTitle()
    }

    /// Delete at the very start of the text goes back to the title above it, as into the line above.
    override func deleteBackward() {
        if selectedRange == NSRange(location: 0, length: 0), controller?.deleteBackIntoTitle() == true { return }
        super.deleteBackward()
        controller?.lastDeleteBackward = CACurrentMediaTime()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Keys pressed: a keyboard is attached, whatever the game controller framework says.
        if presses.contains(where: { $0.key != nil }) { HardwareKeyboard.shared.keyWasPressed() }
        super.pressesBegan(presses, with: event)
    }

    @objc private func submit() {
        guard let controller else { return }
        if let submit = controller.onSubmit { submit() } else { controller.finishEditing() }
    }

    @objc private func finish() {
        guard let controller else { return }
        if let escape = controller.onEscape { escape() } else { controller.finishEditing() }
    }
}
#endif
