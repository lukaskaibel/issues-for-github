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
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.panel)
                                    .shadow(color: Theme.shadow, radius: 20, y: 10)
                                    .padding(-8)
                            }
                        }
                        .offset(x: drag.columnOffset(index, step: width + 12))
                        .zIndex(lifted ? 1 : 0)
                    }
                    .animation(Theme.spring, value: drag.column?.to)
                    if model.currentProject?.viewerCanUpdate == true {
                        AddColumnButton()
                            .frame(width: 180, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
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
                    LiftedCard(active: active, card: model.cardModel(for: active.item), avatarVersion: model.avatarVersion)
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
        let addColumn: CGFloat = model.currentProject?.viewerCanUpdate == true ? 192 : 0
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

    var body: some View {
        VStack(spacing: 8) {
            ColumnHeader(column: column)
                // Drag the header sideways to move the whole column.
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(BoardDrag.space))
                        .onChanged { onHeaderDrag($0.translation.width) }
                        .onEnded { _ in onHeaderDrop() }
                )

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(column.items) { item in
                        BoardCell(
                            card: model.cardModel(for: item), width: width, drag: drag,
                            highlighted: !model.isDragging && (hoveredId == item.id || model.focusedItemId == item.id),
                            selected: model.isSelected(item.id),
                            hoveredPart: hoveredId == item.id && !model.isDragging ? hoveredPart : nil,
                            avatarVersion: model.avatarVersion
                        )
                    }
                }
                .padding(.bottom, 48)
                .animation(Theme.spring, value: column.items.map(\.id))
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
                    case .ended:
                        hover(nil)
                        hoveredPart = nil
                    }
                }
                .gesture(SpatialTapGesture(coordinateSpace: .named(BoardDrag.space)).onEnded { value in
                    // ⌘- and Shift-clicks pick cards. Otherwise a click on a card's priority, labels, sub-issues or
                    // assignees opens that dropdown, and anywhere else on the card opens the issue.
                    if let item = card(at: value.location), model.handleSelectionClick(on: item) {
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
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(BoardDrag.space))
        } action: { frame in
            drag.columnFrames[column.id] = frame
        }
        .onDisappear { drag.columnFrames[column.id] = nil }
        .onChange(of: drag.tick) { autoScroll() }
    }

    private var hoveredTooltip: String {
        guard let hoveredPart, let item = column.items.first(where: { $0.id == hoveredId }) else { return "" }
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

/// One position in a column: the card, or the dashed slot while that card is being dragged.
private struct BoardCell: View {
    var card: CardModel
    var width: CGFloat
    var drag: BoardDrag
    var highlighted: Bool
    var selected: Bool
    var hoveredPart: PickerKind?
    var avatarVersion: Int
    @State private var owner = UUID()

    var body: some View {
        let id = card.item.id
        ZStack {
            if drag.active?.item.id == id {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .frame(height: drag.active?.size.height ?? 80)
            } else {
                CardView(card: card, width: width, highlighted: highlighted, selected: selected, avatarVersion: avatarVersion, hoveredPart: hoveredPart)
                    .equatable()
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(BoardDrag.space))
        } action: { frame in
            drag.setCardFrame(frame, for: id, owner: owner)
        }
        .onDisappear { drag.removeCardFrame(for: id, owner: owner) }
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
            StatusIcon(glyph: column.glyph)
            if renaming {
                TextField("Column name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.uiSemibold)
                    .focused($nameFocused)
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
                Text("\(column.items.count)").foregroundStyle(Theme.textTertiary).monospacedDigit()
            }
            Spacer(minLength: 0)

            if canEdit, column.option != nil {
                Menu {
                    columnMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel("Column options")
            }

            IconButton(systemName: "plus", label: "New issue in \(column.title)", size: 22) {
                model.overlay = .newIssue(statusId: column.option?.id, parentItemId: nil)
            }
            .opacity(hovering ? 1 : 0.55)
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: hovering)
        // The same options on a right-click, as anywhere else in the app.
        .contextMenu {
            if canEdit, column.option != nil {
                columnMenu
                Divider()
            }
            Button("New Issue in \(column.title)") {
                model.overlay = .newIssue(statusId: column.option?.id, parentItemId: nil)
            }
        }
        .confirmationDialog(
            "Delete the \"\(column.title)\" column?",
            isPresented: $confirmDelete
        ) {
            Button("Delete Column", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(column.items.isEmpty
                 ? "The column is removed from the project on GitHub."
                 : "The column is removed from the project on GitHub. Its \(column.items.count) issue\(column.items.count == 1 ? "" : "s") stay in the project without a status.")
        }
    }

    private var canEdit: Bool { model.currentProject?.viewerCanUpdate == true }

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
    @ViewBuilder var columnMenu: some View {
        Button("Rename…") { startRename() }
        Menu("Colour") {
            ForEach(Defaults.optionColors, id: \.self) { color in
                Button {
                    edit { $0.color = color }
                } label: {
                    if column.option?.color == color {
                        Label(color.capitalized, systemImage: "checkmark")
                    } else {
                        Text(color.capitalized)
                    }
                }
            }
        }
        Divider()
        Button("Move Left") { move(-1) }.disabled(position == 0)
        Button("Move Right") { move(1) }.disabled(position == statuses.count - 1)
        Divider()
        Button("Delete Column…", role: .destructive) { confirmDelete = true }
            .disabled(statuses.count <= 1)
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
                TextField("Column name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.uiSemibold)
                    .focused($focused)
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
                        Text("Add column")
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
