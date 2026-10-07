#if os(macOS)
import SwiftUI

struct IssueListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sections.isEmpty {
            EmptyState(title: emptyTitle, message: emptyMessage)
        } else {
            // Where rows come from several boards, each says which; an issue on none says its repository.
            let showsProject = model.scope == .myIssues
                || model.currentRepositoryId.map { model.boards(ofRepository: $0).count > 1 } ?? false
            let canAdd = model.currentProjectId != nil
            IssueTable(
                sections: model.sections.map { section in
                    IssueSectionModel(
                        id: section.id, collapsed: model.isSectionCollapsed(section.id),
                        title: section.title, glyph: section.glyph, optionId: section.option?.id,
                        canAdd: canAdd, count: section.items.count,
                        rows: model.isSectionCollapsed(section.id) ? [] : section.items.map { item in
                            IssueRowModel(
                                item: item, glyph: model.glyph(of: item), priority: model.priorityLevel(of: item),
                                showsPriority: model.project(of: item)?.priorityFieldId != nil,
                                showsStatus: !item.isOnBoard || model.project(of: item)?.statusFieldId != nil,
                                projectTitle: showsProject ? model.project(of: item)?.title ?? (model.scope == .myIssues ? item.repoShortName : nil) : nil,
                                due: model.dueBadge(for: item),
                                selected: model.isSelected(item.id),
                                selecting: !model.selectedIds.isEmpty
                            )
                        }
                    )
                },
                focusedId: model.focusedItemId,
                focusScrollToken: model.focusScrollToken,
                avatarVersion: model.avatarVersion
            )
            // A different project starts at the top again.
            .id(model.scope)
            .padding(.top, 6)
            .task(id: model.scope) { await model.preloadAvatars() }
        }
    }

    private var emptyTitle: String {
        if model.scope == .myIssues { return "Nothing assigned to you" }
        if model.currentRepositoryId != nil { return model.isLoadingRepository ? "Looking for issues…" : "No open issues" }
        return "No issues yet"
    }

    private var emptyMessage: String {
        if model.scope == .myIssues { return "Open issues assigned to you show up here, on a board or not." }
        if model.currentRepositoryId != nil { return "Press C to create one. Issues closed in the last four weeks show up here too." }
        return "Press C to create the first one. Only issues that are in this GitHub Project appear here."
    }
}
#endif
