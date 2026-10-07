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
    /// Picked for a change to several issues at once, and whether anything is picked, which shows every
    /// row's checkbox.
    var selected = false
    var selecting = false
}

struct IssueSectionModel: Equatable {
    var id: String
    var collapsed = false
    var title: String
    var glyph: StatusGlyph
    var optionId: String?
    var canAdd: Bool
    var count: Int
    var rows: [IssueRowModel]
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
        // Issues and section headers can be dragged to a new place; rows open a gap where it would land.
        table.registerForDraggedTypes([Coordinator.itemType, Coordinator.sectionType])
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

            var id: String {
                switch self {
                case .header(let section): "section:\(section.id)"
                case .row(let row): row.item.id
                }
            }
        }

        let model: AppModel
        weak var table: HoverTableView?
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
        /// The issue being dragged, whose row stays behind faded until it lands.
        private var draggedId: String?

        init(model: AppModel) {
            self.model = model
        }

        func apply(sections: [IssueSectionModel], focusedId: String?, focusScrollToken: Int, avatarVersion: Int) {
            guard let table else { return }
            var next: [Entry] = []
            for section in sections {
                // Headers compare by what they show, not by their rows.
                var header = section
                header.rows = []
                next.append(.header(header))
                next += section.rows.map(Entry.row)
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
                cell?.alphaValue = row.item.id == draggedId ? 0.35 : 1
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
            }
            return item
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            guard let row = rowIndexes.first, let item = item(at: row) else { return }
            // The issue lifts off as a card, and its row stays behind faded until it lands.
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell,
               let image = cell.dragImage() {
                let frame = tableView.rect(ofRow: row)
                session.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragged, _, _ in
                    dragged.setDraggingFrame(frame, contents: image)
                }
            }
            draggedId = item.id
            configureView(at: row, in: tableView)
        }

        func tableView(
            _ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let id = draggedId
            draggedId = nil
            refreshHighlight(for: [id])
        }

        /// Rows where a section may be dropped: in front of each header, or after the last row.
        private var sectionBoundaries: [Int] {
            entries.indices.filter { if case .header = entries[$0] { return true } else { return false } } + [entries.count]
        }

        /// Where an issue dropped above `row` lands: the section it joins, and its place among that section's
        /// other issues. Above a header is the end of the section before it.
        private func landing(above row: Int, moving id: String) -> (sectionId: String, index: Int)? {
            guard row > 0 else { return nil }
            guard let header = entries[..<min(row, entries.count)].lastIndex(where: {
                if case .header = $0 { return true } else { return false }
            }), case .header(let section) = entries[header] else { return nil }
            return (section.id, entries[(header + 1)..<row].filter { $0.id != id }.count)
        }

        /// Within its section the issue changes place; in another one it takes that status, as on the board.
        func dropItem(_ id: String, above row: Int) -> Bool {
            guard let item = model.item(id: id), let projectId = item.projectId, let landing = landing(above: row, moving: id),
                  let column = model.columns(projectId: projectId).first(where: { $0.id == landing.sectionId })
            else { return false }
            model.drop(item, in: column, at: landing.index)
            return true
        }

        func tableView(
            _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard info.draggingSource as? NSTableView === tableView else { return [] }
            if info.draggingPasteboard.string(forType: Self.itemType) != nil {
                // Anywhere below the first header; in the middle of a row means just above it.
                tableView.setDropRow(max(row, 1), dropOperation: .above)
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
                guard let cell = table.view(atColumn: 0, row: visible, makeIfNecessary: false) as? IssueRowCell else { continue }
                cell.hoveredPart = visible == row ? cell.part(at: cell.convert(point, from: table))?.kind : nil
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
            if section.canAdd {
                menu.addItem(.separator())
                let add = ClosureMenuItem(String(localized: .newIssueInGroupMenu(group: section.title))) { [model] in
                    model.overlay = .newIssue(statusId: section.optionId, parentItemId: nil)
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
        coordinator?.menu(forRow: row(at: convert(event.locationInWindow, from: nil)))
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
    private var highlighted = false
    private var number = NSAttributedString()
    private var title = NSAttributedString()
    private var date = NSAttributedString()
    private var project: NSAttributedString?
    private var subCount: NSAttributedString?
    private var dueText: NSAttributedString?
    private var dueIcon: NSImage?
    private var labels: [(text: NSAttributedString, size: NSSize, color: NSColor)] = []
    // Measured once when the row is configured; measuring text on every draw is what makes drawing slow.
    private var numberSize = NSSize.zero
    private var titleSize = NSSize.zero
    private var dateSize = NSSize.zero
    private var projectSize = NSSize.zero
    private var subCountSize = NSSize.zero
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
            let truncating = NSMutableParagraphStyle()
            truncating.lineBreakMode = .byTruncatingTail
            number = NSAttributedString(string: item.displayNumber, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(Theme.textTertiary),
            ])
            title = NSAttributedString(string: item.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(Theme.text),
                .paragraphStyle: truncating,
            ])
            date = NSAttributedString(string: relativeDate(item.updatedAt), attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor(Theme.textTertiary),
            ])
            project = row.projectTitle.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor(Theme.textTertiary),
                    .paragraphStyle: truncating,
                ])
            }
            subCount = item.subTotal > 0
                ? NSAttributedString(string: "\(item.subCompleted)/\(item.subTotal)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor(Theme.textSecondary),
                ])
                : nil
            if let due = row.due {
                let color = NSColor(due.tone.color)
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
            labels = item.labels.prefix(3).map { label in
                let text = NSAttributedString(string: label.name, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor(Theme.textSecondary),
                ])
                return (text, text.size(), NSColor(Theme.labelColor(label.color)))
            }
            numberSize = number.size()
            titleSize = title.size()
            dateSize = date.size()
            projectSize = project?.size() ?? .zero
            subCountSize = subCount?.size() ?? .zero
            dueSize = dueText?.size() ?? .zero
            setAccessibilityLabel(row.due.map {
                String(localized: .issueRowSpokenWithDue(number: item.displayNumber, title: item.title, due: $0.tooltip))
            } ?? "\(item.displayNumber) \(item.title)")
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
        cacheDisplay(in: bounds, to: content)
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

        if row.selected {
            NSColor(Theme.selectionFill).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 7, yRadius: 7).fill()
        } else if highlighted {
            NSColor(Theme.selected).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        // The checkbox sits under the section headers' fold arrow; it shows on hover and while picking.
        if row.selected || row.selecting || highlighted {
            drawCheckbox(checked: row.selected, center: NSPoint(x: IssueTable.inset + 15, y: midY))
        }
        // Each part lights up in a shape that suits it, as in Linear: a small square behind an icon, a halo
        // around avatars, and chips in their own outline.
        func iconHover(_ kind: PickerKind, _ rect: NSRect) {
            guard hoveredPart == kind else { return }
            NSColor(Theme.partHover).setFill()
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
        drawPriority(row.priority, x: x, midY: midY)
        x += 14 + 10
        number.draw(at: NSPoint(x: x, y: midY - numberSize.height / 2))
        x += 40 + 10
        if row.showsStatus {
            let rect = NSRect(x: x, y: midY - 7, width: 14, height: 14)
            parts.append((.status, rect))
            iconHover(.status, rect)
        }
        StatusPainter.draw(row.glyph, in: CGRect(x: x, y: midY - 7, width: 14, height: 14), cg: context)
        x += 14 + 10

        // Right to left: assignees, date, project, labels.
        var right = size.width - IssueTable.inset - 14
        var avatarRing = NSColor(row.selected ? Theme.selectionFill : highlighted ? Theme.selected : Theme.panel)
        if canEditFields {
            let count = CGFloat(max(min(row.item.assignees.count, 3), 1))
            let width = 18 + (count - 1) * 13
            let rect = NSRect(x: right - width, y: midY - 9, width: width, height: 18)
            parts.append((.assignees, rect))
            if hoveredPart == .assignees {
                let halo = rect.insetBy(dx: -3, dy: -3)
                avatarRing = NSColor(Theme.partHover)
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
        var labelsRect: NSRect?
        for label in labels.reversed() {
            let textSize = label.size
            let width = textSize.width + 7 + 7 + 5 + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            guard rect.minX > x + 120 else { break }
            labelsRect = labelsRect.map { $0.union(rect) } ?? rect
            drawChip(rect, hovered: canEditFields && hoveredPart == .labels)
            label.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 7, y: midY - 3.5, width: 7, height: 7)).fill()
            label.text.draw(at: NSPoint(x: rect.minX + 19, y: midY - textSize.height / 2))
            right = rect.minX - 6
        }

        if canEditFields, let labelsRect { parts.append((.labels, labelsRect)) }

        // The title takes what is left, with the sub-issue count directly after it.
        let subWidth: CGFloat? = subCount == nil ? nil : subCountSize.width + 7 + 11 + 4 + 7
        let available = max(40, right - 12 - x - (subWidth.map { $0 + 10 } ?? 0))
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
            NSColor(Theme.textSecondary).setStroke()
            glyph.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: origin.x + 6.2, y: origin.y + 5.8, width: 3.1, height: 3.1))
            dot.lineWidth = 1.2
            dot.stroke()
            subCount.draw(at: NSPoint(x: rect.minX + 7 + 11 + 4, y: midY - subCountSize.height / 2))
        }
        // Tooltips follow the parts; rebuilt only when they moved.
        if parts.map(\.rect) != self.parts.map(\.rect) || toolTipsNeedUpdate {
            toolTipsNeedUpdate = false
            removeAllToolTips()
            for part in parts { addToolTip(part.rect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            if dateRect.width > 0 { addToolTip(dateRect, owner: self, userData: nil) }
        }
        self.parts = parts
    }

    private var toolTipsNeedUpdate = true

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let row else { return "" }
        if let part = part(at: point) { return model?.tooltip(part.kind, for: row.item) ?? "" }
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
            NSColor(Theme.accentFill).setFill()
            shape.fill()
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: box.minX + 3.6, y: box.midY + 0.2))
            mark.line(to: NSPoint(x: box.minX + 6, y: box.midY + 2.6))
            mark.line(to: NSPoint(x: box.maxX - 3.4, y: box.midY - 2.6))
            mark.lineWidth = 1.7
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            NSColor.white.setStroke()
            mark.stroke()
        } else {
            shape.lineWidth = 1.2
            NSColor(Theme.textTertiary).setStroke()
            shape.stroke()
        }
    }

    private func drawChip(_ rect: NSRect, hovered: Bool) {
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        if hovered {
            NSColor(Theme.chipHover).setFill()
            outline.fill()
        }
        NSColor(hovered ? Theme.chipHoverBorder : Theme.chipBorder).setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat) {
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
            NSColor(bar.1 ? Theme.textBody : Theme.barOff).setFill()
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
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: .newIssueButtonLabel))?
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
        return IssueTable.Coordinator.sectionMenu(section, model: model)
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
        guard section != self.section else { return }
        self.section = section
        needsDisplay = true
    }

    @objc private func add() {
        model?.overlay = .newIssue(statusId: section?.optionId, parentItemId: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let section, let context = NSGraphicsContext.current?.cgContext else { return }
        // Opaque behind the band, so rows do not show around its corners while it is pinned.
        NSColor(Theme.panel).setFill()
        bounds.fill()
        let band = NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 2), xRadius: 8, yRadius: 8)
        NSColor(Theme.groupHeader).setFill()
        band.fill()
        // A trace of the status colour, as a hint of what the group is.
        NSColor(section.glyph.color).withAlphaComponent(0.07).setFill()
        band.fill()
        let midY = bounds.height / 2
        // The disclosure arrow: down while open, right while folded in.
        let arrow = NSBezierPath()
        let center = NSPoint(x: IssueTable.inset + 15, y: midY)
        if section.collapsed {
            arrow.move(to: NSPoint(x: center.x - 2, y: center.y - 3.5))
            arrow.line(to: NSPoint(x: center.x + 2.5, y: center.y))
            arrow.line(to: NSPoint(x: center.x - 2, y: center.y + 3.5))
        } else {
            arrow.move(to: NSPoint(x: center.x - 3.5, y: center.y - 2))
            arrow.line(to: NSPoint(x: center.x, y: center.y + 2.5))
            arrow.line(to: NSPoint(x: center.x + 3.5, y: center.y - 2))
        }
        arrow.close()
        NSColor(Theme.textTertiary).setFill()
        arrow.fill()
        let left = IssueTable.inset + 28
        StatusPainter.draw(section.glyph, in: CGRect(x: left, y: midY - 7, width: 14, height: 14), cg: context)
        let title = NSAttributedString(string: section.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(Theme.text),
        ])
        let titleSize = title.size()
        title.draw(at: NSPoint(x: left + 22, y: midY - titleSize.height / 2))
        let count = NSAttributedString(string: "\(section.count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(Theme.textTertiary),
        ])
        count.draw(at: NSPoint(x: left + 22 + titleSize.width + 8, y: midY - count.size().height / 2))
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
            let title = NSMenuItem(title: String(localized: .menuIssueCount(count: targets.count)), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }

        for entry in propertyItems(targets: targets) { menu.addItem(entry) }

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
                let title = String(localized: boards.count == 1 ? .addToNamedProject(project: boards[0].title) : .addToProjectMenu)
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
            entries.append(submenu(String(localized: .status), MenuIcons.status(model.glyph(of: item)), status))
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
            entries.append(submenu(String(localized: .priority), MenuIcons.priority(model.priorityLevel(of: item)), priority))
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
            entries.append(submenu(String(localized: .assignee), icon, people))

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
            entries.append(submenu(String(localized: .labels), MenuIcons.symbol("tag"), labels))

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
            entries.append(submenu(String(localized: .dueDateTitle), MenuIcons.symbol("calendar"), dueDateMenu(targets)))
        }
        return entries
    }

    /// macOS 27 hides menu item images unless asked; these icons carry meaning, so they stay visible.
    static func showImages(in menu: NSMenu) {
        for entry in menu.items {
            if entry.image != nil { entry.preferredImageVisibility = .visible }
            if let submenu = entry.submenu { showImages(in: submenu) }
        }
    }

    private func submenu(_ title: String, _ image: NSImage?, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = image
        item.submenu = menu
        return item
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
