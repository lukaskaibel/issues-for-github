import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Milestones, epics and the roadmap they make")
struct PlanningTests {
    static let today = CalendarDay(year: 2026, month: 10, day: 12)
    static let epicLabel = LabelRef(id: "L-epic", name: "epic", color: Item.epicLabelColor)

    static func milestone(_ title: String, due: String?, open: Bool = true, repo: String = "R1", id: String? = nil) -> Milestone {
        Milestone(
            id: id ?? "M-\(repo)-\(title)", repoId: repo, repo: "octo/\(repo.lowercased())", number: 1, title: title, descr: "",
            dueOn: due, state: open ? "OPEN" : "CLOSED", closedAt: open ? nil : Date(), url: nil
        )
    }

    static func epic(_ id: String, parent: String? = nil, number: Int = 1) -> Item {
        Item(
            id: "item-\(id)", projectId: "P1", kind: .issue, position: Double(number) * 1024, contentId: id, number: number,
            title: "Epic \(id)", body: "", state: "OPEN", parentId: parent, labels: [epicLabel]
        )
    }

    static func child(_ id: String, of parent: String, in milestone: String?, done: Bool = false, isEpic: Bool = false) -> Roadmap.Child {
        Roadmap.Child(contentId: id, parentId: parent, milestone: milestone, done: done, isEpic: isEpic)
    }

    // MARK: Epics

    @Test("An epic is an issue with the label epic, in its usual spellings, or the issue type Epic")
    func recognisesEpics() {
        for name in ["epic", "Epic", " EPIC ", "type: epic", "kind/epic", "type/epic"] {
            #expect(Item.isEpicLabel(name), "\(name)")
        }
        for name in ["epics", "epic-ish", "feature", "not epic"] {
            #expect(!Item.isEpicLabel(name), "\(name)")
        }
        var item = Self.epic("e1")
        #expect(item.isEpic)
        item.labels = []
        #expect(!item.isEpic)
        item.issueType = "Epic"
        #expect(item.isEpic)
        // A pull request is never an epic.
        item.kind = .pullRequest
        #expect(!item.isEpic)
    }

    // MARK: Milestones

    @Test("Milestones of the same title in several repositories are one, due the earliest open day")
    func groupsByTitle() {
        let groups = MilestoneGroup.groups([
            Self.milestone("5.4", due: "2026-11-20", repo: "R1"),
            Self.milestone("5.4", due: "2026-11-18", repo: "R2"),
            Self.milestone("5.4", due: "2026-11-01", open: false, repo: "R3"),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].milestones.count == 3)
        #expect(groups[0].isOpen)
        #expect(groups[0].due == CalendarDay("2026-11-18"))
        #expect(groups[0].milestone(inRepository: "R2")?.dueOn == "2026-11-18")
    }

    @Test("Open milestones come first by due day, those without one after them, closed ones last, newest first")
    func ordersGroups() {
        let groups = MilestoneGroup.groups([
            Self.milestone("Someday", due: nil),
            Self.milestone("5.4", due: "2026-11-20"),
            Self.milestone("5.2", due: "2026-08-01", open: false),
            Self.milestone("5.3.2", due: "2026-10-30"),
            Self.milestone("5.3", due: "2026-09-15", open: false),
        ])
        #expect(groups.map(\.title) == ["5.3.2", "5.4", "Someday", "5.3", "5.2"])
    }

    @Test("A milestone's stretch starts the day after the one before it is due; undated ones get four weeks")
    func laysOutWindows() {
        let groups = MilestoneGroup.groups([
            Self.milestone("0.2", due: "2026-09-30", open: false),
            Self.milestone("0.3", due: "2026-10-21"),
            Self.milestone("0.4", due: "2026-11-11"),
            Self.milestone("1.0", due: nil),
        ])
        let windows = Roadmap.layOut(groups, today: Self.today)
        #expect(windows.map(\.group.title) == ["0.3", "0.4", "1.0"])
        #expect(windows.map(\.start.string) == ["2026-10-01", "2026-10-22", "2026-11-12"])
        #expect(windows.map(\.end.string) == ["2026-10-21", "2026-11-11", "2026-12-09"])
        #expect(windows.map(\.undated) == [false, false, true])
    }

    @Test("Without a closed milestone before it, the first stretch starts a few weeks before it is due, or today")
    func startsTheFirstWindow() {
        let far = Roadmap.layOut(MilestoneGroup.groups([Self.milestone("1.0", due: "2026-12-31")]), today: Self.today)
        #expect(far[0].start == Self.today)
        let near = Roadmap.layOut(MilestoneGroup.groups([Self.milestone("0.3", due: "2026-10-20")]), today: Self.today)
        #expect(near[0].start.string == "2026-09-29")
        let undated = Roadmap.layOut(MilestoneGroup.groups([Self.milestone("Next", due: nil)]), today: Self.today)
        #expect(undated[0].start == Self.today)
        #expect(undated[0].end == Self.today.adding(days: Roadmap.undatedLength - 1))
    }

    @Test("Neighbouring stretches run together into one bar")
    func makesRuns() {
        #expect(Roadmap.runs([]) == [])
        #expect(Roadmap.runs([0, 1, 2]) == [0...2])
        #expect(Roadmap.runs([0, 2, 3]) == [0...0, 2...3])
    }

    // MARK: The roadmap

    /// 0.3 and 0.4 with dates, 1.0 without, and epics planned in different ways.
    private func sampleRoadmap() -> Roadmap {
        let groups = MilestoneGroup.groups([
            Self.milestone("0.2", due: "2026-09-30", open: false),
            Self.milestone("0.3", due: "2026-10-21"),
            Self.milestone("0.4", due: "2026-11-11"),
            Self.milestone("1.0", due: nil),
        ])
        let epics = [
            Self.epic("e1", number: 1), Self.epic("e2", number: 2), Self.epic("e3", number: 3), Self.epic("e4", number: 4),
            Self.epic("e5", parent: "e1", number: 5), Self.epic("e6", number: 6), Self.epic("e7", number: 7),
        ]
        let children = [
            // e1: open work in 0.3, finished work in 0.4, and the sub-epic e5 with open work in 0.4.
            Self.child("c1", of: "e1", in: "0.3"),
            Self.child("c2", of: "e1", in: "0.4", done: true),
            Self.child("e5", of: "e1", in: nil, isEpic: true),
            Self.child("c3", of: "e5", in: "0.4"),
            // e2: everything done, in 0.4.
            Self.child("c4", of: "e2", in: "0.4", done: true),
            // e4: work in no milestone.
            Self.child("c5", of: "e4", in: nil),
            // e6: done, in the closed 0.2.
            Self.child("c6", of: "e6", in: "0.2", done: true),
            // e7: work in 0.3 and 1.0 but not 0.4.
            Self.child("c7", of: "e7", in: "0.3"),
            Self.child("c8", of: "e7", in: "1.0"),
        ]
        return Roadmap.make(
            groups: groups, epics: epics, children: children, milestoneOfEpic: ["e3": "1.0"], doneEpics: ["e6"],
            today: Self.today
        )
    }

    @Test("An epic covers the milestones of its unfinished work, and hangs under the epic it belongs to")
    func placesEpics() {
        let roadmap = sampleRoadmap()
        #expect(roadmap.rows.map(\.epic.contentId) == ["e1", "e5", "e7", "e2", "e3"])
        let rows = Dictionary(uniqueKeysWithValues: roadmap.rows.map { ($0.epic.contentId!, $0) })
        // Its sub-epic's work counts for it too.
        #expect(rows["e1"]?.runs == [0...1])
        #expect(rows["e1"]?.next == "0.3")
        #expect(rows["e5"]?.depth == 1)
        #expect(rows["e5"]?.runs == [1...1])
        #expect(rows["e7"]?.runs == [0...0, 2...2])
        // All done: where the work was done.
        #expect(rows["e2"]?.runs == [1...1])
        // Planned by its own milestone alone.
        #expect(rows["e3"]?.runs == [2...2])
        #expect(roadmap.later.map(\.epic.contentId) == ["e4"])
        // A finished epic whose milestones are all closed is no longer on the roadmap.
        #expect(!(roadmap.rows + roadmap.later).contains { $0.epic.contentId == "e6" })
    }

    @Test("An epic counts its own sub-issues, as a whole and per milestone")
    func countsWork() {
        let e1 = sampleRoadmap().rows.first { $0.epic.contentId == "e1" }
        #expect(e1?.done == 1)
        #expect(e1?.total == 3)
        #expect(e1?.perMilestone["0.3"] == Roadmap.Count(done: 0, total: 1))
        #expect(e1?.perMilestone["0.4"] == Roadmap.Count(done: 1, total: 1))
        #expect(e1?.perMilestone[""] == Roadmap.Count(done: 0, total: 1))
    }

    @Test("Moving an epic's open work to another milestone moves its bar")
    func followsWork() {
        let groups = MilestoneGroup.groups([Self.milestone("0.3", due: "2026-10-21"), Self.milestone("0.4", due: "2026-11-11")])
        let before = Roadmap.make(
            groups: groups, epics: [Self.epic("e1")], children: [Self.child("c1", of: "e1", in: "0.3")], milestoneOfEpic: [:],
            today: Self.today
        )
        let after = Roadmap.make(
            groups: groups, epics: [Self.epic("e1")], children: [Self.child("c1", of: "e1", in: "0.4")], milestoneOfEpic: [:],
            today: Self.today
        )
        #expect(before.rows.first?.runs == [0...0])
        #expect(after.rows.first?.runs == [1...1])
        #expect(after.rows.first?.next == "0.4")
    }

    @Test("Epics that are each other's parents don't loop")
    func survivesLoops() {
        let groups = MilestoneGroup.groups([Self.milestone("0.3", due: "2026-10-21")])
        let roadmap = Roadmap.make(
            groups: groups, epics: [Self.epic("a", parent: "b"), Self.epic("b", parent: "a")],
            children: [Self.child("b", of: "a", in: "0.3", isEpic: true), Self.child("a", of: "b", in: "0.3", isEpic: true)],
            milestoneOfEpic: [:], today: Self.today
        )
        #expect(Set(roadmap.rows.compactMap(\.epic.contentId)) == ["a", "b"])
        #expect(roadmap.rows.count == 2)
    }

    // MARK: Due days on GitHub

    @Test("A due day goes to GitHub as noon UTC and comes back as the day it was")
    func convertsDueDays() {
        #expect(GitHubAPI.dueOn(fromDay: "2026-11-20") == "2026-11-20T12:00:00Z")
        #expect(GitHubAPI.day(fromDueOn: "2026-11-20T07:00:00Z") == "2026-11-20")
        #expect(GitHubAPI.day(fromDueOn: nil) == nil)
        #expect(GitHubAPI.day(fromDueOn: "soon") == nil)
    }
}

@Suite("Queued changes to milestones and epics")
struct PlanningOutboxTests {
    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try Project(
                id: "P1", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true, statusFieldId: nil
            ).insert(db)
            try PlanningTests.milestone("0.3", due: "2026-10-21").insert(db)
            try PlanningTests.milestone("0.4", due: "2026-11-11").insert(db)
            var issue = Item(
                id: "item-1", projectId: "P1", kind: .issue, position: 1024, contentId: "issue-1", number: 1,
                title: "Issue 1", body: "", state: "OPEN", repoId: "R1", repo: "octo/r1", parentId: "epic-9", parentNumber: 9
            )
            issue.milestoneId = "M-R1-0.3"
            issue.milestoneTitle = "0.3"
            try issue.insert(db)
            try SubIssue(
                id: "issue-1", parentId: "epic-9", number: 1, title: "Issue 1", state: "OPEN", repo: "octo/r1", url: nil,
                position: 0, milestoneId: "M-R1-0.3", milestoneTitle: "0.3"
            ).insert(db)
        }
        return db
    }

    private func setMilestone(_ id: String?, title: String?, base: String?) -> Mutation {
        .setMilestone(.init(contentId: "issue-1", isPullRequest: false, milestoneId: id, milestoneTitle: title, base: base))
    }

    private func issue(_ db: AppDatabase) throws -> Item {
        try db.reader.read { try Item.fetchOne($0, key: "item-1")! }
    }

    @Test("A new milestone shows on the issue and in its parent's list at once")
    func setsMilestoneLocally() throws {
        let db = try makeDatabase()
        try db.writer.write { try Outbox.enqueue($0, setMilestone("M-R1-0.4", title: "0.4", base: "M-R1-0.3")) }
        let item = try issue(db)
        #expect(item.milestoneId == "M-R1-0.4")
        #expect(item.milestoneTitle == "0.4")
        #expect(item.dirty)
        let sub = try db.reader.read { try SubIssue.filter(Column("id") == "issue-1").fetchOne($0)! }
        #expect(sub.milestoneTitle == "0.4")

        try db.writer.write { try Outbox.enqueue($0, setMilestone(nil, title: nil, base: "M-R1-0.4")) }
        #expect(try issue(db).milestoneId == nil)
    }

    @Test("Changing an issue's milestone again replaces the queued change and keeps what GitHub has")
    func collapsesMilestoneChanges() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, setMilestone("M-R1-0.4", title: "0.4", base: "M-R1-0.3"))
            try Outbox.enqueue(db, setMilestone(nil, title: nil, base: "M-R1-0.4"))
        }
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        guard case .setMilestone(let change) = entries.first?.mutation else {
            Issue.record("Expected a milestone change")
            return
        }
        #expect(change.milestoneId == nil)
        #expect(change.base == "M-R1-0.3")
    }

    @Test("A milestone made here shows at once, and issues put into it wait until GitHub has made it")
    func createsMilestones() throws {
        let db = try makeDatabase()
        let local = LocalID.make()
        try db.writer.write { db in
            try Outbox.enqueue(db, .createMilestone(.init(milestoneId: local, repoId: "R1", repo: "octo/r1", title: "0.5", dueOn: nil, descr: "")))
            try Outbox.enqueue(db, setMilestone(local, title: "0.5", base: "M-R1-0.3"))
        }
        let made = try db.reader.read { try Milestone.fetchOne($0, key: local) }
        #expect(made?.title == "0.5")
        #expect(made?.isOpen == true)
        #expect(made?.isLocalOnly == true)
        #expect(try issue(db).milestoneTitle == "0.5")
        // Waiting for it, and following it to GitHub's id.
        let change = setMilestone(local, title: "0.5", base: "M-R1-0.3")
        #expect(change.referencedIds.contains(local))
        guard case .setMilestone(let remapped) = change.remapping([local: "M-R1-0.5"]) else {
            Issue.record("Expected a milestone change")
            return
        }
        #expect(remapped.milestoneId == "M-R1-0.5")
    }

    @Test("Renaming a milestone renames it on its issues; completing and reopening it sets and clears the day")
    func updatesMilestones() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try Outbox.enqueue(db, .updateMilestone(.init(milestoneId: "M-R1-0.3", change: .init(title: "0.3.1"))))
        }
        #expect(try issue(db).milestoneTitle == "0.3.1")
        try db.writer.write { db in
            try Outbox.enqueue(db, .updateMilestone(.init(milestoneId: "M-R1-0.3", change: .init(state: "CLOSED"))))
        }
        var milestone = try db.reader.read { try Milestone.fetchOne($0, key: "M-R1-0.3")! }
        #expect(milestone.title == "0.3.1")
        #expect(!milestone.isOpen)
        #expect(milestone.closedAt != nil)
        // Both changes still go to GitHub, in one.
        let entries = try db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        if case .updateMilestone(let update) = entries.first?.mutation {
            #expect(update.change == .init(title: "0.3.1", state: "CLOSED"))
        } else {
            Issue.record("Expected a milestone update")
        }
        try db.writer.write { db in
            try Outbox.enqueue(db, .updateMilestone(.init(milestoneId: "M-R1-0.3", change: .init(state: "OPEN"))))
        }
        milestone = try db.reader.read { try Milestone.fetchOne($0, key: "M-R1-0.3")! }
        #expect(milestone.isOpen)
        #expect(milestone.closedAt == nil)
    }

    @Test("Making an issue an epic adds the label; turning it back takes the label and the Epic type away")
    func makesEpics() throws {
        let db = try makeDatabase()
        let label = PlanningTests.epicLabel
        try db.writer.write { db in
            try Outbox.enqueue(db, .setEpic(.init(contentId: "issue-1", repoId: "R1", repo: "octo/r1", isEpic: true, label: label)))
        }
        #expect(try issue(db).isEpic)
        try db.writer.write { db in
            try db.execute(sql: "UPDATE item SET issueType = 'Epic' WHERE id = 'item-1'")
            try Outbox.enqueue(db, .setEpic(.init(contentId: "issue-1", repoId: "R1", repo: "octo/r1", isEpic: false, label: label)))
        }
        let item = try issue(db)
        #expect(!item.isEpic)
        #expect(item.issueType == nil)
        #expect(item.labels.isEmpty)
    }

    @Test("Fresh milestones from GitHub replace the old ones, keep those still being made, and rename issues' milestones")
    func writesFetchedMilestones() throws {
        let db = try makeDatabase()
        let local = LocalID.make()
        try db.writer.write { db in
            try Outbox.enqueue(db, .createMilestone(.init(milestoneId: local, repoId: "R1", repo: "octo/r1", title: "0.5", dueOn: nil, descr: "")))
        }
        var renamed = PlanningTests.milestone("0.3", due: "2026-10-21")
        renamed.title = "0.3 Polish"
        try db.writer.write { db in
            try SyncEngine.writeMilestones(db, [renamed], repoId: "R1")
        }
        let titles = try db.reader.read { try Milestone.order(Column("title")).fetchAll($0).map(\.title) }
        #expect(titles == ["0.3 Polish", "0.5"])
        #expect(try issue(db).milestoneTitle == "0.3 Polish")
    }
}
