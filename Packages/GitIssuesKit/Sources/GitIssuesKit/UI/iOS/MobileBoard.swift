#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The board on the iPad: the Mac's columns and cards, moved with the system's drag and drop. Touch and
/// hold a card to lift it (or to open its menu), then drag it to another place or column; the cards there
/// make room. The header over an epic's issues lifts them all. Dragged out of the app, a card is its link on GitHub.
struct MobileBoard: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    /// A milestone of the board, whose issues it shows in the board's columns.
    var milestone: String? = nil
    /// The project's All Issues: the issues on no board in a column of their own, then the board's columns, in an
    /// order of your own.
    var allIssues = false

    @State private var target: BoardDropTarget?
    /// The card a drag hovering this board carries, which may have been lifted in another window: it dims, and a
    /// card of another project finds no place here. A drop reads its card from the drag instead.
    @State private var dragging: String?
    @State private var dropped = 0
    @State private var addingStatus = false
    @State private var newStatus = ""

    var body: some View {
        let scope = Self.scope(projectId: projectId, milestone: milestone, allIssues: allIssues)
        let columns = model.shownColumns(for: scope)
        let canEdit = model.projects.first { $0.id == projectId }?.viewerCanUpdate == true
        let hidden = model.hiddenColumns(in: scope)
        // A milestone's board and All Issues show the board's columns; they are changed on the board itself.
        let addsStatus = canEdit && milestone == nil && !allIssues && columns.allSatisfy { $0.value == nil }
        GeometryReader { proxy in
            let width = columnWidth(available: proxy.size.width, count: columns.count, trailing: addsStatus || !hidden.isEmpty)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(columns) { column in
                        MobileColumn(
                            projectId: projectId, milestone: milestone, allIssues: allIssues, column: column, width: width,
                            target: $target, dragging: $dragging,
                            onDrop: { id, slot in move(id, to: column, at: slot) },
                            onNest: { id, parent in nest(id, under: parent, in: column) }
                        )
                        .frame(width: width)
                    }
                    if addsStatus || !hidden.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            if addsStatus {
                                Button {
                                    newStatus = ""
                                    addingStatus = true
                                } label: {
                                    Label(.addStatus, systemImage: "plus")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverEffect(.highlight)
                            }
                            if !hidden.isEmpty {
                                MobileHiddenColumns(columns: hidden, scope: scope)
                            }
                        }
                        .frame(width: 170, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.board)
        .sensoryFeedback(.impact(weight: .medium), trigger: dropped)
        .alert(.newStatus, isPresented: $addingStatus) {
            TextField(.statusNamePlaceholder, text: $newStatus)
            Button(.cancel, role: .cancel) {}
            Button(.add) {
                let name = newStatus.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let options = model.statusOptions(projectId: projectId).map(\.remote) + [RemoteOption(id: nil, name: name, color: "GRAY")]
                withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
            }
        } message: {
            Text(.newStatusMessage)
        }
    }

    /// Between columns, which leave room beside their cards for the cards' shadows as well: 22 points from the cards
    /// of one column to the next.
    static let spacing: CGFloat = 14

    private func columnWidth(available: CGFloat, count: Int, trailing: Bool) -> CGFloat {
        guard count > 0 else { return 290 }
        let extra: CGFloat = trailing ? 184 : 0
        let fitted = (available - 36 - extra - CGFloat(count - 1) * Self.spacing) / CGFloat(count)
        return min(max(fitted, 268), 330)
    }

    private func move(_ id: String?, to column: BoardColumn, at slot: Int?) {
        target = nil
        dragging = nil
        if Self.land(id, in: column, at: slot, model: model, projectId: projectId, milestone: milestone, allIssues: allIssues) { dropped += 1 }
    }

    private func nest(_ id: String?, under parentId: String, in column: BoardColumn) {
        target = nil
        dragging = nil
        if DropOntoIssue.nest(id, under: parentId, shown: column.nesting, model: model) { dropped += 1 }
    }

    /// The board a project's, one of its milestones' or its All Issues' board shows.
    static func scope(projectId: String, milestone: String?, allIssues: Bool) -> Scope {
        if allIssues { return .allIssues(projectId) }
        return milestone.map { .milestone(projectId: projectId, title: $0) } ?? .project(projectId)
    }

    /// Lands a card at `slot` among all of the column's cards, itself included, or at the end without one. An
    /// epic's issues lifted by their header land there together. In All Issues, an issue on no board goes on the board,
    /// at the end of the column. False when the drag carried nothing that can land there.
    @discardableResult
    static func land(
        _ id: String?, in column: BoardColumn, at slot: Int?, model: AppModel, projectId: String, milestone: String?,
        allIssues: Bool = false
    ) -> Bool {
        // Nothing goes into All Issues' issues on no board: taking an issue off its board would lose what it has there.
        guard !column.isOnNoBoard else { return false }
        if let id, let lifted = DraggedGroup(id) {
            let board = allIssues ? model.columns(for: .allIssues(projectId)) : model.columns(projectId: projectId)
            let members = board.flatMap(\.nesting.members).filter { lifted.ids.contains($0.id) }
            guard let group = lifted.group(model: model, projectId: projectId, milestone: milestone, allIssues: allIssues), !members.isEmpty else { return false }
            let index = column.items.prefix(slot ?? column.items.count).filter { !lifted.ids.contains($0.id) }.count
            withAnimation(Theme.spring) { model.drop(group, members: members, in: column, at: index, milestone: milestone, inAllIssues: allIssues) }
            return true
        }
        let scope = Self.scope(projectId: projectId, milestone: milestone, allIssues: allIssues)
        guard let id, let item = model.item(id: id), model.fits(item, onBoardOf: scope) else { return false }
        if !item.isOnBoard {
            withAnimation(Theme.spring) { model.addToBoard([item], in: column, projectId: projectId) }
            return true
        }
        // The model counts the place among the column's other cards, without the sub-issues the card brings along.
        let others = Set(column.shown(without: item).map(\.id))
        let index = column.items.prefix(slot ?? column.items.count).filter { others.contains($0.id) }.count
        withAnimation(Theme.spring) { model.drop(item, in: column, at: index, milestone: milestone, inAllIssues: allIssues) }
        return true
    }
}

/// The columns you hid on the board, after its last column: each with its count, shown again with a tap.
private struct MobileHiddenColumns: View {
    @Environment(AppModel.self) private var model
    var columns: [BoardColumn]
    var scope: Scope

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(.hiddenColumns)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            ForEach(columns) { column in
                Button {
                    model.setColumn(column.id, hidden: false, in: scope)
                } label: {
                    HStack(spacing: 8) {
                        ColumnIcon(column: column, size: 16)
                        Text(column.title).lineLimit(1)
                        Text("\(column.count)").monospacedDigit().foregroundStyle(Theme.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityHint(Text(.showColumnAgainTooltip))
            }
        }
    }
}

/// Where a dragged card would land: a column, and the position among all of its cards. Counting the dragged card
/// too, this needs no knowing which card it is, which the drag only tells once dropped.
struct BoardDropTarget: Equatable {
    var columnId: String
    var slot: Int
    /// How far in the card would hang there: under its parent, when the parent is in that column, or its epic's
    /// header.
    var depth = 0
    /// Where the gap shows among all of the column's rows, epic headers and the dragged card included.
    var row: Int?
    /// Whether an epic's issues are dragged by their header, which land as one smaller card.
    var group = false
    /// The card (item id) the dragged card is held over the middle of, and goes under as a sub-issue if let go there:
    /// it lights up, and the gap, if one was open, keeps its room unseen, so that no card moves under the finger.
    var nest: String? = nil
    /// No gap at all: the card was held over another card's middle before any gap opened in this column.
    var gapless = false
}

/// The issues of an epic standing together in a column, lifted by their header: what the drag carries, in place of a
/// card's id, so that a drop in any window moves the issues that were lifted.
struct DraggedGroup: Equatable {
    static let prefix = "epic-group\u{1F}"

    var columnId: String
    /// The epic's node id.
    var epic: String
    var ids: Set<String>

    init(columnId: String, epic: String, ids: Set<String>) {
        self.columnId = columnId
        self.epic = epic
        self.ids = ids
    }

    init?(_ token: String) {
        guard token.hasPrefix(Self.prefix) else { return nil }
        let parts = token.dropFirst(Self.prefix.count).split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        self.init(columnId: parts[0], epic: parts[1], ids: Set(parts[2].split(separator: ",").map(String.init)))
    }

    var token: String {
        Self.prefix + [columnId, epic, ids.sorted().joined(separator: ",")].joined(separator: "\u{1F}")
    }

    /// The group as the board shows it now.
    @MainActor
    func group(model: AppModel, projectId: String, milestone: String?, allIssues: Bool = false) -> Nesting.EpicGroup? {
        let columns = model.columns(for: MobileBoard.scope(projectId: projectId, milestone: milestone, allIssues: allIssues))
        return (columns.first { $0.id == columnId }?.nesting.groups ?? columns.flatMap(\.nesting.groups))
            .first { $0.contentId == epic }
    }
}

/// Card frames inside a column, read while dropping. Kept outside view state so scrolling never redraws.
@MainActor
final class CardFrames {
    var frames: [String: CGRect] = [:]
}

/// One column of the board: its header, and its cards in a scroll of their own, taking cards dropped on it. The
/// iPad's board puts them side by side, the iPhone's one at a time.
struct MobileColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    var projectId: String
    var milestone: String? = nil
    var allIssues = false
    var column: BoardColumn
    var width: CGFloat
    @Binding var target: BoardDropTarget?
    @Binding var dragging: String?
    var onDrop: (String?, Int?) -> Void
    /// A card let go over the middle of another one: the dragged card's id, and the other card's.
    var onNest: (String?, String) -> Void

    @State private var frames = CardFrames()
    @State private var foldFeedback = 0

    var body: some View {
        let space = "column-\(column.id)"
        VStack(spacing: 6 - CardView.shadowRoom.top) {
            MobileColumnHeader(projectId: projectId, milestone: milestone, allIssues: allIssues, column: column)
                .padding(.horizontal, Self.inset)
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(column.nesting.rows.enumerated()), id: \.element.id) { index, row in
                        if gapPosition == index {
                            gap
                        }
                        switch row {
                        case .item(let item):
                            nestedCard(item, space: space)
                        case .epic(let group):
                            groupHeader(group)
                        }
                    }
                    if gapPosition == column.nesting.rows.count {
                        gap
                    }
                }
                // Room for the cards' shadows, which the scroll view would cut off.
                .padding(.horizontal, Self.inset)
                .padding(.top, CardView.shadowRoom.top)
                .padding(.bottom, 80)
                .animation(Theme.spring, value: target)
                .animation(Theme.spring, value: column.nesting.rows.map(\.id))
            }
            .scrollIndicators(.hidden)
            // Pull down: sync now, as on every list.
            .refreshable { await model.refreshAndWait() }
            .coordinateSpace(.named(space))
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("column-\(column.title)")
            .sensoryFeedback(.selection, trigger: foldFeedback)
            // A tick as a card lights up to take the dragged one under it.
            .sensoryFeedback(trigger: nestTarget) { _, new in new == nil ? nil : .selection }
            .onDrop(of: [.plainText, .url], delegate: ColumnDrop(
                model: model, scope: MobileBoard.scope(projectId: projectId, milestone: milestone, allIssues: allIssues),
                column: column, frames: frames, target: $target, dragging: $dragging, onDrop: onDrop, onNest: onNest
            ))
        }
        // The columns stand on the board's grey without lanes, and reach the bottom edge, where their cards scroll out
        // of sight.
        .padding(.top, 4)
    }

    /// How far in from the column's edges its cards are, for their shadows.
    static let inset = CardView.shadowRoom.leading

    /// The cards' width in the column.
    private var inner: CGFloat { width - 2 * Self.inset }

    /// The card of this column a dragged card is held over the middle of, which would take it as a sub-issue.
    private var nestTarget: String? {
        target?.columnId == column.id ? target?.nest : nil
    }

    /// Where the gap shows among all of the column's rows, the dragged card included.
    private var gapPosition: Int? {
        guard let target, target.columnId == column.id, !target.gapless else { return nil }
        if let row = target.row { return min(row, column.nesting.rows.count) }
        // Without knowing the card yet: in front of the card at the slot.
        guard target.slot < column.items.count else { return column.nesting.rows.count }
        return column.nesting.rows.firstIndex { $0.id == column.items[target.slot].id }
    }

    private var gap: some View {
        RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous)
            .fill(Theme.accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous)
                    .stroke(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .frame(height: target?.group == true ? 52 : 76)
            .padding(.leading, CGFloat(min(target?.depth ?? 0, CardTreeLines.deepest)) * CardTreeLines.indent)
            // Kept, unseen, while a card is lit to take the dragged one, so that nothing moves under the finger.
            .opacity(nestTarget == nil ? 1 : 0)
            .accessibilityHidden(true)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// The issues an epic's header lifted, which dim while they are dragged over this board.
    private var liftedIds: Set<String> {
        dragging.flatMap(DraggedGroup.init)?.ids ?? []
    }

    /// The header over an epic's issues. Touch and hold, then drag, to move them all.
    private func groupHeader(_ group: Nesting.EpicGroup) -> some View {
        let lifted = DraggedGroup(columnId: column.id, epic: group.contentId, ids: Set(column.members(of: group).map(\.id)))
        return EpicGroupCardHeader(group: group, column: column, open: { openRoute(.issue(group.epic.id)) }, step: { step(group, by: $0) })
            .opacity(dragging == lifted.token && target != nil ? 0.35 : 1)
            .onDrag {
                CardDragMark.lifted = lifted.token
                return CardDragMark.provider(id: lifted.token, text: group.epic.url ?? group.epic.title)
            } preview: {
                EpicGroupCard(group: group, width: inner)
                    .padding(.bottom, CardStackEdge.height)
            }
    }

    /// A card in its place: a sub-issue hangs in under its parent, with a line from the parent, and a card with
    /// sub-issues folded into it shows the edge of a second card under it. The arrow at its top left folds them.
    private func nestedCard(_ item: Item, space: String) -> some View {
        let place = column.nesting.place(of: item.id)
        let indent = CGFloat(min(place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
        let folded = column.nesting.folded.contains(item.id)
        return card(item, space: space, width: inner - indent)
            .background(alignment: .top) { if folded { CardStackEdge() } }
            .overlay(alignment: .topLeading) {
                if let count = column.nesting.nestedCounts[item.id] {
                    Button {
                        foldFeedback += 1
                        model.toggleFolded(item)
                    } label: {
                        Color.clear.frame(width: 44, height: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(folded ? Text(.unfoldSubIssuesTooltip(count: count)) : Text(.foldSubIssuesTooltip))
                    .accessibilityIdentifier("fold-\(item.displayNumber)")
                }
            }
            .padding(.bottom, folded ? CardStackEdge.height : 0)
            .padding(.leading, indent)
            .background(alignment: .topLeading) {
                if place.depth > 0 { CardTreeLines(place: place, gap: 8) }
            }
    }

    private func card(_ item: Item, space: String, width: CGFloat) -> some View {
        let lit = nestTarget == item.id
        return Button {
            openRoute(.issue(item.id))
        } label: {
            CardView(card: model.cardModel(for: item, in: column.nesting, showsMilestone: milestone == nil), width: width, selected: lit, avatarVersion: model.avatarVersion)
                .equatable()
        }
        .buttonStyle(CardPressStyle())
        .accessibilityIdentifier("card-\(item.displayNumber)")
        .hoverEffect(.lift)
        // Lit to take the dragged card as a sub-issue: a ring a little outside the card and a card a little larger, so
        // both show around the dragged card, which covers most of it.
        .overlay {
            if lit {
                RoundedRectangle(cornerRadius: CardView.cornerRadius + Self.nestRingOutset, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
                    .padding(-Self.nestRingOutset)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .scaleEffect(lit ? 1.03 : 1)
        .animation(Theme.quick, value: lit)
        .opacity((dragging == item.id || liftedIds.contains(item.id)) && target != nil ? 0.35 : 1)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { frame in
            frames.frames[item.id] = frame
        }
        .onDisappear { frames.frames[item.id] = nil }
        .onDrag {
            CardDragMark.lifted = item.id
            return CardDragMark.provider(id: item.id, text: dragText(item))
        } preview: {
            CardView(card: model.cardModel(for: item, in: column.nesting, showsMilestone: milestone == nil), width: width, lifted: true, avatarVersion: model.avatarVersion)
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous))
        .contextMenu {
            ItemMenuContent(item: item, foldable: column.nesting.hasNested(item.id)) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
        .accessibilityAction(named: Text(.moveToNextStatus)) { step(item, by: 1) }
        .accessibilityAction(named: Text(.moveToPreviousStatus)) { step(item, by: -1) }
    }

    /// How far outside a card the ring is that lights it up to take a dragged card.
    static let nestRingOutset: CGFloat = 4

    /// What a card is outside the app: its link on GitHub, or its number and title.
    private func dragText(_ item: Item) -> String {
        item.url ?? "\(item.displayNumber) \(item.title)"
    }

    /// For VoiceOver, which can't drag: moves the card to the neighbouring column.
    private func step(_ item: Item, by delta: Int) {
        guard let next = neighbour(delta) else { return }
        MobileBoard.land(item.id, in: next, at: nil, model: model, projectId: projectId, milestone: milestone, allIssues: allIssues)
    }

    /// For VoiceOver: moves an epic's issues here to the neighbouring column.
    private func step(_ group: Nesting.EpicGroup, by delta: Int) {
        guard let next = neighbour(delta) else { return }
        let members = column.members(of: group)
        withAnimation(Theme.spring) { model.drop(group, members: members, in: next, at: next.items.count, milestone: milestone, inAllIssues: allIssues) }
    }

    /// The column beside this one a card can go to: past All Issues' issues on no board, which take none.
    private func neighbour(_ delta: Int) -> BoardColumn? {
        let columns = model.shownColumns(for: MobileBoard.scope(projectId: projectId, milestone: milestone, allIssues: allIssues))
            .filter { !$0.isOnNoBoard || $0.id == column.id }
        guard let index = columns.firstIndex(where: { $0.id == column.id }), columns.indices.contains(index + delta) else { return nil }
        return columns[index + delta]
    }
}

/// Lands cards dropped on a column at the place the finger points to. Which card it is comes from the drag, which
/// may have started in another window.
private struct ColumnDrop: DropDelegate {
    var model: AppModel
    /// The board: a project's, one of its milestones' or its All Issues'.
    var scope: Scope
    var column: BoardColumn
    var frames: CardFrames
    @Binding var target: BoardDropTarget?
    @Binding var dragging: String?
    var onDrop: (String?, Int?) -> Void
    var onNest: (String?, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        CardDragMark.isCard(info)
    }

    func dropEntered(info: DropInfo) {
        dragging = MainActor.assumeIsolated { CardDragMark.lifted }
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        // Going under another card adds to what is there, which the dragged card's badge says with a plus.
        if target?.columnId == column.id, target?.nest != nil { return DropProposal(operation: .copy) }
        return DropProposal(operation: fits ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        if target?.columnId == column.id { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard CardDragMark.isCard(info) else { return false }
        if target?.columnId == column.id, let parent = target?.nest {
            CardDragMark.loadId(info) { id in onNest(id, parent) }
            return true
        }
        guard fits else { return false }
        let slot = target?.columnId == column.id ? target?.slot : nil
        CardDragMark.loadId(info) { id in onDrop(id, slot) }
        return true
    }

    /// A card of another project, dragged in from a window that shows that project, can't land here, and nothing can
    /// go into All Issues' issues on no board.
    private var fits: Bool {
        guard !column.isOnNoBoard else { return false }
        guard let dragging else { return true }
        let id = DraggedGroup(dragging)?.ids.first ?? dragging
        return MainActor.assumeIsolated { model.item(id: id).map { model.fits($0, onBoardOf: scope) } ?? false }
    }

    /// The card the finger holds the dragged card over the middle of, if the dragged card can go under it: its item
    /// id. Its top and bottom edges are left to placing the card above or below it, as the gaps between cards are.
    private func nestTarget(at location: CGPoint) -> String? {
        guard let dragging, DraggedGroup(dragging) == nil else { return nil }
        return MainActor.assumeIsolated {
            guard let child = model.item(id: dragging) else { return nil }
            for item in column.items {
                guard let frame = frames.frames[item.id], frame.minY <= location.y, location.y <= frame.maxY else { continue }
                let edge = DropOntoIssue.edge(of: frame.height)
                guard location.y > frame.minY + edge, location.y < frame.maxY - edge else { return nil }
                return model.canNest([child], under: item) ? item.id : nil
            }
            return nil
        }
    }

    /// The position among the column's cards, from where the finger is; or the card it would go under.
    private func update(_ info: DropInfo) {
        if let parent = nestTarget(at: info.location) {
            // The gap keeps its place, and its room, while the card is lit: closing it would move the card under the
            // finger away from it.
            var next = target?.columnId == column.id ? target ?? BoardDropTarget(columnId: column.id, slot: 0) : BoardDropTarget(columnId: column.id, slot: 0, gapless: true)
            next.nest = parent
            if next != target { target = next }
            return
        }
        guard fits else {
            if target?.columnId == column.id { target = nil }
            return
        }
        var slot = 0
        for (position, item) in column.items.enumerated() {
            guard let frame = MainActor.assumeIsolated({ frames.frames[item.id] }) else { continue }
            if frame.midY < info.location.y { slot = position + 1 }
        }
        var depth = 0
        var row: Int?
        // An epic's issues land together: among the epic's other issues where the column has some, or as one.
        if let dragging, let lifted = DraggedGroup(dragging) {
            let others = column.items.filter { !lifted.ids.contains($0.id) }
            let landing = column.landing(ofGroup: lifted.epic, moving: lifted.ids, at: column.items.prefix(slot).filter { !lifted.ids.contains($0.id) }.count)
            slot = landing.slot < others.count ? column.items.firstIndex { $0.id == others[landing.slot].id } ?? column.items.count : column.items.count
            row = fullRow(landing.row, shown: column.nesting.rows(without: lifted.ids))
            let next = BoardDropTarget(columnId: column.id, slot: slot, depth: landing.depth, row: row, group: true)
            if next != target { target = next }
            return
        }
        // The gap opens where the card will land: a sub-issue among its parent's sub-issues, any other card never
        // between a parent and its sub-issues, and among an epic's issues or outside them.
        if let dragging, let item = MainActor.assumeIsolated({ model.item(id: dragging) }) {
            let others = column.shown(without: item)
            let kept = Set(others.map(\.id))
            let epic = MainActor.assumeIsolated { model.epic(of: item)?.contentId }
            let landing = column.landing(of: item, at: column.items.prefix(slot).filter { kept.contains($0.id) }.count, epic: epic)
            depth = landing.depth
            if landing.slot < others.count, let next = column.items.firstIndex(where: { $0.id == others[landing.slot].id }) {
                slot = next
            } else {
                slot = column.items.count
            }
            row = fullRow(landing.row, shown: column.rows(without: item))
            // An issue on no board put on the board goes at the end of the column, where the board adds it.
            if !item.isOnBoard {
                let end = column.landing(of: item, at: others.count)
                (slot, depth, row) = (column.items.count, end.depth, fullRow(end.row, shown: column.rows(without: item)))
            }
        }
        let next = BoardDropTarget(columnId: column.id, slot: slot, depth: depth, row: row)
        if next != target { target = next }
    }

    /// Where row `index` of the rows `shown` while something is lifted stands among all of the column's rows: the
    /// landing counts the rows without what is dragged, and the gap goes among all of them.
    private func fullRow(_ index: Int, shown: [Nesting.Row]) -> Int {
        guard shown.indices.contains(index) else { return column.nesting.rows.count }
        return column.nesting.rows.firstIndex { $0.id == shown[index].id } ?? column.nesting.rows.count
    }
}

/// Marks a card being dragged as one of this app's, visible to this app only, and carries which card it is, so a
/// drop moves the card that was dragged, from this window or another. Text dragged in from another app has no mark.
enum CardDragMark {
    static let typeIdentifier = "com.lukaskbl.GitIssues.card"

    /// The card lifted last, in any window: which card a drag carries while it hovers, as its data can only be read
    /// once it's dropped. SwiftUI asks for a card's drag at every lift, but also on a long press that only opens the
    /// menu and once more just after a drop, so a drop never goes by this.
    @MainActor static var lifted: String?

    static func provider(id: String, text: String) -> NSItemProvider {
        let provider = NSItemProvider(object: text as NSString)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
            completion(Data(id.utf8), nil)
            return nil
        }
        return provider
    }

    static func isCard(_ info: DropInfo) -> Bool {
        provider(info) != nil
    }

    /// Reads which card a dropped drag carries, and calls back on the main thread, with nil if it can't be read.
    static func loadId(_ info: DropInfo, then action: @escaping (String?) -> Void) {
        guard let provider = provider(info) else { return action(nil) }
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let id = data.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async { action(id?.isEmpty == false ? id : nil) }
        }
    }

    private static func provider(_ info: DropInfo) -> NSItemProvider? {
        info.itemProviders(for: [.plainText, .url]).first { $0.registeredTypeIdentifiers.contains(typeIdentifier) }
    }
}

/// A card dims a little while pressed, like the rest of the app's plain buttons.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// A column's header: status, name and count, with its menu and "+" for a new issue in it.
private struct MobileColumnHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.colorScheme) private var scheme
    var projectId: String
    var milestone: String? = nil
    var allIssues = false
    var column: BoardColumn

    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            ColumnIcon(column: column, size: 16)
            Text(column.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(column.count)").font(.subheadline).monospacedDigit().foregroundStyle(Theme.textTertiary)
            if let detail = column.detail {
                Text(detail).font(.footnote).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if editsStatuses && column.option != nil || hides {
                Menu {
                    if editsStatuses, let option = column.option {
                        statusItems(option)
                    } else if allIssues {
                        // All Issues puts its columns in an order of its own, on this device.
                        moveItems
                        Divider()
                    }
                    // Hidden here only, for a view's board and All Issues'; one column always stays.
                    if hides {
                        Button {
                            model.setColumn(column.id, hidden: true, in: scope)
                        } label: {
                            Label(.hideColumn, systemImage: "eye.slash")
                        }
                        .disabled(model.shownColumns(for: scope).count <= 1)
                    }
                    if editsStatuses, column.option != nil {
                        Divider()
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label(.deleteStatusEllipsis, systemImage: "trash")
                        }
                        .disabled(statuses.count <= 1)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(.optionsForStatus(status: column.title))
            }
            // A new issue in All Issues goes on the board, so not into the issues on none, and only where you may add one.
            if !allIssues || canEdit && !column.isOnNoBoard {
                Button {
                    // With the column's status or value, and what the view's filter asks for, as on the Mac.
                    let preset = milestone == nil && !allIssues ? model.newIssuePreset(projectId: projectId, column: column.value) : nil
                    // "No status" is a column too: an issue made there gets none, rather than the first status.
                    let statusId = column.option?.id ?? (column.id == BoardColumn.noStatusId ? column.id : nil)
                    navigation.sheet = .newIssue(NewIssueContext(
                        projectId: projectId, inAllIssues: allIssues, statusId: statusId, milestoneTitle: milestone, preset: preset
                    ))
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(.newIssueInStatus(status: column.title))
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 36)
        .alert(.renameStatus, isPresented: $renaming) {
            TextField(.statusNamePlaceholder, text: $name)
            Button(.cancel, role: .cancel) {}
            Button(.rename) {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed != column.title { edit { $0.name = trimmed } }
            }
        }
        .confirmationDialog(Text(.deleteStatusQuestion(name: column.title)), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(.deleteStatus, role: .destructive) { delete() }
        } message: {
            let count = model.issueCount(projectId: projectId, statusId: column.option?.id)
            Text(count == 0
                 ? LocalizedStringResource.statusRemovedFromProject
                 : .statusRemovedIssuesStay(count: count))
        }
    }

    private var canEdit: Bool { model.projects.first { $0.id == projectId }?.viewerCanUpdate == true }

    /// Whether the board's statuses can be changed here: on the board, not in All Issues, which shows them as they are.
    private var editsStatuses: Bool { canEdit && !allIssues }

    private var scope: Scope { MobileBoard.scope(projectId: projectId, milestone: milestone, allIssues: allIssues) }

    /// Whether this board can hide its columns: a view's and All Issues', not a milestone's.
    private var hides: Bool { model.canHideColumns(in: scope) }

    /// Rename, give an icon and colour, and move the status.
    @ViewBuilder private func statusItems(_ option: FieldOption) -> some View {
        Button {
            name = option.name
            renaming = true
        } label: {
            Label(.renameEllipsis, systemImage: "pencil")
        }
        // What the status means, drawn as its circle; kept in iCloud, as GitHub has no icons.
        Menu {
            StatusKindPicker(option: option)
        } label: {
            Label(.statusIcon, systemImage: "circle.dashed")
        }
        Menu {
            Picker(.colour, selection: Binding(
                get: { option.color },
                set: { color in edit { $0.color = color } }
            )) {
                ForEach(Defaults.optionColors, id: \.self) { color in
                    Label {
                        Text(Defaults.colourName(color))
                    } icon: {
                        MenuImages.label(StatusEditor.hex(color), scheme)
                    }
                    .tag(color)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(.colour, systemImage: "paintpalette")
        }
        Divider()
        moveItems
        Divider()
    }

    /// Move Left and Move Right, among the columns the board shows.
    @ViewBuilder private var moveItems: some View {
        let shown = shownStatuses
        Button {
            move(-1)
        } label: {
            Label(.moveLeft, systemImage: "arrow.left")
        }
        .disabled(shown.first == column.id)
        Button {
            move(1)
        } label: {
            Label(.moveRight, systemImage: "arrow.right")
        }
        .disabled(shown.last == column.id)
    }

    private var statuses: [FieldOption] { model.statusOptions(projectId: projectId) }
    private var position: Int { statuses.firstIndex { $0.id == column.id } ?? 0 }

    private func edit(_ change: (inout RemoteOption) -> Void) {
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        change(&options[position])
        model.saveColumns(projectId: projectId, options)
    }

    /// The status columns the board shows, which Move Left and Move Right step through; in All Issues every column.
    private var shownStatuses: [String] {
        let shown = model.shownColumns(for: scope)
        return allIssues ? shown.map(\.id) : shown.compactMap { $0.option?.id }
    }

    private func move(_ delta: Int) {
        let shown = shownStatuses
        guard let index = shown.firstIndex(of: column.id), shown.indices.contains(index + delta) else { return }
        if allIssues {
            model.moveColumn(column.id, among: shown, to: index + delta, allIssuesOf: projectId)
        } else {
            model.moveColumn(column.id, among: shown, to: index + delta, projectId: projectId)
        }
    }

    private func delete() {
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        options.remove(at: position)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }
}
#endif
