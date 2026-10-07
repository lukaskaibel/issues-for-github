#if os(iOS)
import SwiftUI

/// The tabs of the app. On the iPhone: My Issues, Projects and Search in the tab bar. On the iPad the same
/// tabs form a sidebar, where every project is an entry of its own, as on the Mac.
enum MobileTab: Hashable {
    case myIssues
    case projects
    case project(String)
    case search
}

/// A screen pushed onto a tab's navigation stack.
enum Route: Hashable, Codable {
    case project(String)
    case issue(String)
    case statuses(String)
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

    var id: String {
        switch self {
        case .newIssue(let context): "new-\(context.projectId ?? "-")-\(context.statusId ?? "-")-\(context.parentItemId ?? "-")"
        case .account: "account"
        case .queue: "queue"
        case .arrangeSections(let scope): "arrange-\(scope)"
        case .dueDate(let id): "due-\(id)"
        }
    }
}

/// Where a new issue starts out: which project, which status, and which parent for a sub-issue.
struct NewIssueContext: Equatable {
    var projectId: String?
    var statusId: String?
    var parentItemId: String?
    /// Started from My Issues: the new issue is assigned to you, so it shows up there.
    var assignToMe = false
}

/// Navigation of one window: the selected tab and the stack of screens in each.
@MainActor
@Observable
final class MobileNavigation {
    var tab: MobileTab {
        didSet { if tab != oldValue { Self.saveTab(tab) } }
    }
    var myIssuesPath: [Route] = []
    var projectsPath: [Route] = []
    var projectPaths: [String: [Route]] = [:]
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
        case "projects": .projects
        case "search": .search
        default: .myIssues
        }
        // The iPhone opens the Projects tab on the project used last.
        if let project = UserDefaults.standard.string(forKey: Self.projectKey) {
            projectsPath = [.project(project)]
        }
    }

    private static func saveTab(_ tab: MobileTab) {
        let value: String = switch tab {
        case .myIssues: "myIssues"
        case .projects, .project: "projects"
        case .search: "search"
        }
        UserDefaults.standard.set(value, forKey: tabKey)
        if case .project(let id) = tab { UserDefaults.standard.set(id, forKey: projectKey) }
    }

    func path(for tab: MobileTab) -> [Route] {
        switch tab {
        case .myIssues: myIssuesPath
        case .projects: projectsPath
        case .project(let id): projectPaths[id] ?? []
        case .search: searchPath
        }
    }

    func setPath(_ path: [Route], for tab: MobileTab) {
        switch tab {
        case .myIssues: myIssuesPath = path
        case .projects: projectsPath = path
        case .project(let id): projectPaths[id] = path
        case .search: searchPath = path
        }
    }

    func push(_ route: Route, on tab: MobileTab) {
        if case .project(let id) = route { UserDefaults.standard.set(id, forKey: Self.projectKey) }
        setPath(path(for: tab) + [route], for: tab)
    }

    /// The issue open in the selected tab, if its screen is the one in front.
    var currentIssueId: String? {
        if case .issue(let id)? = path(for: tab).last { return id }
        return nil
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

    /// Moves between the iPad sidebar and the tab bar when the window changes width, keeping the project open.
    func adapt(regular: Bool) {
        self.regular = regular
        if regular, tab == .projects, case .project(let id)? = projectsPath.first {
            projectPaths[id] = Array(projectsPath.dropFirst())
            tab = .project(id)
        } else if !regular, case .project(let id) = tab {
            projectsPath = [.project(id)] + (projectPaths[id] ?? [])
            tab = .projects
        }
    }

    /// Takes the screens of an issue you deleted off every stack, so you're back where you came from.
    func forget(issue id: String) {
        func strip(_ path: [Route]) -> [Route] { path.filter { $0 != .issue(id) } }
        myIssuesPath = strip(myIssuesPath)
        projectsPath = strip(projectsPath)
        searchPath = strip(searchPath)
        for (key, path) in projectPaths { projectPaths[key] = strip(path) }
    }

    /// Follows issues whose temporary id was replaced once GitHub created them.
    func follow(remaps: [String: String]) {
        func remap(_ path: [Route]) -> [Route] {
            path.map { route in
                if case .issue(let id) = route, let new = remaps[id] { return .issue(new) }
                return route
            }
        }
        myIssuesPath = remap(myIssuesPath)
        projectsPath = remap(projectsPath)
        searchPath = remap(searchPath)
        for (key, path) in projectPaths { projectPaths[key] = remap(path) }
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
