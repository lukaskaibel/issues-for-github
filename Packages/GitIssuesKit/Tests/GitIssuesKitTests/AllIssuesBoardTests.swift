import Foundation
import Testing
@testable import GitIssuesKit

@MainActor
@Suite("All Issues as a board")
struct AllIssuesBoardTests {
    static let noBoard = ListSection.noProjectId
    static let noStatus = BoardColumn.noStatusId

    @Test("Without an order of your own, the columns keep the board's: the issues on no board first")
    func naturalOrder() {
        let natural = [Self.noBoard, "todo", "doing", "done"]
        #expect(AppModel.arrangedColumnIds(natural, custom: []) == natural)
    }

    @Test("Your order wins, and a column that came since goes after the one before it on the board")
    func newColumnFindsItsPlace() {
        // You put Done first. Then "Review" was added on GitHub between Doing and Done.
        let custom = ["done", Self.noBoard, "todo", "doing"]
        let natural = [Self.noBoard, "todo", "doing", "review", "done"]
        #expect(AppModel.arrangedColumnIds(natural, custom: custom) == ["done", Self.noBoard, "todo", "doing", "review"])
    }

    @Test("A column with nothing before it on the board that has a place goes first")
    func newFirstColumn() {
        let custom = ["doing", "todo"]
        let natural = [Self.noStatus, "todo", "doing"]
        #expect(AppModel.arrangedColumnIds(natural, custom: custom) == [Self.noStatus, "doing", "todo"])
    }

    @Test("A column that isn't there now keeps its place for when it is back")
    func absentColumnKeepsItsPlace() {
        // The issues on no board were moved to the end; now there are none, so the board has no column of them.
        let custom = ["todo", "doing", "done", Self.noBoard]
        let natural = ["todo", "doing", "done"]
        let all = AppModel.arrangedColumnIds(natural, custom: custom)
        #expect(all == custom)
        // Moving Done to the front keeps the issues on no board last.
        let moved = AppModel.columnOrder(all, moving: "done", among: natural, to: 0)
        #expect(moved == ["done", "todo", "doing", Self.noBoard])
        // Once there are issues on no board again, their column is back at the end.
        #expect(AppModel.arrangedColumnIds([Self.noBoard] + natural, custom: moved) == moved)
    }

    @Test("An id named twice counts once")
    func duplicates() {
        #expect(AppModel.arrangedColumnIds(["a", "b"], custom: ["b", "b", "a"]) == ["b", "a"])
    }

    @Test("The display reads back as it was stored, and a list with nothing changed stores nothing")
    func displayCoding() throws {
        let display = AllIssuesDisplay(layout: .board, hiddenColumnIds: ["done"], columnOrder: ["done", Self.noBoard])
        let data = try JSONEncoder().encode(display)
        #expect(try JSONDecoder().decode(AllIssuesDisplay.self, from: data) == display)
        #expect(AllIssuesDisplay().isEmpty)
        #expect(!display.isEmpty)
    }
}
