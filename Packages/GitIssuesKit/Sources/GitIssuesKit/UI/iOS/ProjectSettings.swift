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
                        .accessibilityHint("Renames the status")
                        Text("\(count(option))")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityLabel("\(count(option)) issues")
                        Menu {
                            Picker("Colour", selection: Binding(
                                get: { option.color },
                                set: { color in edit(option) { $0.color = color } }
                            )) {
                                ForEach(Defaults.optionColors, id: \.self) { color in
                                    Label {
                                        Text(color.capitalized)
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
                        .accessibilityLabel("Colour: \(option.color.capitalized)")
                    }
                    .deleteDisabled(statuses.count <= 1)
                }
                .onMove { from, to in move(from: from, to: to) }
                .onDelete { offsets in
                    if let index = offsets.first { deleting = statuses[index] }
                }
            } footer: {
                Text("These are the project's Status field on GitHub and the columns of its board. Changes are saved on GitHub right away, so they need a connection.")
            }
            Section {
                Button {
                    name = ""
                    adding = true
                } label: {
                    Label("Add Status", systemImage: "plus")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Statuses")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Status", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if let option = renaming, !trimmed.isEmpty, trimmed != option.name { edit(option) { $0.name = trimmed } }
            }
        }
        .alert("New Status", isPresented: $adding) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Add") { add() }
        } message: {
            Text("A new column at the end of the board.")
        }
        .confirmationDialog(
            deleting.map { "Delete the \"\($0.name)\" status?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { option in
            Button("Delete Status", role: .destructive) { delete(option) }
        } message: { option in
            let count = count(option)
            Text(count == 0
                 ? "The status is removed from the project on GitHub."
                 : "The status is removed from the project on GitHub. Its \(count) issue\(count == 1 ? "" : "s") stay in the project without a status.")
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
                            Text("\(section.items.count)")
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
                    Text("This order is kept on this device only and doesn't change the project on GitHub.")
                }
                if !model.customListOrder(for: scope).isEmpty {
                    Section {
                        Button("Back to the Usual Order") {
                            withAnimation(Theme.spring) { model.resetListOrder(in: scope) }
                        }
                    } footer: {
                        Text("Work in progress first, then what's next, the backlog and what's done.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
            Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
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
                if let label = notice.action?.adoptLabel {
                    HStack(spacing: 8) {
                        Button("Keep Mine") { model.status.dismiss(notice.id) }
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
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            // A notice that only tells something goes away when tapped; one that asks waits for an answer.
            if notice.action == nil { model.status.dismiss(notice.id) }
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
            // Notices that ask for a decision stay until answered.
            guard notice.action == nil else { return }
            try? await Task.sleep(for: .seconds(notice.isWarning ? 10 : 3))
            model.status.dismiss(notice.id)
        }
    }
}
#endif
