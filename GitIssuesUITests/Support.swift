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
        let language = ProcessInfo.processInfo.environment["GI_LANGUAGE"] ?? "en"
        let locale = ProcessInfo.processInfo.environment["GI_LOCALE"] ?? (language == "en" ? "en_US" : language)
        app.launchArguments = ["-demo.active", "YES", "-uiTestReset", "YES", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            + tab + arguments
        app.launch()
        self.app = app
        return app
    }

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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

    func waitForValue(_ element: XCUIElement, notEqualTo value: String?, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String) != value }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Still \(value ?? "nil")", file: file, line: line)
    }

    /// Scrolls the list until the element is on screen and clear of the tab bar, which lists scroll under.
    func scrollTo(_ element: XCUIElement, in container: XCUIElement? = nil, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable && !behindTabBar(element)) && swipes < maxSwipes {
            (container ?? app).swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    private func behindTabBar(_ element: XCUIElement) -> Bool {
        let bar = app.tabBars.firstMatch
        return bar.exists && bar.frame.height > 0 && element.frame.maxY > bar.frame.minY - 8
    }

    /// Opens a board card's menu with a long press, and stops waiting for animations until `closedCardMenu()`.
    /// A card can be dragged as well, so while its menu is open UIKit holds the drag's lift animator, paused, for
    /// the preview to be dragged out of the menu onto a column. Nothing moves or draws, but XCTest counts the paused
    /// animator as running and would wait a minute before every step.
    func openCardMenu(_ card: XCUIElement) {
        waitsForAnimations(false)
        card.press(forDuration: 1.2)
        wait(button("Status"))
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

    /// Opens a project from the Projects tab of the iPhone.
    func openProjectTab(_ title: String) {
        app.tabBars.buttons["Projects"].tap()
        let row = labelled(title, type: .button)
        wait(row)
        row.tap()
        wait(app.navigationBars[title])
    }

    /// Keeps a screenshot with the test results, to look at afterwards.
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
