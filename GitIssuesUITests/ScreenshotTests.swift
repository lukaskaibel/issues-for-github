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
        shot("2-my-issues")

        element("row-#9").tap()
        wait(element("issue-title"))
        shot("3-issue")

        element("chip-status").tap()
        wait(button("In Review"))
        shot("4-status")
        // A tap outside closes the menu without reaching what is underneath.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap()
        waitGone(button("In Review"))
        goBack()

        element("row-#8").press(forDuration: 1.2)
        wait(button("Status"))
        shot("5-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        element("compose-button").tap()
        let title = element("new-title")
        wait(title)
        title.typeText("Haptic feedback when a card lands")
        shot("6-new-issue")
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
        shot("7-search")
    }

    func testPhoneInbox() throws {
        try XCTSkipIf(isPad, "iPhone screenshots")
        launchForScreenshots(["-mobile.tab", "inbox"])
        wait(element("inbox-row-25"))
        shot("9-inbox")
    }

    /// The board first: what the iPhone has that GitHub's own app hasn't.
    func testPhoneBoard() throws {
        try XCTSkipIf(isPad, "iPhone screenshots")
        launchForScreenshots()
        openProjectTab("Git Issues")
        wait(element("strip-In Progress"))
        wait(element("card-#9"))
        shot("1-board")
    }

    func testPhoneDark() throws {
        try XCTSkipIf(isPad, "iPhone screenshots")
        launchForScreenshots(["-appearance", "dark"])
        openProjectTab("Git Issues")
        element("strip-Todo").tap()
        wait(element("card-#25"))
        shot("8-board-dark")
    }

    func testPad() throws {
        try XCTSkipUnless(isPad, "iPad screenshots")
        XCUIDevice.shared.orientation = .landscapeLeft
        launchForScreenshots()
        openPadProject("Git Issues")
        wait(element("card-#9"))
        shot("1-board")

        element("card-#9").tap()
        wait(element("property-status"))
        shot("2-issue")
        app.typeKey("[", modifierFlags: .command)
        wait(element("card-#8"))

        openCardMenu(element("card-#8"))
        shot("3-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.95)).tap()
        closedCardMenu()

        showLayout("List")
        wait(element("row-#9"))
        shot("4-list")
        showLayout("Board")
    }

    func testPadInbox() throws {
        try XCTSkipUnless(isPad, "iPad screenshots")
        XCUIDevice.shared.orientation = .landscapeLeft
        launchForScreenshots(["-mobile.tab", "inbox"])
        wait(element("inbox-row-25"))
        element("inbox-row-25").tap()
        wait(labelled("New since yesterday"))
        shot("6-inbox")
    }

    func testPadDark() throws {
        try XCTSkipUnless(isPad, "iPad screenshots")
        XCUIDevice.shared.orientation = .landscapeLeft
        launchForScreenshots(["-appearance", "dark"])
        openPadProject("Git Issues")
        wait(element("card-#9"))
        shot("5-board-dark")
    }
}
