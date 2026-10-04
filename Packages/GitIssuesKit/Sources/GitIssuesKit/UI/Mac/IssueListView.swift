#if os(macOS)
import SwiftUI

struct IssueListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sections.isEmpty {
            EmptyState(title: emptyTitle, message: emptyMessage)
        } else {
            let showsProject = model.scope == .myIssues
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
                                showsStatus: model.project(of: item)?.statusFieldId != nil,
                                projectTitle: showsProject ? model.project(of: item)?.title : nil
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
        return "No issues yet"
    }

    private var emptyMessage: String {
        if model.scope == .myIssues { return "Issues assigned to you on any of your project boards show up here." }
        return "Press C to create the first one. Only issues that are in this GitHub Project appear here."
    }
}
#endif
