import XCTest

/// Uses in-memory sample data only: no test changes GitHub project memberships or fields.
final class IssueProjectsTests: AppTestCase {
    private var project: String { "demo-project-app" }

    private func field(_ suffix: String) -> XCUIElement {
        element("project-field-\(project)-\(project)-\(suffix)")
    }

    private var properties: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["issue-projects-scroll", "issue-properties-scroll"])).firstMatch
    }

    private func openProjects(_ arguments: [String] = []) {
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        launch(arguments)
        let issue = element("row-#9")
        wait(issue)
        issue.tap()
        showProjectsSheetIfNeeded()
        wait(element("issue-project-\(project)"))
        snapshot("Project properties")
    }

    private func showProjectsSheetIfNeeded() {
        let entry = element("issue-projects-details")
        if entry.waitForExistence(timeout: isPad ? 1 : 4), entry.isHittable {
            XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
            snapshot("Projects entry")
            entry.tap()
            wait(element("issue-projects-done"))
        }
    }

    private func reveal(_ target: XCUIElement) {
        wait(properties)
        wait(target)
        for _ in 0..<12 where !target.isHittable {
            if target.frame.maxY <= properties.frame.minY + 50 {
                properties.swipeDown(velocity: .slow)
            } else {
                properties.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(target.isHittable)
    }

    private func tap(_ target: XCUIElement) {
        reveal(target)
        target.tap()
    }

    func testAddingRemovingCurrentAndLastProjectsKeepsTheIssueOpen() {
        openProjects()
        tap(element("issue-projects"))
        wait(pickerRow("Website"))
        snapshot("Project selector initial presentation")
        pickerRow("Website").tap()
        wait(element("issue-project-demo-project-site"))
        tap(element("remove-project-\(project)"))
        showProjectsSheetIfNeeded()
        wait(element("issue-project-demo-project-site"))
        waitGone(element("issue-project-\(project)"))
        tap(element("remove-project-demo-project-site"))
        showProjectsSheetIfNeeded()
        waitGone(element("issue-project-demo-project-site"))
        tap(element("issue-projects"))
        wait(pickerRow("Git Issues"))
        pickerRow("Git Issues").tap()
        showProjectsSheetIfNeeded()
        wait(element("issue-project-\(project)"))
        if element("issue-projects-done").exists { element("issue-projects-done").tap() }
        let title = app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "Drag cards between columns")).firstMatch
        wait(title)
        snapshot("Membership round trip keeps the issue open")
    }

    func testEditingProjectSelectionsDatesNumbersTextAndMultipleChoices() {
        openProjects()
        tap(field("version"))
        wait(pickerRow("0.4"))
        pickerRow("0.4").tap()
        waitForValue(field("version"), equalTo: "0.4")

        tap(field("finish"))
        wait(pickerRow("Tomorrow"))
        pickerRow("Tomorrow").tap()
        waitForValue(field("finish"), equalTo: "Tomorrow")
        tap(field("finish"))
        let clearDate = button("Clear value")
        for _ in 0..<6 where !clearDate.isHittable { element("date-picker-list").swipeUp() }
        wait(clearDate)
        clearDate.tap()
        waitForValue(field("finish"), equalTo: "Set value…")

        tap(field("requests"))
        let input = element("project-field-input")
        wait(input)
        input.tap()
        replaceText(of: input, with: "12.5")
        element("project-field-save").tap()
        waitForValue(field("requests"), equalTo: "12.5")

        tap(field("notes"))
        wait(input)
        input.tap()
        replaceText(of: input, with: "Ready for review")
        element("project-field-save").tap()
        waitForValue(field("notes"), equalTo: "Ready for review")

        tap(field("platforms"))
        wait(element("check-iOS"))
        element("check-iOS").tap()
        let android = element("check-Android")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: android)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 6), .completed)
        android.tap()
        button("Done").tap()
        waitForValue(field("platforms"), containing: "Android")
        waitForValue(field("platforms"), containing: "iOS")
        snapshot("Editable project fields")
    }

    func testFirstDueDateIsVisibleBeforeItsFieldSyncs() {
        openProjects(["-demo.offline", "YES"])
        tap(element("issue-projects"))
        wait(pickerRow("Website"))
        pickerRow("Website").tap()
        let due = element("project-due-demo-project-site")
        tap(due)
        wait(pickerRow("Tomorrow"))
        pickerRow("Tomorrow").tap()
        // This remains the fallback row while offline: there is still no due-date field in the project metadata.
        waitForValue(due, equalTo: "Tomorrow", 20)
        snapshot("First due date saved offline without field metadata")
        tap(due)
        let clear = element("date-picker-clear")
        let dates = element("date-picker-list")
        wait(dates)
        scrollTo(clear, in: dates, maxSwipes: 6)
        wait(clear, 20)
        clear.tap()
        waitForValue(due, equalTo: "Add due date", 20)
    }

    func testProjectsRemainAvailableAfterRotationAndInDarkAppearance() {
        openProjects(["-appearance", "dark"])
        if isPad {
            XCUIDevice.shared.orientation = .portrait
            // A 13-inch iPad can keep the inspector in portrait; smaller windows use the Projects sheet.
            showProjectsSheetIfNeeded()
        }
        wait(element("issue-project-\(project)"))
        tap(field("version"))
        pickerRow("0.4").tap()
        waitForValue(field("version"), equalTo: "0.4")
        wait(properties)
        snapshot("Compact project properties in dark appearance")
    }

    func testFoldedProjectsSurviveRemovingTheCurrentCard() {
        openProjects(["-demo.offline", "YES"])
        let usesSheet = element("issue-projects-done").exists
        tap(element("issue-projects"))
        wait(pickerRow("Website"))
        pickerRow("Website").tap()
        let website = element("toggle-project-demo-project-site")
        tap(website)
        waitForValue(website, equalTo: "Folded")
        tap(element("remove-project-\(project)"))
        if usesSheet { wait(element("issue-projects-done")) }
        waitForValue(website, equalTo: "Folded")
        waitGone(element("issue-project-\(project)"))
        snapshot("Folded projects survive replacing the current card")
    }

    func testProjectFieldsFoldIndependentlyAndRestoreTheirValues() {
        openProjects()
        tap(element("issue-projects"))
        wait(pickerRow("Website"))
        pickerRow("Website").tap()
        wait(element("issue-project-demo-project-site"))

        let header = element("toggle-project-\(project)")
        tap(header)
        waitForValue(header, equalTo: "Folded")
        waitGone(field("version"))
        wait(element("remove-project-\(project)"))
        let otherStatus = element("project-field-demo-project-site-demo-project-site-status")
        wait(otherStatus)
        snapshot("One project folded and the other open")

        tap(header)
        waitForValue(header, equalTo: "Open")
        waitForValue(field("version"), equalTo: "0.3")
        wait(otherStatus)
        snapshot("Project fields restored")

        tap(field("area"))
        wait(pickerRow("Interface"))
        snapshot("Wrapped option descriptions align to the leading edge")
        button("Done").tap()

        tap(header)
        tap(element("remove-project-\(project)"))
        showProjectsSheetIfNeeded()
        waitGone(element("issue-project-\(project)"))
        waitForValue(element("toggle-project-demo-project-site"), equalTo: "Open")
    }
}
