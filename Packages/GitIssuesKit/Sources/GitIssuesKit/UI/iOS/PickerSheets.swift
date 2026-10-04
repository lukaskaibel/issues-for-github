#if os(iOS)
import SwiftUI

/// A searchable list to pick a property from, as a sheet: one value for status and priority, several for
/// people and labels. The same choices, in the same order, as the Mac's dropdowns.
struct PickerSheet: View {
    var title: String
    var prompt: String
    var multiple: Bool
    var items: () -> [PickerItem]
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked = 0

    var body: some View {
        NavigationStack {
            let visible = filtered(items())
            List {
                ForEach(visible) { item in
                    Button {
                        picked += 1
                        onPick(item.id)
                        if !multiple { dismiss() }
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
                            if item.selected {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(item.selected ? .isSelected : [])
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
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

    var body: some View {
        PickerSheet(
            title: kind.sheetTitle,
            prompt: kind.searchPrompt,
            multiple: kind.staysOpen,
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
            if let item = model.item(id: itemId) { model.loadRepoMeta(projectId: item.projectId) }
        }
    }
}
#endif
