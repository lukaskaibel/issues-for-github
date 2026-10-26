#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The board on the iPhone: one column at a time across the whole width, and every column with its count in a strip
/// above it, the one on screen raised as in a segmented control. Swipe, or tap the strip, to turn to another column.
/// A lifted card turns the strip into a target for each column: dropped on one, it goes first in that column; held
/// there a moment, the board turns to that column, to place the card among the cards there.
struct PhoneBoard: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var projectId: String

    /// The column on screen.
    @State private var page: String?
    @State private var target: BoardDropTarget?
    @State private var dragging: String?
    /// Whether a lifted card is over the targets, and the column whose target it is over.
    @State private var overTargets = false
    @State private var hot: String?
    /// Whether a lifted card is over the board but neither a column's cards nor the targets: the strip or a column's
    /// header, where a card dragged up quickly may be by the time the drag takes over from the finger.
    @State private var overBoard = false
    /// Whether a card is lifted over the board, which shows the targets.
    @State private var lifting = false
    @State private var dropped = 0
    @State private var turned = 0

    /// The column to open on.
    private var start: String?

    init(projectId: String, page: String?) {
        self.projectId = projectId
        start = page
    }

    /// From the edge of the screen to a column's cards, with the column's own room for their shadows: as far in as
    /// the strip and the lists.
    static let margin: CGFloat = 16 - MobileColumn.inset
    /// The targets cover the strip and the column's header under it.
    static let targetsHeight: CGFloat = 96

    var body: some View {
        let columns = model.shownColumns(for: .project(projectId))
        VStack(spacing: 0) {
            ColumnStrip(columns: columns, page: $page)
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(columns) { column in
                            MobileColumn(
                                projectId: projectId, column: column, width: proxy.size.width - 2 * Self.margin,
                                target: $target, dragging: $dragging,
                                onDrop: { id, slot in land(id, in: column, at: slot) }
                            )
                            .padding(.horizontal, Self.margin)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(column.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
            }
        }
        .onDrop(of: [.plainText, .url], delegate: BoardDrop(over: $overBoard, dragging: $dragging, onEnd: endDrag))
        .overlay(alignment: .top) {
            if lifting {
                let source = source(in: columns)
                GeometryReader { proxy in
                    ColumnTargets(columns: columns, source: source, hot: hot)
                        .onDrop(of: [.plainText, .url], delegate: TargetDrop(
                            model: model, projectId: projectId, columns: columns, source: source, width: proxy.size.width,
                            over: $overTargets, hot: $hot, dragging: $dragging,
                            onDrop: { id, column in land(id, in: column, at: 0) },
                            onEnd: endDrag
                        ))
                }
                .frame(height: Self.targetsHeight)
                .transition(.opacity)
            }
        }
        .background(Theme.board)
        .sensoryFeedback(.impact(weight: .medium), trigger: dropped)
        .sensoryFeedback(.selection, trigger: turned)
        .onChange(of: target != nil || overTargets || overBoard) { _, over in
            if over, !lifting { withAnimation(Theme.quick) { lifting = true } }
        }
        // The drag has ended, or left the board, once it has been over nothing of the board for a moment: going from
        // a column's cards to the targets, one lets go of it a little before the other takes it.
        .task(id: target == nil && !overTargets && !overBoard) {
            guard lifting, target == nil, !overTargets, !overBoard else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, target == nil, !overTargets, !overBoard else { return }
            withAnimation(Theme.quick) { lifting = false }
            hot = nil
        }
        // Held over another column's target, the board turns to that column, as a folder springs open.
        .task(id: hot) {
            guard let column = hot, column != page else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, hot == column else { return }
            turned += 1
            withAnimation(Theme.spring) { page = column }
        }
        // Set once the columns are there: given before, the scroll view showed the first column under another one's
        // name in the strip when a view was switched to.
        .onAppear {
            if page == nil { page = start ?? Self.firstPage(of: columns) }
        }
        .onChange(of: page) { _, id in
            if let id { navigation.boardPages[Self.pageKey(model: model, projectId: projectId)] = id }
        }
        // A column hidden or gone: the board turns to one that is there.
        .onChange(of: columns.map(\.id)) { _, ids in
            if page.map({ !ids.contains($0) }) ?? true { page = Self.firstPage(of: columns) }
        }
    }

    private func land(_ id: String?, in column: BoardColumn, at slot: Int?) {
        endDrag()
        if MobileBoard.land(id, in: column, at: slot, model: model, projectId: projectId, milestone: nil) { dropped += 1 }
    }

    /// After a drop, taken or not: the views that saw the drag hear nothing more of it.
    private func endDrag() {
        target = nil
        dragging = nil
        overTargets = false
        overBoard = false
        hot = nil
        withAnimation(Theme.quick) { lifting = false }
    }

    /// The column the lifted card comes from, which it needn't be dropped on.
    private func source(in columns: [BoardColumn]) -> String? {
        guard let dragging else { return nil }
        let id = DraggedGroup(dragging)?.ids.first ?? dragging
        return columns.first { $0.nesting.members.contains { $0.id == id } }?.id
    }

    /// The board of a project's view and the column it opens on: the one it was left on, else the first column of
    /// work in progress with cards in it.
    static func page(model: AppModel, navigation: MobileNavigation, projectId: String) -> String? {
        let columns = model.shownColumns(for: .project(projectId))
        if let kept = navigation.boardPages[pageKey(model: model, projectId: projectId)], columns.contains(where: { $0.id == kept }) {
            return kept
        }
        return firstPage(of: columns)
    }

    private static func firstPage(of columns: [BoardColumn]) -> String? {
        (columns.first { $0.option?.statusCategory == .started && $0.count > 0 } ?? columns.first { $0.count > 0 } ?? columns.first)?.id
    }

    private static func pageKey(model: AppModel, projectId: String) -> String {
        "\(projectId)\u{1F}\(model.currentView(projectId: projectId)?.id ?? "")"
    }
}

/// The board's columns side by side over the iPhone's board, each with its count, the one on screen raised: a tap
/// turns to another.
private struct ColumnStrip: View {
    var columns: [BoardColumn]
    @Binding var page: String?
    @Namespace private var raised

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(columns) { column in
                        segment(column)
                            .id(column.id)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Theme.control))
                .animation(Theme.spring, value: page)
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.never)
            .onAppear {
                if let page { proxy.scrollTo(page, anchor: .center) }
            }
            .onChange(of: page) { _, id in
                guard let id else { return }
                withAnimation(Theme.spring) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func segment(_ column: BoardColumn) -> some View {
        let selected = column.id == page
        return Button {
            withAnimation(Theme.spring) { page = column.id }
        } label: {
            HStack(spacing: 6) {
                ColumnIcon(column: column, size: 15)
                Text(column.title)
                    .lineLimit(1)
                Text("\(column.count)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.segmentActive)
                        .shadow(color: Theme.cardShadow, radius: 2, y: 1)
                        .matchedGeometryEffect(id: "raised", in: raised)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(.sectionIssueCount(title: column.title, count: column.count))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("strip-\(column.title)")
    }
}

/// While a card is lifted: each column as a target, over the strip and the header of the column on screen. The
/// column the card comes from stays quiet; the one under the finger lights up.
private struct ColumnTargets: View {
    var columns: [BoardColumn]
    var source: String?
    var hot: String?

    static let spacing: CGFloat = 6
    static let padding: CGFloat = 12

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(columns) { column in
                target(column, here: column.id == source, lit: column.id == hot)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.board)
        .animation(Theme.quick, value: hot)
        .accessibilityHidden(true)
    }

    private func target(_ column: BoardColumn, here: Bool, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(spacing: 6) {
            ColumnIcon(column: column, size: 18)
            Text(column.title)
                .font(.caption.weight(lit ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(lit ? Theme.accent : here ? Theme.textTertiary : Theme.textSecondary)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(lit ? Theme.selectionFill : here ? Theme.control : Theme.card))
        .overlay(
            shape.strokeBorder(
                lit ? Theme.accent : Theme.chipBorder,
                style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: lit || here ? [] : [4, 3])
            )
        )
        .opacity(here ? 0.6 : 1)
        .scaleEffect(lit ? 1.05 : 1)
        .accessibilityIdentifier("target-\(column.title)")
    }
}

/// Notices a card lifted over the board outside a column's cards and the targets, which takes no drop itself.
private struct BoardDrop: DropDelegate {
    @Binding var over: Bool
    @Binding var dragging: String?
    var onEnd: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        CardDragMark.isCard(info)
    }

    func dropEntered(info: DropInfo) {
        if dragging == nil { dragging = MainActor.assumeIsolated { CardDragMark.lifted } }
        over = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        over = false
    }

    func performDrop(info: DropInfo) -> Bool {
        onEnd()
        return false
    }
}

/// Takes a card dropped on the targets to the column under the finger, first in it. Which card it is comes from the
/// drag, as on a column.
private struct TargetDrop: DropDelegate {
    var model: AppModel
    var projectId: String
    var columns: [BoardColumn]
    /// The column the card comes from.
    var source: String?
    /// The width of the targets together, to tell which one the finger is over.
    var width: CGFloat
    @Binding var over: Bool
    @Binding var hot: String?
    @Binding var dragging: String?
    var onDrop: (String?, BoardColumn) -> Void
    var onEnd: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        CardDragMark.isCard(info)
    }

    func dropEntered(info: DropInfo) {
        if dragging == nil { dragging = MainActor.assumeIsolated { CardDragMark.lifted } }
        over = true
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: hot == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        over = false
        hot = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let column = destination(info.location)
        onEnd()
        guard CardDragMark.isCard(info), let column else { return false }
        CardDragMark.loadId(info) { id in onDrop(id, column) }
        return true
    }

    private func update(_ info: DropInfo) {
        let next = destination(info.location)?.id
        if next != hot { hot = next }
    }

    /// The column whose target is under the finger, unless the card comes from it or is of another project.
    private func destination(_ location: CGPoint) -> BoardColumn? {
        guard !columns.isEmpty, fits else { return nil }
        let step = (width - 2 * ColumnTargets.padding + ColumnTargets.spacing) / CGFloat(columns.count)
        guard step > 0 else { return nil }
        let index = min(max(Int((location.x - ColumnTargets.padding) / step), 0), columns.count - 1)
        let column = columns[index]
        return column.id == source ? nil : column
    }

    /// A card of another project, dragged in from a window that shows that project, can't land here.
    private var fits: Bool {
        guard let dragging else { return true }
        let id = DraggedGroup(dragging)?.ids.first ?? dragging
        return MainActor.assumeIsolated { model.item(id: id)?.projectId == projectId }
    }
}
#endif
