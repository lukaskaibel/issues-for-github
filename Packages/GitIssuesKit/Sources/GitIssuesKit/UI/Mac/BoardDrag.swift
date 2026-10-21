#if os(macOS)
import Observation
import SwiftUI

/// State of a card drag on the board: which card is lifted, with the other picked ones when it is one of them, or
/// which epic's issues by their header, where it would land, and the geometry needed to work that out. One gesture on
/// the whole board drives it, so the drag survives the card's view moving from one column to another.
@MainActor
@Observable
final class BoardDrag {
    nonisolated static let space = "board"

    struct Active: Equatable {
        /// The card lifted, or the epic whose issues are lifted together.
        var item: Item
        /// The issues of an epic standing together in a column, lifted by their header to move them all.
        var group: GroupDrag?
        /// The picked cards, lifted together by one of them.
        var picked: PickedIssues?
        var size: CGSize
        /// Pointer offset from the card's top-left corner at pick-up.
        var grab: CGSize
        /// Pointer position in board space; while settling, where the pointer would be for the card to rest in its slot.
        var location: CGPoint
        var lifted = false
        var settling = false
        var tilt: Double = 0
    }

    struct GroupDrag: Equatable {
        var group: Nesting.EpicGroup
        var columnId: String
        /// Its issues there, folded ones included.
        var ids: Set<String>
    }

    struct Target: Equatable {
        var columnId: String
        /// Index among the column's cards, not counting the dragged one and the sub-issues it brings along.
        var index: Int
        /// How far in it hangs there: under its parent, when the parent is in that column, or its epic's header.
        var depth = 0
        /// Where it shows among the column's rows, epic headers included, not counting the dragged card.
        var row = 0
    }

    private(set) var active: Active?
    private(set) var target: Target?
    /// Advances ~60 times a second during a drag so columns can scroll when the card is held near an edge.
    private(set) var tick = 0

    @ObservationIgnored private(set) var cardFrames: [String: CGRect] = [:]
    @ObservationIgnored var columnFrames: [String: CGRect] = [:]
    /// Where the board sits in the window (top-left origin), to anchor dropdowns and menus.
    @ObservationIgnored var boardFrameInWindow: CGRect = .zero
    @ObservationIgnored let menuRegion = UUID()
    /// The board's horizontal scroll position, for deciding whether a sideways swipe scrolls or navigates.
    @ObservationIgnored var scrollX: CGFloat = 0
    @ObservationIgnored var maxScrollX: CGFloat = 0
    /// Which view last reported each card's frame, so a view going away cannot erase its successor's frame.
    @ObservationIgnored private var frameOwners: [String: UUID] = [:]

    func setCardFrame(_ frame: CGRect, for id: String, owner: UUID) {
        cardFrames[id] = frame
        frameOwners[id] = owner
    }

    func card(at point: CGPoint, in items: [Item]) -> Item? {
        items.first { cardFrames[$0.id]?.contains(point) == true }
    }

    /// The card whose fold arrow is under a point.
    func fold(at point: CGPoint, in items: [Item]) -> Item? {
        guard let item = card(at: point, in: items), let frame = cardFrames[item.id],
              let rect = CardRegionStore.shared.fold(item.id) else { return nil }
        return rect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -3, dy: -4).contains(point) ? item : nil
    }

    /// The card whose number is under a point.
    func number(at point: CGPoint, in items: [Item]) -> Item? {
        guard let item = card(at: point, in: items), let frame = cardFrames[item.id],
              let rect = CardRegionStore.shared.number(item.id) else { return nil }
        return rect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -3, dy: -4).contains(point) ? item : nil
    }

    /// The clickable part of a card under a point, with its frame in board coordinates.
    func part(at point: CGPoint, in items: [Item]) -> (item: Item, kind: PickerKind, rect: CGRect)? {
        guard let item = card(at: point, in: items), let frame = cardFrames[item.id] else { return nil }
        for part in CardRegionStore.shared.parts(item.id) {
            let rect = part.rect.offsetBy(dx: frame.minX, dy: frame.minY)
            if rect.insetBy(dx: -3, dy: -4).contains(point) { return (item, part.kind, rect) }
        }
        return nil
    }

    func removeCardFrame(for id: String, owner: UUID) {
        guard frameOwners[id] == owner else { return }
        cardFrames[id] = nil
        frameOwners[id] = nil
    }

    // MARK: Epic headers

    /// Where the header over an epic's issues is, and its fold arrow, in board coordinates.
    struct HeaderFrame {
        var columnId: String
        var epic: String
        var frame: CGRect
        var fold: CGRect = .null
    }

    @ObservationIgnored private var headerFrames: [String: HeaderFrame] = [:]
    @ObservationIgnored private var headerFolds: [String: CGRect] = [:]
    @ObservationIgnored private var headerOwners: [String: UUID] = [:]

    private static func headerKey(_ column: String, _ epic: String) -> String {
        "\(column)\u{1F}\(epic)"
    }

    func setHeaderFrame(_ frame: CGRect, column: String, epic: String, owner: UUID) {
        let key = Self.headerKey(column, epic)
        headerFrames[key] = HeaderFrame(columnId: column, epic: epic, frame: frame)
        headerOwners[key] = owner
    }

    func setHeaderFold(_ frame: CGRect, column: String, epic: String) {
        headerFolds[Self.headerKey(column, epic)] = frame
    }

    func removeHeaderFrame(column: String, epic: String, owner: UUID) {
        let key = Self.headerKey(column, epic)
        guard headerOwners[key] == owner else { return }
        headerFrames[key] = nil
        headerFolds[key] = nil
        headerOwners[key] = nil
    }

    /// The header over an epic's issues under a point, in one column or any.
    func header(at point: CGPoint, in columnId: String? = nil) -> HeaderFrame? {
        guard var found = headerFrames.values.first(where: { header in
            (columnId == nil || header.columnId == columnId) && header.frame.contains(point)
        }) else { return nil }
        found.fold = headerFolds[Self.headerKey(found.columnId, found.epic)] ?? .null
        return found
    }

    func headerFrame(column: String, epic: String) -> CGRect? {
        headerFrames[Self.headerKey(column, epic)]?.frame
    }

    /// Whether a point is on the fold arrow of a header.
    func isOnFold(_ point: CGPoint, of header: HeaderFrame) -> Bool {
        !header.fold.isNull && header.fold.insetBy(dx: -4, dy: -4).contains(point)
    }
    @ObservationIgnored private var origin: Target?
    @ObservationIgnored private var ignoringGesture = false
    @ObservationIgnored private var timer: Timer?

    var isDragging: Bool { active != nil }

    /// Columns as they should be drawn right now: the lifted card's slot sits where it would land. The sub-issues
    /// hanging under it go with it, so they leave their column while it is held, and so do the other picked cards
    /// lifted with it. Lifted by their header, an epic's issues leave too, and the column it would land in shows the
    /// slot (see `groupSlot(in:)`).
    func arrange(_ columns: [BoardColumn]) -> [BoardColumn] {
        guard let active, let target else { return columns }
        if let group = active.group {
            // Wherever they are: once dropped, they stand in the column they land in until the slot gives way.
            return columns.map { column in
                var column = column
                guard column.nesting.members.contains(where: { group.ids.contains($0.id) }) else { return column }
                column.nesting.rows = column.nesting.rows(without: group.ids)
                column.items = column.items.filter { !group.ids.contains($0.id) }
                return column
            }
        }
        return columns.map { column in
            var column = column
            if let picked = active.picked {
                if column.nesting.members.contains(where: { picked.moving.contains($0.id) }) {
                    column.nesting.rows = column.nesting.rows(without: picked.moving)
                    column.items = column.items.filter { !picked.moving.contains($0.id) }
                }
            } else if column.items.contains(where: { $0.id == active.item.id }) {
                column.nesting.rows = column.rows(without: active.item)
                column.items = column.shown(without: active.item)
            }
            if column.id == target.columnId {
                column.items.insert(active.item, at: min(target.index, column.items.count))
                column.nesting.rows.insert(.item(active.item), at: min(target.row, column.nesting.rows.count))
            }
            return column
        }
    }

    /// Where the slot for an epic's lifted issues shows among a column's rows as drawn, if it shows there.
    func groupSlot(in columnId: String) -> Int? {
        guard active?.group != nil, let target, target.columnId == columnId else { return nil }
        return target.row
    }

    // MARK: Gesture

    func changed(location: CGPoint, start: CGPoint, velocity: CGSize, model: AppModel) {
        if ignoringGesture { return }
        if active == nil {
            guard begin(at: start, model: model) else {
                ignoringGesture = true
                return
            }
        }
        guard var current = active, !current.settling else { return }
        current.location = location
        // The card leans into the direction it is moving.
        current.tilt = max(-5, min(5, velocity.width / 320))
        active = current
        retarget(model: model)
    }

    func ended(model: AppModel) {
        defer { ignoringGesture = false }
        guard let current = active, !current.settling else { return }
        if let target, target != origin, let column = model.columns.first(where: { $0.id == target.columnId }) {
            if let group = current.group {
                let members = model.columns.flatMap(\.nesting.members).filter { group.ids.contains($0.id) }
                model.drop(group.group, members: members, in: column, at: target.index)
            } else if let picked = current.picked {
                model.drop(picked, in: column, at: target.index)
            } else {
                model.drop(current.item, in: column, at: target.index)
            }
        }
        settle(model: model)
    }

    /// Escape: put the card back where it came from.
    func cancel(model: AppModel) {
        guard let current = active, !current.settling else { return }
        ignoringGesture = true
        withAnimation(Theme.spring) { target = origin }
        // The slot's frame is only known after the layout pass that moves it back.
        DispatchQueue.main.async { [self] in
            guard active?.item.id == current.item.id else { return }
            settle(model: model)
        }
    }

    private func begin(at point: CGPoint, model: AppModel) -> Bool {
        if let header = header(at: point) { return begin(header, at: point, model: model) }
        guard let (id, frame) = cardFrames.first(where: { $0.value.contains(point) }),
              let column = model.columns.first(where: { column in column.items.contains { $0.id == id } }),
              let index = column.items.firstIndex(where: { $0.id == id }) else { return false }
        let item = column.items[index]
        // A picked card brings the other picked ones along.
        let picked = PickedIssues(from: item, in: model.columns, model: model)
        if let picked {
            // Where it stands now, counted as a drop there would count it.
            let index = column.items[..<index].filter { !picked.moving.contains($0.id) }.count
            let landing = column.landing(of: picked, at: index)
            origin = Target(columnId: column.id, index: landing.slot, depth: landing.depth, row: landing.row)
        } else {
            let row = column.nesting.rows.firstIndex { $0.id == id } ?? 0
            origin = Target(columnId: column.id, index: index, depth: column.nesting.depth(of: id), row: row)
        }
        target = origin
        active = Active(
            item: item, picked: picked, size: frame.size,
            grab: CGSize(width: point.x - frame.minX, height: point.y - frame.minY),
            location: point
        )
        model.isDragging = true
        DispatchQueue.main.async { [self] in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) { active?.lifted = true }
        }
        startTimer()
        return true
    }

    /// Lifts the issues of an epic standing together in a column by their header.
    private func begin(_ header: HeaderFrame, at point: CGPoint, model: AppModel) -> Bool {
        guard let column = model.columns.first(where: { $0.id == header.columnId }),
              let group = column.nesting.groups.first(where: { $0.contentId == header.epic }),
              let row = column.nesting.rows.firstIndex(where: { $0.id == group.id }) else { return false }
        let ids = Set(column.members(of: group).map(\.id))
        // Where the group stands now, counted as a drop there would count it.
        let index = column.nesting.rows[..<row].filter { line in line.item.map { !ids.contains($0.id) } ?? false }.count
        let landing = column.landing(ofGroup: group.contentId, moving: ids, at: index)
        origin = Target(columnId: column.id, index: landing.slot, depth: landing.depth, row: landing.row)
        target = origin
        active = Active(
            item: group.epic, group: GroupDrag(group: group, columnId: column.id, ids: ids), size: header.frame.size,
            grab: CGSize(width: point.x - header.frame.minX, height: point.y - header.frame.minY),
            location: point
        )
        model.isDragging = true
        DispatchQueue.main.async { [self] in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) { active?.lifted = true }
        }
        startTimer()
        return true
    }

    private func settle(model: AppModel) {
        guard let current = active else { return }
        stopTimer()
        let slot = cardFrames[current.item.id]
        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
            active?.settling = true
            active?.lifted = false
            active?.tilt = 0
            if let slot {
                active?.location = CGPoint(x: slot.minX + current.grab.width, y: slot.minY + current.grab.height)
                // An epic's issues settle as wide as their slot, which may be one level in.
                if current.group != nil { active?.size.width = slot.width }
            }
        } completion: { [self] in
            // Removing the overlay and showing the real card must not animate: they are in the same place. An
            // epic's issues, and picked cards, unfold from their slot.
            let unfolds = current.group != nil || current.picked != nil
            var transaction = Transaction(animation: unfolds ? Theme.spring : nil)
            transaction.disablesAnimations = !unfolds
            withTransaction(transaction) {
                active = nil
                target = nil
            }
            origin = nil
            model.isDragging = false
        }
    }

    // MARK: Where would it land?

    /// Recomputes the landing spot from the card's centre. Called on pointer movement and after auto-scroll.
    func retarget(model: AppModel) {
        guard let current = active, !current.settling else { return }
        let centre = CGPoint(
            x: current.location.x - current.grab.width + current.size.width / 2,
            y: current.location.y - current.grab.height + current.size.height / 2
        )
        let candidates = model.columns.compactMap { column in columnFrames[column.id].map { (column, $0) } }
        guard let (column, _) = candidates.min(by: { distance(centre.x, to: $0.1) < distance(centre.x, to: $1.1) }) else { return }

        let moving = current.group?.ids ?? current.picked?.moving
        let others = moving.map { moving in column.items.filter { !moving.contains($0.id) } } ?? column.shown(without: current.item)
        var index = 0
        var firstVisible: Int?
        var anyAbove = false
        for (position, item) in others.enumerated() {
            guard let frame = cardFrames[item.id] else { continue }
            if firstVisible == nil { firstVisible = position }
            if frame.midY < centre.y {
                index = position + 1
                anyAbove = true
            }
        }
        if !anyAbove { index = firstVisible ?? others.count }
        // A sub-issue goes among its parent's sub-issues, any other card never between a parent and its sub-issues.
        // An epic's issues go together, among the epic's other issues where the column has some.
        let landing = if let group = current.group {
            column.landing(ofGroup: group.group.contentId, moving: group.ids, at: index)
        } else if let picked = current.picked {
            column.landing(of: picked, at: index)
        } else {
            column.landing(of: current.item, at: index, epic: model.epic(of: current.item)?.contentId)
        }

        let next = Target(columnId: column.id, index: landing.slot, depth: landing.depth, row: landing.row)
        if next != target {
            withAnimation(Theme.spring) { target = next }
        }
    }

    private func distance(_ x: CGFloat, to frame: CGRect) -> CGFloat {
        if x < frame.minX { return frame.minX - x }
        if x > frame.maxX { return x - frame.maxX }
        return 0
    }

    // MARK: Reordering columns

    /// A column being dragged by its header to a new place.
    struct ColumnDrag: Equatable {
        var id: String
        var from: Int
        var to: Int
        var translation: CGFloat
        var settling = false
    }

    private(set) var column: ColumnDrag?

    /// While a column is dragged the data stays put; the dragged column follows the pointer and the
    /// ones it passes slide over by one step.
    func columnOffset(_ index: Int, step: CGFloat) -> CGFloat {
        guard let column else { return 0 }
        if index == column.from {
            return column.settling ? CGFloat(column.to - column.from) * step : column.translation
        }
        if column.from < index, index <= column.to { return -step }
        if column.to <= index, index < column.from { return step }
        return 0
    }

    func dragColumn(_ dragged: BoardColumn, translation: CGFloat, step: CGFloat, model: AppModel) {
        let columns = model.columns
        guard dragged.option != nil, model.currentProject?.viewerCanUpdate == true, column?.settling != true,
              let index = columns.firstIndex(where: { $0.id == dragged.id }) else { return }
        // "No status" is not a real column on GitHub, so it stays first and nothing can go before it.
        let lowest = columns.first?.option == nil ? 1 : 0
        let target = min(max(index + Int((translation / step).rounded()), lowest), columns.count - 1)
        if column == nil {
            column = ColumnDrag(id: dragged.id, from: index, to: target, translation: translation)
        } else {
            column?.translation = translation
            column?.to = target
        }
    }

    func dropColumn(model: AppModel) {
        guard let current = column, !current.settling else { return }
        withAnimation(Theme.spring) {
            column?.settling = true
        } completion: { [self] in
            // Apply the new order and clear the offsets in one step, so nothing visibly jumps.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                let columns = model.columns
                if current.to != current.from, let projectId = model.currentProjectId {
                    var ids = columns.compactMap { $0.option?.id }
                    let offset = columns.first?.option == nil ? 1 : 0
                    if ids.indices.contains(current.from - offset), current.to - offset <= ids.count - 1 {
                        let moved = ids.remove(at: current.from - offset)
                        ids.insert(moved, at: current.to - offset)
                        let options = model.statusOptions(projectId: projectId)
                        model.saveColumns(projectId: projectId, ids.compactMap { id in options.first { $0.id == id }?.remote })
                    }
                }
                column = nil
            }
        }
    }

    // MARK: Auto-scroll clock

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick &+= 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Points to scroll this frame when the pointer is held `distance` inside a 56 pt edge zone.
    static func scrollSpeed(insideEdgeBy distance: CGFloat) -> CGFloat {
        let zone: CGFloat = 56
        guard distance < zone else { return 0 }
        let strength = 1 - max(0, distance) / zone
        return 2 + strength * 14
    }
}
/// Where a column's rows go, and the part of each that the board finds by its frame: a card, the slot a card would
/// land in, or an epic's header.
struct ColumnLayout: Equatable {
    struct Row: Equatable {
        enum Part: Equatable {
            /// A card, or the slot for the card being dragged, or for an epic's issues, by the item's id.
            case card(String)
            /// An epic's header, by the epic's node id.
            case header(String)
        }

        var part: Part
        var indent: CGFloat
        /// The card's or the header's own height, without what the row has under it.
        var height: CGFloat
    }

    var plan = RowPlan()
    var rows: [Row] = []
    var width: CGFloat = 0
}

/// Where a column's cards and epic headers are on the board, for the pointer, clicks and drags, worked out from
/// where the column places its rows and how far it is scrolled. As with a lazy stack, only the rows on screen are
/// told to the board: only those can be pointed at.
@MainActor
final class ColumnFrames {
    var layout = ColumnLayout()
    /// The rows' top left corner on the board, which moves as the column scrolls.
    var origin: CGPoint?
    /// The part of the board the rows show in.
    var clip: CGRect?
    private let owner = UUID()
    private var cards: Set<String> = []
    private var headers: Set<String> = []

    /// The part of the rows on screen, from their top.
    var visible: ClosedRange<CGFloat>? {
        guard let origin, let clip else { return nil }
        return (clip.minY - origin.y)...max(clip.minY - origin.y, clip.maxY - origin.y)
    }

    func update(_ drag: BoardDrag, column: String) {
        guard let origin, let visible else { return }
        var cards = Set<String>()
        var headers = Set<String>()
        for index in layout.plan.rows(in: visible) where layout.rows.indices.contains(index) {
            let row = layout.rows[index]
            let frame = CGRect(
                x: origin.x + row.indent, y: origin.y + layout.plan.tops[index],
                width: layout.width - row.indent, height: row.height
            )
            switch row.part {
            case .card(let id):
                drag.setCardFrame(frame, for: id, owner: owner)
                cards.insert(id)
            case .header(let epic):
                drag.setHeaderFrame(frame, column: column, epic: epic, owner: owner)
                drag.setHeaderFold(BoardDrag.epicFoldFrame(in: frame), column: column, epic: epic)
                headers.insert(epic)
            }
        }
        for id in self.cards where !cards.contains(id) { drag.removeCardFrame(for: id, owner: owner) }
        for epic in self.headers where !headers.contains(epic) { drag.removeHeaderFrame(column: column, epic: epic, owner: owner) }
        self.cards = cards
        self.headers = headers
    }

    /// Takes the column's cards and headers off the board, when the column goes away.
    func clear(_ drag: BoardDrag, column: String) {
        for id in cards { drag.removeCardFrame(for: id, owner: owner) }
        for epic in headers { drag.removeHeaderFrame(column: column, epic: epic, owner: owner) }
        cards = []
        headers = []
    }
}
#endif
