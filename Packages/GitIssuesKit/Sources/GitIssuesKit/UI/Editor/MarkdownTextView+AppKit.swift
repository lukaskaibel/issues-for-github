#if os(macOS)
import AppKit

/// The text view of a Markdown editor. Mouse, keyboard and pasteboard go through the `EditorController`; this class
/// adds what has to live in the view: its height, the placeholder, tracking the mouse, the caret, and Escape and ⌘↵.
@MainActor
final class MarkdownTextView: NSTextView {
    weak var controller: EditorController?

    /// True while the mouse button is down and AppKit is tracking a click or drag. Markdown doesn't show next to the
    /// caret until the button comes up, so selecting never moves text around under the pointer.
    private(set) var isTrackingMouse = false
    /// Shown while the text is empty.
    var placeholder = "" {
        didSet { if placeholder != oldValue, string.isEmpty { needsDisplay = true } }
    }
    /// Takes the keyboard focus as soon as it is in a window, with the caret at the end.
    var takesFocusWhenShown = false
    let copyButton = CodeCopyButton()

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        copyButton.target = self
        copyButton.action = #selector(copyCodeBlock(_:))
        addSubview(copyButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - Size

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: controller?.contentHeight(forWidth: bounds.width) ?? EditorStyle.lineHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
            controller?.onLayoutChange()
        }
    }

    /// The text was set from outside.
    func textDidLoad() {
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    /// You changed the text.
    func textDidChangeContent() {
        if string.count <= 1 { needsDisplay = true }
        invalidateIntrinsicContentSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Diagrams and formulas are pictures in the colours of one appearance.
        controller?.restyleAll()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        var attributes = MarkdownStyler.baseAttributes
        attributes[.foregroundColor] = EditorTheme.textTertiary
        NSAttributedString(string: placeholder, attributes: attributes).draw(at: textContainerOrigin)
    }

    /// A caret as tall as the text it is in, not as the line, which is taller than the font.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let caret = controller?.caretRect(proposed: rect) ?? rect
        if flag {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: caret.minX, y: caret.minY, width: 2, height: caret.height), xRadius: 1, yRadius: 1).fill()
        } else {
            super.drawInsertionPoint(in: rect.union(NSRect(x: caret.minX, y: caret.minY, width: 2, height: caret.height)), color: color, turnedOn: false)
        }
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -2, dy: 0), avoidAdditionalLayout: flag)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if controller?.handleMouseDown(event) == true { return }
        isTrackingMouse = true
        super.mouseDown(with: event)
        isTrackingMouse = false
        controller?.mouseTrackingEnded()
    }

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        controller?.updateCopyButton(at: convert(event.locationInWindow, from: nil))
        controller?.updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        controller?.updateCopyButton(at: nil)
    }

    // AppKit puts the I-beam back on every cursor update; links and checkboxes keep the hand.
    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        controller?.updateCursor(for: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.contextMenu(for: event, base: super.menu(for: event)) ?? super.menu(for: event)
    }

    // The pointer isn't tracked in a window in the background, so nothing would hide the copy button there.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification, object: window)
        if takesFocusWhenShown {
            takesFocusWhenShown = false
            // Once SwiftUI has finished putting the view in place.
            DispatchQueue.main.async { [weak self] in
                guard let self, window.makeFirstResponder(self) else { return }
                setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            }
        }
    }

    @objc private func windowResignedKey() {
        controller?.updateCopyButton(at: nil)
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            if isEditable { isContinuousSpellCheckingEnabled = true }
            needsDisplay = true
            controller?.focusChanged(to: true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            isContinuousSpellCheckingEnabled = false
            controller?.focusChanged(to: false)
        }
        return result
    }

    // MARK: - Keys

    /// ⌘↵ sends or finishes, wherever the editor is.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if window?.firstResponder === self, flags == .command, event.keyCode == 36 || event.keyCode == 76, let controller {
            if let submit = controller.onSubmit { submit() } else { controller.finishEditing() }
            return true
        }
        if window?.firstResponder === self, isEditable, let action = FormatShortcut.action(for: event) {
            NSApp.sendAction(action, to: self, from: nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Pasteboard

    override func copy(_ sender: Any?) {
        if controller?.copySelection(cut: false) != true { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if controller?.copySelection(cut: true) != true { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return super.paste(sender) }
        if controller?.pasteText() != true { super.paste(sender) }
    }
}
#endif
