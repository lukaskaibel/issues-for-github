#if os(iOS)
import SwiftUI

/// A searchable list to pick a property from, as a sheet, with the same choices in the same order as the Mac's
/// dropdowns. A tap picks and closes it. People and labels take several: the circle at the start of a row picks
/// without closing, for the next one.
struct PickerSheet: View {
    var title: String
    var prompt: String
    var multiple: Bool
    /// Opened with a key on an iPad keyboard: typing goes straight to the search, and Return picks the first match.
    var focusesSearch = false
    var items: () -> [PickerItem]
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked = 0
    @State private var searching = false

    var body: some View {
        NavigationStack {
            let visible = filtered(items())
            List {
                ForEach(visible) { item in
                    HStack(spacing: 12) {
                        if multiple {
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
                            .accessibilityLabel(item.selected ? "Remove \(item.title), keep choosing" : "Add \(item.title), keep choosing")
                            .accessibilityIdentifier("check-\(item.title)")
                        }
                        Button {
                            pick(item, keepOpen: false)
                        } label: {
                            HStack(spacing: 12) {
                                item.icon
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).foregroundStyle(Theme.text)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer(minLength: 8)
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
                if visible.isEmpty {
                    if query.isEmpty {
                        Text("Nothing to choose from yet.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
            .onSubmit(of: .search) {
                if let first = visible.first { pick(first, keepOpen: false) }
            }
            .onAppear { if focusesSearch { searching = true } }
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pick(_ item: PickerItem, keepOpen: Bool) {
        picked += 1
        onPick(item.id)
        if !keepOpen { dismiss() }
    }

    private func filtered(_ items: [PickerItem]) -> [PickerItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (PickerItem, Int)? in
                let score = max(fuzzyScore(query, item.title) ?? -1, item.subtitle.flatMap { fuzzyScore(query, $0) } ?? -1)
                return score >= 0 ? (item, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

extension PickerKind {
    var sheetTitle: String {
        switch self {
        case .status: "Status"
        case .priority: "Priority"
        case .assignees: "Assignee"
        case .labels: "Labels"
        case .subIssues: "Sub-issues"
        }
    }

    var searchPrompt: String {
        switch self {
        case .status: "Search statuses"
        case .priority: "Search priorities"
        case .assignees: "Search people"
        case .labels: "Search labels"
        case .subIssues: "Search sub-issues"
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
        PickerSheet(
            title: kind.sheetTitle,
            prompt: kind.searchPrompt,
            multiple: kind.multiple,
            focusesSearch: focusesSearch,
            items: {
                guard let item = model.item(id: itemId) else { return [] }
                return model.pickerItems(kind, for: item)
            },
            onPick: { id in
                guard let item = model.item(id: itemId) else { return }
                model.pick(kind, id: id, for: item)
            }
        )
        .task {
            if let item = model.item(id: itemId) { model.loadRepoMeta(for: item) }
        }
    }
}
#endif
