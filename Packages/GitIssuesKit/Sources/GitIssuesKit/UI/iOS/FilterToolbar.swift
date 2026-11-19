#if os(iOS)
import SwiftUI

/// The filter in the bar of a page of issues: Mail's filter symbol, filled in the accent colour while anything narrows
/// the page, as on the Mac. Its menu: Only My Issues (not in My Issues, where everything is yours), the filter of the
/// view or of My Issues, and how the page shows.
struct FilterToolbarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var scope: Scope

    var body: some View {
        let narrowed = model.isNarrowed(scope)
        Menu {
            if scope != .myIssues, model.viewer != nil {
                Toggle(isOn: Binding(
                    get: { model.onlyMine },
                    set: { on in withAnimation(Theme.spring) { model.onlyMine = on } }
                )) {
                    Label(.onlyMyIssues, systemImage: "person.crop.circle")
                }
            }
            if case .project(let projectId) = scope, let view = model.currentView(projectId: projectId) {
                Section {
                    Button {
                        navigation.sheet = .viewFilter(view.id)
                    } label: {
                        Label(.filterEllipsis, systemImage: "line.3.horizontal.decrease")
                    }
                    ViewDisplayMenu(view: view)
                }
            } else if scope == .myIssues {
                Section {
                    MyIssuesDisplayMenu()
                }
            }
        } label: {
            Label(.filter, systemImage: narrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .tint(narrowed ? Theme.accent : nil)
        .accessibilityAddTraits(narrowed ? .isSelected : [])
        .accessibilityIdentifier("filter-menu")
    }
}

/// A page "Only My Issues" leaves empty though it has issues: it says so, rather than that it has none.
struct OnlyMineEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MobileEmptyState(
            title: String(localized: .nothingOfYoursTitle), message: String(localized: .nothingOfYoursMessage),
            systemImage: "person.crop.circle"
        ) {
            Button(.showEveryonesIssues) {
                withAnimation(Theme.spring) { model.onlyMine = false }
            }
            .buttonStyle(.bordered)
        }
    }
}
#endif
