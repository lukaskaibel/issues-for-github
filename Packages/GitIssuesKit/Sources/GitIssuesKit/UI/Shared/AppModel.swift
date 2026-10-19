import GRDB
import Network
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BoardColumn: Identifiable, Equatable {
    static let noStatusId = "no-status"

    var id: String
    var option: FieldOption?
    var glyph: StatusGlyph
    /// The cards as shown: sub-issues under their parent, folded ones left out.
    var items: [Item]
    var nesting = Nesting()
    /// For a board whose columns are another field than Status: the field and the value its cards share.
    var value: ColumnValue? = nil
    /// The name of such a column, and what it says quietly after its count, such as an iteration's days.
    var label: String? = nil
    var detail: String? = nil
    /// GitHub's colour of an option, shown as a dot before the name.
    var dot: String? = nil

    var title: String { option?.name ?? label ?? String(localized: .noStatus) }
    /// Every card in the column, folded ones included.
    var count: Int { nesting.members.count }
}

struct ListSection: Identifiable, Equatable {
    /// What a group of the list is made of.
    enum Kind: Equatable {
        /// Issues with a status, or a kind of status.
        case status
        /// The issues of an epic in a milestone, or those of none (nil).
        case epic(contentId: String?)
        /// The epics of a milestone on the roadmap, or those planned for none (nil).
        case milestone(title: String?)
        /// The issues of a view's group: the value of the field it groups by that they share.
        case group(GroupKey)
    }

    var id: String
    var title: String
    var glyph: StatusGlyph
    var option: FieldOption?
    var kind: Kind = .status
    /// Shown quietly after the count, such as when a milestone is due.
    var detail: String?
    /// The icon of a view's group, such as a person's avatar or an option's colour.
    var groupIcon: SectionIcon? = nil
    /// The issues as shown: sub-issues under their parent, folded ones left out.
    var items: [Item]
    var nesting = Nesting()
    /// How a view's group shows: as a list, with its progress, or as a person's load.
    var style: GroupStyle = .plain
    /// How far the group's issues are, for groups that show it.
    var progress: GroupProgress?

    /// Every issue in the group, folded ones included.
    var count: Int { nesting.members.count }

    /// The number in the header: how many of all are done for a group that shows its progress, else how many.
    var countText: String {
        if style == .progress, let progress { progress.fraction } else { "\(count)" }
    }
}

/// How a view's group shows in the list. Groups of something that gets finished (a parent issue, a milestone, an
/// iteration) show how far they are; groups by person show how much each has open. Groups of a kind (a label, an
/// option, a status) are only lists.
enum GroupStyle: Equatable {
    case plain
    case progress
    case people
}

/// How many of a group's issues are done, under way and there in all, as the view shows them.
struct GroupProgress: Equatable {
    var done: Int
    var started: Int
    var total: Int

    var open: Int { total - done - started }
    /// "4/6": done of all.
    var fraction: String { "\(done)/\(total)" }
}

enum PaletteMode: Hashable {
    case root
    case status(itemId: String)
    case priority(itemId: String)
    case assignees(itemId: String)
    case labels(itemId: String)
    case dueDate(itemId: String)
    case parent(itemId: String)
    case addSubIssue(itemId: String)
    case blockedBy(itemId: String)
    case blocking(itemId: String)
    case milestone(itemId: String)
    case epic(itemId: String)
    case projects
    /// Every saved view of the open projects, to go to.
    case views
}

enum Overlay: Equatable {
    case palette(PaletteMode)
    case newIssue(statusId: String?, parentItemId: String?)
    /// A new milestone of a board (no title), or an existing one to change. A new one goes to the issues `assigning`.
    case milestoneEditor(projectId: String?, title: String?, assigning: [String])
}

enum ViewMode: String, Codable {
    case board
    case list
}

/// A milestone of a board, by its title.
struct MilestoneRef: Equatable, Identifiable {
    var projectId: String
    var title: String
    var id: String { "\(projectId)/\(title)" }
}

/// A new milestone of a board, or one to change, and the issues a new one goes to.
struct MilestoneEditorRequest: Equatable {
    var projectId: String?
    var title: String?
    var assigning: [String]
}

/// A milestone renamed or completed here: the screens that showed it follow it to its new name, or to the milestone
/// its work went on to (nil: the board).
struct MilestoneMove: Equatable {
    var projectId: String
    var from: String
    var to: String?
}

enum RoadmapLayout: String {
    case timeline
    case list
}

enum RoadmapZoom: String, CaseIterable {
    case months
    case quarters

    /// Points per day.
    var scale: CGFloat {
        switch self {
        case .months: 5
        case .quarters: 1.8
        }
    }
}

enum Scope: Hashable, Codable {
    case project(String)
    case myIssues
    /// Every issue of a repository, on a board or not. The id is the repository's.
    case repository(String)
    case inbox
    /// The issues of a board in one milestone, by its title: the milestones of that name in the board's repositories.
    case milestone(projectId: String, title: String)
    /// A board's epics over its milestones.
    case roadmap(String)

    /// The board the scope belongs to.
    var projectId: String? {
        switch self {
        case .project(let id), .roadmap(let id): id
        case .milestone(let id, _): id
        case .myIssues, .repository, .inbox: nil
        }
    }
}

/// Everything the views read, kept in step with the database, plus navigation state.
@MainActor
@Observable
public final class AppModel {
    private(set) var db: AppDatabase
    let auth: AuthStore
    private(set) var engine: SyncEngine
    public let status: SyncStatus
    #if os(macOS)
    let boardDrag = BoardDrag()
    #endif
    /// Built-in sample data instead of a GitHub account, for trying the app out (and for App Review).
    private(set) var isDemo: Bool

    // Data mirrored from the database.
    private(set) var viewer: Viewer?
    private(set) var projects: [Project] = []
    private(set) var allItems: [Item] = []
    private(set) var options: [FieldOption] = []
    private(set) var repos: [RepoRef] = []
    /// Milestones of the repositories your boards use, open and closed.
    private(set) var milestones: [Milestone] = []
    /// The saved views of every project, in the order of their tabs.
    private(set) var views: [ProjectView] = []
    /// The fields of every project, their own and GitHub's.
    private(set) var fields: [ProjectField] = []
    private(set) var outbox: [OutboxEntry] = []
    /// What blocks the issues whose detail was read, and what they block.
    private(set) var links: [LinkedIssue] = []
    /// GitHub's notifications about issues and pull requests, newest first, archived ones included.
    private(set) var inboxEntries: [InboxEntry] = []
    /// Assignments your own account made, as kept; `selfAssignedInboxEntries` is what the Inbox shows of them.
    private(set) var selfAssignedEntries: [InboxEntry] = []
    private(set) var inboxMeta = InboxMeta()
    /// Snoozes and "marked unread", which GitHub has no place for; shared through iCloud.
    private(set) var personal: PersonalStore
    /// Each project's glyph and colour, which GitHub has no place for either; shared through iCloud.
    private(set) var projectLooks: ProjectLooks

    // Derived from the above for the current scope.
    private(set) var columns: [BoardColumn] = []
    private(set) var sections: [ListSection] = []
    private(set) var glyphs: [String: StatusGlyph] = [:]
    /// Bumped whenever lists may look different, so views that read cached lists redraw.
    private(set) var dataVersion = 0
    /// Lists and boards of every scope on screen, worked out once per change of the data.
    @ObservationIgnored private var sectionCache: [Scope: [ListSection]] = [:]
    @ObservationIgnored private var columnCache: [String: [BoardColumn]] = [:]
    /// Milestones, epics and roadmaps worked out once per change of the data.
    @ObservationIgnored var planningCache = PlanningCache()

    // Navigation.
    var signedIn: Bool
    private(set) var scope: Scope?
    var viewMode: ViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
            #if os(macOS)
            // Board or list is part of how a view shows, which you may change for yourself. iPhone and iPad have a
            // project on screen per window and say which (`showLayout`).
            if !isFollowingView, oldValue != viewMode, let view = currentView {
                setLayout(viewMode, of: view)
            }
            #endif
            recordNavigation()
        }
    }
    /// Set while `viewMode` follows the view that was opened, which isn't a choice to remember.
    @ObservationIgnored var isFollowingView = false
    private(set) var openItemId: String?
    /// The issue the keyboard focus is on. The issue under the pointer is tracked separately and is not
    /// observed, so moving the mouse over a long list does not redraw it.
    var focusedItemId: String?
    @ObservationIgnored var hoveredItemId: String?

    /// Light, dark, or whatever the system is set to.
    var appearance: AppearanceSetting {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }

    /// Which icon the app shows: in the Dock while it runs on the Mac, on the Home Screen on iOS.
    var appIcon: AppIconChoice {
        didSet {
            UserDefaults.standard.set(appIcon.rawValue, forKey: AppIconChoice.defaultsKey)
            appIcon.apply()
        }
    }

    // Back and forward, like a browser.
    var history: [Location] = []
    var historyIndex = -1
    @ObservationIgnored var isRestoringLocation = false
    /// -1...1 while a two-finger swipe is in progress; positive means "going back".
    var swipeProgress: Double = 0
    /// Bumped when avatar images arrive, so painted rows redraw with them.
    var avatarVersion = 0
    /// Bumped to ask for the settings window from places that cannot open it themselves.
    var settingsRequest = 0
    /// The issue waiting for "Delete?" to be confirmed.
    var deletionCandidate: Item?
    /// Set once to ask whether the Mac's GitHub CLI login may be shared with the iPhone and iPad.
    var offerLoginSharing = false
    /// Waiting for "Sign out everywhere?" to be confirmed, on the Mac.
    var confirmSignOutEverywhere = false
    /// Bumped when a list section is folded in or out, so the list redraws.
    var collapseVersion = 0
    /// Parents (node ids) whose sub-issues are folded away under them in lists and on boards. Kept on this device.
    @ObservationIgnored var foldedParents = Set(UserDefaults.standard.stringArray(forKey: "foldedSubIssues") ?? []) {
        didSet { UserDefaults.standard.set(Array(foldedParents), forKey: "foldedSubIssues") }
    }
    /// Epics (node ids) whose issues are folded away under their header on boards and in their lists. Kept on
    /// this device.
    @ObservationIgnored var foldedEpics = Set(UserDefaults.standard.stringArray(forKey: "foldedEpicGroups") ?? []) {
        didSet { UserDefaults.standard.set(Array(foldedEpics), forKey: "foldedEpicGroups") }
    }
    /// A new issue that was closed before it was created, kept for the next time the dialog opens.
    @ObservationIgnored var unsentNewIssue: NewIssueDraft?
    /// A title typed into a picker before choosing to create a new issue instead, for the dialog to start with.
    @ObservationIgnored var newIssueTitle: String?
    /// The milestone and kind a new issue starts with, when it is begun from a milestone or the roadmap.
    @ObservationIgnored var newIssuePlan: NewIssuePlan?
    /// What a new issue starts with when it is begun in a view's column or group.
    @ObservationIgnored var newIssuePreset: NewIssuePreset?
    /// A milestone waiting for "Complete?" to be answered.
    var milestoneToComplete: MilestoneRef?
    /// On iPhone and iPad: the milestone dialog asked for from a picker, which the window shows as a sheet.
    var milestoneEditorRequest: MilestoneEditorRequest?
    /// On iPhone and iPad: the last milestone renamed or completed, for the window's screens to follow.
    var milestoneMove: MilestoneMove?
    /// Timeline or list, as last chosen for the roadmap on this device.
    var roadmapLayout: RoadmapLayout = RoadmapLayout(rawValue: UserDefaults.standard.string(forKey: "roadmap.layout") ?? "") ?? .timeline {
        didSet { UserDefaults.standard.set(roadmapLayout.rawValue, forKey: "roadmap.layout") }
    }
    /// How much time the roadmap's timeline shows at once.
    var roadmapZoom: RoadmapZoom = RoadmapZoom(rawValue: UserDefaults.standard.string(forKey: "roadmap.zoom") ?? "") ?? .months {
        didSet { UserDefaults.standard.set(roadmapZoom.rawValue, forKey: "roadmap.zoom") }
    }
    /// The project opened last, which the sidebar shows while the Inbox, My Issues or a repository is on screen.
    var lastProjectId: String? = UserDefaults.standard.string(forKey: "selectedProject")
    /// The view open in each project, by project id.
    var selectedViewIds: [String: String] = UserDefaults.standard.dictionary(forKey: "views.selected") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(selectedViewIds, forKey: "views.selected") }
    }
    /// How you chose to see a view, where it differs from the view on GitHub, by view id.
    var viewDisplays: [String: ViewDisplay] = AppModel.decoded("views.display") ?? [:] {
        didSet { AppModel.store(viewDisplays, "views.display") }
    }
    /// Filters changed here and not saved to GitHub yet, by view id, as GitHub keeps unsaved changes to a view.
    var draftFilters: [String: String] = UserDefaults.standard.dictionary(forKey: "views.drafts") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(draftFilters, forKey: "views.drafts") }
    }
    /// What GitHub said an unsaved filter matches, for filters with parts only GitHub understands, by view id.
    var draftMatches: [String: (filter: String, ids: Set<String>)] = [:]
    /// Views being saved to GitHub right now.
    var savingViewIds: Set<String> = []
    /// Bumped to open the filter menu, the Display options or a new view from a key or the command palette.
    var filterMenuRequest = 0
    /// The property the next filter menu opens on, for the debug remote and a chip's values.
    @ObservationIgnored var filterMenuStart: String?
    var displayMenuRequest = 0
    var newViewRequest = 0
    /// Bumped to open the icon picker of the project at the top of the sidebar, from the command palette.
    var projectIconRequest = 0
    /// Filter contexts of projects, worked out once per change of the data.
    @ObservationIgnored var filterContexts: [String: FilterContext] = [:]
    /// Projects tucked away in the sidebar. They can still be found in the command palette.
    var hiddenProjectIds = Set(UserDefaults.standard.stringArray(forKey: "hiddenProjects") ?? []) {
        didSet { UserDefaults.standard.set(Array(hiddenProjectIds), forKey: "hiddenProjects") }
    }
    /// Repositories tucked away in the sidebar, like hidden projects.
    var hiddenRepositoryIds = Set(UserDefaults.standard.stringArray(forKey: "hiddenRepositories") ?? []) {
        didSet { UserDefaults.standard.set(Array(hiddenRepositoryIds), forKey: "hiddenRepositories") }
    }
    var overlay: Overlay? {
        didSet {
            if overlay != nil, overlay != oldValue { overlayOpenedAt = Date() }
        }
    }
    /// When the current dialog or palette opened, and keys typed before its text field had focus.
    @ObservationIgnored var overlayOpenedAt: Date?
    #if os(macOS)
    @ObservationIgnored var heldKeys: [NSEvent] = []
    @ObservationIgnored var heldKeysTimer: Timer?
    /// The app's main window, to tell it apart from popovers and the settings window.
    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored var keyMonitorToken: Any?
    /// The start of a two-finger swipe, held back until it is clear whether it goes back or forward or scrolls.
    @ObservationIgnored var pendingSwipe: PendingSwipe?
    #endif
    /// Set while a board drag is in progress so keyboard shortcuts stay out of the way.
    var isDragging = false
    /// Bumped when Escape is pressed during a drag.
    var dragCancelToken = 0
    /// Bumped when the keyboard moves the focus, so lists can scroll it into view.
    var focusScrollToken = 0
    /// Issues picked to change together (X, ⌘-click, Shift-click).
    var selectedIds: Set<String> = []
    /// Where a Shift-click or Shift-arrow range starts, and the range it added last.
    @ObservationIgnored var selectionAnchorId: String?
    @ObservationIgnored var selectionRange: Set<String> = []
    /// The issue shown in the quick look that Space opens.
    var peekItemId: String?

    // The Inbox.
    /// For you or Watching, as last chosen on this device.
    var inboxBucket: InboxBucket {
        didSet { UserDefaults.standard.set(inboxBucket.rawValue, forKey: "inbox.bucket") }
    }
    /// The entry whose issue is shown beside the list.
    var inboxSelectedId: String?
    /// Entries picked to act on together (⌘-click, Shift-click).
    var inboxPicked: Set<String> = []
    @ObservationIgnored var inboxPickAnchor: String?
    /// The last archive or unsubscribe, which can be undone for a few seconds.
    var inboxUndo: InboxUndo?
    /// Bumped when a snoozed entry is due back, so the Inbox shows it.
    var inboxClock = Date()
    @ObservationIgnored var inboxWake: Task<Void, Never>?
    /// Labels and assignable people of repositories none of your boards use, for issues of them.
    var otherRepoMeta: [String: (labels: [LabelRef], people: [Person])] = [:]
    /// Bumped to open the snooze menu of what is selected in the Inbox (H, or "Pick a Date…" in the right-click menu).
    var inboxSnoozeRequest = InboxSnoozeRequest()
    #if os(macOS)
    /// The number of unread Inbox entries on the app's icon in the Dock.
    var showsDockBadge = UserDefaults.standard.object(forKey: "inbox.dockBadge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsDockBadge, forKey: "inbox.dockBadge") }
    }
    #endif
    /// Whether finishing the last open sub-issue of a parent marks the parent done too, as Linear can.
    var completesParents = UserDefaults.standard.object(forKey: "subIssues.completeParent") as? Bool ?? true {
        didSet { UserDefaults.standard.set(completesParents, forKey: "subIssues.completeParent") }
    }
    /// Whether starting work on an issue starts its epic too.
    var startsEpics = UserDefaults.standard.object(forKey: "epics.startWithWork") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startsEpics, forKey: "epics.startWithWork") }
    }

    /// Comments and sub-issues of the issues on screen, one model per issue, with how many views show it.
    @ObservationIgnored private var details: [String: (model: IssueDetailModel, users: Int)] = [:]

    @ObservationIgnored private var dataObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored var pendingGoTo: Date?
    /// M was pressed: B, X or P next marks the issue as blocked, blocking, or a sub-issue, as in Linear.
    @ObservationIgnored var pendingMark: Date?
    @ObservationIgnored var lifecycleObservers: [NSObjectProtocol] = []

    static let demoKey = "demo.active"

    /// The one model of the app. Shared so a notification's button can act even when the app was launched in
    /// the background for it, before any window exists.
    public static let shared: AppModel = {
        #if DEBUG
        // UI tests start from a clean slate: no remembered tab, folded sections or recent issues. Before the model
        // exists, since its properties start from what was remembered.
        if UserDefaults.standard.bool(forKey: "uiTestReset"), let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        #endif
        return AppModel()
    }()

    /// Reminders of due issues, scheduled on this device.
    var notifier: Notifier { Notifier.shared }

    /// An issue to bring up from outside the app, such as a tapped notification; the iPhone and iPad navigation
    /// picks it up.
    var revealItemId: String?

    private init() {
        let demo = UserDefaults.standard.bool(forKey: Self.demoKey)
        let database: AppDatabase
        do {
            database = demo ? try DemoData.database() : try AppDatabase.onDisk()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        db = database
        personal = PersonalStore(persistent: !demo)
        projectLooks = ProjectLooks(persistent: !demo, initial: demo ? DemoData.looks : [:])
        auth = AuthStore()
        // Logins saved by earlier versions move to iCloud Keychain, and a login shared by another device is used.
        if auth.method == .keychain { KeychainTokenStore.migrateToShared() }
        if !demo { auth.adoptSharedLogin() }
        let status = SyncStatus()
        self.status = status
        engine = SyncEngine(db: database, api: Self.api(auth), status: status, demo: demo)
        isDemo = demo
        signedIn = demo || auth.isSignedIn
        viewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .board
        inboxBucket = InboxBucket(rawValue: UserDefaults.standard.string(forKey: "inbox.bucket") ?? "") ?? .forYou
        appearance = AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        #if os(macOS)
        appIcon = AppIconChoice(rawValue: UserDefaults.standard.string(forKey: AppIconChoice.defaultsKey) ?? "") ?? .standard
        #else
        appIcon = AppIconChoice.current
        #endif
        appearance.apply()
        #if os(macOS)
        appIcon.apply()
        // A picture in the Dock doesn't follow light and dark by itself, so it is set again when the system switches.
        _ = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appIcon.apply() }
        }
        #endif
        startObserving()
        restoreScope()
        scheduleInboxWake()
        #if os(macOS)
        installKeyMonitor()
        installNavigationMonitors()
        #if DEBUG
        DebugRemote.startIfRequested(model: self)
        #endif
        #endif
        if signedIn { startSyncing() }
        Notifier.shared.attach(self)
    }

    private static func api(_ auth: AuthStore) -> GitHubAPI {
        GitHubAPI(client: GraphQLClient(tokenSource: auth))
    }

    // MARK: Session

    func startSyncing() {
        let engine = self.engine
        let project = currentProjectId
        Task {
            await engine.setActiveProject(project)
            await engine.start()
        }
        if pathMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in await self?.engine.kick() }
            }
            monitor.start(queue: .global(qos: .utility))
            pathMonitor = monitor
        }
        if lifecycleObservers.isEmpty {
            installLifecycleObservers()
        }
    }

    func completeSignIn() {
        signedIn = true
        startSyncing()
    }

    /// Signs out of this device. With `everywhere`, the login shared through iCloud Keychain is removed too,
    /// which signs out the user's other devices as well.
    func signOut(everywhere: Bool = false) {
        if isDemo {
            leaveDemo()
            return
        }
        Task {
            await engine.stop()
            await auth.signOut(everywhere: everywhere)
            try? db.wipe()
            resetNavigation()
            signedIn = false
            status.phase = .idle
            status.notices = []
        }
    }

    private func resetNavigation() {
        scope = nil
        openItemId = nil
        focusedItemId = nil
        inboxSelectedId = nil
        inboxPicked = []
        inboxUndo = nil
        otherRepoMeta = [:]
        history = []
        historyIndex = -1
        overlay = nil
        deletionCandidate = nil
        details = [:]
    }

    // MARK: Sample data

    /// Shows the built-in sample project, without a GitHub account. Changes stay on this device.
    func enterDemo() {
        guard !isDemo else { return }
        let old = engine
        Task {
            await old.stop()
            do {
                switchDatabase(to: try DemoData.database(), demo: true)
                UserDefaults.standard.set(true, forKey: Self.demoKey)
                signedIn = true
                startSyncing()
            } catch {
                status.post(Notice(title: String(localized: .sampleDataCouldNotLoad), message: error.localizedDescription, isWarning: true))
            }
        }
    }

    func leaveDemo() {
        guard isDemo else { return }
        let old = engine
        Task {
            await old.stop()
            UserDefaults.standard.removeObject(forKey: Self.demoKey)
            if let disk = try? AppDatabase.onDisk() {
                switchDatabase(to: disk, demo: false)
            }
            signedIn = auth.isSignedIn
            if signedIn { startSyncing() }
        }
    }

    private func switchDatabase(to database: AppDatabase, demo: Bool) {
        dataObservation = nil
        db = database
        engine = SyncEngine(db: database, api: Self.api(auth), status: status, demo: demo)
        isDemo = demo
        personal = PersonalStore(persistent: !demo)
        projectLooks = ProjectLooks(persistent: !demo, initial: demo ? DemoData.looks : [:])
        resetNavigation()
        viewer = nil
        projects = []
        allItems = []
        options = []
        repos = []
        milestones = []
        views = []
        fields = []
        outbox = []
        links = []
        inboxEntries = []
        selfAssignedEntries = []
        inboxMeta = InboxMeta()
        status.phase = .idle
        status.notices = []
        status.lastSyncedAt = nil
        startObserving()
        restoreScope()
    }

    // MARK: Observing the database

    struct Snapshot {
        var viewer: Viewer?
        var projects: [Project]
        var items: [Item]
        var options: [FieldOption]
        var repos: [RepoRef]
        var outbox: [OutboxEntry]
        var links: [LinkedIssue]
        var inbox: [InboxEntry]
        var inboxMeta: InboxMeta
        var milestones: [Milestone]
        var views: [ProjectView]
        var fields: [ProjectField]

        /// Without the self-test's project (`Project.sandboxTitle`) and what only its repositories hold: issues on
        /// no board and notifications. The app you use leaves it out; debug builds keep it for the test tools.
        func withoutSandbox() -> Snapshot {
            let sandbox = Set(projects.filter(\.isSandbox).map(\.id))
            guard !sandbox.isEmpty else { return self }
            let elsewhere = Set(repos.filter { !sandbox.contains($0.projectId) }.map(\.id))
            let own = repos.filter { sandbox.contains($0.projectId) && !elsewhere.contains($0.id) }
            let ownIds = Set(own.map(\.id))
            let ownNames = Set(own.map(\.nameWithOwner))
            var result = self
            result.projects.removeAll { sandbox.contains($0.id) }
            result.repos.removeAll { sandbox.contains($0.projectId) }
            result.items.removeAll { item in
                if let projectId = item.projectId { return sandbox.contains(projectId) }
                return item.repoId.map(ownIds.contains) ?? false
            }
            result.options.removeAll { sandbox.contains($0.projectId) }
            result.views.removeAll { sandbox.contains($0.projectId) }
            result.fields.removeAll { sandbox.contains($0.projectId) }
            result.milestones.removeAll { ownIds.contains($0.repoId) }
            result.inbox.removeAll { ownNames.contains($0.repo) }
            return result
        }
    }

    nonisolated static func fetchSnapshot(_ db: Database) throws -> Snapshot {
        Snapshot(
            viewer: try KV.viewer(db),
            projects: try Project
                .order(Column("closed"), Column("ownerLogin").collating(.localizedCaseInsensitiveCompare), Column("title").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db),
            items: try Item.order(Column("position")).fetchAll(db),
            options: try FieldOption.order(Column("position")).fetchAll(db),
            repos: try RepoRef.order(Column("nameWithOwner")).fetchAll(db),
            outbox: try OutboxEntry.order(Column("id")).fetchAll(db),
            links: try LinkedIssue.order(Column("position")).fetchAll(db),
            inbox: try InboxEntry.order(Column("updatedAt").desc).fetchAll(db),
            inboxMeta: try InboxMeta.read(db),
            milestones: try Milestone.order(Column("repoId"), Column("number")).fetchAll(db),
            views: try ProjectView.order(Column("projectId"), Column("position")).fetchAll(db),
            fields: try ProjectField.order(Column("projectId"), Column("position")).fetchAll(db)
        )
    }

    private func startObserving() {
        let observation = ValueObservation.tracking { try Self.fetchSnapshot($0) }
        dataObservation = observation.start(
            in: db.reader,
            scheduling: .immediate,
            onError: { error in print("Database observation failed: \(error)") },
            onChange: { [weak self] snapshot in
                MainActor.assumeIsolated { self?.apply(snapshot) }
            }
        )
    }

    /// Reads the database right now instead of waiting for the observation, so a user action shows in the same frame.
    func reloadNow() {
        if let snapshot = try? db.reader.read({ try Self.fetchSnapshot($0) }) {
            apply(snapshot)
        }
        for entry in details.values { entry.model.reload() }
    }

    private func apply(_ snapshot: Snapshot) {
        #if !DEBUG
        let snapshot = snapshot.withoutSandbox()
        #endif
        if viewer != snapshot.viewer { viewer = snapshot.viewer }
        var listed = snapshot.projects
        #if DEBUG
        // For screenshots and demos: show a single project and hide the rest.
        if let only = UserDefaults.standard.string(forKey: "debugOnlyProject") {
            listed = listed.filter { $0.title == only }
        }
        #endif
        if projects != listed { projects = listed }
        if options != snapshot.options { options = snapshot.options }
        if repos != snapshot.repos { repos = snapshot.repos }
        if allItems != snapshot.items { allItems = snapshot.items }
        outbox = snapshot.outbox
        noteOwnAssignments(in: snapshot.outbox)
        if links != snapshot.links { links = snapshot.links }
        let threads = snapshot.inbox.filter { !$0.isSelfAssigned }
        let assigned = snapshot.inbox.filter(\.isSelfAssigned)
        if inboxEntries != threads { inboxEntries = threads }
        if selfAssignedEntries != assigned { selfAssignedEntries = assigned }
        if inboxMeta != snapshot.inboxMeta { inboxMeta = snapshot.inboxMeta }
        if milestones != snapshot.milestones { milestones = snapshot.milestones }
        if views != snapshot.views { views = snapshot.views }
        if fields != snapshot.fields { fields = snapshot.fields }
        if scope == nil { restoreScope() }
        rebuild()
        notifier.scheduleSoon()
    }

    // MARK: Issue detail

    /// The comments and sub-issues of one issue, kept in step with the database while a view shows it.
    func detail(for contentId: String) -> IssueDetailModel {
        if let existing = details[contentId] { return existing.model }
        let model = IssueDetailModel(contentId: contentId, db: db)
        details[contentId] = (model, 0)
        return model
    }

    /// An issue came on screen: fetch its comments and sub-issues now and keep them fresh while it shows.
    func detailAppeared(_ item: Item) {
        guard let contentId = item.contentId else { return }
        _ = detail(for: contentId)
        details[contentId]?.users += 1
        let projectId = item.projectId
        let repoId = item.repoId
        let fetchable = item.kind != .draft && !item.isLocalOnly
        let engine = self.engine
        Task {
            await engine.setWatchedIssue(fetchable ? contentId : nil)
            // Fetch comments and sub-issues right away rather than at the next sync cycle.
            if fetchable { try? await engine.loadIssueDetail(contentId: contentId) }
            if let repoId { try? await engine.loadRepoMeta(projectId: projectId, repoId: repoId) }
        }
    }

    func detailDisappeared(_ item: Item) {
        guard let contentId = item.contentId, let entry = details[contentId] else { return }
        if entry.users <= 1 {
            details[contentId] = nil
            let engine = self.engine
            Task { await engine.unwatchIssue(contentId) }
        } else {
            details[contentId]?.users -= 1
        }
    }

    // MARK: Derived data

    /// The board on screen: a project, or one of its milestones, which shows the same columns.
    var currentProjectId: String? {
        switch scope {
        case .project(let id): id
        case .milestone(let id, _): id
        default: nil
        }
    }

    /// The board the screen belongs to, the roadmap included.
    var scopeProjectId: String? {
        scope?.projectId
    }

    /// The milestone on screen, by title.
    var currentMilestoneTitle: String? {
        if case .milestone(_, let title) = scope { return title }
        return nil
    }

    var currentProject: Project? {
        currentProjectId.flatMap { id in projects.first { $0.id == id } }
    }

    var currentRepositoryId: String? {
        if case .repository(let id) = scope { return id }
        return nil
    }

    var currentRepository: RepoRef? {
        currentRepositoryId.flatMap(repository(id:))
    }

    func repository(id: String) -> RepoRef? {
        repos.first { $0.id == id }
    }

    /// Repositories in the sidebar: those your open boards use, by name. Their issues are all read, so the ones
    /// on none of your boards show up too.
    var boardRepositories: [RepoRef] {
        let open = Set(openProjects.map(\.id))
        var seen = Set<String>()
        return repos
            .filter { open.contains($0.projectId) && seen.insert($0.id).inserted }
            .sorted { $0.shortName.localizedCaseInsensitiveCompare($1.shortName) == .orderedAscending }
    }

    /// A repository's name, with its owner when another one in the sidebar has the same name.
    func displayName(of repo: RepoRef) -> String {
        let twins = boardRepositories.filter { $0.shortName.caseInsensitiveCompare(repo.shortName) == .orderedSame }
        return twins.count > 1 ? repo.nameWithOwner : repo.shortName
    }

    /// True until the open project has been fetched from GitHub once.
    var isLoadingProject: Bool {
        scopeProjectId.flatMap { id in projects.first { $0.id == id } }.map { $0.lastSyncedAt == nil } ?? false
    }

    /// True until the repository on screen has been read from GitHub once since the app started.
    var isLoadingRepository: Bool {
        guard let id = currentRepositoryId, !isDemo else { return false }
        return !status.readRepositories.contains(id)
    }

    func isLoading(projectId: String) -> Bool {
        projects.first { $0.id == projectId }.map { $0.lastSyncedAt == nil } ?? false
    }

    var openItem: Item? {
        openItemId.flatMap { id in allItems.first { $0.id == id } }
    }

    /// The project the sidebar is about: the one on screen, or the one used last.
    var sidebarProject: Project? {
        let id = scope?.projectId ?? lastProjectId
        return openProjects.first { $0.id == id }
            ?? openProjects.first { !hiddenProjectIds.contains($0.id) } ?? openProjects.first
    }

    /// Projects shown in lists and the sidebar: the open ones.
    var openProjects: [Project] {
        projects.filter { !$0.closed }
    }

    /// Items of a scope, in board order. Issues on none of your boards come first, newest first.
    /// Epics are planned on the roadmap, as Linear's projects are, so boards and lists leave them out.
    func items(in scope: Scope) -> [Item] {
        switch scope {
        case .project(let id):
            // A project shows the view open in it, filtered as on GitHub.
            if let view = currentView(projectId: id) { return items(of: view) }
            return allItems.filter { $0.projectId == id && !$0.isEpic }
        case .myIssues:
            guard let login = viewer?.login else { return [] }
            return allItems.filter { item in !item.isEpic && item.assignees.contains { $0.login == login } }
        case .inbox:
            return []
        case .repository(let id):
            // An issue on two boards is one issue here. Issues closed long ago stay on their boards only.
            let cutoff = Date().addingTimeInterval(-SyncEngine.closedIssueWindow)
            var seen = Set<String>()
            return allItems.filter { item in
                guard item.repoId == id, item.kind == .issue, !item.isEpic else { return false }
                if item.isClosed, let closed = item.closedAt, closed < cutoff { return false }
                return seen.insert(item.contentId ?? item.id).inserted
            }
        case .milestone(let id, let title):
            return allItems.filter { $0.projectId == id && !$0.isEpic && milestoneTitle(of: $0) == title }
        case .roadmap(let id):
            return epics(projectId: id)
        }
    }

    /// Items of the current scope, in board order.
    var scopedItems: [Item] {
        scope.map { items(in: $0) } ?? []
    }

    func project(of item: Item) -> Project? {
        projects.first { $0.id == item.projectId }
    }

    func statusOptions(projectId: String?) -> [FieldOption] {
        guard let projectId else { return [] }
        return options.filter { $0.projectId == projectId && $0.kind == .status }
    }

    func priorityOptions(projectId: String?) -> [FieldOption] {
        guard let projectId else { return [] }
        return options.filter { $0.projectId == projectId && $0.kind == .priority }
    }

    func statusOption(of item: Item) -> FieldOption? {
        guard let id = item.statusId else { return nil }
        return options.first { $0.id == id && $0.projectId == item.projectId && $0.kind == .status }
    }

    func priorityOption(of item: Item) -> FieldOption? {
        guard let id = item.priorityId else { return nil }
        return options.first { $0.id == id && $0.projectId == item.projectId && $0.kind == .priority }
    }

    func priorityLevel(of item: Item) -> PriorityLevel {
        priorityOption(of: item)?.priorityLevel ?? .none
    }

    func glyph(of item: Item) -> StatusGlyph {
        guard item.isOnBoard else { return .withoutProject(item) }
        return glyph(projectId: item.projectId, optionId: item.statusId)
    }

    /// GitHub reuses option ids across projects (every default "Todo" has the same one), so glyphs are keyed per project.
    func glyph(projectId: String?, optionId: String?) -> StatusGlyph {
        guard let projectId else { return .none }
        return optionId.flatMap { glyphs["\(projectId)/\($0)"] } ?? .none
    }

    func repos(projectId: String?) -> [RepoRef] {
        guard let projectId else { return [] }
        return repos.filter { $0.projectId == projectId }
    }

    func repo(of item: Item) -> RepoRef? {
        repos.first { $0.id == item.repoId && (item.projectId == nil || $0.projectId == item.projectId) }
    }

    /// Boards an issue on none of them can go on: the boards its repository is on, or else every board you can
    /// change.
    func boards(toAdd item: Item) -> [Project] {
        let editable = openProjects.filter { $0.viewerCanUpdate }
        let linked = editable.filter { project in repos.contains { $0.projectId == project.id && $0.id == item.repoId } }
        return linked.isEmpty ? editable : linked
    }

    /// The boards a repository's issues are on, for a new issue created in it.
    func boards(ofRepository repoId: String) -> [Project] {
        openProjects.filter { project in project.viewerCanUpdate && repos.contains { $0.projectId == project.id && $0.id == repoId } }
    }

    /// The project item for an issue's node id, if that issue is on a board we know.
    func item(contentId: String) -> Item? {
        allItems.first { $0.contentId == contentId }
    }

    /// A card, or an issue seen only in the Inbox.
    func item(id: String) -> Item? {
        allItems.first { $0.id == id } ?? detachedItem(id: id)
    }

    var pendingCount: Int {
        outbox.filter { $0.state == .pending }.count
    }

    func conflict(for item: Item) -> [OutboxEntry] {
        outbox.filter { $0.state == .conflict && $0.mutation.contentId == item.contentId }
    }

    /// The board of a project: one column per status, plus "No status" when cards have none.
    func columns(projectId: String) -> [BoardColumn] {
        columns(for: .project(projectId))
    }

    /// The board of a project or one of its milestones. A milestone leaves out the columns of the backlog while
    /// they are empty: its issues are planned already.
    func columns(for scope: Scope) -> [BoardColumn] {
        _ = dataVersion
        guard let projectId = scope.projectId else { return [] }
        let key: String
        var view: ProjectView?
        switch scope {
        case .milestone(_, let title): key = "\(projectId)\u{1F}\(title)"
        case .project:
            view = currentView(projectId: projectId)
            key = view.map { "\(projectId)\u{1F}view\u{1F}\($0.id)" } ?? projectId
        default: key = projectId
        }
        if let cached = columnCache[key] { return cached }
        let items = self.items(in: scope)
        if let view, let field = columnField(of: view), field.id != currentStatusFieldId(projectId: projectId) {
            let result = valueColumns(items, field: field, view: view)
            columnCache[key] = result
            return result
        }
        let inMilestone = if case .milestone = scope { true } else { false }
        let result = statusColumns(projectId: projectId, items: items, inMilestone: inMilestone)
        columnCache[key] = result
        return result
    }

    /// One column per status, plus "No status" when cards have none. A milestone leaves out the columns of the
    /// backlog while they are empty.
    func statusColumns(projectId: String, items: [Item], inMilestone: Bool = false) -> [BoardColumn] {
        let statuses = statusOptions(projectId: projectId)
        let known = Set(statuses.map(\.id))
        var result: [BoardColumn] = []
        let unsorted = items.filter { $0.statusId == nil || !known.contains($0.statusId!) }
        // The issues of an epic stand together in each column, under a header of the epic.
        func arranged(_ items: [Item]) -> (items: [Item], nesting: Nesting) {
            Nesting.arrange(items, folded: foldedParents, epic: { self.epic(of: $0) }, foldedEpics: foldedEpics)
        }
        if !unsorted.isEmpty {
            let (shown, nesting) = arranged(unsorted)
            result.append(BoardColumn(id: BoardColumn.noStatusId, option: nil, glyph: .none, items: shown, nesting: nesting))
        }
        for option in statuses {
            let (shown, nesting) = arranged(items.filter { $0.statusId == option.id })
            if inMilestone, shown.isEmpty, option.statusCategory == .backlog { continue }
            result.append(BoardColumn(
                id: option.id, option: option, glyph: glyph(projectId: projectId, optionId: option.id),
                items: shown, nesting: nesting
            ))
        }
        return result
    }

    /// The list of a scope: sections by status in the order the list shows them, empty ones left out.
    func sections(for scope: Scope) -> [ListSection] {
        _ = dataVersion
        if let cached = sectionCache[scope] { return cached }
        var result: [ListSection] = []
        switch scope {
        case .project(let projectId):
            // The list leads with what is being worked on, like Linear does.
            func rank(_ column: BoardColumn) -> Int {
                guard let option = column.option else { return 3 }
                switch option.statusCategory {
                case .started: return 0
                case .unstarted: return 1
                case .backlog: return 2
                case .completed: return 4
                case .canceled: return 5
                }
            }
            if let view = currentView(projectId: projectId), let grouped = groupedSections(of: view) {
                result = grouped
                break
            }
            // A view whose board has columns other than its statuses still lists its issues by status.
            let statusBoard = currentView(projectId: projectId) == nil
                ? columns(projectId: projectId)
                : statusColumns(projectId: projectId, items: items(in: scope))
            let ordered = statusBoard.enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                if ra != rb { return ra < rb }
                // Within "started", later columns (closer to done) come first.
                return ra == 0 ? a.offset > b.offset : a.offset < b.offset
            }.map(\.element)
            result = ordered.filter { !$0.items.isEmpty }.map {
                ListSection(id: $0.id, title: $0.title, glyph: $0.glyph, option: $0.option, items: $0.items, nesting: $0.nesting)
            }

        case .myIssues, .repository:
            result = groupedByKindOfStatus(items(in: scope))

        case .milestone:
            result = groupedByEpic(items(in: scope))

        case .roadmap(let projectId):
            result = epicsByMilestone(projectId: projectId)

        case .inbox:
            break
        }
        // Sections the user put into their own order keep it.
        let custom = customListOrder(for: scope)
        if !custom.isEmpty {
            result = result.enumerated().sorted { a, b in
                let ia = custom.firstIndex(of: a.element.id) ?? Int.max
                let ib = custom.firstIndex(of: b.element.id) ?? Int.max
                return ia != ib ? ia < ib : a.offset < b.offset
            }.map(\.element)
        }
        sectionCache[scope] = result
        return result
    }

    /// Issues from several boards, grouped by what their status means. Issues on none of your boards lead, since
    /// they wait for someone to put them on one; when there are none, the group isn't there.
    private func groupedByKindOfStatus(_ items: [Item]) -> [ListSection] {
        enum Group: CaseIterable {
            case noProject, started, unstarted, backlog, noStatus, completed, canceled
        }
        func group(of item: Item) -> Group {
            guard item.isOnBoard else {
                if !item.isClosed { return .noProject }
                return item.stateReason == "NOT_PLANNED" ? .canceled : .completed
            }
            switch statusOption(of: item)?.statusCategory {
            case .started: return .started
            case .unstarted: return .unstarted
            case .backlog: return .backlog
            case .completed: return .completed
            case .canceled: return .canceled
            case nil: return .noStatus
            }
        }
        let grouped = Dictionary(grouping: items, by: group)
        return Group.allCases.compactMap { kind in
            guard let matching = grouped[kind], !matching.isEmpty else { return nil }
            // The id stays the same in every language: folded sections and the order of sections are kept by it.
            let (id, title, glyph): (String, LocalizedStringResource, StatusGlyph) = switch kind {
            case .noProject: ("No project", .noProject, .noProject)
            case .started: ("In progress", .statusGroupInProgress, StatusGlyph(category: .started, progress: 0.5, color: Theme.started))
            case .unstarted: ("Todo", .statusGroupTodo, StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody))
            case .backlog: ("Backlog", .statusGroupBacklog, .none)
            case .noStatus: ("No status", .noStatus, .none)
            case .completed: ("Done", .statusGroupDone, StatusGlyph(category: .completed, progress: 1, color: Theme.accent))
            case .canceled: ("Canceled", .statusGroupCanceled, StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary))
            }
            let (shown, nesting) = Nesting.arrange(matching, folded: foldedParents)
            return ListSection(id: id, title: String(localized: title), glyph: glyph, option: nil, items: shown, nesting: nesting)
        }
    }

    func rebuild() {
        var map: [String: StatusGlyph] = [:]
        for project in projects {
            for (optionId, glyph) in StatusGlyph.map(for: statusOptions(projectId: project.id)) {
                map["\(project.id)/\(optionId)"] = glyph
            }
        }
        if glyphs != map { glyphs = map }
        sectionCache = [:]
        columnCache = [:]
        filterContexts = [:]
        planningCache = PlanningCache()
        dataVersion &+= 1

        var newColumns: [BoardColumn] = []
        var newSections: [ListSection] = []
        if let scope {
            newSections = sections(for: scope)
            switch scope {
            case .project, .milestone: newColumns = columns(for: scope)
            default: break
            }
        }
        if columns != newColumns { columns = newColumns }
        if sections != newSections { sections = newSections }
    }

    // MARK: Navigation

    private func restoreScope() {
        guard scope == nil, !projects.isEmpty else { return }
        // The Inbox opens again where it was left, as a project does.
        if UserDefaults.standard.bool(forKey: "inbox.selected") {
            select(.inbox)
            return
        }
        let saved = UserDefaults.standard.string(forKey: "selectedProject")
        // A milestone or the roadmap of that project, if that was on screen last.
        if let data = UserDefaults.standard.data(forKey: "selectedPlanning"),
           let planning = try? JSONDecoder().decode(Scope.self, from: data),
           let projectId = planning.projectId, projectId == saved, projects.contains(where: { $0.id == projectId && !$0.closed }) {
            select(planning)
            return
        }
        let project = projects.first { $0.id == saved }
            ?? projects.first { !$0.closed && !hiddenProjectIds.contains($0.id) }
            ?? projects.first { !$0.closed } ?? projects.first
        if let project { select(.project(project.id)) }
    }

    /// The project used last, or the first one: where G then B goes from the Inbox or My Issues.
    func selectLastProject() {
        let saved = UserDefaults.standard.string(forKey: "selectedProject")
        let project = openProjects.first { $0.id == saved } ?? openProjects.first { !hiddenProjectIds.contains($0.id) }
        if let project { select(.project(project.id)) }
    }

    func select(_ newScope: Scope) {
        scope = newScope
        openItemId = nil
        focusedItemId = nil
        clearSelection()
        peekItemId = nil
        if let id = newScope.projectId {
            UserDefaults.standard.set(id, forKey: "selectedProject")
            lastProjectId = id
            setActiveProject(id)
        }
        switch newScope {
        case .milestone, .roadmap:
            UserDefaults.standard.set(try? JSONEncoder().encode(newScope), forKey: "selectedPlanning")
        default:
            UserDefaults.standard.removeObject(forKey: "selectedPlanning")
        }
        setActiveRepository(currentRepositoryId)
        UserDefaults.standard.set(newScope == .inbox, forKey: "inbox.selected")
        if newScope == .inbox { inboxAppeared() }
        rebuild()
        // A project's view shows as board or list as it was last seen.
        if !isRestoringLocation { followCurrentView() }
        recordNavigation()
    }

    /// The project the engine keeps freshest: the one on screen.
    func setActiveProject(_ id: String?) {
        let engine = self.engine
        Task { await engine.setActiveProject(id) }
    }

    /// The repository on screen, whose issues are read as often as the board on screen.
    func setActiveRepository(_ id: String?) {
        let engine = self.engine
        Task { await engine.setActiveRepository(id) }
    }

    /// Opens an issue. Its comments and sub-issues load when its view appears (see `detailAppeared`).
    /// `replacingHistory` is for moving to the next issue with J or K, which doesn't add a step to go back to.
    func open(_ item: Item, replacingHistory: Bool = false) {
        peekItemId = nil
        focusedItemId = item.id
        openItemId = item.id
        recordNavigation(replacing: replacingHistory)
    }

    /// Back from the open issue, with its back button or Escape: to the issue it was opened from, such as the
    /// parent of a sub-issue, or else to the board or list.
    func leaveIssue() {
        if historyIndex > 0, history.indices.contains(historyIndex) {
            let previous = history[historyIndex - 1]
            if previous.scope == scope, let id = previous.itemId, id != openItemId, allItems.contains(where: { $0.id == id }) {
                goBack()
                return
            }
        }
        closeDetail()
    }

    func closeDetail() {
        guard openItemId != nil else { return }
        // Closing an issue returns to where it was opened from, so Forward brings it back.
        if !isRestoringLocation, historyIndex > 0,
           history[historyIndex - 1] == Location(scope: scope, viewMode: viewMode, itemId: nil) {
            goBack()
            return
        }
        openItemId = nil
        recordNavigation()
    }

    /// Follows an issue whose temporary id was replaced after GitHub created it.
    func follow(remaps: [String: String]) {
        if let id = openItemId, let new = remaps[id] {
            openItemId = new
        }
        if let id = focusedItemId, let new = remaps[id] { focusedItemId = new }
        if let id = hoveredItemId, let new = remaps[id] { hoveredItemId = new }
        for index in history.indices {
            if let id = history[index].itemId, let new = remaps[id] { history[index].itemId = new }
        }
        for (old, new) in remaps {
            guard let entry = details.removeValue(forKey: old) else { continue }
            details[new] = (IssueDetailModel(contentId: new, db: db), entry.users)
        }
        // A label made in a repository none of your boards use.
        for (repoId, meta) in otherRepoMeta where meta.labels.contains(where: { remaps[$0.id] != nil }) {
            otherRepoMeta[repoId]?.labels = meta.labels.map { LabelRef(id: remaps[$0.id] ?? $0.id, name: $0.name, color: $0.color) }
        }
    }

    /// Fetches the avatars of everyone assigned to something in view, once.
    func preloadAvatars(for scope: Scope? = nil) async {
        let items = (scope ?? self.scope).map { self.items(in: $0) } ?? []
        let urls = Set(items.flatMap(\.assignees).compactMap(\.avatarUrl) + [viewer?.avatarUrl].compactMap { $0 })
        var loadedAny = false
        for url in urls where AvatarCache.shared.cached(url) == nil {
            if await AvatarCache.shared.load(url) != nil { loadedAny = true }
        }
        if loadedAny { avatarVersion += 1 }
    }

    func loadRepoMeta(projectId: String?) {
        let ids = repos(projectId: projectId).map(\.id)
        let engine = self.engine
        Task {
            for id in ids { try? await engine.loadRepoMeta(projectId: projectId, repoId: id) }
        }
    }

    /// Labels and people for an issue's pickers: its board's repositories, or its own repository when it is on
    /// no board.
    func loadRepoMeta(for item: Item) {
        guard item.isOnBoard else {
            guard let repoId = item.repoId else { return }
            // A repository none of your boards use has no row to keep them in.
            guard repository(id: repoId) != nil else { return loadOtherRepoMeta(repoId) }
            let engine = self.engine
            Task { try? await engine.loadRepoMeta(projectId: nil, repoId: repoId) }
            return
        }
        loadRepoMeta(projectId: item.projectId)
    }

    func refresh() {
        let engine = self.engine
        Task { await engine.forceRefresh() }
    }

    /// Syncs right away and returns when the round is done, for pull-to-refresh.
    func refreshAndWait() async {
        await engine.forceRefresh()
        await engine.syncNow()
    }

    /// One sync round, for an issue a notification names that this device hasn't seen yet.
    func syncAndWait() async {
        guard signedIn else { return }
        await engine.syncNow()
    }

    /// Sends what is queued now rather than at the next round, for changes made from a notification while
    /// the app is in the background. Offline, they stay queued.
    func sendQueuedChanges() async {
        guard signedIn, !isDemo else { return }
        try? await engine.pushPending()
    }

    /// Brings an issue up from outside the app: its project (or My Issues, where it is listed) and the issue.
    func reveal(_ item: Item) {
        peekItemId = nil
        overlay = nil
        #if os(macOS)
        let home: Scope? = item.projectId.map { .project($0) } ?? item.repoId.map { .repository($0) }
        let listed = scope.map { items(in: $0).contains { $0.id == item.id } } ?? false
        if !listed, let home { select(home) }
        open(item)
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        #else
        revealItemId = item.id
        #endif
    }

    // MARK: Writing

    /// Applies mutations locally and queues them for GitHub. `inserting` are items to keep first, in the same
    /// write, such as an issue only the Inbox knew that is being put on a board.
    func perform(_ mutations: [Mutation], inserting: [Item] = []) {
        guard !mutations.isEmpty else { return }
        let completions = parentCompletions(after: mutations)
        let starts = epicStarts(after: mutations)
        let mutations = mutations + completions.mutations + starts.mutations
        do {
            try db.writer.write { db in
                for item in inserting { try item.insert(db, onConflict: .ignore) }
                for mutation in mutations { try Outbox.enqueue(db, mutation) }
            }
            reloadNow()
            for parent in completions.parents {
                status.post(Notice(
                    title: String(localized: .parentDoneWithSubIssues(number: parent.displayNumber)), message: parent.title,
                    action: .openItem(parent.id)
                ))
            }
            for epic in starts.epics {
                status.post(Notice(
                    title: String(localized: .epicStartedWithIssue(number: epic.displayNumber)), message: epic.title,
                    action: .openItem(epic.id)
                ))
            }
        } catch {
            status.post(Notice(title: String(localized: .changeCouldNotBeSaved), message: error.localizedDescription, isWarning: true))
        }
        let engine = self.engine
        Task { await engine.kick() }
    }

    func resolveConflict(_ entry: OutboxEntry, keepMine: Bool) {
        guard let id = entry.id else { return }
        try? db.writer.write { try Outbox.resolveConflict($0, entryId: id, keepMine: keepMine) }
        reloadNow()
        let engine = self.engine
        Task { await engine.kick() }
    }
}
