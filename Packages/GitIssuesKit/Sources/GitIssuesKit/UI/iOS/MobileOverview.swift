#if os(iOS)
import SwiftUI

// MARK: - The overview

/// My Issues as an overview on iPhone and iPad, on the board's grey: the same cards as on the Mac (see
/// `OverviewGrid`), three or two to a row on iPad, one under another on iPhone, each paging sideways through the
/// columns of its board. My Issues' filter stands above them as a line of chips; pulling down syncs.
struct MobileOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// An issue dragged onto another one's row, to go under it as its sub-issue.
    @State private var drag = ListDrag()

    var body: some View {
        OverviewGrid(metrics: sizeClass == .compact ? .compact : .regular, header: filter)
            .background(Theme.board)
            .refreshable { await model.refreshAndWait() }
            .environment(drag)
            .sensoryFeedback(.selection, trigger: drag.lit)
            .sensoryFeedback(.impact(weight: .medium), trigger: drag.landed)
    }

    private var filter: AnyView? {
        guard !model.mineFilter.isEmpty else { return nil }
        // My Issues' filter as a line of chips under the title, like a view's; a tap changes it.
        return AnyView(
            FilterChipStrip(filter: model.mineFilter, scope: .myIssues, identifier: "my-issues-filter") {
                navigation.sheet = .myIssuesFilter
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 6)
        )
    }
}

/// An issue on a card's page: a tap opens it, a long press has its menu with a preview. Touched and held, then
/// dragged over another issue, it goes under that one as its sub-issue.
struct OverviewRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    @Environment(ListDrag.self) private var drag: ListDrag?
    let item: Item
    let page: OverviewPage

    var body: some View {
        Button {
            openRoute(.issue(item.id))
        } label: {
            OverviewRowLabel(item: item, page: page)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .modifier(OverviewRowDropping(drag: drag, item: item, page: page))
        .padding(.horizontal, -8)
        .contextMenu {
            ItemMenuContent(item: item, foldable: false) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
        .accessibilityIdentifier("row-\(item.displayNumber)")
    }
}

/// An overview row dragged, and dropped onto: only to go under another issue, as the overview has no order of its own.
private struct OverviewRowDropping: ViewModifier {
    @Environment(AppModel.self) private var model
    var drag: ListDrag?
    var item: Item
    var page: OverviewPage

    func body(content: Content) -> some View {
        if let drag {
            content
                .modifier(ListRowDropMark(drag: drag, sectionId: page.id, rowId: item.id, indent: 8))
                .modifier(RowDragging(token: item.id, text: DropOntoIssue.text(item)))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { drag.heights[item.id] = $0 }
                .onDrop(of: [.plainText, .url], delegate: ListRowDrop(
                    model: model, drag: drag, sectionId: page.id, rowId: item.id, item: item, placesIn: nil,
                    nests: item.projectId.map { id in model.projects.first { $0.id == id }?.viewerCanUpdate == true } ?? true,
                    onDrop: { id, target in
                        drag.target = nil
                        drag.dragging = nil
                        if target.place == .into, DropOntoIssue.nest(id, under: target.rowId, shown: Nesting(), model: model) { drag.landed += 1 }
                    }
                ))
        } else {
            content
        }
    }
}

/// A long press on a card: its project, and taking the card out.
struct OverviewCardMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    let id: String

    func body(content: Content) -> some View {
        content
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu {
                if let projectId = model.lane(id)?.projectId {
                    Button {
                        openRoute(.project(projectId))
                    } label: {
                        Label(.showBoard, systemImage: "rectangle.split.3x1")
                    }
                }
                Button(role: .destructive) {
                    withAnimation(Theme.spring) { model.removeCard(id) }
                } label: {
                    Label(.removeFromMyIssues, systemImage: "minus.circle")
                }
            }
    }
}

/// Issues are moved to another column from their menu on iPhone and iPad; a page's icon takes no drops.
struct OverviewPageDrop: ViewModifier {
    let cardId: String
    let pageKey: String

    func body(content: Content) -> some View { content }
}

// MARK: - Customize

/// Arranging the overview on iPhone and iPad, as Home's widgets are listed in iOS: whether it arranges itself, then
/// the cards shown, to move or take out, then those that can be added back.
struct CustomizeMyIssuesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cards = model.overviewCards
        let addable = model.addableCards
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { model.mineArrangement.automatic },
                        set: { automatic in withAnimation(Theme.spring) { model.setArrangesAutomatically(automatic) } }
                    )) {
                        Text(.arrangeAutomatically)
                    }
                    .accessibilityIdentifier("arrange-automatically")
                } footer: {
                    Text(.arrangeAutomaticallyFooter)
                }
                Section {
                    ForEach(cards, id: \.self) { id in
                        HStack(spacing: 12) {
                            CustomizeIcon(id: id)
                            Text(model.cardTitle(id)).lineLimit(1)
                        }
                    }
                    .onMove { from, to in
                        guard let index = from.first else { return }
                        let id = cards[index]
                        // `to` counts the card itself where it stood.
                        let target = to > index ? to - 1 : to
                        withAnimation(Theme.spring) { model.moveCard(id, toShownIndex: target) }
                    }
                    .onDelete { offsets in
                        for index in offsets { withAnimation(Theme.spring) { model.removeCard(cards[index]) } }
                    }
                } header: {
                    Text(.widgetsShown)
                }
                if !addable.isEmpty {
                    Section {
                        ForEach(addable, id: \.self) { id in
                            Button {
                                withAnimation(Theme.spring) { model.addCard(id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .green)
                                    CustomizeIcon(id: id)
                                    Text(model.cardTitle(id)).foregroundStyle(Theme.text)
                                }
                            }
                            .accessibilityLabel(Text(.addToMyIssues(name: model.cardTitle(id))))
                        }
                    } header: {
                        Text(.widgetsNotShown)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(.customizeMyIssues)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A card's icon in the Customize sheet.
private struct CustomizeIcon: View {
    let id: String

    var body: some View {
        Group {
            if MineSmartCard(id: id) == .needsYou {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.urgent)
            } else if id.hasPrefix("project/") {
                ProjectIcon(projectId: String(id.dropFirst(8)), size: 20)
            } else {
                StatusIcon(glyph: .noProject, size: 20)
            }
        }
        .frame(width: 28, height: 28)
    }
}
#endif
