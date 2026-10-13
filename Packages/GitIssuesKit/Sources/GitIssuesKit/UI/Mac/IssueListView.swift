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
            let canEdit = model.scopeProjectId.flatMap { id in model.projects.first { $0.id == id } }?.viewerCanUpdate == true
            let canAdd = model.scopeProjectId != nil && (model.currentProjectId != nil || canEdit)
            // A milestone's list doesn't repeat its milestone on every row, nor the roadmap an epic's.
            let showsMilestone: Bool = switch model.scope {
            case .milestone, .roadmap: false
            default: true
            }
            IssueTable(
                sections: model.sections.map { section in
                    IssueSectionModel(
                        id: section.id, collapsed: model.isSectionCollapsed(section.id),
                        title: section.title, glyph: section.glyph, icon: icon(of: section), detail: section.detail,
                        optionId: section.option?.id, kind: section.kind,
                        canAdd: canAdd, count: section.count,
                        lines: model.isSectionCollapsed(section.id) ? [] : section.nesting.rows.map { row -> IssueLine in
                            switch row {
                            case .epic(let group):
                                return .epic(group)
                            case .item(let item):
                                return .row(IssueRowModel(
                                    item: item, glyph: model.glyph(of: item), priority: model.priorityLevel(of: item),
                                    showsPriority: model.project(of: item)?.priorityFieldId != nil,
                                    showsStatus: !item.isOnBoard || model.project(of: item)?.statusFieldId != nil,
                                    projectTitle: showsProject ? model.project(of: item)?.title ?? (model.scope == .myIssues ? item.repoShortName : nil) : nil,
                                    due: model.dueBadge(for: item),
                                    selected: model.isSelected(item.id),
                                    selecting: !model.selectedIds.isEmpty,
                                    nest: section.nesting.place(of: item.id),
                                    nested: section.nesting.nestedCounts[item.id],
                                    folded: section.nesting.folded.contains(item.id),
                                    // Under its parent or its epic's header, the parent goes without saying.
                                    showsParent: section.nesting.namesParent(of: item) && section.kind != .epic(contentId: item.parentId),
                                    parentIsEpic: item.parentId.flatMap { model.issue(contentId: $0) }?.isEpic ?? false,
                                    milestone: showsMilestone ? model.milestoneTitle(of: item) : spanOnRoadmap(item),
                                    milestoneMark: model.milestoneMark(of: item)
                                ))
                            }
                        }
                    )
                },
                // My Issues mixes projects, so there is no one order to put an issue into.
                canMoveRows: canEdit,
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

    /// On the roadmap, an epic that runs over several milestones says how far: "0.3 → 0.4".
    private func spanOnRoadmap(_ item: Item) -> String? {
        guard case .roadmap = model.scope, let span = model.milestoneSpan(of: item), span.contains("→") else { return nil }
        return span
    }

    private func icon(of section: ListSection) -> IssueSectionModel.Icon {
        model.sectionIcon(section, projectId: model.scopeProjectId)
    }

    private var emptyTitle: String {
        if case .milestone(_, let title) = model.scope { return String(localized: .milestoneEmptyTitle(milestone: title)) }
        if model.scope == .myIssues { return String(localized: .nothingAssignedTitle) }
        if model.currentRepositoryId != nil { return String(localized: model.isLoadingRepository ? .lookingForIssues : .noOpenIssues) }
        return String(localized: .noIssuesYet)
    }

    private var emptyMessage: String {
        if case .milestone = model.scope { return String(localized: .milestoneEmptyMessage) }
        if model.scope == .myIssues { return String(localized: .myIssuesEmptyMessage) }
        if model.currentRepositoryId != nil { return String(localized: .repositoryEmptyMessage) }
        return String(localized: .projectEmptyMessage)
    }
}
#endif
