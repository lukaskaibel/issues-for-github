import Foundation
import Testing
@testable import GitIssuesKit

/// The Inbox's categories on the sample data: what each shows, the runs in From You, and which ones Settings offers.
@MainActor
@Suite("The Inbox's categories and the ones switched off in Settings")
struct InboxCategoryTests {
    private func model() throws -> AppModel {
        let model = AppModel(database: try DemoData.database(), api: FakeGitHub([]).api)
        model.reloadNow()
        return model
    }

    @Test func eachCategoryShowsItsOwn() throws {
        let model = try model()
        #expect(model.currentInboxCategory == .needsYou)
        let needs = model.inbox(.needsYou).compactMap(\.number)
        #expect(needs.contains(25) && needs.contains(15) && needs.contains(36))
        #expect(!needs.contains(39) && !needs.contains(37))
        #expect(model.inbox(.updates).compactMap(\.number).sorted() == [4, 9, 37, 39])
        #expect(model.inbox(.fromYou).compactMap(\.number).sorted() == [38, 45, 46, 47])
        #expect(model.inbox(.all).count == model.inbox(.needsYou).count + model.inbox(.fromYou).count + model.inbox(.updates).count)
    }

    @Test func assignmentsMadeTogetherAreOneRowThatUnfolds() throws {
        let model = try model()
        model.showInboxCategory(.fromYou)
        #expect(model.inboxRows.count == 2)
        guard case .batch(let run, false) = model.inboxRows[1] else {
            Issue.record("expected the run, folded")
            return
        }
        #expect(run.entries.compactMap(\.number) == [47, 46, 45])
        model.toggleInboxBatch(run)
        #expect(model.inboxRows.count == 5)
        // J and K stop on the run's row and pick all of it.
        model.inboxSelectedId = nil
        model.stepInbox(1)
        model.stepInbox(1)
        #expect(model.inboxSelectedId == run.id)
        #expect(model.inboxPicked.count == 3)
    }

    @Test func settingsOfferOnlyTheCategoriesSwitchedOn() throws {
        let model = try model()
        defer { model.inboxHiddenCategories = [] }
        model.setInboxCategory(.needsYou, shown: false)
        #expect(model.shownInboxCategories == [.fromYou, .updates, .all])
        // The Inbox opens on the first one left.
        #expect(model.currentInboxCategory == .fromYou)
        model.stepInboxCategory(-1)
        #expect(model.currentInboxCategory == .fromYou)

        // The last one stays on.
        model.setInboxCategory(.fromYou, shown: false)
        model.setInboxCategory(.updates, shown: false)
        model.setInboxCategory(.all, shown: false)
        #expect(model.shownInboxCategories == [.all])

        model.setInboxCategory(.needsYou, shown: true)
        #expect(model.shownInboxCategories == [.needsYou, .all])
    }

    @Test func theNumberCountsTheCategoriesTickedForIt() throws {
        let model = try model()
        defer {
            model.inboxHiddenCategories = []
            model.inboxBadgeCategories = [.needsYou]
        }
        func unread(_ category: InboxCategory) -> Int { model.inbox(category).filter(model.isUnread).count }
        // Needs You until chosen otherwise.
        #expect(model.inboxBadgeCategories == [.needsYou])
        #expect(model.inboxUnreadCount == unread(.needsYou))
        // Several, each entry once.
        model.setInboxBadgeCategory(.fromYou, counted: true)
        #expect(model.inboxUnreadCount == unread(.needsYou) + unread(.fromYou))
        model.setInboxBadgeCategory(.all, counted: true)
        #expect(model.inboxUnreadCount == unread(.all))
        // A category that isn't offered doesn't count, and with none there is no number.
        model.inboxBadgeCategories = [.needsYou]
        model.setInboxCategory(.needsYou, shown: false)
        #expect(model.countedInboxCategories.isEmpty)
        #expect(model.inboxUnreadCount == 0)
        model.setInboxCategory(.needsYou, shown: true)
        #expect(model.inboxUnreadCount == unread(.needsYou))
    }
}
