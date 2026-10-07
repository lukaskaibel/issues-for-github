#if os(macOS)
import SwiftUI

/// The due date dropdown: quick choices, a field that reads typed dates ("fri", "12.10.", "in 3 days"), and a
/// month to click a day in. A pick closes it.
struct DueDatePicker: View {
    @Environment(AppModel.self) private var model
    /// The dates of the issues it is for; one value when they share it.
    var current: Set<String?>
    /// Whether the first date adds a "Due date" field to the project, which the dropdown says once.
    var addsField: Bool
    var width: CGFloat = 280
    var fieldFont: Font = .ui
    var onPick: (CalendarDay?) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PickerList(
                placeholder: PickerKind.dueDate.placeholder,
                items: model.dueDateItems(current: current),
                hint: PickerKind.dueDate.hint,
                width: width,
                maxRows: 7,
                fieldFont: fieldFont,
                search: { model.dueDateSearch($0, current: current) },
                onPick: { onPick(CalendarDay($0)) },
                onClose: onClose
            )
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)
            MonthGrid(selected: current.count == 1 ? current.first?.flatMap(CalendarDay.init) : nil) { day in
                onPick(day)
                onClose()
            }
            .frame(width: min(width, 280))
            .padding(.vertical, 6)
            if addsField {
                Rectangle().fill(Theme.popoverBorder).frame(height: 1)
                Text("Adds a “Due date” field to the project on GitHub.")
                    .font(.tiny)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: width)
    }
}

/// One month of days to click, starting on the week's first day as the device has it.
struct MonthGrid: View {
    var selected: CalendarDay?
    var onPick: (CalendarDay) -> Void

    @State private var month: CalendarDay
    @State private var hovered: CalendarDay?

    init(selected: CalendarDay?, onPick: @escaping (CalendarDay) -> Void) {
        self.selected = selected
        self.onPick = onPick
        let start = selected ?? .today()
        _month = State(initialValue: CalendarDay(year: start.year, month: start.month, day: 1))
    }

    var body: some View {
        let calendar = CalendarDay.calendar
        let today = CalendarDay.today()
        let offset = (month.weekday(calendar) - calendar.firstWeekday + 7) % 7
        let length = month.adding(months: 1).days(from: month)
        let weeks = (offset + length + 6) / 7
        let first = month.adding(days: -offset)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        VStack(spacing: 4) {
            HStack {
                Text(month.date().formatted(.dateTime.month(.wide).year()))
                    .font(.smallMedium)
                    .foregroundStyle(Theme.text)
                Spacer()
                step("chevron.left", "Previous month") { month = month.adding(months: -1) }
                step("chevron.right", "Next month") { month = month.adding(months: 1) }
            }
            .padding(.leading, 6)
            .padding(.bottom, 2)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        Text(symbols[(column + calendar.firstWeekday - 1) % 7])
                            .font(.tiny)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<weeks, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            dayButton(first.adding(days: week * 7 + column), today: today)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func dayButton(_ day: CalendarDay, today: CalendarDay) -> some View {
        let inMonth = day.month == month.month
        let isSelected = day == selected
        let isToday = day == today
        return Button {
            onPick(day)
        } label: {
            Text("\(day.day)")
                .font(.system(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : isToday ? Theme.accent : inMonth ? Theme.text : Theme.textTertiary)
                .opacity(inMonth || isSelected ? 1 : 0.6)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.accentFill : hovered == day ? Theme.popoverSelected : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .onHover { inside in
            if inside { hovered = day } else if hovered == day { hovered = nil }
        }
        .accessibilityLabel(day.longLabel)
    }

    private func step(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .hoverFill(radius: 5)
        }
        .buttonStyle(PlainPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
#endif
