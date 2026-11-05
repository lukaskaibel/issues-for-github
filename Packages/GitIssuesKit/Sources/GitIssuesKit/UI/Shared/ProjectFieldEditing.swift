import SwiftUI

enum ProjectFieldEditing {
    static func label(field: ProjectField, value: FieldValue?) -> String {
        if let option = field.options.first(where: { $0.id == value?.optionId }) { return option.name }
        if let ids = value?.optionIds { return field.options.filter { ids.contains($0.id) }.map(\.name).formatted(.list(type: .and)) }
        if let iteration = field.iterations.first(where: { $0.id == value?.iterationId }) { return iteration.title }
        if let day = value?.date.flatMap(CalendarDay.init) { return day.mediumLabel() }
        return value?.text ?? value?.number?.formatted() ?? String(localized: .projectFieldEmpty)
    }

    static func picked(_ id: String, field: ProjectField, current: FieldValue?) -> FieldValue? {
        guard !id.isEmpty else { return nil }
        if field.kind == .multiSelect {
            var ids = Set(current?.optionIds ?? [])
            if !ids.insert(id).inserted { ids.remove(id) }
            return ids.isEmpty ? nil : FieldValue(optionIds: ids.sorted())
        }
        return field.kind == .iteration ? FieldValue(iterationId: id) : FieldValue(optionId: id)
    }
}

extension AppModel {
    func projectFieldChoices(field: ProjectField, value: FieldValue?) -> [PickerItem] {
        let clear = PickerItem(id: "", title: String(localized: .projectFieldClear), selected: value == nil,
                               icon: AnyView(Image(systemName: "minus").foregroundStyle(Theme.textTertiary)))
        if field.kind == .iteration {
            return [clear] + field.orderedIterations.map { iteration in
                PickerItem(id: iteration.id, title: iteration.title, subtitle: iterationRange(iteration),
                           selected: value?.iterationId == iteration.id, icon: AnyView(IterationIcon(size: 13)))
            }
        }
        return [clear] + field.options.map { option in
            PickerItem(id: option.id, title: option.name, subtitle: option.descr.isEmpty ? nil : option.descr,
                       selected: value?.optionId == option.id || value?.optionIds?.contains(option.id) == true,
                       icon: AnyView(Circle().fill(Theme.optionColor(option.color) ?? Theme.textTertiary).frame(width: 9, height: 9)))
        }
    }

    func saveProjectField(_ target: ProjectFieldTarget, value: FieldValue?) {
        guard let item = item(targetedBy: target), let field = field(id: target.fieldId),
              field.projectId == item.projectId, project(of: item)?.viewerCanUpdate == true else { return }
        setValue(value, of: field, for: [item])
    }

    /// The due-date shortcut can create the project's first date field. Resolve its own card again when picked,
    /// since adding the membership may have replaced its temporary id while the calendar was open.
    func saveProjectDueDate(_ target: ProjectFieldTarget, to day: CalendarDay?) {
        guard let item = item(targetedBy: target), let project = project(of: item),
              !project.closed, project.viewerCanUpdate else { return }
        setDueDate(of: [item], to: day)
    }
}
