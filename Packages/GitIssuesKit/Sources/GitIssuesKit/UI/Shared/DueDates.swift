import SwiftUI

/// How a due date reads: red once it has passed, orange on the day, quiet before, and grey once the issue is done.
enum DueTone: Equatable {
    case overdue
    case today
    case upcoming
    case settled

    var color: Color {
        switch self {
        case .overdue: Theme.overdue
        case .today: Theme.urgent
        case .upcoming: Theme.textSecondary
        case .settled: Theme.textTertiary
        }
    }
}

/// A due date as cards, rows and chips show it.
struct DueBadge: Equatable {
    var day: CalendarDay
    /// "Today", "Fri", "9 Oct".
    var label: String
    var tone: DueTone

    /// "Due Friday, 9 October", "Overdue since 3 October".
    var tooltip: String {
        switch tone {
        case .overdue: "Overdue since \(day.longLabel)"
        case .today: "Due today"
        case .upcoming, .settled: "Due \(day.longLabel)"
        }
    }
}

extension CalendarDay {
    /// For chips: "Today", "Tomorrow", "Yesterday", the weekday within the coming week ("Fri"), else the date
    /// ("9 Oct"), with the year when it isn't this one.
    func shortLabel(today: CalendarDay = .today()) -> String {
        let distance = days(from: today)
        switch distance {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return date().formatted(.dateTime.weekday(.abbreviated))
        default:
            return year == today.year
                ? date().formatted(.dateTime.day().month(.abbreviated))
                : date().formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    /// For the issue's properties: "Today", "Tomorrow", else "Fri, 9 Oct".
    func mediumLabel(today: CalendarDay = .today()) -> String {
        switch days(from: today) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default:
            year == today.year
                ? date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                : date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
    }

    /// "Friday, 9 October 2026", for tooltips and VoiceOver.
    var longLabel: String {
        date().formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

extension AppModel {
    func dueBadge(for item: Item, today: CalendarDay = .today()) -> DueBadge? {
        guard let day = item.due else { return nil }
        let tone: DueTone
        if isDone(item) {
            tone = .settled
        } else if day < today {
            tone = .overdue
        } else if day == today {
            tone = .today
        } else {
            tone = .upcoming
        }
        return DueBadge(day: day, label: day.shortLabel(today: today), tone: tone)
    }

    /// Sets the day each issue is due, or clears it. The project's "Due date" field is added on GitHub if it
    /// has none yet. An issue on no board has nowhere to keep a date, so it is left alone.
    func setDueDate(of items: [Item], to day: CalendarDay?) {
        let value = day?.string
        perform(items.filter { $0.dueDate != value }.compactMap { item in
            item.projectId.map { .setDate(.init(itemId: item.id, projectId: $0, date: value, base: item.dueDate)) }
        })
        if day != nil { notifier.requestPermissionIfNeeded() }
    }

    /// Whether an issue can have a due date: the date is a field of its board, so it needs one.
    func canHaveDueDate(_ item: Item) -> Bool {
        item.isOnBoard
    }

    /// Whether the board has no date field yet, so the first date adds one on GitHub.
    func addsDueField(for item: Item) -> Bool {
        project(of: item)?.dueFieldId == nil
    }

    // MARK: Picker rows

    /// The quick choices and, when there is a date, a way to remove it.
    func dueDateItems(for item: Item) -> [PickerItem] {
        dueDateItems(current: Set(targets(for: item).map(\.dueDate)))
    }

    /// The same for issues whose dates are `current` (one value when they share it), such as a new issue's.
    func dueDateItems(current: Set<String?>, today: CalendarDay = .today()) -> [PickerItem] {
        var rows = DueDateParser.quickPicks(today: today).map { suggestion in
            dueDateRow(suggestion, selected: current == [suggestion.day.string], today: today)
        }
        if current.contains(where: { $0 != nil }) {
            rows.append(PickerItem(
                id: "", title: "Remove due date",
                icon: AnyView(Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary))
            ))
        }
        return rows
    }

    /// What typed text could mean, as rows to pick from.
    func dueDateSearch(_ query: String, current: Set<String?>, today: CalendarDay = .today()) -> [PickerItem] {
        DueDateParser.suggestions(for: query, today: today).map { suggestion in
            dueDateRow(suggestion, selected: current == [suggestion.day.string], today: today)
        }
    }

    private func dueDateRow(_ suggestion: DueDateParser.Suggestion, selected: Bool, today: CalendarDay) -> PickerItem {
        let distance = suggestion.day.days(from: today)
        let symbol = switch distance {
        case 0: "sun.max"
        case 1: "sunrise"
        default: "calendar"
        }
        // A named day shows its date on the right; a date typed out shows its weekday.
        let title = suggestion.title ?? suggestion.day.date().formatted(.dateTime.day().month(.wide).year())
        let detail = suggestion.title == nil
            ? suggestion.day.date().formatted(.dateTime.weekday(.wide))
            : suggestion.day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        #if os(macOS)
        let iconFont = Font.system(size: 12, weight: .medium)
        #else
        let iconFont = Font.body
        #endif
        return PickerItem(
            id: suggestion.day.string, title: title, selected: selected,
            icon: AnyView(Image(systemName: symbol).font(iconFont).foregroundStyle(Theme.textSecondary)),
            trailing: AnyView(Text(detail).font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary))
        )
    }
}

/// The calendar glyph of due dates, coloured by how near the day is.
struct DueDateIcon: View {
    var tone: DueTone? = nil
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "calendar")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tone?.color ?? Theme.textTertiary)
    }
}
