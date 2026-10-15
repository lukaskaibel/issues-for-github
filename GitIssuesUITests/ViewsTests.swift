import XCTest

/// A project's saved views on the iPhone, on the sample data: the board "Git Issues" has the views Board, This Week
/// (this cycle's issues), By Area (open issues grouped by the Area field), Bugs and Sync, Release Plan (a roadmap by
/// milestone), Epics (sub-issues grouped by their parent) and Team (open issues grouped by assignee).
final class PhoneViewsTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone layout")
    }

    private func openView(_ name: String) {
        let pill = element("view-\(name)")
        wait(pill)
        // The capsules scroll sideways; the later ones are off screen at first.
        let screen = app.windows.firstMatch.frame
        var swipes = 0
        while pill.frame.maxX > screen.maxX - 8 && swipes < 4 {
            app.scrollViews.containing(.button, identifier: "view-Board").firstMatch.swipeLeft()
            swipes += 1
        }
        pill.tap()
        XCTAssertTrue(pill.isSelected, "\(name) isn't the open view")
    }

    func testAViewShowsWhatItsFilterFinds() {
        launch()
        openProjectTab("Git Issues")
        wait(element("view-Board"))
        wait(element("view-This Week"))
        XCTAssertTrue(element("view-Board").isSelected)
        snapshot("Views over the project")

        openView("This Week")
        waitForValue(element("view-filter"), equalTo: "Iteration is Current")
        wait(element("row-#9"))
        // Planned for the next cycle, not this one.
        waitGone(element("row-#14"))
        snapshot("This Week")

        openView("Bugs and Sync")
        wait(element("row-#25"))
        waitGone(element("row-#9"))
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
        // Another cycle is a changed filter, as on GitHub, until it is saved.
        waitForValue(element("view-This Week"), equalTo: "Filter changed")

        // Back to the one under way: the view as saved again.
        element("cycle-previous").tap()
        waitForValue(element("view-filter"), equalTo: "Iteration is Current")
        wait(cycle.staticTexts["Cycle 4"])
        wait(element("row-#9"))
        waitForValue(element("view-This Week"), notEqualTo: "Filter changed")
        XCTAssertFalse(button("Save").exists)
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
        waitForValue(element("view-Bugs and Sync"), equalTo: "Filter changed")
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
        // After the last of the views.
        app.scrollViews.containing(.button, identifier: "view-This Week").firstMatch.swipeLeft()
        element("new-view").tap()
        let name = app.textFields["View name"]
        wait(name)
        // The open view's filter comes along, to change before creating.
        wait(labelled("Iteration"))
        snapshot("New view")
        name.typeText("Cycle")
        button("Create").tap()
        waitGone(name)
        wait(element("view-Cycle"))
        XCTAssertTrue(element("view-Cycle").isSelected)
        waitForValue(element("view-filter"), equalTo: "Iteration is Current")
        wait(element("row-#9"))
    }

    func testRenamingAndDeletingAView() {
        launch()
        openProjectTab("Git Issues")
        let pill = element("view-Bugs and Sync")
        wait(pill)
        pill.press(forDuration: 1.2)
        wait(button("Rename"))
        snapshot("View menu")
        button("Rename").tap()
        let alert = app.alerts.firstMatch
        wait(alert)
        let field = alert.textFields.firstMatch
        replaceText(of: field, with: "Bugs")
        confirmAlert(alert, with: "Save")
        wait(element("view-Bugs"))

        element("view-Bugs").press(forDuration: 1.2)
        wait(button("Delete View…"))
        button("Delete View…").tap()
        let confirm = app.alerts.firstMatch
        wait(confirm)
        confirmAlert(confirm, with: "Delete View")
        waitGone(element("view-Bugs"))
        wait(element("view-By Area"))
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
