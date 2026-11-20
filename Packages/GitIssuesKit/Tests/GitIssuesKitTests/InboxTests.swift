import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("The Inbox: GitHub's notifications, what a row says, and reading and archiving them")
struct InboxTests {
    static let viewer = "jordan"
    static let kai = Person(id: "u-kai", login: "kai", name: "Kai Andersen")
    static let theo = Person(id: "u-theo", login: "theo", name: "Theo Novak")
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func entry(
        _ id: String = "t1", reason: String = "comment", unread: Bool = true, updatedAt: Date = now,
        activity: [InboxActivity] = []
    ) -> InboxEntry {
        var entry = InboxEntry(
            id: id, reason: reason, unread: unread, updatedAt: updatedAt, subjectType: "Issue", title: "Crash on launch",
            repo: "acme/app", number: 12
        )
        entry.activity = activity
        entry.activityIsNew = unread
        return entry
    }

    // MARK: What a row says

    // MARK: Which category

    static let bot = Person(id: "b-actions", login: "github-actions")

    static func open(_ entry: InboxEntry, author: String? = nil, assignees: [Person] = []) -> InboxEntry {
        var entry = entry
        entry.state = "OPEN"
        entry.authorLogin = author
        entry.assignees = assignees
        return entry
    }

    @Test func whatSomeoneAsksOfYouNeedsYou() {
        // GitHub never notifies your own actions: someone else asked for your review, mentioned you or assigned you.
        for reason in ["review_requested", "mention", "team_mention", "assign"] {
            #expect(Self.open(Self.entry(reason: reason)).category(viewer: Self.viewer) == .needsYou)
        }
        // Not read yet: GitHub's reason decides alone.
        #expect(Self.entry(reason: "assign").category(viewer: Self.viewer) == .needsYou)
        #expect(Self.entry(reason: "author").category(viewer: Self.viewer) == .updates)
    }

    @Test func aPersonWritingOnAnIssueOfYoursNeedsYou() {
        let comment = InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "What is meant here?", byBot: false)
        let opened = Self.entry(reason: "author", activity: [comment])
        #expect(Self.open(opened, author: "Jordan").category(viewer: Self.viewer) == .needsYou)
        // Assigned to you, or you took part in it.
        #expect(Self.open(opened, assignees: [Person(id: "u-j", login: "jordan")]).category(viewer: Self.viewer) == .needsYou)
        #expect(Self.open(Self.entry(reason: "comment", activity: [comment])).category(viewer: Self.viewer) == .needsYou)
        // Someone else's issue in a project you follow is an update, unless it mentions you.
        #expect(Self.open(Self.entry(reason: "subscribed", activity: [comment])).category(viewer: Self.viewer) == .updates)
        #expect(Self.open(Self.entry(reason: "state_change", activity: [comment])).category(viewer: Self.viewer) == .updates)
        let mention = InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "@jordan have a look", byBot: false)
        #expect(Self.open(Self.entry(reason: "state_change", activity: [mention])).category(viewer: Self.viewer) == .needsYou)
    }

    @Test func botsAndStatusChangesAreUpdates() {
        let bot = InboxActivity(kind: .commented, actor: Self.bot, at: Self.now, text: "Preview deployed", byBot: true)
        #expect(Self.open(Self.entry(reason: "author", activity: [bot]), author: "jordan").category(viewer: Self.viewer) == .updates)
        // Read before the app asked about bots: the login tells.
        let old = InboxActivity(kind: .commented, actor: Person(id: "b", login: "dependabot[bot]"), at: Self.now, text: "Rebased")
        #expect(Self.open(Self.entry(reason: "author", activity: [old]), author: "jordan").category(viewer: Self.viewer) == .updates)
        let moved = InboxActivity(kind: .statusChanged, actor: Self.kai, at: Self.now, detail: "Done", byBot: false)
        #expect(Self.open(Self.entry(reason: "author", activity: [moved]), author: "jordan").category(viewer: Self.viewer) == .updates)
    }

    @Test func whatIsClosedOrMergedOrWatchedIsAnUpdate() {
        let comment = InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "Thanks!", byBot: false)
        for state in ["CLOSED", "MERGED"] {
            var entry = Self.entry(reason: "review_requested", activity: [comment])
            entry.state = state
            entry.authorLogin = "jordan"
            #expect(entry.category(viewer: Self.viewer) == .updates)
        }
        #expect(Self.open(Self.entry(reason: "subscribed")).category(viewer: Self.viewer) == .updates)
        #expect(Self.entry(reason: "subscribed").isWatched)
    }

    // MARK: Runs of assignments

    static func assigned(_ number: Int, at: Date, repo: String = "acme/app") -> InboxEntry {
        var entry = InboxEntry(
            id: "self_assign:AE_\(number)", reason: "self_assign", unread: true, updatedAt: at, subjectType: "Issue",
            title: "Cluster \(number)", repo: repo, number: number
        )
        entry.state = "OPEN"
        return entry
    }

    @Test func assignmentsMadeTogetherAreOneRun() {
        // Newest first, as the list has them: three a minute apart, then one an hour earlier.
        let entries = [
            Self.assigned(13, at: Self.now),
            Self.assigned(12, at: Self.now.addingTimeInterval(-60)),
            Self.assigned(11, at: Self.now.addingTimeInterval(-120)),
            Self.assigned(10, at: Self.now.addingTimeInterval(-3600)),
        ]
        let grouped = InboxBatch.group(entries)
        #expect(grouped.count == 2)
        guard case .batch(let run) = grouped[0], case .entry(let alone) = grouped[1] else {
            Issue.record("expected a run, then an entry")
            return
        }
        #expect(run.entries.map(\.number) == [13, 12, 11])
        #expect(run.numbers == "#11–#13")
        // Named after its first assignment, so a later one joining keeps it the same.
        #expect(run.id == "batch:self_assign:AE_11")
        #expect(alone.number == 10)
    }

    @Test func twoAssignmentsOrAnotherEntryBetweenThemStayRows() {
        let two = [Self.assigned(2, at: Self.now), Self.assigned(1, at: Self.now.addingTimeInterval(-60))]
        #expect(InboxBatch.group(two).allSatisfy { if case .entry = $0 { true } else { false } })
        let interrupted = [
            Self.assigned(3, at: Self.now), Self.assigned(2, at: Self.now.addingTimeInterval(-30)),
            Self.entry("t9", reason: "mention", updatedAt: Self.now.addingTimeInterval(-40)),
            Self.assigned(1, at: Self.now.addingTimeInterval(-60)),
        ]
        #expect(InboxBatch.group(interrupted).count == 4)
        let otherRepo = [
            Self.assigned(3, at: Self.now), Self.assigned(2, at: Self.now.addingTimeInterval(-30), repo: "acme/web"),
            Self.assigned(1, at: Self.now.addingTimeInterval(-60)),
        ]
        #expect(InboxBatch.group(otherRepo).count == 3)
    }

    @Test func anAssignmentLeadsEvenWhenACommentCameAfterIt() {
        let entry = Self.entry(reason: "assign", activity: [
            InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "Looks good"),
            InboxActivity(kind: .assigned, actor: Self.kai, at: Self.now.addingTimeInterval(-60), detail: "jordan"),
        ])
        let summary = entry.summary(viewer: Self.viewer)
        #expect(summary.lead == "Kai Andersen assigned you")
        #expect(summary.sign == .assigned)
        #expect(summary.actor?.login == "kai")
    }

    @Test func aMentionQuotesTheSentence() {
        let entry = Self.entry(reason: "mention", activity: [
            InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "@jordan can you check the wording?"),
        ])
        let summary = entry.summary(viewer: Self.viewer)
        #expect(summary.lead == "Theo Novak mentioned you:")
        #expect(summary.excerpt == "@jordan can you check the wording?")
        #expect(summary.sign == .mentioned)
    }

    @Test func aTeamMentionNamesTheTeam() {
        let entry = Self.entry(reason: "team_mention", activity: [
            InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "Over to @acme/ios for this one"),
        ])
        #expect(entry.summary(viewer: Self.viewer).lead == "Theo Novak mentioned @acme/ios:")
    }

    @Test func severalPeopleCommentingIsOneLine() {
        let entry = Self.entry(activity: [
            InboxActivity(kind: .commented, actor: Self.theo, at: Self.now, text: "Third"),
            InboxActivity(kind: .commented, actor: Self.kai, at: Self.now.addingTimeInterval(-60), text: "Second"),
            InboxActivity(kind: .commented, actor: Self.theo, at: Self.now.addingTimeInterval(-120), text: "First"),
        ])
        let summary = entry.summary(viewer: Self.viewer)
        #expect(summary.lead == "Theo Novak and 1 other commented")
        #expect(summary.excerpt == nil)
    }

    @Test func closingSaysHow() {
        let completed = Self.entry(activity: [InboxActivity(kind: .closed, actor: Self.kai, at: Self.now, detail: "COMPLETED")])
        #expect(completed.summary(viewer: Self.viewer).lead == "Kai Andersen closed it as completed")
        let notPlanned = Self.entry(activity: [InboxActivity(kind: .closed, actor: Self.kai, at: Self.now, detail: "NOT_PLANNED")])
        #expect(notPlanned.summary(viewer: Self.viewer).lead == "Kai Andersen closed it as not planned")
        #expect(notPlanned.summary(viewer: Self.viewer).sign == .notPlanned)
    }

    @Test func withoutActivityTheReasonSpeaks() {
        #expect(Self.entry(reason: "assign").summary(viewer: Self.viewer).lead == "You were assigned")
        #expect(Self.entry(reason: "review_requested").summary(viewer: Self.viewer).lead == "Your review was requested")
        #expect(Self.entry(reason: "subscribed").summary(viewer: Self.viewer).lead == "New activity")
    }

    @Test func aMentionIsTheLoginAsAWordOfItsOwn() {
        #expect(InboxEntry.mentions("@jordan please look", login: "jordan"))
        #expect(InboxEntry.mentions("Thanks, @Jordan!", login: "jordan"))
        #expect(!InboxEntry.mentions("@jordanx please look", login: "jordan"))
        #expect(!InboxEntry.mentions("mail me at team@jordan.dev", login: "jordan"))
        #expect(!InboxEntry.mentions("@acme/jordan", login: "jordan"))
    }

    @Test func timesAreShort() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
        #expect(inboxTime(noon.addingTimeInterval(-20), now: noon, calendar: calendar) == "now")
        #expect(inboxTime(noon.addingTimeInterval(-12 * 60), now: noon, calendar: calendar) == "12m")
        #expect(inboxTime(noon.addingTimeInterval(-3 * 3600), now: noon, calendar: calendar) == "3h")
        #expect(inboxTime(noon.addingTimeInterval(-26 * 3600), now: noon, calendar: calendar) == "Yesterday")
    }

    // MARK: Snoozing

    @Test func snoozeChoicesLandWhereTheySay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Wednesday, 7 October 2026.
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 10))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 17, minute: 30))!
        func parts(_ date: Date) -> DateComponents { calendar.dateComponents([.day, .hour, .minute, .weekday], from: date) }

        #expect(parts(SnoozeChoice.laterToday.date(from: morning, calendar: calendar)).hour == 13)
        // Late in the day, three hours on, even past 18:00.
        #expect(parts(SnoozeChoice.laterToday.date(from: evening, calendar: calendar)).hour == 20)
        let tomorrow = parts(SnoozeChoice.tomorrow.date(from: morning, calendar: calendar))
        #expect(tomorrow.day == 8 && tomorrow.hour == 9)
        let nextWeek = parts(SnoozeChoice.nextWeek.date(from: morning, calendar: calendar))
        #expect(nextWeek.weekday == 2 && nextWeek.day == 12 && nextWeek.hour == 9)
    }

    // MARK: Reading GitHub's answers

    @Test func notificationThreadsAreRead() throws {
        let json = """
        [{"id": "101", "unread": true, "reason": "assign", "updated_at": "2026-10-07T08:40:53Z", "last_read_at": null,
          "subject": {"title": "Crash on launch", "url": "https://api.github.com/repos/acme/app/issues/12", "latest_comment_url": null, "type": "Issue"},
          "repository": {"full_name": "acme/app"}, "url": "", "subscription_url": ""},
         {"id": "102", "unread": false, "reason": "ci_activity", "updated_at": "2026-10-07T08:00:00Z", "last_read_at": "2026-10-07T08:10:00Z",
          "subject": {"title": "CI", "url": null, "latest_comment_url": null, "type": "CheckSuite"},
          "repository": {"full_name": "acme/app"}, "url": "", "subscription_url": ""}]
        """
        let threads = try GitHubAPI.threads(fromJSON: Data(json.utf8))
        #expect(threads.count == 2)
        #expect(threads[0].number == 12)
        #expect(threads[0].repo == "acme/app")
        #expect(threads[0].isIssueOrPullRequest)
        #expect(!threads[1].isIssueOrPullRequest)
        #expect(threads[1].lastReadAt != nil)
    }

    @Test func theTimelineBecomesActivityWithoutYourOwn() throws {
        let json = """
        {"__typename": "Issue", "id": "I_1", "url": "https://github.com/acme/app/issues/12", "title": "Crash on launch",
         "body": "Steps", "state": "OPEN", "stateReason": null, "createdAt": "2026-09-01T10:00:00Z",
         "author": {"login": "kai", "avatarUrl": null, "name": "Kai Andersen"}, "repository": {"id": "R_1"},
         "assignees": {"nodes": [{"id": "u-j", "login": "jordan", "name": null, "avatarUrl": null}]},
         "labels": {"nodes": [{"id": "L1", "name": "bug", "color": "d73a4a"}]},
         "timelineItems": {"nodes": [
           {"__typename": "AssignedEvent", "createdAt": "2026-10-07T08:00:00Z", "actor": {"login": "kai", "name": "Kai Andersen"}, "assignee": {"login": "jordan"}},
           {"__typename": "IssueComment", "id": "C_1", "createdAt": "2026-10-07T08:05:00Z", "bodyText": "Reproduced\\n  on 0.1.0.", "author": {"login": "kai"}},
           {"__typename": "IssueComment", "id": "C_2", "createdAt": "2026-10-07T08:06:00Z", "bodyText": "Thanks!", "author": {"login": "jordan"}},
           {"__typename": "ProjectV2ItemStatusChangedEvent", "createdAt": "2026-10-07T08:07:00Z", "status": "Todo", "project": {"title": "App"}, "actor": {"login": "kai"}},
           {"__typename": "ClosedEvent", "createdAt": "2026-09-30T08:00:00Z", "stateReason": "COMPLETED", "actor": {"login": "kai"}}
         ]}}
        """
        let since = ISO8601DateFormatter().date(from: "2026-10-06T00:00:00Z")
        let detail = try GitHubAPI.inboxDetail(fromJSON: Data(json.utf8), repoId: "R_x", since: since, viewer: "jordan")
        #expect(detail.contentId == "I_1")
        #expect(detail.repoId == "R_1")
        #expect(detail.labels.map(\.name) == ["bug"])
        // Newest first; Jordan's own comment and everything before "since" left out, the issue's opening too.
        #expect(detail.activity.map(\.kind) == [.statusChanged, .commented, .assigned])
        #expect(detail.activity[1].text == "Reproduced on 0.1.0.")
        #expect(detail.activity[1].commentId == "C_1")
        #expect(detail.activity[2].detail == "jordan")
        #expect(detail.activity[0].project == "App")
    }

    // MARK: Reading and archiving through the queue

    private func makeDatabase(_ entries: [InboxEntry]) throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            for entry in entries { try entry.insert(db) }
        }
        return db
    }

    private func entry(_ db: AppDatabase, _ id: String) throws -> InboxEntry {
        try db.reader.read { try InboxEntry.fetchOne($0, key: id)! }
    }

    private func thread(_ id: String, unread: Bool, updatedAt: Date, type: String = "Issue") -> RemoteThread {
        RemoteThread(id: id, reason: "comment", unread: unread, updatedAt: updatedAt, subjectType: type, title: "Crash on launch", repo: "acme/app", number: 12)
    }

    @Test func readingShowsAtOnceAndStaysOverFreshData() throws {
        let db = try makeDatabase([Self.entry("t1")])
        try db.writer.write { try Outbox.enqueue($0, .markThreadRead(.init(threadId: "t1", updatedAt: Self.now, label: "#12"))) }
        #expect(try !entry(db, "t1").unread)
        // GitHub hasn't heard yet and still says unread; the queued change wins.
        try db.writer.write { try SyncEngine.writeInbox($0, threads: [thread("t1", unread: true, updatedAt: Self.now)], lastModified: nil) }
        #expect(try !entry(db, "t1").unread)
        // Something new happened since: that is unread again.
        let later = Self.now.addingTimeInterval(60)
        try db.writer.write { try SyncEngine.writeInbox($0, threads: [thread("t1", unread: true, updatedAt: later)], lastModified: nil) }
        #expect(try entry(db, "t1").unread)
    }

    @Test func archivedStaysAwayUntilSomethingNewHappens() throws {
        let db = try makeDatabase([Self.entry("t1")])
        try db.writer.write { try Outbox.enqueue($0, .archiveThread(.init(threadId: "t1", updatedAt: Self.now, label: "#12"))) }
        #expect(try entry(db, "t1").isArchived)
        try db.writer.write { try SyncEngine.writeInbox($0, threads: [thread("t1", unread: true, updatedAt: Self.now)], lastModified: nil) }
        #expect(try entry(db, "t1").isArchived)
        try db.writer.write { try SyncEngine.writeInbox($0, threads: [thread("t1", unread: true, updatedAt: Self.now.addingTimeInterval(60))], lastModified: nil) }
        #expect(try !entry(db, "t1").isArchived)
    }

    @Test func archivingWaitsBeforeItIsSentSoItCanBeUndone() {
        let change = Mutation.ThreadChange(threadId: "t1", updatedAt: Self.now, label: "#12")
        #expect(Mutation.archiveThread(change).isUndoable)
        #expect(Mutation.unsubscribeThread(change).isUndoable)
        #expect(!Mutation.markThreadRead(change).isUndoable)
    }

    @Test func otherKindsAreCountedAndGoneThreadsLeave() throws {
        let db = try makeDatabase([Self.entry("t1"), Self.entry("t2")])
        try db.writer.write {
            try SyncEngine.writeInbox($0, threads: [
                thread("t1", unread: false, updatedAt: Self.now),
                thread("t3", unread: true, updatedAt: Self.now, type: "Release"),
            ], lastModified: "Wed, 07 Oct 2026 08:40:53 GMT")
        }
        let (ids, meta) = try db.reader.read { (try String.fetchAll($0, sql: "SELECT id FROM inboxEntry"), try InboxMeta.read($0)) }
        #expect(ids == ["t1"])
        #expect(meta.others == ["Release": 1])
        #expect(meta.access == .ok)
        #expect(meta.lastModified == "Wed, 07 Oct 2026 08:40:53 GMT")
    }

    @Test func assigningAnIssueOnNoBoardShowsInTheInbox() throws {
        var outside = Self.entry("t1")
        outside.contentId = "I_9"
        let db = try makeDatabase([outside])
        let me = Person(id: "u-j", login: "jordan")
        try db.writer.write { try Outbox.enqueue($0, .editAssignees(.init(contentId: "I_9", add: [me], remove: []))) }
        #expect(try entry(db, "t1").assignees.map(\.login) == ["jordan"])
    }

    @Test func closingOrRenamingAnIssueOnNoBoardShowsInTheInbox() throws {
        var outside = Self.entry("t1")
        outside.contentId = "I_9"
        outside.state = "OPEN"
        let db = try makeDatabase([outside])
        try db.writer.write { db in
            try Outbox.enqueue(db, .setState(.init(contentId: "I_9", closed: true, reason: "COMPLETED")))
            try Outbox.enqueue(db, .setTitle(.init(itemId: "I_9", contentId: "I_9", value: "Crash on start", base: "Crash on launch")))
        }
        let changed = try entry(db, "t1")
        #expect(changed.state == "CLOSED")
        #expect(changed.stateReason == "COMPLETED")
        #expect(changed.title == "Crash on start")
    }

    @Test func anIssueOnlyTheInboxKnowsGoesOntoABoard() throws {
        var outside = Self.entry("t1")
        outside.contentId = "I_9"
        outside.repoId = "R_1"
        let db = try makeDatabase([outside])
        let detached = try #require(Item(detached: outside))
        #expect(detached.isDetached)
        #expect(!detached.isEditableContent)

        // Kept as an issue of no board first, then put on the board in one write, as AppModel.addToProject does.
        let kept = detached.keptWithoutProject
        #expect(kept.id == Item.idWithoutProject("I_9"))
        #expect(!kept.isDetached)
        try db.writer.write { db in
            try Project(id: "P1", ownerLogin: "acme", ownerIsOrg: true, number: 1, title: "Board", url: "", closed: false, viewerCanUpdate: true).insert(db)
            try kept.insert(db)
            try Outbox.enqueue(db, .addToProject(.init(itemId: kept.id, contentId: "I_9", projectId: "P1", statusFieldId: "F1", statusId: "todo")))
        }
        let card = try db.reader.read { try Item.fetchOne($0, key: kept.id) }
        #expect(card?.projectId == "P1")
        #expect(card?.statusId == "todo")
        #expect(card?.title == "Crash on launch")
        // An issue the app already keeps stays as it is.
        #expect(kept.keptWithoutProject == kept)
    }

    @Test func theSampleDataHasAnInbox() throws {
        let db = try DemoData.database()
        let (entries, meta) = try db.reader.read { (try InboxEntry.fetchAll($0), try InboxMeta.read($0)) }
        #expect(entries.count >= 6)
        #expect(entries.contains { $0.isWatched })
        #expect(entries.contains { $0.unread })
        #expect(meta.otherCount == 2)
    }
}

@MainActor
@Suite("Snoozes and marked-unread entries, kept apart from GitHub")
struct PersonalStoreTests {
    @Test func snoozingAndClearing() {
        let store = PersonalStore(persistent: false)
        let until = Date().addingTimeInterval(3600)
        store.setSnooze("t1", .init(until: until, threadUpdatedAt: Date()))
        #expect(store.snooze("t1")?.until == until)
        #expect(store.nextWake == until)
        store.setMarkedUnread("t1", Date())
        #expect(store.markedUnread("t1") != nil)
        store.clear("t1")
        #expect(store.snooze("t1") == nil)
        #expect(store.markedUnread("t1") == nil)
    }

    @Test func undoPutsARecordBack() {
        let store = PersonalStore(persistent: false)
        let at = Date()
        store.setMarkedUnread("t1", at)
        let before = store.records["t1"]
        store.clear("t1")
        store.restore("t1", before)
        #expect(store.markedUnread("t1") == at)
    }
}
