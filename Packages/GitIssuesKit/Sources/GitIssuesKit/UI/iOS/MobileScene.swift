#if os(iOS)
import SwiftUI
import UIKit

/// The app's scene on iPhone and iPad. The app target only has to show this scene.
public struct GitIssuesScene: Scene {
    @State private var model = AppModel()

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
            case .arrangeSections(let scope):
                ArrangeSectionsSheet(scope: scope)
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
        .tabViewSidebarHeader {
            SidebarAccountHeader()
        }
        .tabViewSidebarBottomBar {
            // The dot in the rows' icon column, the text on their title edge.
            SyncStatusLine(indicatorWidth: 30, spacing: 9)
                .padding(.leading, 31)
                .padding(.trailing, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: wide, initial: true) { _, wide in
            navigation.adapt(regular: wide)
            if wide, navigation.tab == .projects {
                navigation.tab = model.openProjects.first.map { .project($0.id) } ?? .myIssues
            }
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
                    switch route {
                    case .project(let id): ProjectScreen(projectId: id)
                    case .issue(let id): IssueScreen(itemId: id)
                    case .statuses(let id): StatusEditor(projectId: id)
                    }
                }
        }
        .environment(\.openRoute, OpenRouteAction { [navigation] route in navigation.push(route, on: tab) })
    }
}

/// The account at the top of the iPad sidebar, as at the top of the Mac's sidebar. It lines up with the rows below:
/// the avatar sits in their icon column, the name on their title edge, and the compose button in the column of the
/// section's disclosure arrow.
struct SidebarAccountHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        HStack(spacing: 0) {
            Button {
                navigation.sheet = .account
            } label: {
                HStack(spacing: 11) {
                    AccountAvatar(size: 26)
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
            .accessibilityValue(model.isDemo ? "Sample data" : (model.viewer?.login ?? ""))
            Spacer(minLength: 8)
            Button {
                navigation.sheet = .newIssue(NewIssueContext(projectId: navigation.currentProjectId, assignToMe: navigation.tab == .myIssues))
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

/// The signed-in person's avatar, or a placeholder until it is known.
struct AccountAvatar: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat

    var body: some View {
        if let viewer = model.viewer {
            Avatar(login: viewer.login, url: viewer.avatarUrl, size: size)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: size, height: size)
        }
    }
}

extension MobileNavigation {
    /// The project on screen in the selected tab, so a new issue goes there.
    var currentProjectId: String? {
        if case .project(let id) = tab { return id }
        for route in path(for: tab).reversed() {
            if case .project(let id) = route { return id }
        }
        return nil
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
                navigation?.sheet = .newIssue(NewIssueContext(projectId: navigation?.currentProjectId, assignToMe: navigation?.tab == .myIssues))
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
