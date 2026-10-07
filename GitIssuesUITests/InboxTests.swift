import XCTest

/// The Inbox on iPhone and iPad, on the sample data: Kai assigned Jordan #25, Theo commented on #8, mentioned Jordan
/// on #15 and assigned #27 (on no board), Mira asked for a review of a pull request, and a few older ones are read.
final class InboxTests: AppTestCase {
    private func launchInbox() {
        launch(["-mobile.tab", "inbox"])
        wait(element("inbox-row-25"))
    }

    private func isUnread(_ row: XCUIElement) -> Bool {
        row.label.hasPrefix("Unread")
    }

    private func waitForRead(_ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let read = NSPredicate(format: "NOT (label BEGINSWITH 'Unread')")
        let expectation = XCTNSPredicateExpectation(predicate: read, object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 6), .completed, "Still unread: \(row.label)", file: file, line: line)
    }

    // MARK: iPhone

    func testInboxListsWhatHappenedAndOpeningReadsIt() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        let row = element("inbox-row-25")
        XCTAssertTrue(isUnread(row))
        XCTAssertTrue(row.label.contains("Kai Andersen assigned you"))
        XCTAssertTrue(element("inbox-row-15").label.contains("Theo Novak mentioned you"))
        XCTAssertTrue(element("inbox-row-git-issues-36").label.contains("requested your review"))
        snapshot("Inbox")

        row.tap()
        wait(labelled("New since yesterday"))
        wait(labelled("assigned you"))
        wait(element("issue-title"))
        snapshot("Issue from the Inbox")
        goBack()
        waitForRead(element("inbox-row-25"))
    }

    func testAnOverdueIssueIsInTheInboxAndMovesToTomorrow() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        // #25 was due two days ago and is assigned to Jordan.
        let row = element("inbox-due-25")
        wait(row)
        XCTAssertTrue(isUnread(row))
        XCTAssertTrue(row.label.contains("Overdue since"))
        row.tap()
        let later = button("Move to Tomorrow")
        wait(later)
        XCTAssertTrue(button("Mark as Done").exists)
        snapshot("Overdue issue from the Inbox")
        later.tap()
        goBack()
        waitGone(element("inbox-due-25"))
        wait(element("inbox-row-25"))
    }

    func testSwipeLeftArchivesAndUndoBringsItBack() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        let row = element("inbox-row-14")
        wait(row)
        row.swipeLeft()
        let archive = button("Archive")
        wait(archive)
        archive.tap()
        waitGone(row)
        let undo = element("inbox-undo")
        wait(undo)
        snapshot("Archived, with Undo")
        undo.tap()
        waitGone(undo, 2)
        wait(element("inbox-row-14"))
    }

    func testSwipeRightMarksUnreadAndRead() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        let row = element("inbox-row-14")
        wait(row)
        XCTAssertFalse(isUnread(row))
        row.swipeRight()
        button("Unread").tap()
        waitForLabel(row, containing: "Unread")
        row.swipeRight()
        button("Read").tap()
        waitForRead(row)
    }

    func testLongPressSnoozes() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        let row = element("inbox-row-8")
        row.press(forDuration: 1.0)
        let snooze = button("Snooze")
        wait(snooze)
        snapshot("Inbox menu")
        snooze.tap()
        let tomorrow = labelled("Tomorrow", type: .button)
        wait(tomorrow)
        tomorrow.tap()
        waitGone(element("inbox-row-8"))
    }

    func testWatchingShowsRepositoriesYouWatch() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        XCTAssertFalse(element("inbox-row-website-37").exists)
        app.segmentedControls.buttons["Watching"].tap()
        wait(element("inbox-row-website-37"))
        XCTAssertTrue(element("inbox-row-website-37").label.contains("opened it in acme/website"))
        waitGone(element("inbox-row-25"))
    }

    func testIssueOnNoBoardGoesOntoOneFromTheInbox() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        // #27 is in the app's repository but on no board.
        let row = element("inbox-row-git-issues-27")
        scrollTo(row)
        XCTAssertTrue(row.label.contains("Theo Novak assigned you"))
        row.tap()
        let status = element("chip-status")
        wait(status)
        waitForLabel(status, containing: "No project")
        status.tap()
        let todo = button("Todo")
        wait(todo)
        todo.tap()
        waitForLabel(status, containing: "Todo")
    }

    func testIssueOnlyTheInboxKnowsGoesOntoABoard() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        // No board uses acme/brand, so the app knows the issue only from the notification.
        let outside = element("inbox-row-brand-4")
        scrollTo(outside)
        outside.tap()
        let status = element("chip-status")
        wait(status)
        waitForLabel(status, containing: "No project")
        snapshot("Issue only the Inbox knows")
        status.tap()
        // It could go on either board.
        let board = labelled("Git Issues", type: .button)
        wait(board)
        board.tap()
        let todo = button("Todo")
        wait(todo)
        todo.tap()
        waitForLabel(status, containing: "Todo")
    }

    // MARK: iPad

    func testPadShowsTheIssueBesideTheList() throws {
        try XCTSkipUnless(isPad, "iPad layout")
        launchInbox()
        wait(labelled("No notification selected"))
        // Turning the iPad makes the tab bar a sidebar; the Inbox stays as it was.
        XCUIDevice.shared.orientation = .landscapeLeft
        element("inbox-row-25").tap()
        wait(labelled("New since yesterday"))
        wait(element("issue-title"))
        snapshot("iPad Inbox")
        waitForRead(element("inbox-row-25"))
        element("inbox-row-15").tap()
        let title = element("issue-title")
        let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'Conflict banner'"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [switched], timeout: 6), .completed, "The issue beside the list didn't change")
        XCUIDevice.shared.orientation = .portrait
        wait(element("inbox-row-15"))
    }
}
