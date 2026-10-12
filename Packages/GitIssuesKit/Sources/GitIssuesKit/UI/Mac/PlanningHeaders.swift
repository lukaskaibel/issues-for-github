#if os(macOS)
import SwiftUI

/// The header of a milestone: the board it belongs to, its name, Board and List, and on the right how far it is,
/// when it is due, and completing it.
struct MilestoneHeader: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var title: String

    @State private var dueOpen = false

    var body: some View {
        @Bindable var model = model
        let group = model.milestoneGroup(projectId: projectId, title: title)
        BoardCrumb(projectId: projectId)
        MilestoneIcon(mark: group.map { model.mark(of: $0, projectId: projectId) } ?? .none)
        Text(title).font(.uiSemibold).lineLimit(1)
        ViewModeSwitch(mode: $model.viewMode)
            .padding(.leading, 10)
        Spacer(minLength: 12)
        if let group {
            let progress = model.progress(projectId: projectId, milestone: title)
            if progress.total > 0 {
                HStack(spacing: 8) {
                    Text(.subIssuesProgress(done: progress.done, total: progress.total))
                        .font(.small)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .progressViewStyle(ThinProgressStyle())
                        .frame(width: 64)
                }
                .help(Text(.milestoneProgressTooltip(done: progress.done, total: progress.total)))
                .padding(.trailing, 6)
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
                .frame(height: 24)
                .hoverFill(active: dueOpen)
            }
            .buttonStyle(PlainPressStyle())
            .help(group.due.map { Text(.dueOn(date: $0.longLabel)) } ?? Text(.setMilestoneDueDate))
            .disabled(!group.isOpen)
            .dropdown(isPresented: $dueOpen) { close in
                DueDatePicker(
                    current: [group.due?.string], addsField: false, width: 280,
                    onPick: { model.setDue(group, to: $0) }, onClose: close
                )
            }
            if group.isOpen, isReadyToComplete(group, progress: progress) {
                Button(.completeMilestoneButton) {
                    model.milestoneToComplete = MilestoneRef(projectId: projectId, title: title)
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(Text(.completeMilestoneTooltip))
            }
            MilestoneMenuButton(projectId: projectId, group: group)
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
        Menu {
            MilestoneMenuItems(projectId: projectId, group: group)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(.milestoneOptions))
        .accessibilityLabel(.milestoneOptions)
    }
}

/// What can be done to a milestone, in its header's menu and on its sidebar entry.
struct MilestoneMenuItems: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var group: MilestoneGroup

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

/// The board a milestone or the roadmap belongs to, at the start of its header: a click goes to the board.
struct BoardCrumb: View {
    @Environment(AppModel.self) private var model
    var projectId: String

    var body: some View {
        if let project = model.projects.first(where: { $0.id == projectId }) {
            Button {
                model.select(.project(projectId))
            } label: {
                HStack(spacing: 8) {
                    ProjectSwatch(title: project.title)
                    Text(project.title).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            .buttonStyle(PlainPressStyle())
            .help(Text(.showBoardTooltip(project: project.title)))
            Text("›").foregroundStyle(Theme.textTertiary)
        }
    }
}

/// The roadmap's header: its board, Timeline and List, how much time shows, and a new epic.
struct RoadmapHeader: View {
    @Environment(AppModel.self) private var model
    var projectId: String

    var body: some View {
        @Bindable var model = model
        BoardCrumb(projectId: projectId)
        RoadmapIcon().foregroundStyle(Theme.textSecondary)
        Text(.roadmap).font(.uiSemibold)
        SegmentSwitch(
            options: [(LocalizedStringResource.timeline, RoadmapLayout.timeline), (.list, .list)],
            selection: $model.roadmapLayout
        )
        .padding(.leading, 10)
        Spacer(minLength: 12)
        if model.roadmapLayout == .timeline, !model.roadmap(projectId: projectId).windows.isEmpty {
            SegmentSwitch(
                options: [(LocalizedStringResource.months, RoadmapZoom.months), (.quarters, .quarters)],
                selection: $model.roadmapZoom
            )
        }
        if model.projects.first(where: { $0.id == projectId })?.viewerCanUpdate == true {
            Button {
                model.newIssuePlan = NewIssuePlan(isEpic: true)
                model.overlay = .newIssue(statusId: nil, parentItemId: nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text(.newEpic)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .help(Text(.newEpicTooltip))
        }
    }
}

/// Two or more choices side by side, like Board and List.
struct SegmentSwitch<Value: Hashable>: View {
    var options: [(LocalizedStringResource, Value)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    withAnimation(Theme.spring) { selection = option.1 }
                } label: {
                    Text(option.0)
                        .font(.smallMedium)
                        .foregroundStyle(selection == option.1 ? Theme.text : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            if selection == option.1 {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Theme.segmentActive)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(PlainPressStyle())
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
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
