import GRDB
import SwiftUI

/// Statuses made and shaped where they are used: "Create status …" in every status picker, and a status's icon and
/// colour wherever statuses are edited. Statuses are the project's Status field on GitHub, so making one or changing
/// its colour needs a connection; its icon, which says what it means, is the app's own (`StatusKinds`).
extension AppModel {
    // MARK: Kinds

    /// The options with the kinds chosen for statuses in the app.
    func withChosenKinds(_ options: [FieldOption]) -> [FieldOption] {
        guard !statusKinds.records.isEmpty else { return options }
        return options.map { option in
            guard option.kind == .status else { return option }
            var option = option
            option.chosenKind = statusKinds.kind(projectId: option.projectId, optionId: option.id)
            return option
        }
    }

    /// A kind chosen here or on another device redraws every status circle and moves issues between the groups.
    func followStatusKinds() {
        statusKinds.onChange = { [weak self] in self?.reloadNow() }
    }

    /// Gives a status the icon of a kind, and with it its meaning: an issue in a Done or Canceled status is closed.
    /// The kind its name suggests anyway lets the name say again, so renaming it later can change it.
    func setKind(_ kind: StatusCategory, of option: FieldOption) {
        guard option.kind == .status, !option.id.hasPrefix(LocalID.prefix) else { return }
        let named = StatusCategory.infer(from: option.name)
        withAnimation(Theme.spring) {
            statusKinds.set(kind == named ? nil : kind, projectId: option.projectId, optionId: option.id)
        }
    }

    /// The kinds in the order a board has them, for the Icon menus.
    static let statusKindsInOrder: [StatusCategory] = [.backlog, .unstarted, .started, .completed, .canceled]

    /// A kind's circle in the Icon menus, in the status's colour.
    static func kindGlyph(_ kind: StatusCategory, color: String) -> StatusGlyph {
        var glyph = statusGlyph(kind)
        if let colour = Theme.optionColor(color) { glyph.color = colour }
        return glyph
    }

    // MARK: Colours

    /// Gives a status one of GitHub's colours, on GitHub.
    func setColor(_ color: String, of option: FieldOption) {
        guard option.color != color, let index = statusOptions(projectId: option.projectId).firstIndex(where: { $0.id == option.id }) else { return }
        var options = statusOptions(projectId: option.projectId).map(\.remote)
        options[index].color = color
        saveColumns(projectId: option.projectId, options)
    }

    // MARK: Making a status

    /// A row that makes a status carries its name in its id.
    static let newStatusPrefix = "new-status:"

    static func newStatusName(_ id: String) -> String? {
        id.hasPrefix(newStatusPrefix) ? String(id.dropFirst(newStatusPrefix.count)) : nil
    }

    /// "Create status …" in an issue's status picker: for a name its board has no status of, whatever its case, when
    /// the issues it changes are all on that board.
    func newStatusRow(_ query: String, for item: Item) -> PickerItem? {
        guard canCreateStatus(for: item) else { return nil }
        return newStatusRow(query, projectId: item.projectId)
    }

    /// Whether a status can be made for an issue: when it and the issues picked with it are on one board you may change.
    func canCreateStatus(for item: Item) -> Bool {
        guard item.isOnBoard, let projectId = item.projectId, canCreateStatus(projectId: projectId) else { return false }
        return targets(for: item).allSatisfy { $0.projectId == projectId }
    }

    func canCreateStatus(projectId: String?) -> Bool {
        guard let project = projects.first(where: { $0.id == projectId }) else { return false }
        return project.viewerCanUpdate && project.statusFieldId != nil
    }

    /// The same for a board, as in a new issue's form; none on a board you may not change.
    func newStatusRow(_ query: String, projectId: String?) -> PickerItem? {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, canCreateStatus(projectId: projectId),
              !statusOptions(projectId: projectId).contains(where: { OptionMerge.sameName($0.name, name) })
        else { return nil }
        return PickerItem(
            id: Self.newStatusPrefix + name, title: String(localized: .createStatusNamed(name: name)),
            subtitle: canReachGitHub ? nil : String(localized: .needsConnection),
            icon: AnyView(Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)),
            creates: true
        )
    }

    /// Makes a status on the board on GitHub and gives it to `items`, all on that board, in one go. It shows at once,
    /// among the statuses of its kind, and its issues with it; GitHub has it a moment later. A board has no two
    /// statuses of one name, so a name it has already is that status. Needs a connection: offline, a notice says so.
    /// Returns the id the status shows under until GitHub saved it (`optionIdRemaps`), nil when none was made.
    @discardableResult
    func createStatus(named typed: String, projectId: String, for items: [Item]) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let project = projects.first(where: { $0.id == projectId }), let fieldId = project.statusFieldId else { return nil }
        let statuses = statusOptions(projectId: projectId)
        // The issues as they are now: their statuses are what GitHub is asked to change.
        let items = items.filter { $0.projectId == projectId }.map { self.item(id: $0.id) ?? $0 }
        if let existing = statuses.first(where: { OptionMerge.sameName($0.name, name) }) {
            setStatus(of: items, toOptionNamed: existing.name, id: existing.id)
            return existing.id
        }
        guard canReachGitHub else {
            status.post(Notice(
                title: String(localized: .statusCouldNotBeCreated(name: name)),
                message: String(localized: .creatingStatusNeedsConnection), isWarning: true
            ))
            return nil
        }
        let saved = statuses.filter { !$0.id.hasPrefix(LocalID.prefix) }
        let base = saved.map(\.remote)
        let kind = StatusCategory.infer(from: name)
        let new = RemoteOption(id: nil, name: name, color: Self.newStatusColor(kind: kind, among: statuses))
        var options = base
        options.insert(new, at: Self.newStatusIndex(kind: kind, among: saved))
        let place = Self.newStatusIndex(kind: kind, among: statuses)
        let localId = LocalID.make()
        do {
            try db.writer.write { db in
                try db.execute(
                    sql: "UPDATE fieldOption SET position = position + 1 WHERE projectId = ? AND fieldId = ? AND position >= ?",
                    arguments: [projectId, fieldId, place]
                )
                try FieldOption(
                    id: localId, fieldId: fieldId, projectId: projectId, kind: .status,
                    name: name, color: new.color, descr: "", position: place
                ).insert(db)
                for item in items {
                    try db.execute(sql: "UPDATE item SET statusId = ? WHERE id = ?", arguments: [localId, item.id])
                }
            }
        } catch {
            status.post(Notice(title: String(localized: .statusCouldNotBeCreated(name: name)), message: error.localizedDescription, isWarning: true))
            return nil
        }
        withAnimation(Theme.spring) { reloadNow() }
        let engine = self.engine
        Task {
            do {
                let made = try await engine.updateOptions(
                    projectId: projectId, fieldId: fieldId, kind: .status, base: base, options: options,
                    placeholders: [localId: name]
                )
                guard let id = made.first(where: { OptionMerge.sameName($0.name, name) })?.id else { return }
                optionIdRemaps[localId] = id
                reloadNow()
                // The issues' new status goes to GitHub as any change of status does, closing them in a Done one.
                guard let option = statusOptions(projectId: projectId).first(where: { $0.id == id }) else { return }
                perform(items.flatMap { statusMutations($0, option) })
            } catch {
                // Back as it was.
                try? await db.writer.write { db in
                    try db.execute(sql: "DELETE FROM fieldOption WHERE fieldId = ? AND id = ?", arguments: [fieldId, localId])
                    for item in items {
                        try db.execute(
                            sql: "UPDATE item SET statusId = ? WHERE id = ? AND statusId = ?",
                            arguments: [item.statusId, item.id, localId]
                        )
                    }
                }
                withAnimation(Theme.spring) { reloadNow() }
                status.post(Notice(
                    title: String(localized: .statusCouldNotBeCreated(name: name)),
                    message: String(localized: .changingColumnsNeedsConnection(error: error.localizedDescription)), isWarning: true
                ))
            }
        }
        return localId
    }

    /// The status a new issue's form picked: the one GitHub saved for a status made there, none while it is still
    /// being made.
    func savedOptionId(_ id: String?) -> String? {
        guard let id, id.hasPrefix(LocalID.prefix) else { return id }
        return optionIdRemaps[id]
    }

    /// Where a new status of a kind goes: after the board's statuses of that kind, or else after those of the kinds
    /// that come before it on a board (Backlog, Todo, In progress, Done, Canceled).
    static func newStatusIndex(kind: StatusCategory, among statuses: [FieldOption]) -> Int {
        if let last = statuses.lastIndex(where: { $0.statusCategory == kind }) { return last + 1 }
        if let last = statuses.lastIndex(where: { $0.statusCategory < kind }) { return last + 1 }
        return 0
    }

    /// A new status's colour: that of the board's last status of its kind, else GitHub's grey, which the app draws in
    /// the kind's own colour.
    static func newStatusColor(kind: StatusCategory, among statuses: [FieldOption]) -> String {
        statuses.last { $0.statusCategory == kind }?.color ?? "GRAY"
    }
}
