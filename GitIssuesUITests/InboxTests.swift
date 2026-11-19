import XCTest

/// The Inbox on iPhone and iPad, on the sample data: Kai assigned Jordan #25, Theo commented on #8, mentioned Jordan
/// on #15 and assigned #27 (on no board), Mira asked for a review of a pull request, and a few older ones are read;
/// those need Jordan. Theo merged Jordan's pull request and a bot opened one in a watched repository: updates. Jordan's
/// own account opened #38, and #45 to #47 together: from Jordan.
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
        // Low in the list: clear of the search and New Issue at the foot, which take touches above their glass.
        scrollTo(row)
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

    func testCategoriesSortTheInbox() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launchInbox()
        // Needs You first: what someone asks of Jordan, not the pull request merged or the bot's.
        XCTAssertTrue(element("inbox-category-needsYou").isSelected)
        XCTAssertFalse(element("inbox-row-git-issues-39").exists)
        XCTAssertFalse(element("inbox-row-website-37").exists)

        element("inbox-category-updates").tap()
        wait(element("inbox-row-website-37"))
        XCTAssertTrue(element("inbox-row-website-37").label.contains("opened it in acme/website"))
        XCTAssertTrue(element("inbox-row-git-issues-39").exists)
        waitGone(element("inbox-row-25"))
        snapshot("Inbox updates")

        // From You: #38 on its own, and the three an agent opened together as one row that unfolds.
        element("inbox-category-fromYou").tap()
        let run = element("inbox-run-3")
        wait(run)
        XCTAssertTrue(run.label.contains("3 issues assigned to you"))
        XCTAssertTrue(element("inbox-row-git-issues-38").exists)
        XCTAssertFalse(element("inbox-row-git-issues-46").exists)
        run.tap()
        wait(element("inbox-row-git-issues-46"))
        snapshot("Inbox from you")

        element("inbox-category-all").tap()
        wait(element("inbox-row-25"))
        wait(element("inbox-row-website-37"))
        element("inbox-category-needsYou").tap()
        waitGone(element("inbox-row-website-37"))
    }

    func testSettingsChooseTheCategories() throws {
        try XCTSkipIf(isPad, "iPhone layout")
        launch()
        goHome()
        element("account-button").tap()
        wait(app.navigationBars["Account"])
        // Needs You off: the Inbox opens on From You, and Home counts From You once it's ticked for the badge.
        let needsYou = app.switches["inbox-category-setting-needsYou"]
        scrollTo(needsYou, in: app.collectionViews.firstMatch)
        XCTAssertEqual(needsYou.value as? String, "1")
        needsYou.switches.firstMatch.tap()
        waitForValue(needsYou, equalTo: "0")
        let countFromYou = element("inbox-badge-setting-fromYou")
        scrollTo(countFromYou, in: app.collectionViews.firstMatch)
        XCTAssertFalse(countFromYou.isSelected)
        XCTAssertFalse(element("inbox-badge-setting-needsYou").isEnabled)
        countFromYou.tap()
        XCTAssertTrue(countFromYou.isSelected)
        snapshot("Inbox categories in Settings")
        button("Done").tap()
        let inbox = element("home-inbox")
        waitForValue(inbox, equalTo: "4")
        inbox.tap()
        wait(element("inbox-run-3"))
        XCTAssertFalse(element("inbox-category-needsYou").exists)
        XCTAssertTrue(element("inbox-category-fromYou").isSelected)
        XCTAssertFalse(element("inbox-row-25").exists)
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
