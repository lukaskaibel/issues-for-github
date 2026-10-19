#if os(macOS)
import AppKit
import Testing
@testable import GitIssuesKit

/// The Mac's description editor with real keystrokes: the typing rules reach the text view, make one undoable edit
/// each, and keep the text styled.
@MainActor
@Suite("Typing in the Mac's description editor")
struct MarkdownTextViewTests {
    let window: NSWindow
    let view: MarkdownTextView

    init() {
        _ = NSApplication.shared
        view = MarkdownTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.allowsUndo = true
        view.setUpStyling()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .titled, backing: .buffered, defer: true)
        window.contentView = view
        window.makeFirstResponder(view)
    }

    func type(_ text: String) {
        for character in text {
            if character == "\n" {
                view.insertNewline(nil)
            } else {
                view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    func press(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command, keyCode: UInt16 = 0) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                     context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode)!
        return view.performKeyEquivalent(with: event)
    }

    @Test func aDashStartsAListThatReturnContinuesAndEnds() {
        type("-one\ntwo\n\nafter")
        #expect(view.string == "- one\n- two\nafter")
    }

    @Test func commandBTurnsBoldOnAndOff() {
        type("a ")
        #expect(press("b"))
        type("bold")
        #expect(view.string == "a **bold**")
        #expect(press("b"))
        type(" b")
        #expect(view.string == "a **bold** b")
    }

    @Test func boldThickensAndAlwaysGetsThere() {
        type("some words")
        view.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(press("b"))
        #expect(view.string == "some **words**")
        // It starts from how the text looked...
        #expect(weight(at: 8) == 400)
        // ...and ends bold, even where the screen doesn't draw (as here), when no frame comes.
        let start = Date()
        while weight(at: 8) < 590, Date().timeIntervalSince(start) < 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(weight(at: 8) == 590)
    }

    func weight(at index: Int) -> Double {
        let font = view.textStorage!.attribute(.font, at: index, effectiveRange: nil) as! NSFont
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
        return variation?[NSNumber(value: 0x7767_6874)]?.doubleValue ?? 400
    }

    @Test func deletingBehindBoldKeepsTheMarks() {
        type("**bold**")
        view.deleteBackward(nil)
        #expect(view.string == "**bol**")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.deleteBackward(nil)
        #expect(view.string == "bol")
    }

    @Test func eachRuleIsOneUndoStep() {
        type("word")
        // The undo manager closes a group at the end of each turn of the run loop, as after each key press.
        RunLoop.current.run(until: Date())
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(press("b"))
        #expect(view.string == "**word**")
        RunLoop.current.run(until: Date())
        view.undoManager?.undo()
        #expect(view.string == "word")
    }

    @Test func tabMovesAListItemIn() {
        type("- one\ntwo")
        view.insertTab(nil)
        #expect(view.string == "- one\n  - two")
        view.insertBacktab(nil)
        #expect(view.string == "- one\n- two")
    }

    @Test func listShortcutsGoByTheirKey() {
        type("item")
        #expect(press("*", [.command, .shift], keyCode: 28))
        #expect(view.string == "- item")
        #expect(press("(", [.command, .shift], keyCode: 25))
        #expect(view.string == "- [ ] item")
    }

    @Test func everyLineIsTheSameHeight() {
        type("plain\n**bold** and `code`\n\n😀\nend")
        let layout = view.layoutManager!
        layout.ensureLayout(for: view.textContainer!)
        var heights: [CGFloat] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, _, _ in
            heights.append(rect.height)
        }
        // The last line has no spacing after it.
        #expect(Set(heights.dropLast()).count == 1)
    }
}

#endif
