#if os(macOS)
import SwiftUI

/// The window's toolbar, as in Mail and Notes: back and forward, the title of what is on screen (set by the page),
/// its own buttons in glass, and search. What it holds follows the page: a board or a list, an open issue, the Inbox.
struct MainToolbar: ToolbarContent {
    let model: AppModel
    let openItem: Item?
    @Binding var showsInspector: Bool

    var body: some ToolbarContent {
        BackForwardButtons(model: model)
        if let item = openItem {
            IssueToolbarItems(item: item)
        } else if model.scope == .inbox {
            InboxToolbarItems(model: model)
        } else {
            ScopeToolbarItems(model: model)
        }
        ToolbarSpacer(.fixed)
        SearchToolbarItem()
        if openItem != nil {
            ToolbarItem {
                Button {
                    withAnimation(Theme.spring) { showsInspector.toggle() }
                } label: {
                    Label(String(localized: showsInspector ? .hideInspector : .showInspector), systemImage: "sidebar.right")
                }
                .help(Text(showsInspector ? .hideInspectorTooltip : .showInspectorTooltip))
                .keyboardShortcut("i", modifiers: [.command, .control])
            }
        }
    }
}

/// Back and forward through what you looked at, as in a browser, before the title as in Safari and Finder.
private struct BackForwardButtons: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            // From an open issue, back to where it was opened from, as Escape goes.
            Button {
                if model.openItem != nil { model.leaveIssue() } else { model.goBack() }
            } label: {
                Label(String(localized: .back), systemImage: "chevron.left")
            }
            .disabled(model.openItem == nil && !model.canGoBack)
            .help(Text(model.openItem != nil ? .backWithEscShortcut : .backShortcutTooltip))
            Button {
                model.goForward()
            } label: {
                Label(String(localized: .forward), systemImage: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help(Text(.forwardShortcutTooltip))
        }
    }
}

/// Search, where Notes and Mail have their search field: it opens the command palette, which finds issues and
/// everything there is to do.
struct SearchToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem {
            SearchFieldButton()
        }
    }
}

private struct SearchFieldButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // A plain view: the toolbar draws a button with a label of its own as an icon only.
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            Text(.search).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: "⌘K").font(.small).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(width: 180, height: 34)
        .contentShape(Capsule())
        .onTapGesture(perform: toggle)
        .help(Text(.searchShortcutTooltip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.search))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    private func toggle() {
        model.overlay = model.overlay == .palette(.root) ? nil : .palette(.root)
    }
}

// MARK: - An open issue

/// Over an open issue: the arrows to the issue before and after, its link and branch, and GitHub.
private struct IssueToolbarItems: ToolbarContent {
    let item: Item

    var body: some ToolbarContent {
        ToolbarItem {
            IssueStepper(item: item)
        }
        if item.url != nil {
            ToolbarItem {
                IssueLinkButtons(item: item)
            }
            ToolbarItem {
                OpenOnGitHubButton(item: item)
            }
        }
    }
}

/// "6 / 23" between the arrows to the issue before and after, as Mail steps through messages.
private struct IssueStepper: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        if let position = model.position(of: item) {
            HStack(spacing: 0) {
                ToolbarIconButton(systemImage: "chevron.up", label: .previousIssueWithShortcut) { model.step(-1) }
                Text("\(position.index + 1) / \(position.count)")
                    .font(.small)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                ToolbarIconButton(systemImage: "chevron.down", label: .nextIssueWithShortcut) { model.step(1) }
            }
        }
    }
}

/// The issue's link and its branch name, a click away, as in Linear's issue header.
private struct IssueLinkButtons: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        HStack(spacing: 0) {
            ToolbarIconButton(systemImage: "link", label: .copyLinkWithShortcut) { model.copyLink(item) }
            if item.number != nil {
                ToolbarIconButton(systemImage: "arrow.triangle.branch", label: .copyBranchNameWithShortcut) { model.copyBranchName(item) }
            }
        }
    }
}

private struct OpenOnGitHubButton: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        Button {
            model.openOnGitHub(item)
        } label: {
            HStack(spacing: 5) {
                Text(.openOnGitHub)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(.openOnGitHub))
    }
}

/// An icon button inside a toolbar item that holds several, which the toolbar draws in one piece of glass.
struct ToolbarIconButton: View {
    var systemImage: String
    var label: LocalizedStringResource
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.textBody)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

// MARK: - A board, a list, a milestone, the roadmap

private struct ScopeToolbarItems: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        if showsLayoutSwitch {
            ToolbarItem(placement: .principal) {
                LayoutPicker()
            }
        }
        if let projectId = roadmapProjectId {
            ToolbarItem(placement: .principal) {
                RoadmapLayoutPicker()
            }
            ToolbarItem {
                RoadmapToolbarControls(projectId: projectId)
            }
        }
        if let milestone = milestone {
            ToolbarItem {
                MilestoneToolbarStatus(projectId: milestone.projectId, title: milestone.title)
            }
        }
        if let view = model.currentView {
            ToolbarItem {
                ViewToolbarButtons(view: view)
            }
        }
        if let repo = model.currentRepository, repo.url != nil {
            ToolbarItem {
                RepositoryGitHubButton(repo: repo)
            }
        }
        if showsPriorityField, let project = model.currentProject {
            ToolbarItem {
                Button {
                    model.addPriorityField(projectId: project.id)
                } label: {
                    Text(.addPriorityFieldMac).padding(.horizontal, 10).frame(height: 30).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Text(.addPriorityFieldTooltip))
            }
        }
    }

    /// Board and List, where both can show: a project's view (not a timeline) and a milestone.
    private var showsLayoutSwitch: Bool {
        switch model.scope {
        case .project:
            guard model.currentProjectId != nil else { return false }
            if let view = model.currentView { return view.layout != .roadmap && !model.showsTimeline(view) }
            return true
        case .milestone:
            return true
        default:
            return false
        }
    }

    private var roadmapProjectId: String? {
        if case .roadmap(let projectId) = model.scope { return projectId }
        return nil
    }

    private var milestone: MilestoneRef? {
        if case .milestone(let projectId, let title) = model.scope { return MilestoneRef(projectId: projectId, title: title) }
        return nil
    }

    private var showsPriorityField: Bool {
        guard case .project = model.scope, let project = model.currentProject else { return false }
        return project.priorityFieldId == nil && project.viewerCanUpdate && project.lastSyncedAt != nil
    }
}

/// Board or List, as a segmented control in the middle of the toolbar (⌘1, ⌘2).
private struct LayoutPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker(selection: Binding(
            get: { model.viewMode },
            set: { mode in withAnimation(Theme.spring) { model.viewMode = mode } }
        )) {
            Label { Text(.board) } icon: { Image(systemName: "rectangle.split.3x1") }.tag(ViewMode.board)
            Label { Text(.list) } icon: { Image(systemName: "list.bullet") }.tag(ViewMode.list)
        } label: {
            Text(.layout)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .fixedSize()
    }
}

/// The roadmap's Timeline and List.
private struct RoadmapLayoutPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker(selection: Binding(
            get: { model.roadmapLayout },
            set: { layout in withAnimation(Theme.spring) { model.roadmapLayout = layout } }
        )) {
            Text(.timeline).tag(RoadmapLayout.timeline)
            Text(.list).tag(RoadmapLayout.list)
        } label: {
            Text(.layout)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// How much time the roadmap shows, and a new epic.
private struct RoadmapToolbarControls: View {
    @Environment(AppModel.self) private var model
    let projectId: String

    var body: some View {
        HStack(spacing: 6) {
            if model.roadmapLayout == .timeline, !model.roadmap(projectId: projectId).windows.isEmpty {
                Picker(selection: Binding(
                    get: { model.roadmapZoom },
                    set: { zoom in withAnimation(Theme.spring) { model.roadmapZoom = zoom } }
                )) {
                    Text(.months).tag(RoadmapZoom.months)
                    Text(.quarters).tag(RoadmapZoom.quarters)
                } label: {
                    Text(.months)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if model.projects.first(where: { $0.id == projectId })?.viewerCanUpdate == true {
                Button {
                    model.newIssuePlan = NewIssuePlan(isEpic: true)
                    model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text(.newEpic)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Text(.newEpicTooltip))
            }
        }
    }
}

/// A view's filter (F) and how it is displayed (⇧V), side by side in one piece of glass.
private struct ViewToolbarButtons: View {
    let view: ProjectView

    var body: some View {
        HStack(spacing: 0) {
            HeaderFilterButton(view: view)
            DisplayButton(view: view)
        }
    }
}

private struct RepositoryGitHubButton: View {
    let repo: RepoRef

    var body: some View {
        Button {
            if let url = repo.url { Platform.open(url) }
        } label: {
            HStack(spacing: 5) {
                Text(.openOnGitHub)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(.openRepositoryOnGitHubTooltip(repository: repo.nameWithOwner)))
    }
}
#endif
