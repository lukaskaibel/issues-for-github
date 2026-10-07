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
    var items: [Item]

    var title: String { option?.name ?? "No status" }
}

struct ListSection: Identifiable, Equatable {
    var id: String
    var title: String
    var glyph: StatusGlyph
    var option: FieldOption?
    var items: [Item]
}

enum PaletteMode: Hashable {
    case root
    case status(itemId: String)
    case priority(itemId: String)
    case assignees(itemId: String)
    case labels(itemId: String)
    case dueDate(itemId: String)
    case projects
}

enum Overlay: Equatable {
    case palette(PaletteMode)
    case newIssue(statusId: String?, parentItemId: String?)
}

enum ViewMode: String {
    case board
    case list
}

enum Scope: Hashable, Codable {
    case project(String)
    case myIssues
    /// Every issue of a repository, on a board or not. The id is the repository's.
    case repository(String)
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
    private(set) var outbox: [OutboxEntry] = []

    // Derived from the above for the current scope.
    private(set) var columns: [BoardColumn] = []
    private(set) var sections: [ListSection] = []
    private(set) var glyphs: [String: StatusGlyph] = [:]
    /// Bumped whenever lists may look different, so views that read cached lists redraw.
    private(set) var dataVersion = 0
    /// Lists and boards of every scope on screen, worked out once per change of the data.
    @ObservationIgnored private var sectionCache: [Scope: [ListSection]] = [:]
    @ObservationIgnored private var columnCache: [String: [BoardColumn]] = [:]

    // Navigation.
    var signedIn: Bool
    private(set) var scope: Scope?
    var viewMode: ViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
            recordNavigation()
        }
    }
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
    /// A new issue that was closed before it was created, kept for the next time the dialog opens.
    @ObservationIgnored var unsentNewIssue: NewIssueDraft?
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

    /// Comments and sub-issues of the issues on screen, one model per issue, with how many views show it.
    @ObservationIgnored private var details: [String: (model: IssueDetailModel, users: Int)] = [:]

    @ObservationIgnored private var dataObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored var pendingGoTo: Date?
    @ObservationIgnored var lifecycleObservers: [NSObjectProtocol] = []

    static let demoKey = "demo.active"

    /// The one model of the app. Shared so a notification's button can act even when the app was launched in
    /// the background for it, before any window exists.
    public static let shared = AppModel()

    /// Reminders of due issues, scheduled on this device.
    var notifier: Notifier { Notifier.shared }

    /// An issue to bring up from outside the app, such as a tapped notification; the iPhone and iPad navigation
    /// picks it up.
    var revealItemId: String?

    private init() {
        #if DEBUG
        // UI tests start from a clean slate: no remembered tab, folded sections or recent issues.
        if UserDefaults.standard.bool(forKey: "uiTestReset"), let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        #endif
        let demo = UserDefaults.standard.bool(forKey: Self.demoKey)
        let database: AppDatabase
        do {
            database = demo ? try DemoData.database() : try AppDatabase.onDisk()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        db = database
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
        appearance = AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        #if os(macOS)
        appIcon = AppIconChoice(rawValue: UserDefaults.standard.string(forKey: AppIconChoice.defaultsKey) ?? "") ?? .standard
        #else
        appIcon = AppIconChoice.current
        #endif
        appearance.apply()
        #if os(macOS)
        appIcon.apply()
        #endif
        startObserving()
        restoreScope()
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
                status.post(Notice(title: "The sample data could not be loaded", message: error.localizedDescription, isWarning: true))
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
        resetNavigation()
        viewer = nil
        projects = []
        allItems = []
        options = []
        repos = []
        outbox = []
        status.phase = .idle
        status.notices = []
        status.lastSyncedAt = nil
        startObserving()
        restoreScope()
    }

    // MARK: Observing the database

    private struct Snapshot {
        var viewer: Viewer?
        var projects: [Project]
        var items: [Item]
        var options: [FieldOption]
        var repos: [RepoRef]
        var outbox: [OutboxEntry]
    }

    private nonisolated static func fetchSnapshot(_ db: Database) throws -> Snapshot {
        Snapshot(
            viewer: try KV.viewer(db),
            projects: try Project
                .order(Column("closed"), Column("ownerLogin").collating(.localizedCaseInsensitiveCompare), Column("title").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db),
            items: try Item.order(Column("position")).fetchAll(db),
            options: try FieldOption.order(Column("position")).fetchAll(db),
            repos: try RepoRef.order(Column("nameWithOwner")).fetchAll(db),
            outbox: try OutboxEntry.order(Column("id")).fetchAll(db)
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

    var currentProjectId: String? {
        if case .project(let id) = scope { return id }
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
        currentProject.map { $0.lastSyncedAt == nil } ?? false
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

    /// Projects shown in lists and the sidebar: the open ones.
    var openProjects: [Project] {
        projects.filter { !$0.closed }
    }

    /// Items of a scope, in board order. Issues on none of your boards come first, newest first.
    func items(in scope: Scope) -> [Item] {
        switch scope {
        case .project(let id): return allItems.filter { $0.projectId == id }
        case .myIssues:
            guard let login = viewer?.login else { return [] }
            return allItems.filter { item in item.assignees.contains { $0.login == login } }
        case .repository(let id):
            // An issue on two boards is one issue here. Issues closed long ago stay on their boards only.
            let cutoff = Date().addingTimeInterval(-SyncEngine.closedIssueWindow)
            var seen = Set<String>()
            return allItems.filter { item in
                guard item.repoId == id, item.kind == .issue else { return false }
                if item.isClosed, let closed = item.closedAt, closed < cutoff { return false }
                return seen.insert(item.contentId ?? item.id).inserted
            }
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

    func item(id: String) -> Item? {
        allItems.first { $0.id == id }
    }

    var pendingCount: Int {
        outbox.filter { $0.state == .pending }.count
    }

    func conflict(for item: Item) -> [OutboxEntry] {
        outbox.filter { $0.state == .conflict && $0.mutation.contentId == item.contentId }
    }

    /// The board of a project: one column per status, plus "No status" when cards have none.
    func columns(projectId: String) -> [BoardColumn] {
        _ = dataVersion
        if let cached = columnCache[projectId] { return cached }
        let items = allItems.filter { $0.projectId == projectId }
        let statuses = statusOptions(projectId: projectId)
        let known = Set(statuses.map(\.id))
        var result: [BoardColumn] = []
        let unsorted = items.filter { $0.statusId == nil || !known.contains($0.statusId!) }
        if !unsorted.isEmpty {
            result.append(BoardColumn(id: BoardColumn.noStatusId, option: nil, glyph: .none, items: unsorted))
        }
        for option in statuses {
            result.append(BoardColumn(
                id: option.id, option: option, glyph: glyph(projectId: projectId, optionId: option.id),
                items: items.filter { $0.statusId == option.id }
            ))
        }
        columnCache[projectId] = result
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
            let ordered = columns(projectId: projectId).enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                if ra != rb { return ra < rb }
                // Within "started", later columns (closer to done) come first.
                return ra == 0 ? a.offset > b.offset : a.offset < b.offset
            }.map(\.element)
            result = ordered.filter { !$0.items.isEmpty }.map {
                ListSection(id: $0.id, title: $0.title, glyph: $0.glyph, option: $0.option, items: $0.items)
            }

        case .myIssues, .repository:
            result = groupedByKindOfStatus(items(in: scope))
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
            let (title, glyph): (String, StatusGlyph) = switch kind {
            case .noProject: ("No project", .noProject)
            case .started: ("In progress", StatusGlyph(category: .started, progress: 0.5, color: Theme.started))
            case .unstarted: ("Todo", StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody))
            case .backlog: ("Backlog", .none)
            case .noStatus: ("No status", .none)
            case .completed: ("Done", StatusGlyph(category: .completed, progress: 1, color: Theme.accent))
            case .canceled: ("Canceled", StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary))
            }
            return ListSection(id: title, title: title, glyph: glyph, option: nil, items: matching)
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
        dataVersion &+= 1

        var newColumns: [BoardColumn] = []
        var newSections: [ListSection] = []
        if let scope {
            newSections = sections(for: scope)
            if case .project(let projectId) = scope { newColumns = columns(projectId: projectId) }
        }
        if columns != newColumns { columns = newColumns }
        if sections != newSections { sections = newSections }
    }

    // MARK: Navigation

    private func restoreScope() {
        guard scope == nil, !projects.isEmpty else { return }
        let saved = UserDefaults.standard.string(forKey: "selectedProject")
        let project = projects.first { $0.id == saved }
            ?? projects.first { !$0.closed && !hiddenProjectIds.contains($0.id) }
            ?? projects.first { !$0.closed } ?? projects.first
        if let project { select(.project(project.id)) }
    }

    func select(_ newScope: Scope) {
        scope = newScope
        openItemId = nil
        focusedItemId = nil
        clearSelection()
        peekItemId = nil
        if case .project(let id) = newScope {
            UserDefaults.standard.set(id, forKey: "selectedProject")
            setActiveProject(id)
        }
        setActiveRepository(currentRepositoryId)
        rebuild()
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

    /// Applies mutations locally and queues them for GitHub.
    func perform(_ mutations: [Mutation]) {
        guard !mutations.isEmpty else { return }
        do {
            try db.writer.write { db in
                for mutation in mutations { try Outbox.enqueue(db, mutation) }
            }
            reloadNow()
        } catch {
            status.post(Notice(title: "That change could not be saved", message: error.localizedDescription, isWarning: true))
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
