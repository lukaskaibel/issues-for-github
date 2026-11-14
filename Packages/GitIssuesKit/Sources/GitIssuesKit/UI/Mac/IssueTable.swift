#if os(macOS)
import AppKit
import SwiftUI

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
    /// Whether issues can be dragged to a new place: in a project you can edit, not in My Issues. Anywhere an issue
    /// can be dragged onto another one to go under it.
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
        /// The issue the dragged ones would go under if dropped now, which lights up.
        private var nestTargetId: String?
        /// Whether the dragged issues can go under an issue, by its id, as worked out once per drag.
        private var nestable: [String: Bool] = [:]
        /// What the dragged row lifted off as: the card under the pointer, where it sits from the pointer, and the row's
        /// own picture with how many issues the drag carries, for the smaller card it turns into over an issue.
        private struct Lifted {
            var image: NSImage
            var offset: NSPoint
            var content: NSImage?
            var count: Int?
        }
        private var lifted: Lifted?

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
            entries = next
            IssueTable.update(table, from: oldIds, to: next.map(\.id)) { view, row in
                configure(view, with: entries[row])
            }

            if avatarVersion != self.avatarVersion {
                self.avatarVersion = avatarVersion
                for row in IssueTable.loadedRows(of: table) {
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
                scrollToFocused(attempts: 5)
            }
        }

        /// Brings the focused row into view, below the section header held at the top rather than behind it. A list
        /// just switched to from the board isn't laid out yet: scrolled then, the row went to the top edge, under that
        /// header, even when it was in view anyway. So it waits for the layout, a few turns of the run loop at most.
        private func scrollToFocused(attempts: Int) {
            guard let table, let focusedId, let row = entries.firstIndex(where: { $0.id == focusedId }) else { return }
            guard !table.visibleRect.isEmpty else {
                if attempts > 0 {
                    DispatchQueue.main.async { [weak self] in self?.scrollToFocused(attempts: attempts - 1) }
                }
                return
            }
            var rect = table.rect(ofRow: row)
            if !entries[row].isHeader {
                rect.origin.y -= Theme.rowHeight
                rect.size.height += Theme.rowHeight
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                table.scrollToVisible(rect)
            }
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
            let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? PlainRowView) ?? {
                let view = PlainRowView()
                view.identifier = identifier
                return view
            }()
            // A row scrolled into view during a drag lights up only if it is the issue the dragged ones would go under.
            view.isNestTarget = nestTargetId != nil && entries.indices.contains(row) && entries[row].id == nestTargetId
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
        /// A picked issue, which brings the other picked ones along.
        static let pickedType = NSPasteboard.PasteboardType("com.lukaskbl.GitIssues.picked")

        /// Whether a row can be lifted: a section's header always, to put the sections in an order of your own; an epic's
        /// header where its issues can move; an issue where issues can move, and anywhere one that can go under another
        /// issue, as in My Issues, which keeps its own order. The table asks before it lifts a row: once it has, the row
        /// stays hidden until a drag that starts ends, and a drag without anything to carry never does.
        func canDrag(row: Int) -> Bool {
            guard entries.indices.contains(row) else { return false }
            switch entries[row] {
            case .header: return true
            case .row(let issue): return canMoveRows || model.canNestSomewhere(issue.item)
            case .epic(let sectionId, _): return canMoveRows && section(sectionId)?.kind == .status
            }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard canDrag(row: row) else { return nil }
            let item = NSPasteboardItem()
            switch entries[row] {
            case .header(let section):
                item.setString(section.id, forType: Self.sectionType)
            case .row(let issue):
                item.setString(issue.item.id, forType: picked(from: issue.item.id) == nil ? Self.itemType : Self.pickedType)
            case .epic(let sectionId, let group):
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
            // A picked issue lifts off with the others picked: the edge of a second card under it and how many there
            // are, and their rows stay behind faded.
            let picked: PickedIssues? = if case .row(let issue) = entries[row] { self.picked(from: issue.item.id) } else { nil }
            lifted = nil
            if let (image, corner, content) = liftedImage(row, in: tableView, picked: picked) {
                let start = tableView.convert(tableView.window?.convertPoint(fromScreen: screenPoint) ?? .zero, from: nil)
                session.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragged, _, _ in
                    // From where the table lifted the row: by now the row has closed up and `rect(ofRow:)` has no
                    // height, and a frame without one throws, which ends the drag before it starts and leaves the
                    // row hidden.
                    let origin = NSPoint(x: dragged.draggingFrame.origin.x + corner.x, y: dragged.draggingFrame.origin.y + corner.y)
                    dragged.setDraggingFrame(NSRect(origin: origin, size: image.size), contents: image)
                    self.lifted = Lifted(
                        image: image, offset: NSPoint(x: origin.x - start.x, y: origin.y - start.y), content: content, count: picked?.items.count
                    )
                }
            }
            nestable = [:]
            switch entries[row] {
            case .row(let issue):
                draggedIds = picked?.moving ?? [issue.item.id]
            case .epic(let sectionId, let group):
                let members = statusColumn(sectionId)?.members(of: group) ?? []
                draggedIds = Set(members.map(\.id)).union([entries[row].id])
            case .header:
                return
            }
            for loaded in IssueTable.loadedRows(of: tableView) { configureView(at: loaded, in: tableView) }
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let ids = draggedIds
            draggedIds = []
            nestable = [:]
            lifted = nil
            showNestTarget(nil)
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

        /// The card a row lifts off as, the board's lifted card (`LiftedImage`), with where the image's top left corner
        /// is from the row's, and the row's own picture for the smaller card it turns into over an issue: for a picked
        /// issue, with the others picked with it; for an epic's header, the card its issues lift off as together.
        func liftedImage(_ row: Int, in tableView: NSTableView, picked: PickedIssues?) -> (image: NSImage, origin: NSPoint, content: NSImage?)? {
            let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
            let appearance = tableView.effectiveAppearance
            if let cell = cell as? IssueRowCell, let content = cell.liftedContent() {
                return LiftedImage.row(content, inset: IssueTable.inset, count: picked?.items.count, appearance: appearance).map { ($0.image, $0.origin, content) }
            }
            if let cell = cell as? EpicHeaderRowCell, let group = cell.shownGroup {
                return LiftedImage.group(group, rowWidth: cell.bounds.width, inset: IssueTable.inset, appearance: appearance).map { ($0.image, $0.origin, nil) }
            }
            return nil
        }

        /// The picked issues a drag that starts on issue `id` carries: all of them, when it is one of two or more.
        func picked(from id: String) -> PickedIssues? {
            guard let item = model.item(id: id) else { return nil }
            return PickedIssues(from: item, among: groups(of: item), model: model)
        }

        /// The groups a drag of an issue counts in: the columns by status a drop goes into, or in My Issues, which mixes
        /// boards, the list's own sections.
        private func groups(of item: Item) -> [Nesting] {
            model.scope == .myIssues ? model.sections.map(\.nesting) : columns(of: item).map(\.nesting)
        }

        /// The columns by status the list's sections show, which dropped issues join: in All Issues its board's, with
        /// the issues on no board; elsewhere the issue's board's, as its view shows them.
        private func columns(of item: Item) -> [BoardColumn] {
            if let scope = model.scope, case .allIssues = scope { return model.columns(for: scope) }
            guard let projectId = item.projectId else { return [] }
            return model.listColumns(projectId: projectId)
        }

        private func picked(_ info: NSDraggingInfo) -> PickedIssues? {
            info.draggingPasteboard.string(forType: Self.pickedType).flatMap(picked(from:))
        }

        /// The issue being dragged and the sub-issues hanging under it, which come along.
        private func moving(_ item: Item) -> Set<String> {
            guard let group = groups(of: item).first(where: { $0.members.contains { $0.id == item.id } }) else { return [item.id] }
            return group.descendants(of: item.id).union([item.id])
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
            if let scope = model.scope, case .allIssues = scope { return model.columns(for: scope).first { $0.id == sectionId } }
            guard let projectId = model.currentProjectId else { return nil }
            return model.listColumns(projectId: projectId).first { $0.id == sectionId }
        }

        /// The column a section of the list shows, which a dropped issue joins.
        private func column(for sectionId: String, of item: Item) -> BoardColumn? {
            columns(of: item).first { $0.id == sectionId }
        }

        /// Within its section the issue changes place; in another one it takes that status, as on the board. In a
        /// milestone's groups by epic it joins the epic it is dropped into; on the roadmap an epic goes into the
        /// milestone it is dropped into.
        func dropItem(_ id: String, above row: Int) -> Bool {
            guard let item = model.item(id: id), let landing = landing(above: row, moving: moving(item)) else { return false }
            if let section = section(landing.sectionId), section.kind != .status {
                return model.dropPlanned(item, into: section.kind, scope: model.scope)
            }
            guard let column = column(for: landing.sectionId, of: item), !column.isOnNoBoard else { return false }
            if !item.isOnBoard, let projectId = model.allIssuesProjectId {
                // In All Issues: an issue on no board goes on the board, with the status it was dropped on.
                model.addToBoard([item], in: column, projectId: projectId)
                return true
            }
            model.drop(item, in: column, at: landing.index)
            return true
        }

        /// Picked issues dropped above `row` go there together: into a section by status as on the board, into a
        /// group of another kind each one that can go there.
        func dropPicked(_ picked: PickedIssues, above row: Int) -> Bool {
            guard let first = picked.items.first, let landing = landing(above: row, moving: picked.moving) else { return false }
            if let section = section(landing.sectionId), section.kind != .status {
                return model.dropPlanned(picked.items, into: section.kind, scope: model.scope)
            }
            guard let column = column(for: landing.sectionId, of: first), !column.isOnNoBoard else { return false }
            model.drop(picked, in: column, at: landing.index)
            return true
        }

        /// Whether dropping `items` into a section by status would leave them where they are: in a view with an order of
        /// its own, issues already in the section only snap back to their place, so such a drop isn't offered.
        private func staysPut(_ items: [Item], in sectionId: String) -> Bool {
            guard let first = items.first, model.isOrdered(projectId: first.projectId),
                  let column = column(for: sectionId, of: first) else { return false }
            return items.allSatisfy { item in column.nesting.members.contains { $0.id == item.id } }
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
            // An issue on no board put on All Issues' board goes at the end of its status, where the board adds it.
            if !item.isOnBoard { return end(of: landing.sectionId) }
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
            // In the middle of an issue that can take the dragged ones as its sub-issues: they would go under it, and it
            // lights up. Near its top or bottom edge they go in front of it or after it, as anywhere else.
            if dropOperation == .on, let target = nestTarget(at: row), canNest(info, under: target) {
                if nestTargetId != entries[row].id {
                    showNestTarget(entries[row].id)
                    showLifted(nestingUnder: target, info, in: tableView)
                }
                return .move
            }
            leaveNestTarget(info)
            if info.draggingPasteboard.string(forType: Self.epicType) != nil {
                // The gap opens where the epic's issues will land, together, as a whole.
                guard let dragged = draggedGroup(info), let target = groupLanding(dragged, above: row),
                      !staysPut(dragged.members, in: target.column.id) else { return [] }
                let moving = Set(dragged.members.map(\.id))
                let slot = target.column.landing(ofGroup: dragged.group.contentId, moving: moving, at: target.index).row
                tableView.setDropRow(tableRow(slot, afterHeader: target.header, shown: target.column.nesting.rows(without: moving)), dropOperation: .above)
                return .move
            }
            if let picked = picked(info) {
                guard canMoveRows, let first = picked.items.first, let landing = landing(above: max(row, 1), moving: picked.moving),
                      let section = section(landing.sectionId) else { return [] }
                // Other groups take in at their end those of them that can go there.
                if section.kind != .status {
                    guard picked.items.contains(where: { model.canDropPlanned($0, into: section.kind) }) else { return [] }
                    tableView.setDropRow(end(of: section.id), dropOperation: .above)
                    return .move
                }
                // The gap opens where they will land, together. Nothing goes into All Issues' issues on no board.
                guard !staysPut(picked.items, in: section.id), let column = column(for: section.id, of: first), !column.isOnNoBoard
                else { return [] }
                let slot = column.landing(of: picked, at: landing.index).row
                tableView.setDropRow(tableRow(slot, afterHeader: landing.header, shown: column.nesting.rows(without: picked.moving)), dropOperation: .above)
                return .move
            }
            if let id = info.draggingPasteboard.string(forType: Self.itemType) {
                // Where the list keeps its own order, an issue only goes under another one.
                guard canMoveRows else { return [] }
                // Groups by epic or by milestone take an issue in at their end; a group of its own isn't a place.
                if let item = model.item(id: id), let landing = landing(above: max(row, 1), moving: moving(item)),
                   let section = section(landing.sectionId), section.kind != .status {
                    guard model.canDropPlanned(item, into: section.kind) else { return [] }
                    tableView.setDropRow(end(of: section.id), dropOperation: .above)
                    return .move
                }
                // Anywhere below the first header; in the middle of a row means just above it. The gap opens where
                // the issue will land, which for a sub-issue is among its parent's sub-issues.
                if let item = model.item(id: id), let landing = landing(above: max(row, 1), moving: moving(item)) {
                    if staysPut([item], in: landing.sectionId) { return [] }
                    // Nothing goes into All Issues' issues on no board, which one of them only leaves.
                    if column(for: landing.sectionId, of: item)?.isOnNoBoard == true { return [] }
                }
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
            if dropOperation == .on {
                showNestTarget(nil)
                guard let target = nestTarget(at: row), let dragged = draggedItems(info) else { return false }
                model.nest(dragged, under: target)
                return true
            }
            if let id = info.draggingPasteboard.string(forType: Self.itemType) { return dropItem(id, above: row) }
            if let payload = info.draggingPasteboard.string(forType: Self.epicType) {
                return dropGroup(payload, above: row)
            }
            if let picked = picked(info) { return dropPicked(picked, above: row) }
            guard let id = info.draggingPasteboard.string(forType: Self.sectionType) else { return false }
            var target: String?
            if entries.indices.contains(row), case .header(let section) = entries[row] { target = section.id }
            model.moveListSection(id, before: target)
            return true
        }

        // MARK: Dropping onto an issue

        /// The issues a drag carries: one, or the picked ones it brings along. Epics' and sections' headers carry none.
        private func draggedItems(_ info: NSDraggingInfo) -> [Item]? {
            if let picked = picked(info) { return picked.items }
            return info.draggingPasteboard.string(forType: Self.itemType).flatMap { model.item(id: $0) }.map { [$0] }
        }

        /// Whether the issues a drag carries can go under `target`: worked out once per issue and drag, since the table
        /// asks on every move of the pointer.
        private func canNest(_ info: NSDraggingInfo, under target: Item) -> Bool {
            if let known = nestable[target.id] { return known }
            let result = draggedItems(info).map { model.canNest($0, under: target) } ?? false
            nestable[target.id] = result
            return result
        }

        /// The issue a row stands for when issues are dropped onto it: its own, or an epic's for the header over the
        /// epic's issues.
        private func nestTarget(at row: Int) -> Item? {
            guard entries.indices.contains(row) else { return nil }
            switch entries[row] {
            case .row(let issue): return issue.item
            case .epic(_, let group): return group.epic
            case .header: return nil
            }
        }

        /// Off the issue the dragged ones would have gone under: it goes dark, and the lifted card is as it was.
        func leaveNestTarget(_ info: NSDraggingInfo?) {
            guard nestTargetId != nil else { return }
            showNestTarget(nil)
            if let info, let table { showLifted(nestingUnder: nil, info, in: table) }
        }

        /// Over an issue they would go under, the dragged issues show as a smaller card under the pointer, which says
        /// so, and leave the issue in sight: the card they lifted off as covers the row under the pointer.
        private func showLifted(nestingUnder parent: Item?, _ info: NSDraggingInfo, in tableView: NSTableView) {
            guard let lifted else { return }
            let pointer = tableView.convert(info.draggingLocation, from: nil)
            var image = lifted.image
            var origin = NSPoint(x: pointer.x + lifted.offset.x, y: pointer.y + lifted.offset.y)
            if let parent, let content = lifted.content,
               let nesting = LiftedImage.nesting(content, inset: IssueTable.inset, under: parent, count: lifted.count, appearance: tableView.effectiveAppearance) {
                image = nesting.image
                origin = NSPoint(x: pointer.x - 24 + nesting.origin.x, y: pointer.y + 20 + nesting.origin.y)
            }
            info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                item.setDraggingFrame(NSRect(origin: origin, size: image.size), contents: image)
            }
        }

        /// Lights up the row of the issue the dragged ones would go under, and only that one.
        func showNestTarget(_ id: String?) {
            guard id != nestTargetId, let table else { return }
            nestTargetId = id
            // Rows held just off screen too, which a drag scrolling the list brings into view.
            for row in IssueTable.loadedRows(of: table) where entries.indices.contains(row) {
                (table.rowView(atRow: row, makeIfNecessary: false) as? PlainRowView)?.isNestTarget = id != nil && entries[row].id == id
            }
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

        /// The rows as the table shows them, and the ones being dragged, for the debug remote's checks.
        var debugEntries: [Entry] { entries }
        var debugDraggedIds: Set<String> { draggedIds }
        #endif

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            // A click below the issues lets the picked ones go.
            guard row >= 0 else {
                model.clearSelection()
                return
            }
            if let header = sender.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueHeaderCell {
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
                    model.openFromClick(group.epic)
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
                model.releaseSelection(unlessPicked: item)
                Dropdown.show(below: part.rect, in: cell, model: model) { close in
                    ItemPicker(kind: part.kind, itemId: item.id, close: close)
                }
                return
            }
            model.openFromClick(item)
        }

        /// Highlights the part under the pointer, so it reads as clickable.
        func hoverPart(row: Int, pointInTable point: NSPoint) {
            guard let table else { return }
            // Rows made ready off screen too, or one would come back into view lit up where the pointer left it.
            for loaded in IssueTable.loadedRows(of: table) {
                // An epic's header lights up as a whole, or just its arrow.
                if let header = table.view(atColumn: 0, row: loaded, makeIfNecessary: false) as? EpicHeaderRowCell {
                    let local = header.convert(point, from: table)
                    header.hoveringFold = loaded == row && header.isOnFold(local)
                    header.highlighted = loaded == row && !header.hoveringFold && draggedIds.isEmpty
                    continue
                }
                guard let cell = table.view(atColumn: 0, row: loaded, makeIfNecessary: false) as? IssueRowCell else { continue }
                let local = cell.convert(point, from: table)
                cell.hoveredPart = loaded == row ? cell.part(at: local)?.kind : nil
                cell.hoveringFold = loaded == row && cell.isOnFold(local)
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
                return SectionMenu.menu(section, model: model)
            }
            if entries.indices.contains(row), case .epic(let sectionId, let group) = entries[row] {
                return EpicGroupMenu.menu(group, in: statusColumn(sectionId), model: model)
            }
            guard let item = item(at: row) else { return nil }
            return ItemMenuBuilder(model: model, item: item).menu()
        }
    }
}

extension IssueTable {
    /// Takes the table from one list of rows to the next, by their ids, and brings every row it holds a view for up to
    /// date: issues that come or go slide in or out, one that changes place slides there. The data source answers
    /// with the new rows already; `configure` gives a row's view what the row shows now, and leaves a view that shows
    /// it already as it is.
    @MainActor
    static func update(_ table: NSTableView, from oldIds: [String], to newIds: [String], configure: (_ view: NSView, _ row: Int) -> Void) {
        if oldIds != newIds {
            let difference = newIds.difference(from: oldIds).inferringMoves()
            if oldIds.isEmpty || difference.count > 300 {
                table.reloadData()
            } else if let move = singleMove(difference) {
                // One issue changed place, by a drag or a new status: it slides there.
                table.beginUpdates()
                table.moveRow(at: move.from, to: move.to)
                table.endUpdates()
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
            }
        }
        // Every row with a view, not only those on screen: the table makes rows ready around them ahead of a scroll,
        // and such a row would come into view as it was, until the pointer went over it.
        for row in loadedRows(of: table) where row < newIds.count {
            if let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) { configure(view, row) }
        }
    }

    /// The rows the table holds a view for: those on screen, and those it has made ready around them ahead of a scroll.
    @MainActor
    static func loadedRows(of table: NSTableView) -> [Int] {
        var rows: [Int] = []
        // Rows on their way out are counted as row -1.
        table.enumerateAvailableRowViews { _, row in
            if row >= 0 { rows.append(row) }
        }
        return rows
    }

    /// The one row that moved, when that is all that changed.
    private static func singleMove(_ difference: CollectionDifference<String>) -> (from: Int, to: Int)? {
        guard difference.count == 2,
              case .remove(let from, _, let removedTo?) = difference.removals.first,
              case .insert(let to, _, let insertedFrom?) = difference.insertions.first,
              removedTo == to, insertedFrom == from else { return nil }
        return (from, to)
    }
}

/// A group's menu, on its header in the list and on its line on a view's timeline: fold this one or all of them, put
/// the groups back in their usual order, or start an issue in it. It folds in the scope on screen.
@MainActor
enum SectionMenu {
    static func menu(_ section: IssueSectionModel, model: AppModel) -> NSMenu {
        menu(
            id: section.id, title: section.title, folded: section.collapsed, kind: section.kind,
            optionId: section.optionId, canAdd: section.canAdd, model: model
        )
    }

    static func menu(
        id: String, title: String, folded: Bool, kind: ListSection.Kind, optionId: String?, canAdd: Bool, model: AppModel
    ) -> NSMenu {
        let menu = NSMenu()
        let fold = ClosureMenuItem(String(localized: folded ? .unfoldGroup : .foldGroup)) { [model] in model.toggleSection(id) }
        fold.image = MenuIcons.symbol(folded ? "chevron.down" : "chevron.right")
        menu.addItem(fold)
        let all = ClosureMenuItem(String(localized: folded ? .unfoldAllGroups : .foldAllGroups)) { [model] in
            model.toggleAllSections(like: id)
        }
        all.image = MenuIcons.symbol(folded ? "chevron.down.2" : "chevron.right.2")
        menu.addItem(all)
        // Sections dragged into an order of your own go back to the usual one, as on iPhone and iPad.
        if !model.customListOrder().isEmpty {
            let usual = ClosureMenuItem(String(localized: .backToUsualOrder)) { [model] in
                withAnimation(Theme.spring) { model.resetListOrder(in: model.scope ?? .myIssues) }
            }
            usual.image = MenuIcons.symbol("arrow.up.arrow.down")
            menu.addItem(usual)
        }
        if canAdd {
            menu.addItem(.separator())
            let add = ClosureMenuItem(String(localized: .newIssueInGroupMenu(group: title))) { [model] in
                model.addIssue(in: kind, optionId: optionId, sectionId: id)
            }
            add.image = MenuIcons.symbol("plus")
            menu.addItem(add)
        }
        for entry in menu.items where entry.image != nil { entry.preferredImageVisibility = .visible }
        return menu
    }
}

/// A table that reports the row under the pointer and builds a context menu per row.
final class HoverTableView: NSTableView {
    weak var coordinator: IssueTable.Coordinator?
    private var tracking: NSTrackingArea?

    // The app's own key handling moves through issues; the table should not take the keyboard.
    override var acceptsFirstResponder: Bool { false }

    /// Only rows that can go somewhere lift. On macOS 27 the table hides a row it starts to drag before it asks for
    /// what the drag carries; a row with nothing to carry then stayed hidden, blank, until the list was built again.
    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        guard let coordinator, !rowIndexes.isEmpty, rowIndexes.allSatisfy(coordinator.canDrag(row:)) else { return false }
        return super.canDragRows(with: rowIndexes, at: mouseDownPoint)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        coordinator?.leaveNestTarget(sender)
    }

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
        let row = visibleRect.contains(point) ? row(at: point) : -1
        coordinator?.hover(row: row)
        // The part under the pointer too: a part lit before the scroll would go on with its row, and with whichever
        // issue later takes that row's view over, until the pointer moved.
        coordinator?.hoverPart(row: row, pointInTable: point)
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
final class EpicHeaderRowCell: PaintedCell {
    private var group: Nesting.EpicGroup?
    /// What the header shows now.
    var shownGroup: Nesting.EpicGroup? { group }
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

    override func draw(_ dirtyRect: NSRect) {
        guard let group, let context = NSGraphicsContext.current?.cgContext else { return }
        let midY = bounds.height / 2
        if highlighted {
            // As the rows under it light up.
            NSColor(Theme.selected).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        // In line with the issues' status icons: after the priority and number columns.
        var x: CGFloat = IssueTable.inset + 28 + 14 + 10 + 40 + 10
        PlanningGlyph.drawEpic(in: CGRect(x: x, y: midY - 7, width: 14, height: 14), cg: context)
        if !group.folded {
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

    /// An issue that dragged issues would go under if dropped now: tinted, with a ring over the row, as a My Issues
    /// card's page lights up for an issue dragged onto it.
    var isNestTarget = false {
        didSet {
            guard isNestTarget != oldValue else { return }
            needsDisplay = true
            ring.isHidden = !isNestTarget
            if isNestTarget { placeRing() }
        }
    }

    /// Over the row's cell, which may fill itself, so the ring always shows.
    private lazy var ring: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1.5
        view.isHidden = true
        return view
    }()

    private func placeRing() {
        ring.frame = bounds.insetBy(dx: IssueTable.inset, dy: 1)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ring.layer?.borderColor = NSColor(Theme.selectionBorder).cgColor
        }
        if subviews.last !== ring { addSubview(ring, positioned: .above, relativeTo: nil) }
    }

    override func layout() {
        super.layout()
        if isNestTarget { placeRing() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if isNestTarget { placeRing() }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isNestTarget else { return }
        NSColor(Theme.selectionFill).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawSeparator(in dirtyRect: NSRect) {}
    /// The list lights up the issue to drop onto itself; the table's own blue marks are not drawn.
    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {}
}

// MARK: - Cells

/// A row of the list that paints itself in `draw(_:)`, into a layer of its own that is painted again only when it asks.
/// When it gets wider, as the list does while the issue's inspector slides away on going back, AppKit would paint just
/// the new strip on the right and keep the old picture beside it: what sits at the right edge stayed where it was, and
/// each step of the slide left a sliver of the avatars behind, until the pointer went over the row. So a row painted at
/// another size is painted all over again.
class PaintedCell: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { needsDisplay = true }
    }
}

/// A status group's header: icon, name, count, and a button to add an issue with that status.
final class IssueHeaderCell: PaintedCell {
    private var section: IssueSectionModel?
    /// What the header shows now.
    var shownSection: IssueSectionModel? { section }
    private weak var model: AppModel?
    private let addButton = NSButton()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: .newIssueAction))?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        addButton.imagePosition = .imageOnly
        addButton.contentTintColor = NSColor(Theme.textSecondary)
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
        let menu = SectionMenu.menu(section, model: model)
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
        guard section != self.section else { return }
        self.section = section
        addButton.isHidden = !section.canAdd
        addButton.toolTip = String(localized: .newIssueInGroupTooltip(group: section.title))
        toolTip = section.style == .progress ? section.progress.map { String(localized: .milestoneProgressTooltip(done: $0.done, total: $0.total)) } : nil
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
    /// The same glyph for views that draw with Core Graphics.
    static func draw(_ glyph: StatusGlyph, in frame: CGRect, cg context: CGContext) {
        context.draw(Marks.status(glyph, in: frame), mark: NSColor(glyph.color).cgColor, onColor: NSColor(Theme.onColor).cgColor)
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
        // Ticked for the issue in the peek, as on the peek's own menu; picked again, it puts the peek away, as Space does.
        let peeking = model.peekItemId == item.id
        let peek = ClosureMenuItem(String(localized: .peek), checked: peeking) { [model, item] in
            model.hoveredItemId = item.id
            if model.peekItemId != nil, !peeking { model.followPeek(to: item.id) } else { model.togglePeek() }
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
            if item.branchName != nil {
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
        // Each of the board's iteration fields, named as the board names it ("Iteration", "Sprint").
        for field in model.iterationFields(for: item) {
            entries.append(submenu(field.name, MenuIcons.symbol("arrow.triangle.2.circlepath"), iterationMenu(field, targets), picker: .iteration(fieldId: field.id)))
        }
        return entries
    }

    /// No iteration, then the current one and those to come, with the one the issues share checked.
    private func iterationMenu(_ field: ProjectField, _ targets: [Item]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let ids = model.iterationIds(of: targets, field: field)
        let none = ClosureMenuItem(String(localized: .noIteration), checked: ids == [nil]) { [model] in
            model.setIteration(of: targets, field: field, to: nil)
        }
        none.image = MenuIcons.symbol("arrow.triangle.2.circlepath", color: Theme.textTertiary)
        let choices = model.iterationChoices(field, keeping: Set(ids.compactMap { $0 }))
        let numbered = AppModel.numbersPickMilestones(choices.map(\.title))
        if numbered { number(none, 0) }
        menu.addItem(none)
        for (index, iteration) in choices.enumerated() {
            let entry = ClosureMenuItem(model.iterationMenuTitle(iteration, field: field), checked: ids == [iteration.id]) { [model] in
                model.setIteration(of: targets, field: field, to: iteration)
            }
            entry.image = MenuIcons.symbol("arrow.triangle.2.circlepath", color: model.isRunning(iteration, field: field) ? Theme.started : Theme.textSecondary)
            entry.toolTip = model.iterationRange(iteration)
            if numbered { number(entry, index + 1) }
            menu.addItem(entry)
        }
        return menu
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
