#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// My Issues as an overview, on the board's grey: a card per project with a page for each column of its board, and
/// Needs you (see `OverviewGrid`). A right-click beside the cards arranges them; on a card, it shows its project or
/// takes the card out.
struct MyIssuesOverview: View {
    @Environment(AppModel.self) private var model
    @State private var drag = OverviewDrag()

    var body: some View {
        if model.overviewCards.isEmpty {
            emptyState
        } else {
            OverviewGrid(metrics: .standard)
                .environment(drag)
                // A click beside the issues lets the picked ones go, as in the list; a right-click arranges the cards.
                .contentShape(Rectangle())
                .onTapGesture { model.clearSelection() }
                .glassContextMenu { [model] in OverviewMenus.background(model) }
                .task(id: model.scope) { await model.preloadAvatars() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.mineFilter.isEmpty, !model.myItems.isEmpty {
            // The filter hides everything; one click shows it all again.
            EmptyState(title: String(localized: .nothingMatchesFilterTitle), message: String(localized: .nothingMatchesFilterMessage)) {
                Button(.clearFilter) { model.setMineFilter(ProjectFilter("")) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else if model.isLoadingMyIssues {
            MyIssuesLoadingState()
        } else {
            EmptyState(title: String(localized: .nothingAssignedTitle), message: String(localized: .myIssuesEmptyMessage))
        }
    }
}

/// An issue being dragged out of a card: a page's icon of the same project knows from it, before the drop, whether it
/// can take the issue.
@Observable
final class OverviewDrag {
    var itemId: String?
}

// MARK: - Menus

@MainActor
enum OverviewMenus {
    /// A card's menu: its project, and taking it out.
    static func card(_ id: String, model: AppModel) -> NSMenu {
        let menu = MenuBuilder()
        if let projectId = model.lane(id)?.projectId {
            menu.item(.showBoard, "rectangle.split.3x1") { model.select(.project(projectId)) }
            menu.divider()
        }
        menu.item(.arrangeAutomatically, "sparkles", checked: model.mineArrangement.automatic) {
            withAnimation(Theme.spring) { model.setArrangesAutomatically(!model.mineArrangement.automatic) }
        }
        menu.divider()
        menu.item(.removeFromMyIssues, "minus.circle", destructive: true) {
            withAnimation(Theme.spring) { model.removeCard(id) }
        }
        return menu.build()
    }

    /// The menu beside the cards: arranging them by themselves, and what can be added back.
    static func background(_ model: AppModel) -> NSMenu {
        let menu = MenuBuilder()
        menu.item(.arrangeAutomatically, "sparkles", checked: model.mineArrangement.automatic) {
            withAnimation(Theme.spring) { model.setArrangesAutomatically(!model.mineArrangement.automatic) }
        }
        let addable = model.addableCards
        if !addable.isEmpty {
            menu.divider()
            for id in addable {
                menu.item(String(localized: .addToMyIssues(name: model.cardTitle(id))), "plus.circle") {
                    withAnimation(Theme.spring) { model.addCard(id) }
                }
            }
        }
        return menu.build()
    }
}

/// A right-click on a card.
struct OverviewCardMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let id: String

    func body(content: Content) -> some View {
        content.glassContextMenu { [model, id] in OverviewMenus.card(id, model: model) }
    }
}

// MARK: - Issues

/// An issue on a card's page, with everything an issue does in the overview.
struct OverviewRow: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let page: OverviewPage

    var body: some View {
        OverviewRowLabel(item: item, page: page, selected: model.isSelected(item.id))
            .frame(maxHeight: .infinity)
            .modifier(OverviewIssueInteractions(item: item))
    }
}

/// What every issue in the overview does: the pointer and the keyboard focus light it up, a click opens it (⌘ and
/// Shift pick), a right-click has its menu, and it can be dragged onto another column's icon of its card, or onto
/// another issue to go under it.
private struct OverviewIssueInteractions: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(OverviewDrag.self) private var drag
    let item: Item
    @State private var hovering = false
    /// Whether issues dragged onto this one would go under it if dropped now.
    @State private var targeted = false

    func body(content: Content) -> some View {
        let selected = model.isSelected(item.id)
        let focused = model.focusedItemId == item.id
        content
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.accentFill : hovering || focused ? Theme.cardRowHover : .clear)
                    .padding(.vertical, 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(targeted ? Theme.selectionBorder : .clear, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(targeted ? Theme.selectionBorder.opacity(0.14) : .clear))
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            )
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], delegate: IssueDrop(target: item, model: model, drag: drag, targeted: $targeted))
            .id(item.id)
            .onHover { inside in
                hovering = inside
                model.pointer(inside ? .entered : .left, item.id)
            }
            .onTapGesture {
                if model.handleSelectionClick(on: item) { return }
                model.openFromClick(item)
            }
            .onDrag {
                drag.itemId = item.id
                return NSItemProvider(object: item.id as NSString)
            }
            .glassContextMenu { [model, item] in ItemMenuBuilder(model: model, item: item).menu() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.open(item) }
    }
}

/// A page's icon takes an issue of its project dragged onto it: the issue moves to that column, as if picked from its
/// status menu.
struct OverviewPageDrop: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(OverviewDrag.self) private var drag
    let cardId: String
    let pageKey: String
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(targeted ? Theme.selectionBorder : .clear, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(targeted ? Theme.selectionFill : .clear))
                    .allowsHitTesting(false)
            )
            .onDrop(of: [.plainText], delegate: PageDrop(target: target, model: model, drag: drag, targeted: $targeted))
    }

    /// The column, its project, and the issue being dragged, while it can go there.
    private var target: (item: Item, status: FieldOption)? {
        guard let id = drag.itemId, let lane = model.lane(cardId), let projectId = lane.projectId,
              let column = lane.columns.first(where: { $0.key == pageKey }),
              let status = model.status(of: column, projectId: projectId),
              let item = model.allItems.first(where: { $0.id == id }), item.projectId == projectId,
              item.statusId != status.id, model.project(of: item)?.viewerCanUpdate == true else { return nil }
        return (item, status)
    }
}

/// An issue takes the issues dragged onto it as its sub-issues: the one dragged, or all picked with it.
private struct IssueDrop: DropDelegate {
    let target: Item
    let model: AppModel
    let drag: OverviewDrag
    @Binding var targeted: Bool

    private var dragged: [Item]? {
        guard let id = drag.itemId, let item = model.allItems.first(where: { $0.id == id }) else { return nil }
        return model.targets(for: item)
    }

    private var canDrop: Bool {
        dragged.map { model.canNest($0, under: target) } ?? false
    }

    func validateDrop(info: DropInfo) -> Bool { canDrop }

    func dropEntered(info: DropInfo) {
        withAnimation(Theme.quick) { targeted = canDrop }
    }

    func dropExited(info: DropInfo) {
        withAnimation(Theme.quick) { targeted = false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: targeted ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        defer { drag.itemId = nil }
        guard let dragged else { return false }
        withAnimation(Theme.spring) { model.nest(dragged, under: target) }
        return true
    }
}

private struct PageDrop: DropDelegate {
    let target: (item: Item, status: FieldOption)?
    let model: AppModel
    let drag: OverviewDrag
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool { target != nil }

    func dropEntered(info: DropInfo) {
        withAnimation(Theme.quick) { targeted = target != nil }
    }

    func dropExited(info: DropInfo) {
        withAnimation(Theme.quick) { targeted = false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: target != nil ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        defer { drag.itemId = nil }
        guard let target else { return false }
        withAnimation(Theme.spring) { model.setStatus(target.item, to: target.status) }
        return true
    }
}
#endif
