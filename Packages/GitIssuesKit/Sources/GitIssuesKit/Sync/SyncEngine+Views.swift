import Foundation
import GRDB

/// A project's fields and saved views. Views are read with the project; changing, creating and deleting one needs a
/// connection and isn't queued, like changing a board's columns: a view belongs to everyone in the project.
extension SyncEngine {
    /// How long a view changed here is protected from reads that lag behind GitHub.
    static let viewGrace: TimeInterval = 60

    func recentViewChanges() -> Set<String> {
        let now = Date()
        viewsChangedHere = viewsChangedHere.filter { now.timeIntervalSince($0.value) < Self.viewGrace }
        return Set(viewsChangedHere.keys)
    }

    func recentViewDeletions() -> Set<String> {
        let now = Date()
        viewsDeletedHere = viewsDeletedHere.filter { now.timeIntervalSince($0.value) < Self.viewGrace }
        return Set(viewsDeletedHere.keys)
    }

    /// Replaces a project's fields with what GitHub has, only when something changed.
    static func writeFields(_ db: Database, projectId: String, fields: [ProjectField]) throws {
        let existing = try ProjectField.filter(Column("projectId") == projectId).order(Column("position")).fetchAll(db)
        guard existing != fields.sorted(by: { $0.position < $1.position }) else { return }
        try ProjectField.filter(Column("projectId") == projectId).deleteAll(db)
        for field in fields { try field.insert(db, onConflict: .replace) }
    }

    /// Writes a project's views as GitHub lists them. A view changed here moments ago keeps the newer copy, and one
    /// deleted here stays away, while GitHub's reads catch up. What GitHub said a filter matches is kept while the
    /// filter stays the same.
    static func writeViews(_ db: Database, projectId: String, views: [ProjectView], protected: Set<String>, deleted: Set<String>) throws {
        let existing = try ProjectView.filter(Column("projectId") == projectId).fetchAll(db)
        var local: [String: ProjectView] = [:]
        for view in existing { local[view.id] = view }
        let remote = views.filter { !deleted.contains($0.id) }
        for var view in remote {
            if let mine = local[view.id] {
                if protected.contains(view.id), (mine.updatedAt ?? "") > (view.updatedAt ?? "") {
                    if mine.position != view.position {
                        try db.execute(sql: "UPDATE projectView SET position = ? WHERE id = ?", arguments: [view.position, view.id])
                    }
                    continue
                }
                if mine.filter == view.filter {
                    view.matches = mine.matches
                    view.matchesFilter = mine.matchesFilter
                }
                if mine == view { continue }
            }
            try view.save(db)
        }
        let kept = Set(remote.map(\.id)).union(protected)
        for view in existing where !kept.contains(view.id) {
            try view.delete(db)
        }
    }

    /// Asks GitHub which items match the filters the app can't read itself, for views that have such filters.
    /// `force` asks again even when the filter is the same, because the board changed.
    func refreshViewMatches(projectId: String, force: Bool) async throws {
        guard !isDemo else { return }
        let (views, context) = try await db.reader.read { db -> ([ProjectView], FilterContext?) in
            let views = try ProjectView.filter(Column("projectId") == projectId).fetchAll(db)
            guard let project = try Project.fetchOne(db, key: projectId) else { return (views, nil) }
            let fields = try ProjectField.filter(Column("projectId") == projectId).fetchAll(db)
            return (views, FilterContext(project: project, fields: fields, options: [], viewerLogin: try KV.viewer(db)?.login))
        }
        guard let context else { return }
        for view in views {
            let needs = ProjectFilter(view.filter).needsServer(context)
            if !needs {
                if view.matches != nil {
                    try await db.writer.write { db in
                        try db.execute(sql: "UPDATE projectView SET matches = NULL, matchesFilter = NULL WHERE id = ?", arguments: [view.id])
                    }
                }
                continue
            }
            if !force, view.matches != nil, view.matchesFilter == view.filter { continue }
            let ids = try await api.matchingItemIds(projectId: projectId, filter: view.filter)
            let json = String(decoding: try JSONEncoder().encode(ids), as: UTF8.self)
            try await db.writer.write { db in
                try db.execute(
                    sql: "UPDATE projectView SET matches = ?, matchesFilter = ? WHERE id = ? AND filter = ?",
                    arguments: [json, view.filter, view.id, view.filter]
                )
            }
        }
    }

    /// Which items of a project a filter matches, as GitHub reads it: for a filter changed here and not yet saved
    /// that has parts only GitHub understands.
    public func matchingItemIds(projectId: String, filter: String) async throws -> [String]? {
        guard !isDemo else { return nil }
        return try await api.matchingItemIds(projectId: projectId, filter: filter)
    }

    // MARK: Changing views

    /// Changes a view's name, layout, filter or shown fields on GitHub. Needs a connection; not queued.
    public func updateView(_ viewId: String, change: GitHubAPI.ViewChange) async throws {
        guard !change.isEmpty, let view = try await db.reader.read({ try ProjectView.fetchOne($0, key: viewId) }) else { return }
        var updated = view
        if let name = change.name { updated.name = name }
        if let layout = change.layout { updated.layout = layout }
        if let filter = change.filter { updated.filter = filter }
        if let fields = change.visibleFieldIds { updated.visibleFieldIds = fields }
        if isDemo {
            updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        } else if let saved = try await api.updateView(id: viewId, projectId: view.projectId, change: change) {
            updated.name = saved.name
            updated.layout = saved.layout
            updated.filter = saved.filter
            updated.visibleFieldIds = saved.visibleFieldIds
            updated.updatedAt = saved.updatedAt
        }
        if updated.filter != view.filter {
            updated.matches = nil
            updated.matchesFilter = nil
        }
        let snapshot = updated
        try await db.writer.write { db in try snapshot.update(db) }
        viewsChangedHere[viewId] = Date()
        if updated.filter != view.filter { try? await refreshViewMatches(projectId: view.projectId, force: false) }
    }

    /// Deletes a view on GitHub, for everyone in the project. Needs a connection; not queued.
    public func deleteView(_ viewId: String) async throws {
        guard let view = try await db.reader.read({ try ProjectView.fetchOne($0, key: viewId) }) else { return }
        if !isDemo {
            do {
                try await api.deleteView(id: viewId)
            } catch let error as APIError where error.isNotFound {
                // Gone already, which is what was asked for.
            }
        }
        _ = try await db.writer.write { db in try view.delete(db) }
        viewsDeletedHere[viewId] = Date()
    }

    /// Creates a view like `template` (its name, layout, filter, fields, columns, grouping and order) at the end of
    /// a project's views, and returns its id. Needs a connection; not queued.
    public func createView(like template: ProjectView) async throws -> String? {
        let projectId = template.projectId
        let (project, fields, count) = try await db.reader.read { db in
            (
                try Project.fetchOne(db, key: projectId),
                try ProjectField.filter(Column("projectId") == projectId).fetchAll(db),
                try ProjectView.filter(Column("projectId") == projectId).fetchCount(db)
            )
        }
        guard let project else { return nil }
        if isDemo {
            let number = (try await db.reader.read { db in
                try Int.fetchOne(db, sql: "SELECT MAX(number) FROM projectView WHERE projectId = ?", arguments: [projectId])
            } ?? 0) + 1
            var view = template
            view.id = "demo-view-\(UUID().uuidString.lowercased())"
            view.number = number
            view.position = count
            view.updatedAt = ISO8601DateFormatter().string(from: Date())
            view.matches = nil
            view.matchesFilter = nil
            let snapshot = view
            try await db.writer.write { db in try snapshot.insert(db) }
            return view.id
        }
        func number(_ fieldId: String?) -> Int? {
            fieldId.flatMap { id in fields.first { $0.id == id }?.databaseId }
        }
        let new = GitHubAPI.NewView(
            name: template.name, layout: template.layout, filter: template.filter,
            visibleFields: template.visibleFieldIds.compactMap(number),
            groupBy: template.layout == .board ? nil : number(template.groupByFieldId),
            columnsBy: template.layout == .board ? number(template.columnFieldId) : nil,
            sortBy: template.sortBy.compactMap { sort in number(sort.fieldId).map { (field: $0, descending: sort.descending) } }
        )
        let created = try await api.createView(
            ownerLogin: project.ownerLogin, ownerIsOrg: project.ownerIsOrg, projectNumber: project.number, view: new
        )
        // GitHub lists a new view a moment after it is made.
        var views = try await api.views(projectId: projectId)
        for _ in 0..<4 where !views.contains(where: { $0.number == created }) {
            try await Task.sleep(for: .seconds(1.5))
            views = try await api.views(projectId: projectId)
        }
        guard let made = views.first(where: { $0.number == created }) else { return nil }
        viewsChangedHere[made.id] = Date()
        let protected = recentViewChanges()
        let deleted = recentViewDeletions()
        let listed = views
        try await db.writer.write { db in
            try Self.writeViews(db, projectId: projectId, views: listed, protected: protected, deleted: deleted)
        }
        try? await refreshViewMatches(projectId: projectId, force: false)
        return made.id
    }
}

extension FilterContext {
    /// The context of a project's filters on this device.
    public init(
        project: Project, fields: [ProjectField], options: [FieldOption], viewerLogin: String?,
        today: CalendarDay = .today(), parentReference: ((Item) -> String?)? = nil
    ) {
        self.init(
            viewerLogin: viewerLogin, today: today, fields: fields,
            statusFieldId: project.statusFieldId, priorityFieldId: project.priorityFieldId, dueFieldId: project.dueFieldId,
            optionName: { fieldId, optionId in
                options.first { $0.fieldId == fieldId && $0.id == optionId }?.name
                    ?? fields.first { $0.id == fieldId }?.options.first { $0.id == optionId }?.name
            },
            parentReference: parentReference ?? { item in item.parentNumber.map { "\(item.repo ?? "")#\($0)" } }
        )
    }
}
