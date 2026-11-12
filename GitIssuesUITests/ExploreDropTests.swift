import XCTest

/// Throwaway: holds drags long enough to take screenshots from outside, and checks auto-scroll.
final class ExploreDropTests: AppTestCase {
    func testHoldOverMiddle() {
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        launch(ProcessInfo.processInfo.environment["GI_DARK"] == "1" ? ["-AppleInterfaceStyle", "Dark"] : [])
        if isPad { openPadProject("Git Issues") } else {
            openProjectTab("Git Issues")
            element("strip-Todo").tap()
        }
        if ProcessInfo.processInfo.environment["GI_LIST"] == "1" { showLayout("List") }
        let list = ProcessInfo.processInfo.environment["GI_LIST"] == "1"
        let (from, to) = list ? ("row-#17", "row-#25") : ("card-#17", "card-#25")
        let card = element(from)
        let target = element(to)
        wait(card)
        wait(target)
        let hold = Double(ProcessInfo.processInfo.environment["GI_HOLD"] ?? "12") ?? 12
        let dy = Double(ProcessInfo.processInfo.environment["GI_DY"] ?? "0.5") ?? 0.5
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)), withVelocity: .slow, thenHoldForDuration: hold)
        Thread.sleep(forTimeInterval: 1)
        print("EXPLORE from \(element(from).frame) to \(element(to).frame) label \(element(from).label)")
        snapshot("after")
    }

    /// Holds a list row near the bottom edge of the screen: the list should scroll on by itself.
    func testListAutoScroll() {
        launch()
        if isPad { openPadProject("Git Issues") } else { openProjectTab("Git Issues") }
        showLayout("List")
        let row = element("row-#17")
        wait(row)
        let window = app.windows.firstMatch.frame
        let probe = element("row-#21")
        print("EXPLORE before row17 \(row.frame) row21 exists \(probe.exists) \(probe.frame)")
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.midX, dy: window.maxY - 60))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4)
        Thread.sleep(forTimeInterval: 1)
        print("EXPLORE after row17 \(row.frame) row21 exists \(probe.exists) \(probe.frame)")
        snapshot("after autoscroll")
    }
}
