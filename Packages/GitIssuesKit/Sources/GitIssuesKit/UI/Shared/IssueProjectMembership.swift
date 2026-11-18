import Foundation
import GRDB
import SwiftUI

enum IssueProjectMembership {
    static func change(_ item: Item, project: Project, items: [Item], isMember: Bool) -> Mutation? {
        guard !project.closed, project.viewerCanUpdate, item.kind != .draft, let contentId = item.contentId else { return nil }
        let member = items.first { $0.projectId == project.id && $0.contentId == contentId }
        guard (member != nil) != isMember else { return nil }
        var target = member ?? item
        if member == nil {
            target.id = LocalID.make()
            target.projectId = project.id
            target.statusId = nil
            target.priorityId = nil
            target.dueDate = nil
            target.fieldValues = [:]
            target.remoteUpdatedAt = nil
        }
        return .setProjectMembership(.init(item: target, isMember: isMember, base: member != nil))
    }

    /// Queues the change for the issue as the database has it now. Returns it, or nil when there is nothing to change.
    @discardableResult
    static func save(_ item: Item, projectId: String, isMember: Bool, in database: AppDatabase) throws -> Mutation? {
        try database.writer.write { db in
            guard let project = try Project.fetchOne(db, key: projectId), !project.closed, project.viewerCanUpdate,
                  let localContentId = item.contentId, item.kind != .draft else { return nil }
            let contentId = try CreatedIssueIDs.resolve(db, localContentId)
            // Resolve the current membership here: sync may have replaced its temporary ID since the view was drawn.
            let copies = try Item.filter(Column("contentId") == contentId).fetchAll(db)
            var source: Item
            if let current = copies.first {
                source = current
            } else if item.isDetached,
                      let notification = try InboxEntry.filter(Column("contentId") == contentId && Column("missing") == false)
                        .order(Column("updatedAt").desc).fetchOne(db),
                      let current = Item(detached: notification) {
                source = current
            } else {
                // A click must not recreate an ordinary issue that sync has since removed.
                return nil
            }
            source.contentId = contentId
            guard let mutation = change(source, project: project, items: copies, isMember: isMember) else { return nil }
            try Outbox.enqueue(db, mutation)
            return mutation
        }
    }
}

extension AppModel {
    /// Puts an issue on a project or takes it off. Taking it off shows at once and waits a few seconds before it goes
    /// to GitHub, where it would take the values of that project's fields along, so a message can take it back.
    func setMembership(of item: Item, in project: Project, isMember: Bool) {
        guard let project = projects.first(where: { $0.id == project.id }) else { return }
        let change: Mutation?
        do {
            change = try IssueProjectMembership.save(item, projectId: project.id, isMember: isMember, in: db)
        } catch {
            status.post(Notice(title: String(localized: .changeCouldNotBeSaved), message: error.localizedDescription, isWarning: true))
            return
        }
        guard let change else { return }
        reloadNow()
        let engine = engine
        Task { await engine.kick() }
        guard case .setProjectMembership(var removal) = change, !removal.isMember else { return }
        // Folded into the removal while it waits, this leaves GitHub's card alone and brings its values back here.
        removal.isMember = true
        removal.base = false
        let notice = Notice(
            title: String(localized: .queuedRemovedFromProject(project: project.title)),
            message: "\(removal.item.displayNumber) \(removal.item.title)",
            action: .undo([.setProjectMembership(removal)])
        )
        status.post(notice)
        let status = status
        Task {
            // Once it has been sent the card's values are gone, so the offer ends with the wait.
            try? await Task.sleep(for: .seconds(SyncEngine.undoWindow))
            status.dismiss(notice.id)
            try? await Task.sleep(for: .seconds(0.2))
            await engine.kick()
        }
    }

    func isIssueProjectUnfolded(_ section: IssueProjectSection) -> Bool {
        section.isPrimary || unfoldedIssueProjects.contains(section.project.id)
    }

    func toggleIssueProject(_ section: IssueProjectSection) {
        if !unfoldedIssueProjects.insert(section.project.id).inserted { unfoldedIssueProjects.remove(section.project.id) }
    }

    func showsEmptyFields(of section: IssueProjectSection) -> Bool {
        issueProjectsShowingEmptyFields.contains(section.project.id)
    }

    func toggleEmptyFields(of section: IssueProjectSection) {
        if !issueProjectsShowingEmptyFields.insert(section.project.id).inserted {
            issueProjectsShowingEmptyFields.remove(section.project.id)
        }
    }
}
