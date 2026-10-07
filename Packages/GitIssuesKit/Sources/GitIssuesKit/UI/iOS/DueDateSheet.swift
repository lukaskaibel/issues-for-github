#if os(iOS)
import SwiftUI

/// Picks the day an issue is due: quick choices, a date typed into the search field ("fri", "12.10."), or a day
/// in the calendar. A pick closes the sheet.
struct DueDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The dates of the issues it is for; one value when they share it.
    var current: Set<String?>
    /// Whether the first date adds a "Due date" field to the project, which the sheet says once.
    var addsField: Bool
    var onPick: (CalendarDay?) -> Void

    @State private var query = ""
    @State private var day: Date
    @State private var picked = 0

    init(current: Set<String?>, addsField: Bool, onPick: @escaping (CalendarDay?) -> Void) {
        self.current = current
        self.addsField = addsField
        self.onPick = onPick
        // The calendar opens on the date the issue has; changing it is a pick, so this is set before it shows.
        let existing = current.count == 1 ? current.first.flatMap { $0 }.flatMap(CalendarDay.init) : nil
        _day = State(initialValue: (existing ?? .today()).date())
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        rows(model.dueDateItems(current: current).filter { !$0.id.isEmpty })
                    }
                    Section {
                        DatePicker("Due date", selection: $day, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .onChange(of: day) { _, new in pick(CalendarDay(new)) }
                    } footer: {
                        if addsField {
                            Text("The first due date adds a “Due date” field to the project on GitHub.")
                        }
                    }
                    if current.contains(where: { $0 != nil }) {
                        Section {
                            Button("Remove Due Date", role: .destructive) { pick(nil) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    let found = model.dueDateSearch(query, current: current)
                    rows(found)
                    if found.isEmpty {
                        ContentUnavailableView(
                            "No date matches “\(query)”",
                            systemImage: "calendar",
                            description: Text("Try “tomorrow”, “fri”, “next week”, “in 3 days” or “12.10.”.")
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Type a date, like “fri” or “12.10.”")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func rows(_ items: [PickerItem]) -> some View {
        ForEach(items) { item in
            Button {
                pick(CalendarDay(item.id))
            } label: {
                HStack(spacing: 12) {
                    item.icon.frame(width: 24, height: 24)
                    Text(item.title).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    if let trailing = item.trailing { trailing }
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
    }

    private func pick(_ day: CalendarDay?) {
        picked += 1
        onPick(day)
        dismiss()
    }
}

/// The due date sheet for issues that exist; with several picked, for all of them.
struct IssueDueDateSheet: View {
    @Environment(AppModel.self) private var model
    var itemId: String

    var body: some View {
        if let item = model.item(id: itemId) {
            DueDateSheet(
                current: Set(model.targets(for: item).map(\.dueDate)),
                addsField: model.addsDueField(for: item)
            ) { day in
                guard let current = model.item(id: itemId) else { return }
                model.setDueDate(of: model.targets(for: current), to: day)
            }
        }
    }
}

/// Due date as a submenu: the quick choices, any other day in the sheet, and removing it.
struct DueDateMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var item: Item

    var body: some View {
        let today = CalendarDay.today()
        Menu {
            ForEach(DueDateParser.quickPicks(today: today), id: \.day) { pick in
                Button {
                    model.setDueDate(of: [model.item(id: item.id) ?? item], to: pick.day)
                } label: {
                    Label {
                        Text(pick.title ?? pick.day.mediumLabel(today: today))
                        Text(pick.day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    } icon: {
                        Image(systemName: pick.day == today ? "sun.max" : pick.day.days(from: today) == 1 ? "sunrise" : "calendar")
                    }
                }
            }
            Divider()
            Button {
                navigation.sheet = .dueDate(item.id)
            } label: {
                Label("Choose a Date…", systemImage: "calendar.badge.plus")
            }
            if item.dueDate != nil {
                Button(role: .destructive) {
                    model.setDueDate(of: [model.item(id: item.id) ?? item], to: nil)
                } label: {
                    Label("Remove Due Date", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            Label {
                Text("Due Date")
                if let due = model.dueBadge(for: item) { Text(due.day.mediumLabel(today: today)) }
            } icon: {
                Image(systemName: "calendar")
            }
        }
    }
}
#endif
