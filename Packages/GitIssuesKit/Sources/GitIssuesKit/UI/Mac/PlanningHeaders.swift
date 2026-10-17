#if os(macOS)
import SwiftUI

/// In the toolbar over a milestone: how far it is, when it is due, completing it, and its menu. Its name is the
/// window's title and Board and List sit in the middle, as for a view.
struct MilestoneToolbarStatus: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var title: String

    @State private var dueOpen = false

    var body: some View {
        if let group = model.milestoneGroup(projectId: projectId, title: title) {
            HStack(spacing: 4) {
                let progress = model.progress(projectId: projectId, milestone: title)
                if progress.total > 0 {
                    HStack(spacing: 8) {
                        Text(.subIssuesProgress(done: progress.done, total: progress.total))
                            .font(.small)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .progressViewStyle(ThinProgressStyle())
                            .frame(width: 56)
                    }
                    .help(Text(.milestoneProgressTooltip(done: progress.done, total: progress.total)))
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                }
                Button {
                    dueOpen = true
                } label: {
                    HStack(spacing: 6) {
                        let tone = dueTone(group)
                        DueDateIcon(tone: tone, size: 11)
                        (group.due.map { Text($0.shortLabel()) } ?? Text(.addDueDate))
                            .foregroundStyle(group.due == nil ? Theme.textTertiary : tone == .overdue || tone == .today ? tone.color : Theme.textBody)
                    }
                    .font(.small)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(group.due.map { Text(.dueOn(date: $0.longLabel)) } ?? Text(.setMilestoneDueDate))
                .disabled(!group.isOpen)
                .dropdown(isPresented: $dueOpen) { close in
                    DueDatePicker(
                        current: [group.due?.string], addsField: false, width: 280,
                        onPick: { model.setDue(group, to: $0) }, onClose: close
                    )
                }
                if group.isOpen, isReadyToComplete(group, progress: progress) {
                    Button {
                        model.milestoneToComplete = MilestoneRef(projectId: projectId, title: title)
                    } label: {
                        Text(.completeMilestoneButton).font(.small).padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(.completeMilestoneTooltip))
                }
                MilestoneMenuButton(projectId: projectId, group: group)
            }
            // The toolbar proposes less than the item needs on first layout, which wraps "0 / 2" onto two lines.
            .fixedSize()
        }
    }

    private func dueTone(_ group: MilestoneGroup) -> DueTone {
        guard group.isOpen else { return .settled }
        guard let due = group.due else { return .upcoming }
        let today = CalendarDay.today()
        return due < today ? .overdue : due == today ? .today : .upcoming
    }

    /// When the day has come or everything in it is done, as Linear offers to complete a release.
    private func isReadyToComplete(_ group: MilestoneGroup, progress: Roadmap.Count) -> Bool {
        if progress.total > 0, progress.done == progress.total { return true }
        guard let due = group.due else { return false }
        return due <= CalendarDay.today()
    }
}

/// The "…" of a milestone: change it, complete or reopen it, its link.
struct MilestoneMenuButton: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var group: MilestoneGroup

    var body: some View {
        GlassMenuButton(label: .milestoneOptions) {
            MilestoneMenuItems.menu(projectId: projectId, group: group, model: model)
        }
    }
}

/// What can be done to a milestone, in its header's menu and on its sidebar entry.
struct MilestoneMenuItems: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var group: MilestoneGroup

    /// The same, as a menu in glass.
    @MainActor
    static func menu(projectId: String, group: MilestoneGroup, model: AppModel) -> NSMenu {
        let menu = MenuBuilder()
        menu.item(.editMilestoneEllipsis, "pencil") {
            model.overlay = .milestoneEditor(projectId: projectId, title: group.title, assigning: [])
        }
        if group.isOpen {
            menu.item(.completeMilestoneEllipsis, "checkmark.circle") {
                model.milestoneToComplete = MilestoneRef(projectId: projectId, title: group.title)
            }
        } else {
            menu.item(.reopenMilestone, "arrow.uturn.backward.circle") { model.reopenMilestone(group) }
        }
        if let url = group.url {
            menu.divider()
            menu.item(.copyLink, "link") { model.copyLink(url, for: group.title) }
            menu.item(.openOnGitHub, "arrow.up.right.square") {
                if let parsed = URL(string: url) { Platform.open(parsed) }
            }
        }
        return menu.build()
    }

    var body: some View {
        Button(.editMilestoneEllipsis, systemImage: "pencil") {
            model.overlay = .milestoneEditor(projectId: projectId, title: group.title, assigning: [])
        }
        if group.isOpen {
            Button(.completeMilestoneEllipsis, systemImage: "checkmark.circle") {
                model.milestoneToComplete = MilestoneRef(projectId: projectId, title: group.title)
            }
        } else {
            Button(.reopenMilestone, systemImage: "arrow.uturn.backward.circle") { model.reopenMilestone(group) }
        }
        if let url = group.url {
            Divider()
            Button(.copyLink, systemImage: "link") { model.copyLink(url, for: group.title) }
            Button(.openOnGitHub, systemImage: "arrow.up.right.square") {
                if let parsed = URL(string: url) { Platform.open(parsed) }
            }
        }
    }
}

/// Under a milestone's header: what it is about, from its description. A click changes it.
struct MilestoneSummary: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var group: MilestoneGroup

    var body: some View {
        let text = group.descr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Button {
                model.overlay = .milestoneEditor(projectId: projectId, title: group.title, assigning: [])
            } label: {
                Text(text)
                    .font(.small)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .help(Text(.editMilestoneEllipsis))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.panelBorder).frame(height: 1)
            }
        }
    }
}
#endif
