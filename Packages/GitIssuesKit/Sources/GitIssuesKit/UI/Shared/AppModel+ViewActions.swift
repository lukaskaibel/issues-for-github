import SwiftUI

/// Changing a project's views on GitHub: saving a filter, the layout and fields, renaming, creating and deleting.
/// These need a connection and aren't queued, like changing a board's columns: a view is everyone's.
extension AppModel {
    /// Saves the filter changed here to the view on GitHub.
    func saveFilter(of view: ProjectView) {
        guard filterChanged(view) else { return }
        let text = filterText(of: view)
        changeView(view, failure: .viewSaveFailed(view: view.name)) { engine in
            try await engine.updateView(view.id, change: .init(filter: text))
        } done: { model in
            if model.draftFilters[view.id] == text { model.draftFilters[view.id] = nil }
        }
    }

    /// Saves your layout and shown fields to the view on GitHub; columns, grouping and order stay yours.
    func saveDisplay(of view: ProjectView) {
        let display = display(of: view)
        var change = GitHubAPI.ViewChange()
        if let layout = display.layout {
            // A board or a list chosen for a roadmap, or a list for a board, becomes GitHub's board or table.
            if layout == .board { change.layout = .board } else if view.layout != .table { change.layout = .table }
        }
        if let fields = display.visibleFieldIds { change.visibleFieldIds = fields }
        guard !change.isEmpty || display.layout != nil else { return }
        let saved = change
        changeView(view, failure: .viewSaveFailed(view: view.name)) { engine in
            if !saved.isEmpty { try await engine.updateView(view.id, change: saved) }
        } done: { model in
            model.changeDisplay(of: model.view(id: view.id) ?? view) { saved in
                saved.layout = nil
                saved.visibleFieldIds = nil
            }
        }
    }

    func rename(_ view: ProjectView, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != view.name else { return }
        changeView(view, failure: .viewSaveFailed(view: view.name)) { engine in
            try await engine.updateView(view.id, change: .init(name: trimmed))
        } done: { _ in }
    }

    /// Deletes a view on GitHub. The tab next to it opens if it was on screen.
    func delete(_ view: ProjectView) {
        let list = views(projectId: view.projectId)
        let next = list.firstIndex(of: view).flatMap { index in index + 1 < list.count ? list[index + 1] : index > 0 ? list[index - 1] : nil }
        changeView(view, failure: .viewDeleteFailed(view: view.name)) { engine in
            try await engine.deleteView(view.id)
        } done: { model in
            model.draftFilters[view.id] = nil
            model.viewDisplays[view.id] = nil
            if model.selectedViewIds[view.projectId] == view.id, let next { model.show(next) }
            model.rebuild()
        }
    }

    /// A view like `source`, as it shows to you, for a new one to start from: its filter, layout, fields, columns,
    /// grouping and order.
    func template(from source: ProjectView?, projectId: String, name: String = "") -> ProjectView {
        guard let source else {
            return ProjectView(id: LocalID.make(), projectId: projectId, number: 0, name: name, layout: .board, filter: "", position: 0)
        }
        let mode = layout(of: source)
        return ProjectView(
            id: LocalID.make(), projectId: projectId, number: 0, name: name,
            layout: mode == .board ? .board : (source.layout == .roadmap ? .roadmap : .table),
            filter: filterText(of: source), visibleFieldIds: shownFieldIds(of: source),
            groupByFieldId: mode == .list ? groupField(of: source)?.id : nil,
            columnFieldId: mode == .board ? columnField(of: source)?.id : nil,
            sortBy: sort(of: source), position: 0
        )
    }

    /// Creates a view on GitHub and opens it. Returns whether it worked.
    @discardableResult
    func createView(_ template: ProjectView) async -> Bool {
        let engine = self.engine
        savingViewIds.insert(template.id)
        defer { savingViewIds.remove(template.id) }
        do {
            guard let id = try await engine.createView(like: template) else { throw APIError.decoding("No view") }
            reloadNow()
            if let view = view(id: id) { show(view) }
            return true
        } catch {
            status.post(Notice(title: String(localized: .viewCreateFailed), message: error.localizedDescription, isWarning: true))
            return false
        }
    }

    /// Whether views can be saved right now: GitHub has to be reachable.
    var canReachGitHub: Bool {
        status.phase != .offline
    }

    private func changeView(
        _ view: ProjectView, failure: LocalizedStringResource,
        _ work: @escaping @Sendable (SyncEngine) async throws -> Void, done: @escaping (AppModel) -> Void
    ) {
        let engine = self.engine
        savingViewIds.insert(view.id)
        Task {
            defer { savingViewIds.remove(view.id) }
            do {
                try await work(engine)
                reloadNow()
                done(self)
            } catch {
                status.post(Notice(title: String(localized: failure), message: error.localizedDescription, isWarning: true))
            }
        }
    }
}
