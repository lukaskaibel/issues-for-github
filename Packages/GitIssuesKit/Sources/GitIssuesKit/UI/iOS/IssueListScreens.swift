#if os(iOS)
import SwiftUI

// MARK: - My Issues

struct MyIssuesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide

    var body: some View {
        IssueList(scope: .myIssues)
            .navigationTitle("My Issues")
            .navigationSubtitle(SyncSubtitle.text(model))
            .toolbar {
                if !wide {
                    ToolbarItem(placement: .topBarLeading) { AccountButton() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            navigation.sheet = .arrangeSections(.myIssues)
                        } label: {
                            Label("Arrange Sections…", systemImage: "arrow.up.arrow.down")
                        }
                        Divider()
                        Button {
                            model.refresh()
                        } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis")
                    }
                    NewIssueButton(context: NewIssueContext(assignToMe: true))
                }
            }
            .task(id: model.dataVersion) { await model.preloadAvatars(for: .myIssues) }
    }
}

// MARK: - Projects

/// The Projects tab on the iPhone: every project, the one used last opened on top of it.
struct ProjectsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let open = model.openProjects
        let closed = model.projects.filter(\.closed)
        Group {
            if model.projects.isEmpty {
                MobileEmptyState(
                    title: model.status.phase == .offline ? "You're offline" : "Looking for your projects…",
                    message: "Boards come from GitHub Projects. If you have none yet, create one on GitHub and it will show up here.",
                    systemImage: "square.stack",
                    showsProgress: model.status.phase != .offline
                )
            } else {
                List {
                    Section {
                        ForEach(open) { project in
                            NavigationLink(value: Route.project(project.id)) {
                                ProjectRow(project: project)
                            }
                        }
                    }
                    if !closed.isEmpty {
                        Section("Closed") {
                            ForEach(closed) { project in
                                NavigationLink(value: Route.project(project.id)) {
                                    ProjectRow(project: project)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.window)
                .refreshable { await model.refreshAndWait() }
            }
        }
        .navigationTitle("Projects")
        .navigationSubtitle(SyncSubtitle.text(model))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { AccountButton() }
            ToolbarItem(placement: .primaryAction) { NewIssueButton(context: NewIssueContext()) }
        }
    }
}

private struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    var project: Project

    var body: some View {
        let items = model.items(in: .project(project.id))
        let open = items.filter { !(model.statusOption(of: $0)?.statusCategory.isClosed ?? $0.isClosed) }.count
        HStack(spacing: 12) {
            ProjectSwatch(title: project.title, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(project.lastSyncedAt == nil ? project.ownerLogin : "\(project.ownerLogin) · \(open) open")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One project: its list, or on a wide iPad also its board.
struct ProjectScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    @Environment(\.windowWidth) private var windowWidth
    var projectId: String

    var body: some View {
        let project = model.projects.first { $0.id == projectId }
        Group {
            if project == nil {
                MobileEmptyState(title: "This project is gone", message: "It was closed, deleted, or you no longer have access to it on GitHub.", systemImage: "questionmark.square.dashed")
            } else if model.isLoading(projectId: projectId) {
                ProjectLoading()
            } else if wide, model.viewMode == .board {
                MobileBoard(projectId: projectId)
            } else {
                IssueList(scope: .project(projectId))
            }
        }
        .background(Theme.panel)
        .navigationTitle(project?.title ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProjectSwitcher(projectId: projectId, regular: wide))
        .toolbar {
            // A window narrower than this has the tab bar floating in the middle of the bar, next to the header.
            let roomy = windowWidth >= 950
            if wide, let project {
                // The Mac's header: the project's swatch and name, then Board and List.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        ProjectSwatch(title: project.title, size: 14)
                        Text(project.title)
                            .font(.headline)
                            .lineLimit(1)
                        if roomy {
                            Picker("View", selection: Bindable(model).viewMode) {
                                // Named for VoiceOver and the pointer, which would otherwise read the symbols' own names.
                                Image(systemName: "rectangle.split.3x1").accessibilityLabel("Board").help("Board").tag(ViewMode.board)
                                Image(systemName: "list.bullet").accessibilityLabel("List").help("List").tag(ViewMode.list)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            .padding(.leading, 8)
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let project {
                    ProjectOptionsMenu(project: project, showsViewMode: wide && !roomy)
                }
                NewIssueButton(context: NewIssueContext(projectId: projectId))
            }
        }
        .onAppear {
            model.setActiveProject(projectId)
            navigation.rememberProject(projectId)
        }
        .task(id: model.dataVersion) { await model.preloadAvatars(for: .project(projectId)) }
    }
}

/// On the iPhone the title switches to another project. A wide iPad lists the projects in its sidebar, so there
/// the header sits on the leading edge with the Board and List switch beside it, as on the Mac.
private struct ProjectSwitcher: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var projectId: String
    var regular: Bool

    func body(content: Content) -> some View {
        if regular {
            content.toolbarRole(.editor)
        } else {
            content.toolbarTitleMenu {
                ForEach(model.openProjects) { other in
                    Button {
                        navigation.showProject(other.id, regular: false)
                    } label: {
                        if other.id == projectId {
                            Label(other.title, systemImage: "checkmark")
                        } else {
                            Text(other.title)
                        }
                    }
                }
            }
        }
    }
}

/// Shown until a project has been fetched from GitHub once; afterwards the local copy shows at once.
private struct ProjectLoading: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.status.phase {
        case .offline:
            MobileEmptyState(title: "You're offline", message: "This project loads as soon as you're back online.", systemImage: "wifi.slash")
        case .failed(let message):
            MobileEmptyState(title: "This project couldn't be loaded", message: message, systemImage: "exclamationmark.triangle") {
                Button("Try Again") { model.refresh() }
                    .buttonStyle(.bordered)
            }
        default:
            MobileEmptyState(title: "Loading issues…", message: "Fetching this project from GitHub.", showsProgress: true)
        }
    }
}

/// The "…" menu of a project.
private struct ProjectOptionsMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    var project: Project
    /// Board and List, when the bar has no room for them beside the project's name.
    var showsViewMode = false

    var body: some View {
        Menu {
            if showsViewMode {
                Picker("View", selection: Bindable(model).viewMode) {
                    Label("Board", systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                    Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.inline)
                Divider()
            }
            Button {
                navigation.sheet = .arrangeSections(.project(project.id))
            } label: {
                Label("Arrange Sections…", systemImage: "arrow.up.arrow.down")
            }
            if project.viewerCanUpdate, project.statusFieldId != nil {
                Button {
                    openRoute(.statuses(project.id))
                } label: {
                    Label("Edit Statuses…", systemImage: "circle.dashed")
                }
            }
            if project.priorityFieldId == nil, project.viewerCanUpdate {
                Button {
                    model.addPriorityField(projectId: project.id)
                } label: {
                    Label("Add Priority Field", systemImage: "chart.bar.fill")
                }
            }
            Divider()
            Button {
                model.refresh()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            if let url = URL(string: project.url), !project.url.isEmpty {
                Button {
                    Platform.open(url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                }
            }
        } label: {
            Label("Options", systemImage: "ellipsis")
        }
    }
}

// MARK: - The list

/// Issues grouped by status, with sections that fold, headers that stay pinned while their section scrolls,
/// swipe actions and the issue menu on a long press.
struct IssueList: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    var scope: Scope
    @State private var doneFeedback = 0
    @State private var foldFeedback = 0

    var body: some View {
        let sections = model.sections(for: scope)
        Group {
            if sections.isEmpty {
                emptyState
            } else {
                List {
                    if case .project(let id) = scope, let project = model.projects.first(where: { $0.id == id }),
                       project.priorityFieldId == nil, project.viewerCanUpdate, project.lastSyncedAt != nil {
                        PriorityFieldBanner(projectId: id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    ForEach(sections) { section in
                        let folded = model.isSectionCollapsed(section.id, in: scope)
                        Section {
                            if !folded {
                                ForEach(section.items) { item in
                                    row(item)
                                }
                            }
                        } header: {
                            SectionHeaderBand(
                                title: section.title, glyph: section.glyph, count: section.items.count, folded: folded,
                                onToggle: {
                                    foldFeedback += 1
                                    withAnimation(Theme.spring) { model.toggleSection(section.id, in: scope) }
                                },
                                onAdd: addAction(for: section)
                            )
                            .listRowInsets(EdgeInsets())
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListHeaderHeight, 0)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.panel)
        .refreshable { await model.refreshAndWait() }
        .sensoryFeedback(.success, trigger: doneFeedback)
        .sensoryFeedback(.selection, trigger: foldFeedback)
    }

    private func row(_ item: Item) -> some View {
        Button {
            openRoute(.issue(item.id))
        } label: {
            IssueRow(item: item, showsProject: scope == .myIssues)
        }
        .buttonStyle(RowButtonStyle())
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.panel)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if model.canToggleDone(item) {
                let done = model.isDone(item)
                Button {
                    doneFeedback += 1
                    withAnimation(Theme.spring) { model.toggleDone(item) }
                } label: {
                    Label(done ? "Reopen" : "Done", systemImage: done ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Theme.accentFill)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.canDelete(item) {
                Button {
                    model.requestDelete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
            if item.kind != .draft, let viewer = model.viewer {
                let mine = item.assignees.contains { $0.id == viewer.id }
                Button {
                    model.toggleAssignee(item, viewer.person)
                } label: {
                    Label(mine ? "Unassign" : "Assign", systemImage: mine ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                }
                .tint(Color(white: 0.45))
            }
        }
        .contextMenu {
            ItemMenuContent(item: item) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
    }

    private func addAction(for section: ListSection) -> (() -> Void)? {
        guard case .project(let projectId) = scope else { return nil }
        return {
            navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, statusId: section.option?.id))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch scope {
        case .inbox:
            EmptyView()
        case .myIssues:
            MobileEmptyState(
                title: "Nothing assigned to you",
                message: "Issues assigned to you on any of your project boards show up here.",
                systemImage: "scope"
            )
        case .project(let projectId):
            MobileEmptyState(
                title: "No issues yet",
                message: "Only issues that are in this GitHub Project appear here.",
                systemImage: "tray"
            ) {
                Button("New Issue") {
                    navigation.sheet = .newIssue(NewIssueContext(projectId: projectId))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// For a project without a Priority field: one tap adds it with Urgent, High, Medium and Low.
private struct PriorityFieldBanner: View {
    @Environment(AppModel.self) private var model
    var projectId: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("No Priority field").font(.subheadline.weight(.semibold))
                Text("Add one with Urgent, High, Medium and Low to sort by importance.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button("Add") { model.addPriorityField(projectId: projectId) }
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.groupHeader))
    }
}

// MARK: - Toolbar buttons

/// Opens the account and settings sheet; shows the avatar.
struct AccountButton: View {
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.sheet = .account
        } label: {
            AccountAvatar(size: 30)
        }
        .accessibilityLabel("Account and settings")
        .accessibilityIdentifier("account-button")
    }
}

struct NewIssueButton: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var context: NewIssueContext

    var body: some View {
        Button {
            navigation.sheet = .newIssue(context)
        } label: {
            Label("New Issue", systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("compose-button")
        .disabled(model.openProjects.isEmpty)
    }
}

/// The line under a large title: how syncing is going.
@MainActor
enum SyncSubtitle {
    static func text(_ model: AppModel) -> String {
        model.syncLine()
    }
}
#endif
