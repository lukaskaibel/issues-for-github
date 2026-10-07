import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Queued changes and how they sit on top of data from GitHub")
struct OutboxTests {
    static let projectId = "P1"
    static let statusField = "F-status"

    /// A project with three cards in one column.
    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try Project(
                id: Self.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true, statusFieldId: Self.statusField
            ).insert(db)
            for (index, name) in ["Todo", "Doing", "Done"].enumerated() {
                try FieldOption(
                    id: name.lowercased(), fieldId: Self.statusField, projectId: Self.projectId, kind: .status,
                    name: name, color: "GRAY", descr: "", position: index
                ).insert(db)
            }
            for number in 1...3 {
                try Self.item(number).insert(db)
            }
        }
        return db
    }

    static func item(_ number: Int, status: String = "todo", title: String? = nil) -> Item {
        Item(
            id: "item-\(number)", projectId: projectId, kind: .issue, position: Double(number) * 1024,
            statusId: status, contentId: "issue-\(number)", number: number, title: title ?? "Issue \(number)", body: "",
            state: "OPEN"
        )
    }

    private func setStatus(_ number: Int, to option: String, base: String) -> Mutation {
        .setField(.init(itemId: "item-\(number)", projectId: Self.projectId, fieldId: Self.statusField, kind: .status, optionId: option, base: base))
    }

    private func order(_ db: AppDatabase) throws -> [Int] {
        try db.reader.read { try Item.order(Column("position")).fetchAll($0).compactMap(\.number) }
    }

    @Test func aChangeShowsLocallyAtOnce() throws {
        let db = try makeDatabase()
        try db.writer.write { try Outbox.enqueue($0, setStatus(1, to: "doing", base: "todo")) }
        let item = try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
        #expect(item.statusId == "doing")
        #expect(item.dirty)
    }

    @Test func repeatedChangesToOneFieldCollapseAndKeepTheOriginalBase() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setStatus(1, to: "doing", base: "todo"))
            try Outbox.enqueue(db, setStatus(1, to: "done", base: "doing"))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        guard case .setField(let mutation) = entries[0].mutation else {
            Issue.record("Expected a field change")
            return
        }
        #expect(mutation.optionId == "done")
        #expect(mutation.base == "todo")
    }

    @Test func movingACardPlacesItDirectlyBelowTheOneNamed() throws {
        let db = try makeDatabase()
        try db.writer.write { try Outbox.enqueue($0, .move(.init(itemId: "item-1", projectId: Self.projectId, afterItemId: "item-2"))) }
        #expect(try order(db) == [2, 1, 3])
        try db.writer.write { try Outbox.enqueue($0, .move(.init(itemId: "item-3", projectId: Self.projectId, afterItemId: nil))) }
        #expect(try order(db) == [3, 2, 1])
    }

    @Test func unsentChangesSurviveFreshDataFromGitHub() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setStatus(1, to: "doing", base: "todo"))
            // GitHub's copy arrives: still "todo", but a teammate renamed the issue meanwhile.
            try Self.item(1, status: "todo", title: "Renamed by a teammate").save(db)
            try Outbox.rebase(db)
        }
        let item = try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
        #expect(item.statusId == "doing")
        #expect(item.title == "Renamed by a teammate")
    }

    @Test func labelsAndAssigneesAreAddedAndRemovedIndividually() throws {
        let db = try makeDatabase()
        let bug = LabelRef(id: "L1", name: "bug", color: "ff0000")
        let ui = LabelRef(id: "L2", name: "ui", color: "0000ff")
        try db.writer.write { db in
            try Outbox.enqueue(db, .editLabels(.init(contentId: "issue-1", add: [bug], remove: [])))
            // A teammate adds another label on GitHub; ours is re-applied on top instead of replacing the set.
            var remote = Self.item(1)
            remote.labels = [ui]
            try remote.save(db)
            try Outbox.rebase(db)
        }
        let item = try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
        #expect(Set(item.labels.map(\.name)) == ["bug", "ui"])
    }

    @Test func aNewIssueAppearsBeforeGitHubKnowsItAndFollowsItsRealId() throws {
        let db = try makeDatabase()
        let create = Mutation.CreateIssue(
            itemId: "local-item", contentId: "local-issue", projectId: Self.projectId, repoId: "R1", repo: "octo/repo",
            title: "Brand new", body: "", statusFieldId: Self.statusField, statusId: "todo",
            assignees: [], labels: [], createdAt: Date()
        )
        try db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(create))
            try Outbox.enqueue(db, .setField(.init(itemId: "local-item", projectId: Self.projectId, fieldId: Self.statusField, kind: .status, optionId: "doing", base: "todo")))
        }
        let local = try db.reader.read { try Item.fetchOne($0, key: "local-item") }
        #expect(local?.statusId == "doing")
        #expect(try order(db).count == 3) // the new one has no number yet

        let followUp = try db.reader.read { try OutboxEntry.order(Column("id")).fetchAll($0) }[1]
        let remapped = followUp.mutation.remapping(["local-item": "item-99"])
        #expect(remapped.itemId == "item-99")
    }

    @Test func textConflictsAreMergedWhenPossibleAndHeldBackOtherwise() {
        var mergeable = Mutation.SetText(itemId: "i", contentId: "c", value: "a\n\nb (mine)", base: "a\n\nb")
        #expect(SyncEngine.reconcileText(&mergeable, theirs: "a (theirs)\n\nb", mergeLines: true) == .pending)
        #expect(mergeable.value == "a (theirs)\n\nb (mine)")
        #expect(mergeable.base == "a (theirs)\n\nb")

        var clashing = Mutation.SetText(itemId: "i", contentId: "c", value: "mine", base: "base")
        #expect(SyncEngine.reconcileText(&clashing, theirs: "theirs", mergeLines: true) == .conflict)
        #expect(clashing.theirs == "theirs")
        #expect(clashing.value == "mine")

        var untouched = Mutation.SetText(itemId: "i", contentId: "c", value: "mine", base: "base")
        #expect(SyncEngine.reconcileText(&untouched, theirs: "base", mergeLines: true) == .pending)
        #expect(untouched.theirs == nil)
    }

    private func deletion(_ itemId: String, contentId: String?) -> Mutation {
        .deleteItem(.init(itemId: itemId, projectId: Self.projectId, contentId: contentId, isDraft: false, label: "#1 Issue 1"))
    }

    @Test func deletingACardRemovesItAndDropsItsOtherChanges() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setStatus(1, to: "doing", base: "todo"))
            try Outbox.enqueue(db, setStatus(2, to: "done", base: "todo"))
            try Outbox.enqueue(db, deletion("item-1", contentId: "issue-1"))
        }
        let entries = try db.reader.read { try OutboxEntry.order(Column("id")).fetchAll($0) }
        #expect(try order(db) == [2, 3])
        #expect(entries.count == 2)
        #expect(entries.contains { if case .deleteItem = $0.mutation { true } else { false } })
        #expect(!entries.contains { $0.mutation.itemId == "item-1" && $0.mutation.coalesceKey?.hasPrefix("field:") == true })
    }

    @Test func aDeletedCardStaysGoneWhenDataFromGitHubArrives() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, deletion("item-1", contentId: "issue-1"))
            // GitHub hasn't processed the deletion yet and still lists the card.
            try Self.item(1).save(db)
            try Outbox.rebase(db)
        }
        #expect(try order(db) == [2, 3])
    }

    @Test func deletingANewIssueThatNeverReachedGitHubJustForgetsIt() throws {
        let db = try makeDatabase()
        let create = Mutation.CreateIssue(
            itemId: "local-item", contentId: "local-issue", projectId: Self.projectId, repoId: "R1", repo: "octo/repo",
            title: "Never sent", body: "", statusFieldId: Self.statusField, statusId: "todo",
            assignees: [], labels: [], createdAt: Date()
        )
        try db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(create))
            try Outbox.enqueue(db, deletion("local-item", contentId: "local-issue"))
        }
        #expect(try db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
        #expect(try db.reader.read { try Item.fetchOne($0, key: "local-item") } == nil)
    }

    @Test func deletingAnIssueCreatedMomentsAgoDeletesItOnGitHub() throws {
        let db = try makeDatabase()
        var create = Mutation.CreateIssue(
            itemId: "local-item", contentId: "local-issue", projectId: Self.projectId, repoId: "R1", repo: "octo/repo",
            title: "Half sent", body: "", statusFieldId: Self.statusField, statusId: "todo",
            assignees: [], labels: [], createdAt: Date()
        )
        // GitHub has created the issue, but it isn't on the board yet.
        create.createdContentId = "issue-99"
        try db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(create))
            try Outbox.enqueue(db, deletion("local-item", contentId: "local-issue"))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        guard case .deleteItem(let m) = entries.first?.mutation else {
            Issue.record("Expected a deletion")
            return
        }
        #expect(m.contentId == "issue-99")
        #expect(entries[0].mutation.referencedIds == ["issue-99"])
    }

    // MARK: Parents and blockers

    private func summary(_ number: Int, state: String = "OPEN") -> IssueSummary {
        IssueSummary(contentId: "issue-\(number)", number: number, title: "Issue \(number)", state: state)
    }

    private func setParent(_ child: Int, to parent: Int?, base: Int?) -> Mutation {
        .setParent(.init(
            child: summary(child), parentId: parent.map { "issue-\($0)" }, parentNumber: parent,
            parentTitle: parent.map { "Issue \($0)" }, base: base.map { "issue-\($0)" }
        ))
    }

    private func setBlocking(_ blocked: Int, by blocker: Int, _ isBlocked: Bool, base: Bool) -> Mutation {
        .setBlocking(.init(blocked: summary(blocked), blocker: summary(blocker), isBlocked: isBlocked, base: base))
    }

    private func items(_ db: AppDatabase) throws -> [Int: Item] {
        try db.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Item.fetchAll(db).compactMap { item in item.number.map { ($0, item) } })
        }
    }

    /// #3 is a sub-issue of #1, as GitHub has it, and #1's sub-issues have been read.
    private func makeDatabaseWithSubIssue() throws -> AppDatabase {
        let db = try makeDatabase()
        try db.writer.write { db in
            try db.execute(sql: "UPDATE item SET parentId = 'issue-1', parentNumber = 1, parentTitle = 'Issue 1' WHERE id = 'item-3'")
            try db.execute(sql: "UPDATE item SET subTotal = 1 WHERE id = 'item-1'")
            try SubIssue(id: "issue-3", parentId: "issue-1", number: 3, title: "Issue 3", state: "OPEN", position: 0).insert(db)
        }
        return db
    }

    @Test func aSubIssueMovesToAnotherParentAndBothCountsFollow() throws {
        let db = try makeDatabaseWithSubIssue()
        try db.writer.write { try Outbox.enqueue($0, setParent(3, to: 2, base: 1)) }
        var cards = try items(db)
        #expect(cards[3]?.parentId == "issue-2")
        #expect(cards[3]?.parentNumber == 2)
        #expect(cards[1]?.subTotal == 0)
        #expect(cards[2]?.subTotal == 1)
        let lists = try db.reader.read { try SubIssue.fetchAll($0).map(\.parentId) }
        #expect(lists == ["issue-2"])

        // Applied again over the same data, nothing is counted twice.
        try db.writer.write { try Outbox.rebase($0) }
        cards = try items(db)
        #expect(cards[1]?.subTotal == 0)
        #expect(cards[2]?.subTotal == 1)
    }

    @Test func anIssueWithoutAParentBecomesASubIssueAndCountsAsDoneWhenClosed() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try db.execute(sql: "UPDATE item SET state = 'CLOSED' WHERE id = 'item-2'")
            try Outbox.enqueue(db, setParent(2, to: 1, base: nil))
            try Outbox.rebase(db)
        }
        let parent = try items(db)[1]
        #expect(parent?.subTotal == 1)
        #expect(parent?.subCompleted == 1)
    }

    @Test func changesOfParentFoldIntoOneThatKnowsGitHubsParent() throws {
        let db = try makeDatabaseWithSubIssue()
        try db.writer.write { db in
            try Outbox.enqueue(db, setParent(3, to: 2, base: 1))
            try Outbox.enqueue(db, setParent(3, to: nil, base: 2))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        guard case .setParent(let m) = entries.first?.mutation else {
            Issue.record("Expected a change of parent")
            return
        }
        // Taken out of #1 on GitHub, where it still is.
        #expect(m.parentId == nil)
        #expect(m.base == "issue-1")
        let cards = try items(db)
        #expect(cards[3]?.parentId == nil)
        #expect(cards[1]?.subTotal == 0)
        #expect(cards[2]?.subTotal == 0)
    }

    @Test func aParentChangeFollowsIssuesCreatedMomentsAgo() {
        let mutation = setParent(3, to: 2, base: nil).remapping(["issue-2": "real-2", "issue-3": "real-3"])
        guard case .setParent(let m) = mutation else {
            Issue.record("Expected a change of parent")
            return
        }
        #expect(m.child.contentId == "real-3")
        #expect(m.parentId == "real-2")
        #expect(mutation.referencedIds == ["real-3", "real-2"])
    }

    @Test func blockingListsBothIssuesAndCountsOpenOnesOnce() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setBlocking(1, by: 2, true, base: false))
            try Outbox.rebase(db)
        }
        var cards = try items(db)
        #expect(cards[1]?.blockedByCount == 1)
        #expect(cards[2]?.blockingCount == 1)
        let links = try db.reader.read { try LinkedIssue.order(Column("relation")).fetchAll($0) }
        #expect(links.map(\.relation) == [.blockedBy, .blocking])
        #expect(links.map(\.issueId) == ["issue-1", "issue-2"])

        try db.writer.write { try Outbox.enqueue($0, setBlocking(1, by: 2, false, base: true)) }
        cards = try items(db)
        #expect(cards[1]?.blockedByCount == 0)
        #expect(cards[2]?.blockingCount == 0)
        #expect(try db.reader.read { try LinkedIssue.fetchCount($0) } == 0)
    }

    @Test func markingAsBlockedAndBackBeforeSendingLeavesNothingToSend() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setBlocking(1, by: 2, true, base: false))
            try Outbox.enqueue(db, setBlocking(1, by: 2, false, base: true))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        guard case .setBlocking(let m) = entries.first?.mutation else {
            Issue.record("Expected a change of blocker")
            return
        }
        // Where GitHub started and where it ends are the same, so the engine sends nothing.
        #expect(m.isBlocked == m.base)
    }

    @Test func aClosedBlockerShowsClosedInTheIssuesRelations() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setBlocking(1, by: 2, true, base: false))
            try Outbox.enqueue(db, .setState(.init(contentId: "issue-2", closed: true, reason: "COMPLETED")))
        }
        let blocker = try db.reader.read { try LinkedIssue.filter(Column("issueId") == "issue-1").fetchOne($0) }
        #expect(blocker?.isClosed == true)
    }

    @Test func keepingMineOrTakingTheirsSettlesAConflict() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            var entry = OutboxEntry(
                createdAt: Date(), state: .conflict,
                mutation: .setBody(.init(itemId: "item-1", contentId: "issue-1", value: "mine", base: "base", theirs: "theirs"))
            )
            try entry.insert(db)
            try Outbox.resolveConflict(db, entryId: entry.id!, keepMine: false)
        }
        let item = try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
        #expect(item.body == "theirs")
        #expect(try db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
    }
}

@Suite("Due dates in the queue of changes")
struct DueDateOutboxTests {
    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try Project(
                id: OutboxTests.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true
            ).insert(db)
            try OutboxTests.item(1).insert(db)
        }
        return db
    }

    private func setDate(_ date: String?, base: String?) -> Mutation {
        .setDate(.init(itemId: "item-1", projectId: OutboxTests.projectId, date: date, base: base))
    }

    @Test func aDateShowsAtOnceEvenBeforeTheProjectHasAField() throws {
        let db = try makeDatabase()
        try db.writer.write { try Outbox.enqueue($0, setDate("2026-10-09", base: nil)) }
        let item = try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
        #expect(item.dueDate == "2026-10-09")
        #expect(item.due == CalendarDay(year: 2026, month: 10, day: 9))
    }

    @Test func changingTheDateTwiceSendsOneChangeWithTheFirstBase() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setDate("2026-10-09", base: nil))
            try Outbox.enqueue(db, setDate("2026-10-12", base: "2026-10-09"))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        #expect(entries.first?.mutation == setDate("2026-10-12", base: nil))
    }

    @Test func anUnsentDateSurvivesFreshDataFromGitHub() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setDate(nil, base: "2026-10-09"))
            var remote = OutboxTests.item(1)
            remote.dueDate = "2026-10-09"
            try remote.save(db)
            try Outbox.rebase(db)
        }
        let item = try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
        #expect(item.dueDate == nil)
    }
}
