import SwiftUI

/// "Complete 5.3.2?": what isn't done can move to the next milestone or stay, as Linear asks when a release ends.
struct CompleteMilestoneAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let pending = model.milestoneToComplete
        let group = pending.flatMap { model.milestoneGroup(projectId: $0.projectId, title: $0.title) }
        let next = pending.flatMap { ref in group.flatMap { model.milestone(after: $0, projectId: ref.projectId) } }
        let open = pending.map { model.unfinished(projectId: $0.projectId, milestone: $0.title).count } ?? 0
        content.alert(
            Text(.completeMilestoneQuestion(milestone: pending?.title ?? "")),
            isPresented: Binding(
                get: { model.milestoneToComplete != nil },
                set: { if !$0 { model.milestoneToComplete = nil } }
            ),
            presenting: pending
        ) { ref in
            if let group {
                if open > 0, let next {
                    Button(.moveUnfinishedTo(milestone: next.title)) {
                        model.completeMilestone(group, projectId: ref.projectId, moveTo: next)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(.leaveThemInMilestone(milestone: group.title)) {
                        model.completeMilestone(group, projectId: ref.projectId, moveTo: nil)
                    }
                } else {
                    Button(.completeMilestoneButton) {
                        model.completeMilestone(group, projectId: ref.projectId, moveTo: nil)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            Button(.cancel, role: .cancel) { model.milestoneToComplete = nil }
        } message: { ref in
            if open > 0 {
                Text(.milestoneUnfinishedMessage(count: open))
            } else {
                Text(.milestoneAllDoneMessage)
            }
        }
    }
}
