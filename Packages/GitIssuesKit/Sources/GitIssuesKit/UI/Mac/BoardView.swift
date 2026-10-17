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
                    // A milestone's board shows the board's columns; they are changed on the board itself.
                    if model.currentProject?.viewerCanUpdate == true, model.currentMilestoneTitle == nil, columns.allSatisfy({ $0.value == nil }) {
                        AddColumnButton()
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

    private func columnWidth(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 280 }
        let addColumn: CGFloat = model.currentProject?.viewerCanUpdate == true && model.currentMilestoneTitle == nil ? 192 : 0
        let fitted = (available - 32 - addColumn - CGFloat(count - 1) * 12) / CGFloat(count)
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

/// Where a view was last drawn, kept without redrawing the view when it changes.
final class LastFrame {
    var frame: CGRect?
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
    @State private var hoveredId: String?
    @State private var hoveredPart: PickerKind?
    @State private var hoveringFold = false
    /// The epic whose header is under the pointer, and whether the pointer is on its fold arrow.
    @State private var hoveredEpic: String?
    @State private var hoveringEpicFold = false

    /// A row of the column as drawn: an issue, an epic's header, or the slot where an epic's lifted issues land.
    /// Each column stands in a soft lane, as Reminders sets its columns apart, with the cards inset in it.
    static let laneRadius: CGFloat = 18
    static let laneInset: CGFloat = 8

    private enum Line: Identifiable {
        case row(Nesting.Row)
        case groupSlot(BoardDrag.GroupDrag, depth: Int)

        var id: String {
            switch self {
            case .row(let row): row.id
            case .groupSlot: "epic-group-slot"
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
        VStack(spacing: 6) {
            ColumnHeader(column: column)
                // Drag the header sideways to move the whole column.
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(BoardDrag.space))
                        .onChanged { onHeaderDrag($0.translation.width) }
                        .onEnded { _ in onHeaderDrop() }
                )

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(lines) { line in
                        switch line {
                        case .groupSlot(let group, let depth):
                            EpicGroupSlot(group: group.group, width: width, depth: depth, drag: drag)
                        case .row(.epic(let group)):
                            EpicGroupHeader(
                                group: group, columnId: column.id, drag: drag,
                                hovered: !model.isDragging && hoveredEpic == group.contentId,
                                hoveringFold: !model.isDragging && hoveredEpic == group.contentId && hoveringEpicFold
                            )
                        case .row(.item(let item)):
                            BoardCell(
                                card: model.cardModel(for: item, in: column.nesting, showsMilestone: model.currentMilestoneTitle == nil), width: width, drag: drag,
                                place: column.nesting.place(of: item.id),
                                highlighted: !model.isDragging && (hoveredId == item.id || model.focusedItemId == item.id),
                                selected: model.isSelected(item.id),
                                hoveredPart: hoveredId == item.id && !model.isDragging ? hoveredPart : nil,
                                hoveringFold: hoveredId == item.id && !model.isDragging && hoveringFold,
                                avatarVersion: model.avatarVersion
                            )
                        }
                    }
                }
                .padding(.bottom, 40)
                .animation(Theme.spring, value: lines.map(\.id))
                // One hover and one click handler per column instead of one per card.
                .contentShape(Rectangle())
                // The part under the pointer names its value, as in Linear.
                .help(Text(hoveredTooltip))
                .onContinuousHover(coordinateSpace: .named(BoardDrag.space)) { phase in
                    switch phase {
                    case .active(let point):
                        hover(card(at: point))
                        let part = drag.part(at: point, in: column.items)?.kind
                        if part != hoveredPart { hoveredPart = part }
                        let onFold = drag.fold(at: point, in: column.items) != nil
                        if onFold != hoveringFold { hoveringFold = onFold }
                        let header = drag.header(at: point, in: column.id)
                        if header?.epic != hoveredEpic { hoveredEpic = header?.epic }
                        let onEpicFold = header.map { drag.isOnFold(point, of: $0) } ?? false
                        if onEpicFold != hoveringEpicFold { hoveringEpicFold = onEpicFold }
                    case .ended:
                        hover(nil)
                        hoveredPart = nil
                        hoveringFold = false
                        hoveredEpic = nil
                        hoveringEpicFold = false
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
            }
            .scrollIndicators(.never)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                [geometry.contentOffset.y, max(0, geometry.contentSize.height - geometry.containerSize.height)]
            } action: { _, new in
                metrics.offset = new[0]
                metrics.maxOffset = new[1]
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
        .onDisappear { drag.columnFrames[column.id] = nil }
        .onChange(of: drag.tick) { autoScroll() }
    }

    private var hoveredTooltip: String {
        if let epic = hoveredEpic, hoveringEpicFold, let group = column.nesting.groups.first(where: { $0.contentId == epic }) {
            return String(localized: group.folded ? .unfoldEpicGroupTooltip(count: group.count) : .foldEpicGroupTooltip)
        }
        guard let item = column.items.first(where: { $0.id == hoveredId }) else { return "" }
        if hoveringFold {
            guard column.nesting.folded.contains(item.id) else { return String(localized: .foldSubIssuesTooltip) }
            return String(localized: .unfoldSubIssuesTooltip(count: column.nesting.nestedCounts[item.id] ?? 0))
        }
        guard let hoveredPart else { return "" }
        return model.tooltip(hoveredPart, for: item)
    }

    private func card(at point: CGPoint) -> Item? {
        column.items.first { drag.cardFrames[$0.id]?.contains(point) == true }
    }

    private func hover(_ item: Item?) {
        guard hoveredId != item?.id else { return }
        if let previous = hoveredId { model.pointer(.left, previous) }
        hoveredId = item?.id
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

/// Over the issues of an epic standing together in a column: the epic's icon where the line down to them starts,
/// its name on up to three lines, how many of its issues are there, and the arrow that folds them away. A click
/// opens the epic, one on the arrow folds its issues or shows them again, and dragging it moves them all. The
/// column handles the clicks and the board the drag, from where the header and its arrow are.
private struct EpicGroupHeader: View {
    @Environment(AppModel.self) private var model
    var group: Nesting.EpicGroup
    var columnId: String
    var drag: BoardDrag
    var hovered: Bool
    var hoveringFold: Bool
    @State private var owner = UUID()
    @State private var last = LastFrame()

    /// The height of a line of its name, which the icon, the count and the arrow line up with.
    private static let line: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            EpicIcon(size: 12)
                .frame(width: CardTreeLines.indent, height: Self.line)
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
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hoveringFold ? Theme.hover : .clear))
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(BoardDrag.space))
                } action: { frame in
                    drag.setHeaderFold(frame, column: columnId, epic: group.contentId)
                }
                .padding(.vertical, (Self.line - 20) / 2)
                .opacity(hovered || group.folded ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 4)
        .background(alignment: .topLeading) {
            // The start of the line down to the epic's issues, from under its icon.
            if !group.folded {
                Rectangle().fill(Theme.treeLine).frame(width: 1).padding(.top, 19).offset(x: CardTreeLines.indent / 2 - 0.5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovered && !hoveringFold ? Theme.hover : .clear))
        .animation(Theme.quick, value: hovered)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(BoardDrag.space))
        } action: { frame in
            last.frame = frame
            drag.setHeaderFrame(frame, column: columnId, epic: group.contentId, owner: owner)
        }
        .onAppear { if let frame = last.frame { drag.setHeaderFrame(frame, column: columnId, epic: group.contentId, owner: owner) } }
        .onDisappear { drag.removeHeaderFrame(column: columnId, epic: group.contentId, owner: owner) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.epicGroupSpoken(epic: group.epic.title, count: group.count)))
        .accessibilityValue(Text(group.folded ? .sectionFolded : .sectionOpen))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(group.epic) }
        .accessibilityAction(named: Text(group.folded ? .showEpicIssues : .foldEpicIssues)) { model.toggleEpicGroup(group) }
    }
}

/// Where the issues of an epic lifted by their header would land: a dashed card as big as the lifted one.
private struct EpicGroupSlot: View {
    var group: Nesting.EpicGroup
    var width: CGFloat
    var depth: Int
    var drag: BoardDrag
    @State private var owner = UUID()

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
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(BoardDrag.space))
            } action: { frame in
                // The lifted card settles into it.
                drag.setCardFrame(frame, for: group.epic.id, owner: owner)
            }
            .onDisappear { drag.removeCardFrame(for: group.epic.id, owner: owner) }
            .padding(.leading, indent)
            .padding(.bottom, CardStackEdge.height)
    }
}

/// One position in a column: the card, or the dashed slot while that card is being dragged. A sub-issue card
/// hangs in under its parent, with a line from the parent; a card with sub-issues folded into it shows the edge
/// of a second card under it.
private struct BoardCell: View {
    var card: CardModel
    var width: CGFloat
    var drag: BoardDrag
    var place: Nesting.Place
    var highlighted: Bool
    var selected: Bool
    var hoveredPart: PickerKind?
    var hoveringFold: Bool
    var avatarVersion: Int
    @State private var owner = UUID()
    @State private var last = LastFrame()

    var body: some View {
        let id = card.item.id
        let isSlot = drag.active?.item.id == id
        let depth = min(isSlot ? drag.target?.depth ?? 0 : place.depth, CardTreeLines.deepest)
        let indent = CGFloat(depth) * CardTreeLines.indent
        ZStack {
            if isSlot {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .frame(height: drag.active?.size.height ?? 80)
            } else {
                CardView(
                    card: card, width: width - indent, highlighted: highlighted, selected: selected,
                    avatarVersion: avatarVersion, hoveredPart: hoveredPart, hoveringFold: hoveringFold
                )
                .equatable()
                .background(alignment: .top) { if card.folded { CardStackEdge() } }
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(BoardDrag.space))
        } action: { frame in
            last.frame = frame
            drag.setCardFrame(frame, for: id, owner: owner)
        }
        // A card that comes back to where its view stood before, such as one dragged away and back, gets that view
        // again, which reports no change of place.
        .onAppear { if let frame = last.frame { drag.setCardFrame(frame, for: id, owner: owner) } }
        .onDisappear { drag.removeCardFrame(for: id, owner: owner) }
        .padding(.bottom, card.folded && !isSlot ? CardStackEdge.height : 0)
        .padding(.leading, indent)
        .background(alignment: .topLeading) {
            if !isSlot, place.depth > 0 { CardTreeLines(place: place, gap: 8) }
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
            if let value = column.value {
                // A column of another field: its option's colour, or an iteration.
                if let dot = column.dot {
                    GroupIcon(icon: .dot(dot))
                } else if value.value?.iterationId != nil {
                    GroupIcon(icon: .iteration(current: column.detail == String(localized: .currentIteration)))
                } else {
                    StatusIcon(glyph: column.glyph)
                }
            } else {
                StatusIcon(glyph: column.glyph)
            }
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

            if canEdit, column.option != nil {
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
        guard let projectId = model.currentProjectId else { return }
        var options = statuses.map(\.remote)
        let destination = position + delta
        guard options.indices.contains(position), options.indices.contains(destination) else { return }
        options.swapAt(position, destination)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
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
    /// Rename, colour, move and delete the column, and a new issue in it, as a menu in glass.
    func columnMenu(includingNewIssue: Bool) -> NSMenu {
        let menu = MenuBuilder()
        if canEdit, column.option != nil {
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
            menu.item(.moveLeft, "arrow.left", enabled: position != 0) { move(-1) }
            menu.item(.moveRight, "arrow.right", enabled: position != statuses.count - 1) { move(1) }
            menu.divider()
            menu.item(.deleteColumnEllipsis, "trash", enabled: statuses.count > 1, destructive: true) { confirmDelete = true }
        }
        if includingNewIssue {
            menu.divider()
            menu.item(String(localized: .newIssueInColumnMenuItem(column: column.title)), "plus") { newIssue() }
        }
        return menu.build()
    }

    /// GitHub's name for a colour ("GRAY") as the menu shows it.
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
