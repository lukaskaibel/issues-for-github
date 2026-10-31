import XCTest

/// A project's saved views on the iPhone, on the sample data: the board "Git Issues" has the views Board, This Week
/// (this cycle's issues, a board), By Area (open issues grouped by the Area field), Bugs and Sync, Release Plan (a
/// roadmap by milestone), Epics (sub-issues grouped by their parent) and Team (open issues grouped by assignee).
final class PhoneViewsTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone layout")
    }

    /// Opens a view from the project's page, a step back from the view on screen.
    private func openView(_ name: String) {
        openFromProjectPage("Git Issues", name)
    }

    func testAViewShowsWhatItsFilterFinds() {
        launch()
        openProjectTab("Git Issues")
        // The project opens on its open view, which names the screen; its views are on the project's page under it.
        wait(element("strip-In Progress"))
        wait(app.navigationBars["Board"])
        openProjectPage("Git Issues")
        // Each with how many of its issues are open.
        waitForLabel(element("page-This Week"), containing: "9")
        wait(element("page-Bugs and Sync"))
        snapshot("Views on the project's page")

        element("page-This Week").tap()
        wait(app.navigationBars["This Week"])
        waitForValue(element("view-filter"), equalTo: "Iteration is Current")
        wait(element("card-#9"))
        // A board switched to opens on its work in progress, the column the strip raises.
        XCTAssertTrue(element("strip-In Progress").isSelected)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element("card-#9").frame), "In Progress is on screen")
        // Two of the four in Todo are planned for the next cycle, not this one.
        waitForLabel(element("strip-Todo"), containing: "Todo, 2 issues")
        snapshot("This Week")

        openView("Bugs and Sync")
        wait(element("row-#25"))
        waitGone(element("row-#9"))
        snapshot("Bugs and Sync")

        // The view opened last is the one the project opens on from Home.
        goHome()
        openProjectTab("Git Issues")
        wait(app.navigationBars["Bugs and Sync"])
    }

    func testAViewGroupsByItsField() {
        launch()
        openProjectTab("Git Issues")
        openView("By Area")
        wait(element("section-Interface"))
        snapshot("By Area")
        scrollTo(element("section-Sync"))
        wait(element("section-Sync"))
        scrollTo(element("section-Release"))
        wait(element("section-Release"))
        // Only open issues, and none of them done.
        XCTAssertFalse(element("section-Done").exists)
    }

    func testGroupsOfWorkShowHowFarTheyAre() {
        launch()
        openProjectTab("Git Issues")
        openView("Epics")
        let drag = element("section-#9 · Drag cards between columns with spring physics")
        wait(drag)
        waitForValue(drag, equalTo: "Open, 4 of 6 issues done")
        wait(element("row-#13"))
        snapshot("Epics")

        // Nothing under way in it yet, so it starts folded, and the view opens as an overview of what is left.
        let signIn = element("section-#42 · Sign-in and accounts")
        scrollTo(signIn)
        waitForValue(signIn, equalTo: "Folded, 0 of 1 issues done")
        XCTAssertFalse(element("row-#14").exists)
        signIn.tap()
        waitForValue(signIn, equalTo: "Open, 0 of 1 issues done")
        scrollTo(element("row-#14"))
        wait(element("row-#14"))

        // Grouped by person, a group is someone's load.
        openView("Team")
        wait(element("section-jordan"))
        wait(element("row-#8"))
        snapshot("Team")
    }

    func testACycleViewStepsThroughTheCycles() {
        launch()
        openProjectTab("Git Issues")
        openView("This Week")
        showLayout("List")
        let cycle = element("cycle")
        wait(cycle)
        wait(cycle.staticTexts["Cycle 4"])
        wait(element("row-#9"))
        snapshot("Cycle header")

        element("cycle-next").tap()
        waitForValue(element("view-filter"), equalTo: "Iteration is Next")
        wait(cycle.staticTexts["Cycle 5"])
        // Planned for the next cycle.
        wait(element("row-#14"))
        waitGone(element("row-#9"))
        // Another cycle is a changed filter, as on GitHub, until it is saved; the project's page says so too.
        goBack()
        waitForValue(element("page-This Week"), equalTo: "Filter changed")
        element("page-This Week").tap()

        // Back to the one under way: the view as saved again.
        element("cycle-previous").tap()
        waitForValue(element("view-filter"), equalTo: "Iteration is Current")
        wait(cycle.staticTexts["Cycle 4"])
        wait(element("row-#9"))
        XCTAssertFalse(button("Save").exists)
        goBack()
        waitForValue(element("page-This Week"), notEqualTo: "Filter changed")
    }

    func testAChangedFilterStaysUntilSavedOrReset() {
        launch()
        openProjectTab("Git Issues")
        openView("Bugs and Sync")
        waitGone(element("row-#9"))

        element("view-filter").tap()
        wait(app.navigationBars["Bugs and Sync"])
        button("Add Filter").tap()
        wait(app.navigationBars["Add Filter"])
        button("Label").tap()
        wait(app.navigationBars["Label"])
        let ui = pickerRow("ui")
        wait(ui)
        snapshot("Filter values")
        ui.tap()
        // Labels take several, so the screen stays for more; the first term now finds any of three.
        goBack()
        goBack()
        wait(button("Save for Everyone"))
        snapshot("Filter changed")
        button("Done").tap()

        waitForValue(element("view-filter"), equalTo: "Label is any of bug, sync, ui, Open or closed is Open")
        wait(element("row-#9"))
        wait(button("Save"))
        snapshot("Changed filter over the list")

        element("view-filter").tap()
        button("Reset").tap()
        waitGone(button("Reset"))
        button("Done").tap()
        waitForValue(element("view-filter"), equalTo: "Label is any of bug, sync, Open or closed is Open")
        waitGone(element("row-#9"))
        XCTAssertFalse(button("Save").exists)
    }

    func testANewViewStartsFromTheOpenOne() {
        launch()
        openProjectTab("Git Issues")
        openView("This Week")
        showLayout("List")
        // After the last of the views on the project's page.
        openProjectPage("Git Issues")
        scrollTo(element("page-new-view"))
        element("page-new-view").tap()
        let name = app.textFields["View name"]
        wait(name)
        // The open view's filter comes along, to change before creating.
        wait(labelled("Iteration"))
        snapshot("New view")
        name.typeText("Cycle")
        button("Create").tap()
        waitGone(name)
        // The new view opens.
        wait(app.navigationBars["Cycle"])
        waitForValue(element("view-filter"), equalTo: "Iteration is Current")
        wait(element("row-#9"))
        goBack()
        wait(element("page-Cycle"))
    }

    func testRenamingAndDeletingAView() {
        launch()
        // Touch and hold a view on the project's page for its menu.
        openProjectPage("Git Issues")
        let row = element("page-Bugs and Sync")
        wait(row)
        row.press(forDuration: 1.2)
        wait(button("Rename"))
        snapshot("View menu")
        button("Rename").tap()
        let alert = app.alerts.firstMatch
        wait(alert)
        let field = alert.textFields.firstMatch
        replaceText(of: field, with: "Bugs")
        confirmAlert(alert, with: "Save")
        wait(element("page-Bugs"))

        element("page-Bugs").press(forDuration: 1.2)
        wait(button("Delete View…"))
        button("Delete View…").tap()
        let confirm = app.alerts.firstMatch
        wait(confirm)
        confirmAlert(confirm, with: "Delete View")
        waitGone(element("page-Bugs"))
        wait(element("page-By Area"))
    }
}

/// The board on the iPhone, on the sample data: a board view shows one column at a time, with every column and its
/// count in a strip over it. The board "Git Issues" has the columns Backlog, Todo, In Progress, In Review and Done.
final class PhoneBoardTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone layout")
    }

    func testTheBoardShowsOneColumnAtATime() {
        launch()
        openProjectTab("Git Issues")
        // It opens on the work in progress.
        let progress = element("strip-In Progress")
        wait(progress)
        XCTAssertTrue(progress.isSelected)
        wait(element("card-#9"))
        snapshot("iPhone board")

        // A tap on the strip turns to another column.
        let todo = element("strip-Todo")
        todo.tap()
        wait(element("card-#17"))
        waitUntil(todo.isSelected, "Todo is the column on screen")
        snapshot("Todo")

        // A swipe turns to the next.
        element("column-Todo").swipeLeft()
        waitUntil(progress.isSelected, "In Progress is the column on screen")

        // Board or list is the view's, in the Display part of the project's menu.
        showLayout("List")
        wait(element("section-In Progress"))
        waitGone(progress)
        showLayout("Board")
        wait(progress)
    }

    func testACardDroppedOnTheStripGoesFirstInThatColumn() {
        launch()
        openProjectTab("Git Issues")
        let card = element("card-#7")
        wait(card)
        waitForLabel(element("strip-In Review"), containing: "In Review, 3 issues")
        // Lifted, the card turns the strip into a target for each column; In Review's is the fourth of five.
        drag(card, toTarget: 3, holding: 0.3)
        waitForLabel(element("strip-In Review"), containing: "In Review, 4 issues")
        waitForLabel(element("strip-In Progress"), containing: "In Progress, 5 issues")
        snapshot("Dropped on In Review")
    }

    func testACardHeldOverAColumnTurnsTheBoardToIt() {
        launch()
        openProjectTab("Git Issues")
        let card = element("card-#7")
        wait(card)
        // Held over Done's target, the last of five, the board turns to Done, and the card lands first there.
        drag(card, toTarget: 4, holding: 1.6)
        let done = element("strip-Done")
        waitUntil(done.isSelected, "Done is the column on screen")
        wait(card)
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'card-#'"))
            .allElementsBoundByIndex.filter { $0.frame.minX >= 0 && $0.frame.maxX <= app.windows.firstMatch.frame.maxX }
            .min { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(first?.identifier, "card-#7")
        snapshot("Turned to Done")
    }

    /// Touches and holds a card until it lifts, drags it up to the target of a column over the strip, holds it
    /// there, and lets go. The targets share the width equally, 12 points in from the edges with 6 between them.
    private func drag(_ card: XCUIElement, toTarget index: Int, holding seconds: TimeInterval) {
        let width = app.windows.firstMatch.frame.width
        let count = 5.0
        let step = (width - 24 + 6) / count
        let x = 12 + step * (CGFloat(index) + 0.5) - 3
        let y = element("strip-In Progress").frame.midY
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        // Moving slowly lets the drag take over from the card's menu before the finger arrives.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: seconds)
    }

    private func waitUntil(_ condition: @autoclosure @escaping () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 6), .completed, message, file: file, line: line)
    }
}

/// Views on the iPad: the sidebar lists the project's views under a switch to another project, as on the Mac; a board
/// view shows as a board, a list view as a list, each as GitHub has it.
final class PadViewsTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout")
    }

    func testEachViewIsAnEntryOfTheSidebar() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        // Every project has a row, over the entries of the one open.
        wait(sidebarEntry("Website"))
        wait(sidebarEntry("Board"))
        wait(sidebarEntry("Release Plan"))
        wait(sidebarEntry("0.3"))
        wait(sidebarEntry("Roadmap"))
        wait(element("column-Todo"))
        // The sidebar lists them, so no capsules over the board.
        XCTAssertFalse(element("view-Board").exists)
        snapshot("iPad Board view")

        sidebarEntry("By Area").tap()
        wait(element("section-Interface"))
        waitGone(element("column-Todo"))
        snapshot("iPad By Area")

        sidebarEntry("This Week").tap()
        wait(element("column-In Progress"))
        wait(element("card-#9"))
        waitGone(element("card-#14"))
        snapshot("iPad This Week")
    }

    func testTheSwitcherShowsAnotherProjectsViews() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        wait(sidebarEntry("This Week"))
        openPadProject("Website")
        wait(sidebarEntry("All"))
        waitGone(sidebarEntry("This Week"))
        wait(element("column-Todo"))
        snapshot("iPad Website")
        sidebarEntry("All").tap()
        wait(element("row-#31"))
    }

    func testARoadmapViewIsATimeline() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        sidebarEntry("Release Plan").tap()
        let release = element("timeline-section-0.3")
        wait(release)
        wait(element("timeline-row-#9"))
        // A milestone that's all done starts folded.
        wait(element("timeline-section-0.2"))
        XCTAssertFalse(element("timeline-row-#4").exists)
        snapshot("iPad Release Plan")

        release.tap()
        waitGone(element("timeline-row-#9"))
        release.tap()
        wait(element("timeline-row-#9"))

        // The same view as a list, from the Display menu, and back.
        showLayout("List")
        wait(element("section-0.3"))
        waitGone(release)
        showLayout("Timeline")
        wait(release)

        // An issue opens from its name.
        element("timeline-row-#9").tap()
        let title = element("issue-title")
        wait(title)
        XCTAssertEqual(title.value as? String, "Drag cards between columns with spring physics")
    }

    /// A swipe over a bar scrolls dates. Moving the same bar requires a hold first.
    func testTimelineDateEditingRequiresAHold() {
        XCUIDevice.shared.orientation = .landscapeLeft
        func openTimeline() -> XCUIElement {
            launch(["-timeline.scale", "15"])
            openPadProject("Git Issues")
            sidebarEntry("Release Plan").tap()
            let row = element("timeline-row-#9")
            wait(row)
            return row
        }
        func barCentre(_ row: XCUIElement) -> XCUICoordinate {
            // The sample timeline starts ten days before the Monday two weeks ago. #9 runs from seven
            // days ago to today, so its eight-day bar is centred 21 days after that Monday's padding.
            let sinceMonday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
            return row.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: 1 + CGFloat(21 + sinceMonday) * 15, dy: 0))
        }
        func date(_ offset: Int) -> String {
            Calendar.current.date(byAdding: .day, value: offset, to: Date())!
                .formatted(.dateTime.day().month().locale(appLocale))
        }

        let row = openTimeline()
        let original = row.value as? String
        XCTAssertEqual(original, "\(date(-7)) – \(date(0))")
        let start = barCentre(row)
        start.press(forDuration: 0, thenDragTo: start.withOffset(CGVector(dx: -120, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        waitForValue(row, equalTo: original)
        XCTAssertFalse(element("notice-undo").exists)
        // The bar is now left of this point. A held drag here must still leave its dates alone; otherwise the
        // first gesture failed to scroll, leaving the original bar under the finger.
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0)
        waitForValue(row, equalTo: original)
        snapshot("Timeline swipe leaves dates unchanged")

        // Start fresh at the same scroll position. This also proves the swipe above started on an editable bar.
        app.terminate()
        let heldRow = openTimeline()
        let heldStart = barCentre(heldRow)
        heldStart.press(forDuration: 0.5, thenDragTo: heldStart.withOffset(CGVector(dx: 30, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0)
        waitForValue(heldRow, equalTo: "\(date(-5)) – \(date(2))")
        snapshot("Held timeline bar moved by two days")
        heldStart.tap()
        let title = element("issue-title")
        wait(title)
        XCTAssertEqual(title.value as? String, "Drag cards between columns with spring physics")
    }

    func testTheFilterSheetOnTheIPad() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        sidebarEntry("Bugs and Sync").tap()
        element("view-filter").tap()
        wait(app.navigationBars["Bugs and Sync"])
        wait(button("Add Filter"))
        snapshot("iPad filter sheet")
        button("Done").tap()
        waitGone(app.navigationBars["Bugs and Sync"])
    }
}
