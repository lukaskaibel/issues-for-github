#if os(macOS)
import AppKit
import XCTest
@testable import GitIssuesKit

/// Going between the title and the text with the keys, the marks of styles with a keyboard and on a touch keyboard,
/// marks folding in and out as the caret comes and goes, and typing headings and bold, as in Notebook.
@MainActor
final class TitleAndMarksTests: XCTestCase {
    private var all: (EditorHarness) -> NSRange = { NSRange(location: 0, length: ($0.text as NSString).length) }

    // MARK: - The title above the text

    /// An editor under a title, and how often its keys went back to the title.
    private func underATitle(_ text: String) -> (EditorHarness, () -> Int) {
        let h = EditorHarness(text)
        var count = 0
        h.editor.onBackToTitle = { count += 1 }
        return (h, { count })
    }

    func testUpLeftAndDeleteAtTheStartOfTheTextGoToTheTitle() {
        for selector in [#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.deleteBackward(_:))] {
            let (h, wentBack) = underATitle("Body")
            h.caret(0)
            h.command(selector)
            XCTAssertEqual(wentBack(), 1, "\(selector) goes to the title")
            XCTAssertEqual(h.text, "Body", "nothing is deleted")
        }
    }

    func testUpAnywhereOnTheFirstLineGoesToTheTitle() {
        let (h, wentBack) = underATitle("Body\nMore")
        h.caret(2)
        h.command(#selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(wentBack(), 1)
    }

    func testUpFurtherDownAndLeftFurtherInStayInTheText() {
        let (h, wentBack) = underATitle("Body\nMore")
        h.caret(h.range(of: "More").location + 1)
        h.command(#selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(wentBack(), 0)
        XCTAssertEqual(h.selection.location, 1, "up a line")
        h.command(#selector(NSResponder.moveLeft(_:)))
        XCTAssertEqual(wentBack(), 0)
        XCTAssertEqual(h.selection.location, 0)
    }

    func testDeleteHeldDownStopsAtTheStartOfTheText() {
        let (h, wentBack) = underATitle("Body")
        h.caret(1)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(wentBack(), 0, "a Delete right after one that reached the start, as when it is held, stays")
        XCTAssertEqual(h.text, "ody")
        h.settle(0.6)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(wentBack(), 1, "pressed again, it goes to the title")
        XCTAssertEqual(h.text, "ody")
    }

    func testWithoutATitleTheKeysStayInTheText() {
        let h = EditorHarness("Body")
        h.caret(0)
        h.command(#selector(NSResponder.moveUp(_:)))
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.selection, NSRange(location: 0, length: 0))
        XCTAssertEqual(h.text, "Body")
        XCTAssertTrue(h.editor.isFocused)
    }

    func testTheTitleLinkGoesBothWays() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let link = TitleLink()
        var enteredTitle = 0
        link.enterTitle = { enteredTitle += 1 }
        let coordinator = MarkdownEditorCoordinator(configuration: MarkdownEditor(text: "Body\nMore", onSave: { _ in }, titleLink: link), checkboxes: MarkdownCheckboxes())
        let view = coordinator.editor.textView
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        window.contentView?.addSubview(view)
        window.makeFirstResponder(nil)
        view.setSelectedRange(NSRange(location: 7, length: 0))

        link.enterText()
        XCTAssertTrue(coordinator.editor.isFocused, "Tab, ↓ or → at the end of the title go into the text")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0), "at its start")
        view.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(enteredTitle, 1, "and ↑ goes back")

        let readOnly = MarkdownEditorCoordinator(configuration: MarkdownEditor(text: "Body", isEditable: false, titleLink: TitleLink()), checkboxes: MarkdownCheckboxes())
        XCTAssertNil(readOnly.editor.onBackToTitle, "text that is only read isn't gone into")
    }

    func testTabDownOnTheLastLineAndRightAtTheEndLeaveATitle() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let field = NSTextField(wrappingLabelWithString: "A title long enough to wrap onto a second line")
        field.isEditable = true
        field.frame = NSRect(x: 0, y: 0, width: 140, height: 80)
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let length = (editor.string as NSString).length
        let link = TitleLink()
        link.titleView = field

        editor.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertFalse(TitleCaret.leaves(by: .downArrow, of: link), "on the first line ↓ goes down the title")
        XCTAssertFalse(TitleCaret.leaves(by: .rightArrow, of: link))
        XCTAssertTrue(TitleCaret.leaves(by: .tab, of: link), "Tab goes on from anywhere")
        editor.setSelectedRange(NSRange(location: length - 2, length: 0))
        XCTAssertTrue(TitleCaret.leaves(by: .downArrow, of: link), "on its last line ↓ goes on to the text")
        XCTAssertFalse(TitleCaret.leaves(by: .rightArrow, of: link), "→ only at the very end")
        editor.setSelectedRange(NSRange(location: length, length: 0))
        XCTAssertTrue(TitleCaret.leaves(by: .rightArrow, of: link))
        editor.setSelectedRange(NSRange(location: length - 3, length: 3))
        XCTAssertFalse(TitleCaret.leaves(by: .downArrow, of: link), "not with words selected")
        XCTAssertFalse(TitleCaret.leaves(by: .rightArrow, of: link))
    }

    // MARK: - Marks with a keyboard and on a touch keyboard

    func testWithAKeyboardTheStarsOfBoldShowNextToTheCaret() {
        let h = EditorHarness("Some **bold** text")
        h.caret(h.range(of: "bold").location + 2)
        XCTAssertEqual(h.visibleText(in: all(h)), "Some **bold** text")
    }

    func testOnATouchKeyboardTheStarsStayHidden() {
        let h = EditorHarness("Some **bold** text")
        h.editor.marksShowOverride = false
        h.caret(h.range(of: "bold").location + 2)
        XCTAssertEqual(h.visibleText(in: all(h)), "Some bold text")
    }

    func testOnATouchKeyboardATapAtTheEndOfBoldTypesOnInBold() {
        let h = EditorHarness("Some **bold** text")
        h.editor.marksShowOverride = false
        h.caret(h.range(of: "**bold**").upperBound)
        XCTAssertEqual(h.selection.location, h.range(of: "bold").upperBound, "in front of the closing stars, which don't show")
        h.type("er")
        XCTAssertEqual(h.text, "Some **bolder** text")
    }

    func testOnATouchKeyboardATapAtTheStartOfBoldTypesOnPlainly() {
        let h = EditorHarness("Some **bold** text")
        h.editor.marksShowOverride = false
        h.caret(h.range(of: "bold").location)
        XCTAssertEqual(h.selection.location, h.range(of: "**bold").location, "in front of the opening stars")
        h.caret(0)
        h.caret(h.range(of: "**bold").location + 1)
        XCTAssertEqual(h.selection.location, h.range(of: "**bold").location, "never between them")
    }

    func testOnATouchKeyboardAStepIntoHiddenMarksGoesPastThem() {
        let h = EditorHarness("Some **bold** text")
        h.editor.marksShowOverride = false
        let opening = h.range(of: "**bold").location
        h.caret(opening)
        h.command(#selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(h.selection.location, opening + 2, "past both stars at once")
        h.command(#selector(NSResponder.moveLeft(_:)))
        XCTAssertEqual(h.selection.location, opening, "and back")
    }

    func testOnATouchKeyboardDeleteTakesTheLetterYouSeeAndKeepsTheStyle() {
        let h = EditorHarness("Some **bold** text")
        // Right behind the stars, where leaving the bold puts the caret.
        h.caret(h.range(of: "**bold**").upperBound)
        h.editor.marksShowOverride = false
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "Some **bol** text")
        XCTAssertEqual(h.selection.location, h.range(of: "bol").upperBound, "in the bold")
        h.type("t")
        XCTAssertEqual(h.text, "Some **bolt** text", "what you type next is bold too")
    }

    func testOnATouchKeyboardForwardDeleteTakesTheLetterBehindTheMarks() {
        let h = EditorHarness("Some **bold** text")
        h.caret(h.range(of: "**bold").location)
        h.editor.marksShowOverride = false
        h.command(#selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(h.text, "Some **old** text")
    }

    func testOnATouchKeyboardDeletingTheLastLetterTakesTheStyle() {
        let h = EditorHarness("a **b** c")
        h.caret(h.range(of: "**b**").upperBound)
        h.editor.marksShowOverride = false
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "a  c")
        XCTAssertEqual(h.selection, NSRange(location: 2, length: 0))
    }

    func testWithAKeyboardDeleteBehindBoldTakesItsLastLetterAsBefore() {
        let h = EditorHarness("Some **bold** text")
        h.caret(h.range(of: "**bold**").upperBound)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "Some **bol** text")
        XCTAssertEqual(h.selection.location, h.range(of: "**bol**").upperBound, "behind the stars, which show")
    }

    // MARK: - Folding

    func testMarksFoldInAndOutInsteadOfPopping() throws {
        let h = EditorHarness("Some **bold** text and more")
        let animator = h.editor.revealAnimator
        animator.isForced = true
        defer { animator.isForced = nil }
        let stars = h.range(of: "**")
        let after = h.range(of: "bold").location

        h.caret(after + 2)
        XCTAssertTrue(h.isVisible(stars.location), "the stars are there at once")
        let start = try XCTUnwrap(h.editor.storage.attribute(.expansion, at: stars.location, effectiveRange: nil) as? CGFloat)
        XCTAssertLessThan(exp(start), 0.05, "but squeezed to nothing")
        animator.advance(to: 0.5)
        let half = try XCTUnwrap(h.editor.storage.attribute(.expansion, at: stars.location, effectiveRange: nil) as? CGFloat)
        XCTAssertGreaterThan(exp(half), 0.5, "half way they take most of their room")
        XCTAssertLessThan(exp(half), 1)
        animator.advance(to: 1)
        XCTAssertNil(h.editor.storage.attribute(.expansion, at: stars.location, effectiveRange: nil), "then they are plain text")
        XCTAssertNil(h.editor.storage.attribute(.markdownFade, at: stars.location, effectiveRange: nil))

        h.caret(h.range(of: "more").location)
        h.settle(0)
        XCTAssertTrue(h.isVisible(stars.location), "leaving, they stay while they fold away")
        XCTAssertTrue(h.editor.isRevealed(stars.location))
        animator.advance(to: 1)
        h.settle(0)
        XCTAssertFalse(h.isVisible(stars.location), "and are hidden at the end")
        XCTAssertNil(h.editor.storage.attribute(.expansion, at: stars.location, effectiveRange: nil))
    }

    func testTypingWhileMarksFoldKeepsThemFolding() {
        let h = EditorHarness("Some **bold**")
        let animator = h.editor.revealAnimator
        animator.isForced = true
        defer { animator.isForced = nil }
        h.caret((h.text as NSString).length)
        animator.complete()
        h.type(" and")
        XCTAssertTrue(animator.isRunning, "a space after the stars folds them away")
        XCTAssertNotNil(h.editor.storage.attribute(.expansion, at: h.range(of: "**").location, effectiveRange: nil), "still folding after more letters")
        animator.complete()
        h.settle(0)
        XCTAssertEqual(h.visibleText(in: all(h)), "Some bold and")
    }

    func testMarksDontFoldOffScreen() {
        let h = EditorHarness("Some **bold** text")
        XCTAssertFalse(h.editor.revealAnimator.isEnabled, "a window that isn't on screen shows and hides marks at once")
        h.caret(h.range(of: "bold").location + 1)
        XCTAssertFalse(h.editor.revealAnimator.isRunning)
        XCTAssertNil(h.editor.storage.attribute(.expansion, at: h.range(of: "**").location, effectiveRange: nil))
    }

    // MARK: - Headings

    private let note = "Intro line\n## Packing\nSome text."

    func testOnATouchKeyboardHeadingMarksShowOnlyWhileTheyAreTyped() {
        let h = EditorHarness(note)
        h.editor.marksShowOverride = false
        let marker = h.range(of: "## ")
        h.caret(h.range(of: "Packing").location + 3)
        XCTAssertFalse(h.isVisible(marker.location), "a heading picked or tapped into keeps its #s hidden")

        h.caret(h.range(of: "Intro line").upperBound)
        h.type("\n### Next")
        let typed = h.range(of: "### ")
        XCTAssertTrue(h.isVisible(typed.location), "#s typed show, so you see which heading you typed")
        h.type("\n")
        XCTAssertFalse(h.isVisible(typed.location), "until the caret leaves the line")
    }

    func testOnATouchKeyboardTheCaretStaysOutOfHiddenHeadingMarks() {
        let h = EditorHarness(note)
        h.editor.marksShowOverride = false
        h.caret(h.range(of: "## ").location + 1)
        XCTAssertEqual(h.selection.location, h.range(of: "Packing").location, "after the #s you can't see")
    }

    func testWithAKeyboardTheHeadingMarksShowOnItsLine() {
        let h = EditorHarness(note)
        let marker = h.range(of: "## ")
        h.caret(h.range(of: "Packing").location + 3)
        XCTAssertTrue(h.isVisible(marker.location))
        h.caret(0)
        XCTAssertFalse(h.isVisible(marker.location))
        // → from the end of the line above lands in front of the #s that show once the caret is there.
        h.caret(h.range(of: "Intro line").upperBound)
        h.command(#selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(h.selection.location, marker.location)
    }

    func testTextTypedAfterTwoHashesGetsItsSpace() {
        let h = EditorHarness("")
        h.type("##Title\n###Sub\n#12")
        XCTAssertEqual(h.text, "## Title\n### Sub\n#12", "two or more #s only ever start a heading; one may be an issue's number")
    }

    func testHashesTypedInFrontOfALineMakeItAHeading() {
        let h = EditorHarness("Groceries")
        h.caret(0)
        h.type("##")
        XCTAssertEqual(h.text, "## Groceries")
        h.type(" ")
        XCTAssertEqual(h.text, "## Groceries", "a space there steps over the heading's own")
        XCTAssertEqual(h.selection.location, 3)
    }

    func testReturnOnAHeadingWithoutTextTakesTheHeadingOff() {
        let h = EditorHarness("Intro\n## ")
        h.caret((h.text as NSString).length)
        h.type("\n")
        XCTAssertEqual(h.text, "Intro\n")
        XCTAssertEqual(h.selection, NSRange(location: 6, length: 0))
    }

    func testReturnAtTheStartOfAHeadingPutsALineAboveIt() {
        let h = EditorHarness(note)
        let heading = h.range(of: "Packing")
        h.caret(heading.location)
        h.type("\n")
        XCTAssertEqual(h.text, "Intro line\n\n## Packing\nSome text.")
        XCTAssertEqual(h.selection, NSRange(location: heading.location + 1, length: 0), "the caret stays at the heading's text")
    }

    func testReturnAfterAHeadingAtTheEndKeepsThePageStill() {
        let lines = (1...60).map { "Line \($0)" }.joined(separator: "\n")
        let h = EditorHarness(lines + "\n## Heading", height: 400)
        let end = (h.text as NSString).length
        h.caret(end)
        h.scroll(to: max(0, h.editor.yPosition(of: end) - 200))
        let top = h.scrollTop
        h.type("\n")
        h.settle(0.1)
        XCTAssertEqual(h.text, lines + "\n## Heading\n")
        XCTAssertEqual(h.scrollTop, top, accuracy: 0.5, "the page doesn't scroll by a line")
    }

    // MARK: - Bold typed with its stars

    func testTypingBoldWithItsStarsLeavesTheCaretAfterIt() {
        let h = EditorHarness("")
        h.type("Buy **")
        XCTAssertEqual(h.text, "Buy ****", "the closing pair comes along")
        XCTAssertEqual(h.selection.location, 6, "with the caret between")
        h.type("milk** today")
        XCTAssertEqual(h.text, "Buy **milk** today", "the closing stars typed are stepped over")
    }

    func testBoldStartedAtTheStartOfALineIsNoRuleAndNothingMoves() {
        let h = EditorHarness("Intro\n")
        h.caret(6)
        h.type("**")
        XCTAssertEqual(h.text, "Intro\n****")
        XCTAssertEqual(h.editor.document.lines[1].kind, .paragraph, "the empty pair is not a rule while typing")
        let y = h.editor.yPosition(of: 6)
        h.type("b")
        XCTAssertEqual(h.editor.yPosition(of: 6), y, "the line stays where it is when its text comes")
        XCTAssertEqual(MarkdownParser.parse("Intro\n****").lines[1].kind, .thematicBreak, "read, four stars are still a rule")
    }

    func testStarsWithSpacesStayStars() {
        let h = EditorHarness("")
        h.type("2 ** 3")
        XCTAssertEqual(h.text, "2 ** 3")
    }
}
#endif
