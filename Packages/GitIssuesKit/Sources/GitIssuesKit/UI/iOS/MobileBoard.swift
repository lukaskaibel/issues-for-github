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

    @State private var target: BoardDropTarget?
    /// The card a drag hovering this board carries, which may have been lifted in another window: it dims, and a
    /// card of another project finds no place here. A drop reads its card from the drag instead.
    @State private var dragging: String?
    @State private var dropped = 0
    @State private var addingStatus = false
    @State private var newStatus = ""

    var body: some View {
        let columns = model.shownColumns(for: milestone.map { .milestone(projectId: projectId, title: $0) } ?? .project(projectId))
        let canEdit = model.projects.first { $0.id == projectId }?.viewerCanUpdate == true
        let hidden = milestone == nil ? model.hiddenColumns(projectId: projectId) : []
        // A milestone's board shows the board's columns; they are changed on the board itself.
        let addsStatus = canEdit && milestone == nil && columns.allSatisfy { $0.value == nil }
        GeometryReader { proxy in
            let width = columnWidth(available: proxy.size.width, count: columns.count, trailing: addsStatus || !hidden.isEmpty)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { column in
                        MobileColumn(
                            projectId: projectId, milestone: milestone, column: column, width: width,
                            target: $target, dragging: $dragging,
                            onDrop: { id, slot in move(id, to: column, at: slot) }
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
                            if !hidden.isEmpty, let view = model.currentView(projectId: projectId) {
                                MobileHiddenColumns(columns: hidden, view: view)
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
        .background(Theme.panel)
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

    private func columnWidth(available: CGFloat, count: Int, trailing: Bool) -> CGFloat {
        guard count > 0 else { return 290 }
        let extra: CGFloat = trailing ? 184 : 0
        let fitted = (available - 36 - extra - CGFloat(count - 1) * 14) / CGFloat(count)
        return min(max(fitted, 268), 330)
    }

    /// Lands a card at `slot` among all of the column's cards, itself included, or at the end without one. An
    /// epic's issues lifted by their header land there together.
    private func move(_ id: String?, to column: BoardColumn, at slot: Int?) {
        target = nil
        dragging = nil
        if let id, let lifted = DraggedGroup(id) {
            let members = model.columns(projectId: projectId).flatMap(\.nesting.members).filter { lifted.ids.contains($0.id) }
            guard let group = lifted.group(model: model, projectId: projectId, milestone: milestone), !members.isEmpty else { return }
            let index = column.items.prefix(slot ?? column.items.count).filter { !lifted.ids.contains($0.id) }.count
            dropped += 1
            withAnimation(Theme.spring) { model.drop(group, members: members, in: column, at: index) }
            return
        }
        guard let id, let item = model.item(id: id), item.projectId == projectId else { return }
        // The model counts the place among the column's other cards, without the sub-issues the card brings along.
        let others = Set(column.shown(without: item).map(\.id))
        let index = column.items.prefix(slot ?? column.items.count).filter { others.contains($0.id) }.count
        dropped += 1
        withAnimation(Theme.spring) { model.drop(item, in: column, at: index) }
    }
}

/// The columns you hid on the board, after its last column: each with its count, shown again with a tap.
private struct MobileHiddenColumns: View {
    @Environment(AppModel.self) private var model
    var columns: [BoardColumn]
    var view: ProjectView

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(.hiddenColumns)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            ForEach(columns) { column in
                Button {
                    model.setColumn(column.id, hidden: false, of: view)
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
    func group(model: AppModel, projectId: String, milestone: String?) -> Nesting.EpicGroup? {
        let columns = milestone.map { model.columns(for: .milestone(projectId: projectId, title: $0)) } ?? model.columns(projectId: projectId)
        return (columns.first { $0.id == columnId }?.nesting.groups ?? columns.flatMap(\.nesting.groups))
            .first { $0.contentId == epic }
    }
}

/// Card frames inside a column, read while dropping. Kept outside view state so scrolling never redraws.
@MainActor
final class CardFrames {
    var frames: [String: CGRect] = [:]
}

private struct MobileColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    var projectId: String
    var milestone: String? = nil
    var column: BoardColumn
    var width: CGFloat
    @Binding var target: BoardDropTarget?
    @Binding var dragging: String?
    var onDrop: (String?, Int?) -> Void

    @State private var frames = CardFrames()
    @State private var foldFeedback = 0

    var body: some View {
        let space = "column-\(column.id)"
        VStack(spacing: 6) {
            MobileColumnHeader(projectId: projectId, milestone: milestone, column: column)
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
                .padding(.bottom, 80)
                .animation(Theme.spring, value: target)
                .animation(Theme.spring, value: column.nesting.rows.map(\.id))
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(.named(space))
            .frame(maxHeight: .infinity)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous))
            .accessibilityIdentifier("column-\(column.title)")
            .sensoryFeedback(.selection, trigger: foldFeedback)
            .onDrop(of: [.plainText, .url], delegate: ColumnDrop(
                model: model, projectId: projectId, column: column, frames: frames,
                target: $target, dragging: $dragging, onDrop: onDrop
            ))
        }
        // Each column stands in a soft lane, as Reminders sets its columns apart, with the cards inset in it.
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.lane))
    }

    /// The cards' width inside the lane.
    private var inner: CGFloat { width - 16 }

    /// Where the gap shows among all of the column's rows, the dragged card included.
    private var gapPosition: Int? {
        guard let target, target.columnId == column.id else { return nil }
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
                if place.depth > 0 { CardTreeLines(place: place, gap: 8, branchY: 21) }
            }
    }

    private func card(_ item: Item, space: String, width: CGFloat) -> some View {
        Button {
            openRoute(.issue(item.id))
        } label: {
            CardView(card: model.cardModel(for: item, in: column.nesting, showsMilestone: milestone == nil), width: width, avatarVersion: model.avatarVersion)
                .equatable()
        }
        .buttonStyle(CardPressStyle())
        .accessibilityIdentifier("card-\(item.displayNumber)")
        .hoverEffect(.lift)
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

    /// What a card is outside the app: its link on GitHub, or its number and title.
    private func dragText(_ item: Item) -> String {
        item.url ?? "\(item.displayNumber) \(item.title)"
    }

    /// For VoiceOver, which can't drag: moves the card to the neighbouring column.
    private func step(_ item: Item, by delta: Int) {
        guard let next = neighbour(delta) else { return }
        withAnimation(Theme.spring) { model.drop(item, in: next, at: next.items.count) }
    }

    /// For VoiceOver: moves an epic's issues here to the neighbouring column.
    private func step(_ group: Nesting.EpicGroup, by delta: Int) {
        guard let next = neighbour(delta) else { return }
        let members = column.members(of: group)
        withAnimation(Theme.spring) { model.drop(group, members: members, in: next, at: next.items.count) }
    }

    private func neighbour(_ delta: Int) -> BoardColumn? {
        let columns = milestone.map { model.columns(for: .milestone(projectId: projectId, title: $0)) } ?? model.columns(projectId: projectId)
        guard let index = columns.firstIndex(where: { $0.id == column.id }), columns.indices.contains(index + delta) else { return nil }
        return columns[index + delta]
    }
}

/// Lands cards dropped on a column at the place the finger points to. Which card it is comes from the drag, which
/// may have started in another window.
private struct ColumnDrop: DropDelegate {
    var model: AppModel
    var projectId: String
    var column: BoardColumn
    var frames: CardFrames
    @Binding var target: BoardDropTarget?
    @Binding var dragging: String?
    var onDrop: (String?, Int?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        CardDragMark.isCard(info)
    }

    func dropEntered(info: DropInfo) {
        dragging = MainActor.assumeIsolated { CardDragMark.lifted }
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: fits ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        if target?.columnId == column.id { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard CardDragMark.isCard(info) else { return false }
        let slot = target?.columnId == column.id ? target?.slot : nil
        CardDragMark.loadId(info) { id in onDrop(id, slot) }
        return true
    }

    /// A card of another project, dragged in from a window that shows that project, can't land here.
    private var fits: Bool {
        guard let dragging else { return true }
        let id = DraggedGroup(dragging)?.ids.first ?? dragging
        return MainActor.assumeIsolated { model.item(id: id)?.projectId == projectId }
    }

    /// The position among the column's cards, from where the finger is.
    private func update(_ info: DropInfo) {
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
private enum CardDragMark {
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
            if canEdit && column.option != nil || hidingView != nil {
                Menu {
                    if canEdit, let option = column.option {
                        statusItems(option)
                    }
                    // Hidden here only, for a view's board; one column always stays.
                    if let view = hidingView {
                        Button {
                            model.setColumn(column.id, hidden: true, of: view)
                        } label: {
                            Label(.hideColumn, systemImage: "eye.slash")
                        }
                        .disabled(model.shownColumns(for: .project(projectId)).count <= 1)
                    }
                    if canEdit, column.option != nil {
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
            Button {
                navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, statusId: column.option?.id, milestoneTitle: milestone))
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
            Text(column.count == 0
                 ? LocalizedStringResource.statusRemovedFromProject
                 : .statusRemovedIssuesStay(count: column.count))
        }
    }

    private var canEdit: Bool { model.projects.first { $0.id == projectId }?.viewerCanUpdate == true }

    /// The view whose board can hide this column: the open one, but not on a milestone's board.
    private var hidingView: ProjectView? {
        milestone == nil ? model.currentView(projectId: projectId) : nil
    }

    /// Rename, colour and move the status.
    @ViewBuilder private func statusItems(_ option: FieldOption) -> some View {
        Button {
            name = option.name
            renaming = true
        } label: {
            Label(.renameEllipsis, systemImage: "pencil")
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
        Divider()
    }

    private var statuses: [FieldOption] { model.statusOptions(projectId: projectId) }
    private var position: Int { statuses.firstIndex { $0.id == column.id } ?? 0 }

    private func edit(_ change: (inout RemoteOption) -> Void) {
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        change(&options[position])
        model.saveColumns(projectId: projectId, options)
    }

    /// The status columns the board shows, which Move Left and Move Right step through.
    private var shownStatuses: [String] {
        model.shownColumns(for: milestone.map { .milestone(projectId: projectId, title: $0) } ?? .project(projectId)).compactMap { $0.option?.id }
    }

    private func move(_ delta: Int) {
        let shown = shownStatuses
        guard let index = shown.firstIndex(of: column.id), shown.indices.contains(index + delta) else { return }
        model.moveColumn(column.id, among: shown, to: index + delta, projectId: projectId)
    }

    private func delete() {
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        options.remove(at: position)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }
}
#endif
