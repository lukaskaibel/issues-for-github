#if os(iOS)
import SwiftUI

/// A searchable list to pick a property from, as a sheet, with the same choices in the same order as the Mac's
/// dropdowns. A tap picks and closes it. People and labels take several: the circle at the start of a row picks
/// without closing, for the next one.
struct PickerSheet: View {
    var title: LocalizedStringResource
    var prompt: LocalizedStringResource
    var multiple: Bool
    /// Opened with a key on an iPad keyboard: typing goes straight to the search, and Return picks the first match.
    var focusesSearch = false
    var items: () -> [PickerItem]
    /// A row that makes what is typed, such as a label the repository doesn't have yet.
    var creating: ((String) -> PickerItem?)? = nil
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked = 0
    @State private var searching = false
    /// Where each row was at the first pick that kept the sheet open, and whether it was a recent one, so rows stay
    /// put while more are picked.
    @State private var held: [String: (place: Int, recent: Bool)]?

    var body: some View {
        NavigationStack {
            let visible = matching(query, in: rows, creating: query.isEmpty ? nil : creating?(query))
            // Recent choices in a group of their own above the rest, unless they are all there is.
            let recentEnd = query.isEmpty ? visible.lastIndex(where: \.recent).flatMap { $0 < visible.count - 1 ? $0 + 1 : nil } : nil
            List {
                if let recentEnd {
                    Section {
                        ForEach(visible[..<recentEnd]) { row($0) }
                    }
                    Section {
                        ForEach(visible[recentEnd...]) { row($0) }
                    }
                } else {
                    ForEach(visible) { row($0) }
                }
                if visible.isEmpty {
                    if query.isEmpty {
                        Text(.nothingToChooseFrom)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
            .onSubmit(of: .search) {
                if let first = visible.first { pick(first, keepOpen: false) }
            }
            .onAppear { if focusesSearch { searching = true } }
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var rows: [PickerItem] {
        let items = items()
        guard let held else { return items }
        return items.enumerated()
            .sorted { a, b in (held[a.element.id]?.place ?? .max, a.offset) < (held[b.element.id]?.place ?? .max, b.offset) }
            .map { _, item in
                var item = item
                item.recent = held[item.id]?.recent ?? false
                return item
            }
    }

    private func row(_ item: PickerItem) -> some View {
        HStack(spacing: 12) {
            if multiple, !item.creates {
                Button {
                    pick(item, keepOpen: true)
                } label: {
                    Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.selected ? Theme.accent : Theme.textTertiary)
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.selected ? .removeKeepChoosing(name: item.title) : .addKeepChoosing(name: item.title))
                .accessibilityIdentifier("check-\(item.title)")
            }
            Button {
                pick(item, keepOpen: false)
            } label: {
                HStack(spacing: 12) {
                    item.icon
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let prefix = item.prefix {
                                Text(prefix).font(.footnote).monospacedDigit().foregroundStyle(Theme.textTertiary)
                            }
                            Text(item.title).foregroundStyle(Theme.text).lineLimit(2)
                        }
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let trailing = item.trailing { trailing }
                    if item.selected, !multiple {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(item.selected ? .isSelected : [])
        }
    }

    private func pick(_ item: PickerItem, keepOpen: Bool) {
        if keepOpen, held == nil {
            held = Dictionary(rows.enumerated().map { ($1.id, (place: $0, recent: $1.recent)) }) { first, _ in first }
        }
        picked += 1
        onPick(item.id)
        if !keepOpen { dismiss() }
    }
}

extension PickerKind {
    var sheetTitle: LocalizedStringResource {
        switch self {
        case .status: .status
        case .priority: .priority
        case .assignees: .assignee
        case .labels: .labels
        case .dueDate: .dueDateTitle
        case .subIssues: .subIssues
        case .parent: .parentIssueSheetTitle
        case .addSubIssue: .addSubIssue
        case .blockedBy: .blockedBySheetTitle
        case .blocking: .blockingSheetTitle
        case .milestone: .milestone
        case .epic: .epic
        }
    }

    var searchPrompt: LocalizedStringResource {
        switch self {
        case .status: .searchStatuses
        case .priority: .searchPriorities
        case .assignees: .searchPeople
        case .labels: .searchLabels
        case .dueDate: .typeADate
        case .subIssues: .searchSubIssues
        case .parent, .addSubIssue, .blockedBy, .blocking, .epic: .searchByTitleOrNumber
        case .milestone: .searchMilestones
        }
    }
}

/// The picker for one property of an existing issue.
struct IssuePickerSheet: View {
    @Environment(AppModel.self) private var model
    var kind: PickerKind
    var itemId: String
    var focusesSearch = false

    var body: some View {
        if kind == .dueDate {
            IssueDueDateSheet(itemId: itemId)
        } else {
            list
        }
    }

    private var list: some View {
        PickerSheet(
            title: kind.sheetTitle,
            prompt: kind.searchPrompt,
            multiple: kind.multiple,
            focusesSearch: focusesSearch,
            items: {
                guard let item = model.item(id: itemId) else { return [] }
                return model.pickerItems(kind, for: item)
            },
            creating: kind == .labels ? { query in
                model.item(id: itemId).flatMap { model.newLabelRow(query, projectId: $0.projectId, repoId: $0.repoId) }
            } : nil,
            onPick: { id in
                guard let item = model.item(id: itemId) else { return }
                model.pick(kind, id: id, for: item)
            }
        )
        .task {
            if let item = model.item(id: itemId) {
                model.loadRepoMeta(for: item)
                if kind.picksIssues { model.loadRelations(for: item) }
            }
        }
    }
}
#endif
