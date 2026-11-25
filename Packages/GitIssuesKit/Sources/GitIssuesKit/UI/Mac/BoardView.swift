#if os(macOS)
import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var scroll = ScrollPosition(edge: .leading)
    // Kept in a plain object: storing the offset in view state would redraw the board on every scroll tick.
    @State private var metrics = ScrollMetrics()
    /// This board's own right-click area. Each view's board is a new one, and the board going away takes only its own
    /// area along: one id for them all let the old board, fading out after the new one came, take the new one's.
    @State private var menuRegion = UUID()
    var body: some View {
        let drag = model.boardDrag
        GeometryReader { proxy in
            let columns = drag.arrange(model.columns)
            let width = columnWidth(available: proxy.size.width, count: columns.count)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        let lifted = drag.column?.id == column.id
                        ColumnView(
                            column: column, width: width, drag: drag,
                            onHeaderDrag: { translation in drag.dragColumn(column, translation: translation, step: width + Self.spacing, model: model) },
                            onHeaderDrop: { drag.dropColumn(model: model) }
                        )
                        .frame(width: width)
                        .background {
                            // A column lifted by its header floats over the board on a piece of it.
                            if lifted {
                                RoundedRectangle(cornerRadius: ColumnView.liftedRadius, style: .continuous)
                                    .fill(Theme.board)
                                    .shadow(color: Theme.shadow, radius: 20, y: 10)
                            }
                        }
                        .offset(x: drag.columnOffset(index, step: width + Self.spacing))
                        .zIndex(lifted ? 1 : 0)
                    }
                    .animation(Theme.spring, value: drag.column?.to)
                    if showsTrailing {
                        VStack(alignment: .leading, spacing: 14) {
                            if showsAddColumn {
                                AddColumnButton()
                            }
                            if let scope = model.scope, model.canHideColumns(in: scope) {
                                HiddenColumnsList(scope: scope)
                            }
                        }
                        .frame(width: 180, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // The columns reach the window's bottom edge, where their cards scroll out of sight.
                .frame(height: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.never)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                Self.scrollMetrics(geometry)
            } action: { _, new in
                metrics.offset = new[0]
                metrics.maxOffset = new[1]
                drag.scrollX = new[2]
                drag.maxScrollX = new[1]
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                drag.boardFrameInWindow = frame
                // Right-clicking a card opens the same AppKit menu (with icons) as the list does.
                ContextMenus.shared.register(menuRegion, frame: frame) { [model, drag] point in
                    guard model.openItem == nil, model.overlay == nil else { return nil }
                    let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                    // The header over an epic's issues has the epic's menu, and one over a parent's sub-issues the parent's.
                    if let header = drag.header(at: local), let column = model.columns.first(where: { $0.id == header.columnId }),
                       let group = column.nesting.groups.first(where: { $0.contentId == header.head }) {
                        return GroupMenu.menu(group, in: column, model: model)
                    }
                    guard let item = drag.card(at: local, in: model.columns.flatMap(\.items)) else { return nil }
                    return ItemMenuBuilder(model: model, item: item).menu()
                }
                // ⌘-dragging over cards picks them, across columns as a rectangle from where the press started.
                SweepAreas.shared.register(menuRegion, SweepAreas.Area(
                    place: .issues,
                    start: { [model, drag] point in
                        guard model.openItem == nil else { return nil }
                        let origin = drag.boardFrameInWindow.origin
                        return drag.sweepStart(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y), model: model)?.id
                    },
                    rows: { [drag] in
                        let origin = drag.boardFrameInWindow.origin
                        return drag.sweepRows.map { SweepRow(id: $0.id, frame: $0.frame.offsetBy(dx: origin.x, dy: origin.y)) }
                    },
                    autoscroll: { [drag] point in
                        let origin = drag.boardFrameInWindow.origin
                        drag.sweepAutoscroll(at: point.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) })
                    }
                ))
            }
            .onDisappear { [menuRegion] in
                ContextMenus.shared.remove(menuRegion)
                SweepAreas.shared.remove(menuRegion)
            }
            // A click on the board beside the columns' cards, on a column's header or between columns, lets the picked
            // issues go. Clicks on cards and buttons are theirs: the innermost gesture wins.
            .contentShape(Rectangle())
            .onTapGesture { model.clearSelection() }
            .coordinateSpace(.named(BoardDrag.space))
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(BoardDrag.space))
                    .onChanged { drag.changed(location: $0.location, start: $0.startLocation, velocity: $0.velocity, model: model) }
                    .onEnded { _ in drag.ended(model: model) }
            )
            .overlay(alignment: .topLeading) {
                if let active = drag.active {
                    if let group = active.group {
                        LiftedGroup(active: active, group: group.group)
                    } else {
                        // Both placed from the board's top left corner, not centred on each other.
                        ZStack(alignment: .topLeading) {
                            // The issue the lifted card would go under lights up beneath it.
                            if let nest = drag.target?.nest, !active.settling {
                                NestTargetMark(cornerRadius: nest.isHeader ? GroupHeaderLook.highlightRadius : CardView.cornerRadius)
                                    .frame(width: nest.frame.width, height: nest.frame.height)
                                    .offset(x: nest.frame.minX, y: nest.frame.minY)
                                    .transition(.opacity)
                            }
                            let nesting = model.columns.first { $0.nesting.members.contains { $0.id == active.item.id } }?.nesting
                            LiftedCard(
                                active: active, card: model.cardModel(for: active.item, in: nesting, showsMilestone: model.currentMilestoneTitle == nil),
                                avatarVersion: model.avatarVersion, nestingUnder: active.settling ? nil : drag.target?.nest?.item
                            )
                        }
                    }
                }
            }
            .onChange(of: drag.tick) {
                autoScroll(width: proxy.size.width)
            }
            .onChange(of: model.dragCancelToken) {
                drag.cancel(model: model)
            }
            .background(FocusWatcher { reveal($0, width: proxy.size.width) })
            .task(id: model.scope) { await model.preloadAvatars() }
        }
    }

    /// Between columns, which leave room beside their cards for the cards' shadows as well: 20 points from the cards
    /// of one column to the next.
    static let spacing: CGFloat = 12

    /// Keep programmatic scroll coordinates, but measure navigation from the visible board's left edge.
    static func scrollMetrics(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentOffset.x, max(0, geometry.contentSize.width - geometry.containerSize.width),
         geometry.contentOffset.x + geometry.contentInsets.leading]
    }

    /// A milestone's board shows the board's columns; they are changed on the board itself.
    private var showsAddColumn: Bool {
        model.currentProject?.viewerCanUpdate == true && model.currentMilestoneTitle == nil && model.columns.allSatisfy { $0.value == nil }
    }

    /// After the columns: Add Column, and the columns you hid.
    private var showsTrailing: Bool {
        showsAddColumn || model.scope.map { model.canHideColumns(in: $0) && !model.hiddenColumns(in: $0).isEmpty } == true
    }

    private func columnWidth(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 280 }
        let trailing: CGFloat = showsTrailing ? 192 : 0
        let fitted = (available - 32 - trailing - CGFloat(count - 1) * Self.spacing) / CGFloat(count)
        return min(max(fitted, 248), 320)
    }

    /// Scrolls the board sideways to the column of the card the keyboard moved to, when it is out of sight.
    private func reveal(_ id: String, width: CGFloat) {
        guard let column = model.columns.first(where: { $0.items.contains { $0.id == id } }),
              let frame = model.boardDrag.columnFrames[column.id] else { return }
        let margin: CGFloat = 16
        // From the board's left edge in sight, as it scrolls (see `autoScroll(width:)`).
        let current = model.boardDrag.scrollX
        var next = current
        if frame.minX < margin {
            next += frame.minX - margin
        } else if frame.maxX > width - margin {
            next += frame.maxX - width + margin
        }
        next = min(max(next, 0), metrics.maxOffset)
        guard next != current else { return }
        withAnimation(Theme.quick) { scroll.scrollTo(x: next) }
    }

    /// Scrolls the board sideways while a card is held near its left or right edge, or the pointer sweeps there.
    private func autoScroll(width: CGFloat) {
        let drag = model.boardDrag
        guard metrics.maxOffset > 0 else { return }
        let x: CGFloat
        if let active = drag.active {
            guard !active.settling else { return }
            x = active.location.x
        } else if let point = drag.sweepPoint {
            x = point.x
        } else {
            return
        }
        var delta: CGFloat = 0
        if x < 56 {
            delta = -BoardDrag.scrollSpeed(insideEdgeBy: x)
        } else if x > width - 56 {
            delta = BoardDrag.scrollSpeed(insideEdgeBy: width - x)
        }
        // In the coordinates the board scrolls to, which start at its left edge in sight: the board reaches under the
        // sidebar, and its content offset counts from there, so it is as far left as it goes at minus the sidebar's width.
        let next = min(max(drag.scrollX + delta, 0), metrics.maxOffset)
        guard next != drag.scrollX else { return }
        scroll.scrollTo(x: next)
        if drag.active != nil { drag.retarget(model: model) }
    }
}

/// Hands the issue the keyboard moved to to `reveal`, without the view it is in watching the focus: columns aren't
/// worked out again on every key.
private struct FocusWatcher: View {
    @Environment(AppModel.self) private var model
    var reveal: (String) -> Void

    var body: some View {
        Color.clear.onChange(of: model.focusScrollToken) {
            if let id = model.focusedItemId { reveal(id) }
        }
    }
}

/// A scroll view's position, readable without making the view depend on it.
final class ScrollMetrics {
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0
}

/// The card under the pointer during a drag.
private struct LiftedCard: View {
    var active: BoardDrag.Active
    var card: CardModel
    var avatarVersion: Int
    /// The issue it would go under if dropped now: it shrinks a little, lets the issue show through, and says so.
    var nestingUnder: Item?

    private var stack: Int {
        CardStackEdge.layers(max(card.item.subTotal, card.nested ?? 0, (active.picked?.items.count ?? 1) - 1))
    }

    var body: some View {
        let picked = active.picked?.items.count
        CardView(card: card, width: active.size.width, lifted: true, avatarVersion: avatarVersion)
            // It keeps the cards it stands on for its sub-issues, and a parent carries the ones hanging under it along; a
            // picked card stands on one for each of the other picked ones.
            .background(alignment: .top) { CardStackEdge(layers: stack) }
            .overlay(alignment: .topTrailing) { if let picked { PickedCount(count: picked) } }
            .opacity(nestingUnder != nil ? 0.88 : 1)
            .overlay(alignment: .bottomLeading) {
                if let nestingUnder { NestHint(parent: nestingUnder).offset(x: 10, y: 13).transition(.scale(scale: 0.8).combined(with: .opacity)) }
            }
            .scaleEffect(nestingUnder != nil ? 0.9 : 1, anchor: .center)
            .animation(Theme.quick, value: nestingUnder?.id)
            .scaleEffect(active.lifted ? 1.03 : 1)
            .rotationEffect(.degrees(active.lifted ? 1.5 + active.tilt : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active.tilt)
            .liftedShadow(active.lifted)
            .offset(x: active.location.x - active.grab.width, y: active.location.y - active.grab.height)
            .allowsHitTesting(false)
    }
}

/// Under a lifted card held over another issue: that it becomes a sub-issue of it when dropped there.
struct NestHint: View {
    var parent: Item

    var body: some View {
        Label(String(localized: .subIssueOf(number: parent.displayNumber)), systemImage: "arrow.turn.down.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(Capsule().fill(Theme.accentFill))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// How many picked cards a drag carries, on the corner of the lifted one, as the Finder counts the files it drags.
struct PickedCount: View {
    var count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Theme.accentFill))
            .offset(x: 7, y: -7)
            .accessibilityHidden(true)
    }
}

/// The issues of an epic under the pointer during a drag by their header: a card with the epic's name over the
/// edge of a second one.
private struct LiftedGroup: View {
    var active: BoardDrag.Active
    var group: Nesting.Group

    var body: some View {
        GroupCard(group: group, width: active.size.width)
            .scaleEffect(active.lifted ? 1.03 : 1)
            .rotationEffect(.degrees(active.lifted ? 1.5 + active.tilt : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active.tilt)
            .liftedShadow(active.lifted)
            .offset(x: active.location.x - active.grab.width, y: active.location.y - active.grab.height)
            .allowsHitTesting(false)
    }
}

struct ColumnView: View {
    @Environment(AppModel.self) private var model
    var column: BoardColumn
    var width: CGFloat
    var drag: BoardDrag
    var onHeaderDrag: (CGFloat) -> Void = { _ in }
    var onHeaderDrop: () -> Void = {}

    @State private var scroll = ScrollPosition(edge: .top)
    @State private var metrics = ScrollMetrics()
    /// The card or epic header under the pointer. The column itself never reads it, so moving the pointer redraws
    /// only the cards it leaves and enters.
    @State private var hover = ColumnHover()
    /// Which rows have a view as the column scrolls, and where they are on the board.
    @State private var window = RowWindow()
    @State private var frames = ColumnFrames()
    /// How tall epic headers are, which only their views know.
    @State private var measured = MeasuredHeights()

    /// The columns stand on the board's grey without lanes; the gap between them sets them apart. Their cards stay
    /// this far in from the column's edges, inside its scroll view, which would otherwise cut off their shadows.
    static let inset = CardView.shadowRoom.leading
    /// The corners of a column lifted by its header.
    static let liftedRadius: CGFloat = 18
    /// Pointing anywhere in the column shows the button for a new issue in it.
    @State private var inside = ColumnInside()

    /// A row of the column as drawn: an issue, an epic's header, or the slot where an epic's lifted issues land.
    private enum Line: Identifiable {
        case row(Nesting.Row)
        case groupSlot(BoardDrag.GroupDrag, depth: Int)

        var id: String {
            switch self {
            case .row(let row): row.id
            case .groupSlot: "epic-group-slot"
            }
        }

        /// Rows of one kind take over each other's views as the column scrolls.
        var kind: Int {
            switch self {
            case .row(.item): 0
            case .row(.group): 1
            case .groupSlot: 2
            }
        }
    }

    private var lines: [Line] {
        var lines = column.nesting.rows.map(Line.row)
        if let row = drag.groupSlot(in: column.id), let group = drag.active?.group {
            lines.insert(.groupSlot(group, depth: drag.target?.depth ?? 0), at: min(row, lines.count))
        }
        return lines
    }

    var body: some View {
        let width = width - 2 * Self.inset
        let lines = lines
        let layout = layout(of: lines, width: width)
        VStack(spacing: 6 - CardView.shadowRoom.top) {
            ColumnHeader(column: column, inside: inside)
                .padding(.horizontal, Self.inset)
                // Drag the header sideways to move the whole column.
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(BoardDrag.space))
                        .onChanged { onHeaderDrag($0.translation.width) }
                        .onEnded { _ in onHeaderDrop() }
                )

            ScrollView(.vertical) {
                PlacedRows(rows: lines, plan: layout.plan, window: window, kind: \.kind) { line in
                    row(line, width: width)
                } spoken: { line in
                    spoken(line, width: width)
                }
                .animation(Theme.spring, value: lines.map(\.id))
                // One hover and one click handler per column instead of one per card.
                .contentShape(Rectangle())
                // The part under the pointer names its value, as in Linear.
                .modifier(ColumnTooltip(column: column, hover: hover))
                .onContinuousHover(coordinateSpace: .named(BoardDrag.space)) { phase in
                    switch phase {
                    case .active(let point):
                        let item = card(at: point)
                        report(item)
                        let header = drag.header(at: point, in: column.id)
                        hover.update(ColumnHover.State(
                            card: item.map { item in
                                ColumnHover.Card(
                                    id: item.id, part: drag.part(at: point, in: [item])?.kind, onFold: drag.fold(at: point, in: [item]) != nil,
                                    onNumber: drag.number(at: point, in: [item]) != nil
                                )
                            },
                            header: header.map { header in
                                ColumnHover.Header(head: header.head, onFold: drag.isOnFold(point, of: header), onDetail: drag.isOnDetail(point, of: header))
                            }
                        ))
                    case .ended:
                        report(nil)
                        hover.update(ColumnHover.State())
                    }
                }
                .gesture(SpatialTapGesture(coordinateSpace: .named(BoardDrag.space)).onEnded { value in
                    // The release of a deep press, which has opened the peek instead of being a click.
                    if model.deepPress.openedPeek { return }
                    // A click on an epic's header opens the epic, one on a parent's folds its sub-issues away or shows
                    // them (the parent opens from its menu), and so does one on a header's arrow; over a single issue,
                    // which doesn't fold, a click opens the parent too. One on the line under a parent's name changes
                    // the parent's status.
                    if let header = drag.header(at: value.location, in: column.id),
                       let group = column.nesting.groups.first(where: { $0.contentId == header.head }) {
                        if drag.isOnDetail(value.location, of: header), let head = model.headIssue(of: group),
                           model.headStatus(of: group, projectId: model.projectId(of: group, in: column.nesting)) != nil {
                            let origin = drag.boardFrameInWindow.origin
                            model.showPicker(.status, for: head, below: header.detail.offsetBy(dx: origin.x, dy: origin.y))
                        } else if group.canFold, group.kind == .parent || drag.isOnFold(value.location, of: header) {
                            model.toggleGroup(group)
                        } else if let head = model.headIssue(of: group) {
                            model.openFromClick(head)
                        }
                        return
                    }
                    // ⌘- and Shift-clicks pick cards. Otherwise a click on a card's priority, labels, sub-issues or
                    // assignees opens that dropdown, and anywhere else on the card opens the issue.
                    if let item = card(at: value.location), model.handleSelectionClick(on: item) {
                        return
                    }
                    if let item = drag.fold(at: value.location, in: column.items) {
                        model.toggleFolded(item)
                        return
                    }
                    if let hit = drag.part(at: value.location, in: column.items) {
                        model.releaseSelection(unlessPicked: hit.item)
                        let origin = drag.boardFrameInWindow.origin
                        model.showPicker(hit.kind, for: hit.item, below: hit.rect.offsetBy(dx: origin.x, dy: origin.y))
                    } else if let item = card(at: value.location) {
                        model.openFromClick(item)
                    } else {
                        // A click beside the cards lets the picked ones go.
                        model.clearSelection()
                    }
                })
                // Where the rows are on the board, which scrolling changes: cards and headers are found from it.
                .onGeometryChange(for: CGPoint.self) { proxy in
                    proxy.frame(in: .named(BoardDrag.space)).origin
                } action: { origin in
                    frames.origin = origin
                    placeRows()
                }
                // Room for the shadows of the cards, around where the column places them.
                .padding(.horizontal, Self.inset)
                .padding(.top, CardView.shadowRoom.top)
            }
            .scrollIndicators(.never)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                [geometry.contentOffset.y, max(0, geometry.contentSize.height - geometry.containerSize.height)]
            } action: { _, new in
                metrics.offset = new[0]
                metrics.maxOffset = new[1]
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(BoardDrag.space))
            } action: { frame in
                frames.clip = frame
                placeRows()
            }
        }
        .padding(.top, 4)
        .onHover { inside.pointer = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(BoardDrag.space))
        } action: { frame in
            drag.columnFrames[column.id] = frame
        }
        .onChange(of: layout, initial: true) {
            frames.layout = layout
            placeRows()
        }
        .onDisappear {
            drag.columnFrames[column.id] = nil
            frames.clear(drag, column: column.id)
        }
        .onChange(of: drag.tick) { autoScroll() }
        .background(FocusWatcher { reveal($0, in: layout) })
    }

    /// Scrolls the column to the card the keyboard moved to, when it is out of sight.
    private func reveal(_ id: String, in layout: ColumnLayout) {
        guard let index = layout.rows.firstIndex(where: { $0.part == .card(id) }), layout.plan.tops.indices.contains(index),
              let clip = frames.clip else { return }
        let top = layout.plan.tops[index]
        let bottom = top + layout.rows[index].height
        let margin: CGFloat = 8
        if top < metrics.offset + margin {
            withAnimation(Theme.quick) { scroll.scrollTo(y: max(top - margin, 0)) }
        } else if bottom > metrics.offset + clip.height - margin {
            withAnimation(Theme.quick) { scroll.scrollTo(y: min(bottom - clip.height + margin, metrics.maxOffset)) }
        }
    }

    @ViewBuilder private func row(_ line: Line, width: CGFloat) -> some View {
        switch line {
        case .groupSlot(let group, let depth):
            GroupSlot(group: group.group, width: width, depth: depth, measured: measured)
        case .row(.group(let group)):
            GroupHeaderView(
                group: group, detail: detail(of: group), place: column.nesting.place(of: group.id), width: width, hover: hover,
                dragging: model.isDragging, measured: measured
            )
        case .row(.item(let item)):
            BoardCell(
                card: model.cardModel(for: item, in: column.nesting, showsMilestone: model.currentMilestoneTitle == nil), width: width, drag: drag,
                place: column.nesting.place(of: item.id),
                selected: model.isSelected(item.id),
                hover: hover,
                dragging: model.isDragging,
                avatarVersion: model.avatarVersion
            )
        }
    }

    /// What VoiceOver finds for a row, as big as the row and labelled as the row itself would be. Made of plain
    /// values, so that a drag moving the slot doesn't work out every row's label again.
    @ViewBuilder private func spoken(_ line: Line, width: CGFloat) -> some View {
        switch line {
        case .groupSlot:
            Color.clear.accessibilityHidden(true)
        case .row(.group(let group)):
            let detail = detail(of: group)
            let place = column.nesting.place(of: group.id)
            GroupHeaderView.Spoken(
                group: group, detail: detail, width: width,
                height: measured.height(GroupHeaderView.measure(group, detail: detail, place: place, width: width))
            )
        case .row(.item(let item)):
            BoardCell.Spoken(
                item: item, nesting: column.nesting, showsMilestone: model.currentMilestoneTitle == nil, width: width,
                at: BoardCell.Geometry(item: item, place: column.nesting.place(of: item.id), stack: column.nesting.stack(of: item), drag: drag)
            )
        }
    }

    /// Where each row goes, from heights known before any row is drawn: a card's follow from its title, and an epic's
    /// header and the slot for an epic's issues are measured once from their views and kept.
    private func layout(of lines: [Line], width: CGFloat) -> ColumnLayout {
        var heights: [CGFloat] = []
        var rows: [ColumnLayout.Row] = []
        heights.reserveCapacity(lines.count)
        rows.reserveCapacity(lines.count)
        for line in lines {
            switch line {
            case .row(.item(let item)):
                let at = BoardCell.Geometry(item: item, place: column.nesting.place(of: item.id), stack: column.nesting.stack(of: item), drag: drag)
                let height = at.cardHeight(of: item, width: width)
                heights.append(height + at.edge)
                rows.append(.init(part: .card(item.id), indent: at.indent, height: height))
            case .row(.group(let group)):
                let detail = detail(of: group)
                let place = column.nesting.place(of: group.id)
                let height = measured.height(GroupHeaderView.measure(group, detail: detail, place: place, width: width))
                heights.append(height)
                // The line under a parent's name, for the pointer and clicks, from the row's top left corner: where the
                // parent is on this board, a click there changes its status.
                let changesStatus = model.headStatus(of: group, projectId: model.projectId(of: group, in: column.nesting)) != nil
                let detailFrame = detail.flatMap { detail in
                    changesStatus
                        ? GroupHeader.detailFrame(
                            detail, in: CGRect(x: 0, y: 0, width: width, height: height), place: place,
                            iconColumn: GroupHeaderView.iconColumn, nameInset: GroupHeaderView.nameInset
                        )
                        : nil
                }
                rows.append(.init(part: .header(group.contentId, detail: detailFrame, folds: group.canFold), indent: 0, height: height))
            case .groupSlot(let group, let depth):
                let indent = CGFloat(min(depth, CardTreeLines.deepest)) * CardTreeLines.indent
                let height = measured.height(GroupSlot.measure(group.group, width: width - indent))
                heights.append(height + CardStackEdge.height(CardStackEdge.layers(group.group.count)))
                rows.append(.init(part: .card(group.group.head.id), indent: indent, height: height))
            }
        }
        return ColumnLayout(plan: RowPlan(heights: heights, gap: CardTreeLines.boardGap, bottom: 40), rows: rows, width: width)
    }

    /// The line under a parent's name in its header: its number, and its status on this board.
    private func detail(of group: Nesting.Group) -> String? {
        model.headDetail(of: group, projectId: model.projectId(of: group, in: column.nesting))
    }

    /// Tells the board where this column's cards and headers on screen are, and the window which rows to build.
    private func placeRows() {
        if let visible = frames.visible { window.scrolled(to: visible) }
        frames.update(drag, column: column.id)
    }

    private func card(at point: CGPoint) -> Item? {
        column.items.first { drag.cardFrames[$0.id]?.contains(point) == true }
    }

    /// Tells the model which card the pointer is on, as it leaves one and enters another.
    private func report(_ item: Item?) {
        let previous = hover.current.card?.id
        guard previous != item?.id else { return }
        if let previous { model.pointer(.left, previous) }
        if let item { model.pointer(.entered, item.id) }
    }

    /// Scrolls this column while a card is held near its top or bottom edge, or the pointer sweeps there.
    private func autoScroll() {
        guard metrics.maxOffset > 0, let frame = drag.columnFrames[column.id] else { return }
        let y: CGFloat
        if let active = drag.active {
            guard !active.settling, drag.target?.columnId == column.id else { return }
            y = active.location.y
        } else if let point = drag.sweepPoint, frame.minX <= point.x, point.x < frame.maxX {
            y = point.y
        } else {
            return
        }
        let top = frame.minY + 40
        var delta: CGFloat = 0
        if y < top + 56 {
            delta = -BoardDrag.scrollSpeed(insideEdgeBy: y - top)
        } else if y > frame.maxY - 56 {
            delta = BoardDrag.scrollSpeed(insideEdgeBy: frame.maxY - y)
        }
        let next = min(max(metrics.offset + delta, 0), metrics.maxOffset)
        guard next != metrics.offset else { return }
        scroll.scrollTo(y: next)
        if drag.active != nil { drag.retarget(model: model) }
    }
}

/// The column's tooltip, which names what is under the pointer. As a modifier it is worked out again as the pointer
/// moves without the column's cards being worked out again.
private struct ColumnTooltip: ViewModifier {
    @Environment(AppModel.self) private var model
    var column: BoardColumn
    var hover: ColumnHover

    func body(content: Content) -> some View {
        content.help(Text(tooltip))
    }

    private var tooltip: String {
        let pointer = hover.current
        if let header = pointer.header, let group = column.nesting.groups.first(where: { $0.contentId == header.head }) {
            if header.onDetail, let head = model.headIssue(of: group) { return model.tooltip(.status, for: head) }
            // A click anywhere on a parent's header folds its sub-issues, where there are two or more.
            if group.canFold, header.onFold || group.kind == .parent { return group.foldLabel }
            return ""
        }
        guard let card = pointer.card, let item = column.items.first(where: { $0.id == card.id }) else { return "" }
        if card.onFold {
            guard column.nesting.folded.contains(item.id) else { return String(localized: .foldSubIssuesTooltip) }
            return String(localized: .unfoldSubIssuesTooltip(count: column.nesting.nestedCounts[item.id] ?? 0))
        }
        // Cards leave out the repository; as a project can span several, the number names it.
        if card.onNumber { return item.reference ?? "" }
        guard let part = card.part else { return "" }
        return model.tooltip(part, for: item)
    }
}

/// Over issues standing together in a column, an epic's or a parent's: the header they have in every list and on every
/// board (`GroupHeader`), its name on up to three lines. A click on an epic's header opens the epic, one on a parent's
/// folds its sub-issues or shows them again, as one on the arrow does; one on the line under a parent's name changes the
/// parent's status, and dragging it moves them all. The column handles the clicks and the board the drag, from where the
/// column placed the header.
private struct GroupHeaderView: View {
    var group: Nesting.Group
    /// Under a parent's name: its number and its status.
    var detail: String?
    /// Where it hangs inside an epic's group.
    var place: Nesting.Place
    var width: CGFloat
    var hover: ColumnHover
    var dragging: Bool
    var measured: MeasuredHeights

    /// The icon stands in the gutter sub-issue cards hang in, where the line down to the group's cards runs.
    static let iconColumn = (x: CGFloat(0), width: CardTreeLines.indent)
    /// A parent's name stands where the text of the cards beside it does.
    static let nameInset = CardView.padding.width
    /// The arrow ends about where the text of the cards under it does.
    static let trailing: CGFloat = 6
    static let lineLimit = 3

    /// Where the fold arrow is in a header with this frame.
    static func foldFrame(in frame: CGRect) -> CGRect {
        GroupHeader.foldFrame(in: frame, trailing: trailing)
    }

    /// How tall a header is depends on how many lines its name takes beside the count and the arrow, and on the line
    /// under a parent's name. Until its view has been drawn, that is worked out from the name's width.
    static func measure(_ group: Nesting.Group, detail: String?, place: Nesting.Place, width: CGFloat) -> MeasuredHeights.Measure {
        let key = "header \(Int(width)) \(group.kind) \(place.depth) \(group.count) \(detail != nil) \(group.head.title)"
        return MeasuredHeights.Measure(key: key) {
            GroupHeader.height(
                of: group, detail: detail, place: place, width: width, iconColumn: iconColumn, nameInset: nameInset, trailing: trailing,
                lineLimit: lineLimit
            )
        }
    }

    var body: some View {
        let pointer = dragging ? nil : hover[header: group.contentId]
        GroupHeader(
            group: group, detail: detail, place: place, iconColumn: Self.iconColumn, nameInset: Self.nameInset, gap: CardTreeLines.boardGap,
            trailing: Self.trailing, lineLimit: Self.lineLimit, highlighted: pointer != nil, hoveringFold: pointer?.onFold ?? false,
            hoveringDetail: pointer?.onDetail ?? false
        )
        .animation(Theme.quick, value: pointer != nil)
        // Placed as a whole: without it the name and the count each take on the hover fade themselves, so they are
        // drawn again on every frame of it, each time waiting for the window server, and the pointer stutters over a
        // header.
        .geometryGroup()
        .contentShape(Rectangle())
        .reportsHeight(Self.measure(group, detail: detail, place: place, width: width).key, to: measured)
    }

    /// What VoiceOver finds in the header's place, for every header of the column, drawn or not.
    struct Spoken: View {
        @Environment(AppModel.self) private var model
        var group: Nesting.Group
        var detail: String?
        var width: CGFloat
        var height: CGFloat

        var body: some View {
            let head = model.headIssue(of: group)
            Color.clear
                .frame(width: width, height: height)
                .accessibilityElement()
                .accessibilityLabel(Text(group.spoken(detail: detail)))
                .accessibilityValue(group.canFold ? Text(group.folded ? .sectionFolded : .sectionOpen) : Text(verbatim: ""))
                .accessibilityAddTraits(.isButton)
                .modifier(GroupHeaderActions(group: group, open: head.map { head in { model.open(head) } }) { model.toggleGroup(group) })
        }
    }
}

/// What VoiceOver does with a header, as a click does: on an epic's it opens the epic and folds its issues as a named
/// action; on a parent's it folds the sub-issues and opens the parent as a named action, where the app has it. Over a
/// single issue, which doesn't fold, it opens the epic or the parent.
private struct GroupHeaderActions: ViewModifier {
    var group: Nesting.Group
    var open: (() -> Void)?
    var fold: () -> Void

    func body(content: Content) -> some View {
        if !group.canFold {
            content.accessibilityAction { open?() }
        } else if group.kind == .epic {
            content
                .accessibilityAction { open?() }
                .accessibilityAction(named: Text(group.foldAction), fold)
        } else if let open {
            content
                .accessibilityAction(.default, fold)
                .accessibilityAction(named: Text(.openParentIssueCommand), open)
        } else {
            content.accessibilityAction(.default, fold)
        }
    }
}

extension BoardDrag {
    /// Where the fold arrow is in a header with this frame.
    static func groupFoldFrame(in frame: CGRect) -> CGRect {
        GroupHeaderView.foldFrame(in: frame)
    }
}

/// Where the issues lifted by their header would land: a dashed card as big as the lifted one.
private struct GroupSlot: View {
    var group: Nesting.Group
    var width: CGFloat
    var depth: Int
    var measured: MeasuredHeights

    /// As tall as the card the lifted issues show as, which depends on how many lines the name takes.
    static func measure(_ group: Nesting.Group, width: CGFloat) -> MeasuredHeights.Measure {
        MeasuredHeights.Measure(key: "slot \(Int(width)) \(group.count) \(group.head.title)") {
            let font = NSFont.systemFont(ofSize: CardView.titleSize, weight: .medium)
            let count = MeasuredHeights.width(of: "\(group.count)", font: .monospacedDigitSystemFont(ofSize: CardView.metaSize, weight: .regular))
            let name = width - 2 * CardView.padding.width - (CardView.lineHeight - 2) - 2 * 8 - count
            let lines = MeasuredHeights.lines(of: group.head.title, font: font, width: name, limit: 3)
            return max(CardView.lineHeight, MeasuredHeights.textHeight(lines: lines, font: font)) + 2 * CardView.padding.height
        }
    }

    var body: some View {
        let indent = CGFloat(min(depth, CardTreeLines.deepest)) * CardTreeLines.indent
        GroupCard(group: group, width: width - indent)
            .hidden()
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
            .reportsHeight(Self.measure(group, width: width - indent).key, to: measured)
            .padding(.leading, indent)
            .padding(.bottom, CardStackEdge.height(CardStackEdge.layers(group.count)))
    }
}

/// One position in a column: the card, or the dashed slot while that card is being dragged. A sub-issue card
/// hangs in under its parent, with a line from the parent; a card with sub-issues that don't hang under it stands on a
/// card for each, up to three. The card paints all of that itself: a long column scrolls by showing another card in
/// a row that scrolled out, and every view in a row adds to that.
private struct BoardCell: View {
    @Environment(AppModel.self) private var model
    var card: CardModel
    var width: CGFloat
    var drag: BoardDrag
    var place: Nesting.Place
    var selected: Bool
    var hover: ColumnHover
    var dragging: Bool
    var avatarVersion: Int

    /// Where a card stands in its row, worked out without drawing it.
    struct Geometry {
        /// Whether the row is the slot of the card being dragged.
        var isSlot: Bool
        var indent: CGFloat
        /// The slot is as tall as the lifted card.
        var slotHeight: CGFloat?
        /// The cards it stands on for its sub-issues, and how far they reach under it.
        var stack: Int
        var edge: CGFloat

        @MainActor init(item: Item, place: Nesting.Place, stack: Int, drag: BoardDrag) {
            isSlot = drag.active?.item.id == item.id
            indent = CGFloat(min(isSlot ? drag.target?.depth ?? 0 : place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
            slotHeight = isSlot ? drag.active?.size.height ?? 80 : nil
            self.stack = isSlot ? 0 : stack
            edge = CardStackEdge.height(self.stack)
        }

        /// How tall the card or its slot is in a column this wide.
        func cardHeight(of item: Item, width: CGFloat) -> CGFloat {
            slotHeight ?? CardView.height(titleHeight: CardView.titleHeight(item.title, width: width - indent - 2 * CardView.padding.width))
        }
    }

    var body: some View {
        let id = card.item.id
        // Asked here rather than in the column, so the pointer or the keyboard focus moving doesn't work out the
        // whole column again, and only the cards they leave and enter are painted anew.
        let pointer = dragging ? nil : hover[card: id]
        let highlighted = !dragging && (pointer != nil || model.focusedItemId == id)
        let at = Geometry(item: card.item, place: place, stack: card.stack, drag: drag)
        CardView(
            card: card, width: width - at.indent, highlighted: highlighted, selected: selected, peeked: model.isPeeked(id),
            avatarVersion: avatarVersion, hoveredPart: pointer?.part, hoveringFold: pointer?.onFold ?? false,
            slotHeight: at.slotHeight, stack: at.stack,
            tree: !at.isSlot && place.depth > 0 ? place : nil
        )
        .equatable()
        // Held over an issue to go under it, the card won't land in its slot, which fades.
        .opacity(at.isSlot && drag.target?.nest != nil ? 0.35 : 1)
        .padding(.bottom, at.edge)
        .padding(.leading, at.indent)
    }

    /// What VoiceOver finds in the card's place, for every card of the column, drawn or not.
    struct Spoken: View {
        @Environment(AppModel.self) private var model
        var item: Item
        var nesting: Nesting
        var showsMilestone: Bool
        var width: CGFloat
        var at: Geometry

        var body: some View {
            Color.clear
                .frame(width: width - at.indent, height: at.cardHeight(of: item, width: width))
                .accessibilityElement()
                .accessibilityLabel(CardView.spokenLabel(model.cardModel(for: item, in: nesting, showsMilestone: showsMilestone)))
                .accessibilityAddTraits(.isButton)
                // The slot stands in for the card being dragged.
                .accessibilityHidden(at.isSlot)
                .padding(.bottom, at.edge)
                .padding(.leading, at.indent)
        }
    }
}

// MARK: - Column header and editing

/// Whether the pointer is anywhere in a column. Only the column's header reads it, so the pointer coming and going
/// doesn't work the column's cards out again.
@MainActor @Observable
final class ColumnInside {
    var pointer = false
}

struct ColumnHeader: View {
    @Environment(AppModel.self) private var model
    var column: BoardColumn
    var inside: ColumnInside

    @State private var hovering = false
    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ColumnIcon(column: column)
            if renaming {
                TextField(.columnNamePlaceholder, text: $name)
                    .textFieldStyle(.plain)
                    .font(.uiSemibold)
                    .focused($nameFocused)
                    .focusOnAppear()
                    .onSubmit(commitRename)
                    .onKeyPress(.escape) {
                        renaming = false
                        return .handled
                    }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(column.title).font(.uiSemibold).lineLimit(1)
                    // Double-click the name to rename the column in place.
                    .onTapGesture(count: 2) { if canEdit, column.option != nil { startRename() } }
                Text("\(column.count)").foregroundStyle(Theme.textTertiary).monospacedDigit()
                if let detail = column.detail {
                    Text(detail).font(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if canEdit && column.option != nil || model.currentView != nil || inAllIssues {
                GlassMenuButton(label: .columnOptions, size: CGSize(width: 22, height: 22)) {
                    columnMenu(includingNewIssue: false)
                }
                .opacity(hovering ? 1 : 0)
            }

            // Out of sight until the pointer is in the column: a "+" over every column is noise on a quiet board.
            if canAddIssue {
                IconButton(systemName: "plus", label: String(localized: .newIssueInColumnTooltip(column: column.title)), size: 22) {
                    newIssue()
                }
                .opacity(inside.pointer || hovering ? 1 : 0)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .frame(height: 34)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: hovering)
        .animation(Theme.quick, value: inside.pointer)
        // The same options on a right-click, as anywhere else in the app.
        .glassContextMenu { columnMenu(includingNewIssue: true) }
        .confirmationDialog(
            Text(.deleteColumnQuestion(column: column.title)),
            isPresented: $confirmDelete
        ) {
            Button(.deleteColumn, role: .destructive) { delete() }
            Button(.cancel, role: .cancel) {}
        } message: {
            let count = model.issueCount(projectId: model.currentProjectId, statusId: column.option?.id)
            Text(count == 0 ? .deleteEmptyColumnMessage : .deleteColumnMessage(count: count))
        }
    }

    /// Whether the board's statuses can be changed here: on the board, not in All Issues, which shows them as they are.
    private var canEdit: Bool { model.currentProject?.viewerCanUpdate == true }

    /// All Issues' board, whose columns are moved and hidden on this device only.
    private var inAllIssues: Bool { model.allIssuesProjectId != nil }

    /// A new issue in All Issues goes on the board, so not into the issues on none, and only where you may add one.
    private var canAddIssue: Bool {
        guard inAllIssues else { return true }
        return !column.isOnNoBoard && model.boardProject?.viewerCanUpdate == true
    }

    /// A new issue in this column: with its status or its value, and what the view's filter asks for.
    private func newIssue() {
        if let value = column.value {
            model.newIssuePreset = model.newIssuePreset(projectId: model.currentProjectId, column: value)
        } else if model.currentView != nil {
            model.newIssuePreset = model.newIssuePreset(projectId: model.currentProjectId)
        }
        // "No status" is a column too: an issue made there gets none, rather than the first status.
        model.overlay = .newIssue(statusId: column.option?.id ?? (column.id == BoardColumn.noStatusId ? column.id : nil), parentItemId: nil)
    }

    private var statuses: [FieldOption] {
        model.currentProjectId.map { model.statusOptions(projectId: $0) } ?? []
    }

    private var position: Int {
        statuses.firstIndex { $0.id == column.id } ?? 0
    }

    /// The status columns the board shows, which Move Left and Move Right step through; in All Issues every column.
    private var shownStatuses: [String] {
        inAllIssues ? model.columns.map(\.id) : model.columns.compactMap { $0.option?.id }
    }

    private func startRename() {
        name = column.title
        renaming = true
        nameFocused = true
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != column.title else { return }
        edit { $0.name = trimmed }
    }

    private func edit(_ change: (inout RemoteOption) -> Void) {
        guard let projectId = model.currentProjectId else { return }
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        change(&options[position])
        model.saveColumns(projectId: projectId, options)
    }

    private func move(_ delta: Int) {
        let shown = shownStatuses
        guard let index = shown.firstIndex(of: column.id), shown.indices.contains(index + delta) else { return }
        if let projectId = model.allIssuesProjectId {
            model.moveColumn(column.id, among: shown, to: index + delta, allIssuesOf: projectId)
        } else if let projectId = model.currentProjectId {
            model.moveColumn(column.id, among: shown, to: index + delta, projectId: projectId)
        }
    }

    private func delete() {
        guard let projectId = model.currentProjectId else { return }
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        options.remove(at: position)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }
}

extension ColumnHeader {
    /// Rename, colour, move, hide and delete the column, and a new issue in it, as a menu in glass.
    func columnMenu(includingNewIssue: Bool) -> NSMenu {
        let menu = MenuBuilder()
        let editable = canEdit && column.option != nil
        if editable, let option = column.option {
            menu.item(.renameEllipsis, "pencil") { startRename() }
            // What the status means, drawn as its circle; kept in iCloud, as GitHub has no icons.
            menu.submenu(.statusIcon, "circle.dashed") { kinds in
                for kind in AppModel.statusKindsInOrder {
                    kinds.item(
                        AppModel.statusTitle(kind),
                        image: MenuIcons.status(AppModel.kindGlyph(kind, color: option.color)),
                        checked: option.statusCategory == kind
                    ) { [model] in model.setKind(kind, of: option) }
                }
                kinds.divider()
                let note = NSMenuItem(title: String(localized: .statusIconNote), action: nil, keyEquivalent: "")
                note.isEnabled = false
                kinds.menu.addItem(note)
            }
            menu.submenu(.colour, "paintpalette") { colours in
                for color in Defaults.optionColors {
                    colours.item(
                        Defaults.colourName(color),
                        image: MenuIcons.symbol("circle.fill", color: Theme.optionColor(color) ?? Theme.textTertiary),
                        checked: column.option?.color == color
                    ) { edit { $0.color = color } }
                }
            }
            menu.divider()
        }
        // All Issues puts its columns in an order of its own, on this device; the board's are its statuses' order.
        if editable || inAllIssues {
            let shown = shownStatuses
            menu.item(.moveLeft, "arrow.left", enabled: shown.first != column.id) { move(-1) }
            menu.item(.moveRight, "arrow.right", enabled: shown.last != column.id) { move(1) }
            menu.divider()
        }
        // Hidden here only, for a view's board and All Issues'; one column always stays.
        if let scope = model.scope, model.canHideColumns(in: scope) {
            menu.item(.hideColumn, "eye.slash", enabled: model.columns.count > 1) { [model, id = column.id] in
                model.setColumn(id, hidden: true, in: scope)
            }
            menu.divider()
        }
        if editable {
            menu.item(.deleteColumnEllipsis, "trash", enabled: statuses.count > 1, destructive: true) { confirmDelete = true }
        }
        if includingNewIssue, canAddIssue {
            menu.divider()
            menu.item(String(localized: .newIssueInColumnMenuItem(column: column.title)), "plus") { newIssue() }
        }
        return menu.build()
    }

}

/// The columns you hid on the board, at its end: each with its count, shown again with a click.
private struct HiddenColumnsList: View {
    @Environment(AppModel.self) private var model
    var scope: Scope

    var body: some View {
        let hidden = model.hiddenColumns(in: scope)
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(.hiddenColumns)
                    .font(.small)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                ForEach(hidden) { column in
                    Button {
                        model.setColumn(column.id, hidden: false, in: scope)
                    } label: {
                        HStack(spacing: 8) {
                            ColumnIcon(column: column)
                            Text(column.title).lineLimit(1)
                            Text("\(column.count)").foregroundStyle(Theme.textTertiary).monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        .font(.ui)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .hoverFill()
                    }
                    .buttonStyle(PlainPressStyle())
                    .help(Text(.showColumnAgainTooltip))
                }
            }
        }
    }
}

struct AddColumnButton: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if adding {
                TextField(.columnNamePlaceholder, text: $name)
                    .textFieldStyle(.plain)
                    .font(.uiSemibold)
                    .focused($focused)
                    .focusOnAppear()
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.control))
                    .onSubmit(commit)
                    .onKeyPress(.escape) {
                        adding = false
                        return .handled
                    }
                    .onChange(of: focused) { _, isFocused in
                        // Clicking elsewhere keeps what was typed, as renaming a column does; Escape lets it go.
                        if !isFocused { commit() }
                    }
            } else {
                Button {
                    name = ""
                    adding = true
                    focused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        Text(.addColumn)
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .hoverFill()
                }
                .buttonStyle(PlainPressStyle())
            }
        }
        .frame(height: 32)
    }

    private func commit() {
        guard adding else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        adding = false
        guard !trimmed.isEmpty, let projectId = model.currentProjectId else { return }
        let options = model.statusOptions(projectId: projectId).map(\.remote) + [RemoteOption(id: nil, name: trimmed, color: "GRAY")]
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }
}

#endif
