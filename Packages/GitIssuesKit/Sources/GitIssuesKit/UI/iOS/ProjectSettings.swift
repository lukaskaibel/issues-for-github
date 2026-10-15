#if os(iOS)
import SwiftUI

/// The project's statuses, which are the columns of its board: add, rename, recolour, reorder and remove
/// them. They are the Status field on GitHub, so changes are saved there right away.
struct StatusEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var projectId: String

    @State private var renaming: FieldOption?
    @State private var name = ""
    @State private var adding = false
    @State private var deleting: FieldOption?

    var body: some View {
        let statuses = model.statusOptions(projectId: projectId)
        List {
            Section {
                ForEach(statuses) { option in
                    HStack(spacing: 12) {
                        StatusIcon(glyph: model.glyph(projectId: projectId, optionId: option.id), size: 17)
                        Button {
                            name = option.name
                            renaming = option
                        } label: {
                            Text(option.name).foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(.renamesTheStatus)
                        Text("\(count(option))")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityLabel(.issuesCount(count: count(option)))
                        Menu {
                            Picker(.colour, selection: Binding(
                                get: { option.color },
                                set: { color in edit(option) { $0.color = color } }
                            )) {
                                ForEach(Defaults.optionColors, id: \.self) { color in
                                    Label {
                                        Text(Defaults.colourName(color))
                                    } icon: {
                                        MenuImages.label(Self.hex(color), scheme)
                                    }
                                    .tag(color)
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Circle()
                                .fill(Theme.optionColor(option.color) ?? Theme.textTertiary)
                                .frame(width: 14, height: 14)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(.colourIs(colour: Defaults.colourName(option.color)))
                    }
                    .deleteDisabled(statuses.count <= 1)
                }
                .onMove { from, to in move(from: from, to: to) }
                .onDelete { offsets in
                    if let index = offsets.first { deleting = statuses[index] }
                }
            } footer: {
                Text(.statusEditorFooter)
            }
            Section {
                Button {
                    name = ""
                    adding = true
                } label: {
                    Label(.addStatus, systemImage: "plus")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(.statuses)
        .navigationBarTitleDisplayMode(.inline)
        .alert(.renameStatus, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(.statusNamePlaceholder, text: $name)
            Button(.cancel, role: .cancel) {}
            Button(.rename) {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if let option = renaming, !trimmed.isEmpty, trimmed != option.name { edit(option) { $0.name = trimmed } }
            }
        }
        .alert(.newStatus, isPresented: $adding) {
            TextField(.statusNamePlaceholder, text: $name)
            Button(.cancel, role: .cancel) {}
            Button(.add) { add() }
        } message: {
            Text(.newStatusMessage)
        }
        .confirmationDialog(
            deleting.map { String(localized: .deleteStatusQuestion(name: $0.name)) } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { option in
            Button(.deleteStatus, role: .destructive) { delete(option) }
        } message: { option in
            let count = count(option)
            Text(count == 0 ? .statusRemovedFromProject : .statusRemovedIssuesStay(count: count))
        }
    }

    private func count(_ option: FieldOption) -> Int {
        model.allItems.filter { $0.projectId == projectId && $0.statusId == option.id }.count
    }

    private var remote: [RemoteOption] {
        model.statusOptions(projectId: projectId).map(\.remote)
    }

    private func edit(_ option: FieldOption, _ change: (inout RemoteOption) -> Void) {
        var options = remote
        guard let index = model.statusOptions(projectId: projectId).firstIndex(where: { $0.id == option.id }) else { return }
        change(&options[index])
        model.saveColumns(projectId: projectId, options)
    }

    private func move(from: IndexSet, to: Int) {
        var options = remote
        options.move(fromOffsets: from, toOffset: to)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation(Theme.spring) {
            model.saveColumns(projectId: projectId, remote + [RemoteOption(id: nil, name: trimmed, color: "GRAY")])
        }
    }

    private func delete(_ option: FieldOption) {
        let options = remote.filter { $0.id != option.id }
        guard !options.isEmpty else { return }
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }

    /// The name of one of GitHub's option colours ("BLUE"), as the user reads it.

    /// GitHub's option colours as hex, for the colour menu's dots.
    static func hex(_ color: String) -> String {
        switch color {
        case "BLUE": "2F86B5"
        case "GREEN": "2F9B67"
        case "YELLOW": "D29A0A"
        case "ORANGE": "E07B2A"
        case "RED": "D64545"
        case "PINK": "C45FA6"
        case "PURPLE": "5B63D3"
        default: "8B949E"
        }
    }
}

/// The order of a list's sections, as a list to rearrange. A preference of this device only.
struct ArrangeSectionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var scope: Scope

    var body: some View {
        let sections = model.sections(for: scope)
        NavigationStack {
            List {
                Section {
                    ForEach(sections) { section in
                        HStack(spacing: 12) {
                            StatusIcon(glyph: section.glyph, size: 16)
                            Text(section.title)
                            Spacer()
                            Text("\(section.count)")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .onMove { from, to in
                        var ids = sections.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        withAnimation(Theme.spring) { model.setListOrder(ids, in: scope) }
                    }
                } footer: {
                    Text(.sectionOrderFooter)
                }
                if !model.customListOrder(for: scope).isEmpty {
                    Section {
                        Button(.backToUsualOrder) {
                            withAnimation(Theme.spring) { model.resetListOrder(in: scope) }
                        }
                    } footer: {
                        Text(.usualOrderExplanation)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(.arrangeSections)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A project's icon, as Reminders picks a list's: the icon large over the project's name, GitHub's colours, then the
/// glyphs in their groups, with a search field that finds them by name. A colour keeps the sheet open so a glyph can
/// follow; a glyph closes it.
struct ProjectIconSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var projectId: String

    @State private var query = ""
    @State private var searching = false

    /// As many columns as GitHub has colours, so the colours sit over the glyphs' columns.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: Defaults.optionColors.count)

    var body: some View {
        let look = model.projectLooks.look(projectId)
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let found = hasQuery ? ProjectGlyph.matching(query) : []
        NavigationStack {
            List {
                if hasQuery {
                    if !found.isEmpty {
                        Section { grid(found, look: look) }
                    }
                } else {
                    Section {
                        VStack(spacing: 10) {
                            ProjectGlyphImage(look: look, size: 40)
                                .frame(width: 80, height: 80)
                                .background(Circle().fill(Theme.projectColor(look.color).opacity(0.14)))
                            if let project = model.projects.first(where: { $0.id == projectId }) {
                                Text(project.title)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Theme.text)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                    Section {
                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(Defaults.optionColors, id: \.self) { color in
                                colorButton(color, look: look)
                            }
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text(.projectIconNote)
                    }
                    ForEach(ProjectGlyphGroup.allCases, id: \.self) { group in
                        Section {
                            grid(group.glyphs, look: look)
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(16)
            .overlay {
                if hasQuery, found.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(.searchIcons))
            .onSubmit(of: .search) {
                if let first = found.first { pick(first, look: look) }
            }
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle(.projectIcon)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") {
                        searching = false
                        dismiss()
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: look)
    }

    private func grid(_ glyphs: [ProjectGlyph], look: ProjectLook) -> some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(glyphs) { glyph in
                glyphButton(glyph, look: look)
            }
        }
        .padding(.vertical, 4)
    }

    private func colorButton(_ color: String, look: ProjectLook) -> some View {
        let selected = look.color == color
        return Button {
            model.projectLooks.set(ProjectLook(glyph: look.glyph, color: color), for: projectId)
        } label: {
            Circle()
                .fill(Theme.projectColor(color))
                .frame(width: 26, height: 26)
                .overlay {
                    if selected {
                        Circle().stroke(Theme.projectColor(color), lineWidth: 2).frame(width: 34, height: 34)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Defaults.colourName(color))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A glyph closes the sheet, from the search too, which is let go of first.
    private func pick(_ glyph: ProjectGlyph, look: ProjectLook) {
        model.projectLooks.set(ProjectLook(glyph: glyph, color: look.color), for: projectId)
        searching = false
        dismiss()
    }

    private func glyphButton(_ glyph: ProjectGlyph, look: ProjectLook) -> some View {
        let selected = look.glyph == glyph
        return Button {
            pick(glyph, look: look)
        } label: {
            // Every glyph in the colour picked, so the choice shows before it is made.
            ProjectGlyphImage(look: ProjectLook(glyph: glyph, color: look.color), size: 22)
                .frame(width: 38, height: 38)
                .background(Circle().fill(selected ? Theme.projectColor(look.color).opacity(0.16) : .clear))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(glyph.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Changes made elsewhere and changes that couldn't be saved, as banners at the top of the window. They hang
/// just below the navigation bar, so its buttons stay within reach while one shows.
struct NoticeBanners: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.status.notices) { notice in
                NoticeBanner(notice: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 56)
        .frame(maxWidth: 560)
        .animation(Theme.overlay, value: model.status.notices)
    }
}

private struct NoticeBanner: View {
    @Environment(AppModel.self) private var model
    var notice: Notice
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : notice.action?.isUndo == true ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(notice.isWarning ? Theme.warning : Theme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title).font(.subheadline.weight(.semibold))
                    Text(notice.message)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if notice.action?.isUndo == true {
                    Button(.undo) {
                        if let action = notice.action { model.apply(action) }
                        model.status.dismiss(notice.id)
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote.weight(.medium))
                    .accessibilityIdentifier("notice-undo")
                } else if let label = notice.action?.adoptLabel {
                    HStack(spacing: 8) {
                        Button(.keepMine) { model.status.dismiss(notice.id) }
                            .buttonStyle(.bordered)
                        Button(label) {
                            if let action = notice.action { model.apply(action) }
                            model.status.dismiss(notice.id)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.footnote.weight(.medium))
                }
            }
            Spacer(minLength: 0)
            Button {
                model.status.dismiss(notice.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(.dismiss)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            // A notice that only tells something goes away when tapped; one that asks waits for an answer.
            if notice.action == nil || notice.action?.isUndo == true { model.status.dismiss(notice.id) }
        }
        .offset(y: min(offset, 0))
        .gesture(
            DragGesture()
                .onChanged { offset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height < -30 {
                        model.status.dismiss(notice.id)
                    } else {
                        withAnimation(Theme.spring) { offset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .task {
            // Notices that ask for a decision stay until answered; one that can be undone stays a little longer.
            guard notice.action == nil || notice.action?.isUndo == true else { return }
            try? await Task.sleep(for: .seconds(notice.isWarning || notice.action?.isUndo == true ? 10 : 3))
            model.status.dismiss(notice.id)
        }
    }
}
#endif
