#if os(iOS)
import SwiftUI

/// "Only My Issues" in the bar of a board's pages: the person, filled in the accent colour while boards and lists show
/// only yours. The iPad has it always; the iPhone, whose … menu turns it on (`OnlyMineMenuToggle`), while it is on, so
/// that it shows and goes off with one tap.
struct OnlyMineToolbarButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.wideLayout) private var wide

    var body: some View {
        if model.viewer != nil, wide || model.onlyMine {
            let on = model.onlyMine
            Button {
                withAnimation(Theme.spring) { model.onlyMine.toggle() }
            } label: {
                Label(.onlyMyIssues, systemImage: on ? "person.crop.circle.fill" : "person.crop.circle")
            }
            .tint(on ? Theme.accent : nil)
            .help(Text(on ? .showEveryonesIssuesTooltip : .showOnlyMyIssuesTooltip))
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("only-mine")
        }
    }
}

/// "Only My Issues" in the iPhone's … menu of a board's pages, ticked while it is on.
struct OnlyMineMenuToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.wideLayout) private var wide

    var body: some View {
        // The iPad has the button in its bar.
        if !wide, model.viewer != nil {
            Toggle(isOn: Binding(
                get: { model.onlyMine },
                set: { on in withAnimation(Theme.spring) { model.onlyMine = on } }
            )) {
                Label(.onlyMyIssues, systemImage: "person.crop.circle")
            }
        }
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
