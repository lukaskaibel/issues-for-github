#if os(macOS)
import SwiftUI

/// A board's roadmap: its epics on a timeline over its milestones, or as a list by milestone.
struct RoadmapView: View {
    @Environment(AppModel.self) private var model
    var projectId: String

    var body: some View {
        let roadmap = model.roadmap(projectId: projectId)
        if roadmap.rows.isEmpty, roadmap.later.isEmpty {
            EmptyState(title: String(localized: .roadmapEmptyTitle), message: String(localized: .roadmapEmptyMessage)) {
                if model.projects.first(where: { $0.id == projectId })?.viewerCanUpdate == true {
                    HStack(spacing: 8) {
                        Button(.newMilestoneEllipsis) {
                            model.overlay = .milestoneEditor(projectId: projectId, title: nil, assigning: [])
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button(.newEpic) {
                            model.newIssuePlan = NewIssuePlan(isEpic: true)
                            model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        } else if model.roadmapLayout == .list {
            IssueListView()
                .transition(.opacity)
        } else {
            RoadmapTimeline(projectId: projectId) { model.open($0) }
                .transition(.opacity)
        }
    }
}
#endif
