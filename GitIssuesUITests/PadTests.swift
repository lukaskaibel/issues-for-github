import XCTest

/// The iPad: sidebar, board with drag and drop, the issue beside its properties, and the keyboard.
final class PadTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout")
    }

    /// Puts the on-screen keyboard away with its own key, as a hardware keyboard would never show it.
    private func hideKeyboard() {
        let hide = app.keyboards.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hide keyboard' OR label CONTAINS[c] 'dismiss'")).firstMatch
        wait(hide)
        hide.tap()
        waitGone(app.keyboards.firstMatch)
    }

    private func openProject(_ title: String) {
        let entry = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        wait(entry)
        entry.tap()
        wait(app.navigationBars[title])
    }

    func testSidebarAndBoard() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        wait(element("row-#9"))
        snapshot("iPad My Issues")
        openProject("Git Issues")
        wait(element("column-Todo"))
        wait(element("card-#9"))
        snapshot("iPad board")
    }

    func testDragCardToAnotherColumn() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Git Issues")
        let card = element("card-#17")
        let target = element("column-In Progress")
        wait(card)
        wait(target)
        card.press(forDuration: 1.0, thenDragTo: target)
        snapshot("After drag")
        // The card now opens with its new status.
        element("card-#17").tap()
        wait(element("property-status"))
        waitForLabel(element("property-status"), containing: "In Progress")
        snapshot("iPad issue")
    }

    func testListAndIssueWithProperties() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Git Issues")
        app.segmentedControls.buttons["List"].tap()
        wait(element("row-#9"))
        snapshot("iPad list")
        element("row-#9").tap()
        wait(element("property-status"))
        snapshot("iPad issue with properties")
        app.navigationBars.buttons["Next Issue"].tap()
        wait(element("issue-title"))
    }

    func testKeyboardShortcuts() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        wait(element("row-#9"))
        app.typeKey("n", modifierFlags: .command)
        wait(element("new-title"))
        snapshot("iPad new issue")
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["Cancel"].firstMatch.tap()
        app.typeKey("k", modifierFlags: .command)
        wait(app.searchFields.firstMatch)
        snapshot("iPad search")
    }

    func testColumnMenuRenamesRecoloursMovesAndDeletes() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Git Issues")
        wait(element("column-Todo"))

        app.buttons["Options for Todo"].tap()
        button("Rename…").tap()
        let rename = app.alerts["Rename Status"]
        wait(rename)
        replaceText(of: rename.textFields.firstMatch, with: "Up Next")
        confirmAlert(rename, with: "Rename")
        wait(element("column-Up Next"))

        app.buttons["Options for Up Next"].tap()
        button("Colour").tap()
        wait(button("Blue"))
        snapshot("Column colours")
        button("Blue").tap()

        app.buttons["Options for Up Next"].tap()
        button("Move Left").tap()
        let moved = element("column-Up Next")
        wait(moved)
        XCTAssertLessThan(moved.frame.minX, element("column-Backlog").frame.minX)
        snapshot("Column moved left")

        app.buttons["Options for Up Next"].tap()
        labelled("Delete Status", type: .button).tap()
        let confirm = button("Delete Status")
        wait(confirm)
        confirm.tap()
        waitGone(element("column-Up Next"))

        // A new column at the end of the board.
        let add = app.buttons["Add Status"]
        var swipes = 0
        while !add.isHittable && swipes < 4 {
            element("column-In Review").swipeLeft()
            swipes += 1
        }
        add.tap()
        let alert = app.alerts["New Status"]
        wait(alert)
        alert.textFields.firstMatch.typeText("QA")
        confirmAlert(alert, with: "Add")
        wait(element("column-QA"))
        snapshot("Column added")
    }

    func testNewIssueInAColumn() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Git Issues")
        app.buttons["New issue in Todo"].tap()
        let title = element("new-title")
        wait(title)
        waitForLabel(element("new-status"), containing: "Todo")
        title.typeText("Snap cards to a baseline grid")
        snapshot("iPad new issue in Todo")
        button("Create").tap()
        waitGone(title)
        let card = element("column-Todo").descendants(matching: .button).matching(NSPredicate(format: "label CONTAINS %@", "Snap cards to a baseline grid")).firstMatch
        wait(card)
    }

    func testCardMenuOnTheBoard() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Git Issues")
        let card = element("card-#17")
        wait(card)
        card.press(forDuration: 1.2)
        wait(button("Status"))
        snapshot("iPad card menu")
        button("Status").tap()
        button("In Review").tap()
        let moved = element("column-In Review").descendants(matching: .any).matching(identifier: "card-#17").firstMatch
        wait(moved)
    }

    func testIssueKeysAndBack() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Git Issues")
        element("card-#9").tap()
        let title = element("issue-title")
        wait(title)
        let first = title.value as? String
        XCTAssertEqual(first, "Drag cards between columns with spring physics")

        app.typeKey("j", modifierFlags: [])
        waitForValue(title, notEqualTo: first)
        app.typeKey("k", modifierFlags: [])
        waitForValue(title, equalTo: first)

        app.typeKey("s", modifierFlags: [])
        wait(app.navigationBars["Status"])
        snapshot("iPad status picker from the keyboard")
        button("In Review").tap()
        waitForLabel(element("property-status"), containing: "In Review")

        // From the keyboard, the picker's search takes the typing and Return picks the first match.
        app.typeKey("l", modifierFlags: [])
        wait(app.navigationBars["Labels"])
        app.typeText("bug\n")
        waitGone(app.navigationBars["Labels"])
        waitForLabel(element("property-labels"), containing: "bug")

        // Letters typed into the title are text, not shortcuts.
        title.tap()
        title.typeText("s")
        XCTAssertFalse(app.navigationBars["Status"].waitForExistence(timeout: 1.5))
        waitForValue(title, notEqualTo: first)

        // Once the text is put away, the keys work again, on the issue in front.
        hideKeyboard()
        let edited = title.value as? String
        app.typeKey("j", modifierFlags: [])
        waitForValue(title, notEqualTo: edited)
        app.typeKey("k", modifierFlags: [])
        waitForValue(title, equalTo: edited)
        app.typeKey("i", modifierFlags: [])
        waitForLabel(element("property-assignee"), containing: "none")
        app.typeKey("i", modifierFlags: [])
        waitForLabel(element("property-assignee"), containing: "jordan")

        // A comment beside the properties. (⌘↵ in the field needs a hardware keyboard, which the simulator's
        // on-screen keyboard can't stand in for: it has no ⌘ key.)
        let comment = element("comment-field")
        comment.tap()
        comment.typeText("Looks right on the iPad.")
        element("comment-send").tap()
        wait(labelled("Looks right on the iPad."))
        XCTAssertFalse(((comment.value as? String) ?? "").contains("Looks right"), "The field is empty again")
        hideKeyboard()

        app.typeKey("[", modifierFlags: .command)
        wait(element("card-#9"))
    }

    func testSidebarProjectsAccountAndCompose() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openProject("Website")
        wait(element("column-Todo"))
        XCTAssertFalse(element("column-Backlog").exists)
        snapshot("iPad Website board")

        app.buttons["New issue"].firstMatch.tap()
        wait(element("new-title"))
        XCTAssertTrue(labelled("Project: Website", type: .button).exists)
        button("Cancel").tap()

        app.buttons["Account and settings"].tap()
        wait(app.navigationBars["Account"])
        snapshot("iPad account")
        button("Done").tap()

        app.typeKey("3", modifierFlags: .command)
        wait(element("row-#9"))
        openProject("Git Issues")
        app.typeKey("2", modifierFlags: .command)
        wait(element("row-#9"))
        app.typeKey("1", modifierFlags: .command)
        wait(element("card-#9"))
    }

    func testDarkBoardAndSearch() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch(["-appearance", "dark"])
        openProject("Git Issues")
        wait(element("card-#9"))
        snapshot("iPad board, dark")
        app.typeKey("k", modifierFlags: .command)
        let field = app.searchFields.firstMatch
        wait(field)
        app.typeText("emoji")
        wait(element("row-#25"))
        snapshot("iPad search, dark")
        element("row-#25").tap()
        wait(element("property-status"))
        snapshot("iPad issue, dark")
    }

    func testPortraitUsesTheSameApp() {
        XCUIDevice.shared.orientation = .portrait
        launch()
        wait(element("row-#9"))
        snapshot("iPad portrait")
    }
}
