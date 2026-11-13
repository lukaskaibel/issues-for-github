#if os(iOS)
import SwiftUI
import UIKit.UIDevice

// Operate: extend the existing issue properties with one group per open project. Wide iPad windows keep
// the groups in the inspector; compact windows open this same content in a Projects sheet. Native sheets,
// system type, the existing theme and SF Symbols carry the interface. Every field, including empty values,
// is reachable by touch. Project sections animate together; saves stay asynchronous. The footer is a divider
// followed by + Add to project. Reuse data and choices across platforms; keep touch editors native.

struct IssueProjectsSheet: View {
    var reference: IssueReference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MobileIssueProjects(reference: reference)
                    .padding(20)
            }
            .accessibilityIdentifier("issue-projects-scroll")
            .background(Theme.panel)
            .navigationTitle(.issueProjectsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("issue-projects-done")
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct MobileIssueProjects: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var reference: IssueReference
    @State private var editor: ProjectFieldTarget?
    @State private var adding = false
    @State private var dueTarget: ProjectFieldTarget?
    @State private var collapsedProjects = Set<String>()

    var body: some View {
        if let item = model.item(referencedBy: reference) {
            let sections = IssueProjectSection.sections(for: item, items: model.allItems, projects: model.projects, fields: model.fields)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        header(section)
                        VStack(alignment: .leading, spacing: 0) {
                            if !collapsedProjects.contains(section.id) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(section.fields) { field in
                                        fieldRow(section, field: field, primary: item.projectId == section.project.id)
                                    }
                                    if !section.fields.contains(where: { $0.id == section.project.dueFieldId }) {
                                        Button { dueTarget = ProjectFieldTarget(item: section.item, fieldId: "@due") } label: {
                                            LabeledContent {
                                                (section.item.due.map { Text($0.mediumLabel()) } ?? Text(.addDueDate))
                                                    .foregroundStyle(section.item.dueDate == nil ? Theme.textTertiary : Theme.text)
                                            } label: { Text(.dueDate).foregroundStyle(Theme.textSecondary) }
                                            .frame(minHeight: 44)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!section.project.viewerCanUpdate)
                                        .accessibilityLabel(Text(.dueDate))
                                        .accessibilityValue(section.item.due?.mediumLabel() ?? String(localized: .addDueDate))
                                        .accessibilityIdentifier(item.projectId == section.project.id ? "property-due" : "project-due-\(section.project.id)")
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                    }
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("issue-project-\(section.project.id)")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                    Divider().padding(.bottom, 12)
                }
                if item.kind != .draft, item.contentId != nil {
                    Button { adding = true } label: {
                        Label(.addToProjectPlaceholder, systemImage: "plus")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("issue-projects")
                }
            }
            .font(.subheadline)
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .sheet(item: $editor) { target in MobileProjectFieldEditor(target: target) }
            .sheet(isPresented: $adding) { IssueMembershipSheet(reference: reference) }
            .sheet(item: $dueTarget) { target in ProjectDueDateSheet(target: target) }
        }
    }

    private func header(_ section: IssueProjectSection) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.spring) {
                    if !collapsedProjects.insert(section.id).inserted { collapsedProjects.remove(section.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    ProjectIcon(projectId: section.project.id)
                    Text(section.project.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.project.title)
            .accessibilityValue(Text(collapsedProjects.contains(section.id) ? .sectionFolded : .sectionOpen))
            .accessibilityIdentifier("toggle-project-\(section.project.id)")
            if section.item.kind != .draft, section.project.viewerCanUpdate {
                Button {
                    model.setMembership(of: section.item, in: section.project, isMember: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.projectMembershipChanges.isSaving(section.item, projectId: section.project.id, in: model.db, remaps: model.status.idRemaps))
                .accessibilityLabel(.removeIssueFromProject(project: section.project.title))
                .accessibilityIdentifier("remove-project-\(section.project.id)")
            }
        }
        .frame(minHeight: 44)
    }

    private func fieldRow(_ section: IssueProjectSection, field: ProjectField, primary: Bool) -> some View {
        let target = ProjectFieldTarget(item: section.item, fieldId: field.id)
        let isStatus = field.id == section.project.statusFieldId
        let text = isStatus ? model.statusText(of: section.item) : ProjectFieldEditing.label(field: field, value: section.value(of: field))
        return Button { editor = target } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    if model.projectEdits.isSaving(target, in: model.db, remaps: model.status.idRemaps) { ProgressView().controlSize(.small) }
                    if isStatus { StatusIcon(glyph: model.glyph(of: section.item), size: 15) }
                    Text(verbatim: text)
                        .foregroundStyle(section.value(of: field) == nil ? Theme.textTertiary : Theme.text)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                Text(verbatim: field.name).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!section.project.viewerCanUpdate || model.projectEdits.isSaving(target, in: model.db, remaps: model.status.idRemaps))
        .accessibilityLabel(field.name)
        .accessibilityValue(text)
        .accessibilityIdentifier(identifier(field, project: section.project, primary: primary))
    }

    private func identifier(_ field: ProjectField, project: Project, primary: Bool) -> String {
        if primary {
            if field.id == project.statusFieldId { return "property-status" }
            if field.id == project.priorityFieldId { return "property-priority" }
            if field.id == project.dueFieldId { return "property-due" }
            if field.kind == .iteration { return "property-iteration" }
        }
        return "project-field-\(project.id)-\(field.id)"
    }
}

private struct IssueMembershipSheet: View {
    @Environment(AppModel.self) private var model
    var reference: IssueReference

    var body: some View {
        PickerSheet(title: .issueProjectsTitle, prompt: .searchIssueProjects, multiple: true, items: {
            guard let item = model.item(referencedBy: reference) else { return [] }
            let memberships = Set(model.allItems.filter { $0.contentId == item.contentId }.compactMap(\.projectId))
            return model.openProjects.filter(\.viewerCanUpdate).map { project in
                PickerItem(id: project.id, title: project.title, subtitle: project.ownerLogin,
                           selected: memberships.contains(project.id), icon: AnyView(ProjectIcon(projectId: project.id)),
                           trailing: model.projectMembershipChanges.isSaving(item, projectId: project.id, in: model.db, remaps: model.status.idRemaps)
                               ? AnyView(ProgressView().controlSize(.small)) : nil)
            }
        }, onPick: { id in
            guard let item = model.item(referencedBy: reference),
                  let project = model.openProjects.first(where: { $0.id == id }) else { return }
            let member = model.allItems.contains { $0.contentId == item.contentId && $0.projectId == id }
            model.setMembership(of: item, in: project, isMember: !member)
        }, isEnabled: { row in
            guard let item = model.item(referencedBy: reference) else { return false }
            return !model.projectMembershipChanges.isSaving(item, projectId: row.id, in: model.db, remaps: model.status.idRemaps)
        }, detents: UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
    }
}

private struct ProjectDueDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ProjectFieldTarget

    var body: some View {
        if let item = model.item(targetedBy: target), let project = model.project(of: item),
           !project.closed, project.viewerCanUpdate {
            DueDateSheet(current: [item.dueDate], addsField: project.dueFieldId == nil) { day in
                model.saveProjectDueDate(target, to: day)
            }
        } else {
            Color.clear.task { dismiss() }
        }
    }
}

private struct MobileProjectFieldEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ProjectFieldTarget

    var body: some View {
        if let item = model.item(targetedBy: target), let field = model.field(id: target.fieldId),
           let project = model.project(of: item), field.projectId == project.id, project.viewerCanUpdate {
            let value = IssueProjectSection(project: project, item: item, fields: []).value(of: field)
            Group {
                switch field.kind {
                case .singleSelect, .multiSelect, .iteration:
                    PickerSheet(title: .projectFieldEmpty, prompt: .projectFieldEmpty, multiple: field.kind == .multiSelect, fieldName: field.name, items: {
                        model.projectFieldChoices(field: field, value: value)
                    }, creating: { query in
                        model.newProjectStatusRow(query, target: target)
                    }, onPick: { id in
                        model.pickProjectField(id, target: target)
                    }, isEnabled: { _ in !model.projectEdits.isSaving(target, in: model.db, remaps: model.status.idRemaps) })
                    .task {
                        if field.id == project.statusFieldId { model.refreshStatuses(projectId: project.id) }
                    }
                case .date:
                    DueDateSheet(current: [value?.date], addsField: false, fieldName: field.name) { day in
                        model.saveProjectField(target, value: day.map { FieldValue(date: $0.string) })
                    }
                case .text, .number:
                    ProjectValueSheet(target: target, field: field, value: value)
                default:
                    EmptyView()
                }
            }
        } else {
            Color.clear.task { dismiss() }
        }
    }
}

private struct ProjectValueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ProjectFieldTarget
    var field: ProjectField
    var value: FieldValue?
    @State private var text = ""
    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var invalid: Bool { field.kind == .number && !empty && ProjectFieldInput.number(text) == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(field.name, text: $text, axis: field.kind == .number ? .horizontal : .vertical)
                        .keyboardType(field.kind == .number ? .numbersAndPunctuation : .default)
                        .lineLimit(1...8)
                        .focused($focused)
                        .accessibilityIdentifier("project-field-input")
                } footer: {
                    if invalid { Text(.projectFieldInvalidNumber).foregroundStyle(Theme.warning) }
                }
                if value != nil {
                    Button(.projectFieldClear, role: .destructive) { save(nil) }
                        .accessibilityIdentifier("project-field-clear")
                }
            }
            .navigationTitle(Text(verbatim: field.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.saveButton) {
                        guard !invalid else { return }
                        if empty { save(nil) }
                        else if field.kind == .number { save(ProjectFieldInput.number(text).map { FieldValue(number: $0) }) }
                        else { save(FieldValue(text: text)) }
                    }
                    .disabled(invalid)
                    .accessibilityIdentifier("project-field-save")
                }
            }
        }
        .onAppear {
            text = value?.text ?? value?.number.map { $0.formatted(.number.grouping(.never).precision(.significantDigits(1...17))) } ?? ""
            focused = true
        }
    }

    private func save(_ value: FieldValue?) {
        model.saveProjectField(target, value: value)
        dismiss()
    }
}
#endif
