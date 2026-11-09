import SwiftUI

/// How you see a project's All Issues, where it differs from its list: as a board, with the board's columns you hid
/// or put in another order. GitHub has no view behind All Issues, so all of it stays on this device, as the columns
/// you hide on a view's board do, and the board's statuses on GitHub keep their order.
struct AllIssuesDisplay: Codable, Equatable {
    var layout: ViewMode?
    /// The board's columns you hid, by their ids.
    var hiddenColumnIds: [String]?
    /// The columns in the order you put them in, by their ids. One that wasn't there then (a new status, or the issues
    /// on no board once there are some again) goes after the column before it in the board's own order.
    var columnOrder: [String]?

    var isEmpty: Bool { self == AllIssuesDisplay() }
}

extension BoardColumn {
    /// The column of All Issues' board with the issues on no board, which wait for a place on it. Cards leave it for
    /// a status, which puts them on the board; none can go into it.
    var isOnNoBoard: Bool { id == ListSection.noProjectId }
}

extension AppModel {
    // MARK: Board or list

    func allIssuesDisplay(projectId: String) -> AllIssuesDisplay {
        allIssuesDisplays[projectId] ?? AllIssuesDisplay()
    }

    /// Board or list for a project's All Issues: a list, unless you made it a board.
    func allIssuesLayout(projectId: String) -> ViewMode {
        allIssuesDisplay(projectId: projectId).layout ?? .list
    }

    func setAllIssuesLayout(_ mode: ViewMode, projectId: String) {
        guard allIssuesLayout(projectId: projectId) != mode else { return }
        changeAllIssuesDisplay(projectId: projectId) { $0.layout = mode }
    }

    private func changeAllIssuesDisplay(projectId: String, _ change: (inout AllIssuesDisplay) -> Void) {
        var display = allIssuesDisplay(projectId: projectId)
        change(&display)
        // A list is what All Issues is by itself.
        if display.layout == .list { display.layout = nil }
        if display.hiddenColumnIds?.isEmpty == true { display.hiddenColumnIds = nil }
        if display.columnOrder?.isEmpty == true { display.columnOrder = nil }
        allIssuesDisplays[projectId] = display.isEmpty ? nil : display
        rebuild()
    }

    // MARK: Columns

    /// All Issues as a board: first the issues on no board, which wait for a place on it, while there are any; then a
    /// column per status, as on the board. In the order you put them in.
    func allIssuesColumns(projectId: String, items: [Item]) -> [BoardColumn] {
        var result: [BoardColumn] = []
        let onNoBoard = items.filter { !$0.isOnBoard }
        if !onNoBoard.isEmpty {
            // As the list has them: under their parent, but not by epic, which only a board's issues are planned in.
            let (shown, nesting) = Nesting.arrange(onNoBoard, folded: foldedParents)
            result.append(BoardColumn(
                id: ListSection.noProjectId, option: nil, glyph: .noProject, items: shown, nesting: nesting,
                label: String(localized: .noProject)
            ))
        }
        result += statusColumns(projectId: projectId, items: items.filter(\.isOnBoard))
        guard let order = allIssuesDisplay(projectId: projectId).columnOrder else { return result }
        return Self.arrangedColumnIds(result.map(\.id), custom: order).compactMap { id in result.first { $0.id == id } }
    }

    /// Columns in the order you put them in (`custom`): those it names first, in that order, also the ones not there
    /// now, so each keeps its place for when it is back; each of the others (`natural`, in the board's own order) right
    /// after the one before it there that has its place, or first.
    nonisolated static func arrangedColumnIds(_ natural: [String], custom: [String]) -> [String] {
        var result: [String] = []
        for id in custom where !result.contains(id) { result.append(id) }
        guard !result.isEmpty else { return natural }
        for (index, id) in natural.enumerated() where !result.contains(id) {
            if let before = natural[..<index].last(where: { result.contains($0) }), let at = result.firstIndex(of: before) {
                result.insert(id, at: at + 1)
            } else {
                result.insert(id, at: 0)
            }
        }
        return result
    }

    /// Moves a column of All Issues' board to `index` among `shown`, the columns the board shows in their order. Columns
    /// it leaves out (hidden ones, and those that aren't there now) keep their places.
    /// `animated: false` for a column dropped by hand, which is in its new place already.
    func moveColumn(_ id: String, among shown: [String], to index: Int, allIssuesOf projectId: String, animated: Bool = true) {
        let present = columns(for: .allIssues(projectId)).map(\.id)
        let kept = allIssuesDisplay(projectId: projectId).columnOrder ?? []
        let all = Self.arrangedColumnIds(present, custom: kept)
        // A status deleted on GitHub doesn't come back; the issues on no board and those without a status may.
        let lasting: Set<String> = Set(present).union([ListSection.noProjectId, BoardColumn.noStatusId])
        let order = Self.columnOrder(all, moving: id, among: shown, to: index).filter(lasting.contains)
        guard order != all.filter(lasting.contains) else { return }
        let save = { self.changeAllIssuesDisplay(projectId: projectId) { $0.columnOrder = order } }
        if animated { withAnimation(Theme.spring, save) } else { save() }
    }

    /// Back to the board's own order of columns, with the issues on no board first.
    func resetColumnOrder(allIssuesOf projectId: String) {
        withAnimation(Theme.spring) {
            changeAllIssuesDisplay(projectId: projectId) { $0.columnOrder = nil }
        }
    }

    // MARK: Hiding columns

    /// Whether the board of a scope can hide columns: a view's, and All Issues'. A milestone's board shows every column.
    func canHideColumns(in scope: Scope) -> Bool {
        switch scope {
        case .project(let projectId): currentView(projectId: projectId) != nil
        case .allIssues: true
        default: false
        }
    }

    /// The columns you hid on the board of a scope, in the board's order, with their cards.
    func hiddenColumns(in scope: Scope) -> [BoardColumn] {
        switch scope {
        case .project(let projectId):
            return hiddenColumns(projectId: projectId)
        case .allIssues(let projectId):
            let hidden = Set(allIssuesDisplay(projectId: projectId).hiddenColumnIds ?? [])
            guard !hidden.isEmpty else { return [] }
            return columns(for: scope).filter { hidden.contains($0.id) }
        default:
            return []
        }
    }

    /// Hides a column of the board of a scope, or shows it again: a view's or All Issues'. Its cards leave the board
    /// with it, and picks or the keyboard focus on them go.
    func setColumn(_ columnId: String, hidden: Bool, in scope: Scope) {
        switch scope {
        case .project(let projectId):
            if let view = currentView(projectId: projectId) { setColumn(columnId, hidden: hidden, of: view) }
        case .allIssues(let projectId):
            var ids = allIssuesDisplay(projectId: projectId).hiddenColumnIds ?? []
            ids.removeAll { $0 == columnId }
            if hidden { ids.append(columnId) }
            withAnimation(Theme.spring) {
                changeAllIssuesDisplay(projectId: projectId) { $0.hiddenColumnIds = ids }
            }
            guard hidden else { return }
            let gone = Set(columns(for: scope).filter { $0.id == columnId }.flatMap(\.nesting.members).map(\.id))
            selectedIds.subtract(gone)
            if let hovered = hoveredItemId, gone.contains(hovered) { hoveredItemId = nil }
        default:
            break
        }
    }

    // MARK: Moving cards

    /// Whether a card can land on the board of a scope: one of the board's, or in All Issues one of its repositories'
    /// on no board too.
    func fits(_ item: Item, onBoardOf scope: Scope) -> Bool {
        guard let projectId = scope.projectId else { return false }
        if item.projectId == projectId { return true }
        guard case .allIssues = scope, !item.isOnBoard, let repoId = item.repoId else { return false }
        return repos(projectId: projectId).contains { $0.id == repoId }
    }

    /// Whether a card can be dropped into a column: anything but into All Issues' issues on no board, since taking an
    /// issue off its board would lose what it has there. One of them can stay where it is.
    func accepts(_ column: BoardColumn, _ item: Item) -> Bool {
        !column.isOnNoBoard || !item.isOnBoard && column.nesting.members.contains { $0.id == item.id }
    }

    /// Puts an issue on no board, dropped into a status column of All Issues' board, on that board with the column's
    /// status. It goes at the end of the column, where the board puts what is added to it.
    func addToBoard(_ items: [Item], in column: BoardColumn, projectId: String) {
        guard !column.isOnNoBoard, let project = projects.first(where: { $0.id == projectId }) else { return }
        addToProject(items.filter { !$0.isOnBoard }, project: project, status: column.option)
    }
}
