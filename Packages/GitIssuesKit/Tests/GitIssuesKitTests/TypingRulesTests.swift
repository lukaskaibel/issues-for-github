#if os(macOS)
import AppKit
import CoreText
import XCTest
@testable import GitIssuesKit

/// The typing rules of `MarkdownEditing` in the editor with real keystrokes: they reach the text view after the
/// editor's own rules, make one undoable edit each, and the text eases into its new look.
@MainActor
final class TypingRulesTests: XCTestCase {
    private func press(_ h: EditorHarness, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command, keyCode: UInt16) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: h.window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode
        )!
        let handled = h.textView.performKeyEquivalent(with: event)
        h.settle(0)
        return handled
    }

    private func weight(_ h: EditorHarness, at index: Int) -> Double {
        let font = h.editor.storage.attribute(.font, at: index, effectiveRange: nil) as! NSFont
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
        return variation?[NSNumber(value: 0x7767_6874)]?.doubleValue ?? 400
    }

    func testADashStartsAListThatReturnContinuesAndEnds() {
        let h = EditorHarness("")
        h.type("-one\ntwo\n\nafter")
        XCTAssertEqual(h.text, "- one\n- two\nafter")
    }

    func testADashAndBracketsMakeACheckbox() {
        let h = EditorHarness("")
        h.type("-[]todo")
        XCTAssertEqual(h.text, "- [ ] todo")
    }

    func testCommandBTurnsBoldOnAndOff() {
        let h = EditorHarness("")
        h.type("a ")
        XCTAssertTrue(press(h, "b", keyCode: 11))
        h.type("bold")
        XCTAssertEqual(h.text, "a **bold**")
        XCTAssertTrue(press(h, "b", keyCode: 11))
        h.type(" b")
        XCTAssertEqual(h.text, "a **bold** b")
    }

    func testCommandBAtACaretInAWordMakesTheWordBold() {
        let h = EditorHarness("some words")
        h.caret(7)
        XCTAssertTrue(press(h, "b", keyCode: 11))
        XCTAssertEqual(h.text, "some **words**")
    }

    func testBoldThickensAndAlwaysGetsThere() {
        let h = EditorHarness("some words")
        h.caret(7)
        XCTAssertTrue(press(h, "b", keyCode: 11))
        XCTAssertEqual(h.text, "some **words**")
        // It starts from how the text looked...
        XCTAssertEqual(weight(h, at: 8), 400)
        // ...and ends bold, even where the screen doesn't draw (as here), when no frame comes.
        h.settle(until: { weight(h, at: 8) >= 590 }, timeout: 1)
        XCTAssertEqual(weight(h, at: 8), 590)
    }

    func testDeletingBehindBoldKeepsTheMarks() {
        let h = EditorHarness("**bold**")
        h.caret(8)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "**bol**")
        h.caret(2)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "bol")
    }

    func testDeletingASelectionWithOneMarkTakesTheOther() {
        let h = EditorHarness("a **bold** b")
        h.select(NSRange(location: 0, length: 4))
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "bold b")
    }

    func testReturnAtTheEndOfBoldLeavesIt() {
        let h = EditorHarness("**bold**")
        h.caret(6)
        h.type("\nplain")
        XCTAssertEqual(h.text, "**bold**\nplain")
    }

    func testEachRuleIsOneUndoStep() {
        let h = EditorHarness("")
        h.type("word")
        // The undo manager closes a group at the end of each turn of the run loop, as after each key press.
        h.settle(0.01)
        h.caret(2)
        XCTAssertTrue(press(h, "b", keyCode: 11))
        XCTAssertEqual(h.text, "**word**")
        h.settle(0.01)
        h.textView.undoManager?.undo()
        XCTAssertEqual(h.text, "word")
    }

    func testTabMovesAListItemIn() {
        let h = EditorHarness("")
        h.type("- one\ntwo")
        h.command(#selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(h.text, "- one\n  - two")
        h.command(#selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(h.text, "- one\n- two")
    }

    func testListShortcutsAreThoseOfNotes() {
        let h = EditorHarness("item")
        h.caret(2)
        XCTAssertTrue(press(h, "&", [.command, .shift], keyCode: 26))
        XCTAssertEqual(h.text, "- item", "⇧⌘7 bullets")
        XCTAssertTrue(press(h, "L", [.command, .shift], keyCode: 37))
        XCTAssertEqual(h.text, "- [ ] item", "⇧⌘L a checklist")
        XCTAssertTrue(press(h, "(", [.command, .shift], keyCode: 25))
        XCTAssertEqual(h.text, "1. item", "⇧⌘9 numbers")
    }

    func testAnEmojiKeepsItsFontInStyledText() {
        let h = EditorHarness("")
        h.type("😀 **x**")
        let font = h.editor.storage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertTrue(font.fontName.contains("Emoji"), font.fontName)
    }

    func testASpaceTypedAtTheEndOfBoldKeepsItBoldWhileTyping() {
        let h = EditorHarness("a **bold**")
        h.caret(8)
        h.type(" ")
        XCTAssertEqual(h.text, "a **bold **")
        XCTAssertTrue(h.editor.document.lines[0].spans.contains { $0.kind == .strong }, "bold while typing")
        h.window.makeFirstResponder(nil)
        h.settle()
        XCTAssertFalse(h.editor.document.lines[0].spans.contains { $0.kind == .strong }, "read, it is what GitHub shows")
    }

    func testEveryLineIsTheSameHeight() {
        let h = EditorHarness("plain\n**bold** and `code`\n\n😀\nend")
        h.caret(0)
        let layout = h.editor.layoutManager
        layout.ensureLayout(for: h.editor.container)
        var heights: [CGFloat] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, _, _ in
            heights.append(rect.height)
        }
        // The last line has no spacing after it.
        XCTAssertEqual(Set(heights.dropLast()).count, 1, "\(heights)")
    }
}
#endif
