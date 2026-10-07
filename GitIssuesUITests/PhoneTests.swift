import XCTest

/// Every feature of the iPhone app, on the sample data.
final class PhoneTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone layout")
    }

    // MARK: Lists

    func testMyIssuesGroupsByStatusAndFoldsSections() {
        launch()
        wait(app.navigationBars["My Issues"])
        wait(element("section-In progress"))
        wait(element("row-#9"))
        XCTAssertTrue(element("row-#9").label.contains("Drag cards between columns with spring physics"))
        XCTAssertTrue(element("row-#9").label.contains("Urgent priority"))
        snapshot("My Issues")

        element("section-In progress").tap()
        waitGone(element("row-#9"))
        snapshot("My Issues, In progress folded")
        element("section-In progress").tap()
        wait(element("row-#9"))
    }

    func testPullToRefreshKeepsTheList() {
        launch()
        wait(element("row-#9"))
        let start = element("row-#5").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
        wait(element("row-#9"))
    }

    // MARK: An issue

    func testOpenIssueEditTitleAndGoBack() {
        launch()
        element("row-#13").tap()
        let title = element("issue-title")
        wait(title)
        snapshot("Issue #13")
        // Tapping at the end of the line puts the cursor after the last word.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        title.typeText(" quickly")
        app.keyboards.buttons["Done"].firstMatch.tap()
        goBack()
        wait(element("row-#13"))
        waitForLabel(element("row-#13"), containing: "Cancel a drag with Escape quickly")
    }

    func testStatusAndPriorityMenus() {
        launch()
        element("row-#13").tap()
        wait(element("chip-status"))
        element("chip-status").tap()
        wait(button("In Review"))
        snapshot("Status menu")
        button("In Review").tap()
        waitForLabel(element("chip-status"), containing: "In Review")

        element("chip-priority").tap()
        wait(button("Urgent"))
        snapshot("Priority menu")
        button("Urgent").tap()
        waitForLabel(element("chip-priority"), containing: "Urgent")

        // Done closes the issue; the list shows it among the finished ones.
        element("chip-status").tap()
        button("Done").tap()
        waitForLabel(element("chip-status"), containing: "Done")
        goBack()
        let moved = element("row-#13")
        scrollTo(moved)
        waitForLabel(moved, containing: "Done")
    }

    func testAssigneeAndLabelSheets() {
        launch()
        element("row-#13").tap()
        wait(element("chip-assignee"))
        element("chip-assignee").tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        search.typeText("mira")
        let mira = labelled("mira", type: .button)
        wait(mira)
        snapshot("Assignee sheet")
        mira.tap()
        snapshot("Assignee picked while searching")
        button("Done").tap()
        waitForLabel(element("chip-assignee"), containing: "mira")

        element("chip-labels").tap()
        let bug = labelled("bug", type: .button)
        wait(bug)
        bug.tap()
        snapshot("Labels sheet")
        button("Done").tap()
        waitForLabel(element("chip-labels"), containing: "bug")
    }

    func testDescriptionEditsInPlace() {
        launch()
        wait(element("row-#9"))
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        let description = element("issue-description")
        wait(description)
        description.tap()
        app.typeText("Rank matches by **how close** they are.")
        snapshot("Editing a description")
        let done = button("Done")
        wait(done)
        done.tap()
        goBack()
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        wait(element("issue-description"))
        XCTAssertTrue(labelled("how close").waitForExistence(timeout: 4))
    }

    func testDrawnDescriptionTicksBoxesAndShowsTheText() {
        launch()
        wait(element("row-#9"))
        scrollTo(element("row-#16"))
        element("row-#16").tap()
        // A checklist, a table and a diagram: drawn as on GitHub, with boxes that tick.
        let box = app.buttons["Images pasted from the clipboard"]
        wait(box)
        XCTAssertEqual(box.value as? String, "Unchecked")
        box.tap()
        waitForValue(box, equalTo: "Checked")
        snapshot("Drawn description")

        // A tap shows the Markdown, ticked box included; a second tap edits it.
        labelled("drawn the way GitHub draws it").tap()
        waitGone(box)
        let text = element("issue-description")
        XCTAssertTrue((text.value as? String)?.contains("- [x] Images pasted from the clipboard") == true)
        text.tap()
        let done = button("Done")
        wait(done)
        snapshot("Editing a drawn description")
        done.tap()
        wait(box)
        XCTAssertEqual(box.value as? String, "Checked")
    }

    func testCommentsAndSubIssues() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))
        snapshot("Issue #9 with sub-issues")

        // Ticking a sub-issue moves it to done.
        let toggle = element("sub-toggle-#13")
        scrollTo(toggle)
        wait(toggle)
        toggle.tap()
        waitForLabel(element("sub-toggle-#13"), containing: "Reopen")

        let field = element("comment-field")
        wait(field)
        field.tap()
        field.typeText("Let's ship this on Friday.")
        element("comment-send").tap()
        let comment = labelled("Let's ship this on Friday.")
        wait(comment)
        scrollTo(comment)
        snapshot("Comment sent")
    }

    func testNewIssueAndSubIssue() {
        launch()
        element("compose-button").tap()
        let title = element("new-title")
        wait(title)
        title.typeText("Haptic feedback when a card lands")
        snapshot("New issue")
        button("Create").tap()
        waitGone(title)
        // Created from My Issues, it is assigned to you and lands at the end of Todo.
        let row = labelled("Haptic feedback when a card lands")
        scrollTo(row)
        wait(row, 8)
        XCTAssertTrue(row.label.contains("assigned to jordan"))
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)

        // A sub-issue from the issue's menu.
        element("row-#9").tap()
        wait(element("issue-title"))
        app.navigationBars.buttons["More"].tap()
        button("Add Sub-issue").tap()
        let subTitle = element("new-title")
        wait(subTitle)
        subTitle.typeText("Snap to the nearest gap")
        button("Create").tap()
        waitGone(subTitle)
        let sub = labelled("Snap to the nearest gap")
        scrollTo(sub)
        wait(sub, 8)
        snapshot("New sub-issue")
    }

    func testIssueMenuCopiesLinkAndDeletes() {
        launch()
        element("row-#13").tap()
        wait(element("issue-title"))
        app.navigationBars.buttons["More"].tap()
        wait(button("Copy Link"))
        snapshot("Issue menu")
        button("Copy Link").tap()
        wait(labelled("Link copied"))

        // Deleting the issue on screen goes back to the list, without it.
        app.navigationBars.buttons["More"].tap()
        labelled("Delete Issue", type: .button).tap()
        let alert = app.alerts.firstMatch
        wait(alert)
        alert.buttons["Delete"].tap()
        wait(app.navigationBars["My Issues"])
        wait(element("row-#9"))
        waitGone(element("row-#13"))
    }

    func testShareSheet() {
        launch()
        element("row-#13").tap()
        wait(element("issue-title"))
        app.navigationBars.buttons["Share…"].tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        wait(copy, 10)
        snapshot("Share sheet")
        copy.tap()
        waitGone(copy)
        wait(element("issue-title"))
    }

    func testSubIssueOpensAndLeadsBackToItsParent() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))
        let sub = element("sub-#10")
        scrollTo(sub)
        sub.tap()
        let parent = labelled("Sub-issue of #9", type: .button)
        wait(parent)
        waitForLabel(element("chip-status"), containing: "Done")
        snapshot("Sub-issue")
        parent.tap()
        wait(element("sub-toggle-#10"))

        // A sub-issue's own menu, from a long press.
        let row = element("sub-#11")
        scrollTo(row)
        row.press(forDuration: 1.2)
        wait(button("Status"))
        snapshot("Sub-issue menu")
        button("Status").tap()
        button("In Progress").tap()
        waitForLabel(element("sub-toggle-#11"), containing: "Mark #11 as done")
    }

    // MARK: Gestures

    func testSwipeActions() {
        launch()
        let row = element("row-#13")
        wait(element("row-#9"))
        scrollTo(row)
        row.swipeRight()
        wait(button("Done"))
        snapshot("Swipe right: Done")
        button("Done").tap()
        let moved = element("row-#13")
        scrollTo(moved)
        waitForLabel(moved, containing: "Done")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)

        let other = element("row-#5")
        scrollTo(other)
        other.swipeLeft()
        wait(button("Unassign"))
        snapshot("Swipe left: Unassign and Delete")
        button("Delete").tap()
        let alert = app.alerts.firstMatch
        wait(alert)
        snapshot("Delete confirmation")
        alert.buttons["Delete"].tap()
        waitGone(element("row-#5"))
    }

    func testLongPressMenu() {
        launch()
        let row = element("row-#8")
        wait(row)
        row.press(forDuration: 1.2)
        wait(button("Status"))
        snapshot("Long-press menu")
        XCTAssertTrue(button("Priority").exists)
        XCTAssertTrue(button("Copy Link").exists)
        XCTAssertTrue(button("Open on GitHub").exists)
        XCTAssertTrue(labelled("Delete Issue", type: .button).exists)
        button("Status").tap()
        wait(button("In Review"))
        button("In Review").tap()
        waitForLabel(element("row-#8"), containing: "In Review")

        row.press(forDuration: 1.2)
        wait(button("Copy Link"))
        button("Copy Link").tap()
        wait(labelled("Link copied"))
        snapshot("Link copied banner")
    }

    func testLongPressSubmenus() {
        launch()
        let row = element("row-#8")
        wait(row)

        row.press(forDuration: 1.2)
        button("Priority").tap()
        wait(button("Urgent"))
        snapshot("Priority submenu")
        button("Urgent").tap()
        waitForLabel(element("row-#8"), containing: "Urgent priority")

        element("row-#8").press(forDuration: 1.2)
        button("Assignee").tap()
        wait(button("mira"))
        snapshot("Assignee submenu")
        button("mira").tap()
        waitForLabel(element("row-#8"), containing: "mira")

        element("row-#8").press(forDuration: 1.2)
        button("Labels").tap()
        wait(button("bug"))
        button("bug").tap()
        waitForLabel(element("row-#8"), containing: "bug")

        // Unassigned, it leaves My Issues.
        element("row-#8").press(forDuration: 1.2)
        button("Unassign Me").tap()
        waitGone(element("row-#8"))

        scrollTo(element("row-#17"))
        element("row-#17").press(forDuration: 1.2)
        labelled("Delete Issue", type: .button).tap()
        let alert = app.alerts.firstMatch
        wait(alert)
        alert.buttons["Delete"].tap()
        waitGone(element("row-#17"))
    }

    func testOpenOnGitHub() {
        launch()
        element("row-#8").press(forDuration: 1.2)
        button("Open on GitHub").tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        app.activate()
        wait(element("row-#8"))
    }

    // MARK: Search and projects

    func testSearchFindsIssuesAndProjects() {
        launch()
        app.tabBars.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        wait(field)
        field.tap()
        field.typeText("drag")
        wait(element("row-#9"))
        snapshot("Search results")
        element("row-#9").tap()
        wait(element("issue-title"))
        goBack()
        field.tap()
        field.buttons["Clear text"].firstMatch.tap()
        app.typeText("#31")
        wait(element("row-#31"))
    }

    func testProjectsSwitchingAndSettings() {
        launch()
        app.tabBars.buttons["Projects"].tap()
        let website = labelled("Website", type: .button)
        wait(website)
        snapshot("Projects")
        website.tap()
        wait(app.navigationBars["Website"])
        wait(labelled("No Priority field"))
        snapshot("Website without priority")
        button("Add").tap()
        waitGone(labelled("No Priority field"), 8)

        // Switching project from the title menu.
        app.navigationBars["Website"].buttons["Website"].tap()
        wait(button("Git Issues"))
        snapshot("Project title menu")
        button("Git Issues").tap()
        wait(app.navigationBars["Git Issues"])

        // Sections in a different order.
        app.navigationBars.buttons["Options"].tap()
        button("Arrange Sections…").tap()
        wait(app.navigationBars["Arrange Sections"])
        snapshot("Arrange sections")
        button("Done").tap()

        // Statuses: add one and see it in the list's menu.
        app.navigationBars.buttons["Options"].tap()
        button("Edit Statuses…").tap()
        wait(app.navigationBars["Statuses"])
        button("Add Status").tap()
        let alert = app.alerts.firstMatch
        wait(alert)
        alert.textFields.firstMatch.typeText("QA")
        confirmAlert(alert, with: "Add")
        wait(labelled("QA", type: .button))
        snapshot("Statuses")
    }

    func testNewIssueInASectionWithEveryProperty() {
        launch()
        openProjectTab("Git Issues")
        element("add-In Progress").tap()
        let title = element("new-title")
        wait(title)
        title.typeText("Spring back when a drop misses")
        waitForLabel(element("new-status"), containing: "In Progress")

        element("new-priority").tap()
        button("High").tap()
        waitForLabel(element("new-priority"), containing: "High")
        element("new-assignee").tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        search.typeText("theo")
        let theo = labelled("theo", type: .button)
        wait(theo)
        theo.tap()
        button("Done").tap()
        waitForLabel(element("new-assignee"), containing: "theo")
        element("new-labels").tap()
        let labelSearch = app.searchFields.firstMatch
        wait(labelSearch)
        labelSearch.tap()
        labelSearch.typeText("ui")
        wait(button("ui"))
        button("ui").tap()
        button("Done").tap()
        waitForLabel(element("new-labels"), containing: "ui")
        element("new-description").tap()
        element("new-description").typeText("Cards that land outside a column go back to where they came from.")
        snapshot("New issue with properties")
        button("Create").tap()
        waitGone(title)

        let row = labelled("Spring back when a drop misses")
        scrollTo(row)
        wait(row)
        XCTAssertTrue(row.label.contains("In Progress"), row.label)
        XCTAssertTrue(row.label.contains("High priority"), row.label)
        XCTAssertTrue(row.label.contains("theo"), row.label)
        XCTAssertTrue(row.label.contains("labels ui"), row.label)
        row.tap()
        wait(labelled("Cards that land outside a column"))
    }

    func testDiscardingANewIssueAsksFirst() {
        launch()
        element("compose-button").tap()
        let title = element("new-title")
        wait(title)
        title.typeText("Half a thought")
        button("Cancel").tap()
        let discard = button("Discard")
        wait(discard)
        snapshot("Discard new issue")
        discard.tap()
        waitGone(title)
        XCTAssertFalse(labelled("Half a thought").exists)
    }

    func testStatusesRenameRecolourReorderAndDelete() {
        launch()
        openProjectTab("Git Issues")
        app.navigationBars.buttons["Options"].tap()
        button("Edit Statuses…").tap()
        wait(app.navigationBars["Statuses"])

        app.buttons["In Review"].tap()
        let rename = app.alerts["Rename Status"]
        wait(rename)
        replaceText(of: rename.textFields.firstMatch, with: "Review")
        confirmAlert(rename, with: "Rename")
        wait(app.buttons["Review"])

        let colour = cell("Review").buttons.matching(NSPredicate(format: "label BEGINSWITH 'Colour'")).firstMatch
        colour.tap()
        wait(button("Pink"))
        snapshot("Status colours")
        button("Pink").tap()
        waitForLabel(colour, containing: "Pink")

        // Done moves to the top.
        let handle = reorderHandle(in: cell("Done"))
        let top = reorderHandle(in: cell("Backlog"))
        wait(handle)
        handle.press(forDuration: 0.6, thenDragTo: top)
        let backlog = app.buttons["Backlog"]
        XCTAssertLessThan(app.buttons["Done"].frame.minY, backlog.frame.minY)
        snapshot("Statuses rearranged")

        // The red circle in front of the row, which iOS doesn't label.
        cell("Backlog").coordinate(withNormalizedOffset: CGVector(dx: 0.075, dy: 0.5)).tap()
        let confirm = app.buttons["Delete"].firstMatch
        wait(confirm)
        confirm.tap()
        let dialog = button("Delete Status")
        wait(dialog)
        snapshot("Delete status")
        dialog.tap()
        waitGone(app.buttons["Backlog"])

        // The list shows the new statuses.
        goBack()
        wait(element("section-Review"))
        XCTAssertFalse(element("section-Backlog").exists)
    }

    func testArrangeSectionsAndReset() {
        launch()
        openProjectTab("Git Issues")
        wait(element("section-In Progress"))
        app.navigationBars.buttons["Options"].tap()
        button("Arrange Sections…").tap()
        wait(app.navigationBars["Arrange Sections"])
        let todo = reorderHandle(in: cell("Todo"))
        let first = reorderHandle(in: app.cells.firstMatch)
        wait(todo)
        todo.press(forDuration: 0.6, thenDragTo: first)
        scrollTo(button("Back to the Usual Order"), in: app.collectionViews.firstMatch)
        wait(button("Back to the Usual Order"))
        snapshot("Sections rearranged")
        button("Done").tap()
        // Back at the top of the list, where the first section is.
        app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        let todoFirst = element("section-Todo")
        wait(todoFirst)
        let progress = element("section-In Progress")
        XCTAssertTrue(!progress.exists || todoFirst.frame.minY < progress.frame.minY, "Todo leads the list")
        XCTAssertLessThan(todoFirst.frame.minY, app.frame.height / 3)

        app.navigationBars.buttons["Options"].tap()
        button("Arrange Sections…").tap()
        scrollTo(button("Back to the Usual Order"), in: app.collectionViews.firstMatch)
        button("Back to the Usual Order").tap()
        button("Done").tap()
        // Work in progress leads again; Todo is further down, maybe below the screen.
        let todoHeader = element("section-Todo")
        XCTAssertTrue(!todoHeader.exists || element("section-In Progress").frame.minY < todoHeader.frame.minY)
    }

    func testSearchOpensAProject() {
        launch()
        app.tabBars.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        wait(field)
        field.tap()
        field.typeText("web")
        let website = labelled("Website", type: .button)
        wait(website)
        website.tap()
        wait(app.navigationBars["Website"])
        wait(element("row-#31"))
    }

    // MARK: Account

    func testAccountAppearanceAndQueue() {
        launch()
        element("account-button").tap()
        wait(app.navigationBars["Account"])
        snapshot("Account")
        app.segmentedControls.buttons["Dark"].tap()
        snapshot("Account, dark")
        app.segmentedControls.buttons["System"].tap()
        labelled("Queued changes", type: .button).tap()
        wait(labelled("Everything is saved to GitHub"))
        goBack()
        button("Done").tap()
        wait(element("row-#9"))
    }

    func testAppIconChoice() {
        launch()
        element("account-button").tap()
        wait(app.navigationBars["Account"])
        let dark = button("Card, dark")
        scrollTo(dark, in: app.collectionViews.firstMatch)
        wait(dark)
        dark.tap()
        confirmIconChange()
        XCTAssertTrue(dark.isSelected)
        button("Card, light or dark with the system").tap()
        confirmIconChange()
        XCTAssertTrue(button("Card, light or dark with the system").isSelected)
    }

    func testLeavingSampleDataShowsSignIn() {
        launch()
        element("account-button").tap()
        wait(app.navigationBars["Account"])
        app.collectionViews.firstMatch.swipeUp()
        let leave = button("Leave Sample Data")
        wait(leave)
        leave.tap()
        wait(button("Use a Personal Access Token"))
        snapshot("Sign in")
        button("Use a Personal Access Token").tap()
        wait(app.navigationBars["Sign In with a Token"])
        snapshot("Token sheet")
        // A made-up token is checked with GitHub and turned down there, with an explanation.
        let field = app.secureTextFields.firstMatch
        wait(field)
        field.typeText("ghp_" + String(repeating: "0", count: 36))
        button("Sign In").tap()
        wait(labelled("didn't accept this token"), 20)
        snapshot("Token refused")
        button("Cancel").tap()
        button("Explore with Sample Data").tap()
        wait(element("row-#9"), 8)
    }

    // MARK: Looks

    func testLargeText() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'row-'")).firstMatch
        wait(row)
        snapshot("Large text, My Issues")
        row.tap()
        wait(element("issue-title"))
        snapshot("Large text, issue")
    }

    /// A row of a list, by the text of one of its parts.
    private func cell(_ text: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// The grip that moves a row while a list is being edited.
    private func reorderHandle(in cell: XCUIElement) -> XCUIElement {
        cell.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).firstMatch
    }

    /// iOS confirms a new app icon with an alert of its own.
    private func confirmIconChange() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for alert in [app.alerts.firstMatch, springboard.alerts.firstMatch] where alert.waitForExistence(timeout: 3) {
            snapshot("Icon changed")
            alert.buttons.firstMatch.tap()
            return
        }
    }

    func testLandscapeKeepsTheIPhoneLayout() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'row-'")).firstMatch
        wait(row)
        // Even where a large iPhone is wide, it keeps its tabs and lists.
        XCTAssertTrue(app.tabBars.buttons["Projects"].exists)
        snapshot("Landscape, My Issues")
        row.tap()
        wait(element("issue-title"))
        XCTAssertTrue(element("chip-status").exists)
        snapshot("Landscape, issue")
        XCUIDevice.shared.orientation = .portrait
    }

    func testDarkAppearance() {
        launch(["-appearance", "dark"])
        wait(element("row-#9"))
        snapshot("Dark, My Issues")
        element("row-#9").tap()
        wait(element("issue-title"))
        snapshot("Dark, issue")
        element("chip-status").tap()
        wait(button("In Review"))
        snapshot("Dark, status menu")
    }
}
