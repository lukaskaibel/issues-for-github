import XCTest

/// Throwaway: holds drags long enough to take screenshots from outside.
final class ExploreDropTests: AppTestCase {
    func testHoldOverMiddle() {
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        launch(ProcessInfo.processInfo.environment["GI_DARK"] == "1" ? ["-AppleInterfaceStyle", "Dark"] : [])
        if isPad { openPadProject("Git Issues") } else { openProjectTab("Git Issues") }
        let (from, to) = isPad ? ("card-#17", "card-#25") : ("card-#7", "card-#9")
        let card = element(from)
        let target = element(to)
        wait(card)
        wait(target)
        let hold = Double(ProcessInfo.processInfo.environment["GI_HOLD"] ?? "12") ?? 12
        let dy = Double(ProcessInfo.processInfo.environment["GI_DY"] ?? "0.5") ?? 0.5
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)), withVelocity: .slow, thenHoldForDuration: hold)
        Thread.sleep(forTimeInterval: 1)
        print("EXPLORE from \(element(from).frame) to \(element(to).frame)")
        print("EXPLORE notice \(labelled("sub-issue of").exists) \(labelled("sub-issue of").label)")
        snapshot("after")
        Thread.sleep(forTimeInterval: 2)
    }
}
