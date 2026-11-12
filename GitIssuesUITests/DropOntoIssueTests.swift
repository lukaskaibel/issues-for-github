import XCTest

/// A card dropped onto the middle of another card on the iPhone's and iPad's board becomes that issue's sub-issue;
/// dropped onto a card's top or bottom edge, it only moves there, as before.
final class DropOntoIssueTests: AppTestCase {
    private func openBoard() {
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            launch()
            openPadProject("Git Issues")
        } else {
            launch()
            openProjectTab("Git Issues")
        }
    }

    /// Touches and holds `card` until it lifts, drags it slowly to the point `dy` (0 top, 1 bottom) down `target`, holds
    /// it there, and lets go. Moving slowly and resting lets the drag take over from the card's menu before the finger
    /// arrives, as in PadTests.testDragCardToAnotherColumn.
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

    func testACardDroppedOntoAnotherCardBecomesItsSubIssueAndUndoTakesItBack() {
        openBoard()
        // Both stand on their own, in the same column (Todo on the iPad; In Progress on the iPhone, where it opens).
        let (child, parent) = isPad ? (element("card-#17"), element("card-#25")) : (element("card-#7"), element("card-#15"))
        wait(child)
        wait(parent)
        XCTAssertEqual(child.frame.minX, parent.frame.minX, accuracy: 1)
        drag(child, onto: parent)
        wait(notice(isPad ? "#17 is now a sub-issue of #25" : "#7 is now a sub-issue of #15"))
        snapshot("Dropped onto a card")
        waitForLabel(child, containing: isPad ? "Sub-issue of #25" : "Sub-issue of #15")
        XCTAssertTrue(hangs(child, under: parent), "The card hangs under its new parent")
        element("notice-undo").tap()
        waitUntil(!child.label.contains("Sub-issue of"), "Undo took the parent back")
        XCTAssertEqual(child.frame.minX, parent.frame.minX, accuracy: 1)
    }

    func testACardDroppedOntoAnotherCardsEdgeOnlyMovesThere() {
        openBoard()
        let (child, other) = isPad ? (element("card-#17"), element("card-#25")) : (element("card-#7"), element("card-#15"))
        wait(child)
        wait(other)
        XCTAssertLessThan(child.frame.minY, other.frame.minY)
        // The bottom edge of the other card: the card goes below it, standing on its own.
        drag(child, onto: other, at: 0.92)
        waitUntil(child.frame.minY > other.frame.maxY, "The card moved below the other one")
        XCTAssertEqual(child.frame.minX, other.frame.minX, accuracy: 1)
        XCTAssertFalse(child.label.contains("Sub-issue of"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is now a sub-issue of'")).firstMatch.exists)
    }

    func testAParentCantBeDroppedOntoItsOwnSubIssue() {
        openBoard()
        // #9 is in In Progress, with #13 hanging under it.
        let parent = element("card-#9")
        let child = element("card-#13")
        wait(parent)
        wait(child)
        drag(parent, onto: child)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is now a sub-issue of'")).firstMatch.exists)
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
        wait(notice("#17 is now a sub-issue of #7"))
        waitForLabel(child, containing: "Sub-issue of #7")
        // Back in Todo, beside the cards it stood with.
        XCTAssertEqual(child.frame.minX, neighbour.frame.minX, accuracy: 1)
    }

    private func waitUntil(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 6), .completed, message, file: file, line: line)
    }
}
