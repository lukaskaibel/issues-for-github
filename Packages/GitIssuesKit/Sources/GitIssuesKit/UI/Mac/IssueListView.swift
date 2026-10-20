#if os(macOS)
import SwiftUI

struct IssueListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sections.isEmpty {
            if model.scope == .myIssues, !model.mineFilter.isEmpty, !model.assignedItems.isEmpty {
                // The filter hides everything; one click shows it all again.
                EmptyState(title: String(localized: .nothingMatchesFilterTitle), message: String(localized: .nothingMatchesFilterMessage)) {
                    Button(.clearFilter) { model.setMineFilter(ProjectFilter("")) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                EmptyState(title: emptyTitle, message: emptyMessage)
            }
        } else {
            // Where rows come from several boards, each says which; an issue on none says its repository. My Issues
            // grouped by project says it in the groups.
            let showsProject = model.scope == .myIssues
                || model.currentRepositoryId.map { model.boards(ofRepository: $0).count > 1 } ?? false
            let groupsByProject = model.scope == .myIssues && model.mineDisplay.grouping == .project
            let canEdit = model.scopeProjectId.flatMap { id in model.projects.first { $0.id == id } }?.viewerCanUpdate == true
            let canAdd = model.scopeProjectId != nil && (model.currentProjectId != nil || canEdit)
            // A milestone's list doesn't repeat its milestone on every row, nor the roadmap an epic's.
            let showsMilestone: Bool = switch model.scope {
            case .milestone, .roadmap: false
            default: !model.groupsByMilestone && !model.viewPinsMilestone(projectId: model.currentProjectId)
            }
            // The person with the most open issues sets how long the load bars are.
            let mostOpen = model.sections.filter { $0.style == .people }.compactMap { $0.progress.map { $0.total - $0.done } }.max() ?? 0
            IssueTable(
                sections: model.sections.map { section in
                    IssueSectionModel(
                        id: section.id, collapsed: model.isFolded(section),
                        title: section.title, glyph: section.glyph, icon: icon(of: section), detail: section.detail,
                        optionId: section.option?.id, kind: section.kind,
                        canAdd: canAdd, count: section.count,
                        lines: model.isFolded(section) ? [] : section.nesting.rows.map { row -> IssueLine in
                            switch row {
                            case .epic(let group):
                                return .epic(group)
                            case .item(let item):
                                return .row(IssueRowModel(
                                    item: item, glyph: model.glyph(of: item), priority: model.priorityLevel(of: item),
                                    showsPriority: model.project(of: item)?.priorityFieldId != nil,
                                    showsStatus: !item.isOnBoard || model.project(of: item)?.statusFieldId != nil,
                                    projectTitle: showsProject ? place(of: item, groupsByProject: groupsByProject) : nil,
                                    due: model.dueBadge(for: item),
                                    blocker: model.blockerMark(for: item),
                                    selected: model.isSelected(item.id),
                                    selecting: !model.selectedIds.isEmpty,
                                    nest: section.nesting.place(of: item.id),
                                    nested: section.nesting.nestedCounts[item.id],
                                    folded: section.nesting.folded.contains(item.id),
                                    // Under its parent or its epic's header, the parent goes without saying.
                                    showsParent: section.nesting.namesParent(of: item) && section.kind != .epic(contentId: item.parentId)
                                        && section.kind != .group(.parent(contentId: item.parentId)),
                                    parentIsEpic: item.parentId.flatMap { model.issue(contentId: $0) }?.isEpic ?? false,
                                    milestone: showsMilestone ? model.milestoneTitle(of: item) : spanOnRoadmap(item),
                                    milestoneMark: model.milestoneMark(of: item),
                                    chips: model.fieldChips(of: item, in: model.scope)
                                ))
                            }
                        },
                        style: section.style, progress: section.progress,
                        load: mostOpen > 0 ? CGFloat(section.progress.map { $0.total - $0.done } ?? 0) / CGFloat(mostOpen) : 0
                    )
                },
                // My Issues mixes projects, so there is no one order to put an issue into.
                canMoveRows: canEdit,
                focusedId: model.focusedItemId,
                focusScrollToken: model.focusScrollToken,
                avatarVersion: model.avatarVersion,
                // Grouped otherwise, My Issues starts at the top again too.
                listKey: "\(model.scope) \(model.currentView?.id ?? "") \(model.scope == .myIssues ? model.mineDisplay.grouping.rawValue : "")"
            )
            // A different project starts at the top again.
            .id(model.scope)
            .padding(.top, 6)
            .task(id: model.scope) { await model.preloadAvatars() }
        }
    }

    /// Which board a row is on, or for an issue on none in My Issues, its repository.
    private func place(of item: Item, groupsByProject: Bool) -> String? {
        if let project = model.project(of: item) { return groupsByProject ? nil : project.title }
        return model.scope == .myIssues ? item.repoShortName : nil
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
