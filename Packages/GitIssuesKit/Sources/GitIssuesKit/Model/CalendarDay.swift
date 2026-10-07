import Foundation

/// A day without a time, as GitHub's Date fields hold it ("2026-10-09"). It is read in the Gregorian
/// calendar and the time zone of this device, so "today" is the reader's today.
public struct CalendarDay: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads "2026-10-09". Anything after the date, such as a time, is ignored.
    public init?(_ text: String) {
        let parts = text.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init(_ date: Date, calendar: Calendar = CalendarDay.calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public static func today(_ calendar: Calendar = CalendarDay.calendar, now: Date = Date()) -> CalendarDay {
        CalendarDay(now, calendar: calendar)
    }

    /// The calendar days are counted in: Gregorian, as GitHub's dates are, in this device's time zone and with
    /// its first day of the week. Made again only when the time zone or region changes, since every card asks.
    public static var calendar: Calendar {
        let zone = TimeZone.current
        let locale = Locale.current
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedCalendar, cached.timeZone == zone, cached.locale == locale { return cached }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        calendar.firstWeekday = Calendar.current.firstWeekday
        cachedCalendar = calendar
        return calendar
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedCalendar: Calendar?

    /// The form GitHub reads and writes.
    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// The start of the day.
    public func date(_ calendar: Calendar = CalendarDay.calendar) -> Date {
        calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int = 0, months: Int = 0, calendar: Calendar = CalendarDay.calendar) -> CalendarDay {
        var step = DateComponents()
        step.day = days
        step.month = months
        let moved = calendar.date(byAdding: step, to: date(calendar)) ?? date(calendar)
        return CalendarDay(moved, calendar: calendar)
    }

    /// Whole days from `other` to this day: 1 when this is the day after.
    public func days(from other: CalendarDay, calendar: Calendar = CalendarDay.calendar) -> Int {
        calendar.dateComponents([.day], from: other.date(calendar), to: date(calendar)).day ?? 0
    }

    /// 1 is Sunday, 2 Monday, up to 7 for Saturday, as in `Calendar`.
    public func weekday(_ calendar: Calendar = CalendarDay.calendar) -> Int {
        calendar.component(.weekday, from: date(calendar))
    }

    /// Whether the day exists, so 31 February is turned down.
    func isValid(_ calendar: Calendar) -> Bool {
        CalendarDay(date(calendar), calendar: calendar) == self
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

extension Item {
    /// The day the issue is due, from the project's date field.
    public var due: CalendarDay? {
        dueDate.flatMap(CalendarDay.init)
    }
}

// MARK: - Typing a date

/// Reads a due date typed in a few words, as Linear and Things do: "today", "tomorrow", "fri", "next week",
/// "in 3 days", "2w", "12.10.", "10/12", "oct 12" or "2026-10-12". Words may be cut short ("tom", "next f").
public enum DueDateParser {
    public struct Suggestion: Hashable, Sendable {
        /// "Tomorrow", "Friday", "In 3 days"; nil for a date typed out, which is shown as the date itself.
        public var title: String?
        public var day: CalendarDay
    }

    /// The choices offered before anything is typed: today, tomorrow, the end of this week, next week and in
    /// two weeks, without repeating a day.
    public static func quickPicks(today: CalendarDay, calendar: Calendar = CalendarDay.calendar) -> [Suggestion] {
        var picks = [
            Suggestion(title: "Today", day: today),
            Suggestion(title: "Tomorrow", day: today.adding(days: 1, calendar: calendar)),
        ]
        let friday = endOfWeek(today, calendar)
        if friday.days(from: today, calendar: calendar) >= 2 {
            picks.append(Suggestion(title: weekdayName(friday, calendar), day: friday))
        }
        picks.append(Suggestion(title: "Next week", day: nextWeek(today, calendar)))
        picks.append(Suggestion(title: "In two weeks", day: today.adding(days: 14, calendar: calendar)))
        return unique(picks)
    }

    /// What the text could mean, best first. Empty when it reads as no date at all.
    public static func suggestions(for query: String, today: CalendarDay, calendar: Calendar = CalendarDay.calendar) -> [Suggestion] {
        let text = query.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !text.isEmpty else { return [] }
        var result = relative(text, today, calendar)
        result += typedOut(text, today, calendar).map { Suggestion(title: nil, day: $0) }
        result += named(text, today, calendar)
        return Array(unique(result).prefix(6))
    }

    // MARK: Named days

    private static func named(_ text: String, _ today: CalendarDay, _ calendar: Calendar) -> [Suggestion] {
        var phrases: [(name: String, title: String, day: CalendarDay)] = [
            ("today", "Today", today),
            ("tomorrow", "Tomorrow", today.adding(days: 1, calendar: calendar)),
            ("tmrw", "Tomorrow", today.adding(days: 1, calendar: calendar)),
        ]
        // The coming weekdays in order, starting tomorrow.
        for offset in 1...7 {
            let day = today.adding(days: offset, calendar: calendar)
            let name = weekdayName(day, calendar)
            phrases.append((name.lowercased(), name, day))
        }
        phrases.append(("next week", "Next week", nextWeek(today, calendar)))
        phrases.append(("end of week", "End of week", endOfWeek(today, calendar)))
        phrases.append(("end of month", "End of month", endOfMonth(today, calendar)))
        phrases.append(("next month", "Next month", today.adding(months: 1, calendar: calendar)))
        let monday = nextWeek(today, calendar)
        for offset in 0..<7 {
            let day = monday.adding(days: offset, calendar: calendar)
            let name = weekdayName(day, calendar)
            phrases.append(("next \(name.lowercased())", "Next \(name)", day))
        }
        return phrases.filter { $0.name.hasPrefix(text) }.map { Suggestion(title: $0.title, day: $0.day) }
    }

    /// "in 3 days", "3 weeks", "3d", "+3": a count of days, weeks or months from today. Without a unit,
    /// every unit is offered.
    private static func relative(_ text: String, _ today: CalendarDay, _ calendar: Calendar) -> [Suggestion] {
        var rest = Substring(text)
        if rest.hasPrefix("in ") { rest = rest.dropFirst(3) }
        if rest.hasPrefix("+") { rest = rest.dropFirst() }
        let digits = rest.prefix { $0.isNumber }
        guard let count = Int(digits), count > 0, count < 1000 else { return [] }
        let unit = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        // A bare number is more likely a day of the month, which `typedOut` reads, unless "in" or "+" said otherwise.
        if unit.isEmpty, rest.count == text.count { return [] }
        let units: [(names: [String], title: String, days: Int, months: Int)] = [
            (["days", "d"], count == 1 ? "In 1 day" : "In \(count) days", count, 0),
            (["weeks", "w"], count == 1 ? "In 1 week" : "In \(count) weeks", count * 7, 0),
            (["months", "m"], count == 1 ? "In 1 month" : "In \(count) months", 0, count),
        ]
        return units
            .filter { option in unit.isEmpty || option.names.contains { $0.hasPrefix(unit) || unit == $0 } }
            .map { Suggestion(title: $0.title, day: today.adding(days: $0.days, months: $0.months, calendar: calendar)) }
    }

    // MARK: Dates typed out

    private static func typedOut(_ text: String, _ today: CalendarDay, _ calendar: Calendar) -> [CalendarDay] {
        func numbers(_ string: String, separator: Character) -> [Int]? {
            let parts = string.split(separator: separator, omittingEmptySubsequences: false)
            var values: [Int] = []
            for (index, part) in parts.enumerated() {
                // "12.10." ends in a separator.
                if part.isEmpty, index == parts.count - 1, index > 0 { continue }
                guard let value = Int(part) else { return nil }
                values.append(value)
            }
            return values
        }
        // 2026-10-12
        if let parts = numbers(text, separator: "-"), parts.count == 3, parts[0] > 999 {
            return valid(CalendarDay(year: parts[0], month: parts[1], day: parts[2]), calendar).map { [$0] } ?? []
        }
        // 12.10. and 12.10.2026, day first as in most of Europe.
        if text.contains("."), let parts = numbers(text, separator: "."), (2...3).contains(parts.count) {
            return dated(day: parts[0], month: parts[1], year: parts.count == 3 ? parts[2] : nil, today, calendar)
        }
        // 10/12: in the order of this device's date format.
        if text.contains("/"), let parts = numbers(text, separator: "/"), (2...3).contains(parts.count) {
            let monthFirst = monthComesFirst(calendar.locale ?? .current)
            return dated(
                day: monthFirst ? parts[1] : parts[0], month: monthFirst ? parts[0] : parts[1],
                year: parts.count == 3 ? parts[2] : nil, today, calendar
            )
        }
        // 12: the next 12th.
        if let day = Int(text), (1...31).contains(day) {
            for months in 0...2 {
                let start = today.adding(months: months, calendar: calendar)
                if let candidate = valid(CalendarDay(year: start.year, month: start.month, day: day), calendar), candidate >= today {
                    return [candidate]
                }
            }
            return []
        }
        // oct 12, 12 october, 12. oct 2027
        let words = text.replacingOccurrences(of: ".", with: " ").split(separator: " ").map(String.init)
        guard (2...3).contains(words.count) else { return [] }
        let numbers = words.compactMap(Int.init)
        let names = words.filter { Int($0) == nil }
        guard names.count == 1, let month = month(named: names[0], calendar), let day = numbers.first else { return [] }
        let year = numbers.count == 2 ? numbers[1] : nil
        return dated(day: day, month: month, year: year, today, calendar)
    }

    private static func dated(day: Int, month: Int, year: Int?, _ today: CalendarDay, _ calendar: Calendar) -> [CalendarDay] {
        if var year {
            if year < 100 { year += 2000 }
            return valid(CalendarDay(year: year, month: month, day: day), calendar).map { [$0] } ?? []
        }
        // Without a year, the next time that day comes round.
        for year in [today.year, today.year + 1] {
            if let candidate = valid(CalendarDay(year: year, month: month, day: day), calendar), candidate >= today {
                return [candidate]
            }
        }
        return []
    }

    private static func valid(_ day: CalendarDay, _ calendar: Calendar) -> CalendarDay? {
        guard (1...12).contains(day.month), (1...31).contains(day.day), day.isValid(calendar) else { return nil }
        return day
    }

    private static func month(named word: String, _ calendar: Calendar) -> Int? {
        guard word.count >= 3 else { return nil }
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        for symbols in [english.monthSymbols, calendar.monthSymbols, calendar.shortMonthSymbols] {
            if let index = symbols.firstIndex(where: { $0.lowercased().replacingOccurrences(of: ".", with: "").hasPrefix(word) }) {
                return index + 1
            }
        }
        return nil
    }

    private static func monthComesFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let month = format.firstIndex(of: "M"), let day = format.firstIndex(of: "d") else { return true }
        return month < day
    }

    // MARK: Helpers

    static func weekdayName(_ day: CalendarDay, _ calendar: Calendar) -> String {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        return english.weekdaySymbols[day.weekday(calendar) - 1]
    }

    /// The Monday after this week.
    static func nextWeek(_ today: CalendarDay, _ calendar: Calendar) -> CalendarDay {
        let toMonday = (9 - today.weekday(calendar)) % 7
        return today.adding(days: toMonday == 0 ? 7 : toMonday, calendar: calendar)
    }

    /// This week's Friday; on a weekend, the next one.
    static func endOfWeek(_ today: CalendarDay, _ calendar: Calendar) -> CalendarDay {
        let toFriday = (6 - today.weekday(calendar) + 7) % 7
        return today.adding(days: toFriday, calendar: calendar)
    }

    static func endOfMonth(_ today: CalendarDay, _ calendar: Calendar) -> CalendarDay {
        let first = CalendarDay(year: today.year, month: today.month, day: 1)
        return first.adding(days: -1, months: 1, calendar: calendar)
    }

    private static func unique(_ suggestions: [Suggestion]) -> [Suggestion] {
        var seen = Set<CalendarDay>()
        return suggestions.filter { seen.insert($0.day).inserted }
    }
}
