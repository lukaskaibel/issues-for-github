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

    /// GRDB's async write suspends the caller while its writer queue commits the local change.
    static func save(_ item: Item, projectId: String, isMember: Bool, in database: AppDatabase) async throws -> Int64? {
        try await database.writer.write { db in
            guard let project = try Project.fetchOne(db, key: projectId), !project.closed, project.viewerCanUpdate,
                  let localContentId = item.contentId, item.kind != .draft else { return nil }
            let contentId = try CreatedIssueIDs.resolve(db, localContentId)
            // Resolve the current membership here: sync may have replaced its temporary ID since the click.
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
                // A queued click must not recreate an ordinary issue that sync has since removed.
                return nil
            }
            source.contentId = contentId
            guard let mutation = change(source, project: project, items: copies, isMember: isMember) else { return nil }
            try Outbox.enqueue(db, mutation)
            return try Outbox.revision(db)
        }
    }
}

/// Tracks a local save until both the transaction and its observed UI update have completed.
@MainActor @Observable
final class ProjectMembershipChanges {
    private struct Key: Hashable {
        var database: ObjectIdentifier
        var contentId: String
        var projectId: String
    }

    private struct Pending {
        var savedRevision: Int64?
    }

    private var pending: [Key: Pending] = [:]
    @ObservationIgnored private var observedRevisions: [ObjectIdentifier: Int64] = [:]

    func isSaving(_ item: Item, projectId: String, in database: AppDatabase, remaps: [String: String] = [:]) -> Bool {
        guard let contentId = item.contentId else { return false }
        return pending.keys.contains {
            $0.database == ObjectIdentifier(database) && $0.projectId == projectId
                && (remaps[$0.contentId] ?? $0.contentId) == (remaps[contentId] ?? contentId)
        }
    }

    @discardableResult
    func save(_ item: Item, project: Project, isMember: Bool, in database: AppDatabase, remaps: [String: String] = [:],
              onSaved: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor (Error) -> Void) -> Task<Void, Never>? {
        guard let contentId = item.contentId, item.kind != .draft, !project.closed, project.viewerCanUpdate else { return nil }
        let key = Key(database: ObjectIdentifier(database), contentId: contentId, projectId: project.id)
        guard !isSaving(item, projectId: project.id, in: database, remaps: remaps) else { return nil }
        pending[key] = Pending()
        return Task {
            do {
                if let revision = try await IssueProjectMembership.save(item, projectId: project.id, isMember: isMember, in: database) {
                    if var change = pending[key] {
                        change.savedRevision = revision
                        pending[key] = observedRevisions[key.database, default: 0] >= revision ? nil : change
                    }
                    onSaved()
                } else {
                    pending[key] = nil
                }
            } catch {
                pending[key] = nil
                onFailure(error)
            }
        }
    }

    func shouldAnimate(from previous: [Item], to items: [Item], in database: AppDatabase, remaps: [String: String] = [:]) -> Bool {
        pending.contains { key, _ in
            key.database == ObjectIdentifier(database)
                && contains(key, in: previous, remaps: remaps) != contains(key, in: items, remaps: remaps)
        }
    }

    func observe(revision: Int64, in database: AppDatabase) {
        let databaseId = ObjectIdentifier(database)
        observedRevisions[databaseId] = max(observedRevisions[databaseId, default: 0], revision)
        for (key, change) in pending where key.database == databaseId {
            if let saved = change.savedRevision, saved <= revision { pending[key] = nil }
        }
    }

    func forget(_ database: AppDatabase) {
        pending = pending.filter { $0.key.database != ObjectIdentifier(database) }
        observedRevisions[ObjectIdentifier(database)] = nil
    }

    private func contains(_ key: Key, in items: [Item], remaps: [String: String]) -> Bool {
        items.contains {
            $0.contentId.map { remaps[$0] ?? $0 } == (remaps[key.contentId] ?? key.contentId) && $0.projectId == key.projectId
        }
    }
}

extension AppModel {
    func setMembership(of item: Item, in project: Project, isMember: Bool) {
        guard let project = projects.first(where: { $0.id == project.id }) else { return }
        let database = db
        let engine = engine
        projectMembershipChanges.save(item, project: project, isMember: isMember, in: database, remaps: status.idRemaps, onSaved: {
            Task { await engine.kick() }
        }, onFailure: { [weak self] error in
            guard let self, self.db === database else { return }
            self.status.post(Notice(title: String(localized: .changeCouldNotBeSaved), message: error.localizedDescription, isWarning: true))
        })
    }
}
