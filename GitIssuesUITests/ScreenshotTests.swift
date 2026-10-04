import XCTest

/// The App Store screenshots, taken on the sample data. Skipped in normal runs: `Tools/app-store-screenshots.sh`
/// runs them on a 6.9-inch iPhone and a 13-inch iPad and collects the images.
final class ScreenshotTests: AppTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GI_SCREENSHOTS"] == "1", "Run by Tools/app-store-screenshots.sh")
    }

    private func launchForScreenshots(_ arguments: [String] = []) {
        launch(["-screenshotMode", "YES"] + arguments)
    }

    /// A screenshot for the App Store, named so the script can sort it.
    private func shot(_ name: String) {
        // Let springs and fades settle first.
        Thread.sleep(forTimeInterval: 1.2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AppStore-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPhone() throws {
        try XCTSkipIf(isPad, "iPhone screenshots")
        launchForScreenshots()
        wait(element("row-#9"))
        shot("1-my-issues")

        element("row-#9").tap()
        wait(element("issue-title"))
        shot("2-issue")

        element("chip-status").tap()
        wait(button("In Review"))
        shot("3-status")
        // A tap outside closes the menu without reaching what is underneath.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap()
        waitGone(button("In Review"))
        goBack()

        element("row-#8").press(forDuration: 1.2)
        wait(button("Status"))
        shot("4-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        element("compose-button").tap()
        let title = element("new-title")
        wait(title)
        title.typeText("Haptic feedback when a card lands")
        shot("5-new-issue")
        button("Cancel").tap()
        button("Discard").tap()
        waitGone(title)
        Thread.sleep(forTimeInterval: 0.8)

        app.tabBars.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        wait(field)
        field.tap()
        field.typeText("drag")
        wait(element("row-#9"))
        shot("6-search")
    }

    func testPhoneDark() throws {
        try XCTSkipIf(isPad, "iPhone screenshots")
        launchForScreenshots(["-appearance", "dark"])
        openProjectTab("Git Issues")
        wait(element("section-In Progress"))
        shot("7-project-dark")
    }

    func testPad() throws {
        try XCTSkipUnless(isPad, "iPad screenshots")
        XCUIDevice.shared.orientation = .landscapeLeft
        launchForScreenshots()
        let project = app.cells.matching(NSPredicate(format: "label == %@", "Git Issues")).firstMatch
        wait(project)
        project.tap()
        wait(element("card-#9"))
        shot("1-board")

        element("card-#9").tap()
        wait(element("property-status"))
        shot("2-issue")
        app.typeKey("[", modifierFlags: .command)
        wait(element("card-#8"))

        element("card-#8").press(forDuration: 1.2)
        wait(button("Status"))
        shot("3-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.95)).tap()

        app.segmentedControls.buttons["List"].tap()
        wait(element("row-#9"))
        shot("4-list")
        app.segmentedControls.buttons["Board"].tap()
    }

    func testPadDark() throws {
        try XCTSkipUnless(isPad, "iPad screenshots")
        XCUIDevice.shared.orientation = .landscapeLeft
        launchForScreenshots(["-appearance", "dark"])
        let project = app.cells.matching(NSPredicate(format: "label == %@", "Git Issues")).firstMatch
        wait(project)
        project.tap()
        wait(element("card-#9"))
        shot("5-board-dark")
    }
}
