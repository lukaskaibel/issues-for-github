import CoreGraphics
import Testing
@testable import GitIssuesKit

@Suite("⌘-dragging over issues picks them")
@MainActor
struct SweepPickTests {
    /// Five rows of a list, 30 points apart, as wide as the list.
    let listRows = (0..<5).map { SweepRow(id: "r\($0)", frame: CGRect(x: 0, y: CGFloat($0) * 30, width: 400, height: 30)) }

    /// Two columns of cards, 100 points tall with 10 between them, side by side with 20 between the columns.
    let boardCards = [
        SweepRow(id: "a0", frame: CGRect(x: 0, y: 0, width: 200, height: 100)),
        SweepRow(id: "a1", frame: CGRect(x: 0, y: 110, width: 200, height: 100)),
        SweepRow(id: "a2", frame: CGRect(x: 0, y: 220, width: 200, height: 100)),
        SweepRow(id: "b0", frame: CGRect(x: 220, y: 0, width: 200, height: 100)),
        SweepRow(id: "b1", frame: CGRect(x: 220, y: 110, width: 200, height: 100)),
    ]

    @Test("Down a list it sweeps every row from the press to the pointer, and going back leaves rows again")
    func list() {
        let start = CGPoint(x: 50, y: 40)
        #expect(SweepPick.swept(listRows, from: start, to: start, sideways: false) == ["r1"])
        #expect(SweepPick.swept(listRows, from: start, to: CGPoint(x: 50, y: 100), sideways: false) == ["r1", "r2", "r3"])
        #expect(SweepPick.swept(listRows, from: start, to: CGPoint(x: 50, y: 70), sideways: false) == ["r1", "r2"])
        // Up past the row it started on, and off to the side of the list: how far up counts.
        #expect(SweepPick.swept(listRows, from: start, to: CGPoint(x: 900, y: 5), sideways: false) == ["r0", "r1"])
        // The line between two rows belongs to the one below it.
        #expect(SweepPick.swept(listRows, from: start, to: CGPoint(x: 50, y: 60), sideways: false) == ["r1", "r2"])
    }

    @Test("On a board it sweeps the cards a rectangle from the press to the pointer meets, also in other columns")
    func board() {
        let start = CGPoint(x: 100, y: 50)
        #expect(SweepPick.swept(boardCards, from: start, to: CGPoint(x: 150, y: 150)) == ["a0", "a1"])
        // In the gap between the columns: nothing of the next one yet.
        #expect(SweepPick.swept(boardCards, from: start, to: CGPoint(x: 210, y: 150)) == ["a0", "a1"])
        #expect(SweepPick.swept(boardCards, from: start, to: CGPoint(x: 300, y: 150)) == ["a0", "a1", "b0", "b1"])
        // Back into the first column, the second one's cards are left.
        #expect(SweepPick.swept(boardCards, from: start, to: CGPoint(x: 100, y: 250)) == ["a0", "a1", "a2"])
        // In the gap between two cards of a column, the card below isn't reached.
        #expect(SweepPick.swept(boardCards, from: start, to: CGPoint(x: 100, y: 105)) == ["a0"])
    }

    @Test("Started on an issue that isn't picked it picks, on top of what was; started on a picked one it lets go")
    func picksOrLetsGo() {
        let picking = SweepPick(place: .issues, anchor: "r1", picked: ["r4"])
        #expect(picking.picks)
        #expect(picking.picked(sweeping: ["r1", "r2"]) == ["r1", "r2", "r4"])
        #expect(picking.picked(sweeping: ["r1"]) == ["r1", "r4"])

        let lettingGo = SweepPick(place: .issues, anchor: "r1", picked: ["r0", "r1", "r2", "r4"])
        #expect(!lettingGo.picks)
        #expect(lettingGo.picked(sweeping: ["r1", "r2", "r3"]) == ["r0", "r4"])
        // Going back, the ones it leaves are picked again, as they were.
        #expect(lettingGo.picked(sweeping: ["r1"]) == ["r0", "r2", "r4"])
    }

    @Test("The model sweeps the list's picks, an issue page's sub-issues and the Inbox's notifications; Escape undoes it")
    func model() throws {
        let model = AppModel(database: try AppDatabase.inMemory(), api: FakeGitHub([]).api)
        model.selectedIds = ["x"]
        model.beginSweep(on: "a", in: .issues)
        #expect(model.selectedIds == ["a", "x"])
        model.sweep(over: ["a", "b", "c"])
        #expect(model.selectedIds == ["a", "b", "c", "x"])
        model.sweep(over: ["b"])
        // The issue the press started on stays swept, wherever the pointer is.
        #expect(model.selectedIds == ["a", "b", "x"])
        model.endSweep()
        #expect(model.activeSweep == nil)
        #expect(model.selectionAnchorId == "a")

        model.beginSweep(on: "b", in: .issues)
        model.sweep(over: ["b", "x"])
        #expect(model.selectedIds == ["a"])
        model.cancelSweep()
        #expect(model.selectedIds == ["a", "b", "x"])

        model.beginSweep(on: "s1", in: .subIssues)
        model.sweep(over: ["s2"])
        model.endSweep()
        #expect(model.pickedSubIssueIds == ["s1", "s2"])
        #expect(model.selectedIds == ["a", "b", "x"])

        // In the Inbox the notification on screen is picked along with the first, as a ⌘-click picks it.
        model.inboxSelectedId = "n0"
        model.beginSweep(on: "n2", in: .inbox)
        model.sweep(over: ["n3"])
        #expect(model.inboxPicked == ["n0", "n2", "n3"])
        model.cancelSweep()
        #expect(model.inboxPicked.isEmpty)
    }
}
