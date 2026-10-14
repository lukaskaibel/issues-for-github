import XCTest

/// Milestones, epics and the roadmap on the iPhone, on the sample data: the board "Git Issues" has milestones 0.3
/// (due in 9 days, the current one), 0.4 and 1.0, and epics #40 to #44.
final class PhonePlanningTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone layout")
    }

    private func openMilestone(_ title: String) {
        app.tabBars.buttons["Projects"].tap()
        let row = element("milestone-\(title)")
        wait(row)
        row.tap()
        wait(app.navigationBars[title])
    }

    private func openRoadmap() {
        app.tabBars.buttons["Projects"].tap()
        let row = element("roadmap-Git Issues")
        wait(row)
        row.tap()
        wait(app.navigationBars["Roadmap"])
    }

    func testTheNextMilestonesAndTheRoadmapAreUnderTheirBoard() {
        launch()
        app.tabBars.buttons["Projects"].tap()
        wait(element("milestone-0.3"))
        wait(element("milestone-0.4"))
        wait(element("roadmap-Git Issues"))
        // Only the next two; the roadmap has the rest.
        XCTAssertFalse(element("milestone-1.0").exists)
        // Completed milestones don't show.
        XCTAssertFalse(element("milestone-0.2").exists)
        snapshot("Projects with milestones")
    }

    func testAMilestoneListsItsIssuesByEpic() {
        launch()
        openMilestone("0.3")
        wait(labelled("Board polish"))
        wait(element("section-Drag and drop on the board"))
        wait(element("row-#9"))
        // Epics are planned on the roadmap, not listed with the work.
        XCTAssertFalse(element("row-#40").exists)
        // In its epic's group, an issue doesn't name the epic again, nor the milestone it is in.
        XCTAssertFalse(element("row-#9").label.contains("Epic:"), element("row-#9").label)
        XCTAssertFalse(element("row-#9").label.contains("Milestone:"), element("row-#9").label)
        snapshot("Milestone 0.3")
        scrollTo(element("section-Offline-first sync"))
        wait(element("section-Offline-first sync"))
        scrollTo(element("section-No epic"))
        wait(element("section-No epic"))
        snapshot("Milestone 0.3, no epic")
    }

    func testTheRoadmapListsEpicsByTheirNextMilestone() {
        launch()
        openRoadmap()
        wait(element("section-0.3"))
        wait(element("row-#40"))
        wait(element("row-#41"))
        wait(element("section-0.4"))
        wait(element("row-#42"))
        snapshot("Roadmap list")
        scrollTo(element("section-Later"))
        wait(element("section-Later"))
        wait(element("row-#44"))
        snapshot("Roadmap list, later")
    }

    func testAnEpicShowsItsWorkByMilestone() {
        launch()
        openRoadmap()
        element("row-#40").tap()
        wait(element("issue-title"))
        wait(labelled("Progress"))
        // Where its issues are planned, a part per milestone.
        wait(element("chip-milestone"))
        snapshot("Epic")
        scrollTo(labelled("Drag cards between columns"))
        wait(labelled("Drag cards between columns"))
        snapshot("Epic, its issues")
    }

    func testTheMilestoneChipMovesAnIssue() {
        launch()
        openMilestone("0.3")
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        let chip = element("chip-milestone")
        wait(chip)
        waitForLabel(chip, containing: "0.3")
        chip.tap()
        let row = pickerRow("0.4")
        wait(row)
        snapshot("Milestone sheet")
        row.tap()
        waitGone(app.navigationBars["Milestone"])
        waitForLabel(chip, containing: "0.4")
        goBack()
        wait(app.navigationBars["0.3"])
        waitGone(element("row-#17"))
    }

    func testTheLongPressMenuSetsAMilestoneAndMakesAnEpic() {
        launch()
        let row = element("row-#17")
        scrollTo(row)
        wait(row)
        row.press(forDuration: 1.2)
        let milestone = labelled("Milestone", type: .button)
        wait(milestone)
        milestone.tap()
        wait(button("1.0"))
        snapshot("Milestone submenu")
        button("1.0").tap()
        waitForLabel(element("row-#17"), containing: "Milestone: 1.0")

        element("row-#17").press(forDuration: 1.2)
        button("Add to Epic…").tap()
        let epic = pickerRow("#43")
        wait(epic)
        epic.tap()
        waitForLabel(element("row-#17"), containing: "Epic: Ready for 1.0")

        // An epic leaves My Issues for the roadmap.
        element("row-#17").press(forDuration: 1.2)
        wait(button("Make Epic"))
        button("Make Epic").tap()
        waitGone(element("row-#17"))
    }

    func testANewIssueInAMilestoneStartsThere() {
        launch()
        openMilestone("0.3")
        element("compose-button").tap()
        let title = element("new-title")
        wait(title)
        waitForLabel(element("new-milestone"), containing: "0.3")
        title.typeText("Haptics when a card lands")
        snapshot("New issue in a milestone")
        button("Create").tap()
        waitGone(title)
        let row = labelled("Haptics when a card lands")
        scrollTo(row)
        wait(row)
    }

    func testANewEpicFromTheRoadmap() {
        launch()
        openRoadmap()
        element("roadmap-add").tap()
        button("New Epic").tap()
        let title = element("new-title")
        wait(title)
        wait(app.navigationBars["New Epic"])
        title.typeText("Widgets")
        button("Create").tap()
        waitGone(title)
        let row = labelled("Widgets")
        scrollTo(row)
        wait(row)
    }

    func testANewMilestoneFromTheRoadmapShowsThere() {
        launch()
        openRoadmap()
        element("roadmap-add").tap()
        button("New Milestone…").tap()
        let name = element("milestone-name")
        wait(name)
        name.typeText("0.5")
        snapshot("New milestone")
        button("Create").tap()
        waitGone(name)
        let section = element("section-0.5")
        scrollTo(section)
        wait(section)
    }

    func testRenamingAMilestoneKeepsItsScreen() {
        launch()
        openMilestone("0.4")
        app.navigationBars.buttons["Milestone options"].tap()
        button("Edit Milestone…").tap()
        let name = element("milestone-name")
        wait(name)
        name.tap()
        replaceText(of: name, with: "0.4 Teams")
        button("Save").tap()
        waitGone(name)
        wait(app.navigationBars["0.4 Teams"])
    }

    func testAnEpicsIssuesStandTogetherUnderItsHeaderFoldAndOpenIt() {
        launch()
        openProjectTab("Git Issues")
        element("section-In Review").tap()
        waitGone(element("row-#5"))
        let header = element("epic-group-Offline-first sync")
        wait(header)
        XCTAssertTrue(header.label.contains("2 issues"), header.label)
        let first = element("row-#8")
        let second = element("row-#15")
        wait(second)
        XCTAssertGreaterThan(first.frame.minY, header.frame.maxY - 1)
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
        // Under the epic's header, a row doesn't name the epic again.
        XCTAssertFalse(first.label.contains("Epic:"), first.label)
        // A single issue of an epic stands alone and names it.
        scrollTo(element("row-#24"))
        XCTAssertTrue(element("row-#24").label.contains("Epic: Drag and drop on the board"), element("row-#24").label)
        app.swipeDown()
        snapshot("An epic's issues under its header")

        // The arrow folds them away; the header itself opens the epic.
        let fold = element("fold-epic-Offline-first sync")
        fold.tap()
        waitGone(first)
        waitGone(second)
        waitForValue(header, equalTo: "Folded")
        snapshot("An epic's issues folded")
        fold.tap()
        wait(first)
        header.tap()
        let title = element("issue-title")
        wait(title)
        XCTAssertEqual(title.value as? String, "Offline-first sync")
    }

    /// The header's menu moves all of the epic's issues in the section to another status, and the message takes it
    /// back.
    func testAnEpicsHeaderMovesItsIssuesToAnotherStatus() {
        launch()
        openProjectTab("Git Issues")
        let header = element("epic-group-Offline-first sync")
        wait(header)
        openCardMenu(header, showing: "Move Issues To")
        button("Move Issues To").tap()
        button("In Review").tap()
        closedCardMenu()
        let undo = element("notice-undo")
        wait(undo)
        snapshot("An epic's issues moved to In Review")
        // In Review has #6 of the epic already: the three stand together there, and In Progress has none left.
        waitForLabel(header, containing: "3 issues")
        XCTAssertTrue(element("row-#8").label.contains("In Review"), element("row-#8").label)
        XCTAssertTrue(element("row-#15").label.contains("In Review"), element("row-#15").label)
        undo.tap()
        waitForLabel(header, containing: "2 issues")
        XCTAssertTrue(element("row-#8").label.contains("In Progress"), element("row-#8").label)
    }

    func testAnIssueDroppedAmongAnEpicsIssuesJoinsTheEpic() {
        launch()
        openProjectTab("Git Issues")
        element("section-In Review").tap()
        waitGone(element("row-#5"))
        let moving = element("row-#7")
        let below = element("row-#15")
        wait(below)
        // Between #8 and #15, which stand under Offline-first sync. Once #7 is lifted, the rows below it close up
        // by its height, so the finger aims that much higher.
        let start = moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: below.frame.midX, dy: below.frame.minY - moving.frame.height + 12))
        start.press(forDuration: 0.6, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        let header = element("epic-group-Offline-first sync")
        waitForLabel(header, containing: "3 issues")
        XCTAssertGreaterThan(moving.frame.minY, header.frame.maxY - 1)
        snapshot("#7 joined Offline-first sync")
        moving.tap()
        wait(element("chip-parent"))
        waitForLabel(element("chip-parent"), containing: "Offline-first sync")
    }

    func testCompletingAMilestoneMovesWhatIsLeftAndCanBeUndone() {
        launch()
        openMilestone("0.3")
        app.navigationBars.buttons["Milestone options"].tap()
        button("Complete Milestone…").tap()
        let alert = app.alerts["Complete 0.3?"]
        wait(alert)
        snapshot("Complete milestone")
        confirmAlert(alert, with: "Move Unfinished to 0.4")
        // The screen goes on to where the work went.
        wait(app.navigationBars["0.4"])
        wait(element("row-#9"))
        let undo = element("notice-undo")
        wait(undo)
        snapshot("Milestone completed")
        undo.tap()
        waitGone(element("row-#9"))
        goBack()
        wait(element("milestone-0.3"))
    }
}

/// Milestones, epics and the roadmap on the iPad: in the sidebar under their board, the milestone's board, and the
/// roadmap's timeline.
final class PadPlanningTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout")
    }

    private func openSidebarEntry(_ title: String) {
        let entry = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        wait(entry)
        entry.tap()
    }

    func testAMilestoneShowsTheBoardsColumns() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openSidebarEntry("0.3")
        wait(element("column-In Progress"))
        wait(element("card-#9"))
        wait(labelled("Board polish"))
        // Epics and the work of other milestones aren't on it.
        XCTAssertFalse(element("card-#40").exists)
        XCTAssertFalse(element("card-#14").exists)
        snapshot("iPad milestone board")

        app.segmentedControls.buttons["List"].tap()
        wait(element("section-Drag and drop on the board"))
        snapshot("iPad milestone list")
        app.segmentedControls.buttons["Board"].tap()
        wait(element("card-#9"))
    }

    func testTheRoadmapTimeline() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openSidebarEntry("Roadmap")
        let epic = app.buttons["Sign-in and accounts"]
        wait(epic)
        XCTAssertTrue((epic.value as? String ?? "").hasPrefix("0.4"), String(describing: epic.value))
        snapshot("iPad roadmap timeline")

        app.segmentedControls.buttons["List"].tap()
        wait(element("section-0.4"))
        snapshot("iPad roadmap list")
        app.segmentedControls.buttons["Timeline"].tap()
        wait(app.buttons["Sign-in and accounts"])
    }

    /// Dragging an epic's bar onto another milestone moves the epic and its unfinished issues there.
    func testDraggingAnEpicsBarMovesItToAnotherMilestone() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openSidebarEntry("Roadmap")
        let epic = app.buttons["Sign-in and accounts"]
        wait(epic)
        // The sample's open milestones run from 11 days ago to 58 days ahead: 0.3 until day 9, 0.4 until day 30,
        // 1.0 until day 58. The timeline fills the width beside the names.
        let before = epic.value as? String
        let left = epic.frame.maxX + 1
        let right = app.windows.firstMatch.frame.maxX
        let y = epic.frame.midY
        func point(day: Double) -> XCUICoordinate {
            let x = left + (right - left) * CGFloat((day + 11) / 70)
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        }
        point(day: 20).press(forDuration: 0.3, thenDragTo: point(day: 45), withVelocity: .slow, thenHoldForDuration: 0.3)
        waitForValue(epic, notEqualTo: before)
        XCTAssertTrue((epic.value as? String ?? "").hasPrefix("1.0"), String(describing: epic.value))
        let undo = element("notice-undo")
        wait(undo)
        snapshot("iPad epic moved")
        undo.tap()
        let restored = NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String)?.hasPrefix("0.4") == true }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: restored, object: epic)], timeout: 6), .completed)
    }

    func testCompletingTheMilestoneOnScreenGoesOnToTheNext() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openSidebarEntry("0.3")
        wait(element("card-#9"))
        app.navigationBars.buttons["Milestone options"].tap()
        button("Complete Milestone…").tap()
        let alert = app.alerts["Complete 0.3?"]
        wait(alert)
        confirmAlert(alert, with: "Move Unfinished to 0.4")
        // The window goes on to 0.4, with what was left of 0.3; 0.3 leaves the sidebar and 1.0 comes in after 0.4.
        wait(app.navigationBars["0.4"])
        waitGone(app.cells.matching(NSPredicate(format: "label == %@", "0.3")).firstMatch)
        wait(app.cells.matching(NSPredicate(format: "label == %@", "1.0")).firstMatch)
        wait(element("card-#9"))
        wait(element("card-#14"))
        XCTAssertFalse(element("card-#18").exists, "1.0's work isn't on 0.4's board")
        snapshot("iPad after completing 0.3")
    }

    func testAnEpicsCardsStandTogetherInTheColumn() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        let header = element("epic-group-Offline-first sync")
        wait(header)
        let first = element("card-#8")
        let second = element("card-#15")
        wait(second)
        // Under the header, one level in.
        XCTAssertGreaterThan(first.frame.minY, header.frame.maxY - 1)
        XCTAssertGreaterThan(first.frame.minX, header.frame.minX + 8)
        XCTAssertEqual(first.frame.minX, second.frame.minX, accuracy: 1)
        snapshot("iPad epic group")

        // The arrow folds them away; the header itself opens the epic.
        let fold = element("fold-epic-Offline-first sync")
        fold.tap()
        waitGone(first)
        waitGone(second)
        fold.tap()
        wait(first)
        header.tap()
        let title = element("issue-title")
        wait(title)
        XCTAssertEqual(title.value as? String, "Offline-first sync")
    }

    /// Dragging the header over an epic's cards moves them all to the column it is dropped on, and the message
    /// takes it back.
    func testDraggingAnEpicsHeaderMovesItsCards() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        let header = element("epic-group-Offline-first sync")
        let first = element("card-#8")
        let target = element("card-#16")
        wait(header)
        wait(first)
        wait(target)
        let from = first.frame
        // Onto In Review, below #16; In Review has #6 of the epic already, which the cards join. A pointer lifts
        // the header without its menu.
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .click(forDuration: 0.3, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        let undo = element("notice-undo")
        wait(undo)
        waitForLabel(header, containing: "3 issues")
        XCTAssertGreaterThan(first.frame.minX, from.maxX, "#8 went to the column on the right")
        XCTAssertEqual(element("card-#15").frame.minX, first.frame.minX, accuracy: 1)
        snapshot("iPad epic's cards moved")
        undo.tap()
        waitForLabel(header, containing: "2 issues")
        XCTAssertEqual(first.frame.minX, from.minX, accuracy: 1)
    }

    func testACardDroppedAmongAnEpicsCardsJoinsTheEpic() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        let card = element("card-#7")
        let below = element("card-#15")
        wait(card)
        wait(below)
        // Between #8 and #15, which stand under Offline-first sync. On its way the gap opens above the epic's header
        // first and pushes the group down, so the pointer aims at the lower part of #15, which is then where the gap
        // between #8 and #15 opens. A pointer lifts the card without its menu, which a short drag by finger can't leave.
        let target = below.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.3, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        let header = element("epic-group-Offline-first sync")
        waitForLabel(header, containing: "3 issues")
        waitForLabel(element("card-#7"), containing: "Epic: Offline-first sync")
        snapshot("iPad card joined an epic")
    }

    func testCommandFourOpensTheRoadmap() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openPadProject("Git Issues")
        wait(element("card-#9"))
        app.typeKey("4", modifierFlags: .command)
        wait(app.buttons["Sign-in and accounts"])
    }
}
