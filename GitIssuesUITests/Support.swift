import XCTest

/// Shared steps for the UI tests. Every test starts the app fresh on the built-in sample data, so tests never
/// touch GitHub and never depend on each other.
class AppTestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    /// Starts in My Issues unless the test asks for another tab with `-mobile.tab`; a fresh install opens the Inbox.
    @discardableResult
    func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let tab = arguments.contains("-mobile.tab") ? [] : ["-mobile.tab", "myIssues"]
        // In English whatever the simulator's language, since the tests find buttons by their labels. GI_LANGUAGE
        // (TEST_RUNNER_GI_LANGUAGE for xcodebuild) runs them in another, to look at a translation.
        app.launchArguments = ["-demo.active", "YES", "-uiTestReset", "YES", "-AppleLanguages", "(\(language))", "-AppleLocale", appLocale.identifier]
            + tab + arguments
        app.launch()
        self.app = app
        return app
    }

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var language: String { ProcessInfo.processInfo.environment["GI_LANGUAGE"] ?? "en" }

    /// The locale the app runs in, for dates the tests write themselves: the simulator's own region may differ.
    var appLocale: Locale {
        Locale(identifier: ProcessInfo.processInfo.environment["GI_LOCALE"] ?? (language == "en" ? "en_US" : language))
    }

    /// Any element with this accessibility identifier.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first element whose label contains the text.
    func labelled(_ text: String, type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons[label].firstMatch
    }

    /// Markdown drawn in a text view (a comment, a description) that holds this text.
    func textShowing(_ text: String) -> XCUIElement {
        app.textViews.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    /// A row of a picker sheet, by the name it starts with. Its circle, which picks without closing the sheet,
    /// is `element("check-<name>")`.
    func pickerRow(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func wait(_ element: XCUIElement, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing: \(element)", file: file, line: line)
    }

    func waitGone(_ element: XCUIElement, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Still there: \(element)", file: file, line: line)
    }

    func waitForLabel(_ element: XCUIElement, containing text: String, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element.label) lacks \(text)", file: file, line: line)
    }

    func waitForValue(_ element: XCUIElement, equalTo value: String?, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String) == value }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(String(describing: element.value)) is not \(value ?? "nil")", file: file, line: line)
    }

    func waitForValue(_ element: XCUIElement, containing text: String, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String)?.contains(text) == true }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(String(describing: element.value)) lacks \(text)", file: file, line: line)
    }

    func waitForValue(_ element: XCUIElement, lacking text: String, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String)?.contains(text) != true }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(String(describing: element.value)) still has \(text)", file: file, line: line)
    }

    func waitForValue(_ element: XCUIElement, notEqualTo value: String?, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String) != value }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Still \(value ?? "nil")", file: file, line: line)
    }

    /// Scrolls the list until the element is on screen and clear of the bars at the foot of the screen and of an
    /// issue's comment field, which lists and issues scroll under.
    func scrollTo(_ element: XCUIElement, in container: XCUIElement? = nil, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable && !behindTabBar(element) && !behindCommentField(element)) && swipes < maxSwipes {
            (container ?? app).swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    /// Under the iPad's tab bar, or the iPhone's search and New Issue at the foot of the screen.
    private func behindTabBar(_ element: XCUIElement) -> Bool {
        let foot = app.windows.firstMatch.frame.maxY - 140
        return [app.tabBars.firstMatch, app.toolbars.firstMatch].contains { bar in
            bar.exists && bar.frame.height > 0 && bar.frame.minY > foot && element.frame.maxY > bar.frame.minY - 8
        }
    }

    /// Under the comment field at the bottom of an issue, where a touch may reach the field instead.
    private func behindCommentField(_ element: XCUIElement) -> Bool {
        let field = app.textFields["comment-field"].firstMatch
        let send = app.buttons["comment-send"].firstMatch
        guard field.exists, send.exists, !["comment-field", "comment-send"].contains(element.identifier) else { return false }
        let bar = field.frame.union(send.frame)
        let frame = element.frame
        return frame.maxY > bar.minY - 8 && frame.maxX > bar.minX && frame.minX < bar.maxX
    }

    /// Opens a board card's menu with a long press, and stops waiting for animations until `closedCardMenu()`.
    /// A card can be dragged as well, so while its menu is open UIKit holds the drag's lift animator, paused, for
    /// the preview to be dragged out of the menu onto a column. Nothing moves or draws, but XCTest counts the paused
    /// animator as running and would wait a minute before every step. The same goes for anything else that can be
    /// dragged and has a menu, such as an epic's header; `showing` is an item of its menu.
    func openCardMenu(_ card: XCUIElement, showing item: String = "Status") {
        waitsForAnimations(false)
        card.press(forDuration: 1.2)
        wait(button(item))
        // What XCTest no longer waits for: the menu springing open.
        Thread.sleep(forTimeInterval: 0.8)
    }

    func closedCardMenu() {
        waitsForAnimations(true)
    }

    /// XCTest has no public switch for its wait on animations before each step; `XCUIApplication` keeps one under
    /// this name. Should it go away, the tests still pass, only slowly.
    private func waitsForAnimations(_ waits: Bool) {
        guard app.responds(to: NSSelectorFromString("setIdleAnimationWaitEnabled:")) else { return }
        app.setValue(waits, forKey: "idleAnimationWaitEnabled")
    }

    /// Back one screen.
    func goBack() {
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons["BackButton"]
        if back.exists {
            back.tap()
        } else {
            bar.buttons.element(boundBy: 0).tap()
        }
    }

    /// Replaces the text of a field that has the keyboard: deletes what's there, then types.
    func replaceText(of field: XCUIElement, with text: String) {
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }

    /// Taps a button of an alert until the alert has gone. On the iPad the keyboard sometimes folds and unfolds
    /// right after typing, moving the alert under the finger.
    func confirmAlert(_ alert: XCUIElement, with title: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 where alert.exists {
            alert.buttons[title].tap()
            if !alert.waitForExistence(timeout: 0.1) { return }
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)], timeout: 2)
        }
        XCTAssertFalse(alert.exists, "The alert stayed", file: file, line: line)
    }

    /// Goes back to the iPhone's Home, at the root of its one stack, from wherever the app is.
    func goHome() {
        let home = element("home-inbox")
        var steps = 0
        while !home.exists && steps < 6 {
            goBack()
            steps += 1
            _ = home.waitForExistence(timeout: 2)
        }
        wait(home)
    }

    /// Opens a project from the iPhone's Home: it opens on its open view, which names the screen, with the project's
    /// name under it and the project's page under the screen.
    func openProjectTab(_ title: String) {
        goHome()
        // Its row, not a pinned tile, whose label starts with what was pinned.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        wait(row)
        row.tap()
        wait(app.navigationBars.staticTexts[title])
    }

    /// Opens the iPhone's page of a project, with its views, milestones and roadmap: from one of its screens, Back;
    /// from anywhere else, the project from Home, then Back.
    func openProjectPage(_ title: String) {
        let page = app.navigationBars[title]
        if page.exists, element("page-All Issues").exists { return }
        if !app.navigationBars.staticTexts[title].exists { openProjectTab(title) }
        goBack()
        wait(page)
        wait(element("page-All Issues"))
    }

    /// Opens one of a project's views, a milestone, All Issues or the roadmap from the project's page.
    func openFromProjectPage(_ project: String, _ entry: String) {
        openProjectPage(project)
        let row = element("page-\(entry)")
        scrollTo(row)
        row.tap()
        wait(app.navigationBars[entry])
    }

    /// Puts the cursor in the search field at the foot of the iPhone screen in front.
    @discardableResult
    func openSearch() -> XCUIElement {
        let field = app.searchFields.firstMatch
        wait(field)
        field.tap()
        return field
    }

    /// Opens a project from its row in the iPad sidebar, which lists every project: it opens on its open view.
    func openPadProject(_ title: String) {
        tapSidebarEntry(title)
        wait(app.navigationBars[title])
    }

    /// Taps an entry of the iPad sidebar, scrolling the sidebar to it first: under every project's row, the open
    /// project's milestones and roadmap can be below the bottom of the screen.
    func tapSidebarEntry(_ title: String) {
        let entry = sidebarEntry(title)
        wait(entry)
        let screen = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 40)
        var swipes = 0
        while !screen.contains(entry.frame) && swipes < 4 {
            // On the Projects heading, which never opens anything.
            let heading = app.cells["projectSection"]
            heading.exists ? heading.swipeUp() : entry.swipeUp()
            swipes += 1
        }
        entry.tap()
    }

    /// An entry of the iPad sidebar, by its name: a view, a milestone, the roadmap or a repository.
    func sidebarEntry(_ title: String) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Shows the open view of a project as a board or a list ("Board", "List"), from the Display part of the
    /// project's menu.
    func showLayout(_ name: String) {
        app.navigationBars.buttons["Options"].firstMatch.tap()
        let display = button("Display")
        wait(display)
        display.tap()
        wait(button(name))
        button(name).tap()
    }

    /// Keeps a screenshot with the test results, to look at afterwards.
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
