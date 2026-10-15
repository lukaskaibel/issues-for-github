#if os(iOS)
import SwiftUI

// MARK: - My Issues

struct MyIssuesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide

    var body: some View {
        IssueList(scope: .myIssues)
            .navigationTitle(.myIssues)
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
                            Label(.arrangeSectionsMenu, systemImage: "arrow.up.arrow.down")
                        }
                        Divider()
                        Button {
                            model.refresh()
                        } label: {
                            Label(.syncNow, systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Label(.options, systemImage: "ellipsis")
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
                    title: model.status.phase == .offline ? String(localized: .youreOffline) : String(localized: .lookingForProjects),
                    message: String(localized: .noProjectsMessage),
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
                            // Its next milestones and its roadmap right under it, as in the iPad's sidebar.
                            if model.hasPlanning(projectId: project.id) {
                                ForEach(model.sidebarMilestones(projectId: project.id)) { group in
                                    NavigationLink(value: Route.milestone(projectId: project.id, title: group.title)) {
                                        MilestoneListRow(projectId: project.id, group: group)
                                    }
                                }
                                NavigationLink(value: Route.roadmap(project.id)) {
                                    HStack(spacing: 12) {
                                        RoadmapIcon(size: 16).foregroundStyle(Theme.textSecondary).frame(width: 18)
                                        Text(.roadmap).foregroundStyle(Theme.text)
                                    }
                                    .padding(.leading, 30)
                                    .accessibilityElement(children: .combine)
                                }
                                .accessibilityIdentifier("roadmap-\(project.title)")
                            }
                        }
                    }
                    let repos = model.boardRepositories
                    if !repos.isEmpty {
                        // Like the teams in Linear: every issue of a repository, whether it is on a board or not.
                        Section(.repositories) {
                            ForEach(repos) { repo in
                                NavigationLink(value: Route.repository(repo.id)) {
                                    RepositoryRow(repo: repo)
                                }
                            }
                        }
                    }
                    if !closed.isEmpty {
                        Section(.closedProjects) {
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
        .navigationTitle(.projects)
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
        let items = model.allItems.filter { $0.projectId == project.id && !$0.isEpic }
        let open = items.filter { !(model.statusOption(of: $0)?.statusCategory.isClosed ?? $0.isClosed) }.count
        HStack(spacing: 12) {
            ProjectSwatch(title: project.title, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(project.lastSyncedAt == nil ? project.ownerLogin : String(localized: .ownerOpenIssueCount(owner: project.ownerLogin, count: open)))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A milestone under its board in the Projects tab: its diamond, its name and when it is due.
private struct MilestoneListRow: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var group: MilestoneGroup

    var body: some View {
        let today = CalendarDay.today()
        HStack(spacing: 12) {
            MilestoneIcon(mark: model.mark(of: group, projectId: projectId), size: 15)
                .frame(width: 18)
            Text(group.title).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let due = group.due {
                Text(due.shortLabel(today: today))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(due < today ? Theme.overdue : Theme.textSecondary)
            }
        }
        .padding(.leading, 30)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("milestone-\(group.title)")
    }
}

private struct RepositoryRow: View {
    @Environment(AppModel.self) private var model
    var repo: RepoRef

    var body: some View {
        let open = model.items(in: .repository(repo.id)).filter { !model.isDone($0) }.count
        HStack(spacing: 12) {
            RepositoryIcon(size: 15)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.shortName).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(.ownerOpenIssueCount(owner: String(repo.nameWithOwner.dropLast(repo.shortName.count + 1)), count: open))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Every issue of a repository, on a board or not, as a list grouped like My Issues.
struct RepositoryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    var repoId: String

    var body: some View {
        let repo = model.repository(id: repoId)
        Group {
            if repo == nil {
                MobileEmptyState(title: String(localized: .repositoryGoneTitle), message: String(localized: .repositoryGoneMessage), systemImage: "questionmark.square.dashed")
            } else {
                IssueList(scope: .repository(repoId))
            }
        }
        .background(Theme.panel)
        .navigationTitle(repo.map { model.displayName(of: $0) } ?? String(localized: .repository))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(EditorRole(active: wide))
        .toolbar {
            if wide, let repo {
                // As a project's header on a wide iPad: on the leading edge, the owner before the name.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        RepositoryIcon(size: 13).foregroundStyle(Theme.textSecondary)
                        let owner = Text(repo.nameWithOwner.dropLast(repo.shortName.count)).foregroundStyle(Theme.textSecondary)
                        Text("\(owner)\(Text(repo.shortName).foregroundStyle(Theme.text))")
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        navigation.sheet = .arrangeSections(.repository(repoId))
                    } label: {
                        Label(.arrangeSectionsMenu, systemImage: "arrow.up.arrow.down")
                    }
                    Divider()
                    Button {
                        model.refresh()
                    } label: {
                        Label(.syncNow, systemImage: "arrow.triangle.2.circlepath")
                    }
                    if let url = repo?.url {
                        Button {
                            Platform.open(url)
                        } label: {
                            Label(.openOnGitHub, systemImage: "arrow.up.right.square")
                        }
                    }
                } label: {
                    Label(.options, systemImage: "ellipsis")
                }
                NewIssueButton(context: NewIssueContext(repoId: repoId))
            }
        }
        .onAppear { model.setActiveRepository(repoId) }
        .onDisappear { model.setActiveRepository(nil) }
        .task(id: model.dataVersion) { await model.preloadAvatars(for: .repository(repoId)) }
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
        // Board or list as this project's open view has it. A project the iPad keeps ready in another sidebar entry
        // mustn't follow a switch made in this one.
        let mode = model.currentView(projectId: projectId).map { model.layout(of: $0) } ?? model.viewMode
        Group {
            if project == nil {
                MobileEmptyState(title: String(localized: .projectGoneTitle), message: String(localized: .projectGoneMessage), systemImage: "questionmark.square.dashed")
            } else if model.isLoading(projectId: projectId) {
                ProjectLoading()
            } else if wide, mode == .board {
                MobileBoard(projectId: projectId)
            } else {
                IssueList(scope: .project(projectId))
            }
        }
        // The project's saved views, and the open one's filter, over its list or board.
        .safeAreaInset(edge: .top, spacing: 0) {
            if project != nil, !model.views(projectId: projectId).isEmpty, !model.isLoading(projectId: projectId) {
                ViewBar(projectId: projectId)
            }
        }
        .background(Theme.panel)
        .navigationTitle(project?.title ?? String(localized: .project))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProjectSwitcher(projectId: projectId, regular: wide))
        .toolbar {
            // A window narrower than this has the tab bar floating in the middle of the bar, next to the header.
            let roomy = windowWidth >= 950
            if wide, let project {
                // The Mac's header: the project's swatch and name, then Board and List.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        // The view open, which the sidebar lists under the project; the project itself before
                        // GitHub's views are read.
                        if let view = model.currentView(projectId: project.id) {
                            ViewLayoutGlyph(view: view)
                                .foregroundStyle(Theme.textSecondary)
                            Text(view.name)
                                .font(.headline)
                                .lineLimit(1)
                        } else {
                            ProjectSwatch(title: project.title, size: 14)
                            Text(project.title)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        // With saved views, board or list belongs to the view and is in its Display menu.
                        if roomy, model.views(projectId: project.id).isEmpty {
                            Picker(.viewModePicker, selection: Bindable(model).viewMode) {
                                // Named for VoiceOver and the pointer, which would otherwise read the symbols' own names.
                                Image(systemName: "rectangle.split.3x1").accessibilityLabel(.board).help(Text(.board)).tag(ViewMode.board)
                                Image(systemName: "list.bullet").accessibilityLabel(.list).help(Text(.list)).tag(ViewMode.list)
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
            if let view = model.currentView(projectId: projectId) { model.followLayout(of: view) }
        }
        .task(id: model.dataVersion) { await model.preloadAvatars(for: .project(projectId)) }
    }
}

/// A wide iPad puts the header on the leading edge, as on the Mac.
struct EditorRole: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active { content.toolbarRole(.editor) } else { content }
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
struct ProjectLoading: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.status.phase {
        case .offline:
            MobileEmptyState(title: String(localized: .youreOffline), message: String(localized: .projectLoadsWhenOnline), systemImage: "wifi.slash")
        case .failed(let message):
            MobileEmptyState(title: String(localized: .projectLoadFailed), message: message, systemImage: "exclamationmark.triangle") {
                Button(.tryAgain) { model.refresh() }
                    .buttonStyle(.bordered)
            }
        default:
            MobileEmptyState(title: String(localized: .loadingIssues), message: String(localized: .fetchingProject), showsProgress: true)
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
            if let view = model.currentView(projectId: project.id) {
                // The open view: how it shows, its filter, a new one, and its own menu.
                ViewDisplayMenu(view: view)
                Menu {
                    ViewMenuItems(view: view)
                } label: {
                    Label(view.name, systemImage: "rectangle.stack")
                }
                if model.canEditViews(projectId: project.id) {
                    Button {
                        navigation.sheet = .newView(projectId: project.id, sourceViewId: view.id, duplicate: false)
                    } label: {
                        Label(.newViewEllipsis, systemImage: "plus.rectangle.on.rectangle")
                    }
                }
                Divider()
            } else if showsViewMode {
                Picker(.viewModePicker, selection: Bindable(model).viewMode) {
                    Label(.board, systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                    Label(.list, systemImage: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.inline)
                Divider()
            }
            Button {
                navigation.sheet = .arrangeSections(.project(project.id))
            } label: {
                Label(.arrangeSectionsMenu, systemImage: "arrow.up.arrow.down")
            }
            if project.viewerCanUpdate, project.statusFieldId != nil {
                Button {
                    openRoute(.statuses(project.id))
                } label: {
                    Label(.editStatuses, systemImage: "circle.dashed")
                }
            }
            if project.priorityFieldId == nil, project.viewerCanUpdate {
                Button {
                    model.addPriorityField(projectId: project.id)
                } label: {
                    Label(.addPriorityField, systemImage: "chart.bar.fill")
                }
            }
            Divider()
            Button {
                model.refresh()
            } label: {
                Label(.syncNow, systemImage: "arrow.triangle.2.circlepath")
            }
            if let url = URL(string: project.url), !project.url.isEmpty {
                Button {
                    Platform.open(url)
                } label: {
                    Label(.openOnGitHub, systemImage: "arrow.up.right.square")
                }
            }
        } label: {
            Label(.options, systemImage: "ellipsis")
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
                    if case .milestone(let projectId, let title) = scope, let group = model.milestoneGroup(projectId: projectId, title: title) {
                        MilestoneSummaryCard(projectId: projectId, group: group)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
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
                                ForEach(section.nesting.rows) { line in
                                    switch line {
                                    case .item(let item):
                                        row(item, in: section)
                                    case .epic(let group):
                                        EpicGroupRow(group: group, column: column(of: section)) { openRoute(.issue(group.epic.id)) }
                                            .listRowInsets(EdgeInsets())
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Theme.panel)
                                    }
                                }
                                // Touch and hold, then drag, to give an issue a new place in its section, or an epic's
                                // issues by their header.
                                .onMove(perform: canMove ? { move(in: section, from: $0, to: $1) } : nil)
                            }
                        } header: {
                            SectionHeaderBand(
                                title: section.title, glyph: section.glyph,
                                icon: section.kind == .status ? nil : model.sectionIcon(section, projectId: scope.projectId),
                                detail: section.detail, count: section.count, folded: folded,
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
                // An epic's header is lower than the usual row; its line runs on into the issues below it.
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.panel)
        .refreshable { await model.refreshAndWait() }
        .sensoryFeedback(.success, trigger: doneFeedback)
        .sensoryFeedback(.selection, trigger: foldFeedback)
    }

    private func row(_ item: Item, in section: ListSection) -> some View {
        let nested = section.nesting.nestedCounts[item.id]
        let folded = section.nesting.folded.contains(item.id)
        let depth = min(section.nesting.depth(of: item.id), IssueRow.deepestIndent)
        let epic = model.epic(of: item)?.contentId
        return Button {
            openRoute(.issue(item.id))
        } label: {
            IssueRow(
                item: item, showsProject: showsProject, place: section.nesting.place(of: item.id), nested: nested,
                folded: folded,
                // Under its parent or its epic's header, the parent goes without saying.
                showsParent: section.nesting.namesParent(of: item) && section.kind != .epic(contentId: item.parentId)
                    && section.kind != .group(.parent(contentId: item.parentId)),
                showsMilestone: showsMilestone,
                showsEpic: section.kind != .epic(contentId: epic) && section.nesting.groupOf[item.id] == nil,
                chips: model.fieldChips(of: item, in: scope)
            )
        }
        .buttonStyle(RowButtonStyle())
        // The arrow left of the status icon folds the sub-issues hanging under the issue in or out.
        .overlay(alignment: .topLeading) {
            if let nested {
                Button {
                    foldFeedback += 1
                    model.toggleFolded(item)
                } label: {
                    Color.clear.frame(width: 44 + CGFloat(depth) * IssueRow.indent, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(folded ? Text(.unfoldSubIssuesTooltip(count: nested)) : Text(.foldSubIssuesTooltip))
                .accessibilityIdentifier("fold-\(item.displayNumber)")
            }
        }
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
                    Label(done ? LocalizedStringResource.reopen : .markDone, systemImage: done ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Theme.accentFill)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.canDelete(item) {
                Button {
                    model.requestDelete(item)
                } label: {
                    Label(.delete, systemImage: "trash")
                }
                .tint(.red)
            }
            if item.kind != .draft, let viewer = model.viewer {
                let mine = item.assignees.contains { $0.id == viewer.id }
                Button {
                    model.toggleAssignee(item, viewer.person)
                } label: {
                    Label(mine ? LocalizedStringResource.unassignSwipe : .assignSwipe, systemImage: mine ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                }
                .tint(Color(white: 0.45))
            }
        }
        .contextMenu {
            ItemMenuContent(item: item, foldable: nested != nil) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
    }

    /// Issues keep their place on the board, so they can be moved in a project you can edit. My Issues mixes
    /// projects and has no such order.
    private var canMove: Bool {
        guard case .project(let id) = scope, !model.isOrdered(projectId: id) else { return false }
        return model.projects.first { $0.id == id }?.viewerCanUpdate == true
    }

    /// The board's column a section of a board's list shows.
    private func column(of section: ListSection) -> BoardColumn? {
        guard case .project(let projectId) = scope, section.kind == .status else { return nil }
        return model.listColumns(projectId: projectId).first { $0.id == section.id }
    }

    private func move(in section: ListSection, from source: IndexSet, to destination: Int) {
        let rows = section.nesting.rows
        guard let from = source.first, rows.indices.contains(from), let column = column(of: section) else { return }
        if case .epic(let group) = rows[from] {
            // The epic's issues go together, to where its header was put.
            let members = column.members(of: group)
            let moving = Set(members.map(\.id))
            let index = rows.prefix(destination).compactMap(\.item).filter { !moving.contains($0.id) }.count
            model.drop(group, members: members, in: column, at: index)
            return
        }
        guard case .item(let item) = rows[from] else { return }
        // `destination` counts the rows, epic headers and the issue itself in its old place included; `drop`
        // counts the other issues, without the sub-issues the issue brings along.
        let others = Set(column.shown(without: item).map(\.id))
        let index = rows.prefix(destination).compactMap(\.item).filter { others.contains($0.id) }.count
        // Put right below an epic's header, it joins the epic, as it shows.
        let above = rows.prefix(destination).last { row in row.item.map { others.contains($0.id) } ?? true }
        let header: String? = if case .epic(let group)? = above { group.contentId } else { nil }
        model.drop(item, in: column, at: index, belowEpicHeader: header)
    }

    /// Where rows come from several boards, each says which; an issue on none says its repository.
    private var showsProject: Bool {
        switch scope {
        case .myIssues: true
        case .repository(let id): model.boards(ofRepository: id).count > 1
        case .project, .inbox, .milestone, .roadmap: false
        }
    }

    /// A milestone's list doesn't repeat its milestone on every row, nor the roadmap an epic's own.
    private var showsMilestone: Bool {
        switch scope {
        case .milestone, .roadmap: false
        case .project(let id):
            // A view grouped by milestone says it in its groups.
            !(model.currentView(projectId: id).map { model.layout(of: $0) == .list && model.groupField(of: $0)?.kind == .milestone } ?? false)
                && !model.viewPinsMilestone(projectId: id)
        default: true
        }
    }

    private func addAction(for section: ListSection) -> (() -> Void)? {
        guard let projectId = scope.projectId else { return nil }
        let canEdit = model.projects.first { $0.id == projectId }?.viewerCanUpdate == true
        switch (scope, section.kind) {
        case (.project, .group(let key)):
            let parent: String? = if case .parent(let contentId) = key { contentId.flatMap { model.issue(contentId: $0)?.id } } else { nil }
            return {
                let preset = model.newIssuePreset(projectId: projectId, group: key)
                navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, statusId: preset?.statusId, parentItemId: parent, preset: preset))
            }
        case (.project, _):
            return { navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, statusId: section.option?.id)) }
        case (.milestone(_, let title), .epic(let contentId)) where canEdit:
            let parent = contentId.flatMap { model.issue(contentId: $0)?.id }
            return { navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, parentItemId: parent, milestoneTitle: title)) }
        case (.roadmap, .milestone(let title)) where canEdit:
            return { navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, milestoneTitle: title, isEpic: true)) }
        default:
            return nil
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch scope {
        case .inbox:
            EmptyView()
        case .myIssues:
            MobileEmptyState(
                title: String(localized: .nothingAssignedTitle),
                message: String(localized: .myIssuesEmptyMessage),
                systemImage: "scope"
            )
        case .repository(let repoId):
            if model.status.readRepositories.contains(repoId) || model.isDemo {
                MobileEmptyState(
                    title: String(localized: .noOpenIssues),
                    message: String(localized: .recentlyClosedShowToo),
                    systemImage: "tray"
                ) {
                    Button(.newIssue) {
                        navigation.sheet = .newIssue(NewIssueContext(repoId: repoId))
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                MobileEmptyState(title: String(localized: .loadingIssues), message: String(localized: .fetchingRepository), showsProgress: true)
            }
        case .milestone(let projectId, let title):
            MobileEmptyState(
                title: String(localized: .milestoneEmptyTitle(milestone: title)),
                message: String(localized: .milestoneEmptyMessage),
                systemImage: "diamond"
            ) {
                Button(.newIssue) {
                    navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, milestoneTitle: title))
                }
                .buttonStyle(.borderedProminent)
            }
        case .roadmap:
            MobileEmptyState(title: String(localized: .roadmapEmptyTitle), message: String(localized: .roadmapEmptyMessage), systemImage: "calendar.day.timeline.left")
        case .project(let projectId):
            MobileEmptyState(
                title: String(localized: .noIssuesYet),
                message: String(localized: .onlyProjectIssuesAppear),
                systemImage: "tray"
            ) {
                Button(.newIssue) {
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
                Text(.noPriorityField).font(.subheadline.weight(.semibold))
                Text(.addPriorityFieldHint)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(.add) { model.addPriorityField(projectId: projectId) }
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
        .accessibilityLabel(.accountAndSettings)
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
            Label(.newIssue, systemImage: "square.and.pencil")
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
