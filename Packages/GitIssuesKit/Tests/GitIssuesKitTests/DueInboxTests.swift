import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Issues that are due, as Inbox entries")
struct DueInboxTests {
    private func item(due: CalendarDay) -> Item {
        var item = OutboxTests.item(1, title: "Ship the release notes")
        item.dueDate = due.string
        item.repo = "acme/git-issues"
        return item
    }

    @Test func aDueEntryNamesTheIssueAndTheDay() {
        let today = CalendarDay.today()
        let entry = InboxEntry(due: item(due: today), day: today, overdue: false, at: Date())
        #expect(entry.id == "due:issue-1:\(today.string)")
        #expect(entry.isDue)
        #expect(entry.dueDay == today)
        #expect(entry.bucket == .forYou)
        #expect(entry.contentId == "issue-1")
        #expect(entry.title == "Ship the release notes")
        let summary = entry.summary(viewer: "jordan")
        #expect(summary.lead == "Due today")
        #expect(summary.sign == .due)
    }

    @Test func anOverdueEntryIsANewEntrySayingSinceWhen() {
        let yesterday = CalendarDay.today().adding(days: -1)
        let entry = InboxEntry(due: item(due: yesterday), day: yesterday, overdue: true, at: Date())
        #expect(entry.id == "overdue:issue-1:\(yesterday.string)")
        #expect(entry.summary(viewer: nil).lead == "Overdue since yesterday")
        #expect(entry.summary(viewer: nil).sign == .overdue)

        let earlier = CalendarDay.today().adding(days: -5)
        let older = InboxEntry(due: item(due: earlier), day: earlier, overdue: true, at: Date())
        #expect(older.summary(viewer: nil).lead == "Overdue since \(earlier.mediumLabel())")
    }

    @Test func notificationsFromGitHubAreNotDue() {
        let entry = InboxEntry(id: "123", reason: "assign", unread: true, updatedAt: Date(), subjectType: "Issue", title: "T", repo: "a/b", number: 1)
        #expect(!entry.isDue)
        #expect(entry.dueDay == nil)
    }

    @Test @MainActor func readAndArchivedAreKeptAndCleared() {
        let store = PersonalStore(persistent: false)
        let id = "due:issue-1:2026-10-07"
        #expect(!store.isRead(id))
        store.setRead(id, true)
        #expect(store.isRead(id))
        store.setArchived(id, true)
        #expect(store.isArchived(id))
        store.clear(id)
        #expect(!store.isRead(id))
        #expect(!store.isArchived(id))
    }
}
