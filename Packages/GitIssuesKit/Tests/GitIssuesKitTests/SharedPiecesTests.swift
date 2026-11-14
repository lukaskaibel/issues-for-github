import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif
@testable import GitIssuesKit

/// The pieces every place draws an issue with, on every platform: an issue known only from another one's page as a row
/// like any other, the labels rows and cards show, a status on a picked row, a due date as a property, and the shapes
/// of the marks that views, cards and rows all draw.
@Suite("Pieces every row and card of an issue is drawn with")
struct SharedPiecesTests {
    private static let sub = SubIssue(
        id: "issue-77", parentId: "issue-9", number: 77, title: "Elsewhere", state: "CLOSED", stateReason: "NOT_PLANNED",
        repo: "acme/other", url: "https://github.com/acme/other/issues/77", position: 3,
        assignees: [Person(id: "u1", login: "mira")], milestoneTitle: "0.3", subTotal: 4, subCompleted: 1
    )

    @Test("A sub-issue known only from GitHub is an issue of its own for its row, on none of your boards")
    func subIssueStandIn() {
        let item = Item(standingInFor: Self.sub, blockedBy: 2)
        #expect(item.isStandIn)
        #expect(!item.isOnBoard)
        #expect(item.contentId == "issue-77")
        #expect(item.displayNumber == "#77")
        #expect(item.isClosed)
        #expect(item.subTotal == 4 && item.subCompleted == 1)
        #expect(item.blockedByCount == 2)
        #expect(item.assignees.map(\.login) == ["mira"])
        #expect(item.milestoneTitle == "0.3")
        // One not on GitHub yet has no number to show.
        var unsent = Self.sub
        unsent.number = 0
        #expect(Item(standingInFor: unsent, blockedBy: 0).number == nil)
    }

    @Test("An issue another one is blocked by, known only from GitHub, is one too")
    func relationStandIn() {
        let link = LinkedIssue(
            id: "issue-5", issueId: "issue-13", relation: .blockedBy, number: 5, title: "Keyboard navigation", state: "OPEN",
            repo: "acme/issues", url: "https://github.com/acme/issues/issues/5", position: 0
        )
        let item = Item(standingInFor: link)
        #expect(item.isStandIn)
        #expect(item.contentId == "issue-5")
        #expect(item.displayNumber == "#5")
        #expect(!item.isClosed)
        #expect(item.url == link.url)
    }

    @Test("An epic's own label is left out wherever labels show; on any other issue it stays")
    func epicLabel() {
        let labels = [LabelRef(id: "l1", name: "Epic", color: "6E56CF"), LabelRef(id: "l2", name: "ui", color: "8F96F2")]
        let epic = Item(id: "e", kind: .issue, position: 0, title: "Drag and drop", body: "", state: "OPEN", labels: labels)
        #expect(epic.isEpic)
        #expect(epic.shownLabels.map(\.name) == ["ui"])
        let draft = Item(id: "d", kind: .draft, position: 0, title: "A draft", body: "", state: "OPEN", labels: labels)
        #expect(draft.shownLabels.map(\.name) == ["Epic", "ui"])
    }

    @Test("On a picked row a status turns white, but done and canceled keep their filled circle for the mark on it")
    func statusOnAccent() {
        let started = StatusGlyph(category: .started, progress: 0.5, color: Theme.started)
        #expect(started.onAccent.color == .white)
        #expect(started.onAccent.category == .started)
        let done = StatusGlyph(category: .completed, progress: 1, color: Theme.accent)
        #expect(done.onAccent == done)
        let canceled = StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary)
        #expect(canceled.onAccent == canceled)
    }

    @Test("An issue closed as a duplicate or not planned is canceled, on a board or not; closed otherwise is done")
    func closedReasons() {
        func closed(_ reason: String?) -> Item {
            Item(id: "i", kind: .issue, position: 0, contentId: "c", title: "T", body: "", state: "CLOSED", stateReason: reason)
        }
        #expect(StatusGlyph.withoutProject(closed("DUPLICATE")).category == .canceled)
        #expect(StatusGlyph.withoutProject(closed("NOT_PLANNED")).category == .canceled)
        #expect(StatusGlyph.withoutProject(closed("COMPLETED")).category == .completed)
        #expect(StatusGlyph.openOrClosed("CLOSED", reason: "DUPLICATE").category == .canceled)
        // Open and on no board: the ring with a plus that puts it on one.
        let open = Item(id: "i", kind: .issue, position: 0, contentId: "c", title: "T", body: "", state: "OPEN")
        #expect(StatusGlyph.withoutProject(open).addsToProject)
    }

    @Test("A due date as a property takes its tone's colour only while it asks for attention")
    func dueEmphasis() {
        let day = CalendarDay(year: 2026, month: 11, day: 14)
        #expect(DueBadge(day: day, label: "Today", tone: .today).emphasis == DueTone.today.color)
        #expect(DueBadge(day: day, label: "Nov 12", tone: .overdue).emphasis == DueTone.overdue.color)
        #expect(DueBadge(day: day, label: "Fri", tone: .upcoming).emphasis == nil)
        #expect(DueBadge(day: day, label: "Fri", tone: .settled).emphasis == nil)
    }

    @Test("A priority lights its bars up to its level, and Urgent is one square in the middle of the box")
    func priorityShapes() {
        let box = CGRect(x: 10, y: 20, width: 14, height: 12)
        for (level, lit) in [(PriorityLevel.none, 0), (.low, 1), (.medium, 2), (.high, 3)] {
            let shapes = Marks.priority(level, in: box)
            #expect(shapes.count == 3)
            #expect(shapes.filter { $0.ink == .mark }.count == lit)
            // The bars stand on the bottom of the box, each taller than the one before.
            let rects = shapes.map { $0.path.boundingRect }
            #expect(rects.allSatisfy { abs($0.maxY - box.maxY) < 0.01 })
            #expect(rects[0].height < rects[1].height && rects[1].height < rects[2].height)
        }
        let urgent = Marks.priority(.urgent, in: box)
        #expect(urgent.count == 1)
        #expect(urgent[0].path.boundingRect == Marks.urgentSquare(in: box))
        #expect(Marks.urgentSquare(in: box).midX == box.midX && Marks.urgentSquare(in: box).midY == box.midY)
    }

    @Test("A sub-issue's line turns into it at its branch, and one with more sub-issues below goes on past it")
    func treeLines() {
        let lineX: (Int) -> CGFloat = { CGFloat($0) * 20 + 7 }
        // The last one under its parent: the line comes down and turns into the issue.
        let last = Marks.treeLines(Nesting.Place(depth: 1, continues: [false]), deepest: 5, lineX: lineX, branchY: 18, branchEnd: 17, height: 36)
        #expect(abs(last.boundingRect.minY) < 0.01)
        #expect(abs(last.boundingRect.maxY - 18) < 0.01)
        #expect(abs(last.boundingRect.maxX - 17) < 0.01)
        // One with others after it: the line goes on to the row's foot.
        let middle = Marks.treeLines(Nesting.Place(depth: 1, continues: [true]), deepest: 5, lineX: lineX, branchY: 18, branchEnd: 17, height: 36)
        #expect(abs(middle.boundingRect.maxY - 36) < 0.01)
        // At the top level there is no line.
        #expect(Marks.treeLines(Nesting.Place(), deepest: 5, lineX: lineX, branchY: 18, branchEnd: 17, height: 36).isEmpty)
    }

    @Test("A picked checkbox is a box with a tick; an empty one is an outline only")
    func checkbox() {
        let box = CGRect(x: 0, y: 0, width: 14, height: 14)
        let checked = Marks.checkbox(checked: true, in: box)
        #expect(checked.count == 2)
        #expect(checked[0].stroke == nil && checked[1].ink == .onColor)
        let empty = Marks.checkbox(checked: false, in: box)
        #expect(empty.count == 1)
        #expect(empty[0].stroke != nil && empty[0].ink == .off)
    }

    @Test("An epic's icon is the stack of layers in its square, stroked thinner when smaller")
    func epicMark() {
        let big = Marks.epic(in: CGRect(x: 0, y: 0, width: 14, height: 14))
        let small = Marks.epic(in: CGRect(x: 0, y: 0, width: 7, height: 7))
        #expect(big.count == 1 && big[0].ink == .mark)
        #expect(big[0].path.boundingRect.maxX <= 14 && big[0].path.boundingRect.minX >= 0)
        #expect((small[0].stroke?.lineWidth ?? 0) * 2 == big[0].stroke?.lineWidth)
    }

    @Test("A fold arrow grows with the text around it, from the same middle")
    func foldArrowScale() {
        let center = CGPoint(x: 50, y: 30)
        let plain = Marks.foldArrow(folded: false, center: center)[0]
        let larger = Marks.foldArrow(folded: false, center: center, scale: 2)[0]
        #expect(abs(larger.path.boundingRect.width - 2 * plain.path.boundingRect.width) < 0.01)
        #expect(abs(larger.path.boundingRect.midX - plain.path.boundingRect.midX) < 0.01)
        #expect(larger.stroke?.lineWidth == 2 * (plain.stroke?.lineWidth ?? 0))
    }

    #if os(macOS)
    @Test("An epic's header is a line of its name high with room above and below, and its arrow ends the first line")
    @MainActor
    func epicHeader() {
        let epic = Item(id: "e", kind: .issue, position: 0, title: "Offline-first sync", body: "", state: "OPEN")
        let group = Nesting.EpicGroup(epic: epic, count: 2, folded: false)
        let look = EpicHeaderLook.self
        let oneLine = EpicHeader.height(of: group, width: 240, iconColumn: (0, 16), trailing: 6, lineLimit: 3)
        #expect(oneLine == look.line + look.top + look.bottom)
        // A long name wraps on a narrow board, up to the limit.
        var long = group
        long.epic.title = String(repeating: "A long name for an epic ", count: 8)
        let wrapped = EpicHeader.height(of: long, width: 240, iconColumn: (0, 16), trailing: 6, lineLimit: 3)
        #expect(wrapped > oneLine)
        #expect(wrapped <= MeasuredHeights.textHeight(lines: 3, font: look.nameFont) + look.top + look.bottom)
        // The arrow's square ends `trailing` before the header's edge, on the first line.
        let frame = CGRect(x: 100, y: 200, width: 240, height: oneLine)
        let fold = EpicHeader.foldFrame(in: frame, trailing: 6)
        #expect(fold.maxX == frame.maxX - 6)
        #expect(abs(fold.midY - (frame.minY + look.top + look.line / 2)) < 0.01)
    }

    @Test("The list's epic header draws its arrow where a click folds it, under the section header's +")
    @MainActor
    func listEpicHeaderFold() {
        let epic = Item(id: "e", kind: .issue, position: 0, title: "Offline-first sync", body: "", state: "OPEN")
        let cell = EpicHeaderRowCell(frame: NSRect(x: 0, y: 0, width: 900, height: Theme.rowHeight))
        cell.configure(Nesting.EpicGroup(epic: epic, count: 2, folded: false))
        let image = NSImage(size: cell.bounds.size, flipped: true) { _ in
            cell.draw(cell.bounds)
            return true
        }
        _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let arrow = NSPoint(x: 900 - EpicHeaderRowCell.trailing - EpicHeaderLook.arrowBox / 2, y: Theme.rowHeight - EpicHeaderLook.bottom - EpicHeaderLook.line / 2)
        #expect(cell.isOnFold(arrow))
        #expect(!cell.isOnFold(NSPoint(x: 200, y: arrow.y)))
    }
    #endif
}

