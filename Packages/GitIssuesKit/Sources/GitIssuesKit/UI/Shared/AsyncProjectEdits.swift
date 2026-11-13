import GRDB
import SwiftUI

private enum ProjectEditError: LocalizedError {
    case issueGone, fieldUnavailable

    var errorDescription: String? {
        switch self {
        case .issueGone: String(localized: .issueGoneMessage)
        case .fieldUnavailable: String(localized: .projectFieldUnavailable)
        }
    }
}

/// A local field transaction runs on GRDB's writer queue. Its UI stays pending until observation catches up.
@MainActor @Observable
final class AsyncProjectEdits {
    struct Expected: Sendable, Equatable {
        var target: ProjectFieldTarget
        var value: FieldValue?
        var dueDate = false
        var addingToProject: String?

        func matches(_ items: [Item], projects: [Project], fields: [ProjectField], remaps: [String: String] = [:]) -> Bool {
            let target = target.remapping(remaps)
            if let projectId = addingToProject {
                return items.contains { $0.contentId == target.issue.contentId && $0.projectId == projectId }
            }
            guard let item = target.resolve(in: items) else { return false }
            if dueDate { return item.dueDate == value?.date }
            guard let field = fields.first(where: { $0.id == target.fieldId }),
                  let project = projects.first(where: { $0.id == item.projectId }) else { return false }
            return IssueProjectSection(project: project, item: item, fields: []).value(of: field) == value
        }
    }

    private struct Pending {
        var database: ObjectIdentifier
        var expected: [Expected]
        var mutations: [Mutation]
        var order: Int
        var savedRevision: Int64?
    }

    private var pending: [UUID: Pending] = [:]
    @ObservationIgnored private var observedRevisions: [ObjectIdentifier: Int64] = [:]
    @ObservationIgnored private var nextOrder = 0
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var tailId: UUID?

    func isSaving(_ target: ProjectFieldTarget, in database: AppDatabase, remaps: [String: String] = [:]) -> Bool {
        pending.values.contains {
            $0.database == ObjectIdentifier(database) && $0.expected.contains { $0.target.remapping(remaps).id == target.remapping(remaps).id }
        }
    }

    @discardableResult
    func save(_ mutations: [Mutation], inserting: [Item] = [], expected: [Expected], in database: AppDatabase,
              onSaved: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor (Error) -> Void) -> Task<Void, Never>? {
        guard !mutations.isEmpty else { return nil }
        let databaseId = ObjectIdentifier(database)
        let targets = Set(expected.map { $0.target.id })
        let latest = pending.values.filter {
            $0.database == databaseId && $0.expected.contains { targets.contains($0.target.id) }
        }.max { $0.order < $1.order }
        // Ignore duplicate clicks, but keep a distinct choice or a reversal queued after the latest edit.
        if latest?.expected == expected, latest?.mutations == mutations { return nil }
        let id = UUID()
        nextOrder += 1
        pending[id] = Pending(database: databaseId, expected: expected, mutations: mutations, order: nextOrder)
        let previous = tail
        let task = Task {
            await previous?.value
            do {
                let revision = try await Self.persist(mutations, inserting: inserting, expected: expected, in: database)
                if var change = pending[id] {
                    change.savedRevision = revision
                    pending[id] = observedRevisions[databaseId, default: 0] >= revision ? nil : change
                }
                onSaved()
            } catch {
                pending[id] = nil
                onFailure(error)
            }
            if tailId == id { tail = nil; tailId = nil }
        }
        tail = task
        tailId = id
        return task
    }

    @discardableResult
    nonisolated static func persist(_ mutations: [Mutation], inserting: [Item], expected: [Expected], in database: AppDatabase) async throws -> Int64 {
        try await database.writer.write { db in
            for item in inserting { try item.insert(db, onConflict: .ignore) }
            var remaps: [String: String] = [:]
            for edit in expected {
                guard let contentId = edit.target.issue.contentId else { continue }
                let resolvedContentId = try CreatedIssueIDs.resolve(db, contentId)
                remaps[contentId] = resolvedContentId
                let target = edit.target.remapping([contentId: resolvedContentId])
                let copies = try Item.filter(Column("contentId") == resolvedContentId).fetchAll(db)
                let current: Item?
                if edit.addingToProject != nil {
                    current = copies.first { $0.id == edit.target.issue.itemId } ?? copies.first { $0.projectId == nil }
                } else {
                    current = target.resolve(in: copies)
                }
                guard let current else {
                    throw ProjectEditError.issueGone
                }
                if let projectId = edit.addingToProject {
                    guard let project = try Project.fetchOne(db, key: projectId), !project.closed, project.viewerCanUpdate,
                          current.projectId == nil || current.projectId == projectId else {
                        throw ProjectEditError.fieldUnavailable
                    }
                } else {
                    guard let projectId = current.projectId, let project = try Project.fetchOne(db, key: projectId),
                          !project.closed, project.viewerCanUpdate,
                          try edit.dueDate || ProjectField.fetchOne(db, key: edit.target.fieldId)?.projectId == projectId else {
                        throw ProjectEditError.fieldUnavailable
                    }
                }
                remaps[edit.target.issue.itemId] = current.id
            }
            for mutation in mutations { try Outbox.enqueue(db, mutation.remapping(remaps)) }
            return try Outbox.revision(db)
        }
    }

    func shouldAnimate(from previous: [Item], to items: [Item], projects: [Project], fields: [ProjectField], in database: AppDatabase, remaps: [String: String] = [:]) -> Bool {
        pending.values.contains { change in
            change.database == ObjectIdentifier(database) && change.expected.contains {
                !$0.matches(previous, projects: projects, fields: fields, remaps: remaps) && $0.matches(items, projects: projects, fields: fields, remaps: remaps)
            }
        }
    }

    func observe(revision: Int64, in database: AppDatabase) {
        let databaseId = ObjectIdentifier(database)
        observedRevisions[databaseId] = max(observedRevisions[databaseId, default: 0], revision)
        for (id, change) in pending where change.database == databaseId {
            if let saved = change.savedRevision, saved <= revision { pending[id] = nil }
        }
    }

    func forget(_ database: AppDatabase) {
        pending = pending.filter { $0.value.database != ObjectIdentifier(database) }
        observedRevisions[ObjectIdentifier(database)] = nil
        tail = nil
        tailId = nil
    }
}

extension AppModel {
    func performProjectEdits(_ mutations: [Mutation], inserting: [Item] = [], expected: [AsyncProjectEdits.Expected]) {
        guard !mutations.isEmpty else { return }
        let completions = parentCompletions(after: mutations)
        let starts = epicStarts(after: mutations)
        let database = db
        let engine = engine
        let mutations = mutations + completions.mutations + starts.mutations
        projectEdits.save(mutations, inserting: inserting, expected: expected, in: database,
                          onSaved: { [weak self] in
            if let self, self.db === database {
                if self.finishesWork(mutations) { AppReview.shared.finishedSomething() }
                for parent in completions.parents {
                    self.status.post(Notice(title: String(localized: .parentDoneWithSubIssues(number: parent.displayNumber)), message: parent.title, action: .openItem(parent.id)))
                }
                for epic in starts.epics {
                    self.status.post(Notice(title: String(localized: .epicStartedWithIssue(number: epic.displayNumber)), message: epic.title, action: .openItem(epic.id)))
                }
            }
            Task { await engine.kick() }
        }, onFailure: { [weak self] error in
            guard let self, self.db === database else { return }
            self.status.post(Notice(title: String(localized: .changeCouldNotBeSaved), message: error.localizedDescription, isWarning: true))
        })
    }
}
