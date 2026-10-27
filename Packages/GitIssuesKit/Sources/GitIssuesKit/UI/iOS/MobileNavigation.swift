#if os(iOS)
import SwiftUI

/// Where the app is. On the iPad: the entries of the sidebar, where every project is one of its own, then its views
/// and milestones. On the iPhone, which has no tab bar: Home (`projects` with nothing pushed), or the Inbox, My Issues
/// or search opened on top of it, each with the screens opened from there. A project there is its page with its
/// views and milestones, and whichever of them is open on top of it.
enum MobileTab: Hashable {
    case inbox
    case myIssues
    /// Home on the iPhone, with the projects and their screens pushed onto it.
    case projects
    case project(String)
    /// A project's All Issues, at the top of its entries in the iPad sidebar.
    case allIssues(String)
    /// A board's milestone and its roadmap, under the board in the iPad sidebar.
    case milestone(projectId: String, title: String)
    case roadmap(String)
    /// A view of the project chosen in the iPad sidebar: the project, as the view shows it.
    case view(projectId: String, viewId: String)
    case search
}

/// A screen pushed onto a tab's navigation stack.
enum Route: Hashable, Codable {
    /// The Inbox, My Issues and search, opened from the iPhone's Home: the first screen of their tab's stack.
    case inbox
    case myIssues
    case search
    /// A project's open view.
    case project(String)
    /// A project's All Issues.
    case allIssues(String)
    /// The iPhone's page of a project: All Issues, its views, its next milestones and the roadmap. It is under every
    /// one of them, however they were opened.
    case projectPage(String)
    case issue(String)
    case statuses(String)
    case milestone(projectId: String, title: String)
    case roadmap(String)
    /// An issue opened from the Inbox: what's new on it shows at the top.
    case inboxIssue(entry: String, item: String)
}

/// Sheets the whole window can show, whichever tab asked for them.
enum MobileSheet: Identifiable, Equatable {
    case newIssue(NewIssueContext)
    case account
    /// The changes waiting to be sent, from the card at the bottom of the iPad sidebar.
    case queue
    case arrangeSections(Scope)
    /// The due date of an issue, from a menu that has no screen of its own to show it.
    case dueDate(String)
    /// A picker for an issue, from a long press on its row or card: its parent, sub-issues or blockers.
    case picker(itemId: String, kind: PickerKind)
    /// A new milestone of a board (no title), or one to change; a new one goes to the issues `assigning`.
    case milestoneEditor(projectId: String?, title: String?, assigning: [String])
    /// A saved view's filter, to change and save.
    case viewFilter(String)
    /// My Issues' filter.
    case myIssuesFilter
    /// A new saved view, starting from the one open or a copy of another.
    case newView(projectId: String, sourceViewId: String?, duplicate: Bool)
    /// The glyph and colour a project shows with.
    case projectIcon(String)

    var id: String {
        switch self {
        case .newIssue(let context): "new-\(context.projectId ?? "-")-\(context.inAllIssues)-\(context.statusId ?? "-")-\(context.parentItemId ?? "-")-\(context.milestoneTitle ?? "-")-\(context.isEpic)"
        case .milestoneEditor(let projectId, let title, let assigning): "milestone-\(projectId ?? "-")-\(title ?? "-")-\(assigning.joined(separator: ","))"
        case .account: "account"
        case .queue: "queue"
        case .arrangeSections(let scope): "arrange-\(scope)"
        case .dueDate(let id): "due-\(id)"
        case .picker(let itemId, let kind): "picker-\(kind)-\(itemId)"
        case .viewFilter(let id): "view-filter-\(id)"
        case .myIssuesFilter: "my-issues-filter"
        case .newView(let projectId, let source, let duplicate): "new-view-\(projectId)-\(source ?? "-")-\(duplicate)"
        case .projectIcon(let id): "project-icon-\(id)"
        }
    }
}

/// Where a new issue starts out: which project, which status, and which parent for a sub-issue.
struct NewIssueContext: Equatable {
    var projectId: String?
    /// Started in the project's All Issues: the issue goes on its board or on none, in one of its repositories.
    var inAllIssues = false
    var statusId: String?
    var parentItemId: String?
    /// Started from My Issues: the new issue is assigned to you, so it shows up there.
    var assignToMe = false
    /// Started in a milestone: the new issue goes into it.
    var milestoneTitle: String?
    /// Started from the roadmap: a new epic.
    var isEpic = false
    /// Started in a view's group or column: the values its filter asks for and the group's.
    var preset: NewIssuePreset?
}

/// Navigation of one window: the selected tab and the stack of screens in each.
@MainActor
@Observable
final class MobileNavigation {
    /// The saved view being renamed or waiting for "Delete?" to be answered.
    var renamingView: String?
    var deletingView: String?
    var tab: MobileTab {
        didSet {
            guard tab != oldValue else { return }
            saveTab()
            if let id = Self.projectId(of: tab) { sidebarProjectId = id }
        }
    }
    /// The project the iPad sidebar shows All Issues, the views and milestones of: the one on screen, or the one used
    /// last.
    var sidebarProjectId: String? = UserDefaults.standard.string(forKey: MobileNavigation.projectKey)
    var inboxPath: [Route] = []
    /// On a wide iPad the Inbox shows the selected entry's issue beside the list; this is that issue.
    var inboxRootItemId: String?
    var myIssuesPath: [Route] = []
    var projectsPath: [Route] = [] {
        didSet {
            // A project's view, All Issues, milestone or roadmap opened from Home, a pin, a link or where the app was
            // left has the project's page under it, so Back leads there before Home.
            if let first = projectsPath.first, let id = Self.pageProject(of: first) {
                projectsPath.insert(.projectPage(id), at: 0)
            }
            // Home, a project's page or a project: where the iPhone opens next time.
            if tab == .projects, Self.place(of: projectsPath) != Self.place(of: oldValue) { saveTab() }
        }
    }
    var projectPaths: [String: [Route]] = [:]
    var allIssuesPaths: [String: [Route]] = [:]
    /// The stacks of milestones' and roadmaps' entries in the iPad sidebar.
    var planningPaths: [String: [Route]] = [:]
    var searchPath: [Route] = []
    var sheet: MobileSheet?
    /// What is typed into the search tab's field.
    var searchQuery = ""
    /// Bumped to ask the search tab to put the cursor in its field (⌘K).
    var searchFocusRequest = 0
    /// The column the iPhone's board of a project's view was left on, by `PhoneBoard.pageKey`, to come back to it.
    var boardPages: [String: String] = [:]
    /// Whether the window is wide enough for the sidebar and the board.
    private(set) var regular = false
    /// A property picker asked for from the keyboard, for the issue on screen; that issue's screen shows it.
    var pickerRequest: PickerRequest?

    struct PickerRequest: Equatable {
        var itemId: String
        var kind: PickerKind
    }

    private static let tabKey = "mobile.tab"
    /// The project opened last on this device. Not the Mac's key: that one is set before anything is opened.
    private static let projectKey = "mobile.lastProject"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.tabKey)
        tab = switch saved {
        case "inbox": .inbox
        case "myIssues": .myIssues
        case "search": .search
        // Projects come first: the iPhone's Home, the iPad's project used last.
        default: .projects
        }
        // Where it was left: on the project used last, its page or its open view, unless that was Home.
        if let project = UserDefaults.standard.string(forKey: Self.projectKey) {
            // Set in here, the path doesn't put the page under the project itself.
            if saved == "projects" { projectsPath = [.projectPage(project), .project(project)] }
            if saved == "projectPage" { projectsPath = [.projectPage(project)] }
        }
    }

    /// The project whose page goes under a screen opened first on Home's stack.
    private static func pageProject(of route: Route) -> String? {
        switch route {
        case .project(let id), .allIssues(let id), .roadmap(let id): id
        case .milestone(let id, _): id
        default: nil
        }
    }

    /// Where on Home's stack the iPhone is, as saved for next time.
    private static func place(of path: [Route]) -> String {
        switch path.first {
        case nil: "home"
        case .projectPage? where path.count == 1: "projectPage"
        default: "projects"
        }
    }

    private func saveTab() {
        let value: String = switch tab {
        case .inbox: "inbox"
        case .myIssues: "myIssues"
        case .projects: Self.place(of: projectsPath)
        case .project, .allIssues, .milestone, .roadmap, .view: "projects"
        // The iPhone's search is a field on its screens, and comes back as Home.
        case .search: regular ? "search" : "home"
        }
        UserDefaults.standard.set(value, forKey: Self.tabKey)
        if case .project(let id) = tab { UserDefaults.standard.set(id, forKey: Self.projectKey) }
    }

    /// The iPhone's one stack: Home at its root, and the Inbox, My Issues or search, when one of them is open, as the
    /// first screen on it.
    var phonePath: [Route] {
        switch tab {
        case .inbox: [.inbox] + inboxPath
        case .myIssues: [.myIssues] + myIssuesPath
        case .search: [.search] + searchPath
        default: projectsPath
        }
    }

    func setPhonePath(_ path: [Route]) {
        switch path.first {
        case .inbox?:
            inboxPath = Array(path.dropFirst())
            tab = .inbox
        case .myIssues?:
            myIssuesPath = Array(path.dropFirst())
            tab = .myIssues
        case .search?:
            searchPath = Array(path.dropFirst())
            tab = .search
        default:
            projectsPath = path
            tab = .projects
        }
    }

    func path(for tab: MobileTab) -> [Route] {
        switch tab {
        case .inbox: inboxPath
        case .myIssues: myIssuesPath
        case .projects: projectsPath
        case .project(let id): projectPaths[id] ?? []
        case .allIssues(let id): allIssuesPaths[id] ?? []
        case .milestone, .roadmap: planningPaths[Self.planningKey(tab)] ?? []
        // A project's views share the project's stack.
        case .view(let projectId, _): projectPaths[projectId] ?? []
        case .search: searchPath
        }
    }

    /// The project a tab is about, if it is about one.
    static func projectId(of tab: MobileTab) -> String? {
        switch tab {
        case .project(let id), .roadmap(let id), .milestone(let id, _), .view(let id, _), .allIssues(let id): id
        default: nil
        }
    }

    private static func planningKey(_ tab: MobileTab) -> String {
        switch tab {
        case .milestone(let projectId, let title): "milestone:\(projectId)\u{1F}\(title)"
        case .roadmap(let projectId): "roadmap:\(projectId)"
        default: ""
        }
    }

    func setPath(_ path: [Route], for tab: MobileTab) {
        switch tab {
        case .inbox: inboxPath = path
        case .myIssues: myIssuesPath = path
        case .projects: projectsPath = path
        case .project(let id): projectPaths[id] = path
        case .allIssues(let id): allIssuesPaths[id] = path
        case .milestone, .roadmap: planningPaths[Self.planningKey(tab)] = path
        case .view(let projectId, _): projectPaths[projectId] = path
        case .search: searchPath = path
        }
    }

    func push(_ route: Route, on tab: MobileTab) {
        if case .project(let id) = route { UserDefaults.standard.set(id, forKey: Self.projectKey) }
        setPath(path(for: tab) + [route], for: tab)
    }

    /// The issue open in the selected tab, if its screen is the one in front.
    var currentIssueId: String? {
        switch path(for: tab).last {
        case .issue(let id)?: return id
        case .inboxIssue(_, let id)?: return id
        case nil where tab == .inbox && regular: return inboxRootItemId
        default: return nil
        }
    }

    func requestPicker(_ kind: PickerKind) {
        guard let id = currentIssueId else { return }
        pickerRequest = PickerRequest(itemId: id, kind: kind)
    }

    /// Goes back one screen in the selected tab (⌘[ on an iPad keyboard); on the iPhone, as far as Home.
    func pop() {
        if !regular {
            var path = phonePath
            guard !path.isEmpty else { return }
            path.removeLast()
            setPhonePath(path)
            return
        }
        var path = path(for: tab)
        guard !path.isEmpty else { return }
        path.removeLast()
        setPath(path, for: tab)
    }

    /// Remembers the project on screen, so the Projects tab opens on it next time.
    func rememberProject(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.projectKey)
    }

    /// Opens a project on its open view: in its own sidebar entry on a wide iPad window, on Home otherwise, over the
    /// project's page.
    func showProject(_ id: String, regular: Bool) {
        UserDefaults.standard.set(id, forKey: Self.projectKey)
        if regular {
            tab = .project(id)
        } else {
            projectsPath = [.project(id)]
            tab = .projects
        }
    }

    /// Opens a project's All Issues: in its own sidebar entry on a wide iPad window, on its project otherwise.
    func showAllIssues(_ projectId: String, regular: Bool) {
        UserDefaults.standard.set(projectId, forKey: Self.projectKey)
        if regular {
            tab = .allIssues(projectId)
        } else {
            projectsPath = [.allIssues(projectId)]
            tab = .projects
        }
    }

    /// Moves between the iPad sidebar and the tab bar when the window changes width, keeping the project open.
    func adapt(regular: Bool) {
        self.regular = regular
        // The iPad's sidebar lists what the iPhone's page of a project has.
        let onPage = projectsPath.first.flatMap { route -> String? in
            if case .projectPage(let id) = route { id } else { nil }
        }
        let path = onPage == nil ? projectsPath : Array(projectsPath.dropFirst())
        if regular, tab == .projects, case .project(let id)? = path.first {
            projectPaths[id] = Array(path.dropFirst())
            tab = .project(id)
        } else if regular, tab == .projects, case .allIssues(let id)? = path.first {
            allIssuesPaths[id] = Array(path.dropFirst())
            tab = .allIssues(id)
        } else if regular, tab == .projects, let id = onPage {
            tab = .project(id)
        } else if !regular, case .project(let id) = tab {
            projectsPath = [.project(id)] + (projectPaths[id] ?? [])
            tab = .projects
        } else if !regular, case .allIssues(let id) = tab {
            projectsPath = [.allIssues(id)] + (allIssuesPaths[id] ?? [])
            tab = .projects
        } else if !regular, case .milestone(let projectId, let title) = tab {
            projectsPath = [.milestone(projectId: projectId, title: title)] + (planningPaths[Self.planningKey(tab)] ?? [])
            tab = .projects
        } else if !regular, case .roadmap(let projectId) = tab {
            projectsPath = [.roadmap(projectId)] + (planningPaths[Self.planningKey(tab)] ?? [])
            tab = .projects
        } else if !regular, case .view(let projectId, _) = tab {
            projectsPath = [.project(projectId)] + (projectPaths[projectId] ?? [])
            tab = .projects
        }
    }

    /// Takes the screens of an issue you deleted off every stack, so you're back where you came from.
    func forget(issue id: String) {
        func strip(_ path: [Route]) -> [Route] {
            path.filter { route in
                if case .inboxIssue(_, let item) = route { return item != id }
                return route != .issue(id)
            }
        }
        inboxPath = strip(inboxPath)
        if inboxRootItemId == id { inboxRootItemId = nil }
        myIssuesPath = strip(myIssuesPath)
        projectsPath = strip(projectsPath)
        searchPath = strip(searchPath)
        for (key, path) in projectPaths { projectPaths[key] = strip(path) }
        for (key, path) in allIssuesPaths { allIssuesPaths[key] = strip(path) }
        for (key, path) in planningPaths { planningPaths[key] = strip(path) }
    }

    /// Follows a milestone renamed or completed: its screens show it under its new name, or the milestone its work
    /// went on to; with none, its screen closes and its sidebar entry gives way to the board.
    func follow(_ move: MilestoneMove) {
        let from = Route.milestone(projectId: move.projectId, title: move.from)
        let to = move.to.map { Route.milestone(projectId: move.projectId, title: $0) }
        func replace(_ path: [Route]) -> [Route] {
            path.compactMap { $0 == from ? to : $0 }
        }
        inboxPath = replace(inboxPath)
        myIssuesPath = replace(myIssuesPath)
        projectsPath = replace(projectsPath)
        searchPath = replace(searchPath)
        for (key, path) in projectPaths { projectPaths[key] = replace(path) }
        for (key, path) in allIssuesPaths { allIssuesPaths[key] = replace(path) }
        for (key, path) in planningPaths { planningPaths[key] = replace(path) }
        let oldTab = MobileTab.milestone(projectId: move.projectId, title: move.from)
        guard tab == oldTab else { return }
        let stack = planningPaths.removeValue(forKey: Self.planningKey(oldTab)) ?? []
        if let title = move.to {
            let newTab = MobileTab.milestone(projectId: move.projectId, title: title)
            planningPaths[Self.planningKey(newTab)] = stack
            tab = newTab
        } else {
            tab = .project(move.projectId)
        }
    }

    /// Follows issues whose temporary id was replaced once GitHub created them.
    func follow(remaps: [String: String]) {
        func remap(_ path: [Route]) -> [Route] {
            path.map { route in
                if case .issue(let id) = route, let new = remaps[id] { return .issue(new) }
                if case .inboxIssue(let entry, let id) = route, let new = remaps[id] { return .inboxIssue(entry: entry, item: new) }
                return route
            }
        }
        inboxPath = remap(inboxPath)
        if let id = inboxRootItemId, let new = remaps[id] { inboxRootItemId = new }
        myIssuesPath = remap(myIssuesPath)
        projectsPath = remap(projectsPath)
        searchPath = remap(searchPath)
        for (key, path) in projectPaths { projectPaths[key] = remap(path) }
        for (key, path) in allIssuesPaths { allIssuesPaths[key] = remap(path) }
        for (key, path) in planningPaths { planningPaths[key] = remap(path) }
    }
}

/// Pushes a screen onto the navigation stack the view sits in.
struct OpenRouteAction {
    var action: (Route) -> Void
    func callAsFunction(_ route: Route) { action(route) }
}

extension EnvironmentValues {
    @Entry var openRoute = OpenRouteAction { _ in }
    /// A wide iPad window: the sidebar with a project per entry, the board, and an issue's properties in a column.
    /// An iPhone keeps its own layout even where it is wide, as a large one is in landscape.
    @Entry var wideLayout = false
    /// The width of the window, for bars that rearrange when it is narrow.
    @Entry var windowWidth: CGFloat = 0
}

/// Recently opened issues, newest first, for the search tab.
enum RecentIssues {
    private static let key = "mobile.recentIssues"

    static var ids: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ id: String) {
        var list = ids.filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: key)
    }
}
#endif
