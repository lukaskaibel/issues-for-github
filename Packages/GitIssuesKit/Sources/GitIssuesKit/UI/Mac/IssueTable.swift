#if os(macOS)
import AppKit
import SwiftUI

/// What one list row shows, gathered up front so drawing needs no lookups.
struct IssueRowModel: Equatable {
    var item: Item
    var glyph: StatusGlyph
    var priority: PriorityLevel
    /// Whether the project has the field, so the icon can be clicked to change it.
    var showsPriority = true
    var showsStatus = true
    /// Shown in "My Issues", where rows come from several projects.
    var projectTitle: String?
    var due: DueBadge?
    /// What blocks it, when an open issue does.
    var blocker: BlockerMark?
    /// Picked for a change to several issues at once, and whether anything is picked, which shows every
    /// row's checkbox.
    var selected = false
    var selecting = false
    /// How the row hangs under a parent in its group.
    var nest = Nesting.Place()
    /// How many sub-issues hang under this one in its group, folded or not; nil when none do.
    var nested: Int?
    var folded = false
    /// A sub-issue whose parent is in another group names the parent.
    var showsParent = false
    /// Whether that parent is an epic, which it then names with the epic's icon.
    var parentIsEpic = false
    /// The milestone it is planned for, where the list isn't a milestone's.
    var milestone: String?
    var milestoneMark: MilestoneMark = .upcoming
    /// The project's own fields the view shows, such as an iteration or a "Workstream".
    var chips: [FieldChip] = []
}

struct IssueSectionModel: Equatable {
    typealias Icon = SectionIcon

    var id: String
    var collapsed = false
    var title: String
    var glyph: StatusGlyph
    var icon: Icon = .plain
    /// Quiet text after the count, such as when a milestone is due.
    var detail: String?
    var optionId: String?
    var kind: ListSection.Kind = .status
    var canAdd: Bool
    var count: Int
    /// The section's lines: its issues, and the headers over epics' issues standing together.
    var lines: [IssueLine]
    /// A view's group: as a list, with its progress as a bar, or as a person's load.
    var style: GroupStyle = .plain
    var progress: GroupProgress?
    /// A person's open issues against those of the person with the most, for the length of the load bar.
    var load: CGFloat = 0

    /// The number in the header: how many of all are done for a group that shows its progress, else how many.
    var countText: String {
        if style == .progress, let progress { progress.fraction } else { "\(count)" }
    }

    var rows: [IssueRowModel] {
        lines.compactMap { if case .row(let row) = $0 { row } else { nil } }
    }
}

/// One line of a section: an issue, or the header over the issues of an epic standing together.
enum IssueLine: Equatable {
    case row(IssueRowModel)
    case epic(Nesting.EpicGroup)
}

/// The issue list. It is an AppKit table rather than a SwiftUI stack because a table recycles its rows
/// and prepares the next ones ahead of the scroll, which keeps a list of hundreds of issues smooth.
struct IssueTable: NSViewRepresentable {
    /// Space between the list's edges and its rounded header bands and row highlights.
    static let inset: CGFloat = 8

    @Environment(AppModel.self) private var model
    var sections: [IssueSectionModel]
    /// Whether issues can be dragged to a new place: in a project you can edit, not in My Issues.
    var canMoveRows = false
    var focusedId: String?
    var focusScrollToken: Int
    var avatarVersion: Int
    /// Which list this is (My Issues, a project's view, a milestone…); another one starts at its top.
    var listKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = HoverTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("issue"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Theme.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.floatsGroupRows = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsColumnResizing = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:))
        table.coordinator = context.coordinator
        context.coordinator.table = table
        // Issues, epics' headers and section headers can be dragged to a new place; rows open a gap where it would land.
        table.registerForDraggedTypes([Coordinator.itemType, Coordinator.epicType, Coordinator.sectionType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        // No top inset: the list ends cleanly at the top edge, under the sticky header.
        // Room at the end for the selection bar, so the last row can scroll clear of it.
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 76, right: 0)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.scrolled(_:)),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
        let sticky = IssueHeaderCell()
        sticky.handlesClicks = true
        sticky.isHidden = true
        scroll.addSubview(sticky)
        // While the next header pushes it up, it slides out under the top edge instead of over the toolbar.
        scroll.clipsToBounds = true
        context.coordinator.sticky = sticky
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.canMoveRows = canMoveRows
        if context.coordinator.listKey != listKey {
            // Not where the last list was scrolled to; before the rows change, so the focused issue can still be
            // scrolled to.
            if context.coordinator.listKey != nil {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            context.coordinator.listKey = listKey
        }
        context.coordinator.apply(
            sections: sections, focusedId: focusedId, focusScrollToken: focusScrollToken, avatarVersion: avatarVersion
        )
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        enum Entry: Equatable {
            case header(IssueSectionModel)
            case row(IssueRowModel)
            /// The header over an epic's issues in a section, which is named with it: an epic can have issues in
            /// several sections.
            case epic(sectionId: String, group: Nesting.EpicGroup)

            var id: String {
                switch self {
                case .header(let section): "section:\(section.id)"
                case .row(let row): row.item.id
                case .epic(let sectionId, let group): "epic:\(sectionId):\(group.contentId)"
                }
            }

            var isHeader: Bool {
                if case .header = self { true } else { false }
            }
        }

        let model: AppModel
        weak var table: HoverTableView?
        var listKey: String?
        weak var scrollView: NSScrollView?
        /// The header of the section the list is scrolled into, held at the top while its own row is out of view.
        weak var sticky: IssueHeaderCell?
        private var stickySectionId: String?
        private var entries: [Entry] = []
        private var focusedId: String?
        private var hoveredId: String?
        private var focusScrollToken = 0
        private var avatarVersion = 0
        var canMoveRows = false
        /// The rows being dragged, which stay behind faded until they land: an issue, or an epic's header and its
        /// issues.
        private var draggedIds: Set<String> = []

        init(model: AppModel) {
            self.model = model
        }

        func apply(sections: [IssueSectionModel], focusedId: String?, focusScrollToken: Int, avatarVersion: Int) {
            guard let table else { return }
            var next: [Entry] = []
            for section in sections {
                // Headers compare by what they show, not by their rows.
                var header = section
                header.lines = []
                next.append(.header(header))
                next += section.lines.map { line in
                    switch line {
                    case .row(let row): .row(row)
                    case .epic(let group): .epic(sectionId: section.id, group: group)
                    }
                }
            }
            let oldIds = entries.map(\.id)
            let newIds = next.map(\.id)
            let old = entries
            entries = next

            if oldIds == newIds {
                for row in visibleRows(in: table) where old[row] != next[row] {
                    configureView(at: row, in: table)
                }
            } else {
                let difference = newIds.difference(from: oldIds).inferringMoves()
                if old.isEmpty || difference.count > 300 {
                    table.reloadData()
                } else if let move = Self.singleMove(difference) {
                    // One issue changed place, by a drag or a new status: it slides there.
                    table.beginUpdates()
                    table.moveRow(at: move.from, to: move.to)
                    table.endUpdates()
                    for row in visibleRows(in: table) { configureView(at: row, in: table) }
                } else {
                    // Rows slide to their new place when an issue changes status or order.
                    table.beginUpdates()
                    for change in difference {
                        switch change {
                        case .remove(let offset, _, _):
                            table.removeRows(at: IndexSet(integer: offset), withAnimation: [.effectFade, .slideUp])
                        case .insert(let offset, _, _):
                            table.insertRows(at: IndexSet(integer: offset), withAnimation: [.effectFade, .slideDown])
                        }
                    }
                    table.endUpdates()
                    for row in visibleRows(in: table) { configureView(at: row, in: table) }
                }
            }

            if avatarVersion != self.avatarVersion {
                self.avatarVersion = avatarVersion
                for row in visibleRows(in: table) {
                    table.view(atColumn: 0, row: row, makeIfNecessary: false)?.needsDisplay = true
                }
            }
            updateSticky()
            if focusedId != self.focusedId {
                let previous = self.focusedId
                self.focusedId = focusedId
                refreshHighlight(for: [previous, focusedId])
            }
            if focusScrollToken != self.focusScrollToken {
                self.focusScrollToken = focusScrollToken
                if let focusedId, let row = entries.firstIndex(where: { $0.id == focusedId }) {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.12
                        context.allowsImplicitAnimation = true
                        table.scrollRowToVisible(row)
                    }
                }
            }
        }

        /// The one row that moved, when that is all that changed.
        private static func singleMove(_ difference: CollectionDifference<String>) -> (from: Int, to: Int)? {
            guard difference.count == 2,
                  case .remove(let from, _, let removedTo?) = difference.removals.first,
                  case .insert(let to, _, let insertedFrom?) = difference.insertions.first,
                  removedTo == to, insertedFrom == from else { return nil }
            return (from, to)
        }

        private func visibleRows(in table: NSTableView) -> Range<Int> {
            let range = table.rows(in: table.visibleRect)
            let lower = max(0, range.location)
            return lower..<min(entries.count, lower + range.length)
        }

        private func configureView(at row: Int, in table: NSTableView) {
            guard entries.indices.contains(row),
                  let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) else { return }
            configure(view, with: entries[row])
        }

        private func configure(_ view: NSView, with entry: Entry) {
            switch entry {
            case .header(let section):
                (view as? IssueHeaderCell)?.configure(section, model: model)
            case .row(let row):
                let cell = view as? IssueRowCell
                cell?.model = model
                cell?.configure(row, highlighted: row.item.id == hoveredId || row.item.id == focusedId)
                cell?.alphaValue = draggedIds.contains(row.item.id) ? 0.35 : 1
            case .epic(_, let group):
                (view as? EpicHeaderRowCell)?.configure(group)
                view.alphaValue = draggedIds.contains(entry.id) ? 0.35 : 1
            }
        }

        private func refreshHighlight(for ids: [String?]) {
            guard let table else { return }
            for id in ids.compactMap({ $0 }) {
                if let row = entries.firstIndex(where: { $0.id == id }) { configureView(at: row, in: table) }
            }
        }

        // MARK: Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int {
            entries.count
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .header = entries[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            Theme.rowHeight
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("row-view")
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? PlainRowView { return reused }
            let view = PlainRowView()
            view.identifier = identifier
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entry = entries[row]
            switch entry {
            case .header:
                let identifier = NSUserInterfaceItemIdentifier("header")
                let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? IssueHeaderCell) ?? {
                    let cell = IssueHeaderCell()
                    cell.identifier = identifier
                    return cell
                }()
                configure(view, with: entry)
                return view
            case .epic:
                let identifier = NSUserInterfaceItemIdentifier("epic-header")
                let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? EpicHeaderRowCell) ?? {
                    let cell = EpicHeaderRowCell()
                    cell.identifier = identifier
                    return cell
                }()
                configure(view, with: entry)
                return view
            case .row:
                let identifier = NSUserInterfaceItemIdentifier("issue")
                let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? IssueRowCell) ?? {
                    let cell = IssueRowCell()
                    cell.identifier = identifier
                    return cell
                }()
                configure(view, with: entry)
                return view
            }
        }

        // MARK: Reordering issues and sections

        static let itemType = NSPasteboard.PasteboardType("com.lukaskbl.GitIssues.item")
        /// An epic's header, as its section's id and the epic's, which brings the epic's issues there along.
        static let epicType = NSPasteboard.PasteboardType("com.lukaskbl.GitIssues.epic-group")
        static let sectionType = NSPasteboard.PasteboardType("com.lukaskbl.GitIssues.section")

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard entries.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            switch entries[row] {
            case .header(let section):
                item.setString(section.id, forType: Self.sectionType)
            case .row(let issue):
                guard canMoveRows else { return nil }
                item.setString(issue.item.id, forType: Self.itemType)
            case .epic(let sectionId, let group):
                guard canMoveRows, section(sectionId)?.kind == .status else { return nil }
                item.setString("\(sectionId)\u{1F}\(group.contentId)", forType: Self.epicType)
            }
            return item
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            guard let row = rowIndexes.first, entries.indices.contains(row) else { return }
            // The issue lifts off as a card, and its row closes up into the gap where it would land. An epic's header
            // lifts off the same way, and its issues stay behind faded until they land.
            let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
            if let image = (cell as? IssueRowCell)?.dragImage() ?? (cell as? EpicHeaderRowCell)?.dragImage(),
               image.size.width > 0, image.size.height > 0 {
                session.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragged, _, _ in
                    // From where the table lifted the row: by now the row has closed up and `rect(ofRow:)` has no
                    // height, and a frame without one throws, which ends the drag before it starts and leaves the
                    // row hidden.
                    dragged.setDraggingFrame(NSRect(origin: dragged.draggingFrame.origin, size: image.size), contents: image)
                }
            }
            switch entries[row] {
            case .row(let issue):
                draggedIds = [issue.item.id]
            case .epic(let sectionId, let group):
                let members = statusColumn(sectionId)?.members(of: group) ?? []
                draggedIds = Set(members.map(\.id)).union([entries[row].id])
            case .header:
                return
            }
            for visible in visibleRows(in: tableView) { configureView(at: visible, in: tableView) }
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let ids = draggedIds
            draggedIds = []
            refreshHighlight(for: Array(ids))
            // The table hides the dragged row while it is dragged, and the list hides none of its own: once the drag
            // is over, every row shows again, wherever the drop has put it.
            DispatchQueue.main.async {
                let hidden = tableView.hiddenRowIndexes
                if !hidden.isEmpty { tableView.unhideRows(at: hidden, withAnimation: []) }
            }
        }

        /// The row after a section's last one.
        private func end(of sectionId: String) -> Int {
            guard let header = entries.firstIndex(where: { $0.id == "section:\(sectionId)" }) else { return entries.count }
            var row = header + 1
            while row < entries.count, !entries[row].isHeader { row += 1 }
            return row
        }

        /// Rows where a section may be dropped: in front of each header, or after the last row.
        private var sectionBoundaries: [Int] {
            entries.indices.filter { if case .header = entries[$0] { return true } else { return false } } + [entries.count]
        }

        /// The issue being dragged and the sub-issues hanging under it, which come along.
        private func moving(_ item: Item) -> Set<String> {
            guard let projectId = item.projectId,
                  let column = model.listColumns(projectId: projectId).first(where: { $0.nesting.members.contains { $0.id == item.id } })
            else { return [item.id] }
            return column.nesting.descendants(of: item.id).union([item.id])
        }

        /// Where an issue dropped above `row` lands: the section it joins, and its place among that section's
        /// other issues, leaving out the ones it brings along. Above a header is the end of the section before it.
        private func landing(above row: Int, moving: Set<String>) -> (sectionId: String, header: Int, index: Int)? {
            guard row > 0 else { return nil }
            guard let header = entries[..<min(row, entries.count)].lastIndex(where: {
                if case .header = $0 { return true } else { return false }
            }), case .header(let section) = entries[header] else { return nil }
            let issues = entries[(header + 1)..<row].filter { entry in
                if case .row(let issue) = entry { !moving.contains(issue.item.id) } else { false }
            }
            return (section.id, header, issues.count)
        }

        /// The column by status a section of the project's list shows, hidden on the board or not.
        private func statusColumn(_ sectionId: String) -> BoardColumn? {
            guard let projectId = model.currentProjectId else { return nil }
            return model.listColumns(projectId: projectId).first { $0.id == sectionId }
        }

        /// The column a section of a project's list shows, which a dropped issue joins.
        private func column(for sectionId: String, of item: Item) -> BoardColumn? {
            guard let projectId = item.projectId else { return nil }
            return model.listColumns(projectId: projectId).first { $0.id == sectionId }
        }

        /// Within its section the issue changes place; in another one it takes that status, as on the board. In a
        /// milestone's groups by epic it joins the epic it is dropped into; on the roadmap an epic goes into the
        /// milestone it is dropped into.
        func dropItem(_ id: String, above row: Int) -> Bool {
            guard let item = model.item(id: id), let landing = landing(above: row, moving: moving(item)) else { return false }
            if let section = section(landing.sectionId), section.kind != .status {
                return model.dropPlanned(item, into: section.kind, scope: model.scope)
            }
            guard let column = column(for: landing.sectionId, of: item) else { return false }
            model.drop(item, in: column, at: landing.index)
            return true
        }

        private func section(_ id: String) -> IssueSectionModel? {
            for entry in entries {
                if case .header(let section) = entry, section.id == id { return section }
            }
            return nil
        }

        /// The row an issue dropped above `row` really lands above: a sub-issue among its parent's sub-issues, any
        /// other issue in front of or after the ones that stand on their own.
        private func snappedDropRow(_ id: String, above row: Int) -> Int {
            guard let item = model.item(id: id) else { return row }
            let moving = moving(item)
            guard let landing = landing(above: row, moving: moving), let column = column(for: landing.sectionId, of: item)
            else { return row }
            // The landing counts the section's rows without the issue and what it brings along, epic headers included.
            let slot = column.landing(of: item, at: landing.index, epic: model.epic(of: item)?.contentId).row
            return tableRow(slot, afterHeader: landing.header, shown: column.nesting.rows(without: moving))
        }

        /// The table row where row `slot` of a section's `shown` rows stands; the section's header is at `header`.
        private func tableRow(_ slot: Int, afterHeader header: Int, shown: [Nesting.Row]) -> Int {
            let kept = Set(shown.map(\.id))
            var seen = 0
            var current = header + 1
            while current < entries.count, !entries[current].isHeader {
                let id: String? = switch entries[current] {
                case .row(let issue): issue.item.id
                case .epic(_, let group): group.id
                case .header: nil
                }
                if let id, kept.contains(id) {
                    if seen == slot { return current }
                    seen += 1
                }
                current += 1
            }
            return current
        }

        /// Drops the issues of an epic's group above `row`, together. `epic` is the epic's node id; the group is the
        /// first one of it in the list.
        func dropGroup(epic: String, above row: Int) -> Bool {
            guard let section = entries.first(where: { entry in
                if case .epic(_, let group) = entry { group.contentId == epic } else { false }
            }), case .epic(let sectionId, _) = section else { return false }
            return dropGroup("\(sectionId)\u{1F}\(epic)", above: row)
        }

        private func dropGroup(_ payload: String, above row: Int) -> Bool {
            guard let dragged = draggedGroup(payload), let target = groupLanding(dragged, above: row) else { return false }
            model.drop(dragged.group, members: dragged.members, in: target.column, at: target.index)
            return true
        }

        /// The epic's header a drag carries, with the issues it brings along: the section it comes from, its group
        /// there and the group's issues.
        private func draggedGroup(_ info: NSDraggingInfo) -> (group: Nesting.EpicGroup, members: [Item])? {
            info.draggingPasteboard.string(forType: Self.epicType).flatMap(draggedGroup)
        }

        private func draggedGroup(_ payload: String) -> (group: Nesting.EpicGroup, members: [Item])? {
            let parts = payload.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
            guard parts.count == 2, let source = statusColumn(parts[0]),
                  let group = source.nesting.groups.first(where: { $0.contentId == parts[1] }) else { return nil }
            return (group, source.members(of: group))
        }

        /// Where an epic's issues dropped above `row` land: the section and their place among its issues. Only the
        /// board's columns take them, as a whole.
        private func groupLanding(_ dragged: (group: Nesting.EpicGroup, members: [Item]), above row: Int)
            -> (column: BoardColumn, header: Int, index: Int)? {
            let moving = Set(dragged.members.map(\.id))
            guard let landing = landing(above: max(row, 1), moving: moving), section(landing.sectionId)?.kind == .status,
                  let column = statusColumn(landing.sectionId) else { return nil }
            return (column, landing.header, landing.index)
        }

        func tableView(
            _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard info.draggingSource as? NSTableView === tableView else { return [] }
            if info.draggingPasteboard.string(forType: Self.epicType) != nil {
                // The gap opens where the epic's issues will land, together, as a whole.
                guard let dragged = draggedGroup(info), let target = groupLanding(dragged, above: row) else { return [] }
                let moving = Set(dragged.members.map(\.id))
                let slot = target.column.landing(ofGroup: dragged.group.contentId, moving: moving, at: target.index).row
                tableView.setDropRow(tableRow(slot, afterHeader: target.header, shown: target.column.nesting.rows(without: moving)), dropOperation: .above)
                return .move
            }
            if let id = info.draggingPasteboard.string(forType: Self.itemType) {
                // Groups by epic or by milestone take an issue in at their end; a group of its own isn't a place.
                if let item = model.item(id: id), let landing = landing(above: max(row, 1), moving: moving(item)),
                   let section = section(landing.sectionId), section.kind != .status {
                    guard model.canDropPlanned(item, into: section.kind) else { return [] }
                    tableView.setDropRow(end(of: section.id), dropOperation: .above)
                    return .move
                }
                // Anywhere below the first header; in the middle of a row means just above it. The gap opens where
                // the issue will land, which for a sub-issue is among its parent's sub-issues.
                tableView.setDropRow(snappedDropRow(id, above: max(row, 1)), dropOperation: .above)
                return .move
            }
            guard let nearest = sectionBoundaries.min(by: { abs($0 - row) < abs($1 - row) }) else { return [] }
            tableView.setDropRow(nearest, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation
        ) -> Bool {
            if let id = info.draggingPasteboard.string(forType: Self.itemType) { return dropItem(id, above: row) }
            if let payload = info.draggingPasteboard.string(forType: Self.epicType) {
                return dropGroup(payload, above: row)
            }
            guard let id = info.draggingPasteboard.string(forType: Self.sectionType) else { return false }
            var target: String?
            if entries.indices.contains(row), case .header(let section) = entries[row] { target = section.id }
            model.moveListSection(id, before: target)
            return true
        }

        // MARK: Pointer

        func item(at row: Int) -> Item? {
            guard entries.indices.contains(row), case .row(let model) = entries[row] else { return nil }
            return model.item
        }

        // MARK: Sticky header and collapsing

        /// Places the sticky header over the top of the list. It shows only while the current section's own
        /// header has scrolled out of view, and the next header pushes it up as it arrives.
        func updateSticky() {
            guard let table, let scrollView, let sticky else { return }
            let height = Theme.rowHeight
            let top = scrollView.contentView.bounds.minY
            var current: (row: Int, section: IssueSectionModel)?
            var next: Int?
            for (row, entry) in entries.enumerated() {
                guard case .header(let section) = entry else { continue }
                if table.rect(ofRow: row).minY <= top + 0.5 {
                    current = (row, section)
                } else {
                    next = row
                    break
                }
            }
            guard let current, table.rect(ofRow: current.row).minY < top - 0.5 else {
                sticky.isHidden = true
                stickySectionId = nil
                return
            }
            var offset: CGFloat = 0
            if let next {
                let gap = table.rect(ofRow: next).minY - top
                if gap < height { offset = gap - height }
            }
            sticky.configure(current.section, model: model)
            stickySectionId = current.section.id
            // `offset` is zero or negative: the next header pushes the sticky one up.
            let y = scrollView.isFlipped ? offset : scrollView.bounds.height - height - offset
            sticky.frame = NSRect(x: 0, y: y, width: scrollView.bounds.width, height: height)
            sticky.isHidden = false
        }

        #if DEBUG
        var listSummary: String {
            let rows = entries.map { entry -> String in
                switch entry {
                case .header(let section): "[\(section.title)\(section.collapsed ? " folded" : "")]"
                case .row(let row): row.item.displayNumber
                case .epic(_, let group): "<\(group.epic.title)\(group.folded ? " folded" : "") \(group.count)>"
                }
            }
            let shown = sticky.map { !$0.isHidden } ?? false
            let place = "\(stickySectionId ?? "?") y=\(Int(sticky?.frame.minY ?? 0))"
            return "sticky=" + (shown ? place : "hidden") + " rows=" + rows.joined(separator: " ")
        }
        #endif

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            if row >= 0, let header = sender.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueHeaderCell {
                if let event = NSApp.currentEvent { header.click(at: header.convert(event.locationInWindow, from: nil)) }
                return
            }
            // A click on an epic's header opens the epic; one on its arrow folds its issues away or shows them again.
            if entries.indices.contains(row), case .epic(_, let group) = entries[row] {
                if let event = NSApp.currentEvent,
                   let cell = sender.view(atColumn: 0, row: row, makeIfNecessary: false) as? EpicHeaderRowCell,
                   cell.isOnFold(cell.convert(event.locationInWindow, from: nil)) {
                    model.toggleEpicGroup(group)
                } else {
                    model.open(group.epic)
                }
                return
            }
            guard let item = item(at: row) else { return }
            // ⌘- and Shift-clicks pick issues, as does a click on the checkbox at the start of the row.
            if model.handleSelectionClick(on: item) { return }
            if let event = NSApp.currentEvent,
               let cell = sender.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell,
               cell.checkboxRect.contains(cell.convert(event.locationInWindow, from: nil)) {
                model.toggleSelection(item)
                return
            }
            if let event = NSApp.currentEvent,
               let cell = sender.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell,
               cell.isOnFold(cell.convert(event.locationInWindow, from: nil)) {
                model.toggleFolded(item)
                return
            }
            if let event = NSApp.currentEvent,
               let cell = sender.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell,
               let part = cell.part(at: cell.convert(event.locationInWindow, from: nil)) {
                Dropdown.show(below: part.rect, in: cell, model: model) { close in
                    ItemPicker(kind: part.kind, itemId: item.id, close: close)
                }
                return
            }
            model.open(item)
        }

        /// Highlights the part under the pointer, so it reads as clickable.
        func hoverPart(row: Int, pointInTable point: NSPoint) {
            guard let table else { return }
            for visible in visibleRows(in: table) {
                // An epic's header lights up as a whole, or just its arrow.
                if let header = table.view(atColumn: 0, row: visible, makeIfNecessary: false) as? EpicHeaderRowCell {
                    let local = header.convert(point, from: table)
                    header.hoveringFold = visible == row && header.isOnFold(local)
                    header.highlighted = visible == row && !header.hoveringFold && draggedIds.isEmpty
                    continue
                }
                guard let cell = table.view(atColumn: 0, row: visible, makeIfNecessary: false) as? IssueRowCell else { continue }
                let local = cell.convert(point, from: table)
                cell.hoveredPart = visible == row ? cell.part(at: local)?.kind : nil
                cell.hoveringFold = visible == row && cell.isOnFold(local)
            }
        }

        func hover(row: Int) {
            let id = item(at: row)?.id
            guard id != hoveredId else { return }
            let previous = hoveredId
            hoveredId = id
            if let previous { model.pointer(.left, previous) }
            if let id { model.pointer(.entered, id) }
            refreshHighlight(for: [previous, id])
        }

        /// Keeps the highlight under the pointer while the list scrolls beneath it.
        @objc func scrolled(_ notification: Notification) {
            updateSticky()
            table?.updateHoverFromCurrentMouseLocation()
        }

        func menu(forRow row: Int) -> NSMenu? {
            if entries.indices.contains(row), case .header(let section) = entries[row] {
                return Self.sectionMenu(section, model: model)
            }
            if entries.indices.contains(row), case .epic(let sectionId, let group) = entries[row] {
                return EpicGroupMenu.menu(group, in: statusColumn(sectionId), model: model)
            }
            guard let item = item(at: row) else { return nil }
            return ItemMenuBuilder(model: model, item: item).menu()
        }

        /// A section header's menu: fold this one or all of them, or start an issue in it.
        static func sectionMenu(_ section: IssueSectionModel, model: AppModel) -> NSMenu {
            let menu = NSMenu()
            let fold = ClosureMenuItem(String(localized: section.collapsed ? .unfoldGroup : .foldGroup)) { [model] in model.toggleSection(section.id) }
            fold.image = MenuIcons.symbol(section.collapsed ? "chevron.down" : "chevron.right")
            menu.addItem(fold)
            let all = ClosureMenuItem(String(localized: section.collapsed ? .unfoldAllGroups : .foldAllGroups)) { [model] in
                model.toggleAllSections(like: section.id)
            }
            all.image = MenuIcons.symbol(section.collapsed ? "chevron.down.2" : "chevron.right.2")
            menu.addItem(all)
            // Sections dragged into an order of your own go back to the usual one, as on iPhone and iPad.
            if !model.customListOrder().isEmpty {
                let usual = ClosureMenuItem(String(localized: .backToUsualOrder)) { [model] in
                    withAnimation(Theme.spring) { model.resetListOrder(in: model.scope ?? .myIssues) }
                }
                usual.image = MenuIcons.symbol("arrow.up.arrow.down")
                menu.addItem(usual)
            }
            if section.canAdd {
                menu.addItem(.separator())
                let add = ClosureMenuItem(String(localized: .newIssueInGroupMenu(group: section.title))) { [model] in
                    model.addIssue(in: section.kind, optionId: section.optionId, sectionId: section.id)
                }
                add.image = MenuIcons.symbol("plus")
                menu.addItem(add)
            }
            for entry in menu.items where entry.image != nil { entry.preferredImageVisibility = .visible }
            return menu
        }
    }
}

/// A table that reports the row under the pointer and builds a context menu per row.
final class HoverTableView: NSTableView {
    weak var coordinator: IssueTable.Coordinator?
    private var tracking: NSTrackingArea?

    // The app's own key handling moves through issues; the table should not take the keyboard.
    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        coordinator?.hover(row: row(at: point))
        coordinator?.hoverPart(row: row(at: point), pointInTable: point)
    }

    override func mouseExited(with event: NSEvent) {
        coordinator?.hover(row: -1)
        coordinator?.hoverPart(row: -1, pointInTable: .zero)
    }

    func updateHoverFromCurrentMouseLocation() {
        guard let window, window.isKeyWindow else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        coordinator?.hover(row: visibleRect.contains(point) ? row(at: point) : -1)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = coordinator?.menu(forRow: row(at: convert(event.locationInWindow, from: nil)))
        // A click shows the menu in glass, like the pickers; VoiceOver's Show Menu still gets the AppKit menu.
        if let menu, ContextMenus.isContextClick(event), let model = coordinator?.model {
            GlassMenu.show(menu, at: event, in: self, model: model)
            return nil
        }
        return menu
    }
}

/// The header over the issues of an epic standing together in a section: the epic's icon in line with the
/// issues' status icons, where the line down to them starts, its name, how many of its issues are there, and the
/// arrow that folds them away. A click opens the epic, one on the arrow folds its issues or shows them again, and
/// dragging it moves them all.
final class EpicHeaderRowCell: NSView {
    private var group: Nesting.EpicGroup?
    private var title = NSAttributedString()
    private var count = NSAttributedString()
    /// The arrow, where it was drawn last.
    private(set) var foldRect: NSRect?
    var highlighted = false {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }
    var hoveringFold = false {
        didSet {
            guard hoveringFold != oldValue else { return }
            needsDisplay = true
            toolTip = hoveringFold ? group.map { String(localized: $0.folded ? .unfoldEpicGroupTooltip(count: $0.count) : .foldEpicGroupTooltip) } : nil
        }
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidChangeEffectiveAppearance() {
        configure(group, force: true)
    }

    func configure(_ group: Nesting.EpicGroup?, force: Bool = false) {
        guard force || group != self.group else { return }
        // A row used again for another epic starts without the pointer on it.
        if group?.id != self.group?.id {
            highlighted = false
            hoveringFold = false
        }
        self.group = group
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        title = NSAttributedString(string: group?.epic.title ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(Theme.text),
            .paragraphStyle: truncating,
        ])
        count = NSAttributedString(string: group.map { "\($0.count)" } ?? "", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(Theme.textTertiary),
        ])
        if let group {
            setAccessibilityLabel(String(localized: .epicGroupSpoken(epic: group.epic.title, count: group.count)))
            setAccessibilityValue(String(localized: group.folded ? .sectionFolded : .sectionOpen))
        }
        needsDisplay = true
    }

    func isOnFold(_ point: NSPoint) -> Bool {
        foldRect?.insetBy(dx: -3, dy: -4).contains(point) ?? false
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    /// The header as a card lifting off the list, for dragging the epic's issues.
    func dragImage() -> NSImage? {
        guard let content = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        let wasHighlighted = highlighted, wasHovering = hoveringFold
        highlighted = false
        hoveringFold = false
        drawsLine = false
        cacheDisplay(in: bounds, to: content)
        drawsLine = true
        highlighted = wasHighlighted
        hoveringFold = wasHovering
        needsDisplay = true
        let appearance = effectiveAppearance
        return NSImage(size: bounds.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                let card = NSBezierPath(
                    roundedRect: rect.insetBy(dx: IssueTable.inset, dy: 1).insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7
                )
                NSColor(Theme.cardLifted).setFill()
                card.fill()
                NSColor(Theme.cardLiftedBorder).setStroke()
                card.lineWidth = 1
                card.stroke()
            }
            content.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
    }

    /// Off while the header is drawn as a card being dragged.
    private var drawsLine = true

    override func draw(_ dirtyRect: NSRect) {
        guard let group, let context = NSGraphicsContext.current?.cgContext else { return }
        let midY = bounds.height / 2
        if highlighted {
            NSColor(Theme.selected).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        // In line with the issues' status icons: after the priority and number columns.
        var x: CGFloat = IssueTable.inset + 28 + 14 + 10 + 40 + 10
        PlanningGlyph.drawEpic(in: CGRect(x: x, y: midY - 7, width: 14, height: 14), cg: context)
        if !group.folded, drawsLine {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x + 7, y: midY + 9))
            line.line(to: NSPoint(x: x + 7, y: bounds.height))
            line.lineWidth = 1
            NSColor(Theme.treeLine).setStroke()
            line.stroke()
        }
        x += 14 + 10
        let titleSize = title.size()
        let countSize = count.size()
        let room = bounds.width - x - IssueTable.inset - 14 - countSize.width - 30
        let titleWidth = min(titleSize.width, max(room, 40))
        title.draw(in: NSRect(x: x, y: midY - titleSize.height / 2, width: titleWidth, height: titleSize.height))
        x += titleWidth + 8
        count.draw(at: NSPoint(x: x, y: midY - countSize.height / 2))
        x += countSize.width + 6
        let rect = NSRect(x: x, y: midY - 7, width: 14, height: 14)
        foldRect = rect
        if hoveringFold {
            NSColor(Theme.partHover).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5).fill()
        }
        IssueRowCell.drawFoldArrow(
            folded: group.folded, center: NSPoint(x: rect.midX, y: rect.midY),
            color: NSColor(hoveringFold ? Theme.textSecondary : Theme.textTertiary)
        )
    }
}

/// Row container without the system's selection and separator drawing.
final class PlainRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawSeparator(in dirtyRect: NSRect) {}
}

// MARK: - Cells

/// One issue, drawn directly. Configuring and drawing a recycled cell takes a fraction of a millisecond.
final class IssueRowCell: NSView, NSViewToolTipOwner {
    weak var model: AppModel?
    private var row: IssueRowModel?
    /// The date's place, for its tooltip.
    private var dateRect = NSRect.zero
    /// The number's place, whose tooltip names the repository.
    private var numberRect = NSRect.zero
    private var highlighted = false
    private var number = NSAttributedString()
    private var title = NSAttributedString()
    private var date = NSAttributedString()
    private var project: NSAttributedString?
    private var subCount: NSAttributedString?
    private var blockerText: NSAttributedString?
    private var parentHint: NSAttributedString?
    private var milestoneText: NSAttributedString?
    private var milestoneSize = NSSize.zero
    private var dueText: NSAttributedString?
    private var dueIcon: NSImage?
    private var labels: [(text: NSAttributedString, size: NSSize, color: NSColor)] = []
    // Measured once when the row is configured; measuring text on every draw is what makes drawing slow.
    private var numberSize = NSSize.zero
    private var titleSize = NSSize.zero
    private var dateSize = NSSize.zero
    private var projectSize = NSSize.zero
    private var subCountSize = NSSize.zero
    private var blockerSize = NSSize.zero
    private var parentHintSize = NSSize.zero
    private var dueSize = NSSize.zero
    /// Where the clickable parts were drawn last, in this cell's coordinates.
    private(set) var parts: [(kind: PickerKind, rect: NSRect)] = []
    /// The part under the pointer, which gets a soft highlight like a button.
    var hoveredPart: PickerKind? {
        didSet { if hoveredPart != oldValue { needsDisplay = true } }
    }

    func part(at point: NSPoint) -> (kind: PickerKind, rect: NSRect)? {
        parts.first { $0.rect.insetBy(dx: -3, dy: -4).contains(point) }
    }

    /// The arrow that folds the sub-issues hanging under this issue in or out, where it was drawn last.
    private(set) var foldRect: NSRect?
    var hoveringFold = false {
        didSet { if hoveringFold != oldValue { needsDisplay = true } }
    }

    func isOnFold(_ point: NSPoint) -> Bool {
        foldRect?.insetBy(dx: -3, dy: -4).contains(point) ?? false
    }

    /// Sub-issues hang this much further in per level, down to a few levels.
    static let indent: CGFloat = 20
    static let deepestIndent = 5
    /// Off while the row is drawn as a card being dragged.
    private var drawsTree = true

    /// The start of the row, where the checkbox shows: a click there picks the issue.
    var checkboxRect: NSRect {
        NSRect(x: IssueTable.inset, y: 0, width: 22, height: bounds.height)
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    func configure(_ row: IssueRowModel, highlighted: Bool) {
        if row != self.row {
            self.row = row
            let item = row.item
            // Picked rows are filled with the accent colour, as a Mac list shows its selection, and read in white.
            let onAccent = row.selected
            let primary = onAccent ? NSColor.white : NSColor(Theme.text)
            let secondary = onAccent ? NSColor.white.withAlphaComponent(0.88) : NSColor(Theme.textSecondary)
            let tertiary = onAccent ? NSColor.white.withAlphaComponent(0.8) : NSColor(Theme.textTertiary)
            let truncating = NSMutableParagraphStyle()
            truncating.lineBreakMode = .byTruncatingTail
            number = NSAttributedString(string: item.displayNumber, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: tertiary,
            ])
            title = NSAttributedString(string: item.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: primary,
                .paragraphStyle: truncating,
            ])
            date = NSAttributedString(string: relativeDate(item.updatedAt), attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: tertiary,
            ])
            project = row.projectTitle.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: tertiary,
                    .paragraphStyle: truncating,
                ])
            }
            parentHint = row.showsParent ? item.parentNumber.map { number in
                NSAttributedString(string: row.parentIsEpic ? item.parentTitle ?? "#\(number)" : "#\(number) \(item.parentTitle ?? "")", attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: tertiary,
                    .paragraphStyle: truncating,
                ])
            } : nil
            subCount = item.subTotal > 0
                ? NSAttributedString(string: "\(item.subCompleted)/\(item.subTotal)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: secondary,
                ])
                : nil
            blockerText = row.blocker?.text.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: onAccent ? NSColor.white : NSColor(Theme.blocked),
                ])
            }
            if let due = row.due {
                let color = onAccent ? NSColor.white : NSColor(due.tone.color)
                dueText = NSAttributedString(string: due.label, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                ])
                dueIcon = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
            } else {
                dueText = nil
                dueIcon = nil
            }
            milestoneText = row.milestone.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: secondary,
                    .paragraphStyle: truncating,
                ])
            }
            milestoneSize = milestoneText?.size() ?? .zero
            // An epic's own label says what the row shows already.
            labels = item.labels.filter { !(item.isEpic && Item.isEpicLabel($0.name)) }.prefix(3).map { label in
                let text = NSAttributedString(string: label.name, attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: onAccent ? NSColor.white : NSColor(Theme.textBody),
                ])
                return (text, text.size(), NSColor(Theme.labelColor(label.color)))
            }
            numberSize = number.size()
            titleSize = title.size()
            dateSize = date.size()
            projectSize = project?.size() ?? .zero
            subCountSize = subCount?.size() ?? .zero
            blockerSize = blockerText?.size() ?? .zero
            parentHintSize = parentHint?.size() ?? .zero
            dueSize = dueText?.size() ?? .zero
            var spoken = row.due.map {
                String(localized: .issueRowSpokenWithDue(number: item.displayNumber, title: item.title, due: $0.tooltip))
            } ?? "\(item.displayNumber) \(item.title)"
            if row.blocker != nil, let blocked = model?.tooltip(.blockedBy, for: item) { spoken += ", \(blocked)" }
            setAccessibilityLabel(item.parentNumber.map { number in
                let parent = String(localized: row.parentIsEpic
                    ? .epicTooltip(epic: item.parentTitle ?? "#\(number)") : .subIssueOf(number: "#\(number)"))
                return "\(spoken), \(parent)"
            } ?? spoken)
            needsDisplay = true
        }
        if highlighted != self.highlighted {
            self.highlighted = highlighted
            needsDisplay = true
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    /// The row as a card lifted off the list, to drag around.
    func dragImage() -> NSImage? {
        guard let content = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        // Without the hover fill and checkbox, which belong to the pointer, not to the issue.
        let wasHighlighted = highlighted, wasHovered = hoveredPart
        highlighted = false
        hoveredPart = nil
        drawsTree = false
        cacheDisplay(in: bounds, to: content)
        drawsTree = true
        highlighted = wasHighlighted
        hoveredPart = wasHovered
        needsDisplay = true
        let appearance = effectiveAppearance
        return NSImage(size: bounds.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                let card = NSBezierPath(
                    roundedRect: rect.insetBy(dx: IssueTable.inset, dy: 1).insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7
                )
                NSColor(Theme.cardLifted).setFill()
                card.fill()
                NSColor(Theme.cardLiftedBorder).setStroke()
                card.lineWidth = 1
                card.stroke()
            }
            // On top of the card; a plain `draw(in:)` would copy the transparent pixels over it.
            content.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        let midY = size.height / 2

        let onAccent = row.selected
        if row.selected {
            NSColor(Theme.accentFill).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
        } else if highlighted {
            NSColor(Theme.selected).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        // The checkbox sits under the section headers' fold arrow; it shows on hover and while picking.
        if row.selected || row.selecting || highlighted {
            drawCheckbox(checked: row.selected, center: NSPoint(x: IssueTable.inset + 15, y: midY))
        }
        // Each part lights up in a shape that suits it, as in Linear: a small square behind an icon, a halo
        // around avatars, and chips in their own shape.
        let partHover = onAccent ? NSColor.white.withAlphaComponent(0.22) : NSColor(Theme.partHover)
        func iconHover(_ kind: PickerKind, _ rect: NSRect) {
            guard hoveredPart == kind else { return }
            partHover.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -4), xRadius: 5, yRadius: 5).fill()
        }
        var parts: [(kind: PickerKind, rect: NSRect)] = []
        let canEditFields = row.item.kind != .draft

        // Left to right: priority, number, status. The priority lines up with the headers' status icon.
        var x: CGFloat = IssueTable.inset + 28
        if row.showsPriority {
            let rect = NSRect(x: x, y: midY - 7, width: 14, height: 14)
            parts.append((.priority, rect))
            iconHover(.priority, rect)
        }
        drawPriority(row.priority, x: x, midY: midY, onAccent: onAccent)
        x += 14 + 10
        number.draw(at: NSPoint(x: x, y: midY - numberSize.height / 2))
        let numberRect = NSRect(x: x, y: midY - 9, width: numberSize.width, height: 18)
        x += 40 + 10
        // A sub-issue hangs under its parent: status and title move in, with a line from the parent's status.
        if drawsTree { drawTree(row, from: x, midY: midY) }
        x += CGFloat(min(row.nest.depth, Self.deepestIndent)) * Self.indent
        if row.showsStatus {
            let rect = NSRect(x: x, y: midY - 7, width: 14, height: 14)
            parts.append((.status, rect))
            iconHover(.status, rect)
        }
        var glyph = row.glyph
        if onAccent, glyph.category != .completed, glyph.category != .canceled { glyph.color = .white }
        StatusPainter.draw(glyph, in: CGRect(x: x, y: midY - 7, width: 14, height: 14), cg: context)
        x += 14 + 10
        // The arrow that folds the sub-issues under this issue in or out.
        if row.nested != nil {
            let rect = NSRect(x: x - 4, y: midY - 7, width: 14, height: 14)
            foldRect = rect
            if hoveringFold {
                partHover.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5).fill()
            }
            Self.drawFoldArrow(folded: row.folded, center: NSPoint(x: rect.midX, y: rect.midY), color: onAccent ? .white : NSColor(Theme.textSecondary))
            x = rect.maxX + 8
        } else {
            foldRect = nil
        }

        // Right to left: assignees, date, project, labels.
        var right = size.width - IssueTable.inset - 14
        var avatarRing = NSColor(row.selected ? Theme.accentFill : highlighted ? Theme.selected : Theme.panel)
        if canEditFields {
            let count = CGFloat(max(min(row.item.assignees.count, 3), 1))
            let width = 18 + (count - 1) * 13
            let rect = NSRect(x: right - width, y: midY - 9, width: width, height: 18)
            parts.append((.assignees, rect))
            if hoveredPart == .assignees {
                let halo = rect.insetBy(dx: -3, dy: -3)
                avatarRing = partHover
                avatarRing.setFill()
                NSBezierPath(roundedRect: halo, xRadius: halo.height / 2, yRadius: halo.height / 2).fill()
                if row.item.assignees.isEmpty {
                    // Where an avatar would be, as Linear shows for an unassigned issue.
                    let circle = NSRect(x: rect.maxX - 18, y: midY - 9, width: 18, height: 18).insetBy(dx: 1.5, dy: 1.5)
                    let dashed = NSBezierPath(ovalIn: circle)
                    dashed.lineWidth = 1.2
                    dashed.setLineDash([2.2, 2], count: 2, phase: 0)
                    NSColor(Theme.textTertiary).setStroke()
                    dashed.stroke()
                }
            }
        }
        drawAvatars(row.item.assignees, rightEdge: right, midY: midY, ring: avatarRing, context: context)
        right -= 30 + 10
        date.draw(at: NSPoint(x: right - dateSize.width, y: midY - dateSize.height / 2))
        dateRect = NSRect(x: right - dateSize.width, y: midY - 9, width: dateSize.width, height: 18)
        right -= 52 + 10
        if let dueText {
            let icon = dueIcon?.size ?? .zero
            let width = 7 + icon.width + 4 + dueSize.width + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            parts.append((.dueDate, rect))
            drawChip(rect, hovered: hoveredPart == .dueDate)
            dueIcon?.draw(
                in: NSRect(x: rect.minX + 7, y: midY - icon.height / 2, width: icon.width, height: icon.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            dueText.draw(at: NSPoint(x: rect.minX + 7 + icon.width + 4, y: midY - dueSize.height / 2))
            right = rect.minX - 10
        }
        if let project {
            let width = min(projectSize.width, 160)
            project.draw(with: NSRect(x: right - width, y: midY - projectSize.height / 2, width: width, height: projectSize.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            right -= width + 10
        }
        if let milestoneText {
            let textWidth = min(milestoneSize.width, 120)
            let width = 7 + 10 + 5 + textWidth + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            if rect.minX > x + 160 {
                parts.append((.milestone, rect))
                drawChip(rect, hovered: hoveredPart == .milestone)
                PlanningGlyph.drawMilestone(row.milestoneMark, in: CGRect(x: rect.minX + 7, y: midY - 5, width: 10, height: 10), cg: context)
                milestoneText.draw(
                    with: NSRect(x: rect.minX + 7 + 10 + 5, y: midY - milestoneSize.height / 2, width: textWidth, height: milestoneSize.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
                )
                right = rect.minX - 6
            }
        }
        // The project's own fields the view shows, as far as there is room.
        for field in row.chips.reversed() {
            let text = NSAttributedString(string: field.text, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor(Theme.textSecondary),
            ])
            let textSize = text.size()
            let textWidth = min(textSize.width, 120)
            let width = 7 + 10 + 5 + textWidth + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            guard rect.minX > x + 160 else { break }
            drawChip(rect, hovered: false)
            let icon = CGRect(x: rect.minX + 7, y: midY - 5, width: 10, height: 10)
            switch field.icon {
            case .option(let color): PlanningGlyph.drawDot(color, in: icon.insetBy(dx: -1, dy: -1), cg: context)
            case .iteration: MenuIcons.symbol("arrow.triangle.2.circlepath", color: Theme.textTertiary)?.draw(in: icon)
            case .date: MenuIcons.symbol("calendar", color: Theme.textTertiary)?.draw(in: icon)
            case .text: MenuIcons.symbol("text.alignleft", color: Theme.textTertiary)?.draw(in: icon)
            }
            text.draw(
                with: NSRect(x: rect.minX + 7 + 10 + 5, y: midY - textSize.height / 2, width: textWidth, height: textSize.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            )
            right = rect.minX - 6
        }
        var labelsRect: NSRect?
        for label in labels.reversed() {
            let textSize = label.size
            let width = textSize.width + 7 + 7 + 5 + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            guard rect.minX > x + 120 else { break }
            labelsRect = labelsRect.map { $0.union(rect) } ?? rect
            let tint = onAccent ? NSColor.white.withAlphaComponent(canEditFields && hoveredPart == .labels ? 0.3 : 0.2)
                : label.color.withAlphaComponent(canEditFields && hoveredPart == .labels ? 0.24 : 0.14)
            tint.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            label.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 7, y: midY - 3.5, width: 7, height: 7)).fill()
            label.text.draw(at: NSPoint(x: rect.minX + 19, y: midY - textSize.height / 2))
            right = rect.minX - 6
        }

        if canEditFields, let labelsRect { parts.append((.labels, labelsRect)) }

        // The title takes what is left, with the sub-issue count and, when blocked, a flag with what blocks it
        // directly after it, and the parent of a sub-issue whose parent is elsewhere.
        let subWidth: CGFloat? = subCount == nil ? nil : subCountSize.width + 7 + 11 + 4 + 7
        let blockedWidth: CGFloat? = row.blocker == nil ? nil : blockerText == nil ? 26 : 7 + 11 + 4 + blockerSize.width + 7
        let beside = (subWidth.map { $0 + 10 } ?? 0) + (blockedWidth.map { $0 + 6 } ?? 0)
        let hintWidth: CGFloat? = parentHint == nil ? nil : 7 + 11 + 4 + parentHintSize.width + 7
        // The parent keeps some room as long as the title keeps more.
        let hintRoom = hintWidth.map { min($0, 200) + 10 } ?? 0
        let reserve = right - 12 - x - beside - hintRoom >= 200 ? hintRoom : 0
        let available = max(40, right - 12 - x - beside - reserve)
        let titleWidth = min(titleSize.width, available)
        title.draw(
            with: NSRect(x: x, y: midY - titleSize.height / 2, width: available, height: titleSize.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        if let subCount, let subWidth {
            let rect = NSRect(x: x + titleWidth + 10, y: midY - 10, width: subWidth, height: 20)
            parts.append((.subIssues, rect))
            drawChip(rect, hovered: hoveredPart == .subIssues)
            let origin = NSPoint(x: rect.minX + 7, y: midY - 5.5)
            let glyph = NSBezierPath()
            glyph.move(to: NSPoint(x: origin.x + 2.3, y: origin.y + 1.8))
            glyph.line(to: NSPoint(x: origin.x + 2.3, y: origin.y + 5.5))
            glyph.curve(
                to: NSPoint(x: origin.x + 4.1, y: origin.y + 7.3),
                controlPoint1: NSPoint(x: origin.x + 2.3, y: origin.y + 6.7),
                controlPoint2: NSPoint(x: origin.x + 2.9, y: origin.y + 7.3)
            )
            glyph.line(to: NSPoint(x: origin.x + 6, y: origin.y + 7.3))
            glyph.lineWidth = 1.2
            glyph.lineCapStyle = .round
            (onAccent ? NSColor.white : NSColor(Theme.textSecondary)).setStroke()
            glyph.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: origin.x + 6.2, y: origin.y + 5.8, width: 3.1, height: 3.1))
            dot.lineWidth = 1.2
            dot.stroke()
            subCount.draw(at: NSPoint(x: rect.minX + 7 + 11 + 4, y: midY - subCountSize.height / 2))
        }
        var afterTitle = x + titleWidth + 10 + (subWidth.map { $0 + 6 } ?? 0)
        if let blockedWidth {
            let after = afterTitle
            afterTitle += blockedWidth + 6
            let rect = NSRect(x: after, y: midY - 10, width: blockedWidth, height: 20)
            parts.append((.blockedBy, rect))
            drawChip(rect, hovered: hoveredPart == .blockedBy)
            if let flag = onAccent ? Self.blockedFlagOnAccent : Self.blockedFlag {
                let size = flag.size
                let flagX = blockerText == nil ? rect.midX - size.width / 2 : rect.minX + 7 + (11 - size.width) / 2
                flag.draw(
                    in: NSRect(x: flagX, y: midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                )
            }
            blockerText?.draw(at: NSPoint(x: rect.minX + 7 + 11 + 4, y: midY - blockerSize.height / 2))
        }
        if let parentHint, let hintWidth {
            let width = min(hintWidth, right - 12 - afterTitle)
            if width >= 70 {
                let rect = NSRect(x: afterTitle, y: midY - 10, width: width, height: 20)
                let kind: PickerKind = row.parentIsEpic ? .epic : .parent
                parts.append((kind, rect))
                if hoveredPart == kind { drawChip(rect, hovered: true) }
                if row.parentIsEpic {
                    PlanningGlyph.drawEpic(in: CGRect(x: rect.minX + 6, y: midY - 6, width: 12, height: 12), cg: context)
                } else if let arrow = Self.parentArrow {
                    let size = arrow.size
                    arrow.draw(
                        in: NSRect(x: rect.minX + 7, y: midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                    )
                }
                let textX = rect.minX + 7 + 11 + 4
                parentHint.draw(
                    with: NSRect(x: textX, y: midY - parentHintSize.height / 2, width: rect.maxX - 7 - textX, height: parentHintSize.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
                )
            }
        }
        // Tooltips follow the parts; rebuilt only when they moved.
        if parts.map(\.rect) != self.parts.map(\.rect) || foldRect != tooltipFoldRect || numberRect != self.numberRect || toolTipsNeedUpdate {
            toolTipsNeedUpdate = false
            tooltipFoldRect = foldRect
            self.numberRect = numberRect
            removeAllToolTips()
            for part in parts { addToolTip(part.rect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            if let foldRect { addToolTip(foldRect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            addToolTip(numberRect.insetBy(dx: -3, dy: -4), owner: self, userData: nil)
            if dateRect.width > 0 { addToolTip(dateRect, owner: self, userData: nil) }
        }
        self.parts = parts
    }

    private var toolTipsNeedUpdate = true
    private var tooltipFoldRect: NSRect?

    /// Lines from the parents above down to this row: a straight one through the row for each level whose
    /// sub-issues go on below it, a branch into this row's status icon, and a line from this row's status icon
    /// down to its own sub-issues when they show.
    private func drawTree(_ row: IssueRowModel, from base: CGFloat, midY: CGFloat) {
        let depth = min(row.nest.depth, Self.deepestIndent)
        let height = bounds.height
        let path = NSBezierPath()
        for level in 0..<depth {
            let lineX = base + CGFloat(level) * Self.indent + 7
            let continues = row.nest.continues.indices.contains(level) && row.nest.continues[level]
            if level < depth - 1 {
                if continues {
                    path.move(to: NSPoint(x: lineX, y: 0))
                    path.line(to: NSPoint(x: lineX, y: height))
                }
                continue
            }
            let end = base + CGFloat(depth) * Self.indent - 3
            if continues {
                path.move(to: NSPoint(x: lineX, y: 0))
                path.line(to: NSPoint(x: lineX, y: height))
                path.move(to: NSPoint(x: lineX, y: midY))
                path.line(to: NSPoint(x: end, y: midY))
            } else {
                let radius: CGFloat = 5
                path.move(to: NSPoint(x: lineX, y: 0))
                path.line(to: NSPoint(x: lineX, y: midY - radius))
                path.curve(
                    to: NSPoint(x: lineX + radius, y: midY),
                    controlPoint1: NSPoint(x: lineX, y: midY - radius * 0.45),
                    controlPoint2: NSPoint(x: lineX + radius * 0.45, y: midY)
                )
                path.line(to: NSPoint(x: end, y: midY))
            }
        }
        if row.nested != nil, !row.folded {
            let lineX = base + CGFloat(depth) * Self.indent + 7
            path.move(to: NSPoint(x: lineX, y: midY + 10))
            path.line(to: NSPoint(x: lineX, y: height))
        }
        guard !path.isEmpty else { return }
        path.lineWidth = 1
        NSColor(Theme.treeLine).setStroke()
        path.stroke()
    }

    /// A chevron that points down while the sub-issues show and to the right while they are folded in.
    static func drawFoldArrow(folded: Bool, center: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        if folded {
            path.move(to: NSPoint(x: center.x - 1.5, y: center.y - 3.5))
            path.line(to: NSPoint(x: center.x + 2, y: center.y))
            path.line(to: NSPoint(x: center.x - 1.5, y: center.y + 3.5))
        } else {
            path.move(to: NSPoint(x: center.x - 3.5, y: center.y - 1.5))
            path.line(to: NSPoint(x: center.x, y: center.y + 2))
            path.line(to: NSPoint(x: center.x + 3.5, y: center.y - 1.5))
        }
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static var parentArrow: NSImage? {
        NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.textTertiary)]))
        )
    }

    private static var blockedFlag: NSImage? {
        NSImage(systemSymbolName: "flag.fill", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.blocked)]))
        )
    }

    /// In a picked row, which is filled with the accent colour, the flag is white like the rest of the row.
    private static var blockedFlagOnAccent: NSImage? {
        NSImage(systemSymbolName: "flag.fill", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [.white]))
        )
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let row else { return "" }
        if isOnFold(point) {
            return String(localized: row.folded ? .unfoldSubIssuesTooltip(count: row.nested ?? 0) : .foldSubIssuesTooltip)
        }
        if let part = part(at: point) { return model?.tooltip(part.kind, for: row.item) ?? "" }
        // A project's rows leave out the repository; as a project can span several, the number names it.
        if numberRect.insetBy(dx: -3, dy: -4).contains(point) { return row.item.reference ?? "" }
        if dateRect.insetBy(dx: -3, dy: -4).contains(point), let updated = row.item.updatedAt {
            var lines = [String(localized: .updatedOnDateTooltip(date: updated.formatted(date: .long, time: .shortened)))]
            if let created = row.item.createdAt {
                lines.append(String(localized: .createdOnDateTooltip(date: created.formatted(date: .long, time: .shortened))))
            }
            return lines.joined(separator: "\n")
        }
        return ""
    }

    private func drawCheckbox(checked: Bool, center: NSPoint) {
        let box = NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
        let shape = NSBezierPath(roundedRect: box.insetBy(dx: checked ? 0 : 0.6, dy: checked ? 0 : 0.6), xRadius: 4, yRadius: 4)
        if checked {
            // On the accent-filled row the box is white with the mark in the accent colour.
            NSColor.white.setFill()
            shape.fill()
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: box.minX + 3.6, y: box.midY + 0.2))
            mark.line(to: NSPoint(x: box.minX + 6, y: box.midY + 2.6))
            mark.line(to: NSPoint(x: box.maxX - 3.4, y: box.midY - 2.6))
            mark.lineWidth = 1.7
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            NSColor(Theme.accentFill).setStroke()
            mark.stroke()
        } else {
            shape.lineWidth = 1.2
            NSColor(Theme.textTertiary).setStroke()
            shape.stroke()
        }
    }

    /// The quiet parts of a row (due date, sub-issues, milestone, fields) are text with a symbol, as Mail and
    /// Reminders write them; under the pointer they light up as the button they are.
    private func drawChip(_ rect: NSRect, hovered: Bool) {
        guard hovered else { return }
        (row?.selected == true ? NSColor.white.withAlphaComponent(0.22) : NSColor(Theme.partHover)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat, onAccent: Bool = false) {
        if level == .urgent {
            let rect = NSRect(x: x + 1, y: midY - 6, width: 12, height: 12)
            NSColor(Theme.urgent).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            let mark = NSAttributedString(string: "!", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .heavy),
                .foregroundColor: NSColor(Theme.onColor),
            ])
            let markSize = mark.size()
            mark.draw(at: NSPoint(x: rect.midX - markSize.width / 2, y: rect.midY - markSize.height / 2))
            return
        }
        let bars: [(CGFloat, Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
        for (index, bar) in bars.enumerated() {
            (onAccent ? NSColor.white.withAlphaComponent(bar.1 ? 1 : 0.35) : NSColor(bar.1 ? Theme.textBody : Theme.barOff)).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: x + CGFloat(index) * 5, y: midY + 6 - bar.0, width: 3, height: bar.0),
                xRadius: 1, yRadius: 1
            ).fill()
        }
    }

    private func drawAvatars(_ people: [Person], rightEdge: CGFloat, midY: CGFloat, ring: NSColor, context: CGContext) {
        let shown = Array(people.prefix(3))
        let diameter: CGFloat = 18
        for (index, person) in shown.enumerated().reversed() {
            let offset = CGFloat(shown.count - 1 - index) * 13
            let rect = NSRect(x: rightEdge - diameter - offset, y: midY - diameter / 2, width: diameter, height: diameter)
            // A ring in the row colour separates overlapping avatars.
            if shown.count > 1 {
                ring.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5)).fill()
            }
            if let url = person.avatarUrl, let image = AvatarCache.shared.cached(url) {
                context.saveGState()
                NSBezierPath(ovalIn: rect).addClip()
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
                context.restoreGState()
            } else {
                NSColor(Avatar.color(for: person.login)).setFill()
                NSBezierPath(ovalIn: rect).fill()
                let initials = NSAttributedString(string: String(person.login.prefix(2)).uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                ])
                let initialsSize = initials.size()
                initials.draw(at: NSPoint(x: rect.midX - initialsSize.width / 2, y: rect.midY - initialsSize.height / 2))
            }
        }
    }
}

/// A status group's header: icon, name, count, and a button to add an issue with that status.
final class IssueHeaderCell: NSView {
    private var section: IssueSectionModel?
    private weak var model: AppModel?
    private let addButton = NSButton()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: .newIssueAction))?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        addButton.imagePosition = .imageOnly
        addButton.target = self
        addButton.action = #selector(add)
        addSubview(addButton)
    }

    /// The copy pinned over the top of the list takes clicks itself; headers inside the table leave them
    /// to the table, which also lets you drag them to reorder sections.
    var handlesClicks = false

    /// A click folds the section in or out, except on the + button. With Option, every section follows.
    func click(at point: NSPoint) {
        guard let section, !addButton.frame.contains(point) else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            model?.toggleAllSections(like: section.id)
        } else {
            model?.toggleSection(section.id)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !handlesClicks { super.mouseDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Inside the table the table builds the menu; the pinned copy builds its own.
        guard handlesClicks, let section, let model else { return super.menu(for: event) }
        let menu = IssueTable.Coordinator.sectionMenu(section, model: model)
        if ContextMenus.isContextClick(event) {
            GlassMenu.show(menu, at: event, in: self, model: model)
            return nil
        }
        return menu
    }

    override func mouseUp(with event: NSEvent) {
        guard handlesClicks else { return super.mouseUp(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { click(at: point) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func layout() {
        super.layout()
        addButton.frame = NSRect(x: bounds.width - IssueTable.inset - 10 - 22, y: (bounds.height - 22) / 2, width: 22, height: 22)
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    func configure(_ section: IssueSectionModel, model: AppModel) {
        self.model = model
        addButton.isHidden = !section.canAdd
        addButton.contentTintColor = NSColor(Theme.textSecondary)
        addButton.toolTip = String(localized: .newIssueInGroupTooltip(group: section.title))
        toolTip = section.style == .progress ? section.progress.map { String(localized: .milestoneProgressTooltip(done: $0.done, total: $0.total)) } : nil
        guard section != self.section else { return }
        self.section = section
        needsDisplay = true
    }

    @objc private func add() {
        guard let section else { return }
        model?.addIssue(in: section.kind, optionId: section.optionId, sectionId: section.id)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let section, let context = NSGraphicsContext.current?.cgContext else { return }
        // Opaque, so rows do not show through while it is pinned; a plain heading, as Mail and Reminders head a
        // group, with a hairline under it.
        NSColor(Theme.panel).setFill()
        bounds.fill()
        NSColor(Theme.rowSeparator).setFill()
        NSRect(x: IssueTable.inset + 10, y: bounds.height - 1, width: bounds.width - 2 * IssueTable.inset - 20, height: 1).fill()
        let midY = bounds.height / 2 + 1
        // The disclosure arrow: down while open, right while folded in.
        let arrow = NSBezierPath()
        let center = NSPoint(x: IssueTable.inset + 15, y: midY)
        // A chevron, as the system draws its disclosure arrows now.
        if section.collapsed {
            arrow.move(to: NSPoint(x: center.x - 1.5, y: center.y - 4))
            arrow.line(to: NSPoint(x: center.x + 2.5, y: center.y))
            arrow.line(to: NSPoint(x: center.x - 1.5, y: center.y + 4))
        } else {
            arrow.move(to: NSPoint(x: center.x - 4, y: center.y - 1.5))
            arrow.line(to: NSPoint(x: center.x, y: center.y + 2.5))
            arrow.line(to: NSPoint(x: center.x + 4, y: center.y - 1.5))
        }
        arrow.lineWidth = 1.6
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        NSColor(Theme.textTertiary).setStroke()
        arrow.stroke()
        let left = IssueTable.inset + 28
        let iconRect = CGRect(x: left, y: midY - 7, width: 14, height: 14)
        switch section.icon {
        case .status(let glyph): StatusPainter.draw(glyph, in: iconRect, cg: context)
        case .milestone(let mark): PlanningGlyph.drawMilestone(mark, in: iconRect, cg: context)
        case .epic: PlanningGlyph.drawEpic(in: iconRect, cg: context)
        case .plain: break
        case .dot(let color): PlanningGlyph.drawDot(color, in: iconRect, cg: context)
        case .progress(let done, let total): PlanningGlyph.drawProgress(done: done, total: total, in: iconRect, cg: context)
        case .iteration(let current):
            MenuIcons.symbol("arrow.triangle.2.circlepath", color: current ? Theme.started : Theme.textSecondary)?
                .draw(in: iconRect.insetBy(dx: 0.5, dy: 0.5))
        case .person(let person): MenuIcons.avatar(person).draw(in: iconRect.insetBy(dx: -1, dy: -1))
        case .repository: MenuIcons.symbol("book.closed", color: Theme.textSecondary)?.draw(in: iconRect)
        case .priority(let level): MenuIcons.priority(level).draw(in: iconRect)
        case .project(let look): MenuIcons.symbol(look.glyph.systemName, color: Theme.projectColor(look.color))?.draw(in: iconRect)
        case .due(let tone): MenuIcons.symbol("calendar", color: tone.color)?.draw(in: iconRect.insetBy(dx: 0.5, dy: 0.5))
        }
        let titleX = section.icon == .plain ? left : left + 22
        // Room for the count and the + button after the title.
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: section.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(section.icon == .plain ? Theme.textSecondary : Theme.text),
            .paragraphStyle: truncating,
        ])
        let titleSize = title.size()
        let titleWidth = min(titleSize.width, max(bounds.width - titleX - 140, 80))
        title.draw(with: NSRect(x: titleX, y: midY - titleSize.height / 2, width: titleWidth, height: titleSize.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let count = NSAttributedString(string: section.countText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(Theme.textTertiary),
        ])
        count.draw(at: NSPoint(x: titleX + titleWidth + 8, y: midY - count.size().height / 2))
        if let detail = section.detail {
            let text = NSAttributedString(string: detail, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor(Theme.textTertiary),
            ])
            text.draw(at: NSPoint(x: titleX + titleWidth + 8 + count.size().width + 10, y: midY - text.size().height / 2))
        }
        // How far the group is, or how much the person has open, before the + button.
        if let progress = section.progress, section.style != .plain, bounds.width > 520 {
            let right = section.canAdd ? addButton.frame.minX - 12 : bounds.width - IssueTable.inset - 14
            let bar = CGRect(x: right - Self.barWidth, y: midY - 3, width: Self.barWidth, height: 6)
            switch section.style {
            case .progress: GroupBars.drawProgress(progress, in: bar, cg: context)
            case .people: GroupBars.drawLoad(progress, share: section.load, in: bar, cg: context)
            case .plain: break
            }
        }
    }

    static let barWidth: CGFloat = 120
}

/// The bars of a view's groups, drawn the same in the list's headers wherever they appear.
enum GroupBars {
    /// Done, under way and the rest, as one bar across the group.
    static func drawProgress(_ progress: GroupProgress, in rect: CGRect, cg context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let track = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        context.addPath(track)
        context.clip()
        context.setFillColor(NSColor(Theme.textTertiary).withAlphaComponent(0.22).cgColor)
        context.fill(rect)
        guard progress.total > 0 else { return }
        let done = rect.width * CGFloat(progress.done) / CGFloat(progress.total)
        let started = rect.width * CGFloat(progress.started) / CGFloat(progress.total)
        context.setFillColor(NSColor(Theme.positive).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.minY, width: done, height: rect.height))
        context.setFillColor(NSColor(Theme.started).cgColor)
        context.fill(CGRect(x: rect.minX + done, y: rect.minY, width: started, height: rect.height))
    }

    /// What a person has open, as long as their share of the most anyone has: what is under way first, then the rest.
    static func drawLoad(_ progress: GroupProgress, share: CGFloat, in rect: CGRect, cg context: CGContext) {
        let open = progress.total - progress.done
        guard open > 0 else { return }
        let width = max(rect.height, rect.width * min(max(share, 0), 1))
        let bar = CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height)
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: bar, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
        context.clip()
        context.setFillColor(NSColor(Theme.textTertiary).withAlphaComponent(0.35).cgColor)
        context.fill(bar)
        context.setFillColor(NSColor(Theme.started).cgColor)
        context.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(progress.started) / CGFloat(open), height: bar.height))
    }
}

// MARK: - Shared drawing

extension StatusPainter {
    /// The same glyph as the SwiftUI version, for views that draw with Core Graphics.
    static func draw(_ glyph: StatusGlyph, in frame: CGRect, cg context: CGContext) {
        let rect = frame.insetBy(dx: 1.25, dy: 1.25)
        let color = NSColor(glyph.color).cgColor
        let inner = NSColor(Theme.onColor).cgColor
        let s = frame.width / 14
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: frame.minX + x * s, y: frame.minY + y * s) }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(1.5)
        if glyph.addsToProject {
            context.strokeEllipse(in: rect)
            context.setLineWidth(1.4 * s)
            context.setLineCap(.round)
            context.move(to: point(7, 4.6))
            context.addLine(to: point(7, 9.4))
            context.move(to: point(4.6, 7))
            context.addLine(to: point(9.4, 7))
            context.strokePath()
            return
        }
        switch glyph.category {
        case .backlog:
            context.setLineDash(phase: 0, lengths: [2, 2.3])
            context.strokeEllipse(in: rect)
        case .unstarted:
            context.strokeEllipse(in: rect)
        case .started:
            context.strokeEllipse(in: rect)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            context.move(to: center)
            // Clockwise from twelve o'clock in a flipped (top-left origin) coordinate system.
            context.addArc(
                center: center, radius: rect.width / 2 - 2.5,
                startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * glyph.progress, clockwise: false
            )
            context.closePath()
            context.fillPath()
        case .completed:
            context.fillEllipse(in: rect.insetBy(dx: -0.75, dy: -0.75))
            context.setStrokeColor(inner)
            context.setLineWidth(1.6 * s)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: point(4.4, 7.2))
            context.addLine(to: point(6.2, 9))
            context.addLine(to: point(9.6, 5.2))
            context.strokePath()
        case .canceled:
            context.fillEllipse(in: rect.insetBy(dx: -0.75, dy: -0.75))
            context.setStrokeColor(inner)
            context.setLineWidth(1.5 * s)
            context.setLineCap(.round)
            context.move(to: point(4.8, 4.8))
            context.addLine(to: point(9.2, 9.2))
            context.move(to: point(9.2, 4.8))
            context.addLine(to: point(4.8, 9.2))
            context.strokePath()
        }
    }
}

// MARK: - Context menu

/// The menu of the header over an epic's issues in a board column or list section: open the epic, move all of its
/// issues there to another column, fold them away or show them.
@MainActor
enum EpicGroupMenu {
    static func menu(_ group: Nesting.EpicGroup, in column: BoardColumn?, model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = ClosureMenuItem(String(localized: .openEpicCommand)) { [model] in model.open(group.epic) }
        open.image = MenuIcons.epic
        menu.addItem(open)
        if let column {
            let members = column.members(of: group)
            let projectId = members.first?.projectId
            let statuses = model.statusOptions(projectId: projectId)
            if !statuses.isEmpty {
                let move = NSMenu()
                for option in statuses {
                    let entry = ClosureMenuItem(option.name, checked: option.id == column.option?.id) { [model] in
                        model.setStatus(of: group, members: members, to: option)
                    }
                    entry.image = MenuIcons.status(model.glyph(projectId: projectId, optionId: option.id))
                    move.addItem(entry)
                }
                let title = String(localized: .moveEpicIssuesTo)
                let submenu = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                submenu.image = MenuIcons.status(column.glyph)
                submenu.submenu = move
                menu.addItem(submenu)
            }
        }
        let fold = ClosureMenuItem(String(localized: group.folded ? .showEpicIssues : .foldEpicIssues)) { [model] in
            model.toggleEpicGroup(group)
        }
        fold.image = MenuIcons.symbol(group.folded ? "chevron.down" : "chevron.right")
        menu.addItem(fold)
        ItemMenuBuilder.showImages(in: menu)
        return menu
    }
}

/// The right-click menu for an issue, used by cards, list rows and sub-issues alike. Each entry has an
/// icon, and the property submenus show the same glyphs and number keys as the dropdowns.
@MainActor
struct ItemMenuBuilder {
    let model: AppModel
    let item: Item

    func menu() -> NSMenu {
        let menu = NSMenu()
        // Keep the enabled states set here instead of AppKit's automatic ones.
        menu.autoenablesItems = false
        model.loadRepoMeta(for: item)
        // On a picked issue, the menu acts on everything picked; checkmarks show values they all share.
        let targets = model.targets(for: item)
        let several = targets.count > 1
        if several {
            let title = NSMenuItem(title: String(localized: .selectedIssueCount(count: targets.count)), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }

        for entry in propertyItems(targets: targets) { menu.addItem(entry) }
        let relations = relationItems(targets: targets)
        if !relations.isEmpty {
            menu.addItem(.separator())
            for entry in relations { menu.addItem(entry) }
        }

        menu.addItem(.separator())
        if several {
            if targets.contains(where: { $0.url != nil }) {
                let copy = ClosureMenuItem(String(localized: .copyLinks)) { [model] in model.copyLinks(targets) }
                copy.image = MenuIcons.symbol("link")
                menu.addItem(copy)
            }
            let clear = ClosureMenuItem(String(localized: .clearSelection)) { [model] in model.clearSelection() }
            clear.image = MenuIcons.symbol("xmark.circle")
            menu.addItem(clear)
            Self.showImages(in: menu)
            return menu
        }
        let open = ClosureMenuItem(String(localized: .openIssue)) { [model, item] in model.open(item) }
        open.image = MenuIcons.symbol("arrow.up.left.and.arrow.down.right")
        menu.addItem(open)
        let peek = ClosureMenuItem(String(localized: .peek)) { [model, item] in
            model.hoveredItemId = item.id
            if model.peekItemId != nil { model.followPeek(to: item.id) } else { model.togglePeek() }
        }
        peek.image = MenuIcons.symbol("eye")
        hint(peek, " ")
        menu.addItem(peek)
        if model.nesting(around: item)?.hasNested(item.id) == true {
            let folded = model.isFolded(item)
            let fold = ClosureMenuItem(String(localized: folded ? .unfoldSubIssuesMenuItem : .foldSubIssuesMenuItem)) { [model, item] in
                model.toggleFolded(item)
            }
            fold.image = MenuIcons.symbol(folded ? "chevron.down" : "chevron.right")
            menu.addItem(fold)
        }
        if item.url != nil {
            let copy = ClosureMenuItem(String(localized: .copyLink)) { [model, item] in model.copyLink(item) }
            copy.image = MenuIcons.symbol("link")
            menu.addItem(copy)
            if item.number != nil {
                let branch = ClosureMenuItem(String(localized: .copyBranchName)) { [model, item] in model.copyBranchName(item) }
                branch.image = MenuIcons.symbol("arrow.triangle.branch")
                branch.keyEquivalent = "."
                branch.keyEquivalentModifierMask = [.command, .shift]
                menu.addItem(branch)
            }
            let github = ClosureMenuItem(String(localized: .openOnGitHub)) { [model, item] in model.openOnGitHub(item) }
            github.image = MenuIcons.symbol("arrow.up.right.square")
            menu.addItem(github)
        }

        if item.kind == .issue || item.kind == .draft {
            menu.addItem(.separator())
            let delete = ClosureMenuItem(String(localized: item.kind == .draft ? .deleteDraft : .deleteIssue)) { [model, item] in
                model.requestDelete(item)
            }
            delete.image = MenuIcons.symbol("trash")
            delete.isEnabled = model.canDelete(item)
            if delete.isEnabled {
                delete.attributedTitle = NSAttributedString(string: delete.title, attributes: [
                    .foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0),
                ])
            }
            menu.addItem(delete)
        }
        Self.showImages(in: menu)
        return menu
    }

    /// The quick choices, the full dropdown for any other day, and removing the date.
    private func dueDateMenu(_ targets: [Item]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let today = CalendarDay.today()
        let current = Set(targets.map(\.dueDate))
        for pick in DueDateParser.quickPicks(today: today) {
            let entry = ClosureMenuItem(pick.title ?? pick.day.mediumLabel(today: today), checked: current == [pick.day.string]) { [model] in
                model.setDueDate(of: targets, to: pick.day)
            }
            entry.image = MenuIcons.symbol(pick.day == today ? "sun.max" : pick.day.days(from: today) == 1 ? "sunrise" : "calendar")
            entry.toolTip = pick.day.longLabel
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let other = ClosureMenuItem(String(localized: .chooseADate)) { [model, item] in
            model.overlay = .palette(.dueDate(itemId: item.id))
        }
        other.image = MenuIcons.symbol("calendar.badge.plus")
        hint(other, "d")
        menu.addItem(other)
        if current.contains(where: { $0 != nil }) {
            let remove = ClosureMenuItem(String(localized: .removeDueDate)) { [model] in model.setDueDate(of: targets, to: nil) }
            remove.image = MenuIcons.symbol("calendar.badge.minus")
            menu.addItem(remove)
        }
        return menu
    }

    /// Status, priority, assignee, labels and Assign to Me, as submenus: the part of the menu the Inbox shows too.
    func propertyItems(targets: [Item]) -> [NSMenuItem] {
        var entries: [NSMenuItem] = []
        // An issue on none of your boards goes onto one instead of getting a status.
        if !item.isOnBoard {
            let boards = model.boards(toAdd: item)
            if !boards.isEmpty {
                let add = NSMenu()
                for project in boards {
                    let statuses = model.statusOptions(projectId: project.id)
                    let target = boards.count == 1 ? add : NSMenu()
                    if statuses.isEmpty {
                        target.addItem(ClosureMenuItem(project.title) { [model, item] in
                            model.pick(.status, id: "\(project.id)/", for: item)
                        })
                    }
                    for (index, option) in statuses.enumerated() {
                        let entry = ClosureMenuItem(option.name) { [model, item] in
                            model.pick(.status, id: "\(project.id)/\(option.id)", for: item)
                        }
                        entry.image = MenuIcons.status(model.glyph(projectId: project.id, optionId: option.id))
                        if boards.count == 1 { number(entry, index + 1) }
                        target.addItem(entry)
                    }
                    if boards.count > 1 { add.addItem(submenu(project.title, nil, target)) }
                }
                let title = String(localized: boards.count == 1 ? .addToNamedProject(project: boards[0].title) : .addToProject)
                entries.append(submenu(title, MenuIcons.status(.noProject), add))
            }
        }

        let statuses = model.statusOptions(projectId: item.projectId)
        if !statuses.isEmpty {
            let status = NSMenu()
            for (index, option) in statuses.enumerated() {
                let checked = targets.allSatisfy { model.statusOption(of: $0)?.name == option.name }
                let entry = ClosureMenuItem(option.name, checked: checked) { [model, item] in
                    model.pick(.status, id: option.id, for: item)
                }
                entry.image = MenuIcons.status(model.glyph(projectId: item.projectId, optionId: option.id))
                number(entry, index + 1)
                status.addItem(entry)
            }
            entries.append(submenu(String(localized: .status), MenuIcons.status(model.glyph(of: item)), status, picker: .status))
        }

        let priorities = model.priorityOptions(projectId: item.projectId)
        if !priorities.isEmpty {
            let priority = NSMenu()
            let none = ClosureMenuItem(String(localized: .noPriority), checked: targets.allSatisfy { $0.priorityId == nil }) { [model, item] in
                model.pick(.priority, id: "", for: item)
            }
            none.image = MenuIcons.priority(.none)
            number(none, 0)
            priority.addItem(none)
            for (index, option) in priorities.enumerated() {
                let checked = targets.allSatisfy { model.priorityOption(of: $0)?.name == option.name }
                let entry = ClosureMenuItem(option.name, checked: checked) { [model, item] in
                    model.pick(.priority, id: option.id, for: item)
                }
                entry.image = MenuIcons.priority(option.priorityLevel)
                number(entry, index + 1)
                priority.addItem(entry)
            }
            entries.append(submenu(String(localized: .priority), MenuIcons.priority(model.priorityLevel(of: item)), priority, picker: .priority))
        }

        if item.kind != .draft {
            let people = NSMenu()
            people.autoenablesItems = false
            for person in model.people(for: item) {
                let checked = targets.allSatisfy { target in target.assignees.contains { $0.id == person.id } }
                let entry = ClosureMenuItem(person.login, checked: checked) { [model, item] in
                    model.pick(.assignees, id: person.id, for: item)
                }
                entry.image = MenuIcons.avatar(person)
                people.addItem(entry)
            }
            let icon = item.assignees.first.map(MenuIcons.avatar) ?? MenuIcons.symbol("person.crop.circle")
            entries.append(submenu(String(localized: .assignee), icon, people, picker: .assignees))

            let labels = NSMenu()
            for label in model.labels(for: item) {
                let checked = targets.allSatisfy { target in target.labels.contains { $0.name == label.name } }
                let entry = ClosureMenuItem(label.name, checked: checked) { [model, item] in
                    model.pick(.labels, id: label.id, for: item)
                }
                entry.image = MenuIcons.labelDot(label.color)
                labels.addItem(entry)
            }
            if labels.items.isEmpty {
                let empty = NSMenuItem(title: String(localized: .noLabelsInRepository), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                labels.addItem(empty)
            }
            entries.append(submenu(String(localized: .labels), MenuIcons.symbol("tag"), labels, picker: .labels))

            if let viewer = model.viewer {
                let mine = targets.allSatisfy { target in target.assignees.contains { $0.id == viewer.id } }
                let assignMe = ClosureMenuItem(String(localized: mine ? .unassignMe : .assignToMe)) { [model] in
                    model.toggleAssignMe(targets)
                }
                assignMe.image = MenuIcons.symbol(mine ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                hint(assignMe, "i")
                entries.append(assignMe)
            }
        }
        if targets.contains(where: model.canHaveDueDate) {
            entries.append(submenu(String(localized: .dueDateTitle), MenuIcons.symbol("calendar"), dueDateMenu(targets), picker: .dueDate))
        }
        if targets.contains(where: model.canHaveMilestone) {
            entries.append(submenu(String(localized: .milestone), MenuIcons.milestone(model.milestoneMark(of: item)), milestoneMenu(targets), picker: .milestone))
        }
        return entries
    }

    /// No milestone, the open ones with the one they share checked, and a new one for them.
    private func milestoneMenu(_ targets: [Item]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let titles = Set(targets.map { model.milestoneTitle(of: $0) })
        let none = ClosureMenuItem(String(localized: .noMilestone), checked: titles == [nil]) { [model] in
            model.setMilestone(of: targets, to: nil)
        }
        none.image = MenuIcons.milestone(.none)
        number(none, 0)
        menu.addItem(none)
        let today = CalendarDay.today()
        let groups = model.milestoneGroups(for: item).filter { $0.isOpen || titles.contains($0.title) }
        for (index, group) in groups.enumerated() {
            let entry = ClosureMenuItem(group.title, checked: titles == [group.title]) { [model] in
                model.setMilestone(of: targets, to: group)
            }
            entry.image = MenuIcons.milestone(model.mark(of: group, projectId: item.projectId, today: today))
            entry.toolTip = group.due.map { String(localized: .dueOn(date: $0.longLabel)) }
            number(entry, index + 1)
            menu.addItem(entry)
        }
        if item.projectId != nil {
            menu.addItem(.separator())
            let new = ClosureMenuItem(String(localized: .newMilestoneEllipsis)) { [model, item] in
                model.overlay = .milestoneEditor(projectId: item.projectId, title: nil, assigning: targets.map(\.id))
            }
            new.image = MenuIcons.symbol("plus")
            menu.addItem(new)
        }
        return menu
    }

    /// Parent, sub-issues and blockers. Each opens its picker in the command palette, where issues are found by
    /// typing.
    func relationItems(targets: [Item]) -> [NSMenuItem] {
        guard targets.allSatisfy(model.canRelate) else { return [] }
        var entries: [NSMenuItem] = []
        let hasParent = targets.contains { $0.parentId != nil }
        let parent = ClosureMenuItem(String(localized: hasParent ? .changeParentIssueMenuItem : .setParentIssueMenuItem)) { [model, item] in
            model.overlay = .palette(.parent(itemId: item.id))
        }
        parent.image = MenuIcons.symbol("arrow.turn.left.up")
        entries.append(parent)
        if hasParent {
            let number = targets.count == 1 ? item.parentNumber : nil
            let title = number.map { String(localized: .removeFromNumber(number: "#\($0)")) } ?? String(localized: .removeFromParentMenuItem)
            let remove = ClosureMenuItem(title) { [model] in
                model.setParent(of: targets, to: nil)
            }
            remove.image = MenuIcons.symbol("arrow.uturn.left")
            entries.append(remove)
        }
        if targets.count == 1 {
            let add = NSMenu()
            let new = ClosureMenuItem(String(localized: .newSubIssueMenuItem)) { [model, item] in
                model.overlay = .newIssue(statusId: nil, parentItemId: item.id)
            }
            new.image = MenuIcons.symbol("plus")
            add.addItem(new)
            let existing = ClosureMenuItem(String(localized: .addExistingIssueMenuItem)) { [model, item] in
                model.overlay = .palette(.addSubIssue(itemId: item.id))
            }
            existing.image = MenuIcons.symbol("magnifyingglass")
            add.addItem(existing)
            entries.append(submenu(String(localized: .addSubIssue), MenuIcons.subIssue, add))
        }
        if !targets.contains(where: \.isEpic) {
            let epic = ClosureMenuItem(String(localized: .addToEpicCommand)) { [model, item] in
                model.overlay = .palette(.epic(itemId: item.id))
            }
            epic.image = MenuIcons.epic
            entries.append(epic)
        }
        if targets.allSatisfy(model.canMakeEpic) {
            let isEpic = targets.allSatisfy(\.isEpic)
            let make = ClosureMenuItem(String(localized: isEpic ? .turnIntoIssueCommand : .makeEpicCommand)) { [model] in
                model.setEpic(targets, !isEpic)
            }
            make.image = MenuIcons.symbol(isEpic ? "square.stack.3d.down.right.fill" : "square.stack.3d.up")
            entries.append(make)
        }
        let mark = NSMenu()
        let blockedBy = ClosureMenuItem(String(localized: .blockedByMenuItem)) { [model, item] in
            model.overlay = .palette(.blockedBy(itemId: item.id))
        }
        blockedBy.image = MenuIcons.blocked
        mark.addItem(blockedBy)
        let blocking = ClosureMenuItem(String(localized: .blockingMenuItem)) { [model, item] in
            model.overlay = .palette(.blocking(itemId: item.id))
        }
        blocking.image = MenuIcons.blocking
        mark.addItem(blocking)
        entries.append(submenu(String(localized: .markAsMenu), MenuIcons.blocked, mark))
        return entries
    }

    /// macOS 27 hides menu item images unless asked; these icons carry meaning, so they stay visible.
    static func showImages(in menu: NSMenu) {
        for entry in menu.items {
            if entry.image != nil { entry.preferredImageVisibility = .visible }
            if let submenu = entry.submenu { showImages(in: submenu) }
        }
    }

    /// A submenu; one for a property of the issue names its picker, which the glass menu opens in its place.
    private func submenu(_ title: String, _ image: NSImage?, _ menu: NSMenu, picker: PickerKind? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.image = image
        entry.submenu = menu
        if let picker { entry.representedObject = PickerMenuTarget(kind: picker, itemId: item.id) }
        return entry
    }

    /// Shows the number that picks this entry in the dropdowns; typing it while the submenu is open picks it too.
    private func number(_ entry: NSMenuItem, _ value: Int) {
        guard value <= 9 else { return }
        hint(entry, String(value))
    }

    private func hint(_ entry: NSMenuItem, _ key: String) {
        entry.keyEquivalent = key
        entry.keyEquivalentModifierMask = []
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Not used") }

    @objc private func run() {
        handler()
    }
}
#endif
