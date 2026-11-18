#if os(macOS)
import AppKit
import Testing
@testable import GitIssuesKit

@MainActor
@Suite("Right-clicks on the Mac: the innermost area's menu, and views floating over the page keep them to themselves")
struct ContextMenusTests {
    private let board = CGRect(x: 240, y: 50, width: 1200, height: 850)
    private let peek = CGRect(x: 970, y: 60, width: 460, height: 830)

    private func menu(_ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        return menu
    }

    private func title(_ click: ContextMenus.Click) -> String {
        switch click {
        case .menu(let menu): menu.title
        case .view: "view"
        case .nothing: "nothing"
        }
    }

    @Test func theSmallestAreaWithAMenuWinsAndOneWithoutLetsTheNextOutHaveIt() {
        let menus = ContextMenus()
        menus.register(UUID(), frame: board) { [self] _ in menu("card") }
        let header = UUID()
        menus.register(header, frame: CGRect(x: 260, y: 64, width: 240, height: 34)) { [self] _ in menu("column") }
        #expect(title(menus.click(at: CGPoint(x: 300, y: 80))) == "column")
        menus.register(header, frame: CGRect(x: 260, y: 64, width: 240, height: 34)) { _ in nil }
        #expect(title(menus.click(at: CGPoint(x: 300, y: 80))) == "card")
        #expect(title(menus.click(at: CGPoint(x: 100, y: 80))) == "view")
    }

    @Test func thePeekHasItsOwnMenuNeverTheCardsUnderIt() {
        let menus = ContextMenus()
        menus.register(UUID(), frame: board) { [self] _ in menu("card") }
        // A column header under the peek is smaller than the peek, and still doesn't count.
        menus.register(UUID(), frame: CGRect(x: 1040, y: 64, width: 240, height: 34)) { [self] _ in menu("column") }
        menus.register(UUID(), frame: peek, floats: true) { [self] _ in menu("peek") }
        #expect(title(menus.click(at: CGPoint(x: 1150, y: 80))) == "peek")
        #expect(title(menus.click(at: CGPoint(x: 1150, y: 500))) == "peek")
        // Beside the peek, the board's cards have theirs.
        #expect(title(menus.click(at: CGPoint(x: 600, y: 500))) == "card")
    }

    @Test func aFloatingViewWithoutAMenuTakesTheClickAndDoesNothing() {
        let menus = ContextMenus()
        menus.register(UUID(), frame: board) { [self] _ in menu("card") }
        menus.register(UUID(), frame: CGRect(x: 600, y: 780, width: 380, height: 80), floats: true) { _ in nil }
        #expect(title(menus.click(at: CGPoint(x: 700, y: 800))) == "nothing")
    }

    @Test func aNoticeOverThePeekDoesNothingRatherThanOpenThePeeksMenu() {
        let menus = ContextMenus()
        menus.register(UUID(), frame: board) { [self] _ in menu("card") }
        menus.register(UUID(), frame: peek, floats: true) { [self] _ in menu("peek") }
        menus.register(UUID(), frame: CGRect(x: 900, y: 800, width: 380, height: 70), floats: true) { _ in nil }
        #expect(title(menus.click(at: CGPoint(x: 1000, y: 830))) == "nothing")
        #expect(title(menus.click(at: CGPoint(x: 1000, y: 500))) == "peek")
    }

    @Test func textInAFloatingViewKeepsItsOwnMenu() {
        let menus = ContextMenus()
        menus.register(UUID(), frame: board) { [self] _ in menu("card") }
        menus.register(UUID(), frame: peek, floats: true) { [self] _ in menu("peek") }
        #expect(title(menus.click(at: CGPoint(x: 1150, y: 400), onText: true)) == "view")
        // Under no floating view, the card's menu, as before.
        #expect(title(menus.click(at: CGPoint(x: 600, y: 400), onText: true)) == "card")
    }

    @Test func aFloatingViewTakenAwayCoversNothing() {
        let menus = ContextMenus()
        menus.register(UUID(), frame: board) { [self] _ in menu("card") }
        let bar = UUID()
        menus.register(bar, frame: CGRect(x: 600, y: 820, width: 500, height: 44), floats: true) { [self] _ in menu("picked") }
        #expect(title(menus.click(at: CGPoint(x: 700, y: 840))) == "picked")
        menus.remove(bar)
        #expect(title(menus.click(at: CGPoint(x: 700, y: 840))) == "card")
    }
}
#endif
