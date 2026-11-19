import XCTest

/// A card dropped onto the middle of another card on the iPhone's and iPad's board becomes that issue's sub-issue;
/// dropped onto a card's top or bottom edge, it only moves there, as before.
final class DropOntoIssueTests: AppTestCase {
    /// The project's board, on the iPhone turned to `column`; it opens on In Progress.
    private func openBoard(column: String = "Todo") {
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            launch()
            openPadProject("Git Issues")
        } else {
            launch()
            openProjectTab("Git Issues")
            if column != "In Progress" {
                let strip = element("strip-\(column)")
                wait(strip)
                strip.tap()
                waitUntil(strip.isSelected, "\(column) is the column on screen")
            }
        }
    }

    /// Touches and holds `card` until it lifts, drags it slowly to the point `dy` (0 top, 1 bottom) down `target`, holds
    /// it there, and lets go. Moving slowly and resting lets the drag take over from the card's menu before the finger
    /// arrives, as in PadTests.testDragCardToAnotherColumn. The targets are above or beside the card: a touch dragged
    /// straight down slides over the card's menu, which opens under it, and never lifts the card.
    private func drag(_ card: XCUIElement, onto target: XCUIElement, at dy: CGFloat = 0.5) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.8)
    }

    /// Whether `card` hangs in under `parent`, below it and indented.
    private func hangs(_ card: XCUIElement, under parent: XCUIElement) -> Bool {
        card.frame.minX > parent.frame.minX + 8 && card.frame.minY > parent.frame.maxY
    }

    private func notice(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// The page of #9, whose sub-issues are, in order, #13, #28, #10, #11, #12 and #23.
    private func openSubIssues() {
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            launch()
            openPadProject("Git Issues")
            element("card-#9").tap()
        } else {
            launch()
            element("row-#9").tap()
        }
        wait(element("issue-title"))
    }

    func testASubIssueDroppedOntoAnotherOneGoesUnderItAndUndoTakesItBack() {
        openSubIssues()
        // From the last row: the row's menu opens under the finger, and the drag takes over from it only after the
        // finger has come some way, more than the one row from #28 on the iPad.
        let (child, parent) = (element("sub-#23"), element("sub-#13"))
        scrollTo(child)
        wait(parent)
        drag(child, onto: parent)
        wait(notice("1 issue made a sub-issue of #13"), 15)
        snapshot("Sub-issue dropped onto another one")
        // It hangs under #13 now, which is folded; it is done, as one of #13's two was.
        waitGone(child)
        waitForLabel(parent, containing: "2 of 3 sub-issues done")
        element("notice-undo").tap()
        wait(child)
        waitForLabel(parent, containing: "1 of 2 sub-issues done")
    }

    func testPickedSubIssuesDroppedOntoAnotherOneGoUnderItTogether() {
        openSubIssues()
        let options = element("sub-options")
        scrollTo(options)
        options.tap()
        wait(button("Select"))
        button("Select").tap()
        wait(element("sub-pick-done"))
        let (first, second, parent) = (element("sub-#10"), element("sub-#11"), element("sub-#28"))
        scrollTo(second)
        first.tap()
        second.tap()
        wait(labelled("2 selected"))
        drag(second, onto: parent)
        wait(notice("2 issues made sub-issues of #28"), 15)
        snapshot("Picked sub-issues dropped onto another one")
        waitGone(first)
        waitGone(second)
    }

    func testACardDroppedOntoAnotherCardBecomesItsSubIssueAndUndoTakesItBack() {
        openBoard()
        // Both stand on their own, in Todo, #17 above #25.
        let (child, parent) = (element("card-#25"), element("card-#17"))
        wait(child)
        wait(parent)
        XCTAssertEqual(child.frame.minX, parent.frame.minX, accuracy: 1)
        drag(child, onto: parent)
        wait(notice("1 issue made a sub-issue of #17"), 15)
        snapshot("Dropped onto a card")
        waitForLabel(child, containing: "Sub-issue of #17")
        XCTAssertTrue(hangs(child, under: parent), "The card hangs under its new parent")
        element("notice-undo").tap()
        waitUntil(!child.label.contains("Sub-issue of"), "Undo took the parent back")
        XCTAssertEqual(child.frame.minX, parent.frame.minX, accuracy: 1)
    }

    func testACardDroppedOntoAnotherCardsEdgeOnlyMovesThere() {
        openBoard()
        let (child, other) = (element("card-#25"), element("card-#17"))
        wait(child)
        wait(other)
        XCTAssertGreaterThan(child.frame.minY, other.frame.minY)
        // The top edge of the other card: the card goes above it, standing on its own.
        drag(child, onto: other, at: 0.08)
        waitUntil(child.frame.maxY < other.frame.minY, "The card moved above the other one")
        XCTAssertEqual(child.frame.minX, other.frame.minX, accuracy: 1)
        XCTAssertFalse(child.label.contains("Sub-issue of"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'made a sub-issue of'")).firstMatch.exists)
    }

    func testAParentCantBeDroppedOntoItsOwnSubIssue() throws {
        // A sub-issue hangs below its parent, and a touch dragged down slides over the card's menu; the iPad's pointer
        // lifts the card without its menu.
        try XCTSkipUnless(isPad, "Needs the iPad's pointer")
        openBoard(column: "In Progress")
        // #9 is in In Progress, with #13 hanging under it.
        let parent = element("card-#9")
        let child = element("card-#13")
        wait(parent)
        wait(child)
        parent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.6, thenDragTo: child.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.8)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'made a sub-issue of'")).firstMatch.exists)
        XCTAssertFalse(parent.label.contains("Sub-issue of"))
        XCTAssertTrue(hangs(child, under: parent), "#13 still hangs under #9")
    }

    func testACardDroppedOntoACardInAnotherColumnKeepsItsStatus() throws {
        try XCTSkipUnless(isPad, "Only the iPad shows two columns at once")
        openBoard()
        let child = element("card-#17")
        let parent = element("card-#7")
        let neighbour = element("card-#25")
        wait(child)
        wait(parent)
        drag(child, onto: parent)
        wait(notice("1 issue made a sub-issue of #7"), 15)
        waitForLabel(child, containing: "Sub-issue of #7")
        // Back in Todo, beside the cards it stood with.
        XCTAssertEqual(child.frame.minX, neighbour.frame.minX, accuracy: 1)
    }

    private func waitUntil(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 6), .completed, message, file: file, line: line)
    }
}
