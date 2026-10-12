#if os(iOS)
import SwiftUI

/// The tabs of the app. On the iPhone: Inbox, My Issues, Projects and Search in the tab bar. On the iPad the same
/// tabs form a sidebar, where every project is an entry of its own, as on the Mac.
enum MobileTab: Hashable {
    case inbox
    case myIssues
    case projects
    case project(String)
    /// A repository's entry in the iPad sidebar.
    case repository(String)
    /// A board's milestone and its roadmap, under the board in the iPad sidebar.
    case milestone(projectId: String, title: String)
    case roadmap(String)
    case search
}

/// A screen pushed onto a tab's navigation stack.
enum Route: Hashable, Codable {
    case project(String)
    case repository(String)
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

    var id: String {
        switch self {
        case .newIssue(let context): "new-\(context.projectId ?? "-")-\(context.repoId ?? "-")-\(context.statusId ?? "-")-\(context.parentItemId ?? "-")-\(context.milestoneTitle ?? "-")-\(context.isEpic)"
        case .milestoneEditor(let projectId, let title, let assigning): "milestone-\(projectId ?? "-")-\(title ?? "-")-\(assigning.joined(separator: ","))"
        case .account: "account"
        case .queue: "queue"
        case .arrangeSections(let scope): "arrange-\(scope)"
        case .dueDate(let id): "due-\(id)"
        case .picker(let itemId, let kind): "picker-\(kind)-\(itemId)"
        }
    }
}

/// Where a new issue starts out: which project, which status, and which parent for a sub-issue.
struct NewIssueContext: Equatable {
    var projectId: String?
    /// Started in a repository: the issue is created there, on one of its boards or on none.
    var repoId: String?
    var statusId: String?
    var parentItemId: String?
    /// Started from My Issues: the new issue is assigned to you, so it shows up there.
    var assignToMe = false
    /// Started in a milestone: the new issue goes into it.
    var milestoneTitle: String?
    /// Started from the roadmap: a new epic.
    var isEpic = false
}

/// Navigation of one window: the selected tab and the stack of screens in each.
@MainActor
@Observable
final class MobileNavigation {
    var tab: MobileTab {
        didSet { if tab != oldValue { Self.saveTab(tab) } }
    }
    var inboxPath: [Route] = []
    /// On a wide iPad the Inbox shows the selected entry's issue beside the list; this is that issue.
    var inboxRootItemId: String?
    var myIssuesPath: [Route] = []
    var projectsPath: [Route] = []
    var projectPaths: [String: [Route]] = [:]
    var repositoryPaths: [String: [Route]] = [:]
    /// The stacks of milestones' and roadmaps' entries in the iPad sidebar.
    var planningPaths: [String: [Route]] = [:]
    var searchPath: [Route] = []
    var sheet: MobileSheet?
    /// What is typed into the search tab's field.
    var searchQuery = ""
    /// Bumped to ask the search tab to put the cursor in its field (⌘K).
    var searchFocusRequest = 0
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
        case "myIssues": .myIssues
        case "projects": .projects
        case "search": .search
        // The Inbox comes first, as in Linear.
        default: .inbox
        }
        // The iPhone opens the Projects tab on the project used last.
        if let project = UserDefaults.standard.string(forKey: Self.projectKey) {
            projectsPath = [.project(project)]
        }
    }

    private static func saveTab(_ tab: MobileTab) {
        let value: String = switch tab {
        case .inbox: "inbox"
        case .myIssues: "myIssues"
        case .projects, .project, .repository, .milestone, .roadmap: "projects"
        case .search: "search"
        }
        UserDefaults.standard.set(value, forKey: tabKey)
        if case .project(let id) = tab { UserDefaults.standard.set(id, forKey: projectKey) }
    }

    func path(for tab: MobileTab) -> [Route] {
        switch tab {
        case .inbox: inboxPath
        case .myIssues: myIssuesPath
        case .projects: projectsPath
        case .project(let id): projectPaths[id] ?? []
        case .repository(let id): repositoryPaths[id] ?? []
        case .milestone, .roadmap: planningPaths[Self.planningKey(tab)] ?? []
        case .search: searchPath
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
        case .repository(let id): repositoryPaths[id] = path
        case .milestone, .roadmap: planningPaths[Self.planningKey(tab)] = path
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

    /// Goes back one screen in the selected tab (⌘[ on an iPad keyboard).
    func pop() {
        var path = path(for: tab)
        guard !path.isEmpty else { return }
        path.removeLast()
        setPath(path, for: tab)
    }

    /// Remembers the project on screen, so the Projects tab opens on it next time.
    func rememberProject(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.projectKey)
    }

    /// Opens a project: in its own sidebar entry on a wide iPad window, inside the Projects tab otherwise.
    func showProject(_ id: String, regular: Bool) {
        UserDefaults.standard.set(id, forKey: Self.projectKey)
        if regular {
            tab = .project(id)
        } else {
            projectsPath = [.project(id)]
            tab = .projects
        }
    }

    /// Opens a repository: in its own sidebar entry on a wide iPad window, inside the Projects tab otherwise.
    func showRepository(_ id: String, regular: Bool) {
        if regular {
            tab = .repository(id)
        } else {
            projectsPath = [.repository(id)]
            tab = .projects
        }
    }

    /// Moves between the iPad sidebar and the tab bar when the window changes width, keeping the project open.
    func adapt(regular: Bool) {
        self.regular = regular
        if regular, tab == .projects, case .project(let id)? = projectsPath.first {
            projectPaths[id] = Array(projectsPath.dropFirst())
            tab = .project(id)
        } else if regular, tab == .projects, case .repository(let id)? = projectsPath.first {
            repositoryPaths[id] = Array(projectsPath.dropFirst())
            tab = .repository(id)
        } else if !regular, case .project(let id) = tab {
            projectsPath = [.project(id)] + (projectPaths[id] ?? [])
            tab = .projects
        } else if !regular, case .repository(let id) = tab {
            projectsPath = [.repository(id)] + (repositoryPaths[id] ?? [])
            tab = .projects
        } else if !regular, case .milestone(let projectId, let title) = tab {
            projectsPath = [.project(projectId), .milestone(projectId: projectId, title: title)] + (planningPaths[Self.planningKey(tab)] ?? [])
            tab = .projects
        } else if !regular, case .roadmap(let projectId) = tab {
            projectsPath = [.project(projectId), .roadmap(projectId)] + (planningPaths[Self.planningKey(tab)] ?? [])
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
        for (key, path) in repositoryPaths { repositoryPaths[key] = strip(path) }
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
        for (key, path) in repositoryPaths { repositoryPaths[key] = replace(path) }
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
        for (key, path) in repositoryPaths { repositoryPaths[key] = remap(path) }
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
