#if os(macOS)
import SwiftUI

/// The toolbar's filter: Mail's filter symbol, filled in the accent colour while anything narrows the page on screen
/// (`pageIsNarrowed`), with a dot while the view's filter or display is changed here and not saved. Its panel holds
/// whose issues (Only My Issues), which (the view's filter, or My Issues') and how they show (display). F opens it
/// straight at what to filter by, as the filter button did; a click or ⇧V opens the whole panel.
struct FilterPanelButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false
    @State private var picking = false

    var body: some View {
        let narrowed = model.pageIsNarrowed
        Button {
            picking = false
            open = true
        } label: {
            Image(systemName: narrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(narrowed ? Theme.accent : Theme.textBody)
                .overlay(alignment: .topTrailing) {
                    if model.pageChangedForYou {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(x: 3, y: -2)
                    }
                }
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .help(Text(.filterAndDisplayTooltip))
        .accessibilityLabel(Text(.filter))
        .accessibilityAddTraits(narrowed ? .isSelected : [])
        .disabled(!model.hasFilterPanel)
        .dropdown(isPresented: $open, placement: .belowTrailing) { close in
            FilterPanel(picking: picking, close: close)
        }
        .onChange(of: model.filterMenuRequest) {
            picking = true
            open = true
        }
        .onChange(of: model.displayMenuRequest) {
            picking = false
            open = true
        }
    }
}

/// Whose, which, how: Only My Issues on top (not in My Issues, where everything is yours), the filter of the view or
/// of My Issues, and how they show. A view's changes are reset or saved for everyone together at the foot.
struct FilterPanel: View {
    @Environment(AppModel.self) private var model
    /// Straight at the list of what to filter by (F).
    var picking: Bool
    var close: () -> Void

    var body: some View {
        if picking, let filter, let scope = filterScope {
            FilterMenu(filter: filter, scope: scope, close: close)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if model.scope != .myIssues {
                    OnlyMineRow()
                }
                if let filter, let scope = filterScope {
                    if model.scope != .myIssues { PopoverDivider(outset: 14) }
                    VStack(alignment: .leading, spacing: 8) {
                        PanelHeading(title: .filter)
                        FilterChipsRow(filter: filter, scope: scope, wraps: true)
                        if scope == .myIssues, model.mineFilter.terms.count > 1 {
                            Button(.clearFilter) { model.setMineFilter(ProjectFilter("")) }
                                .buttonStyle(QuietButtonStyle())
                                .padding(.leading, -8)
                        }
                    }
                }
                if let view = model.currentView {
                    PopoverDivider(outset: 14)
                    PanelHeading(title: .display)
                    DisplayOptions(view: view)
                    ViewChangesFooter(view: view)
                } else if model.scope == .myIssues {
                    PopoverDivider(outset: 14)
                    PanelHeading(title: .display)
                    MyIssuesDisplayOptions()
                }
            }
            .padding(14)
            .frame(width: 340)
            .font(.ui)
            .foregroundStyle(Theme.text)
            .background(MenuKeys(onMove: { _ in }, onActivate: {}, onBack: close))
        }
    }

    /// The filter the page has: a view's, written here until saved, or My Issues', which applies at once.
    private var filter: Binding<ProjectFilter>? {
        if model.scope == .myIssues {
            return Binding(get: { model.mineFilter }, set: { model.setMineFilter($0) })
        }
        guard let view = model.currentView else { return nil }
        return Binding(get: { model.filter(of: view) }, set: { model.setFilter($0, of: view) })
    }

    private var filterScope: FilterScope? {
        model.scope == .myIssues ? .myIssues : model.currentView.map { .project($0.projectId) }
    }
}

/// A part's name in the panel, as its lists' names are written.
private struct PanelHeading: View {
    var title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(.smallMedium)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Only My Issues as a switch, saying that it holds on every board and not only in the view on screen.
struct OnlyMineRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 16))
                .foregroundStyle(model.onlyMine ? Theme.accent : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(.onlyMyIssues)
                Text(.onlyMyIssuesEverywhere)
                    .font(.tiny)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { model.onlyMine }, set: { model.onlyMine = $0 })) {
                Text(.onlyMyIssues)
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .disabled(model.viewer == nil)
        .accessibilityElement(children: .combine)
    }
}

/// What the view's filter and display have changed here: Reset takes both back, Save for Everyone puts on GitHub what
/// it takes. Columns, grouping and order stay yours, which a line under it says.
private struct ViewChangesFooter: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView

    var body: some View {
        let filterChanged = model.filterChanged(view)
        let displayChanged = model.displayDiffers(view)
        if filterChanged || displayChanged {
            PopoverDivider(outset: 14)
            HStack(spacing: 8) {
                Text(.changedForYou).font(.small).foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 8)
                Button(.reset) {
                    if filterChanged { model.resetFilter(of: view) }
                    if displayChanged { model.resetDisplay(of: view) }
                }
                .buttonStyle(QuietButtonStyle())
                if model.canEditViews(projectId: view.projectId), filterChanged || model.displayCanBeSaved(view) {
                    let saving = model.savingViewIds.contains(view.id)
                    Button {
                        model.saveChanges(of: view)
                    } label: {
                        HStack(spacing: 6) {
                            if saving { ProgressView().controlSize(.mini) }
                            Text(.saveForEveryone)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.canReachGitHub || saving)
                    .help(Text(model.canReachGitHub ? .saveForEveryoneTooltip : .needsConnection))
                }
            }
            if displayChanged, model.displayStaysYours(view) {
                Text(.displayStaysYoursHint)
                    .font(.tiny)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if filterChanged, !model.canEditViews(projectId: view.projectId) {
                Text(.filterOnlyForYou)
                    .font(.tiny)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// "Mine" first in the line of filter chips while Only My Issues narrows the page: a click on its cross shows
/// everyone's issues again, as the toolbar's person button did.
struct OnlyMineChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.onlyMine = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 11))
                Text(.mineChip).font(.smallMedium)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.menuHighlight))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainPressStyle())
        .help(Text(.showEveryonesIssuesTooltip))
        .accessibilityLabel(Text(.showEveryonesIssuesCommand))
        .fixedSize()
    }
}

/// Under the header of a page without a filter of its own (All Issues, a milestone, the roadmap): the Mine chip
/// while Only My Issues narrows it, so the page says why it shows only yours.
struct OnlyMineBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.narrowsToMine {
            HStack(spacing: 6) {
                OnlyMineChip()
                Spacer(minLength: 8)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(height: 40)
            .transition(.opacity)
        }
    }
}
#endif
