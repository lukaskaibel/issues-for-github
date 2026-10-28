import Foundation

/// A drag's date snapshot. Moving the pointer changes this value; only dropping it queues a write.
struct TimelineDateEdit: Equatable {
    enum Part: Equatable { case move, start, end }

    struct Endpoint: Equatable {
        var field: ProjectField
        var day: CalendarDay
    }

    var itemId: String
    var projectId: String
    var start: Endpoint?
    var end: Endpoint?

    /// A single date moves as a point; only a range has two independent resize handles.
    var canResize: Bool {
        guard let start, let end else { return false }
        return start.day <= end.day
    }

    var span: TimelineSpan {
        if let start, let end { return .stretch(min(start.day, end.day), max(start.day, end.day)) }
        return .day((end ?? start)!.day, milestone: false)
    }

    static func make(
        item: Item, dates: (start: ProjectField?, end: ProjectField?), context: FilterContext,
        displayedSpan: TimelineSpan?, canUpdate: Bool
    ) -> Self? {
        guard canUpdate, let projectId = item.projectId else { return nil }
        func endpoint(_ field: ProjectField?) -> Endpoint? {
            guard let field, field.kind == .date, field.projectId == projectId,
                  let text = context.value(of: field, in: item)?.date, let day = CalendarDay(text) else { return nil }
            return Endpoint(field: field, day: day)
        }
        let start = endpoint(dates.start)
        let end = endpoint(dates.end)
        guard start != nil || end != nil else { return nil }
        let edit = Self(itemId: item.id, projectId: projectId, start: start, end: end)
        // An iteration takes precedence over a lone date. Neither it nor a milestone is an issue's date to move.
        guard edit.span == displayedSpan else { return nil }
        return edit
    }

    func adjusted(by days: Int, part: Part) -> Self {
        var next = self
        switch part {
        case .move:
            if let start { next.start?.day = start.day.adding(days: days) }
            if let end { next.end?.day = end.day.adding(days: days) }
        case .start:
            guard canResize, let start, let end else { return self }
            next.start?.day = min(start.day.adding(days: days), end.day)
        case .end:
            guard canResize, let start, let end else { return self }
            next.end?.day = max(end.day.adding(days: days), start.day)
        }
        return next
    }

    /// Uses the same mutations as the field pickers. Due dates have their own column and mutation.
    func mutations(from original: Self, item: Item, dueFieldId: String?) -> [Mutation] {
        guard itemId == original.itemId, projectId == original.projectId,
              item.id == itemId, item.projectId == projectId,
              start?.field == original.start?.field, end?.field == original.end?.field else { return [] }
        let pairs = [(original.start, start), (original.end, end)]
        // If a teammate changed an endpoint during the drag, leave the newer range alone.
        for (before, _) in pairs {
            guard let before else { continue }
            let current = before.field.id == dueFieldId ? item.dueDate : item.fieldValues[before.field.id]?.date
            guard current.flatMap(CalendarDay.init) == before.day else { return [] }
        }
        return pairs.compactMap { before, after in
            guard let before, let after, before.day != after.day else { return nil }
            if after.field.id == dueFieldId {
                return .setDate(.init(itemId: itemId, projectId: projectId, date: after.day.string, base: item.dueDate))
            }
            return .setProjectField(.init(
                itemId: itemId, projectId: projectId, fieldId: after.field.id, fieldName: after.field.name,
                value: FieldValue(date: after.day.string), valueName: nil, base: item.fieldValues[after.field.id]
            ))
        }
    }
}

extension AppModel {
    func timelineDateEdit(for item: Item, view: ProjectView) -> TimelineDateEdit? {
        guard item.projectId == view.projectId, let context = filterContext(projectId: view.projectId) else { return nil }
        let dates = timelineDateFields(projectId: view.projectId)
        let span = timelineSpan(of: item, view: view, dates: dates, iteration: timelineIterationField(of: view))
        return TimelineDateEdit.make(
            item: item, dates: dates, context: context, displayedSpan: span,
            canUpdate: projects.first { $0.id == view.projectId }?.viewerCanUpdate == true
        )
    }

    func commitTimelineDateEdit(original: TimelineDateEdit, edited: TimelineDateEdit) {
        guard let project = projects.first(where: { $0.id == original.projectId }), project.viewerCanUpdate,
              let item = allItems.first(where: { $0.id == original.itemId }) else { return }
        guard [original.start, original.end].compactMap({ $0 }).allSatisfy({ endpoint in
            field(id: endpoint.field.id).map { $0.projectId == original.projectId && $0.kind == .date } == true
        }) else { return }
        perform(edited.mutations(from: original, item: item, dueFieldId: project.dueFieldId))
    }
}
