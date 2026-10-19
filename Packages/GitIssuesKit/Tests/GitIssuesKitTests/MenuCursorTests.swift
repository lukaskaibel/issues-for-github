#if os(macOS)
import Observation
import Testing
@testable import GitIssuesKit

@MainActor
@Suite("The light in menus, pickers and the palette, which redraws only the rows it leaves and enters")
struct MenuCursorTests {
    private final class Redrawn: @unchecked Sendable {
        var rows: [Int] = []
    }

    /// The rows that `change` would redraw, each watched the way SwiftUI watches a row's body.
    private func redrawn(_ cursor: MenuCursor<Int>, rows: Range<Int>, by change: () -> Void) -> [Int] {
        let redrawn = Redrawn()
        for row in rows {
            withObservationTracking {
                _ = cursor.isLit(row)
            } onChange: {
                redrawn.rows.append(row)
            }
        }
        change()
        return redrawn.rows.sorted()
    }

    @Test func movingTheLightRedrawsTheRowItLeavesAndTheRowItEnters() {
        let cursor = MenuCursor<Int>(2)
        #expect(redrawn(cursor, rows: 0..<30) { cursor.key = 5 } == [2, 5])
        #expect(cursor.isLit(5))
        #expect(!cursor.isLit(2))
    }

    @Test func thePointerStayingOnItsRowRedrawsNothing() {
        let cursor = MenuCursor<Int>(3)
        #expect(redrawn(cursor, rows: 0..<30) { cursor.key = 3 } == [])
    }

    @Test func anotherSubmenuOpeningRedrawsBothRows() {
        let cursor = MenuCursor<Int>()
        cursor.openSubmenu(1, takesKey: false)
        #expect(redrawn(cursor, rows: 0..<30) { cursor.openSubmenu(4, takesKey: true) } == [1, 4])
        #expect(cursor.isLit(4))
        #expect(cursor.openTakesKey)
    }

    @Test func theArrowKeysGoRoundAndAskTheListToScroll() {
        let cursor = MenuCursor<Int>()
        // Down from nothing starts at the top, up from the top goes round to the bottom.
        cursor.step(1, through: [0, 2, 3])
        #expect(cursor.key == 0)
        cursor.step(-1, through: [0, 2, 3])
        #expect(cursor.key == 3)
        #expect(cursor.keyMoves == 2)
    }

    @Test func leavingARowPutsItOutUnlessThePointerIsOnAnotherAlready() {
        let cursor = MenuCursor<String>()
        cursor.hover("sync", true)
        cursor.hover("settings", true)
        cursor.hover("sync", false)
        #expect(cursor.key == "settings")
        cursor.hover("settings", false)
        #expect(cursor.key == nil)
    }
}
#endif
