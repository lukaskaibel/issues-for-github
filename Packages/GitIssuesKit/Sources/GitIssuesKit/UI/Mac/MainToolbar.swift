#if os(macOS)
import SwiftUI

/// The window's toolbar, as in Mail and Notes: back and forward, the title of what is on screen (set by the page),
/// its own buttons in glass, and search. What it holds follows the page: a board or a list, an open issue, the Inbox.
/// It has the same items on every page and only their contents change, so moving around adds or removes no item,
/// which the toolbar would animate each time.
struct MainToolbar: ToolbarContent {
    let model: AppModel
    let openItem: Item?
    @Binding var showsInspector: Bool

    var body: some ToolbarContent {
        BackForwardButtons(model: model)
        ToolbarItem(placement: .principal) {
            PrincipalControl(openItem: openItem)
        }
        .sharedBackgroundVisibility(model.hasPrincipalControl(openItem: openItem) ? .automatic : .hidden)
        ToolbarItem {
            PageControls(openItem: openItem, showsInspector: $showsInspector)
        }
        .sharedBackgroundVisibility(model.hasPageControls(openItem: openItem) ? .automatic : .hidden)
        ToolbarSpacer(.fixed)
        ToolbarItem {
            SearchButton()
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

/// In the middle: Board and List, the roadmap's Timeline and List, or the Inbox's For You and Watching.
private struct PrincipalControl: View {
    @Environment(AppModel.self) private var model
    let openItem: Item?

    var body: some View {
        // In one container: the toolbar names an item after a picker it holds directly, and a new name is a new item.
        HStack(spacing: 0) {
            if openItem == nil, model.scope == .inbox, model.showsInboxBuckets {
                InboxBuckets()
            } else if openItem == nil, model.showsLayoutSwitch {
                LayoutPicker()
            } else if openItem == nil, model.roadmapScopeProjectId != nil {
                RoadmapLayoutPicker()
            }
        }
    }
}

/// The page's own buttons, in one piece of glass: an issue's arrows, link and GitHub; what to do with a
/// notification; the filter and display of a view or My Issues; a milestone's progress and date; the roadmap's zoom.
private struct PageControls: View {
    @Environment(AppModel.self) private var model
    let openItem: Item?
    @Binding var showsInspector: Bool

    var body: some View {
        HStack(spacing: 0) {
            if let item = openItem {
                IssueStepper(item: item)
                if item.url != nil {
                    IssueLinkButtons(item: item)
                    OpenOnGitHubButton(item: item)
                }
                ToolbarIconButton(
                    systemImage: "sidebar.right", label: showsInspector ? .hideInspector : .showInspector,
                    help: showsInspector ? .hideInspectorTooltip : .showInspectorTooltip
                ) {
                    withAnimation(Theme.spring) { showsInspector.toggle() }
                }
                .keyboardShortcut("i", modifiers: [.command, .control])
            } else if model.scope == .inbox {
                InboxToolbarControls()
            } else {
                if let projectId = model.roadmapScopeProjectId {
                    RoadmapToolbarControls(projectId: projectId)
                }
                if let milestone = model.milestoneScope {
                    MilestoneToolbarStatus(projectId: milestone.projectId, title: milestone.title)
                }
                if let view = model.currentView {
                    ViewToolbarButtons(view: view)
                }
                if model.scope == .myIssues {
                    MyIssuesToolbarButtons()
                }
                if model.showsPriorityFieldButton, let project = model.currentProject {
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
        .fixedSize()
    }
}

/// Search, where Mail has it: a magnifying glass that opens the command palette, which finds issues and everything
/// there is to do. Typing happens there, so the toolbar has no field of its own.
private struct SearchButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ToolbarIconButton(systemImage: "magnifyingglass", label: .search, help: .searchShortcutTooltip) {
            model.overlay = model.overlay == .palette(.root) ? nil : .palette(.root)
        }
    }
}

/// What the toolbar shows for the page on screen.
extension AppModel {
    /// Board and List, where both can show: a project's view (not a timeline) and a milestone.
    fileprivate var showsLayoutSwitch: Bool {
        switch scope {
        case .project:
            guard currentProjectId != nil else { return false }
            if let view = currentView { return view.layout != .roadmap && !showsTimeline(view) }
            return true
        case .milestone:
            return true
        default:
            return false
        }
    }

    fileprivate var roadmapScopeProjectId: String? {
        if case .roadmap(let projectId) = scope { return projectId }
        return nil
    }

    fileprivate var milestoneScope: MilestoneRef? {
        if case .milestone(let projectId, let title) = scope { return MilestoneRef(projectId: projectId, title: title) }
        return nil
    }

    fileprivate var showsPriorityFieldButton: Bool {
        guard case .project = scope, let project = currentProject else { return false }
        return project.priorityFieldId == nil && project.viewerCanUpdate && project.lastSyncedAt != nil
    }

    fileprivate func hasPrincipalControl(openItem: Item?) -> Bool {
        guard openItem == nil else { return false }
        if scope == .inbox { return showsInboxBuckets }
        return showsLayoutSwitch || roadmapScopeProjectId != nil
    }

    fileprivate func hasPageControls(openItem: Item?) -> Bool {
        if openItem != nil || scope == .inbox { return true }
        return roadmapScopeProjectId != nil || milestoneScope != nil || currentView != nil || scope == .myIssues
            || showsPriorityFieldButton
    }
}

// MARK: - An open issue

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
    /// The tooltip, when it says more than the label, such as the shortcut.
    var help: LocalizedStringResource?
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
        .help(Text(help ?? label))
        .accessibilityLabel(Text(label))
    }
}

// MARK: - A board, a list, a milestone, the roadmap

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
                TimelineZoomButtons()
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
    @Environment(AppModel.self) private var model
    let view: ProjectView

    var body: some View {
        HStack(spacing: 0) {
            if model.showsTimeline(view) { TimelineZoomButtons() }
            HeaderFilterButton(
                filter: Binding(get: { model.filter(of: view) }, set: { model.setFilter($0, of: view) }),
                scope: .project(view.projectId)
            )
            DisplayButton(changed: model.displayDiffers(view)) { close in
                DisplayOptions(view: view, close: close)
            }
        }
    }
}

/// My Issues' filter and display, as a view has them.
private struct MyIssuesToolbarButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            HeaderFilterButton(filter: Binding(get: { model.mineFilter }, set: { model.setMineFilter($0) }), scope: .myIssues)
            DisplayButton(changed: !model.mineDisplay.isDefault) { close in
                MyIssuesDisplayOptions(close: close)
            }
        }
    }
}
#endif
