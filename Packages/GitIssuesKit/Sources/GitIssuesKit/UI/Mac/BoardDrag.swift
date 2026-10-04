#if os(macOS)
import Observation
import SwiftUI

/// State of a card drag on the board: which card is lifted, where it would land, and the geometry
/// needed to work that out. One gesture on the whole board drives it, so the drag survives the card's
/// view moving from one column to another.
@MainActor
@Observable
final class BoardDrag {
    nonisolated static let space = "board"

    struct Active: Equatable {
        var item: Item
        var size: CGSize
        /// Pointer offset from the card's top-left corner at pick-up.
        var grab: CGSize
        /// Pointer position in board space; while settling, where the pointer would be for the card to rest in its slot.
        var location: CGPoint
        var lifted = false
        var settling = false
        var tilt: Double = 0
    }

    struct Target: Equatable {
        var columnId: String
        /// Index among the column's cards, not counting the dragged one.
        var index: Int
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
    @ObservationIgnored private var origin: Target?
    @ObservationIgnored private var ignoringGesture = false
    @ObservationIgnored private var timer: Timer?

    var isDragging: Bool { active != nil }

    /// Columns as they should be drawn right now: the lifted card's slot sits where it would land.
    func arrange(_ columns: [BoardColumn]) -> [BoardColumn] {
        guard let active, let target else { return columns }
        return columns.map { column in
            var column = column
            column.items.removeAll { $0.id == active.item.id }
            if column.id == target.columnId {
                column.items.insert(active.item, at: min(target.index, column.items.count))
            }
            return column
        }
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
            model.drop(current.item, in: column, at: target.index)
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
        guard let (id, frame) = cardFrames.first(where: { $0.value.contains(point) }),
              let column = model.columns.first(where: { column in column.items.contains { $0.id == id } }),
              let index = column.items.firstIndex(where: { $0.id == id }) else { return false }
        let item = column.items[index]
        origin = Target(columnId: column.id, index: index)
        target = origin
        active = Active(
            item: item, size: frame.size,
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
            }
        } completion: { [self] in
            // Removing the overlay and showing the real card must not animate: they are in the same place.
            var transaction = Transaction()
            transaction.disablesAnimations = true
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

        let others = column.items.filter { $0.id != current.item.id }
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

        let next = Target(columnId: column.id, index: index)
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
#endif
