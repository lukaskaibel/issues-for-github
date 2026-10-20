#if os(macOS)
import AppKit
import XCTest
@testable import GitIssuesKit

/// How the Markdown editor behaves under a person's hands, as Notebook's does: what shows next to the caret, what a
/// selection takes, what Return, Backspace and Tab do, and that nothing moves while you select.
@MainActor
final class EditorBehaviorTests: XCTestCase {
    // MARK: - Always drawn, Markdown next to the caret

    func testMarkdownIsHiddenUntilTheCaretComes() {
        let h = EditorHarness("# Plan\n\nFive days in **October**, `code` and [GitHub](https://github.com).")
        h.caret(h.text.utf16.count)
        h.caret(0)
        XCTAssertFalse(h.isVisible(h.range(of: "**").location), "bold markers hide away from the caret")
        XCTAssertFalse(h.isVisible(h.range(of: "`").location))
        XCTAssertFalse(h.isVisible(h.range(of: "](https").location + 1), "a link's address never shows")
        XCTAssertEqual(h.visibleText(in: h.range(of: "Five days in **October**")), "Five days in October")
    }

    func testCaretRevealsSpanAndLeavingHidesIt() {
        let h = EditorHarness("Five days in **October** in Kyoto.")
        let bold = h.range(of: "October")
        h.caret(bold.location + 3)
        XCTAssertTrue(h.isVisible(bold.location - 1), "markers show while the caret is in the span")
        h.caret(h.range(of: "Kyoto").location)
        XCTAssertFalse(h.isVisible(bold.location - 1), "markers hide when the caret leaves")
    }

    func testHeadingMarksShowOnlyOnTheHeadingLine() {
        let h = EditorHarness("## Plan\nText")
        h.caret(h.range(of: "Text").location)
        XCTAssertFalse(h.isVisible(0))
        h.caret(h.range(of: "Plan").location + 1)
        XCTAssertTrue(h.isVisible(0))
    }

    func testSelectingDoesNotReveal() {
        let h = EditorHarness("Five days in **October** in Kyoto.")
        let bold = h.range(of: "October")
        h.caret(h.range(of: "Kyoto").location)
        h.select(NSRange(location: 0, length: bold.upperBound + 2))
        XCTAssertFalse(h.isVisible(bold.location - 1), "selecting over a span doesn't show its markers")
        XCTAssertTrue(h.editor.revealed.isEmpty)
    }

    func testDragSelectionKeepsLayoutStill() {
        let h = EditorHarness("Five days in **October** in Kyoto and more text after it.\nSecond line")
        let bold = h.range(of: "October")
        h.caret(bold.location + 2)
        XCTAssertTrue(h.isVisible(bold.location - 1))
        let kyoto = h.range(of: "Kyoto")
        let start = h.point(of: kyoto.location, fraction: 0.1)
        let end = h.point(of: kyoto.upperBound - 1, fraction: 0.9)
        let x = h.point(of: kyoto.location).x
        h.click(at: start, dragTo: end)
        XCTAssertEqual(h.selection, kyoto, "the drag selects what was under the pointer")
        XCTAssertEqual(h.point(of: kyoto.location).x, x, accuracy: 0.5, "nothing moves when the button comes up")
        h.click(at: h.point(of: h.range(of: "Second").location))
        XCTAssertFalse(h.isVisible(bold.location - 1), "a caret elsewhere hides the markers again")
    }

    func testClickPlacesCaretAndRevealsAfterMouseUp() {
        let h = EditorHarness("Five days in **October** in Kyoto.")
        let bold = h.range(of: "October")
        h.click(at: h.point(of: bold.location + 3, fraction: 0.0))
        XCTAssertEqual(h.selection, NSRange(location: bold.location + 3, length: 0))
        XCTAssertTrue(h.isVisible(bold.location - 1))
    }

    func testRevealDoesNotMoveOtherLines() {
        let h = EditorHarness("A short **bold** line.\nNext line\nThird")
        let next = h.range(of: "Third")
        let before = h.editor.yPosition(of: next.location)
        h.caret(h.range(of: "bold").location + 1)
        XCTAssertEqual(h.editor.yPosition(of: next.location), before, accuracy: 0.5)
    }

    func testNothingShowsWithoutTheFocus() {
        let h = EditorHarness("Five days in **October**.")
        h.caret(h.range(of: "October").location + 2)
        XCTAssertTrue(h.isVisible(h.range(of: "**").location))
        h.window.makeFirstResponder(nil)
        h.settle()
        XCTAssertFalse(h.isVisible(h.range(of: "**").location), "leaving the text draws it as GitHub does")
    }

    // MARK: - The caret

    private func caret(_ h: EditorHarness, at index: Int) -> (proposed: NSRect, drawn: NSRect) {
        h.caret(index)
        let glyph = h.editor.layoutManager.glyphIndexForCharacter(at: index)
        let line = h.editor.layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let proposed = NSRect(x: 100, y: h.textView.textContainerOrigin.y + line.minY, width: 1, height: line.height)
        return (proposed, h.editor.caretRect(proposed: proposed))
    }

    func testCaretStaysInItsLineAndSitsWhereTextDoes() {
        let h = EditorHarness("# Kick-off\n\nFive days in October.\n\nPlain paragraph.")
        let text = caret(h, at: h.range(of: "days").location)
        let places = [
            "end of a line": caret(h, at: h.range(of: "October.").upperBound),
            "empty line": caret(h, at: h.range(of: "October.").upperBound + 1),
            "empty line under a heading": caret(h, at: h.range(of: "Kick-off").upperBound + 1),
        ]
        for (place, caret) in places {
            // Blinking redraws only the proposed rectangle: any of the caret outside it would stay on screen.
            XCTAssertGreaterThanOrEqual(caret.drawn.minY, caret.proposed.minY, place)
            XCTAssertLessThanOrEqual(caret.drawn.maxY, caret.proposed.maxY, place)
            XCTAssertEqual(caret.drawn.minY - caret.proposed.minY, text.drawn.minY - text.proposed.minY, accuracy: 0.1, place)
            XCTAssertEqual(caret.drawn.height, text.drawn.height, accuracy: 0.1, place)
        }
    }

    // MARK: - Selections take things whole

    func testSelectingBoldTextTakesItsMarkers() {
        let h = EditorHarness("keep **this** word")
        let content = h.range(of: "this")
        h.select(content)
        XCTAssertEqual(h.selection, NSRange(location: content.location - 2, length: content.length + 4))
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "keep  word")
    }

    func testPartOfBoldKeepsMarkers() {
        let h = EditorHarness("keep **this** word")
        let content = h.range(of: "this")
        h.select(NSRange(location: content.location, length: 2))
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "keep **is** word")
    }

    func testCopyGivesMarkdown() {
        let h = EditorHarness("keep **this** word")
        h.select(h.range(of: "this"))
        h.textView.copy(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**this**")
    }

    func testPastingAnAddressOverTextLinksIt() {
        let h = EditorHarness("see the docs")
        h.select(h.range(of: "docs"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://docs.github.com", forType: .string)
        h.textView.paste(nil)
        XCTAssertEqual(h.text, "see the [docs](https://docs.github.com)")
    }

    // MARK: - Lists

    func testCaretStepsAroundBullets() {
        let h = EditorHarness("Intro\n- [ ] Task")
        let task = h.range(of: "Task")
        h.caret(h.range(of: "Intro").upperBound)
        h.command(#selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(h.selection.location, task.location, "right from the end of the line above lands in the item's text")
        h.command(#selector(NSResponder.moveLeft(_:)))
        XCTAssertEqual(h.selection.location, h.range(of: "Intro").upperBound, "left from the item's text goes back up")
    }

    func testReturnContinuesAndEndsLists() {
        let h = EditorHarness("- [x] Passport")
        h.caret(h.text.utf16.count)
        h.type("\nAdapter")
        XCTAssertEqual(h.text, "- [x] Passport\n- [ ] Adapter")
        h.type("\n")
        XCTAssertEqual(h.text, "- [x] Passport\n- [ ] Adapter\n- [ ] ")
        h.type("\n")
        XCTAssertEqual(h.text, "- [x] Passport\n- [ ] Adapter\n", "Return on an empty item ends the list")
    }

    func testNumberedListsCount() {
        let h = EditorHarness("1. First")
        h.caret(h.text.utf16.count)
        h.type("\nSecond\nThird")
        XCTAssertEqual(h.text, "1. First\n2. Second\n3. Third")
    }

    func testBackspaceAtItemStartRemovesBullet() {
        let h = EditorHarness("- Item")
        h.caret(h.range(of: "Item").location)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "Item")
    }

    func testTabNestsAndShiftTabUnnests() {
        let h = EditorHarness("- One\n- Two")
        h.caret(h.range(of: "Two").location + 1)
        h.command(#selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(h.text, "- One\n  - Two")
        XCTAssertEqual(h.selection.location, h.range(of: "Two").location + 1, "the caret stays in the text")
        h.command(#selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(h.text, "- One\n- Two")
    }

    func testCheckboxClickToggles() {
        let h = EditorHarness("- [ ] Task")
        let rect = h.editor.layoutManager.rect(forObjectAt: 2, origin: h.textView.textContainerOrigin)!
        h.click(at: NSPoint(x: rect.minX + 8, y: rect.midY))
        XCTAssertEqual(h.text, "- [x] Task")
        h.click(at: NSPoint(x: rect.minX + 8, y: rect.midY))
        XCTAssertEqual(h.text, "- [ ] Task")
    }

    func testTypingBracketsMakesTask() {
        let h = EditorHarness("")
        h.type("[] Buy milk")
        XCTAssertEqual(h.text, "- [ ] Buy milk")
    }

    func testReturnAfterAFenceClosesIt() {
        let h = EditorHarness("```swift")
        h.caret(h.text.utf16.count)
        h.type("\nlet x = 1")
        XCTAssertEqual(h.text, "```swift\nlet x = 1\n```")
    }

    // MARK: - Links and pictures

    func testClickOnLinkOpensIt() {
        let h = EditorHarness("see [GitHub](https://github.com) now and https://example.com")
        h.caret(0)
        h.click(at: h.point(of: h.range(of: "GitHub").location + 2))
        h.click(at: h.point(of: h.range(of: "example").location))
        XCTAssertEqual(h.opened.map(\.absoluteString), ["https://github.com", "https://example.com"])
    }

    func testLinkTextEditsLikeText() {
        let h = EditorHarness("see [GitHub](https://github.com) now")
        let link = h.range(of: "GitHub")
        h.caret(link.upperBound)
        h.command(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(h.text, "see [GitHu](https://github.com) now", "Backspace takes the text, never the address")
    }

    func testCommandLLinksTheSelectionAndAsksForTheAddress() {
        let h = EditorHarness("see the docs")
        h.select(h.range(of: "docs"))
        h.editor.insertLink()
        XCTAssertEqual(h.text, "see the [docs]()")
        // What Done in the popover does.
        h.editor.finishEditingLink(at: h.range(of: "[docs]").location, outcome: .save("https://docs.github.com"), isNew: true)
        XCTAssertEqual(h.text, "see the [docs](https://docs.github.com)")
        XCTAssertNotNil(h.object(at: h.range(of: "](https").location), "the address hides behind the pencil")
    }

    func testCommandLWithoutSelectionPutsInAWordToTypeOver() {
        let h = EditorHarness("see ")
        h.caret(4)
        h.editor.insertLink()
        let word = String(localized: .linkTextPlaceholder)
        XCTAssertEqual(h.text, "see [\(word)]()")
        h.editor.finishEditingLink(at: 4, outcome: .save("https://github.com"), isNew: true, selectsText: true)
        XCTAssertEqual(h.text, "see [\(word)](https://github.com)")
        XCTAssertEqual(h.selection, h.range(of: word), "the word is selected to type over")
        // Cancelled, a new link leaves nothing behind.
        let other = EditorHarness("see ")
        other.caret(4)
        other.editor.insertLink()
        other.editor.finishEditingLink(at: 4, outcome: .save(""), isNew: true, selectsText: true)
        XCTAssertEqual(other.text, "see ")
    }

    func testRemovingALinkKeepsItsText() {
        let h = EditorHarness("see [GitHub](https://github.com) now")
        h.editor.finishEditingLink(at: h.range(of: "[GitHub]").location, outcome: .remove, isNew: false)
        XCTAssertEqual(h.text, "see GitHub now")
    }

    func testPictureIsOneThing() {
        let h = EditorHarness("Before\n![shot](https://example.invalid/shot.png)\nAfter")
        let image = h.range(of: "![shot](https://example.invalid/shot.png)")
        XCTAssertNotNil(h.object(at: image.location), "a picture on a line of its own is drawn")
        h.select(NSRange(location: 2, length: image.location + 5 - 2))
        XCTAssertEqual(h.selection.upperBound, image.upperBound, "a selection takes it whole")
    }

    // MARK: - Blocks

    func testTableIsDrawnAndOpensAtTheClickedCell() {
        let h = EditorHarness("Intro\n\n| A | B |\n| --- | --- |\n| one | two |\n\nAfter")
        let table = h.range(of: "| A |")
        guard case .table? = h.object(at: table.location)?.kind else { return XCTFail("the table isn't drawn") }
        XCTAssertFalse(h.isVisible(h.range(of: "| one").location + 2), "its Markdown is hidden")
        let rect = h.editor.layoutManager.rect(forObjectAt: table.location, origin: h.textView.textContainerOrigin)!
        let model: TableModel
        if case .table(let found)? = h.object(at: table.location)?.kind { model = found } else { return }
        let layout = model.layout(maxWidth: rect.width)
        let top = h.editor.yPosition(of: table.location) + EditorStyle.objectParagraph().paragraphSpacingBefore
        // The second row, second column.
        h.click(at: NSPoint(x: rect.minX + layout.columnWidths[0] + 10, y: top + layout.rowHeights[0] + layout.rowHeights[1] / 2))
        XCTAssertNotNil(h.editor.activeBlock)
        XCTAssertEqual(h.selection.location, h.range(of: "two").upperBound)
        XCTAssertTrue(h.isVisible(h.range(of: "| one").location + 2), "open, it shows its Markdown")
        h.caret(h.range(of: "After").location)
        XCTAssertNil(h.editor.activeBlock, "and closes when the caret leaves")
    }

    func testATableTypedShowsItsSourceAfterTheCaretComesBack() {
        let h = EditorHarness("Steps")
        h.caret(h.text.utf16.count)
        h.type("\n\n| Key | Does |\n|---|---|\n| Up | Moves |")
        XCTAssertNotNil(h.editor.activeBlock, "the table being typed is open")
        XCTAssertEqual(h.visibleText(in: h.range(of: "| Up | Moves |")), "| Up | Moves |")
        h.type("\nmore")
        XCTAssertNil(h.editor.activeBlock)
        XCTAssertFalse(h.isVisible(h.range(of: "| Up").location + 2), "left, it is drawn")
        for _ in 0..<5 { h.command(#selector(NSResponder.deleteBackward(_:))) }
        XCTAssertNotNil(h.editor.activeBlock, "back in it, it is open again")
        XCTAssertEqual(h.visibleText(in: h.range(of: "| Up | Moves |")), "| Up | Moves |", "and its source shows")
        XCTAssertEqual(h.visibleText(in: h.range(of: "| Key | Does |")), "| Key | Does |")
    }

    func testABlockAtTheEndKeepsItsBoxAndRoom() {
        let ending = EditorHarness("Steps\n\n| Key | Does |\n|---|---|\n| Up | Moves |")
        let followed = EditorHarness("Steps\n\n| Key | Does |\n|---|---|\n| Up | Moves |\n")
        for h in [ending, followed] { h.caret(h.range(of: "Moves").location) }
        let box = { (h: EditorHarness) in h.editor.layoutManager.blockBox(at: h.range(of: "| Up").location, origin: .zero)?.height }
        XCTAssertEqual(box(ending), box(followed), "the box goes round the last row, at the end of the text too")
        XCTAssertGreaterThanOrEqual(ending.editor.contentHeight(forWidth: 600) + 1, followed.editor.contentHeight(forWidth: 600) - EditorStyle.lineHeight)
    }

    func testMathIsDrawnAndShowsItsSourceNextToTheCaret() {
        let h = EditorHarness("Area $\\pi r^2$ here\n\n$$\nE = mc^2\n$$")
        let inline = h.range(of: "$\\pi")
        guard case .mathInline? = h.object(at: inline.location)?.kind else { return XCTFail("inline maths isn't drawn") }
        guard case .mathBlock? = h.object(at: h.range(of: "$$").location)?.kind else { return XCTFail("display maths isn't drawn") }
        XCTAssertFalse(h.isVisible(inline.location))
        h.caret(inline.location + 2)
        XCTAssertTrue(h.isVisible(inline.location), "next to the caret it is its source")
    }

    func testAlertGetsItsTitle() {
        let h = EditorHarness("> [!WARNING]\n> Back up first.")
        h.caret(h.text.utf16.count)
        guard case .callout(let type, let label)? = h.object(at: h.range(of: "[!WARNING]").location)?.kind else { return XCTFail("no alert") }
        XCTAssertEqual(type, "warning")
        XCTAssertEqual(label, String(localized: .alertWarning))
        XCTAssertFalse(h.isVisible(h.range(of: "WARNING").location))
    }

    func testCodeBlockHidesItsFences() {
        let h = EditorHarness("Run:\n\n```swift\nlet x = 1\n```\n\nDone")
        h.caret(0)
        XCTAssertFalse(h.isVisible(h.range(of: "```swift").location))
        XCTAssertTrue(h.isVisible(h.range(of: "let").location))
        h.caret(h.range(of: "let").location)
        XCTAssertTrue(h.isVisible(h.range(of: "```swift").location), "inside, the fences show")
    }

    func testCommentsAreFaintToEditAndGoneToRead() {
        let text = "<!-- Describe the bug -->\nIt quits."
        let editing = EditorHarness(text)
        editing.caret(editing.text.utf16.count)
        XCTAssertEqual(editing.visibleText(in: editing.range(of: "<!-- Describe the bug -->")), " Describe the bug ")
        let reading = EditorHarness(text, editable: false)
        XCTAssertEqual(reading.visibleText(in: reading.range(of: "<!-- Describe the bug -->")), "")
        XCTAssertLessThan(reading.editor.contentHeight(forWidth: 600), editing.editor.contentHeight(forWidth: 600))
    }

    // MARK: - Formatting

    func testCommandBTogglesBold() {
        let h = EditorHarness("make this bold")
        h.select(h.range(of: "this"))
        h.textView.toggleBoldface(nil)
        XCTAssertEqual(h.text, "make **this** bold")
        h.textView.toggleBoldface(nil)
        XCTAssertEqual(h.text, "make this bold")
    }

    func testTypingMarkerWrapsSelection() {
        let h = EditorHarness("make this italic")
        h.select(h.range(of: "this"))
        h.type("*")
        XCTAssertEqual(h.text, "make *this* italic")
    }

    func testTheFormatShortcutsWorkWithoutTheMenu() {
        let h = EditorHarness("Groceries")
        func press(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: h.window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            )!
            return h.textView.performKeyEquivalent(with: event)
        }
        h.select(h.range(of: "Groceries"))
        XCTAssertTrue(press("b", 11, .command))
        XCTAssertEqual(h.text, "**Groceries**")
        XCTAssertTrue(press("b", 11, .command))
        XCTAssertTrue(press("L", 37, [.command, .shift]))
        XCTAssertEqual(h.text, "- [ ] Groceries", "⇧⌘L makes a task")
        XCTAssertTrue(press("U", 32, [.command, .shift]))
        XCTAssertEqual(h.text, "- [x] Groceries", "⇧⌘U ticks it")
        XCTAssertTrue(press("&", 26, [.command, .shift]))
        XCTAssertEqual(h.text, "- Groceries", "⇧⌘7, whatever Shift makes of the 7")
        XCTAssertTrue(press("]", 30, [.command, .option]))
        XCTAssertEqual(h.text, "  - Groceries", "⌥⌘] nests it")
        XCTAssertFalse(press("k", 40, .command), "other shortcuts go on to the menu")
        h.editor.isEditable = false
        XCTAssertFalse(press("b", 11, .command), "text that is only read isn't formatted")
    }

    func testBoldOverWholeLinesLeavesTheirPunctuationOutside() {
        let h = EditorHarness("- [ ] Milk\n- [x] Eggs\n\n## Later")
        h.select(NSRange(location: 0, length: h.text.utf16.count))
        h.textView.toggleBoldface(nil)
        XCTAssertEqual(h.text, "- [ ] **Milk**\n- [x] **Eggs**\n\n## **Later**")
        XCTAssertTrue(h.editor.nsText.substring(with: h.editor.selection).contains("Milk**\n- [x] **Eggs**\n\n## **Later"))
        h.textView.toggleBoldface(nil)
        XCTAssertEqual(h.text, "- [ ] Milk\n- [x] Eggs\n\n## Later", "and pressed again, it comes off every line")
        XCTAssertEqual(h.editor.nsText.substring(with: h.editor.selection), "Milk\n- [x] Eggs\n\n## Later")
    }

    func testBoldKeepsAnEmojiAtTheSelectionsEdgeWhole() {
        let h = EditorHarness("Party 🎉")
        h.select(NSRange(location: 0, length: h.text.utf16.count))
        h.textView.toggleBoldface(nil)
        XCTAssertEqual(h.text, "**Party 🎉**")
    }

    func testTypingAMarkerOverAWholeLineWrapsItsWords() {
        let h = EditorHarness("> Quoted words ")
        h.select(NSRange(location: 0, length: h.text.utf16.count))
        h.type("_")
        XCTAssertEqual(h.text, "> _Quoted words_ ")
        let cell = EditorHarness("| A | B |\n| --- | --- |\n| one | two |")
        cell.select(cell.range(of: "| one | two |"))
        cell.type("*")
        XCTAssertEqual(cell.text, "| A | B |\n| --- | --- |\n*", "across cells the marker is typed, as anywhere else")
    }

    func testLineFormats() {
        let h = EditorHarness("Groceries")
        h.caret(3)
        h.textView.makeHeading(nil)
        XCTAssertEqual(h.text, "## Groceries")
        h.textView.makeChecklist(nil)
        XCTAssertEqual(h.text, "- [ ] Groceries")
        h.textView.markChecked(nil)
        XCTAssertEqual(h.text, "- [x] Groceries")
        h.textView.makeBody(nil)
        XCTAssertEqual(h.text, "Groceries")
    }

    func testUndoAfterListContinuation() {
        let h = EditorHarness("- One")
        h.caret(5)
        h.type("\n")
        XCTAssertEqual(h.text, "- One\n- ")
        h.textView.undoManager?.undo()
        XCTAssertEqual(h.text, "- One")
    }

    // MARK: - Text that is only read

    func testReadOnlyTextOpensNothingAndShowsNoMarkdown() {
        let h = EditorHarness("Five **bold**\n\n| A |\n| - |\n| 1 |\n\n- [ ] Task\n\n[link](https://github.com)", editable: false)
        h.caret(h.range(of: "bold").location + 1)
        XCTAssertFalse(h.isVisible(h.range(of: "**").location))
        let table = h.range(of: "| A |")
        let rect = h.editor.layoutManager.rect(forObjectAt: table.location, origin: h.textView.textContainerOrigin)!
        h.click(at: NSPoint(x: rect.minX + 10, y: h.editor.yPosition(of: table.location) + 20))
        XCTAssertNil(h.editor.activeBlock)
        let box = h.editor.layoutManager.rect(forObjectAt: h.range(of: "[ ]").location, origin: h.textView.textContainerOrigin)!
        h.click(at: NSPoint(x: box.minX + 8, y: box.midY))
        XCTAssertEqual(h.text.contains("- [ ] Task"), true, "checkboxes don't tick")
        XCTAssertNil(h.object(at: h.range(of: "](https").location), "no pencil to edit the link")
        h.click(at: h.point(of: h.range(of: "link").location + 1))
        XCTAssertEqual(h.opened.map(\.absoluteString), ["https://github.com"], "links still open")
    }

    func testCheckboxesTickWhereAllowedThoughTheTextIsOnlyRead() {
        let h = EditorHarness("- [ ] Task", editable: false)
        h.editor.allowsChecking = true
        let box = h.editor.layoutManager.rect(forObjectAt: 2, origin: h.textView.textContainerOrigin)!
        h.click(at: NSPoint(x: box.minX + 8, y: box.midY))
        XCTAssertEqual(h.text, "- [x] Task")
        XCTAssertEqual(h.changes, 1)
    }

    // MARK: - In a page

    func testHeightFollowsTheText() {
        let h = EditorHarness("One line, long enough to wrap where the text is narrow")
        let one = h.editor.contentHeight(forWidth: 600)
        h.caret(h.text.utf16.count)
        h.type("\nTwo\nThree")
        XCTAssertGreaterThan(h.editor.contentHeight(forWidth: 600), one * 2.5)
        XCTAssertGreaterThan(h.editor.contentHeight(forWidth: 80), h.editor.contentHeight(forWidth: 600), "narrower, the text wraps")
    }

    func testReloadKeepsTheCaret() {
        let h = EditorHarness("Hello world")
        h.caret(h.range(of: "world").location)
        h.editor.reload(text: "Well, hello world")
        XCTAssertEqual(h.text, "Well, hello world")
        XCTAssertEqual(h.selection.location, h.range(of: "world").location)
        XCTAssertEqual(h.changes, 0, "text from GitHub isn't taken for typing")
    }

    func testTheCaretLineStaysPutWhenATableAboveCloses() {
        let rows = (1...12).map { "| row \($0) | value |" }.joined(separator: "\n")
        let h = EditorHarness("Intro\n\n| A | B |\n| --- | --- |\n\(rows)\n\n" + (1...40).map { "Line \($0)" }.joined(separator: "\n"), height: 300)
        // Open the table, scroll down to a line under it and put the caret there: the table closes above it.
        h.caret(h.range(of: "row 3").location)
        XCTAssertNotNil(h.editor.activeBlock)
        h.scroll(to: 200)
        let line = h.range(of: "Line 2\n")
        let before = h.screenY(of: line.location)
        h.caret(line.location)
        h.settle(until: { abs(h.screenY(of: line.location) - before) < 1 }, timeout: 2)
        XCTAssertNil(h.editor.activeBlock)
        XCTAssertEqual(h.screenY(of: line.location), before, accuracy: 1, "the page scrolled by what the table gave back")
    }

    func testTheCaretStaysClearOfWhatCoversThePageBottom() {
        let h = EditorHarness((1...12).map { "Line \($0)" }.joined(separator: "\n"), height: 300)
        // A comment field of 60 points over the foot of the page, as SwiftUI's safe area inset sets it.
        h.scrollView.automaticallyAdjustsContentInsets = false
        h.scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)
        h.caret(h.text.utf16.count)
        h.type("\nLine 13\nLine 14\nLine 15")
        let clip = h.scrollView.contentView
        let caret = { h.textView.convert(NSPoint(x: 0, y: h.editor.yPosition(of: h.text.utf16.count) + EditorStyle.lineHeight), to: clip).y }
        h.settle(until: { caret() <= clip.bounds.maxY - 60 })
        XCTAssertLessThanOrEqual(caret(), clip.bounds.maxY - 60, "the line typed on is above the comment field")
    }

    func testNoTabsInTextOutsideListsAndCode() {
        let h = EditorHarness("- One\n- Two\n\n```\ncode\n```")
        h.caret(h.range(of: "code").location)
        h.command(#selector(NSResponder.insertTab(_:)))
        XCTAssertTrue(h.text.contains("    code"), "Tab indents code by four spaces")
    }
}
#endif
