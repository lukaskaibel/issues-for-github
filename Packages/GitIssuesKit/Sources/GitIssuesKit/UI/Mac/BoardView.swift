#if os(macOS)
import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var scroll = ScrollPosition(edge: .leading)
    // Kept in a plain object: storing the offset in view state would redraw the board on every scroll tick.
    @State private var metrics = ScrollMetrics()
    var body: some View {
        let drag = model.boardDrag
        GeometryReader { proxy in
            let columns = drag.arrange(model.columns)
            let width = columnWidth(available: proxy.size.width, count: columns.count)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        let lifted = drag.column?.id == column.id
                        ColumnView(
                            column: column, width: width, drag: drag,
                            onHeaderDrag: { translation in drag.dragColumn(column, translation: translation, step: width + 12, model: model) },
                            onHeaderDrop: { drag.dropColumn(model: model) }
                        )
                        .frame(width: width)
                        .background {
                            if lifted {
                                RoundedRectangle(cornerRadius: ColumnView.laneRadius, style: .continuous)
                                    .fill(Theme.lane)
                                    .shadow(color: Theme.shadow, radius: 20, y: 10)
                            }
                        }
                        .offset(x: drag.columnOffset(index, step: width + 12))
                        .zIndex(lifted ? 1 : 0)
                    }
                    .animation(Theme.spring, value: drag.column?.to)
                    if showsTrailing {
                        VStack(alignment: .leading, spacing: 14) {
                            if showsAddColumn {
                                AddColumnButton()
                            }
                            if let projectId = model.currentProjectId, model.currentView != nil {
                                HiddenColumnsList(projectId: projectId)
                            }
                        }
                        .frame(width: 180, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(height: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.never)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                [geometry.contentOffset.x, max(0, geometry.contentSize.width - geometry.containerSize.width)]
            } action: { _, new in
                metrics.offset = new[0]
                metrics.maxOffset = new[1]
                drag.scrollX = new[0]
                drag.maxScrollX = new[1]
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                drag.boardFrameInWindow = frame
                // Right-clicking a card opens the same AppKit menu (with icons) as the list does.
                ContextMenus.shared.register(drag.menuRegion, frame: frame) { [model, drag] point in
                    guard model.openItem == nil, model.overlay == nil else { return nil }
                    let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                    // The header over an epic's issues has the epic's menu.
                    if let header = drag.header(at: local), let column = model.columns.first(where: { $0.id == header.columnId }),
                       let group = column.nesting.groups.first(where: { $0.contentId == header.epic }) {
                        return EpicGroupMenu.menu(group, in: column, model: model)
                    }
                    guard let item = drag.card(at: local, in: model.columns.flatMap(\.items)) else { return nil }
                    return ItemMenuBuilder(model: model, item: item).menu()
                }
            }
            .onDisappear { ContextMenus.shared.remove(drag.menuRegion) }
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
                        let nesting = model.columns.first { $0.nesting.members.contains { $0.id == active.item.id } }?.nesting
                        LiftedCard(active: active, card: model.cardModel(for: active.item, in: nesting, showsMilestone: model.currentMilestoneTitle == nil), avatarVersion: model.avatarVersion)
                    }
                }
            }
            .onChange(of: drag.tick) {
                autoScroll(width: proxy.size.width)
            }
            .onChange(of: model.dragCancelToken) {
                drag.cancel(model: model)
            }
            .task(id: model.scope) { await model.preloadAvatars() }
        }
    }

    /// A milestone's board shows the board's columns; they are changed on the board itself.
    private var showsAddColumn: Bool {
        model.currentProject?.viewerCanUpdate == true && model.currentMilestoneTitle == nil && model.columns.allSatisfy { $0.value == nil }
    }

    /// After the columns: Add Column, and the columns you hid.
    private var showsTrailing: Bool {
        showsAddColumn || model.currentView != nil && model.currentProjectId.map { !model.hiddenColumns(projectId: $0).isEmpty } == true
    }

    private func columnWidth(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 280 }
        let trailing: CGFloat = showsTrailing ? 192 : 0
        let fitted = (available - 32 - trailing - CGFloat(count - 1) * 12) / CGFloat(count)
        return min(max(fitted, 248), 320)
    }

    /// Scrolls the board sideways while a card is held near its left or right edge.
    private func autoScroll(width: CGFloat) {
        let drag = model.boardDrag
        guard let active = drag.active, !active.settling, metrics.maxOffset > 0 else { return }
        let x = active.location.x
        var delta: CGFloat = 0
        if x < 56 {
            delta = -BoardDrag.scrollSpeed(insideEdgeBy: x)
        } else if x > width - 56 {
            delta = BoardDrag.scrollSpeed(insideEdgeBy: width - x)
        }
        let next = min(max(metrics.offset + delta, 0), metrics.maxOffset)
        guard next != metrics.offset else { return }
        scroll.scrollTo(x: next)
        drag.retarget(model: model)
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

    var body: some View {
        CardView(card: card, width: active.size.width, lifted: true, avatarVersion: avatarVersion)
            // A parent carries the sub-issues hanging under it along.
            .background(alignment: .top) { if card.nested != nil { CardStackEdge() } }
            .scaleEffect(active.lifted ? 1.03 : 1)
            .rotationEffect(.degrees(active.lifted ? 1.5 + active.tilt : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active.tilt)
            .shadow(color: active.lifted ? Theme.shadow : .clear, radius: active.lifted ? 22 : 0, y: active.lifted ? 16 : 0)
            .offset(x: active.location.x - active.grab.width, y: active.location.y - active.grab.height)
            .allowsHitTesting(false)
    }
}

/// The issues of an epic under the pointer during a drag by their header: a card with the epic's name over the
/// edge of a second one.
private struct LiftedGroup: View {
    var active: BoardDrag.Active
    var group: Nesting.EpicGroup

    var body: some View {
        EpicGroupCard(group: group, width: active.size.width)
            .scaleEffect(active.lifted ? 1.03 : 1)
            .rotationEffect(.degrees(active.lifted ? 1.5 + active.tilt : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active.tilt)
            .shadow(color: active.lifted ? Theme.shadow : .clear, radius: active.lifted ? 22 : 0, y: active.lifted ? 16 : 0)
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

    /// Each column stands in a soft lane, as Reminders sets its columns apart, with the cards inset in it.
    static let laneRadius: CGFloat = 18
    static let laneInset: CGFloat = 8

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
            case .row(.epic): 1
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
        let width = width - 2 * Self.laneInset
        let lines = lines
        let layout = layout(of: lines, width: width)
        VStack(spacing: 6) {
            ColumnHeader(column: column)
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
                            header: header.map { ColumnHover.Header(epic: $0.epic, onFold: drag.isOnFold(point, of: $0)) }
                        ))
                    case .ended:
                        report(nil)
                        hover.update(ColumnHover.State())
                    }
                }
                .gesture(SpatialTapGesture(coordinateSpace: .named(BoardDrag.space)).onEnded { value in
                    // A click on an epic's header opens the epic, one on its arrow folds its issues away or shows them.
                    if let header = drag.header(at: value.location, in: column.id),
                       let group = column.nesting.groups.first(where: { $0.contentId == header.epic }) {
                        if drag.isOnFold(value.location, of: header) { model.toggleEpicGroup(group) } else { model.open(group.epic) }
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
                        let origin = drag.boardFrameInWindow.origin
                        model.showPicker(hit.kind, for: hit.item, below: hit.rect.offsetBy(dx: origin.x, dy: origin.y))
                    } else if let item = card(at: value.location) {
                        model.open(item)
                    }
                })
                // Where the rows are on the board, which scrolling changes: cards and headers are found from it.
                .onGeometryChange(for: CGPoint.self) { proxy in
                    proxy.frame(in: .named(BoardDrag.space)).origin
                } action: { origin in
                    frames.origin = origin
                    placeRows()
                }
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
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.laneRadius - Self.laneInset, bottomTrailingRadius: Self.laneRadius - Self.laneInset, style: .continuous))
        }
        .padding(.horizontal, Self.laneInset)
        .padding(.top, 4)
        .padding(.bottom, Self.laneInset)
        .background(RoundedRectangle(cornerRadius: Self.laneRadius, style: .continuous).fill(Theme.lane))
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
    }

    @ViewBuilder private func row(_ line: Line, width: CGFloat) -> some View {
        switch line {
        case .groupSlot(let group, let depth):
            EpicGroupSlot(group: group.group, width: width, depth: depth, measured: measured)
        case .row(.epic(let group)):
            EpicGroupHeader(group: group, width: width, hover: hover, dragging: model.isDragging, measured: measured)
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
        case .row(.epic(let group)):
            EpicGroupHeader.Spoken(group: group, width: width, height: measured.height(EpicGroupHeader.measure(group, width: width)))
        case .row(.item(let item)):
            BoardCell.Spoken(
                item: item, nesting: column.nesting, showsMilestone: model.currentMilestoneTitle == nil, width: width,
                at: BoardCell.Geometry(item: item, place: column.nesting.place(of: item.id), folded: column.nesting.folded.contains(item.id), drag: drag)
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
                let at = BoardCell.Geometry(item: item, place: column.nesting.place(of: item.id), folded: column.nesting.folded.contains(item.id), drag: drag)
                let height = at.cardHeight(of: item, width: width)
                heights.append(height + at.edge)
                rows.append(.init(part: .card(item.id), indent: at.indent, height: height))
            case .row(.epic(let group)):
                let height = measured.height(EpicGroupHeader.measure(group, width: width))
                heights.append(height)
                rows.append(.init(part: .header(group.contentId), indent: 0, height: height))
            case .groupSlot(let group, let depth):
                let indent = CGFloat(min(depth, CardTreeLines.deepest)) * CardTreeLines.indent
                let height = measured.height(EpicGroupSlot.measure(group.group, width: width - indent))
                heights.append(height + CardStackEdge.height)
                rows.append(.init(part: .card(group.group.epic.id), indent: indent, height: height))
            }
        }
        return ColumnLayout(plan: RowPlan(heights: heights, gap: CardTreeLines.boardGap, bottom: 40), rows: rows, width: width)
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

    /// Scrolls this column while a card is held near its top or bottom edge.
    private func autoScroll() {
        guard let active = drag.active, !active.settling, drag.target?.columnId == column.id,
              metrics.maxOffset > 0, let frame = drag.columnFrames[column.id] else { return }
        let top = frame.minY + 40
        let y = active.location.y
        var delta: CGFloat = 0
        if y < top + 56 {
            delta = -BoardDrag.scrollSpeed(insideEdgeBy: y - top)
        } else if y > frame.maxY - 56 {
            delta = BoardDrag.scrollSpeed(insideEdgeBy: frame.maxY - y)
        }
        let next = min(max(metrics.offset + delta, 0), metrics.maxOffset)
        guard next != metrics.offset else { return }
        scroll.scrollTo(y: next)
        drag.retarget(model: model)
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
        if let header = pointer.header, header.onFold, let group = column.nesting.groups.first(where: { $0.contentId == header.epic }) {
            return String(localized: group.folded ? .unfoldEpicGroupTooltip(count: group.count) : .foldEpicGroupTooltip)
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

/// Over the issues of an epic standing together in a column: the epic's icon where the line down to them starts,
/// its name on up to three lines, how many of its issues are there, and the arrow that folds them away. A click
/// opens the epic, one on the arrow folds its issues or shows them again, and dragging it moves them all. The
/// column handles the clicks and the board the drag, from where the column placed the header.
private struct EpicGroupHeader: View {
    var group: Nesting.EpicGroup
    var width: CGFloat
    var hover: ColumnHover
    var dragging: Bool
    var measured: MeasuredHeights

    /// The height of a line of its name, which the icon, the count and the arrow line up with.
    private static let line: CGFloat = 16
    private static let padding: CGFloat = 4
    private static let spacing: CGFloat = 6
    private static let arrow: CGFloat = 20

    /// Where the fold arrow is in a header with this frame: at its trailing edge, centred on the first line.
    static func foldFrame(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.maxX - padding - arrow, y: frame.minY + padding + (line - arrow) / 2,
            width: arrow, height: arrow
        )
    }

    /// How tall a header is depends on how many lines its name takes beside the count and the arrow. Until its view
    /// has been drawn, that is worked out from the name's width.
    static func measure(_ group: Nesting.EpicGroup, width: CGFloat) -> MeasuredHeights.Measure {
        MeasuredHeights.Measure(key: "header \(Int(width)) \(group.count) \(group.epic.title)") {
            let count = MeasuredHeights.width(of: "\(group.count)", font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
            let name = width - (CardTreeLines.indent + spacing) - padding - 3 * spacing - 4 - arrow - count
            let lines = MeasuredHeights.lines(of: group.epic.title, font: .systemFont(ofSize: 12, weight: .medium), width: name, limit: 3)
            return max(line, MeasuredHeights.textHeight(lines: lines, font: .systemFont(ofSize: 12, weight: .medium))) + 2 * padding
        }
    }

    var body: some View {
        let pointer = dragging ? nil : hover[header: group.contentId]
        let hovered = pointer != nil
        let hoveringFold = pointer?.onFold ?? false
        HStack(alignment: .top, spacing: Self.spacing) {
            Text(group.epic.title)
                .font(.smallMedium)
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Self.line)
            Text("\(group.count)")
                .font(.small)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(height: Self.line)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hoveringFold ? Theme.textSecondary : Theme.textTertiary)
                .rotationEffect(.degrees(group.folded ? -90 : 0))
                .frame(width: Self.arrow, height: Self.arrow)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hoveringFold ? Theme.hover : .clear))
                .padding(.vertical, (Self.line - Self.arrow) / 2)
                .opacity(hovered || group.folded ? 1 : 0)
        }
        // Room for the icon, which the Canvas behind draws.
        .padding(.leading, CardTreeLines.indent + Self.spacing)
        .padding(.vertical, Self.padding)
        .padding(.trailing, Self.padding)
        .background {
            // The epic's icon, and the start of the line down to its issues from under the icon, in one pass.
            Canvas { context, size in
                if !group.folded {
                    // On a whole device pixel, as a rectangle view is drawn.
                    let scale = context.environment.displayScale
                    let x = ((CardTreeLines.indent / 2 - 0.5) * scale).rounded() / scale
                    context.fill(Path(CGRect(x: x, y: 19, width: 1, height: size.height - 19)), with: .color(Theme.treeLine))
                }
                let icon = CGRect(x: 2, y: Self.padding + 2, width: 12, height: 12)
                context.stroke(
                    PlanningGlyph.layers(in: icon), with: .color(Theme.epic),
                    style: StrokeStyle(lineWidth: 1.4 * icon.width / 14, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovered && !hoveringFold ? Theme.hover : .clear))
        .animation(Theme.quick, value: hovered)
        // Placed as a whole: without it the name, the count and the icon each take on the hover fade themselves, so
        // they are drawn again on every frame of it, each time waiting for the window server, and the pointer
        // stutters over an epic's header.
        .geometryGroup()
        .contentShape(Rectangle())
        .reportsHeight(Self.measure(group, width: width).key, to: measured)
    }

    /// What VoiceOver finds in the header's place, for every header of the column, drawn or not.
    struct Spoken: View {
        @Environment(AppModel.self) private var model
        var group: Nesting.EpicGroup
        var width: CGFloat
        var height: CGFloat

        var body: some View {
            Color.clear
                .frame(width: width, height: height)
                .accessibilityElement()
                .accessibilityLabel(Text(.epicGroupSpoken(epic: group.epic.title, count: group.count)))
                .accessibilityValue(Text(group.folded ? .sectionFolded : .sectionOpen))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.open(group.epic) }
                .accessibilityAction(named: Text(group.folded ? .showEpicIssues : .foldEpicIssues)) { model.toggleEpicGroup(group) }
        }
    }
}

extension BoardDrag {
    /// Where the fold arrow is in an epic's header with this frame.
    static func epicFoldFrame(in frame: CGRect) -> CGRect {
        EpicGroupHeader.foldFrame(in: frame)
    }
}

/// Where the issues of an epic lifted by their header would land: a dashed card as big as the lifted one.
private struct EpicGroupSlot: View {
    var group: Nesting.EpicGroup
    var width: CGFloat
    var depth: Int
    var measured: MeasuredHeights

    /// As tall as the card the lifted issues show as, which depends on how many lines the epic's name takes.
    static func measure(_ group: Nesting.EpicGroup, width: CGFloat) -> MeasuredHeights.Measure {
        MeasuredHeights.Measure(key: "slot \(Int(width)) \(group.count) \(group.epic.title)") {
            let font = NSFont.systemFont(ofSize: CardView.titleSize, weight: .medium)
            let count = MeasuredHeights.width(of: "\(group.count)", font: .monospacedDigitSystemFont(ofSize: CardView.metaSize, weight: .regular))
            let name = width - 2 * CardView.padding.width - (CardView.lineHeight - 2) - 2 * 8 - count
            let lines = MeasuredHeights.lines(of: group.epic.title, font: font, width: name, limit: 3)
            return max(CardView.lineHeight, MeasuredHeights.textHeight(lines: lines, font: font)) + 2 * CardView.padding.height
        }
    }

    var body: some View {
        let indent = CGFloat(min(depth, CardTreeLines.deepest)) * CardTreeLines.indent
        EpicGroupCard(group: group, width: width - indent)
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
            .padding(.bottom, CardStackEdge.height)
    }
}

/// One position in a column: the card, or the dashed slot while that card is being dragged. A sub-issue card
/// hangs in under its parent, with a line from the parent; a card with sub-issues folded into it shows the edge
/// of a second card under it. The card paints all of that itself: a long column scrolls by showing another card in
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
        /// The edge of a second card under one whose sub-issues are folded into it.
        var edge: CGFloat

        @MainActor init(item: Item, place: Nesting.Place, folded: Bool, drag: BoardDrag) {
            isSlot = drag.active?.item.id == item.id
            indent = CGFloat(min(isSlot ? drag.target?.depth ?? 0 : place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
            slotHeight = isSlot ? drag.active?.size.height ?? 80 : nil
            edge = folded && !isSlot ? CardStackEdge.height : 0
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
        let at = Geometry(item: card.item, place: place, folded: card.folded, drag: drag)
        CardView(
            card: card, width: width - at.indent, highlighted: highlighted, selected: selected,
            avatarVersion: avatarVersion, hoveredPart: pointer?.part, hoveringFold: pointer?.onFold ?? false,
            slotHeight: at.slotHeight, stackEdge: at.edge > 0,
            tree: !at.isSlot && place.depth > 0 ? place : nil
        )
        .equatable()
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

struct ColumnHeader: View {
    @Environment(AppModel.self) private var model
    var column: BoardColumn

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

            if canEdit && column.option != nil || model.currentView != nil {
                GlassMenuButton(label: .columnOptions, size: CGSize(width: 22, height: 22)) {
                    columnMenu(includingNewIssue: false)
                }
                .opacity(hovering ? 1 : 0)
            }

            IconButton(systemName: "plus", label: String(localized: .newIssueInColumnTooltip(column: column.title)), size: 22) {
                newIssue()
            }
            .opacity(hovering ? 1 : 0.55)
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .frame(height: 34)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: hovering)
        // The same options on a right-click, as anywhere else in the app.
        .glassContextMenu { columnMenu(includingNewIssue: true) }
        .confirmationDialog(
            Text(.deleteColumnQuestion(column: column.title)),
            isPresented: $confirmDelete
        ) {
            Button(.deleteColumn, role: .destructive) { delete() }
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(column.count == 0 ? .deleteEmptyColumnMessage : .deleteColumnMessage(count: column.count))
        }
    }

    private var canEdit: Bool { model.currentProject?.viewerCanUpdate == true }

    /// A new issue in this column: with its status or its value, and what the view's filter asks for.
    private func newIssue() {
        if let value = column.value {
            model.newIssuePreset = model.newIssuePreset(projectId: model.currentProjectId, column: value)
        } else if model.currentView != nil {
            model.newIssuePreset = model.newIssuePreset(projectId: model.currentProjectId)
        }
        model.overlay = .newIssue(statusId: column.option?.id, parentItemId: nil)
    }

    private var statuses: [FieldOption] {
        model.currentProjectId.map { model.statusOptions(projectId: $0) } ?? []
    }

    private var position: Int {
        statuses.firstIndex { $0.id == column.id } ?? 0
    }

    /// The status columns the board shows, which Move Left and Move Right step through.
    private var shownStatuses: [String] {
        model.columns.compactMap { $0.option?.id }
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
        guard let projectId = model.currentProjectId, let index = shown.firstIndex(of: column.id),
              shown.indices.contains(index + delta) else { return }
        model.moveColumn(column.id, among: shown, to: index + delta, projectId: projectId)
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
        if editable {
            menu.item(.renameEllipsis, "pencil") { startRename() }
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
            let shown = shownStatuses
            menu.item(.moveLeft, "arrow.left", enabled: shown.first != column.id) { move(-1) }
            menu.item(.moveRight, "arrow.right", enabled: shown.last != column.id) { move(1) }
            menu.divider()
        }
        // Hidden here only, for a view's board; one column always stays.
        if let view = model.currentView {
            menu.item(.hideColumn, "eye.slash", enabled: model.columns.count > 1) { [model, id = column.id] in
                model.setColumn(id, hidden: true, of: view)
            }
            menu.divider()
        }
        if editable {
            menu.item(.deleteColumnEllipsis, "trash", enabled: statuses.count > 1, destructive: true) { confirmDelete = true }
        }
        if includingNewIssue {
            menu.divider()
            menu.item(String(localized: .newIssueInColumnMenuItem(column: column.title)), "plus") { newIssue() }
        }
        return menu.build()
    }

}

/// The columns you hid on the board, at its end: each with its count, shown again with a click.
private struct HiddenColumnsList: View {
    @Environment(AppModel.self) private var model
    var projectId: String

    var body: some View {
        let hidden = model.hiddenColumns(projectId: projectId)
        if !hidden.isEmpty, let view = model.currentView {
            VStack(alignment: .leading, spacing: 2) {
                Text(.hiddenColumns)
                    .font(.small)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                ForEach(hidden) { column in
                    Button {
                        model.setColumn(column.id, hidden: false, of: view)
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
                        if !isFocused { adding = false }
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        adding = false
        guard !trimmed.isEmpty, let projectId = model.currentProjectId else { return }
        let options = model.statusOptions(projectId: projectId).map(\.remote) + [RemoteOption(id: nil, name: trimmed, color: "GRAY")]
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }
}

#endif
