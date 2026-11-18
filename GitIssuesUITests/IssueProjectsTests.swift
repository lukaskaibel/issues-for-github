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

    /// The project's fields without a value wait behind "n more fields", which stays as it was left between launches.
    private func showEmptyFields(_ projectId: String? = nil, until target: XCUIElement) {
        guard !target.exists else { return }
        tap(element("project-more-fields-\(projectId ?? project)"))
        wait(target)
    }

    private func unfold(_ projectId: String) {
        let header = element("toggle-project-\(projectId)")
        reveal(header)
        if (header.value as? String) != "Open" { header.tap() }
        waitForValue(header, equalTo: "Open")
    }

    /// The sample issue is on the website's board as well.
    private func waitForWebsite() {
        wait(element("issue-project-demo-project-site"))
    }

    func testAddingRemovingCurrentAndLastProjectsKeepsTheIssueOpen() {
        openProjects()
        tap(element("issue-projects"))
        wait(pickerRow("Blog"))
        snapshot("Project selector initial presentation")
        pickerRow("Blog").tap()
        wait(element("issue-project-demo-project-blog"))
        tap(element("remove-project-demo-project-blog"))
        waitGone(element("issue-project-demo-project-blog"))
        tap(element("remove-project-\(project)"))
        wait(button("Undo"))
        snapshot("Removing a project offers Undo")
        showProjectsSheetIfNeeded()
        wait(element("issue-project-demo-project-site"))
        waitGone(element("issue-project-\(project)"))
        tap(element("remove-project-demo-project-site"))
        showProjectsSheetIfNeeded()
        waitGone(element("issue-project-demo-project-site"))
        if element("issue-projects-done").exists { element("issue-projects-done").tap() }
        let title = app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "Drag cards between columns")).firstMatch
        wait(title)
        snapshot("Membership round trip keeps the issue open")
    }

    func testUndoBringsTheProjectAndItsValuesBack() {
        openProjects()
        waitForValue(field("version"), equalTo: "0.3")
        tap(element("remove-project-\(project)"))
        let undo = button("Undo")
        wait(undo)
        undo.tap()
        showProjectsSheetIfNeeded()
        wait(element("issue-project-\(project)"))
        // The page moved on to the issue's other project, so this one is back below it, folded.
        unfold(project)
        waitForValue(field("version"), equalTo: "0.3")
    }

    func testEditingProjectSelectionsDatesNumbersTextAndMultipleChoices() {
        openProjects()
        tap(field("version"))
        wait(pickerRow("0.4"))
        pickerRow("0.4").tap()
        waitForValue(field("version"), equalTo: "0.4")

        showEmptyFields(until: field("finish"))
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
        element("check-Android").tap()
        button("Done").tap()
        waitForValue(field("platforms"), containing: "Android")
        waitForValue(field("platforms"), containing: "iOS")
        snapshot("Editable project fields")
    }

    func testFirstDueDateIsVisibleBeforeItsFieldSyncs() {
        openProjects(["-demo.offline", "YES"])
        waitForWebsite()
        unfold("demo-project-site")
        let due = element("project-due-demo-project-site")
        showEmptyFields("demo-project-site", until: due)
        tap(due)
        wait(pickerRow("Tomorrow"))
        pickerRow("Tomorrow").tap()
        // This remains the fallback row while offline: there is still no due-date field in the project metadata.
        waitForValue(due, equalTo: "Tomorrow", 20)
        snapshot("First due date saved offline without field metadata")
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

    func testOtherProjectsFoldAndKeepTheirOwnStatus() {
        openProjects()
        waitForWebsite()
        let header = element("toggle-project-demo-project-site")
        unfold("demo-project-site")
        let status = element("project-more-fields-demo-project-site")
        wait(status)
        snapshot("Another project unfolded")
        tap(header)
        waitForValue(header, equalTo: "Folded")
        waitGone(status)
        snapshot("Another project folded")
        // The project the issue was opened from keeps its fields in view.
        wait(field("version"))
    }

    func testRemovingTheCurrentProjectKeepsTheOtherOne() {
        openProjects(["-demo.offline", "YES"])
        let usesSheet = element("issue-projects-done").exists
        waitForWebsite()
        tap(element("remove-project-\(project)"))
        if usesSheet { wait(element("issue-projects-done")) }
        showProjectsSheetIfNeeded()
        wait(element("issue-project-demo-project-site"))
        waitGone(element("issue-project-\(project)"))
        snapshot("The issue stays open on its other project")
    }
}
