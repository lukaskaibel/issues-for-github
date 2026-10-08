#if os(iOS)
import SwiftUI

/// The search tab, in the role of the Mac's command palette: issues in every project by title or number, and
/// projects by name. Without a query it shows the issues opened last.
struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @Environment(\.wideLayout) private var wide
    @FocusState private var focused: Bool
    /// The last request for the cursor (⌘K) that was answered.
    @State private var answeredFocusRequest = 0

    var body: some View {
        @Bindable var navigation = navigation
        let trimmed = navigation.searchQuery.trimmingCharacters(in: .whitespaces)
        List {
            if trimmed.isEmpty {
                let recent = RecentIssues.ids.compactMap { model.item(id: $0) }
                if !recent.isEmpty {
                    Section {
                        ForEach(recent) { item in issueRow(item, highlight: nil) }
                    } header: {
                        header(.recentIssues)
                    }
                }
                if !model.openProjects.isEmpty {
                    Section {
                        ForEach(model.openProjects) { project in projectRow(project) }
                    } header: {
                        header(.projects)
                    }
                }
            } else {
                let issues = issueResults(trimmed)
                let projects = model.openProjects.filter { fuzzyScore(trimmed, $0.title) != nil }
                if !issues.isEmpty {
                    Section {
                        ForEach(issues) { item in issueRow(item, highlight: trimmed) }
                    } header: {
                        header(.issues, detail: String(localized: .resultCount(count: issues.count)))
                    }
                }
                if !projects.isEmpty {
                    Section {
                        ForEach(projects) { project in projectRow(project) }
                    } header: {
                        header(.projects)
                    }
                }
                if issues.isEmpty, projects.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .navigationTitle(.search)
        .searchable(text: $navigation.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(.searchPrompt))
        .searchFocused($focused)
        // Also when ⌘K opened this tab for the first time, so the field wasn't there yet when it was asked for.
        .task(id: navigation.searchFocusRequest) {
            guard navigation.searchFocusRequest != answeredFocusRequest else { return }
            answeredFocusRequest = navigation.searchFocusRequest
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Issues whose number starts with the digits typed, then fuzzy matches on the title, best first.
    private func issueResults(_ query: String) -> [Item] {
        let digits = query.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return model.allItems
            .compactMap { item -> (Item, Int)? in
                if let number = item.number, !digits.isEmpty, digits.allSatisfy(\.isNumber), String(number).hasPrefix(digits) {
                    return (item, 1000 - String(number).count)
                }
                return fuzzyScore(query, item.title).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(50)
            .map(\.0)
    }

    private func header(_ title: LocalizedStringResource, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Theme.textTertiary)
            }
        }
        .textCase(nil)
    }

    private func issueRow(_ item: Item, highlight: String?) -> some View {
        Button {
            openRoute(.issue(item.id))
        } label: {
            IssueRow(item: item, showsProject: true, highlight: highlight)
        }
        .buttonStyle(RowButtonStyle())
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.panel)
        .contextMenu {
            ItemMenuContent(item: item) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
    }

    /// A project: opened inside this tab on the iPhone, and in its own sidebar entry on a wide iPad.
    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        let label = HStack(spacing: 12) {
            ProjectSwatch(title: project.title, size: 16)
            Text(project.title).foregroundStyle(Theme.text)
            Spacer()
            Text(project.ownerLogin).font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
        if wide {
            Button {
                navigation.showProject(project.id, regular: true)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .listRowBackground(Theme.panel)
        } else {
            NavigationLink(value: Route.project(project.id)) { label }
                .listRowBackground(Theme.panel)
        }
    }
}
#endif
