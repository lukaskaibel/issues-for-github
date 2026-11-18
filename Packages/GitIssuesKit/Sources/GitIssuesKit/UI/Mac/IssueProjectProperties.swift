#if os(macOS)
import SwiftUI

/// A line of an issue's details for a project's field. Field names are the project's, so a long one wraps rather than
/// widening every label.
struct IssuePropertyRow<Content: View>: View {
    var title: Text
    @Binding var labelWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            title
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: labelWidth, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 30)
    }
}

/// The open projects an issue is on, in its details: the one it was opened from with the fields that have a value,
/// the others folded under their name and status, and a way to add more.
struct IssueProjectsProperties: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var item: Item
    @Binding var labelWidth: CGFloat

    var body: some View {
        ForEach(IssueProjectSection.sections(for: item, items: model.allItems, projects: model.projects, fields: model.fields)) { section in
            Group {
                if section.isPrimary {
                    PrimaryIssueProject(section: section, labelWidth: $labelWidth)
                } else {
                    OtherIssueProject(section: section, labelWidth: $labelWidth)
                }
            }
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
        }
        if item.isOnBoard, item.kind != .draft, item.contentId != nil {
            IssueProjectsButton(item: item)
        }
    }
}

private struct PrimaryIssueProject: View {
    @Environment(AppModel.self) private var model
    var section: IssueProjectSection
    @Binding var labelWidth: CGFloat
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            IssuePropertyRow(title: Text(.project), labelWidth: $labelWidth) {
                HStack(spacing: 8) {
                    ProjectIcon(projectId: section.project.id)
                    Text(section.project.title).lineLimit(1)
                    Spacer(minLength: 4)
                    RemoveProjectButton(section: section, visible: hovering)
                }
                .padding(.leading, 8)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            ProjectFieldRows(section: section, labelWidth: $labelWidth)
        }
    }
}

private struct OtherIssueProject: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var section: IssueProjectSection
    @Binding var labelWidth: CGFloat
    @State private var hovering = false

    private var unfolded: Bool { model.isIssueProjectUnfolded(section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.spring) { model.toggleIssueProject(section) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(unfolded ? 90 : 0))
                            .frame(width: 10)
                        ProjectIcon(projectId: section.project.id)
                        Text(section.project.title).lineLimit(1)
                        Spacer(minLength: 4)
                        if !unfolded, section.project.statusFieldId != nil {
                            StatusIcon(glyph: model.glyph(of: section.item))
                            Text(model.statusText(of: section.item))
                                .font(.small)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.project.title)
                .accessibilityValue(Text(unfolded ? .sectionOpen : .sectionFolded))
                .accessibilityIdentifier("toggle-project-\(section.project.id)")
                RemoveProjectButton(section: section, visible: hovering)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            if unfolded {
                ProjectFieldRows(section: section, labelWidth: $labelWidth)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.project.title)
    }
}

private struct RemoveProjectButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var section: IssueProjectSection
    var visible: Bool

    var body: some View {
        if section.item.kind != .draft, section.project.viewerCanUpdate {
            IconButton(systemName: "xmark", label: String(localized: .removeIssueFromProject(project: section.project.title)), size: 20) {
                withAnimation(reduceMotion ? nil : Theme.spring) {
                    model.setMembership(of: section.item, in: section.project, isMember: false)
                }
            }
            .opacity(visible ? 1 : 0)
            .accessibilityIdentifier("remove-project-\(section.project.id)")
        }
    }
}

/// A project's fields with a value, and behind "n more fields" those without.
private struct ProjectFieldRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var section: IssueProjectSection
    @Binding var labelWidth: CGFloat

    var body: some View {
        let showsEmpty = model.showsEmptyFields(of: section)
        // All of them in the project's order once they show, so a field doesn't jump when it gets a value.
        ForEach(showsEmpty ? section.listedFields : section.filledFields) { field in
            IssuePropertyRow(title: Text(verbatim: field.name), labelWidth: $labelWidth) {
                ProjectFieldProperty(section: section, field: field)
            }
        }
        if showsEmpty, section.offersDueField {
            IssuePropertyRow(title: Text(.dueDate), labelWidth: $labelWidth) {
                ProjectDueDateProperty(item: section.item, canEdit: section.project.viewerCanUpdate)
            }
        }
        if section.hiddenCount > 0 {
            IssuePropertyRow(title: Text(verbatim: ""), labelWidth: $labelWidth) {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.spring) { model.toggleEmptyFields(of: section) }
                } label: {
                    (showsEmpty ? Text(.projectFieldsFewer) : Text(.projectFieldsMore(count: section.hiddenCount)))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .hoverFill(radius: 8, fill: Theme.partHover)
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityIdentifier("project-more-fields-\(section.project.id)")
            }
        }
    }
}

struct IssueProjectsButton: View {
    var item: Item
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Label(.addToProjectPlaceholder, systemImage: "plus")
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open, radius: 8, fill: Theme.partHover)
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityIdentifier("issue-projects")
        .dropdown(isPresented: $open) { close in
            IssueProjectsPicker(item: item, close: close)
        }
    }
}

private struct IssueProjectsPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var item: Item
    var close: () -> Void

    var body: some View {
        if let current = model.item(referencedBy: IssueReference(item)) {
            let memberships = Set(model.allItems.filter { $0.contentId == current.contentId }.compactMap(\.projectId))
            let projects = model.openProjects.filter(\.viewerCanUpdate)
            PickerList(placeholder: String(localized: .searchIssueProjects), items: projects.map { project in
                PickerItem(id: project.id, title: project.title, subtitle: project.ownerLogin,
                           selected: memberships.contains(project.id), icon: AnyView(ProjectIcon(projectId: project.id)))
            }, multiple: true, width: 320, onPick: { id in
                guard let project = model.projects.first(where: { $0.id == id }) else { return }
                withAnimation(reduceMotion ? nil : Theme.spring) {
                    model.setMembership(of: current, in: project, isMember: !memberships.contains(id))
                }
            }, onClose: close)
        } else {
            Color.clear.task { close() }
        }
    }
}

private struct ProjectFieldProperty: View {
    @Environment(AppModel.self) private var model
    var section: IssueProjectSection
    var field: ProjectField
    @State private var open = false

    private var value: FieldValue? { section.value(of: field) }
    private var selectedOption: FieldChoice? {
        if field.id == section.project.statusFieldId {
            return model.statusOption(of: section.item).map { FieldChoice(id: $0.id, name: $0.name, color: $0.color, descr: $0.descr) }
        }
        if field.id == section.project.priorityFieldId {
            return model.priorityOption(of: section.item).map { FieldChoice(id: $0.id, name: $0.name, color: $0.color, descr: $0.descr) }
        }
        return field.options.first { $0.id == value?.optionId }
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 7) {
                if let option = selectedOption {
                    if field.id == section.project.statusFieldId {
                        StatusIcon(glyph: model.glyph(of: section.item))
                    } else if field.id == section.project.priorityFieldId {
                        PriorityIcon(level: model.priorityLevel(of: section.item))
                    } else {
                        Circle().fill(Theme.optionColor(option.color) ?? Theme.textTertiary).frame(width: 9, height: 9)
                    }
                    Text(option.name)
                } else if let ids = value?.optionIds, !ids.isEmpty {
                    Text(field.options.filter { ids.contains($0.id) }.map(\.name).formatted(.list(type: .and)))
                } else if let iteration = field.iterations.first(where: { $0.id == value?.iterationId }) {
                    IterationIcon(size: 13)
                        .foregroundStyle(model.isRunning(iteration, field: field) ? Theme.started : Theme.textSecondary)
                    Text(iteration.title).lineLimit(1)
                    if let when = model.iterationPlace(iteration, field: field) ?? model.iterationRange(iteration) {
                        Text(when).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                } else if field.id == section.project.dueFieldId, let due = model.dueBadge(for: section.item) {
                    DueDateValue(due: due)
                } else if let day = value?.date.flatMap(CalendarDay.init) {
                    DueDateIcon(size: 12)
                    Text(day.mediumLabel())
                } else if let text = value?.text {
                    Text(verbatim: text)
                } else if let number = value?.number {
                    Text(number.formatted()).monospacedDigit()
                } else {
                    Text(.projectFieldEmpty).foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .hoverFill(active: open, radius: 8, fill: Theme.partHover)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .disabled(!section.project.viewerCanUpdate || !model.canEditValue(of: field, on: section.item))
        .accessibilityLabel(field.name)
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier("project-field-\(section.project.id)-\(field.id)")
        .dropdown(isPresented: $open) { close in
            switch field.kind {
            case .singleSelect, .multiSelect, .iteration:
                ProjectFieldChoicePicker(target: ProjectFieldTarget(item: section.item, fieldId: field.id), close: close)
            case .date:
                DueDatePicker(current: [value?.date], addsField: false, fieldName: field.name, onPick: { day in
                    save(day.map { FieldValue(date: $0.string) })
                }, onClose: close)
            case .text, .number:
                ProjectFieldTextEditor(field: field, value: value, onSave: save, close: close)
            default:
                EmptyView()
            }
        }
    }

    private var spokenValue: String {
        if field.id == section.project.statusFieldId || field.id == section.project.priorityFieldId {
            return selectedOption?.name ?? String(localized: .projectFieldEmpty)
        }
        return ProjectFieldEditing.label(field: field, value: value)
    }

    private func save(_ value: FieldValue?) {
        model.saveProjectField(ProjectFieldTarget(item: section.item, fieldId: field.id), value: value)
    }
}

/// A dropdown has a root of its own. Read the observed model here so checks follow picks that keep it open.
private struct ProjectFieldChoicePicker: View {
    @Environment(AppModel.self) private var model
    var target: ProjectFieldTarget
    var close: () -> Void

    var body: some View {
        if let item = model.item(targetedBy: target), let field = model.field(id: target.fieldId), let project = model.project(of: item) {
            let value = IssueProjectSection(project: project, item: item, fields: []).value(of: field)
            PickerList(placeholder: field.name, items: model.projectFieldChoices(field: field, value: value), multiple: field.kind == .multiSelect,
                       creating: field.id == project.statusFieldId ? { model.newProjectStatusRow($0, target: target) } : nil,
                       onPick: { id in
                model.pickProjectField(id, target: target)
            }, onClose: close)
            .disabled(!project.viewerCanUpdate)
            .onAppear {
                if field.id == project.statusFieldId { model.refreshStatuses(projectId: project.id) }
            }
        }
    }
}

private struct ProjectDueDateProperty: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var canEdit: Bool
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            (item.due.map { Text($0.mediumLabel()) } ?? Text(.addDueDate))
                .foregroundStyle(item.dueDate == nil ? Theme.textTertiary : Theme.text)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open, radius: 8, fill: Theme.partHover)
        }
        .buttonStyle(PlainPressStyle())
        .disabled(!canEdit)
        .dropdown(isPresented: $open) { close in
            ProjectDueDatePicker(target: ProjectFieldTarget(item: item, fieldId: "@due"), close: close)
        }
    }
}

private struct ProjectDueDatePicker: View {
    @Environment(AppModel.self) private var model
    var target: ProjectFieldTarget
    var close: () -> Void

    var body: some View {
        if let item = model.item(targetedBy: target), let project = model.project(of: item),
           !project.closed, project.viewerCanUpdate {
            DueDatePicker(current: [item.dueDate], addsField: project.dueFieldId == nil, onPick: { day in
                model.saveProjectDueDate(target, to: day)
            }, onClose: close)
        } else {
            Color.clear.task { close() }
        }
    }
}

private struct ProjectFieldTextEditor: View {
    var field: ProjectField
    var value: FieldValue?
    var onSave: (FieldValue?) -> Void
    var close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isNumber: Bool { field.kind == .number }
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var invalid: Bool { isNumber && !isEmpty && ProjectFieldInput.number(text) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: field.name).font(.smallMedium)
            TextField(field.name, text: $text, axis: isNumber ? .horizontal : .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(save)
                .onKeyPress(.escape) { close(); return .handled }
            if invalid {
                Text(.projectFieldInvalidNumber).font(.small).foregroundStyle(Theme.warning)
            }
            HStack {
                Button(.projectFieldClear) { onSave(nil); close() }
                    .disabled(value == nil)
                Spacer()
                Button(.cancel, action: close)
                Button(.saveButton, action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(invalid)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            text = value?.text ?? value?.number.map { $0.formatted(.number.grouping(.never).precision(.significantDigits(1...17))) } ?? ""
            focused = true
        }
    }

    private func save() {
        guard !invalid else { return }
        if isEmpty {
            onSave(nil)
        } else if isNumber, let number = ProjectFieldInput.number(text) {
            onSave(FieldValue(number: number))
        } else {
            onSave(FieldValue(text: text))
        }
        close()
    }
}
#endif
