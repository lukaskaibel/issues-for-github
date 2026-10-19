#if os(macOS)
import SwiftUI

/// Under My Issues' header: its filter as chips, as a view's, and a button that takes it all away. The filter is
/// yours alone and applies at once, so there is nothing to save. Without a filter the bar isn't there.
struct MyIssuesFilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let filter = model.mineFilter
        if !filter.isEmpty {
            HStack(spacing: 6) {
                FilterChipsRow(filter: Binding(get: { model.mineFilter }, set: { model.setMineFilter($0) }), scope: .myIssues)
                Spacer(minLength: 8)
                if filter.terms.count > 1 {
                    Button(.clearFilter) { model.setMineFilter(ProjectFilter("")) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(height: 40)
            .transition(.opacity)
        }
    }
}

/// How My Issues shows: what it groups by and what it is ordered by. It has no view on GitHub, so the choice stays
/// on this Mac; Reset goes back to groups by status, most urgent first.
struct MyIssuesDisplayOptions: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void

    var body: some View {
        let display = model.mineDisplay
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(.groupBy).foregroundStyle(Theme.textSecondary)
                    SelectDropdown(
                        options: MineGrouping.allCases.map { .init(id: $0.rawValue, title: $0.title) },
                        selected: display.grouping.rawValue, marked: display.grouping != MineDisplay().grouping
                    ) { id in
                        model.setMineDisplay { $0.grouping = MineGrouping(rawValue: id) ?? .status }
                    }
                }
                GridRow {
                    Text(.orderBy).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        SelectDropdown(
                            options: MineOrder.allCases.map { .init(id: $0.rawValue, title: $0.title) },
                            selected: display.order.rawValue, marked: display.order != MineDisplay().order
                        ) { id in
                            model.setMineOrder(MineOrder(rawValue: id) ?? .priority)
                        }
                        if display.order != .manual {
                            Button {
                                model.setMineDisplay { $0.descending.toggle() }
                            } label: {
                                Image(systemName: display.descending ? "arrow.down" : "arrow.up")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 24, height: 24)
                                    .hoverFill()
                            }
                            .buttonStyle(PlainPressStyle())
                            .help(Text(display.descending ? .descending : .ascending))
                        }
                    }
                }
            }
            .font(.small)
            if !display.isDefault {
                Rectangle().fill(Theme.popoverBorder).frame(height: 1).padding(.horizontal, -14)
                HStack {
                    Spacer(minLength: 8)
                    Button(.reset) { model.resetMineDisplay() }
                        .buttonStyle(QuietButtonStyle())
                        .help(Text(.resetMyIssuesDisplayTooltip))
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(onMove: { _ in }, onActivate: {}, onBack: close))
    }
}
#endif
