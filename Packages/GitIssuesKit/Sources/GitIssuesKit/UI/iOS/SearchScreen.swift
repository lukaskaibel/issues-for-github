#if os(iOS)
import SwiftUI

/// Search on its own screen, in the role of the Mac's command palette: in the iPad's sidebar, and on the iPhone for ⌘K
/// from a keyboard. Issues in every project by title or number, and projects by name; without a query, the issues
/// opened last.
struct SearchScreen: View {
    @Environment(MobileNavigation.self) private var navigation
    @FocusState private var focused: Bool
    /// The last request for the cursor (⌘K) that was answered.
    @State private var answeredFocusRequest = 0

    var body: some View {
        @Bindable var navigation = navigation
        SearchResults(query: navigation.searchQuery)
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
    }
}

/// The iPhone's search at the foot of its screens, as in Notes and Notebook, beside New Issue in the accent's glass:
/// while the field is in use, what it finds covers the screen. Each screen keeps its own query.
struct PhoneSearchBar: ViewModifier {
    @Environment(\.wideLayout) private var wide
    /// Where New Issue starts a new issue from this screen.
    var context: NewIssueContext
    @State private var query = ""

    func body(content: Content) -> some View {
        if wide {
            content
        } else {
            SearchCover(query: query) { content }
                .searchable(text: $query, prompt: Text(.searchPrompt))
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        NewIssueButton(context: context, prominent: true)
                    }
                }
        }
    }
}

/// A screen under the iPhone's search field: what the field finds, over the screen, while it is in use.
private struct SearchCover<Content: View>: View {
    @Environment(\.isSearching) private var searching
    var query: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .overlay {
                if searching {
                    SearchResults(query: query)
                        .transition(.opacity)
                }
            }
            .animation(Theme.quick, value: searching)
    }
}

/// What a search finds: issues in every project by title or number, and projects by name. Without a query, the
/// issues opened last and the projects.
struct SearchResults: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @Environment(\.wideLayout) private var wide
    var query: String

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
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

    /// A project: opened on the iPhone's stack, and in its own sidebar entry on a wide iPad.
    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        let label = HStack(spacing: 12) {
            ProjectIcon(projectId: project.id, size: 16)
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
            Button {
                openRoute(.project(project.id))
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .listRowBackground(Theme.panel)
        }
    }
}
#endif
