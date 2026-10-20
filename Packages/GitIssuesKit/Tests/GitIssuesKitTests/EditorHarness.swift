#if os(macOS)
import AppKit
@testable import GitIssuesKit

/// A Markdown editor in an off-screen window, inside a page that scrolls as an issue's does, for tests that type,
/// click and select like a person would. Taken from Notebook's tests.
@MainActor
final class EditorHarness {
    let editor: EditorController
    let window: NSWindow
    let scrollView: NSScrollView
    /// Links that were clicked.
    var opened: [URL] = []
    /// How often the editor said its text changed.
    var changes = 0

    init(_ text: String, editable: Bool = true, width: CGFloat = 600, height: CGFloat = 700, above: CGFloat = 0, dark: Bool = false) {
        _ = NSApplication.shared
        self.above = above
        editor = EditorController(isEditable: editable)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.hasVerticalScroller = true
        let page = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.documentView = page
        page.addSubview(editor.textView)
        window.contentView = scrollView
        editor.openLink = { [unowned self] in opened.append($0) }
        editor.onTextChange = { [unowned self] in changes += 1 }
        editor.onHeightChange = { [unowned self] in layOut() }
        editor.load(text: text)
        layOut()
        window.makeFirstResponder(editor.textView)
        settle()
    }

    /// Room above the text in the page, as an issue's title takes.
    let above: CGFloat

    /// The text view as tall as its text and the page as tall as that, as SwiftUI lays them out.
    func layOut() {
        let width = scrollView.contentSize.width
        let height = editor.contentHeight(forWidth: width)
        editor.textView.frame = NSRect(x: 0, y: above, width: width, height: height)
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: width, height: max(scrollView.contentSize.height, above + height + 400))
    }

    var textView: MarkdownTextView { editor.textView }
    var text: String { editor.text }
    var selection: NSRange { textView.selectedRange() }

    deinit {
        MainActor.assumeIsolated { window.orderOut(nil) }
    }

    func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        editor.layoutManager.ensureLayout(for: editor.container)
    }

    /// Runs the run loop until the condition holds, or for at most `timeout`: for what happens on a timer or a moment
    /// later, which a busy machine delays.
    @discardableResult
    func settle(until condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        settleRunLoop(until: condition, timeout: timeout)
    }

    // MARK: - Acting like a person

    func caret(_ location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        settle(0)
    }

    func select(_ range: NSRange) {
        textView.setSelectedRange(range)
        settle(0)
    }

    func type(_ string: String) {
        for character in string {
            if character == "\n" {
                textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            } else {
                textView.insertText(String(character), replacementRange: textView.selectedRange())
            }
        }
        settle(0)
    }

    func command(_ selector: Selector) {
        textView.doCommand(by: selector)
        settle(0)
    }

    /// Where a character is drawn, in the text view's coordinates.
    func point(of index: Int, fraction: CGFloat = 0.5) -> NSPoint {
        let layout = editor.layoutManager
        let glyph = layout.glyphIndexForCharacter(at: index)
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: editor.container)
        let origin = textView.textContainerOrigin
        return NSPoint(x: rect.minX + rect.width * fraction + origin.x, y: rect.midY + origin.y)
    }

    /// A real click through AppKit's own mouse tracking: press, optionally drag, release.
    func click(at point: NSPoint, dragTo end: NSPoint? = nil, count: Int = 1) {
        let windowPoint = textView.convert(point, to: nil)
        let endPoint = textView.convert(end ?? point, to: nil)
        func event(_ type: NSEvent.EventType, _ location: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        if end != nil {
            let steps = 6
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let location = NSPoint(x: windowPoint.x + (endPoint.x - windowPoint.x) * t, y: windowPoint.y + (endPoint.y - windowPoint.y) * t)
                NSApp.postEvent(event(.leftMouseDragged, location), atStart: false)
            }
        }
        NSApp.postEvent(event(.leftMouseUp, endPoint), atStart: false)
        textView.mouseDown(with: event(.leftMouseDown, windowPoint))
        // A click the editor handled itself (a checkbox, a link) leaves the release in the queue.
        while NSApp.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantPast, inMode: .default, dequeue: true) != nil {}
        settle(0)
    }

    // MARK: - Looking

    /// Whether the character is drawn (not hidden Markdown, not an object in its place).
    func isVisible(_ index: Int) -> Bool {
        let layout = editor.layoutManager
        let glyph = layout.glyphIndexForCharacter(at: index)
        return layout.propertyForGlyph(at: glyph) != .controlCharacter
    }

    func visibleText(in range: NSRange? = nil) -> String {
        let ns = text as NSString
        let range = range ?? NSRange(location: 0, length: ns.length)
        var result = ""
        for index in range.location..<range.upperBound where isVisible(index) {
            result += ns.substring(with: NSRange(location: index, length: 1))
        }
        return result
    }

    func range(of string: String) -> NSRange {
        (text as NSString).range(of: string)
    }

    func object(at index: Int) -> EditorObject? {
        editor.layoutManager.object(at: index)
    }

    /// Where the page is scrolled to.
    var scrollTop: CGFloat { scrollView.contentView.bounds.minY }

    func scroll(to y: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settle(0)
    }

    /// How far down the window a character is, which scrolling changes.
    func screenY(of index: Int) -> CGFloat {
        editor.screenY(editor.yPosition(of: index))
    }

    /// The text view drawn into a PNG, for looking at, when `EDITOR_SNAPSHOTS` names a folder.
    @discardableResult
    func snapshot(_ name: String) -> URL? {
        guard let directory = ProcessInfo.processInfo.environment["EDITOR_SNAPSHOTS"] else { return nil }
        settle(0.3)
        let view = textView
        // On the page's colour, as in the app.
        view.drawsBackground = true
        view.backgroundColor = EditorTheme.panel
        defer { view.drawsBackground = false }
        let rect = NSRect(x: 0, y: 0, width: view.bounds.width, height: min(view.frame.height, 4000))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        return url
    }
}

/// Runs the main run loop until the condition holds, or for at most `timeout`.
@MainActor
@discardableResult
func settleRunLoop(until condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
#endif
