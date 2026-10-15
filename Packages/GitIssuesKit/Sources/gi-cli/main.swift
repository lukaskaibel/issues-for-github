import Foundation
@testable import GitIssuesKit
import GRDB

// Development tool: exercises the sync engine against real GitHub data without the UI.
// Uses the GitHub CLI's login. Usage:
//   gi-cli projects
//   gi-cli pull <project title>
//   gi-cli views <project title>   (reads only: what each saved view shows here, next to what GitHub says)
//   gi-cli selftest            (writes to the "Git Issues Sandbox" project only)
//   gi-cli inbox               (reads the notifications; changes nothing)
//   gi-cli inbox read|archive <thread id>   (only for threads of the sandbox project's repositories)

struct CLITokens: TokenSource {
    func token() async throws -> String { try await GitHubCLI.token() }
}

func makeEngine(path: String? = nil) async throws -> (AppDatabase, SyncEngine, SyncStatus, GitHubAPI) {
    let db = try path.map { try AppDatabase.onDisk(at: URL(fileURLWithPath: $0)) } ?? AppDatabase.inMemory()
    let api = GitHubAPI(client: GraphQLClient(tokenSource: CLITokens()))
    let status = await MainActor.run { SyncStatus() }
    return (db, SyncEngine(db: db, api: api, status: status), status, api)
}

func findProject(_ db: AppDatabase, title: String) throws -> Project {
    guard let project = try db.projects().first(where: { $0.title.localizedCaseInsensitiveContains(title) }) else {
        throw CLIError("No project matching \"\(title)\".")
    }
    return project
}

struct CLIError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

func printBoard(_ db: AppDatabase, projectId: String) throws {
    try db.reader.read { db in
        let options = try FieldOption
            .filter(Column("projectId") == projectId && Column("kind") == OptionKind.status.rawValue)
            .order(Column("position")).fetchAll(db)
        let priorities = try FieldOption
            .filter(Column("projectId") == projectId && Column("kind") == OptionKind.priority.rawValue)
            .fetchAll(db)
        let items = try Item.filter(Column("projectId") == projectId).order(Column("position")).fetchAll(db)
        func line(_ item: Item) -> String {
            let priority = priorities.first { $0.id == item.priorityId }?.name ?? "-"
            let labels = item.labels.map(\.name).joined(separator: ",")
            let sub = item.subTotal > 0 ? " [\(item.subCompleted)/\(item.subTotal)]" : ""
            return "    \(item.displayNumber) \(item.title) (\(priority); \(labels); \(item.assignees.map(\.login).joined(separator: ",")))\(sub) \(item.state)\(item.viewerCanDelete ? " deletable" : "")"
        }
        for option in options {
            let cards = items.filter { $0.statusId == option.id }
            print("  \(option.name) [\(option.statusCategory)] — \(cards.count)")
            for card in cards.prefix(6) { print(line(card)) }
        }
        let known = Set(options.map(\.id))
        let none = items.filter { $0.statusId == nil || !known.contains($0.statusId!) }
        if !none.isEmpty {
            print("  No status — \(none.count)")
            for card in none.prefix(6) { print(line(card)) }
        }
    }
}

func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "projects":
        let (db, engine, _, _) = try await makeEngine()
        try await engine.refreshProjects()
        print("Signed in as \(db.viewer()?.login ?? "?")")
        for project in try db.projects() {
            print("  \(project.ownerLogin)/\(project.number)  \(project.title)\(project.closed ? "  (closed)" : "")")
        }

    case "pull":
        guard args.count > 1 else { throw CLIError("Usage: gi-cli pull <project title>") }
        let (db, engine, _, _) = try await makeEngine()
        try await engine.refreshProjects()
        let project = try findProject(db, title: args[1])
        let start = Date()
        try await engine.pull(projectId: project.id)
        print("\(project.title): first pull took \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        try printBoard(db, projectId: project.id)
        let again = Date()
        try await engine.pull(projectId: project.id)
        print("Second pull (nothing changed) took \(String(format: "%.2f", Date().timeIntervalSince(again)))s")

    case "views":
        // Each saved view's filter checked here and by GitHub, to see that both find the same items. Reads only.
        guard args.count > 1 else { throw CLIError("Usage: gi-cli views <project title>") }
        let (db, engine, _, api) = try await makeEngine()
        try await engine.refreshProjects()
        let project = try findProject(db, title: args[1])
        try await engine.pull(projectId: project.id)
        let (views, fields, options, items, viewer) = try await db.reader.read { db in
            (
                try ProjectView.filter(Column("projectId") == project.id).order(Column("position")).fetchAll(db),
                try ProjectField.filter(Column("projectId") == project.id).fetchAll(db),
                try FieldOption.filter(Column("projectId") == project.id).fetchAll(db),
                try Item.filter(Column("projectId") == project.id).fetchAll(db),
                try KV.viewer(db)
            )
        }
        let current = try await db.reader.read { try Project.fetchOne($0, key: project.id) } ?? project
        let byContent = Dictionary(items.compactMap { item in item.contentId.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
        let context = FilterContext(project: current, fields: fields, options: options, viewerLogin: viewer?.login, parentReference: { item in
            guard let number = item.parentNumber else { return nil }
            return "\(item.parentId.flatMap { byContent[$0]?.repo } ?? item.repo ?? "")#\(number)"
        })
        print("\(project.title): \(items.count) items, \(fields.count) fields, \(views.count) views")
        for field in fields where field.kind == .iteration {
            print("  iteration field \(field.name): \(field.iterations.count) iterations, current \(field.iteration(offset: 0, from: .today())?.title ?? "-")")
        }
        var mismatches = 0
        // Filters given after the project's title are checked instead of its views.
        let checked = args.count > 2
            ? args.dropFirst(2).enumerated().map { ProjectView(id: "check-\($0)", projectId: project.id, number: $0, name: "check", layout: .table, filter: $1, position: $0) }
            : views
        for view in checked {
            let filter = ProjectFilter(view.filter)
            let local = Set(items.filter { filter.matches($0, context) }.map(\.id))
            let remote = Set(try await api.matchingItemIds(projectId: project.id, filter: view.filter))
            let needs = filter.needsServer(context)
            let same = local == remote
            if !same, !needs { mismatches += 1 }
            print("  \(view.number) \(view.name) [\(view.layout.rawValue)] \"\(view.filter)\": here \(local.count), GitHub \(remote.count)\(needs ? " (asks GitHub)" : "")\(same ? "" : "  DIFFERENT")")
            if !same {
                func numbers(_ ids: Set<String>) -> String {
                    ids.compactMap { id in items.first { $0.id == id }?.displayNumber ?? id }.sorted().prefix(12).joined(separator: " ")
                }
                print("      only here: \(numbers(local.subtracting(remote)))")
                print("      only on GitHub: \(numbers(remote.subtracting(local)))")
            }
        }
        print(mismatches == 0 ? "Every filter the app reads itself found what GitHub found." : "\(mismatches) filters differ.")

    case "inspect":
        // Opens a database file (running any pending migrations) and reports what is in it.
        guard args.count > 1 else { throw CLIError("Usage: gi-cli inspect <db path>") }
        let db = try AppDatabase.onDisk(at: URL(fileURLWithPath: args[1]))
        try await db.reader.read { db in
            let columns = try db.columns(in: "item").map(\.name)
            print("item columns include viewerCanDelete:", columns.contains("viewerCanDelete"))
            print("projects:", try Project.fetchCount(db), "items:", try Item.fetchCount(db))
            print("items waiting to be fetched again:", try Item.filter(Column("remoteUpdatedAt") == nil).fetchCount(db))
            print("queued changes:", try OutboxEntry.fetchCount(db))
        }

    case "selftest":
        if args.count > 1, args[1] == "views" { try await SelfTest.runViews() } else { try await SelfTest.run() }

    case "inbox":
        let (db, engine, _, api) = try await makeEngine()
        try await engine.refreshProjects()
        let start = Date()
        try await engine.pullInbox()
        print("Inbox read in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        let viewer = db.viewer()?.login
        let (entries, meta) = try await db.reader.read { (try InboxEntry.order(Column("updatedAt").desc).fetchAll($0), try InboxMeta.read($0)) }
        print("access: \(meta.access.rawValue), other notifications on GitHub: \(meta.otherCount)")
        if args.count == 3 {
            // Writes only where the self-test may: threads of the sandbox project's repositories.
            let sandbox = try findProject(db, title: SelfTest.sandboxTitle)
            guard sandbox.title == SelfTest.sandboxTitle else { throw CLIError("Refusing to write outside the sandbox.") }
            let repos = Set(try await api.projectMeta(id: sandbox.id).repos.map(\.nameWithOwner))
            guard let entry = entries.first(where: { $0.id == args[2] }), repos.contains(entry.repo) else {
                throw CLIError("Thread \(args[2]) isn't one of the sandbox's repositories (\(repos.sorted().joined(separator: ", "))).")
            }
            switch args[1] {
            case "read": try await api.markThreadRead(entry.id)
            case "archive": try await api.markThreadDone(entry.id)
            default: throw CLIError("Usage: gi-cli inbox read|archive <thread id>")
            }
            print("\(args[1]): \(entry.label)")
            return
        }
        for entry in entries {
            let summary = entry.summary(viewer: viewer)
            let flags = [
                entry.isSelfAssigned ? "assigned by your account" : entry.unread ? "unread" : nil,
                entry.missing ? "missing" : nil, entry.bucket == .watching ? "watching" : nil,
            ].compactMap { $0 }
            print("  \(entry.id)  \(entry.displayNumber(withRepo: true)) \(entry.title)")
            print("      \(summary.sign.rawValue): \(summary.lead) \(summary.excerpt.map { String($0.prefix(80)) } ?? "")  [\(flags.joined(separator: ", "))] \(entry.activity.count) events")
        }

    default:
        print("Usage: gi-cli projects | pull <project title> | selftest | inbox [read|archive <thread id>]")
    }
}

do {
    try await run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
