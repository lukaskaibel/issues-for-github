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

    func testMyIssuesFiltersGroupsAndOrders() {
        launch()
        wait(app.navigationBars["My Issues"])
        wait(element("row-#8"))
        // Most urgent first, also across projects: #9 (Urgent) before #8 (High) in In progress.
        XCTAssertLessThan(element("row-#9").frame.minY, element("row-#8").frame.minY)

        // Grouped by project from the "…" menu; the issues on no board lead.
        app.navigationBars.buttons["Options"].firstMatch.tap()
        wait(button("Group by"))
        button("Group by").tap()
        wait(button("Project"))
        button("Project").tap()
        wait(element("section-No project"))
        wait(element("section-Git Issues"))
        snapshot("My Issues by project")

        // Only what is urgent, whatever each project calls it.
        app.navigationBars.buttons["Options"].firstMatch.tap()
        wait(button("Filter…"))
        button("Filter…").tap()
        wait(app.navigationBars["Filter"])
        button("Add Filter").tap()
        wait(app.navigationBars["Add Filter"])
        button("Priority").tap()
        wait(app.navigationBars["Priority"])
        let urgent = pickerRow("Urgent")
        wait(urgent)
        snapshot("My Issues filter values")
        urgent.tap()
        goBack()
        goBack()
        button("Done").tap()
        waitForValue(element("my-issues-filter"), equalTo: "Priority is Urgent")
        wait(element("row-#9"))
        waitGone(element("row-#8"))
        snapshot("My Issues, only urgent")

        // One tap on the filter line, Clear Filter, and everything is back.
        element("my-issues-filter").tap()
        wait(button("Clear Filter"))
        button("Clear Filter").tap()
        button("Done").tap()
        waitGone(element("my-issues-filter"))
        scrollTo(element("row-#8"))
        wait(element("row-#8"))

        // Reset goes back to groups by status.
        app.navigationBars.buttons["Options"].firstMatch.tap()
        wait(button("Reset"))
        button("Reset").tap()
        wait(element("section-In progress"))
    }

    func testIssuesMoveWithinTheirSection() {
        launch()
        openProjectTab("Git Issues")
        // The board view, as a list.
        showLayout("List")
        // With In Review folded, all of In Progress is on screen without scrolling.
        element("section-In Review").tap()
        waitGone(element("row-#5"))
        // #8 and #15 stand together under their epic, Offline-first sync.
        let top = element("row-#8")
        let moving = element("row-#15")
        wait(moving)
        XCTAssertTrue(moving.isHittable)
        XCTAssertGreaterThan(moving.frame.minY, top.frame.minY)
        // Touch and hold, then drag it above #8. Moving soon after the row lifts makes it a drag; holding still
        // until the menu is fully open keeps the menu instead.
        let start = moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.6, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in moving.frame.minY < top.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 4), .completed, "#15 is above #8")
        snapshot("Moved #15 to the top of its epic's issues")
        XCTAssertTrue(moving.label.contains("In Progress"), moving.label)
        // Still under the epic's header.
        XCTAssertGreaterThan(moving.frame.minY, element("epic-group-Offline-first sync").frame.maxY - 1)
    }

    func testSubIssuesHangUnderTheirParentAndFold() {
        launch()
        openProjectTab("Git Issues")
        // The board view, as a list.
        showLayout("List")
        element("section-In Review").tap()
        waitGone(element("row-#5"))
        let parent = element("row-#9")
        let child = element("row-#13")
        wait(child)
        // Both are in progress, so #13 hangs right under #9.
        XCTAssertEqual(child.frame.minY, parent.frame.maxY, accuracy: 2)
        XCTAssertTrue(child.label.contains("Sub-issue of #9"), child.label)
        snapshot("Sub-issues under their parent")

        element("fold-#9").tap()
        waitGone(element("row-#13"))
        waitGone(element("row-#28"))
        waitForLabel(parent, containing: "Show 2 sub-issues")
        snapshot("Sub-issues folded")
        element("fold-#9").tap()
        wait(element("row-#13"))
        wait(element("row-#28"))
    }

    func testFinishingTheLastSubIssueFinishesItsParent() {
        launch()
        openProjectTab("Git Issues")
        // The board view, as a list.
        showLayout("List")
        element("section-In Review").tap()
        waitGone(element("row-#5"))
        for number in ["#13", "#28"] {
            let row = element("row-\(number)")
            scrollTo(row)
            row.swipeRight()
            wait(button("Done"))
            // Scrolled up under its section's header, the row's Done is covered: bring it down and swipe again.
            if !button("Done").isHittable {
                app.swipeDown(velocity: .slow)
                row.swipeRight()
                wait(button("Done"))
            }
            button("Done").tap()
            waitGone(button("Done"))
        }
        wait(labelled("All sub-issues done, so #9 is done too"))
        snapshot("Parent done with its sub-issues")
        let parent = element("row-#9")
        scrollTo(parent)
        waitForLabel(parent, containing: "Done")
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
        // Below #27 and #38, which are on no board and lead My Issues.
        scrollTo(element("row-#13"))
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
        // Below #27 and #38, which are on no board and lead My Issues.
        scrollTo(element("row-#13"))
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
        // Below #27 and #38, which are on no board and lead My Issues.
        scrollTo(element("row-#13"))
        element("row-#13").tap()
        wait(element("chip-assignee"))
        element("chip-assignee").tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        search.typeText("mira")
        let mira = pickerRow("mira")
        wait(mira)
        snapshot("Assignee sheet")
        // A tap picks and closes the sheet.
        mira.tap()
        waitGone(app.navigationBars["Assignee"])
        waitForLabel(element("chip-assignee"), containing: "mira")

        // The circle picks without closing, for picking several.
        element("chip-labels").tap()
        let bug = element("check-bug")
        wait(bug)
        bug.tap()
        snapshot("Labels sheet, one picked with its circle")
        XCTAssertTrue(app.navigationBars["Labels"].exists, "The sheet stays open")
        pickerRow("sync").tap()
        waitGone(app.navigationBars["Labels"])
        waitForLabel(element("chip-labels"), containing: "bug")
        waitForLabel(element("chip-labels"), containing: "sync")
    }

    func testTypingALabelTheRepositoryLacksMakesIt() {
        launch()
        scrollTo(element("row-#13"))
        element("row-#13").tap()
        wait(element("chip-labels"))
        element("chip-labels").tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        // A label of that name, whatever its case, is picked rather than made again.
        search.typeText("SYNC")
        wait(pickerRow("sync"))
        XCTAssertFalse(pickerRow("Create label").exists)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "perf")
        let create = pickerRow("Create label “perf”")
        wait(create)
        XCTAssertFalse(element("check-Create label “perf”").exists, "Making a label has no circle")
        snapshot("Labels sheet, a label to make")
        create.tap()
        waitGone(app.navigationBars["Labels"])
        waitForLabel(element("chip-labels"), containing: "perf")
        // Made in the repository, it is one of its labels from now on.
        element("chip-labels").tap()
        wait(search)
        search.tap()
        search.typeText("perf")
        wait(pickerRow("perf"))
        XCTAssertFalse(pickerRow("Create label").exists)
    }

    func testRecentChoicesComeFirst() {
        // As if "sync" had just been added to another issue: it leads the sheet, apart from the rest.
        launch(["-recentPicks", "{ label = (sync); }"])
        scrollTo(element("row-#13"))
        element("row-#13").tap()
        wait(element("chip-labels"))
        element("chip-labels").tap()
        let sync = pickerRow("sync")
        wait(sync)
        XCTAssertLessThan(sync.frame.minY, pickerRow("auth").frame.minY, "The label picked last comes first")
        snapshot("Labels sheet with the recent one first")

        // Picking several keeps the rows where they are, although "bug" is now the latest choice.
        let place = pickerRow("bug").frame.minY
        element("check-bug").tap()
        _ = XCTWaiter.wait(for: [expectation(description: "The list settles")], timeout: 0.8)
        XCTAssertEqual(pickerRow("bug").frame.minY, place, accuracy: 1, "A picked row stays put")
        XCTAssertLessThan(sync.frame.minY, pickerRow("bug").frame.minY)
    }

    func testDueDateSheet() {
        launch()
        // Below #27 and #38, which are on no board and lead My Issues.
        scrollTo(element("row-#13"))
        element("row-#13").tap()
        let chip = element("chip-due")
        wait(chip)
        waitForLabel(chip, containing: "none")
        func day(_ offset: Int) -> String {
            Calendar.current.date(byAdding: .day, value: offset, to: Date())!
                .formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(appLocale))
        }

        chip.tap()
        let tomorrow = labelled("Tomorrow", type: .button)
        wait(tomorrow)
        snapshot("Due date sheet")
        tomorrow.tap()
        waitForLabel(chip, containing: day(1))

        // A date typed in a few words.
        chip.tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        search.typeText("in 3")
        let found = labelled("In 3 days", type: .button)
        wait(found)
        snapshot("Due date typed")
        found.tap()
        waitForLabel(chip, containing: day(3))

        chip.tap()
        let remove = button("Remove Due Date")
        scrollTo(remove, in: app.collectionViews.firstMatch)
        remove.tap()
        waitForLabel(chip, containing: "none")
    }

    func testDescriptionEditsInPlace() {
        launch()
        wait(element("row-#9"))
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        let description = element("issue-description")
        wait(description)
        description.tap()
        // The bar above the keyboard, with Done in reach.
        let done = element("writing-bar-done")
        wait(done)
        app.typeText("Rank matches by **how close** they are.")
        // Typed this fast, iOS takes the keys for a hardware keyboard's and puts the on-screen one away for a moment,
        // the bar going down with it: tap once it is back.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        snapshot("Editing a description")
        // Undo and redo in the bar take back the typing and bring it back.
        button("Undo").tap()
        waitForValue(description, lacking: "they are.")
        button("Redo").tap()
        waitForValue(description, containing: "they are.")
        done.tap()
        waitGone(done)
        goBack()
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        wait(element("issue-description"))
        XCTAssertTrue(((element("issue-description").value as? String) ?? "").contains("Rank matches by **how close** they are."))
    }

    func testTypingMarkdownInADescription() {
        launch()
        wait(element("row-#9"))
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        let description = element("issue-description")
        wait(description)
        description.tap()
        let done = element("writing-bar-done")
        wait(done)

        // Bold from the bar; inside it a second Bold comes in on the left, which leaves it.
        button("Bold").tap()
        app.typeText("bold")
        let bold = app.buttons.matching(NSPredicate(format: "label == 'Bold'"))
        wait(bold.element(boundBy: 1))
        XCTAssertEqual(bold.count, 2)
        bold.element(boundBy: 0).tap()
        // "-" starts a bullet, Return continues the list and ends it on an empty item, "[]" makes a checkbox.
        app.typeText(" text\n-item\n\n-[]todo")
        waitForValue(description, equalTo: "**bold** text\n- item\n- [ ] todo")
        snapshot("Typing Markdown")

        // The checkbox of the caret's line ticks from the bar.
        button("Checkbox").tap()
        waitForValue(description, equalTo: "**bold** text\n- item\n- [x] todo")

        // Saved: drawn as a checklist when the issue opens again, the box ticked.
        done.tap()
        waitGone(done)
        goBack()
        scrollTo(element("row-#17"))
        element("row-#17").tap()
        let box = app.buttons["todo"]
        wait(box)
        XCTAssertEqual(box.value as? String, "Checked")
    }

    func testDescriptionTicksBoxesAndFormatsInPlace() {
        launch()
        wait(element("row-#9"))
        scrollTo(element("row-#16"))
        element("row-#16").tap()
        // A checklist, an alert, a table and a diagram, drawn as on GitHub, with boxes that tick.
        let box = app.buttons["Images pasted from the clipboard"]
        wait(box)
        XCTAssertEqual(box.value as? String, "Unchecked")
        box.tap()
        waitForValue(box, equalTo: "Checked")
        snapshot("Description drawn as on GitHub")
        let text = element("issue-description")
        XCTAssertTrue(((text.value as? String) ?? "").contains("- [x] Images pasted from the clipboard"))
        XCTAssertFalse(element("writing-bar-done").exists, "ticking a box doesn't bring up the keyboard")

        // A tap in the first line puts the caret there; the Format panel turns the line into a heading.
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.01)).tap()
        let done = element("writing-bar-done")
        wait(done)
        button("Format").tap()
        let heading = button("Heading")
        wait(heading)
        heading.tap()
        waitForValue(text, containing: "## Write Markdown")
        snapshot("Format panel")
        button("Close").tap()
        wait(done)
        done.tap()
        waitGone(done)
        XCTAssertEqual(box.value as? String, "Checked")
    }

    func testCommentsAndSubIssues() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))
        snapshot("Issue #9 with sub-issues")

        // A sub-issue's status circle shows its board's columns; picking one moves it, and another moves it back.
        let status = element("sub-status-#13")
        scrollTo(status)
        wait(status)
        status.tap()
        wait(button("Done"))
        snapshot("Sub-issue status menu")
        button("Done").tap()
        waitForLabel(element("sub-status-#13"), containing: "Done")
        element("sub-status-#13").tap()
        wait(button("In Progress"))
        button("In Progress").tap()
        waitForLabel(element("sub-status-#13"), containing: "In Progress")

        let field = element("comment-field")
        wait(field)
        field.tap()
        field.typeText("Let's ship this on Friday.")
        element("comment-send").tap()
        let comment = textShowing("Let's ship this on Friday.")
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
        button("New Sub-issue").tap()
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

    func testExistingIssueBecomesSubIssueAndBlocker() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))

        // The plus beside the sub-issues finds an issue that exists already, by its number.
        let add = element("sub-add")
        scrollTo(add)
        add.tap()
        button("Add Existing Issue…").tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        search.typeText("17")
        let palette = labelled("Command palette with fuzzy search", type: .button)
        wait(palette)
        snapshot("Existing issue as sub-issue")
        palette.tap()
        let sub = element("sub-#17")
        scrollTo(sub)
        wait(sub)

        // Marked as blocked by #6 from the issue's menu, it lists #6 under Blocked by.
        app.navigationBars.buttons["More"].tap()
        button("Mark As").tap()
        button("Blocked By…").tap()
        let blockerSearch = app.searchFields.firstMatch
        wait(blockerSearch)
        blockerSearch.tap()
        blockerSearch.typeText("Delta")
        let delta = labelled("Delta sync for project items", type: .button)
        wait(delta)
        delta.tap()
        let blocker = element("link-#6")
        scrollTo(blocker)
        wait(blocker)
        snapshot("Blocked by")
    }

    func testIssueMenuCopiesLinkAndDeletes() {
        launch()
        // Below #27 and #38, which are on no board and lead My Issues.
        scrollTo(element("row-#13"))
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
        // Below #27 and #38, which are on no board and lead My Issues.
        scrollTo(element("row-#13"))
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
        wait(element("sub-status-#10"))

        // A sub-issue's own menu, from a long press.
        let row = element("sub-#11")
        scrollTo(row)
        row.press(forDuration: 1.2)
        wait(button("Status"))
        snapshot("Sub-issue menu")
        button("Status").tap()
        button("In Progress").tap()
        waitForLabel(element("sub-status-#11"), containing: "In Progress")
    }

    func testPickSeveralSubIssuesAndChangeThemTogether() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))

        // Select, in the "…" beside the plus, puts circles in place of the status circles; a tap then picks a
        // sub-issue instead of opening it.
        let options = element("sub-options")
        scrollTo(options)
        options.tap()
        wait(button("Select"))
        snapshot("Sub-issue options")
        button("Select").tap()
        wait(element("sub-pick-done"))
        XCTAssertFalse(element("comment-field").exists, "The bar for the picked ones stands where the comment field was")
        clearOfPickBar(element("sub-#12"))
        element("sub-#10").tap()
        element("sub-#11").tap()
        wait(labelled("2 selected"))
        XCTAssertTrue(element("sub-#10").isSelected)
        XCTAssertFalse(element("sub-#12").isSelected)
        snapshot("Picking sub-issues")

        // The long-press menu of a picked one changes both.
        element("sub-#11").press(forDuration: 1.2)
        wait(labelled("2 issues"))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "No on-screen keyboard comes up with the menu")
        snapshot("Menu of two picked sub-issues")
        XCTAssertFalse(button("Open Issue").exists)
        button("Status").tap()
        button("In Progress").tap()
        element("sub-pick-done").tap()
        waitGone(element("sub-pick-done"))
        wait(element("comment-field"))
        waitForLabel(element("sub-status-#10"), containing: "In Progress")
        waitForLabel(element("sub-status-#11"), containing: "In Progress")

        // Select from a row's own menu starts with that row picked; the bar at the foot moves them under another
        // parent, and with all of them gone from the list the picking ends.
        element("sub-#12").press(forDuration: 1.2)
        button("Select").tap()
        wait(element("sub-pick-done"))
        clearOfPickBar(element("sub-#23"))
        element("sub-#23").tap()
        wait(labelled("2 selected"))
        element("sub-pick-parent").tap()
        let search = app.searchFields.firstMatch
        wait(search)
        search.tap()
        search.typeText("Offline")
        let epic = labelled("Offline-first sync", type: .button)
        wait(epic)
        epic.tap()
        waitGone(element("sub-#12"))
        waitGone(element("sub-#23"))
        waitGone(element("sub-pick-done"))
        XCTAssertTrue(element("sub-#13").exists, "The others stay")

        // Select All, then none.
        scrollTo(options)
        options.tap()
        button("Select").tap()
        element("sub-pick-all").tap()
        wait(labelled("4 selected"))
        XCTAssertEqual(element("sub-pick-all").label, "Deselect All")
        element("sub-pick-all").tap()
        wait(labelled("0 selected"))
        // The bar settles with Select All back in place before ✓ ends the picking.
        waitForLabel(element("sub-pick-all"), containing: "Select All")
        element("sub-pick-done").tap()
        waitGone(element("sub-pick-done"), 10)
    }

    func testPickSubIssuesOfAnEpic() {
        launch()
        scrollTo(element("row-#8"))
        element("row-#8").tap()
        let parent = element("chip-parent")
        wait(parent)
        parent.tap()

        // An epic lists its issues by milestone; picking works across them, and "…" at the foot changes all.
        let options = element("sub-options")
        scrollTo(options)
        options.tap()
        button("Select").tap()
        clearOfPickBar(element("sub-#4"))
        element("sub-#8").tap()
        element("sub-#15").tap()
        wait(labelled("2 selected"))
        snapshot("Picking an epic's sub-issues")
        element("sub-pick-more").tap()
        wait(labelled("2 issues"))
        button("Priority").tap()
        button("Low").tap()
        element("sub-pick-done").tap()
        waitGone(element("sub-pick-done"))
        element("sub-#15").tap()
        waitForLabel(element("chip-priority"), containing: "Low")
    }

    func testPickASubIssueUnfoldedUnderAnother() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))
        // #13's own sub-issues unfold under it; one of them is picked with one listed in #9 itself.
        let fold = element("sub-fold-#13")
        scrollTo(fold)
        fold.tap()
        wait(element("sub-#29"))
        element("sub-options").tap()
        button("Select").tap()
        clearOfPickBar(element("sub-#28"))
        XCTAssertTrue(element("sub-fold-#13").exists, "The arrow stays while picking")
        element("sub-#29").tap()
        element("sub-#28").tap()
        wait(labelled("2 selected"))
        snapshot("Picking a sub-issue of a sub-issue")
        // #29 is on no board, so its menu offers Add to Project in place of Status; Assign to Me suits both.
        element("sub-#29").press(forDuration: 1.2)
        wait(labelled("2 issues"))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "No on-screen keyboard comes up with the menu")
        snapshot("Menu of a picked sub-issue of a sub-issue")
        button("Assign to Me").tap()
        element("sub-pick-done").tap()
        waitGone(element("sub-pick-done"))
        element("sub-#29").tap()
        waitForLabel(element("chip-assignee"), containing: "jordan")
    }

    /// Moves the page up a little until the sub-issue is clear of the bar that picking brings at the foot.
    private func clearOfPickBar(_ row: XCUIElement) {
        let bar = element("sub-pick-parent")
        wait(bar)
        var drags = 0
        while row.frame.maxY > bar.frame.minY - 16, drags < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            drags += 1
        }
    }

    func testSubIssuesOfASubIssueUnfoldUnderIt() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))
        // #13 has sub-issues of its own: it says how far they are, and its arrow unfolds them under it.
        let fold = element("sub-fold-#13")
        scrollTo(fold)
        wait(fold)
        waitForLabel(element("sub-#13"), containing: "1 of 2 sub-issues done")
        XCTAssertFalse(element("sub-#29").exists)
        fold.tap()
        let child = element("sub-#29")
        wait(child)
        wait(element("sub-#30"))
        snapshot("Sub-issues of a sub-issue")
        // Folded again, they go.
        fold.tap()
        waitGone(child)
        waitGone(element("sub-#30"))
    }

    func testSubIssuesFollowThePickedOrder() {
        launch()
        element("row-#9").tap()
        wait(element("issue-title"))
        let done = element("sub-#23")
        scrollTo(done)
        func isAbove(_ first: String, _ second: String) -> Bool {
            element("sub-#\(first)").frame.minY < element("sub-#\(second)").frame.minY
        }
        // By priority to start with: #13 (Medium) over #28 (Low), and the done ones after both.
        XCTAssertTrue(isAbove("13", "28"))
        XCTAssertTrue(isAbove("28", "10"))

        element("sub-options").tap()
        wait(button("Newest First"))
        snapshot("Sub-issue order")
        button("Newest First").tap()
        waitGone(button("Newest First"))
        // #28 was opened last; the done ones stay at the bottom.
        let newest = expectation(for: NSPredicate { _, _ in isAbove("28", "13") }, evaluatedWith: nil)
        wait(for: [newest], timeout: 6)
        XCTAssertTrue(isAbove("13", "10"))
        snapshot("Sub-issues, newest first")
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

    /// Home, under everything else: the Inbox and My Issues as tiles with their counts, then the projects.
    func testHomeLeadsToTheInboxMyIssuesAndTheProjects() {
        launch(["-mobile.tab", "home"])
        let inbox = element("home-inbox")
        wait(inbox)
        waitForValue(inbox, equalTo: "8")
        wait(labelled("Git Issues", type: .button))
        wait(labelled("Website", type: .button))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        snapshot("Home")

        inbox.tap()
        wait(element("inbox-row-25"))
        goHome()
        element("home-my-issues").tap()
        wait(element("row-#9"))
        goHome()
        labelled("Git Issues", type: .button).tap()
        wait(element("strip-In Progress"))
        // New Issue at the foot starts in the project on screen.
        element("compose-button").tap()
        wait(element("new-title"))
        XCTAssertTrue(labelled("Project: Git Issues", type: .button).exists)
        button("Cancel").tap()
    }

    /// A project opens on its open view, with the project's page under it: Back leads to the page, Back again Home.
    func testAProjectOpensOnItsViewWithItsPageUnderIt() {
        launch(["-mobile.tab", "home"])
        openProjectTab("Git Issues")
        wait(app.navigationBars["Board"])
        wait(element("strip-In Progress"))

        goBack()
        wait(app.navigationBars["Git Issues"])
        wait(element("page-All Issues"))
        wait(element("page-This Week"))
        // One search field and New Issue at the foot, whichever screen is in front.
        XCTAssertEqual(app.searchFields.count, 1)
        snapshot("Project's page")

        element("page-Bugs and Sync").tap()
        wait(app.navigationBars["Bugs and Sync"])
        wait(app.navigationBars.staticTexts["Git Issues"])
        wait(element("row-#25"))
        XCTAssertEqual(app.searchFields.count, 1)
        goBack()
        wait(element("page-Bugs and Sync"))
        goBack()
        wait(element("home-inbox"))

        // Opened again, on the view used last, and still with its page under it.
        openProjectTab("Git Issues")
        wait(app.navigationBars["Bugs and Sync"])
        XCTAssertEqual(app.searchFields.count, 1)
        goBack()
        wait(app.navigationBars["Git Issues"])
    }

    /// A view, a milestone, All Issues or the roadmap pinned from the project's page shows as a tile on Home.
    func testPinnedViewsAndMilestonesAreTilesOnHome() {
        launch(["-mobile.tab", "home"])
        openProjectPage("Git Issues")
        let week = element("page-This Week")
        wait(week)
        week.press(forDuration: 1.2)
        wait(button("Pin"))
        snapshot("Pin in a view's menu")
        button("Pin").tap()
        waitForValue(week, equalTo: "Pinned")

        // A swipe to the right pins too: all the way at once, or with the button it uncovers.
        let milestone = element("page-0.4")
        scrollTo(milestone)
        milestone.swipeRight()
        if button("Pin").waitForExistence(timeout: 2) { button("Pin").tap() }
        waitForValue(milestone, equalTo: "Pinned")

        goBack()
        let tile = element("pin-This Week")
        wait(tile)
        waitForValue(tile, equalTo: "9")
        wait(element("pin-0.4"))
        snapshot("Pins on Home")

        // A tile opens what was pinned, over its project's page.
        tile.tap()
        wait(app.navigationBars["This Week"])
        wait(element("strip-In Progress"))
        goBack()
        wait(app.navigationBars["Git Issues"])

        // And the view's own menu unpins it.
        element("page-This Week").tap()
        wait(app.navigationBars["This Week"])
        app.navigationBars.buttons["Options"].tap()
        wait(button("Unpin"))
        button("Unpin").tap()
        goHome()
        waitGone(element("pin-This Week"))

        // Touch and hold a tile to unpin it there.
        element("pin-0.4").press(forDuration: 1.2)
        wait(button("Unpin"))
        button("Unpin").tap()
        waitGone(element("pin-0.4"))
    }

    func testSearchFindsIssuesAndProjects() {
        launch()
        // The field at the foot of My Issues looks through every project.
        let field = openSearch()
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
        goHome()
        let website = labelled("Website", type: .button)
        wait(website)
        snapshot("Projects")
        website.tap()
        wait(app.navigationBars.staticTexts["Website"])
        // Its board as a list, which offers the field it lacks.
        showLayout("List")
        wait(labelled("No Priority field"))
        snapshot("Website without priority")
        button("Add").tap()
        waitGone(labelled("No Priority field"), 8)

        // Another project is a step further back: its page, then Home.
        goBack()
        wait(app.navigationBars["Website"])
        goBack()
        wait(element("home-inbox"))
        openProjectTab("Git Issues")

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

    func testAllIssuesListsIssuesOnNoBoardAndMakesThem() {
        launch()
        // First on the project's page, with how many open issues of its repository are on no board.
        openProjectPage("Git Issues")
        let all = element("page-All Issues")
        wait(all)
        XCTAssertTrue(all.label.contains("4 on no board"), all.label)
        snapshot("All Issues on the project's page")
        all.tap()
        wait(app.navigationBars["All Issues"])
        // The issues on no board lead, the board's follow.
        wait(element("row-#27"))
        wait(element("row-#5"))
        snapshot("All Issues")

        // A new issue from here goes on the board, or on none.
        element("compose-button").tap()
        let title = element("new-title")
        wait(title)
        let project = labelled("Project: Git Issues", type: .button)
        wait(project)
        project.tap()
        let none = button("No project")
        wait(none)
        none.tap()
        wait(labelled("Project: none", type: .button))
        title.typeText("Crash report from a beta tester")
        button("Create").tap()
        waitGone(title)
        wait(labelled("Crash report from a beta tester"), 8)

        goBack()
        waitForLabel(element("page-All Issues"), containing: "5 on no board")
    }

    func testProjectIconFromTheProjectMenu() {
        launch()
        openProjectTab("Git Issues")
        app.navigationBars.buttons["Options"].tap()
        button("Change Icon…").tap()
        wait(app.navigationBars["Project Icon"])
        // The sample's blue laptop; the laptop is further down, among the devices.
        XCTAssertTrue(button("Blue").isSelected)
        snapshot("Project icon")

        // A colour keeps the sheet open, so a glyph can follow; the glyph, found by its name, closes it.
        button("Orange").tap()
        wait(app.buttons.matching(NSPredicate(format: "label == 'Orange' AND selected == true")).firstMatch)
        XCTAssertTrue(app.navigationBars["Project Icon"].exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("flask")
        wait(button("Flask"))
        snapshot("Project icon, searching")
        // A lone match's button reaches across its row for VoiceOver; the glyph itself is at the start of it.
        button("Flask").images.firstMatch.tap()
        waitGone(app.navigationBars["Project Icon"])

        // A long press on the project on Home opens it too, and the choice is kept.
        goHome()
        labelled("Git Issues", type: .button).press(forDuration: 1)
        button("Change Icon…").tap()
        wait(app.navigationBars["Project Icon"])
        XCTAssertTrue(button("Orange").isSelected)
        snapshot("Project icon, changed")
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("flask")
        wait(button("Flask"))
        XCTAssertTrue(button("Flask").isSelected)
        // Done closes it while searching too, keeping the icon.
        button("Done").tap()
        waitGone(app.navigationBars["Project Icon"])
        snapshot("Projects with the changed icon")
    }

    func testNewIssueInASectionWithEveryProperty() {
        launch()
        openProjectTab("Git Issues")
        // The board view, as a list.
        showLayout("List")
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
        let theo = pickerRow("theo")
        wait(theo)
        theo.tap()
        waitForLabel(element("new-assignee"), containing: "theo")
        element("new-labels").tap()
        let labelSearch = app.searchFields.firstMatch
        wait(labelSearch)
        labelSearch.tap()
        labelSearch.typeText("ui")
        wait(button("ui"))
        button("ui").tap()
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
        wait(textShowing("Cards that land outside a column"))
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

        // The board shows the new statuses.
        goBack()
        wait(element("strip-Review"))
        XCTAssertFalse(element("strip-Backlog").exists)
    }

    func testArrangeSectionsAndReset() {
        launch()
        openProjectTab("Git Issues")
        // The board view, as a list.
        showLayout("List")
        wait(element("section-In Progress"))
        app.navigationBars.buttons["Options"].tap()
        button("Arrange Sections…").tap()
        wait(app.navigationBars["Arrange Sections"])
        // The grips by their names: the list under the sheet has cells named like these.
        let todo = app.buttons["Reorder Todo"]
        let first = app.buttons["Reorder In Review"]
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
        let field = openSearch()
        field.typeText("web")
        let website = labelled("Website", type: .button)
        wait(website)
        website.tap()
        wait(app.navigationBars.staticTexts["Website"])
        wait(element("card-#31"))
    }

    // MARK: Account

    func testAccountAppearanceAndQueue() {
        launch()
        // Your picture is at the top of Home.
        goHome()
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
        wait(element("home-inbox"))
    }

    func testAppIconChoice() {
        launch()
        // Your picture is at the top of Home.
        goHome()
        element("account-button").tap()
        wait(app.navigationBars["Account"])
        let graphite = button("Graphite")
        scrollTo(graphite, in: app.collectionViews.firstMatch)
        wait(graphite)
        graphite.tap()
        confirmIconChange()
        XCTAssertTrue(graphite.isSelected)
        button("Card").tap()
        confirmIconChange()
        XCTAssertTrue(button("Card").isSelected)
    }

    func testLeavingSampleDataShowsSignIn() {
        launch()
        // Your picture is at the top of Home.
        goHome()
        element("account-button").tap()
        wait(app.navigationBars["Account"])
        let leave = button("Leave Sample Data")
        scrollTo(leave, in: app.collectionViews.firstMatch)
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
    /// All Issues in the menu of a project's title, whose second line says how many are on no board.
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
        // Even where a large iPhone is wide, it keeps its one stack and lists, with search at the foot.
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
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
