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
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        MyIssuesDisplayMenu()
                        Divider()
                        // The overview arranges its widgets in a sheet of its own; the list, its sections.
                        if model.mineDisplay.layout == .overview {
                            Button {
                                navigation.sheet = .customizeMyIssues
                            } label: {
                                Label(.customizeEllipsis, systemImage: "square.grid.2x2")
                            }
                        } else {
                            Button {
                                navigation.sheet = .arrangeSections(.myIssues)
                            } label: {
                                Label(.arrangeSectionsMenu, systemImage: "arrow.up.arrow.down")
                            }
                        }
                        Button {
                            model.refresh()
                        } label: {
                            Label(.syncNow, systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Label(.options, systemImage: "ellipsis")
                    }
                    if wide { NewIssueButton(context: NewIssueContext(assignToMe: true)) }
                }
            }
            .modifier(PhoneSearchBar(context: NewIssueContext(assignToMe: true)))
            .task(id: model.dataVersion) { await model.preloadAvatars(for: .myIssues) }
    }
}

/// My Issues' filter and how it shows, at the top of its "…" menu: Filter… opens the sheet; the overview or the list,
/// a group (for the list) or an order is picked right in the menu, which then closes.
private struct MyIssuesDisplayMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        let display = model.mineDisplay
        Button {
            navigation.sheet = .myIssuesFilter
        } label: {
            Label(.filterEllipsis, systemImage: "line.3.horizontal.decrease")
        }
        Picker(.layout, selection: Binding(get: { model.mineDisplay.layout }, set: { layout in withAnimation(Theme.spring) { model.setMineLayout(layout) } })) {
            Label { Text(.overview) } icon: { Image(systemName: "square.grid.2x2") }.tag(MineLayout.overview)
            Label { Text(.list) } icon: { Image(systemName: "list.bullet") }.tag(MineLayout.list)
        }
        .pickerStyle(.menu)
        if display.layout == .list {
            Picker(.groupBy, selection: Binding(get: { model.mineDisplay.grouping }, set: { grouping in model.setMineDisplay { $0.grouping = grouping } })) {
                ForEach(MineGrouping.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
        Picker(.orderBy, selection: Binding(get: { model.mineDisplay.order }, set: { model.setMineOrder($0) })) {
            ForEach(MineOrder.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        if display.order != .manual {
            Button {
                model.setMineDisplay { $0.descending.toggle() }
            } label: {
                Label(display.descending ? .descending : .ascending, systemImage: display.descending ? "arrow.down" : "arrow.up")
            }
        }
        if !display.optionsAreDefault {
            Button(role: .destructive) {
                model.resetMineDisplay()
            } label: {
                Label(.reset, systemImage: "arrow.uturn.backward")
            }
        }
    }
}

/// My Issues' filter, term by term, as a view's. It is yours alone and applies at once, so there is nothing to save.
struct MyIssuesFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FilterTermsForm(filter: Binding(get: { model.mineFilter }, set: { model.setMineFilter($0) }), scope: .myIssues) {
                if !model.mineFilter.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            model.setMineFilter(ProjectFilter(""))
                        } label: {
                            Label(.clearFilter, systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(.filter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done) { dismiss() }
                }
            }
        }
    }
}

/// A project's All Issues: its board's issues and those of its repositories on no board, as a list by status with
/// the issues on no board first.
struct AllIssuesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    var projectId: String

    var body: some View {
        let project = model.projects.first { $0.id == projectId }
        IssueList(scope: .allIssues(projectId))
            .background(Theme.panel)
            .navigationTitle(.allIssues)
            .navigationSubtitle(project?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(EditorRole(active: wide))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            navigation.sheet = .arrangeSections(.allIssues(projectId))
                        } label: {
                            Label(.arrangeSectionsMenu, systemImage: "arrow.up.arrow.down")
                        }
                        // Home's pins are the iPhone's.
                        if !wide { PinMenuItem(entry: .allIssues(projectId)) }
                        Divider()
                        Button {
                            model.refresh()
                        } label: {
                            Label(.syncNow, systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Label(.options, systemImage: "ellipsis")
                    }
                    if wide { NewIssueButton(context: NewIssueContext(projectId: projectId, inAllIssues: true)) }
                }
            }
            .modifier(PhoneSearchBar(context: NewIssueContext(projectId: projectId, inAllIssues: true)))
            .onAppear {
                model.setActiveProject(projectId)
                navigation.rememberProject(projectId)
                model.setActiveRepositories(model.repos(projectId: projectId).map(\.id))
            }
            .onDisappear { model.setActiveRepositories([]) }
            .task(id: model.dataVersion) { await model.preloadAvatars(for: .allIssues(projectId)) }
    }
}

/// One project: its list or its board, the iPad's columns side by side, the iPhone's one at a time.
struct ProjectScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @Environment(\.wideLayout) private var wide
    @Environment(\.windowWidth) private var windowWidth
    var projectId: String

    var body: some View {
        let project = model.projects.first { $0.id == projectId }
        // Board or list as this project's open view has it. A project the iPad keeps ready in another sidebar entry
        // mustn't follow a switch made in this one.
        let mode = model.currentView(projectId: projectId).map { model.layout(of: $0) } ?? model.viewMode
        // The iPhone has no room for a timeline, and a board needs columns to show.
        let phoneBoard = project != nil && !wide && mode == .board && !model.isLoading(projectId: projectId)
            && !model.shownColumns(for: .project(projectId)).isEmpty
        let onBoard = phoneBoard || project != nil && wide && mode == .board && !(model.currentView(projectId: projectId).map { model.showsTimeline($0) } ?? false)
        let ground = onBoard ? Theme.board : Theme.panel
        Group {
            if project == nil {
                MobileEmptyState(title: String(localized: .projectGoneTitle), message: String(localized: .projectGoneMessage), systemImage: "questionmark.square.dashed")
            } else if model.isLoading(projectId: projectId) {
                ProjectLoading()
            } else if wide, let view = model.currentView(projectId: projectId), model.showsTimeline(view) {
                // GitHub's roadmap layout: the view's issues on a timeline, where there is room for one.
                ViewTimeline(view: view, scope: .project(projectId), nameWidth: 280) { openRoute(.issue($0.id)) }
            } else if wide, mode == .board {
                MobileBoard(projectId: projectId)
                    .id(model.currentView(projectId: projectId)?.id)
            } else if phoneBoard {
                PhoneBoard(projectId: projectId, page: PhoneBoard.page(model: model, navigation: navigation, projectId: projectId))
                    .id(model.currentView(projectId: projectId)?.id)
            } else {
                // Another view starts at its top, not where the last one was scrolled to.
                IssueList(scope: .project(projectId))
                    .id(model.currentView(projectId: projectId)?.id)
            }
        }
        // The open view's filter over its list or board. The iPhone lists the project's views on its page, under
        // this screen; the iPad in its sidebar.
        .safeAreaInset(edge: .top, spacing: 0) {
            if project != nil, !model.views(projectId: projectId).isEmpty, !model.isLoading(projectId: projectId) {
                ViewBar(projectId: projectId, ground: ground)
            }
        }
        // White pages, and under the board the grey its cards stand on, under the bars above it too.
        .background(ground)
        // On the iPhone the open view names the screen and the project is under it, as Back leads to the project's page.
        .navigationTitle(!wide ? model.currentView(projectId: projectId)?.name ?? project?.title ?? "" : project?.title ?? String(localized: .project))
        .modifier(ProjectSubtitle(title: !wide && model.currentView(projectId: projectId) != nil ? project?.title : nil))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(EditorRole(active: wide))
        .toolbar {
            // A window narrower than this has the tab bar floating in the middle of the bar, next to the header.
            let roomy = windowWidth >= 950
            if wide, let project {
                // The Mac's header: the project's icon and name, then Board and List.
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
                            ProjectIcon(projectId: project.id, size: 14)
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
                    ProjectOptionsMenu(project: project, showsViewMode: !(wide && roomy))
                }
                if wide { NewIssueButton(context: NewIssueContext(projectId: projectId)) }
            }
        }
        .modifier(PhoneSearchBar(context: NewIssueContext(projectId: projectId)))
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

/// The project's name under the title of one of its screens on the iPhone.
struct ProjectSubtitle: ViewModifier {
    var title: String?

    func body(content: Content) -> some View {
        if let title { content.navigationSubtitle(title) } else { content }
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

/// My Issues before your projects have each been fetched once, as right after signing in: they come one by one, and
/// their issues with them.
private struct MyIssuesLoading: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.status.phase {
        case .offline:
            MobileEmptyState(title: String(localized: .youreOffline), message: String(localized: .myIssuesLoadsWhenOnline), systemImage: "wifi.slash")
        case .failed(let message):
            MobileEmptyState(title: String(localized: .syncProblem), message: message, systemImage: "exclamationmark.triangle") {
                Button(.tryAgain) { model.refresh() }
                    .buttonStyle(.bordered)
            }
        default:
            MobileEmptyState(title: String(localized: .loadingIssues), message: String(localized: .myIssuesLoadingMessage), showsProgress: true)
        }
    }
}

/// The "…" menu of a project: on one of its views, that view's part first; on the iPhone's page of the project, only
/// the project's.
struct ProjectOptionsMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @Environment(\.wideLayout) private var wide
    var project: Project
    /// Board and List, when the bar has no room for them beside the project's name.
    var showsViewMode = false
    /// The open view's part and arranging the sections: off on the project's page, which shows no view.
    var showsView = true

    var body: some View {
        Menu {
            if showsView, let view = model.currentView(projectId: project.id) {
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
                // Home's pins are the iPhone's.
                if !wide { PinMenuItem(entry: .view(view)) }
                Divider()
            } else if showsViewMode {
                Picker(.viewModePicker, selection: Bindable(model).viewMode) {
                    Label(.board, systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                    Label(.list, systemImage: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.inline)
                Divider()
            }
            if showsView {
                Button {
                    navigation.sheet = .arrangeSections(.project(project.id))
                } label: {
                    Label(.arrangeSectionsMenu, systemImage: "arrow.up.arrow.down")
                }
            }
            Button {
                navigation.sheet = .projectIcon(project.id)
            } label: {
                Label(.changeIconEllipsis, systemImage: "paintpalette")
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
            // The overview shows projects with nothing started or to do too.
            if sections.isEmpty && !(isOverview && !model.mineLanes.isEmpty) {
                emptyState
            } else {
                List {
                    if case .milestone(let projectId, let title) = scope, let group = model.milestoneGroup(projectId: projectId, title: title) {
                        MilestoneSummaryCard(projectId: projectId, group: group)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    if scope == .myIssues, !model.mineFilter.isEmpty {
                        // My Issues' filter as a line of chips under the title, like a view's; a tap changes it.
                        FilterChipStrip(filter: model.mineFilter, scope: .myIssues, identifier: "my-issues-filter") {
                            navigation.sheet = .myIssuesFilter
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                    }
                    if case .project(let id) = scope, let project = model.projects.first(where: { $0.id == id }),
                       project.priorityFieldId == nil, project.viewerCanUpdate, project.lastSyncedAt != nil {
                        PriorityFieldBanner(projectId: id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    if isOverview {
                        overview(sections)
                    } else {
                        groups(sections)
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

    /// My Issues as an overview: its widgets in their order. A project shows what you are doing there and the most
    /// pressing of what is next, the rest as counts at its end; small projects stand two to a row as tiles; a smart
    /// widget lists what it finds across every project.
    @ViewBuilder
    private func overview(_ sections: [ListSection]) -> some View {
        let lanes = Dictionary(model.mineLanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byId = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ForEach(MobileWidgetRow.rows(model.overviewWidgets, lanes: lanes)) { row in
            switch row {
            case .tiles(let widgets):
                ProjectTilesRow(widgets: widgets)
            case .widget(let widget):
                if let smart = widget.smart {
                    smartSection(smart, size: widget.size)
                } else if let lane = lanes[widget.id] {
                    laneSection(lane, section: byId[lane.id])
                }
            }
        }
    }

    /// A project, or the issues on no board: In progress and Up next, then the rest as counts.
    @ViewBuilder
    private func laneSection(_ lane: MineLane, section: ListSection?) -> some View {
        let folded = model.isSectionCollapsed(lane.id, in: scope)
        let unfolded = model.showsAllNext(lane)
        let container = section ?? ListSection(id: lane.id, title: lane.title, glyph: .none, items: [])
        Section {
            if !folded {
                if !lane.started.isEmpty {
                    OverviewSubhead(title: .statusGroupInProgress)
                    ForEach(lane.started) { row($0, in: container, idle: true) }
                }
                if !lane.next.isEmpty {
                    // The issues on no board are all waiting; the header says where they are.
                    if lane.projectId != nil { OverviewSubhead(title: .upNext) }
                    ForEach(lane.shownNext(unfolded: unfolded)) { row($0, in: container) }
                }
                OverviewLaneFoot(lane: lane, unfolded: unfolded)
            }
        } header: {
            SectionHeaderBand(
                title: lane.title, glyph: .noProject,
                icon: lane.projectId.map { .project(model.projectLooks.look($0)) } ?? .status(.noProject),
                warning: lane.overdue > 0 ? String(localized: .overviewOverdue(count: lane.overdue)) : nil,
                count: lane.open, folded: folded,
                onToggle: {
                    foldFeedback += 1
                    withAnimation(Theme.spring) { model.toggleSection(lane.id, in: scope) }
                },
                onAdd: nil
            )
            .listRowInsets(EdgeInsets())
        }
        .listSectionSeparator(.hidden)
    }

    /// Needs you, Due this week or Done this week: a small one lists two, the others up to six.
    @ViewBuilder
    private func smartSection(_ widget: MineSmartWidget, size: MineWidgetSize) -> some View {
        let limit = size == .small ? 2 : 6
        let folded = model.isSectionCollapsed(widget.id, in: scope)
        let count: Int = switch widget {
        case .needsYou: model.needsYou.count
        case .dueThisWeek: model.dueThisWeek.count
        case .doneThisWeek: model.doneThisWeek.count
        }
        let container = ListSection(id: widget.id, title: widget.title, glyph: .none, items: [])
        Section {
            if !folded {
                if count == 0 {
                    Text(widget == .needsYou ? .nothingNeedsYou : widget == .dueThisWeek ? .nothingDueThisWeek : .nothingDoneThisWeek)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, IssueRow.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.panel)
                }
                switch widget {
                case .needsYou:
                    ForEach(model.needsYou.prefix(limit)) { NeedsYouListRow(entry: $0) }
                case .dueThisWeek:
                    ForEach(model.dueThisWeek.prefix(limit)) { row($0, in: container, namesBoard: true) }
                case .doneThisWeek:
                    ForEach(model.doneThisWeek.prefix(limit)) { row($0, in: container, namesBoard: true) }
                }
            }
        } header: {
            SmartWidgetHeader(widget: widget, count: count)
                .listRowInsets(EdgeInsets())
        }
        .listSectionSeparator(.hidden)
    }

    private var isOverview: Bool {
        scope == .myIssues && model.mineDisplay.layout == .overview
    }

    /// The list's groups, as a project's columns, a view's groups or My Issues' list has them.
    @ViewBuilder
    private func groups(_ sections: [ListSection]) -> some View {
        // The person with the most open issues sets how long the load bars are.
        let mostOpen = sections.filter { $0.style == .people }.compactMap { $0.progress.map { $0.total - $0.done } }.max() ?? 0
        ForEach(sections) { section in
            let folded = model.isFolded(section, in: scope)
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
                    // Only sections by status are columns of the board; a group by another field has no order.
                    .onMove(perform: canMove && column(of: section) != nil ? { move(in: section, from: $0, to: $1) } : nil)
                }
            } header: {
                SectionHeaderBand(
                    title: section.title, glyph: section.glyph,
                    icon: section.kind == .status ? nil : model.sectionIcon(section, projectId: scope.projectId),
                    detail: section.detail,
                    count: section.count, countText: section.countText, folded: folded,
                    bar: section.progress.map { progress in
                        (section.style, progress, mostOpen > 0 ? CGFloat(progress.total - progress.done) / CGFloat(mostOpen) : 0)
                    },
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

    /// `namesBoard` overrides whether a row of My Issues names its project: the overview's smart widgets mix them.
    private func row(_ item: Item, in section: ListSection, idle: Bool = false, namesBoard: Bool? = nil) -> some View {
        let nested = section.nesting.nestedCounts[item.id]
        let folded = section.nesting.folded.contains(item.id)
        let depth = min(section.nesting.depth(of: item.id), IssueRow.deepestIndent)
        let epic = model.epic(of: item)?.contentId
        return Button {
            openRoute(.issue(item.id))
        } label: {
            IssueRow(
                item: item, showsProject: showsProject,
                namesBoard: namesBoard ?? !(scope == .myIssues && (model.mineDisplay.grouping == .project || model.mineDisplay.layout == .overview)),
                namesRepository: isAllIssues,
                place: section.nesting.place(of: item.id), nested: nested,
                folded: folded,
                // Under its parent or its epic's header, the parent goes without saying.
                showsParent: section.nesting.namesParent(of: item) && section.kind != .epic(contentId: item.parentId)
                    && section.kind != .group(.parent(contentId: item.parentId)),
                showsMilestone: showsMilestone,
                showsEpic: section.kind != .epic(contentId: epic) && section.nesting.groupOf[item.id] == nil,
                chips: model.fieldChips(of: item, in: scope),
                idleDays: idle ? model.idleDays(of: item) : nil
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

    private var isAllIssues: Bool {
        if case .allIssues = scope { return true }
        return false
    }

    /// Where rows come from several boards, each says which; an issue on none says its repository. All Issues of a
    /// board with several repositories says each row's.
    private var showsProject: Bool {
        switch scope {
        case .myIssues: true
        case .allIssues(let id): model.repos(projectId: id).count > 1
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
            if !model.mineFilter.isEmpty, !model.assignedItems.isEmpty {
                // The filter hides everything; one tap shows it all again.
                MobileEmptyState(
                    title: String(localized: .nothingMatchesFilterTitle),
                    message: String(localized: .nothingMatchesFilterMessage),
                    systemImage: "line.3.horizontal.decrease.circle"
                ) {
                    Button(.clearFilter) { model.setMineFilter(ProjectFilter("")) }
                        .buttonStyle(.bordered)
                }
            } else if model.isLoadingMyIssues {
                MyIssuesLoading()
            } else {
                MobileEmptyState(
                    title: String(localized: .nothingAssignedTitle),
                    message: String(localized: .myIssuesEmptyMessage),
                    systemImage: "scope"
                )
            }
        case .allIssues(let projectId):
            if model.isLoading(allIssuesOf: projectId) {
                MobileEmptyState(title: String(localized: .loadingIssues), message: String(localized: .fetchingRepositories), showsProgress: true)
            } else {
                MobileEmptyState(
                    title: String(localized: .noIssuesYet),
                    message: String(localized: .noBoardIssuesShowToo),
                    systemImage: "rectangle.stack"
                ) {
                    Button(.newIssue) {
                        navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, inAllIssues: true))
                    }
                    .buttonStyle(.borderedProminent)
                }
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
            if let view = model.viewHidingEverything(projectId: projectId) {
                // The view's filter hides every issue, which isn't the project having none.
                let changed = model.filterChanged(view)
                MobileEmptyState(
                    title: String(localized: .nothingMatchesFilterTitle),
                    message: String(localized: changed ? .viewFilterMatchesNothingChanged : .viewFilterMatchesNothing),
                    systemImage: "line.3.horizontal.decrease.circle"
                ) {
                    if changed {
                        Button(.reset) { model.resetFilter(of: view) }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                projectEmptyState(projectId)
            }
        }
    }

    private func projectEmptyState(_ projectId: String) -> some View {
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

/// Over a project's started issues, and over what is next, in My Issues' overview.
private struct OverviewSubhead: View {
    let title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(.smallMedium)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, IssueRow.leading)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.panel)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The end of a project in the overview: a tap shows the rest of what is next, or only the first few again; then
/// what waits in the backlog and what was finished this week.
private struct OverviewLaneFoot: View {
    @Environment(AppModel.self) private var model
    let lane: MineLane
    let unfolded: Bool

    var body: some View {
        let more = lane.moreNext(unfolded: unfolded)
        let canFold = unfolded && lane.next.count > MineLane.nextShown
        let counts = [
            lane.later > 0 ? String(localized: .overviewInBacklog(count: lane.later)) : nil,
            lane.doneThisWeek > 0 ? String(localized: .overviewDoneThisWeek(count: lane.doneThisWeek)) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        if more > 0 || canFold || !counts.isEmpty {
            HStack(spacing: 6) {
                if more > 0 || canFold {
                    Button {
                        withAnimation(Theme.spring) { model.toggleAllNext(lane) }
                    } label: {
                        HStack(spacing: 5) {
                            Text(canFold ? .overviewShowFewer : .overviewMoreToDo(count: more))
                            Image(systemName: canFold ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainPressStyle())
                    .accessibilityIdentifier("more-\(lane.title)")
                }
                if !counts.isEmpty {
                    Text(counts)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .frame(minHeight: 44)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.leading, IssueRow.leading)
            .padding(.trailing, 18)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.panel)
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
    /// In the accent's glass, at the foot of an iPhone screen, as Notes and Notebook show New Note.
    var prominent = false

    var body: some View {
        let button = Button {
            navigation.sheet = .newIssue(context)
        } label: {
            Label(.newIssue, systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("compose-button")
        .disabled(model.openProjects.isEmpty)
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button
        }
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
