import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("An issue's type, shown and changed")
struct IssueTypeTests {
    private static let bug = IssueTypeRef(id: "T-bug", name: "Bug", color: "RED")
    private static let task = IssueTypeRef(id: "T-task", name: "Task", color: "YELLOW")

    private func label(_ name: String) -> LabelRef {
        LabelRef(id: "L-\(name)", name: name, color: "8F96F2")
    }

    private func issue(_ id: String = "issue-1", type: String? = nil, color: String? = nil, labels: [String] = [], repo: String? = "R1") -> Item {
        Item(
            id: "item-\(id)", projectId: "P1", kind: .issue, position: 1024, contentId: id, number: 1, title: id, body: "",
            state: "OPEN", repoId: repo, repo: repo.map { "octo/\($0.lowercased())" }, labels: labels.map(label),
            issueType: type, issueTypeColor: color
        )
    }

    private func database(_ item: Item) throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try Project(
                id: "P1", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true, statusFieldId: nil
            ).insert(db)
            try item.insert(db)
            try SubIssue(id: item.contentId ?? "", parentId: "issue-9", number: 1, title: "Sub", state: "OPEN", position: 0).insert(db)
        }
        return db
    }

    private func set(_ type: IssueTypeRef?, from base: IssueTypeRef?) -> Mutation {
        .setIssueType(.init(
            contentId: "issue-1", typeId: type?.id, name: type?.name, color: type?.color,
            baseName: base?.name, baseColor: base?.color
        ))
    }

    @Test("Cards and rows show a type with its colour, but not Epic, which the epic's icon says")
    func shownType() {
        let shown = issue(type: "Bug", color: "RED").shownType
        #expect(shown?.name == "Bug")
        #expect(shown?.color == "RED")
        #expect(issue(type: "Epic", color: "PURPLE").shownType == nil)
        #expect(issue().shownType == nil)
    }

    @Test("A label named like the type is left out of cards and rows, and only that one")
    func labelsThatRepeatTheType() {
        let typed = issue(type: "Bug", color: "RED", labels: ["bug", "sync"])
        #expect(typed.shownLabels.map(\.name) == ["sync"])
        // The issue itself keeps it: its page lists every label.
        #expect(typed.labels.count == 2)
        #expect(issue(labels: ["bug", "sync"]).shownLabels.map(\.name) == ["bug", "sync"])
        #expect(issue(type: "Epic", labels: ["epic", "sync"]).shownLabels.map(\.name) == ["sync"])
    }

    @Test("A type can be changed on an issue GitHub has, unless it is Epic")
    func whatCanHaveAType() {
        #expect(issue().canHaveIssueType)
        #expect(issue(type: "Bug").canHaveIssueType)
        #expect(!issue(type: "Epic").canHaveIssueType)
        #expect(!issue(repo: nil).canHaveIssueType)
        var draft = issue()
        draft.kind = .draft
        #expect(!draft.canHaveIssueType)
    }

    @Test("An issue known only from another's page shows its type but can't be changed from the row")
    func standIn() {
        var sub = SubIssue(id: "issue-7", parentId: "issue-9", number: 7, title: "Sub", state: "OPEN", position: 0)
        sub.issueType = "Bug"
        sub.issueTypeColor = "RED"
        let item = Item(standingInFor: sub, blockedBy: 0)
        #expect(item.shownType?.name == "Bug")
        #expect(!item.canHaveIssueType)
    }

    @Test("No type comes first; the type the issues share is checked, and none when they differ")
    @MainActor
    func pickerRows() {
        let rows = AppModel.issueTypeItems([Self.task, Self.bug], current: ["Bug"])
        #expect(rows.map(\.id) == ["", "T-task", "T-bug"])
        #expect(rows.map(\.selected) == [false, false, true])
        #expect(rows.map(\.shortcut) == ["0", "1", "2"])
        #expect(AppModel.issueTypeItems([Self.bug], current: [nil]).map(\.selected) == [true, false])
        #expect(AppModel.issueTypeItems([Self.bug], current: [nil, "Bug"]).allSatisfy { !$0.selected })
    }

    @Test("Each issue gets its own repository's type of that name, and only a change is queued")
    @MainActor
    func changes() {
        let other = IssueTypeRef(id: "T-other-bug", name: "Bug", color: "ORANGE")
        let items = [
            issue("issue-1", type: "Task", color: "YELLOW"), issue("issue-2", repo: "R2"),
            issue("issue-3", type: "Bug", color: "RED"), issue("issue-4", repo: "R3"), issue("issue-5", type: "Epic"),
        ]
        let types = { (item: Item) -> [IssueTypeRef] in
            switch item.repoId {
            case "R1": [Self.task, Self.bug]
            case "R2": [other]
            default: [Self.task]
            }
        }
        let changes = AppModel.issueTypeMutations(items, named: "Bug", types: types).compactMap { mutation -> Mutation.SetIssueType? in
            if case .setIssueType(let change) = mutation { change } else { nil }
        }
        #expect(changes.map(\.contentId) == ["issue-1", "issue-2"])
        #expect(changes.map(\.typeId) == ["T-bug", "T-other-bug"])
        #expect(changes[0].baseName == "Task")
        #expect(changes[0].baseColor == "YELLOW")

        let removed = AppModel.issueTypeMutations(items, named: nil, types: types)
        #expect(removed.count == 2)
    }

    @Test("A new type shows on the issue and in its parent's list at once")
    func appliesLocally() throws {
        let db = try database(issue(type: "Task", color: "YELLOW"))
        try db.writer.write { try Outbox.enqueue($0, set(Self.bug, from: Self.task)) }
        let (item, sub) = try db.reader.read { db in
            (try Item.fetchOne(db, key: "item-issue-1")!, try SubIssue.filter(Column("id") == "issue-1").fetchOne(db)!)
        }
        #expect(item.issueType == "Bug")
        #expect(item.issueTypeColor == "RED")
        #expect(item.dirty)
        #expect(sub.issueType == "Bug")
        #expect(sub.issueTypeColor == "RED")
    }

    @Test("Changed twice before sending, it remembers what GitHub has")
    func keepsWhatGitHubHas() throws {
        let db = try database(issue(type: "Task", color: "YELLOW"))
        try db.writer.write { db in
            try Outbox.enqueue(db, set(Self.bug, from: Self.task))
            try Outbox.enqueue(db, set(nil, from: Self.bug))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        guard case .setIssueType(let change) = entries.first?.mutation else {
            Issue.record("Expected a change of the type")
            return
        }
        #expect(change.name == nil)
        #expect(change.baseName == "Task")
        #expect(change.baseColor == "YELLOW")
    }

    @Test("GitHub's list of a repository's types is read with ids and colours")
    func readsTypes() throws {
        let json = #"{"id":"T1","name":"Bug","color":"RED","isEnabled":true}"#
        let type = try JSONDecoder().decode(IssueTypeDTO.self, from: Data(json.utf8))
        #expect(type.ref == Self.bug.withId("T1"))
        let onAnIssue = try JSONDecoder().decode(IssueTypeDTO.self, from: Data(#"{"name":"Bug","color":"RED"}"#.utf8))
        #expect(onAnIssue.ref == nil)
    }

    @Test("The sample data has issues of each type, and some without one")
    func sampleData() throws {
        let items = try DemoData.database().reader.read { try Item.fetchAll($0) }
        let names = Set(items.compactMap(\.issueType))
        #expect(names == ["Bug", "Feature", "Task"])
        #expect(items.contains { $0.issueType == nil && !$0.isEpic })
        #expect(items.filter(\.isEpic).allSatisfy { $0.issueType == nil })
        #expect(items.allSatisfy { ($0.issueType == nil) == ($0.issueTypeColor == nil) })
    }
}

private extension IssueTypeRef {
    func withId(_ id: String) -> IssueTypeRef { IssueTypeRef(id: id, name: name, color: color) }
}
