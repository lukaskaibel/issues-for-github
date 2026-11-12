#if os(macOS)
import AppKit
import Testing
@testable import GitIssuesKit

/// The Mac list is an AppKit table, which keeps views for more rows than are on screen: it makes the next ones ready
/// ahead of a scroll. A change has to reach those too, or a row scrolled into view shows what its issue was, labels and
/// all, until the pointer goes over it.
@MainActor
@Suite("Rows of the Mac list show their issues as they are now", .serialized)
struct ListRowsTests {
    /// A table as the list sets one up, handing out painted rows for `rows`.
    @MainActor
    final class Source: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [IssueRowModel]

        init(rows: [IssueRowModel]) {
            self.rows = rows
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Theme.rowHeight }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("issue")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? IssueRowCell) ?? {
                let cell = IssueRowCell()
                cell.identifier = identifier
                return cell
            }()
            cell.configure(rows[row], highlighted: false)
            return cell
        }

        /// What the list's coordinator does with a change: the rows are new, then the table is brought up to date.
        func change(_ table: NSTableView, to rows: [IssueRowModel]) {
            let oldIds = self.rows.map(\.item.id)
            self.rows = rows
            IssueTable.update(table, from: oldIds, to: rows.map(\.item.id)) { view, row in
                (view as? IssueRowCell)?.configure(self.rows[row], highlighted: false)
            }
        }
    }

    private static let labels = [
        LabelRef(id: "l1", name: "bug", color: "D73A4A"), LabelRef(id: "l2", name: "sync", color: "4CB782"),
        LabelRef(id: "l3", name: "ui", color: "8F96F2"),
    ]

    private static func row(_ number: Int, labels: [LabelRef] = []) -> IssueRowModel {
        let item = Item(
            id: "item-\(number)", projectId: "P1", kind: .issue, position: Double(number), contentId: "issue-\(number)",
            number: number, title: "Issue \(number)", body: "", state: "OPEN", repo: "acme/issues", labels: labels
        )
        return IssueRowModel(item: item, glyph: .none, priority: .none)
    }

    private static let rows = (1...200).map { row($0, labels: [labels[0]]) }

    /// A window with the table in a scroll view, scrolled into the middle, and the rows around the part on screen
    /// made ready, as a scroll makes them.
    private func makeTable(_ source: Source) -> (NSWindow, NSTableView, NSScrollView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("issue"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Theme.rowHeight
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = source
        table.delegate = source
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        window.contentView = scroll
        table.reloadData()
        scroll.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 80 * Theme.rowHeight))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.layoutSubtreeIfNeeded()
        table.prepareContent(in: table.visibleRect.insetBy(dx: 0, dy: -300))
        scroll.layoutSubtreeIfNeeded()
        return (window, table, scroll)
    }

    private func visibleRows(_ table: NSTableView) -> Range<Int> {
        let range = table.rows(in: table.visibleRect)
        return range.location..<(range.location + range.length)
    }

    /// Rows whose view shows something else than the row is now.
    private func stale(_ table: NSTableView, _ source: Source) -> [Int] {
        IssueTable.loadedRows(of: table).filter { row in
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell)?.row != source.rows[row]
        }
    }

    @Test("The table holds rows off screen, which a change reaches as well")
    func changeReachesRowsMadeReadyOffScreen() {
        let source = Source(rows: Self.rows)
        let (window, table, scroll) = makeTable(source)
        defer { window.close() }
        let visible = visibleRows(table)
        let loaded = Set(IssueTable.loadedRows(of: table))
        // What this test is about: rows with a view that aren't on screen.
        #expect(!loaded.subtracting(visible).isEmpty)

        // A sync brings new labels for every issue.
        source.change(table, to: Self.rows.map { Self.row($0.item.number!, labels: Self.labels) })
        #expect(stale(table, source).isEmpty)

        // Scrolled on, the rows that come into view show them too.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 250))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.layoutSubtreeIfNeeded()
        for row in visibleRows(table) {
            #expect((table.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell)?.row?.item.labels == Self.labels)
        }
    }

    @Test("A change that adds and moves issues reaches every row with a view")
    func changeWithNewRowsReachesEveryRow() {
        let source = Source(rows: Self.rows)
        let (window, table, _) = makeTable(source)
        defer { window.close() }
        // A new issue comes in on screen, one further down moves up, and every issue gets new labels.
        var next = Self.rows.map { Self.row($0.item.number!, labels: [Self.labels[2]]) }
        next.insert(Self.row(500, labels: [Self.labels[1]]), at: 85)
        next.swapAt(70, 95)
        source.change(table, to: next)
        #expect(stale(table, source).isEmpty)

        // One issue changing place on its own slides there; the rest are brought up to date all the same.
        var moved = next.map { Self.row($0.item.number!, labels: [Self.labels[0], Self.labels[1]]) }
        moved.insert(moved.remove(at: 90), at: 75)
        source.change(table, to: moved)
        #expect(stale(table, source).isEmpty)
    }

    @Test("A row's view taken over by another issue drops the pointer's place on the parts of the one before")
    func reusedRowDropsHover() {
        let cell = IssueRowCell(frame: NSRect(x: 0, y: 0, width: 900, height: Theme.rowHeight))
        cell.configure(Self.row(1, labels: Self.labels), highlighted: true)
        cell.hoveredPart = .labels
        cell.hoveringFold = true
        // The same issue with something changed keeps the pointer where it is.
        cell.configure(Self.row(1, labels: [Self.labels[0]]), highlighted: true)
        #expect(cell.hoveredPart == .labels)
        #expect(cell.hoveringFold)
        cell.configure(Self.row(2, labels: Self.labels), highlighted: false)
        #expect(cell.hoveredPart == nil)
        #expect(!cell.hoveringFold)
        #expect(cell.parts.isEmpty)
    }
}
#endif
