#if os(iOS)
import SwiftUI
import UIKit

/// The app's scene on iPhone and iPad. The app target only has to show this scene.
public struct GitIssuesScene: Scene {
    @State private var model = AppModel.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MobileRoot()
                .environment(model)
        }
        .commands {
            MobileCommands(model: model)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await model.backgroundRefresh()
        }
    }
}

/// One window: signed in, the tabs (or the iPad sidebar); otherwise the sign-in screen.
struct MobileRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var navigation = MobileNavigation()
    @State private var windowWidth: CGFloat = 0

    var body: some View {
        @Bindable var navigation = navigation
        ZStack {
            if model.signedIn {
                MainTabs()
                    .transition(.opacity)
            } else {
                SignInScreen()
                    .transition(.opacity)
            }
        }
        .animation(Theme.overlay, value: model.signedIn)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .environment(\.windowWidth, windowWidth)
        .environment(\.wideLayout, sizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad)
        .environment(navigation)
        .focusedSceneValue(\.mobileNavigation, navigation)
        .tint(Theme.accent)
        .background(WindowAppearance(setting: model.appearance))
        .sheet(item: $navigation.sheet) { sheet in
            switch sheet {
            case .newIssue(let context):
                NewIssueSheet(context: context)
            case .account:
                AccountSheet()
            case .queue:
                NavigationStack { QueueScreen(showsDone: true) }
            case .arrangeSections(let scope):
                ArrangeSectionsSheet(scope: scope)
            case .dueDate(let itemId):
                IssueDueDateSheet(itemId: itemId)
            case .picker(let itemId, let kind):
                IssuePickerSheet(kind: kind, itemId: itemId)
            case .milestoneEditor(let projectId, let title, let assigning):
                MilestoneEditorSheet(projectId: projectId, title: title, assigning: assigning)
            case .viewFilter(let viewId):
                ViewFilterSheet(viewId: viewId)
            case .myIssuesFilter:
                MyIssuesFilterSheet()
            case .newView(let projectId, let sourceViewId, let duplicate):
                NewViewSheet(projectId: projectId, sourceViewId: sourceViewId, duplicate: duplicate)
            case .projectIcon(let projectId):
                ProjectIconSheet(projectId: projectId)
            }
        }
        .modifier(ViewAlerts(navigation: navigation))
        .modifier(CompleteMilestoneAlert())
        // "New milestone…" in a picker sheet: the editor comes once the picker has gone.
        .onChange(of: model.milestoneEditorRequest) { _, request in
            guard let request else { return }
            model.milestoneEditorRequest = nil
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                navigation.sheet = .milestoneEditor(projectId: request.projectId, title: request.title, assigning: request.assigning)
            }
        }
        .alert(
            model.deletionCandidate.map { Text(.deleteItemQuestion(number: $0.displayNumber)) } ?? Text(.deleteQuestion),
            isPresented: Binding(
                get: { model.deletionCandidate != nil },
                set: { if !$0 { model.deletionCandidate = nil } }
            ),
            presenting: model.deletionCandidate
        ) { item in
            Button(.delete, role: .destructive) {
                model.delete(item)
                navigation.forget(issue: item.id)
            }
            Button(.cancel, role: .cancel) { model.deletionCandidate = nil }
        } message: { item in
            if item.kind == .draft {
                Text(.draftDeletionMessage(title: item.title))
            } else {
                Text(.issueDeletionMessage(title: item.title))
            }
        }
        .overlay(alignment: .top) {
            NoticeBanners()
        }
        .onChange(of: model.status.idRemaps) { _, remaps in
            model.follow(remaps: remaps)
            navigation.follow(remaps: remaps)
        }
        .onChange(of: model.milestoneMove) { _, move in
            guard let move else { return }
            model.milestoneMove = nil
            navigation.follow(move)
            HomePins.shared.follow(move)
        }
        // Initial too: without a token the first sync fails before this view is on screen.
        .onChange(of: model.status.phase, initial: true) { _, phase in
            if phase == .unauthorized { model.signedIn = false }
        }
        .onChange(of: model.signedIn) { _, signedIn in
            // A new session starts on its first screen.
            if signedIn { self.navigation = MobileNavigation() }
        }
    }
}

/// Puts the appearance chosen in the app on the window, so sheets and popovers follow it too.
private struct WindowAppearance: UIViewRepresentable {
    var setting: AppearanceSetting

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let style: UIUserInterfaceStyle = switch setting {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        DispatchQueue.main.async {
            view.window?.overrideUserInterfaceStyle = style
        }
    }
}

// MARK: - Tabs

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    @Environment(\.colorScheme) private var scheme
    /// Whether the iPad sidebar has the projects you hid unfolded at the end of the list.
    @State private var hiddenOpen = false

    var body: some View {
        Group {
            if wide {
                sidebar
            } else {
                PhoneStack()
            }
        }
        .onChange(of: model.revealItemId, initial: true) { _, id in
            guard let id else { return }
            model.revealItemId = nil
            reveal(id)
        }
        // A milestone closed or a board's plans gone elsewhere: their entry leaves the sidebar, and its board shows.
        .onChange(of: model.dataVersion) { _, _ in
            // A milestone renamed or completed here is followed by its own move.
            guard wide, model.milestoneMove == nil else { return }
            switch navigation.tab {
            case .milestone(let projectId, let title)
                where !model.hasPlanning(projectId: projectId) || !model.sidebarMilestones(projectId: projectId).contains { $0.title == title }:
                navigation.tab = .project(projectId)
            case .roadmap(let projectId) where !model.hasPlanning(projectId: projectId):
                navigation.tab = .project(projectId)
            case .view(let projectId, let id) where model.view(id: id) == nil:
                navigation.tab = .project(projectId)
            case .project(let projectId):
                // GitHub's views came in: the project's entry gives way to its open view's.
                if let view = model.currentView(projectId: projectId) { navigation.tab = .view(projectId: projectId, viewId: view.id) }
            default:
                break
            }
        }
        // A view's entry opens that view. A project chosen in the sidebar, or asked for by a link or a shortcut, opens
        // on its open view's entry; a view chosen elsewhere lights up its own.
        .onChange(of: navigation.tab, initial: true) { _, tab in
            switch tab {
            case .view(_, let id):
                if let view = model.view(id: id) { model.show(view) }
            case .project(let projectId) where wide:
                if let view = model.currentView(projectId: projectId) { navigation.tab = .view(projectId: projectId, viewId: view.id) }
            default:
                break
            }
        }
        .onChange(of: model.selectedViewIds) { _, _ in
            if case .view(let projectId, let id) = navigation.tab, let view = model.currentView(projectId: projectId), view.id != id {
                navigation.tab = .view(projectId: projectId, viewId: view.id)
            }
        }
        // With the last hidden project shown again, the next one hidden starts folded away.
        .onChange(of: model.hiddenProjectIds.isEmpty) { _, none in
            if none { hiddenOpen = false }
        }
        .onChange(of: wide, initial: true) { _, wide in
            navigation.adapt(regular: wide)
            // The iPhone's Home has no entry of its own in the sidebar: the project used last opens instead.
            if wide, navigation.tab == .projects {
                navigation.tab = sidebarProject.map { .project($0.id) } ?? .myIssues
            }
        }
    }

    /// The iPad's sidebar: the Inbox, My Issues and search, then every project, and under them the entries of the
    /// project on screen: All Issues and its views, then its next milestones and its roadmap. A project's row opens it
    /// on its open view, as one of its views' rows does.
    private var sidebar: some View {
        @Bindable var navigation = navigation
        return TabView(selection: $navigation.tab) {
            Tab(.inbox, systemImage: "tray", value: MobileTab.inbox) {
                InboxSplit()
            }
            .badge(model.inboxUnreadCount)
            .customizationID("inbox")
            Tab(.myIssues, systemImage: "scope", value: MobileTab.myIssues) {
                TabStack(tab: .myIssues) { MyIssuesScreen() }
            }
            .customizationID("myIssues")
            TabSection(.projects) {
                // The ones you hid at the end, where they unfold.
                ForEach(model.shownProjects + model.hiddenProjects) { project in
                    let hidden = model.hiddenProjectIds.contains(project.id)
                    Tab(value: MobileTab.project(project.id)) {
                        TabStack(tab: .project(project.id)) { ProjectScreen(projectId: project.id) }
                    } label: {
                        Label {
                            Text(project.title)
                        } icon: {
                            Image(uiImage: PlanningImages.project(model.projectLooks.look(project.id), scheme))
                        }
                    }
                    .customizationID("project.\(project.id)")
                    .contextMenu {
                        Button {
                            navigation.sheet = .projectIcon(project.id)
                        } label: {
                            Label(.changeIconEllipsis, systemImage: "paintpalette")
                        }
                        Button {
                            setHidden(project, !hidden)
                        } label: {
                            Label(hidden ? .showInSidebar : .hideFromSidebar, systemImage: hidden ? "eye" : "eye.slash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            setHidden(project, !hidden)
                        } label: {
                            Label(hidden ? .showInSidebar : .hideFromSidebar, systemImage: hidden ? "eye" : "eye.slash")
                        }
                        .tint(hidden ? Theme.accentFill : Color(white: 0.45))
                    }
                    // A hidden project stays in the TabView, so it can still be opened, but leaves the list unless it
                    // is unfolded or on screen.
                    .hidden(hidden && !hiddenOpen && sidebarProject?.id != project.id)
                }
            }
            .customizationID("projectSection")
            .sectionActions {
                // A line at the end of the list that folds the projects you hid out and in again, as on the Mac and
                // the iPhone's Home. (A menu here wouldn't open: the sidebar shows a section's actions as buttons.)
                let hidden = model.hiddenProjects
                if !hidden.isEmpty {
                    Button {
                        withAnimation(Theme.spring) { hiddenOpen.toggle() }
                    } label: {
                        Label(String(localized: .hiddenProjectsCount(count: hidden.count)), systemImage: hiddenOpen ? "eye" : "eye.slash")
                    }
                }
            }
            if let project = sidebarProject {
                viewSection(project)
                if model.hasPlanning(projectId: project.id) {
                    planningSection(project)
                }
            }
            Tab(value: MobileTab.search, role: .search) {
                TabStack(tab: .search) { SearchScreen() }
            }
            .customizationID("search")
        }
        .tabViewStyle(.sidebarAdaptable)
        // The sidebar's header and bottom bar are hosted on their own when the sidebar first appears, which can be
        // when an iPad turns from portrait to landscape; they get the model and navigation handed on explicitly, or
        // they'd find none.
        .tabViewSidebarHeader {
            SidebarAccountHeader()
                .environment(model)
                .environment(navigation)
        }
        .tabViewSidebarBottomBar {
            // Nothing while everything is on GitHub (the dot on the avatar says so); a card when you're offline or
            // something needs you.
            VStack {
                if let attention = model.syncAttention {
                    SidebarSyncHint(attention: attention)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .transition(.opacity)
                }
            }
            .animation(Theme.overlay, value: model.syncAttention)
            .environment(model)
            .environment(navigation)
        }
    }

    /// The project the sidebar is about: the one on screen, hidden or not; else the one used last, unless it was hidden
    /// since.
    private var sidebarProject: Project? {
        let open = model.openProjects
        if let id = MobileNavigation.projectId(of: navigation.tab), let project = open.first(where: { $0.id == id }) { return project }
        return open.first { $0.id == navigation.sidebarProjectId && !model.hiddenProjectIds.contains($0.id) }
            ?? model.shownProjects.first ?? open.first
    }

    /// Hides a project from the sidebar or shows it again. Hiding the one on screen moves on to the next one listed,
    /// as on the Mac, or to My Issues when there is none.
    private func setHidden(_ project: Project, _ hidden: Bool) {
        model.setHidden(project, hidden)
        guard hidden, MobileNavigation.projectId(of: navigation.tab) == project.id else { return }
        navigation.tab = model.shownProjects.first.map { .project($0.id) } ?? .myIssues
    }

    /// Under the project's name: All Issues first, with how many are on no board as a quiet count, then the project's
    /// views, each an entry.
    private func viewSection(_ project: Project) -> some TabContent<MobileTab> {
        TabSection(project.title) {
            Tab(value: MobileTab.allIssues(project.id)) {
                TabStack(tab: .allIssues(project.id)) { AllIssuesScreen(projectId: project.id) }
            } label: {
                Label(.allIssues, systemImage: "rectangle.stack")
            }
            .badge(model.countOnNoBoard(projectId: project.id))
            .customizationID("allIssues.\(project.id)")
            ForEach(model.views(projectId: project.id)) { view in
                let tab = MobileTab.view(projectId: project.id, viewId: view.id)
                Tab(value: tab) {
                    TabStack(tab: tab) { ProjectScreen(projectId: project.id) }
                } label: {
                    Label {
                        Text(view.name)
                    } icon: {
                        layoutImage(of: view)
                    }
                }
                .customizationID("view.\(view.id)")
            }
            // Until GitHub's views have been read, the project's own row above shows its board.
        }
        .customizationID("viewSection")
    }

    /// The project's next milestones and its roadmap.
    private func planningSection(_ project: Project) -> some TabContent<MobileTab> {
        TabSection(.milestones) {
            ForEach(sidebarMilestones(projectId: project.id), id: \.self) { title in
                Tab(value: MobileTab.milestone(projectId: project.id, title: title)) {
                    TabStack(tab: .milestone(projectId: project.id, title: title)) {
                        MilestoneScreen(projectId: project.id, title: title)
                    }
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        let mark = model.milestoneGroup(projectId: project.id, title: title).map { model.mark(of: $0, projectId: project.id) }
                        Image(uiImage: PlanningImages.milestone(mark ?? .completed, scheme))
                    }
                }
                .customizationID("milestone.\(project.id).\(title)")
            }
            Tab(value: MobileTab.roadmap(project.id)) {
                TabStack(tab: .roadmap(project.id)) { RoadmapScreen(projectId: project.id) }
            } label: {
                Label {
                    Text(.roadmap)
                } icon: {
                    Image(uiImage: PlanningImages.roadmap(scheme))
                }
            }
            .customizationID("roadmap.\(project.id)")
        }
        .customizationID("milestoneSection")
    }

    /// A view's layout, as the sidebar's icons are images.
    private func layoutImage(of view: ProjectView) -> Image {
        if view.layout == .roadmap, model.display(of: view).layout == nil {
            return Image(uiImage: PlanningImages.roadmap(scheme))
        }
        return Image(systemName: model.layout(of: view) == .board ? "rectangle.split.3x1" : "list.bullet")
    }

    /// A board's next milestones in the sidebar, and the one on screen while it stays there: completed or renamed
    /// here, it stays until the window has followed it on, as an entry taken away while selected would make the
    /// sidebar choose another itself.
    private func sidebarMilestones(projectId: String) -> [String] {
        guard model.hasPlanning(projectId: projectId) else { return [] }
        var titles = model.sidebarMilestones(projectId: projectId).map(\.title)
        if case .milestone(projectId, let title) = navigation.tab, !titles.contains(title) { titles.append(title) }
        return titles
    }

    /// Opens an issue a notification was about: in My Issues, where issues assigned to you are, else in its
    /// project, on top of whatever was showing.
    private func reveal(_ itemId: String) {
        guard let item = model.item(id: itemId) else { return }
        navigation.sheet = nil
        let mine = model.assignedItems.contains { $0.id == item.id }
        if mine {
            navigation.tab = .myIssues
            navigation.myIssuesPath = [.issue(item.id)]
        } else {
            if let projectId = item.projectId { navigation.showProject(projectId, regular: wide) }
            navigation.push(.issue(item.id), on: navigation.tab)
        }
    }
}

/// The iPhone's one stack, without a tab bar: Home at its root, the screen the app was left on opened on top. Back from
/// the Inbox, My Issues or a project's page leads Home; back from a project's view, milestone or roadmap leads to the
/// project's page first.
struct PhoneStack: View {
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        NavigationStack(path: Binding(
            get: { navigation.phonePath },
            set: { navigation.setPhonePath($0) }
        )) {
            HomeScreen()
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .environment(\.openRoute, OpenRouteAction { [navigation] route in navigation.setPhonePath(navigation.phonePath + [route]) })
    }
}

/// A tab's navigation stack, with every screen of the app reachable from it.
struct TabStack<Root: View>: View {
    @Environment(MobileNavigation.self) private var navigation
    var tab: MobileTab
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack(path: Binding(
            get: { navigation.path(for: tab) },
            set: { navigation.setPath($0, for: tab) }
        )) {
            root
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .environment(\.openRoute, OpenRouteAction { [navigation] route in navigation.push(route, on: tab) })
    }
}

/// The screen a route leads to, in any tab's stack.
struct RouteDestination: View {
    var route: Route

    var body: some View {
        switch route {
        case .inbox: InboxScreen()
        case .myIssues: MyIssuesScreen()
        case .search: SearchScreen()
        case .project(let id): ProjectScreen(projectId: id)
        case .allIssues(let id): AllIssuesScreen(projectId: id)
        case .issue(let id): IssueScreen(itemId: id)
        case .inboxIssue(let entry, let item): IssueScreen(itemId: item, inboxEntryId: entry)
        case .statuses(let id): StatusEditor(projectId: id)
        case .milestone(let projectId, let title): MilestoneScreen(projectId: projectId, title: title)
        case .roadmap(let projectId): RoadmapScreen(projectId: projectId)
        case .projectPage(let id): ProjectPage(projectId: id)
        }
    }
}

/// The account at the top of the iPad sidebar, with the state of syncing as a dot on its picture, and the compose
/// button; the projects are the sidebar's own entries below. It lines up with the rows below: the picture sits in their
/// icon column, the name on their title edge, and the compose button in the column of the section's disclosure arrow.
struct SidebarAccountHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        HStack(spacing: 0) {
            accountButton
            Spacer(minLength: 8)
            Button {
                navigation.sheet = .newIssue(navigation.newIssueContext)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .contentShape(.hoverEffect, Circle().inset(by: 3))
                    .hoverEffect(.highlight)
            }
            .buttonStyle(PlainPressStyle())
            .accessibilityLabel(.newIssueAction)
            .disabled(model.openProjects.isEmpty)
        }
        // The sidebar's rows put their icons 1 pt in and their accessories 15 pt past the content edge.
        .padding(.leading, 1)
        .padding(.trailing, -15)
    }

    /// Your picture and login: the account, Sync Now and the settings.
    private var accountButton: some View {
        Button {
            navigation.sheet = .account
        } label: {
            HStack(spacing: 11) {
                StatusAvatar(size: 26)
                HStack(spacing: 6) {
                    Text(model.viewer?.login ?? "GitHub")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, .rect(cornerRadius: 12).inset(by: -7))
            .hoverEffect(.highlight)
        }
        .buttonStyle(PlainPressStyle())
        .layoutPriority(1)
        .accessibilityLabel(.accountAndSettings)
        .accessibilityValue(model.accountSummary())
        .accessibilityIdentifier("sidebar-account")
    }
}

/// What needs your attention about syncing, at the bottom of the iPad sidebar: being offline, a change to decide on,
/// or a sync that failed. As on the Mac, nothing shows while everything is fine.
struct SidebarSyncHint: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var attention: SyncAttention

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: attention.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(attention.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(attention.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = attention.actionTitle {
                    Button(action, action: perform)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func perform() {
        switch attention {
        case .conflict(_, _, let itemId):
            if let itemId { navigation.push(.issue(itemId), on: navigation.tab) }
        case .failed:
            model.refresh()
        case .offline:
            navigation.sheet = .queue
        }
    }
}

extension MobileNavigation {
    /// The project on screen in the selected tab, so a new issue goes there.
    var currentProjectId: String? {
        switch tab {
        case .project(let id), .roadmap(let id), .allIssues(let id): return id
        case .milestone(let id, _), .view(let id, _): return id
        default: break
        }
        for route in path(for: tab).reversed() {
            switch route {
            case .project(let id), .roadmap(let id), .allIssues(let id), .projectPage(let id): return id
            case .milestone(let id, _): return id
            default: continue
            }
        }
        return nil
    }

    /// The milestone on screen in the selected tab, so a new issue goes into it.
    var currentMilestoneTitle: String? {
        if case .milestone(_, let title) = tab, path(for: tab).isEmpty { return title }
        if case .milestone(_, let title)? = path(for: tab).last { return title }
        return nil
    }

    /// Whether a project's All Issues is the screen in front in the selected tab, so a new issue may go on no board.
    var inAllIssues: Bool {
        for route in path(for: tab).reversed() {
            if case .allIssues = route { return true }
            if case .issue = route { continue }
            return false
        }
        if case .allIssues = tab { return true }
        return false
    }

    /// Where the compose button starts a new issue: the project on screen, or My Issues.
    var newIssueContext: NewIssueContext {
        NewIssueContext(projectId: currentProjectId, inAllIssues: inAllIssues, assignToMe: tab == .myIssues, milestoneTitle: currentMilestoneTitle)
    }
}

// MARK: - Keyboard and menu bar

extension FocusedValues {
    @Entry var mobileNavigation: MobileNavigation?
}

/// The iPad menu bar and keyboard shortcuts: the same commands as the Mac's menus.
struct MobileCommands: Commands {
    var model: AppModel
    @FocusedValue(\.mobileNavigation) private var navigation

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(.newIssue) {
                if let navigation { navigation.sheet = .newIssue(navigation.newIssueContext) }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(navigation == nil || !model.signedIn || model.openProjects.isEmpty)
        }
        CommandMenu(Text(.goMenu)) {
            let unavailable = navigation == nil || !model.signedIn
            // The board is on wide windows only, and switches the project on screen.
            let noBoard = unavailable || navigation?.regular != true || navigation?.currentProjectId == nil
            Button(.back) { navigation?.pop() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(unavailable)
            Divider()
            Button(.search) {
                navigation?.tab = .search
                navigation?.searchFocusRequest += 1
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(unavailable)
            Divider()
            // A project's open view keeps board or list as yours; a milestone switches what is on screen.
            let projectId: String? = switch navigation?.tab {
            case .project(let id)?, .view(let id, _)?: id
            default: nil
            }
            Button(.board) { model.showLayout(.board, projectId: projectId) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(noBoard)
            Button(.list) { model.showLayout(.list, projectId: projectId) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(noBoard)
            Button(.myIssues) { navigation?.tab = .myIssues }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(unavailable)
            Button(.allIssues) {
                guard let navigation, let projectId = navigation.currentProjectId ?? navigation.sidebarProjectId ?? model.openProjects.first?.id
                else { return }
                navigation.showAllIssues(projectId, regular: navigation.regular)
            }
            .disabled(unavailable || model.openProjects.isEmpty)
            Button(.roadmap) {
                guard let navigation, let projectId = navigation.currentProjectId ?? model.openProjects.first?.id else { return }
                if navigation.regular {
                    navigation.tab = .roadmap(projectId)
                } else {
                    navigation.projectsPath = [.project(projectId), .roadmap(projectId)]
                    navigation.tab = .projects
                }
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(unavailable || model.openProjects.isEmpty)
            Button(.inbox) { navigation?.tab = .inbox }
                .disabled(unavailable)
            Divider()
            Button(.syncWithGitHubNow) { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(unavailable)
        }
        CommandMenu(Text(.issueMenu)) {
            // The issue in front in the focused window.
            let item = navigation?.currentIssueId.flatMap { model.item(id: $0) }
            Button(.copyGitHubLink) { if let item { model.copyLink(item) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(item?.url == nil)
            Button(.copyBranchName) { if let item { model.copyBranchName(item) } }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(item?.branchName == nil)
            Button(.openOnGitHub) { if let item { model.openOnGitHub(item) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(item?.url == nil)
            Divider()
            Button(.deleteIssue) { if let item { model.requestDelete(item) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(item.map { !model.canDelete($0) } ?? true)
        }
    }
}
#endif
