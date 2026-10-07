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
            }
        }
        .alert(
            model.deletionCandidate.map { "Delete \($0.displayNumber)?" } ?? "Delete?",
            isPresented: Binding(
                get: { model.deletionCandidate != nil },
                set: { if !$0 { model.deletionCandidate = nil } }
            ),
            presenting: model.deletionCandidate
        ) { item in
            Button("Delete", role: .destructive) {
                model.delete(item)
                navigation.forget(issue: item.id)
            }
            Button("Cancel", role: .cancel) { model.deletionCandidate = nil }
        } message: { item in
            if item.kind == .draft {
                Text("The draft “\(item.title)” is removed from the board.")
            } else {
                Text("“\(item.title)” and its comments are deleted on GitHub for everyone. This can't be undone.")
            }
        }
        .overlay(alignment: .top) {
            NoticeBanners()
        }
        .onChange(of: model.status.idRemaps) { _, remaps in
            model.follow(remaps: remaps)
            navigation.follow(remaps: remaps)
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

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            Tab("Inbox", systemImage: "tray", value: MobileTab.inbox) {
                if wide {
                    InboxSplit()
                } else {
                    TabStack(tab: .inbox) { InboxScreen() }
                }
            }
            .badge(model.inboxUnreadCount)
            .customizationID("inbox")
            Tab("My Issues", systemImage: "scope", value: MobileTab.myIssues) {
                TabStack(tab: .myIssues) { MyIssuesScreen() }
            }
            .customizationID("myIssues")
            if wide {
                // On a wide iPad every project is an entry of its own, as in the Mac's sidebar.
                TabSection("Projects") {
                    ForEach(model.openProjects) { project in
                        Tab(value: MobileTab.project(project.id)) {
                            TabStack(tab: .project(project.id)) { ProjectScreen(projectId: project.id) }
                        } label: {
                            Label {
                                Text(project.title)
                            } icon: {
                                Image(uiImage: SwatchImages.image(for: project.title))
                            }
                        }
                        .customizationID("project.\(project.id)")
                    }
                }
                .customizationID("projectSection")
                if !model.boardRepositories.isEmpty {
                    // Like the teams in Linear: every issue of a repository, whether it is on a board or not.
                    TabSection("Repositories") {
                        ForEach(model.boardRepositories) { repo in
                            Tab(value: MobileTab.repository(repo.id)) {
                                TabStack(tab: .repository(repo.id)) { RepositoryScreen(repoId: repo.id) }
                            } label: {
                                Label(model.displayName(of: repo), systemImage: "book.closed")
                            }
                            .customizationID("repository.\(repo.id)")
                        }
                    }
                    .customizationID("repositorySection")
                }
            } else {
                Tab("Projects", systemImage: "square.stack", value: MobileTab.projects) {
                    TabStack(tab: .projects) { ProjectsScreen() }
                }
                .customizationID("projects")
            }
            Tab(value: MobileTab.search, role: .search) {
                TabStack(tab: .search) { SearchScreen() }
            }
            .customizationID("search")
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: model.revealItemId, initial: true) { _, id in
            guard let id else { return }
            model.revealItemId = nil
            reveal(id)
        }
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
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: wide, initial: true) { _, wide in
            navigation.adapt(regular: wide)
            if wide, navigation.tab == .projects {
                navigation.tab = model.openProjects.first.map { .project($0.id) } ?? .myIssues
            }
        }
    }

    /// Opens an issue a notification was about: in My Issues, where issues assigned to you are, else in its
    /// project, on top of whatever was showing.
    private func reveal(_ itemId: String) {
        guard let item = model.item(id: itemId) else { return }
        navigation.sheet = nil
        let mine = model.items(in: .myIssues).contains { $0.id == item.id }
        if mine {
            navigation.tab = .myIssues
            navigation.myIssuesPath = [.issue(item.id)]
        } else {
            if let projectId = item.projectId { navigation.showProject(projectId, regular: wide) }
            navigation.push(.issue(item.id), on: navigation.tab)
        }
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
        case .project(let id): ProjectScreen(projectId: id)
        case .repository(let id): RepositoryScreen(repoId: id)
        case .issue(let id): IssueScreen(itemId: id)
        case .inboxIssue(let entry, let item): IssueScreen(itemId: item, inboxEntryId: entry)
        case .statuses(let id): StatusEditor(projectId: id)
        }
    }
}

/// The account at the top of the iPad sidebar, as at the top of the Mac's sidebar, with the state of syncing as a dot
/// on the avatar. It lines up with the rows below: the avatar sits in their icon column, the name on their title edge,
/// and the compose button in the column of the section's disclosure arrow.
struct SidebarAccountHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        HStack(spacing: 0) {
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
            .accessibilityLabel("Account and settings")
            .accessibilityValue(model.accountSummary())
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
            .accessibilityLabel("New issue")
            .disabled(model.openProjects.isEmpty)
        }
        // The sidebar's rows put their icons 1 pt in and their accessories 15 pt past the content edge.
        .padding(.leading, 1)
        .padding(.trailing, -15)
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
        if case .project(let id) = tab { return id }
        for route in path(for: tab).reversed() {
            if case .project(let id) = route { return id }
            if case .repository = route { return nil }
        }
        return nil
    }

    /// The repository on screen in the selected tab, so a new issue is created in it.
    var currentRepositoryId: String? {
        if case .repository(let id) = tab { return id }
        for route in path(for: tab).reversed() {
            if case .repository(let id) = route { return id }
            if case .project = route { return nil }
        }
        return nil
    }

    /// Where the compose button starts a new issue: the project or repository on screen, or My Issues.
    var newIssueContext: NewIssueContext {
        NewIssueContext(projectId: currentProjectId, repoId: currentRepositoryId, assignToMe: tab == .myIssues)
    }
}

/// Coloured project squares as images, for the sidebar where entries need an image.
@MainActor
enum SwatchImages {
    private static var cache: [String: UIImage] = [:]

    static func image(for title: String) -> UIImage {
        if let cached = cache[title] { return cached }
        // As wide as the sidebar's symbol column, so project names line up with "My Issues" and "Search".
        let renderer = ImageRenderer(content: ProjectSwatch(title: title, size: 16).frame(width: 28, height: 28))
        renderer.scale = 3
        let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) ?? UIImage()
        cache[title] = image
        return image
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
            Button("New Issue") {
                if let navigation { navigation.sheet = .newIssue(navigation.newIssueContext) }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(navigation == nil || !model.signedIn || model.openProjects.isEmpty)
        }
        CommandMenu("Go") {
            let unavailable = navigation == nil || !model.signedIn
            // The board is on wide windows only, and switches the project on screen.
            let noBoard = unavailable || navigation?.regular != true || navigation?.currentProjectId == nil
            Button("Back") { navigation?.pop() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(unavailable)
            Divider()
            Button("Search") {
                navigation?.tab = .search
                navigation?.searchFocusRequest += 1
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(unavailable)
            Divider()
            Button("Board") { withAnimation(Theme.spring) { model.viewMode = .board } }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(noBoard)
            Button("List") { withAnimation(Theme.spring) { model.viewMode = .list } }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(noBoard)
            Button("My Issues") { navigation?.tab = .myIssues }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(unavailable)
            Button("Inbox") { navigation?.tab = .inbox }
                .disabled(unavailable)
            Divider()
            Button("Sync with GitHub Now") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(unavailable)
        }
        CommandMenu("Issue") {
            // The issue in front in the focused window.
            let item = navigation?.currentIssueId.flatMap { model.item(id: $0) }
            Button("Copy GitHub Link") { if let item { model.copyLink(item) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(item?.url == nil)
            Button("Copy Branch Name") { if let item { model.copyBranchName(item) } }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(item?.branchName == nil)
            Button("Open on GitHub") { if let item { model.openOnGitHub(item) } }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(item?.url == nil)
            Divider()
            Button("Delete Issue…") { if let item { model.requestDelete(item) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(item.map { !model.canDelete($0) } ?? true)
        }
    }
}
#endif
