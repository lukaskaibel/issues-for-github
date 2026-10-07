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
/// English always works, and so do the words of the language the app speaks ("morgen", "明日", "через 3 дня").
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
            Suggestion(title: String(localized: .today), day: today),
            Suggestion(title: String(localized: .tomorrow), day: today.adding(days: 1, calendar: calendar)),
        ]
        let friday = endOfWeek(today, calendar)
        if friday.days(from: today, calendar: calendar) >= 2 {
            picks.append(Suggestion(title: weekdayTitle(friday, calendar), day: friday))
        }
        picks.append(Suggestion(title: String(localized: .dueNextWeek), day: nextWeek(today, calendar)))
        picks.append(Suggestion(title: String(localized: .dueInTwoWeeks), day: today.adding(days: 14, calendar: calendar)))
        return unique(picks)
    }

    /// What the text could mean, best first. Empty when it reads as no date at all. Words are read in English and
    /// in the language of the calendar's locale, which is the app's.
    public static func suggestions(for query: String, today: CalendarDay, calendar: Calendar = CalendarDay.calendar) -> [Suggestion] {
        let text = NameWords.fold(query)
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !text.isEmpty else { return [] }
        let languages = DateWords.languages(for: calendar)
        var result = relative(text, today, calendar, languages)
        result += typedOut(text, today, calendar).map { Suggestion(title: nil, day: $0) }
        result += named(text, today, calendar, languages)
        return Array(unique(result).prefix(6))
    }

    // MARK: Named days

    private static func named(_ text: String, _ today: CalendarDay, _ calendar: Calendar, _ languages: [DateWords]) -> [Suggestion] {
        var phrases: [(names: [String], title: String, day: CalendarDay)] = []
        func add(_ names: [String], _ title: String, _ day: CalendarDay) { phrases.append((names, title, day)) }

        let tomorrow = today.adding(days: 1, calendar: calendar)
        let monday = nextWeek(today, calendar)
        add(languages.flatMap(\.today), String(localized: .today), today)
        add(languages.flatMap(\.tomorrow), String(localized: .tomorrow), tomorrow)
        let afterTomorrow = today.adding(days: 2, calendar: calendar)
        add(languages.flatMap(\.dayAfterTomorrow), weekdayTitle(afterTomorrow, calendar), afterTomorrow)
        // The coming weekdays in order, starting tomorrow.
        for offset in 1...7 {
            let day = today.adding(days: offset, calendar: calendar)
            add(languages.flatMap { $0.weekdayNames(day.weekday(calendar)) }, weekdayTitle(day, calendar), day)
        }
        add(languages.flatMap(\.nextWeek), String(localized: .dueNextWeek), monday)
        add(languages.flatMap(\.endOfWeek), String(localized: .dueEndOfWeek), endOfWeek(today, calendar))
        add(languages.flatMap(\.endOfMonth), String(localized: .dueEndOfMonth), endOfMonth(today, calendar))
        add(languages.flatMap(\.nextMonth), String(localized: .dueNextMonth), today.adding(months: 1, calendar: calendar))
        for offset in 0..<7 {
            let day = monday.adding(days: offset, calendar: calendar)
            let names = languages.flatMap { words in
                words.weekdayNames(day.weekday(calendar)).flatMap { name in
                    words.nextWeekday.map { $0.replacingOccurrences(of: "%@", with: name) }
                }
            }
            add(names, String(localized: .dueNextWeekday(weekday: weekdayTitle(day, calendar))), day)
        }
        return phrases
            .filter { phrase in phrase.names.contains { $0.hasPrefix(text) } }
            .map { Suggestion(title: $0.title, day: $0.day) }
    }

    /// "in 3 days", "3 weeks", "3d", "+3", "dans 3 jours", "3日後": a count of days, weeks or months from today.
    /// Without a unit, every unit is offered.
    private static func relative(_ text: String, _ today: CalendarDay, _ calendar: Calendar, _ languages: [DateWords]) -> [Suggestion] {
        var rest = Substring(text)
        if let lead = languages.flatMap(\.countLeads).first(where: { rest.hasPrefix($0) }) { rest = rest.dropFirst(lead.count) }
        if rest.hasPrefix("+") { rest = rest.dropFirst() }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard let count = Int(digits), count > 0, count < 1000 else { return [] }
        let unit = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        // A bare number is more likely a day of the month, which `typedOut` reads, unless "in" or "+" said otherwise.
        if unit.isEmpty, rest.count == text.count { return [] }
        let units: [(names: [String], title: String, days: Int, months: Int)] = [
            (languages.flatMap(\.days), String(localized: .dueInDays(count: count)), count, 0),
            (languages.flatMap(\.weeks), String(localized: .dueInWeeks(count: count)), count * 7, 0),
            (languages.flatMap(\.months), String(localized: .dueInMonths(count: count)), 0, count),
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
        // 2026年10月12日, 10月12号, 10월 12일, and 12日 or 12일 alone: Chinese, Japanese and Korean dates.
        if let match = text.wholeMatch(of: #/(?:(\d{4})\s*[年년]\s*)?(?:(\d{1,2})\s*[月월]\s*)?(\d{1,2})\s*[日号일]?/#),
           match.output.2 != nil || text.last.map({ "日号일".contains($0) }) == true {
            let day = Int(match.output.3)!
            if let month = match.output.2.flatMap({ Int($0) }) {
                return dated(day: day, month: month, year: match.output.1.flatMap { Int($0) }, today, calendar)
            }
            return nextDayOfMonth(day, today, calendar)
        }
        // 12: the next 12th.
        if let day = Int(text), (1...31).contains(day) {
            return nextDayOfMonth(day, today, calendar)
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

    private static func nextDayOfMonth(_ day: Int, _ today: CalendarDay, _ calendar: Calendar) -> [CalendarDay] {
        guard (1...31).contains(day) else { return [] }
        for months in 0...2 {
            let start = today.adding(months: months, calendar: calendar)
            if let candidate = valid(CalendarDay(year: start.year, month: start.month, day: day), calendar), candidate >= today {
                return [candidate]
            }
        }
        return []
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
        let symbols = [english.monthSymbols, calendar.monthSymbols, calendar.shortMonthSymbols, calendar.standaloneMonthSymbols]
        for names in symbols {
            if let index = names.firstIndex(where: { NameWords.fold($0).replacingOccurrences(of: ".", with: "").hasPrefix(word) }) {
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

    /// The weekday's name as a choice in a list: "Friday", "Freitag", "Vendredi", "金曜日".
    static func weekdayTitle(_ day: CalendarDay, _ calendar: Calendar) -> String {
        var style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide)
        style.capitalizationContext = .listItem
        return day.date(calendar).formatted(style)
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

// MARK: - Words for dates

/// What people type for a day in one language, lower case and without accents, as `NameWords.fold` leaves it.
/// Weekday names come from the calendar; `nextWeekday` puts one where "%@" stands.
struct DateWords {
    var language: String
    var today: [String]
    var tomorrow: [String]
    var dayAfterTomorrow: [String] = []
    var nextWeek: [String]
    var endOfWeek: [String]
    var endOfMonth: [String]
    var nextMonth: [String]
    var nextWeekday: [String]
    /// What may come before a count: "in ", "dans ", "через ".
    var countLeads: [String] = []
    var days: [String]
    var weeks: [String]
    var months: [String]
    /// Forms the calendar doesn't give, by weekday (1 is Sunday): Russian says "в пятницу".
    var moreWeekdays: [Int: [String]] = [:]

    /// The weekday's full and short names in this language.
    func weekdayNames(_ weekday: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language == "en" ? "en_US_POSIX" : language)
        let names = [calendar.weekdaySymbols[weekday - 1], calendar.shortWeekdaySymbols[weekday - 1]]
            .map { NameWords.fold($0).replacingOccurrences(of: ".", with: "") }
        return names + (moreWeekdays[weekday] ?? [])
    }

    /// English, and the language of the calendar's locale when it is another one the app speaks.
    static func languages(for calendar: Calendar) -> [DateWords] {
        let code = (calendar.locale ?? .current).language.languageCode?.identifier ?? "en"
        return [english] + (code == "en" ? [] : all.filter { $0.language.hasPrefix(code) })
    }

    private static func folded(_ words: DateWords) -> DateWords {
        var words = words
        for path in [\DateWords.today, \.tomorrow, \.dayAfterTomorrow, \.nextWeek, \.endOfWeek, \.endOfMonth, \.nextMonth,
                     \.nextWeekday, \.countLeads, \.days, \.weeks, \.months] as [WritableKeyPath<DateWords, [String]>] {
            words[keyPath: path] = NameWords.fold(words[keyPath: path])
        }
        words.moreWeekdays = words.moreWeekdays.mapValues(NameWords.fold)
        return words
    }

    static let english = DateWords(
        language: "en", today: ["today"], tomorrow: ["tomorrow", "tmrw"], nextWeek: ["next week"],
        endOfWeek: ["end of week"], endOfMonth: ["end of month"], nextMonth: ["next month"], nextWeekday: ["next %@"],
        countLeads: ["in "], days: ["days", "d"], weeks: ["weeks", "w"], months: ["months", "m"]
    )

    static let all: [DateWords] = [
        DateWords(
            language: "de", today: ["heute"], tomorrow: ["morgen"], dayAfterTomorrow: ["übermorgen"],
            nextWeek: ["nächste woche"], endOfWeek: ["ende der woche"], endOfMonth: ["ende des monats", "monatsende"],
            nextMonth: ["nächsten monat", "nächster monat"], nextWeekday: ["nächsten %@", "nächster %@", "kommenden %@"],
            countLeads: ["in "], days: ["tagen", "tage", "tag", "t"], weeks: ["wochen", "woche", "w"],
            months: ["monaten", "monate", "monat", "m"]
        ),
        DateWords(
            language: "fr", today: ["aujourd'hui", "aujourdhui"], tomorrow: ["demain"], dayAfterTomorrow: ["après-demain", "apres demain"],
            nextWeek: ["semaine prochaine", "la semaine prochaine"], endOfWeek: ["fin de semaine", "fin de la semaine"],
            endOfMonth: ["fin du mois", "fin de mois"], nextMonth: ["mois prochain", "le mois prochain"], nextWeekday: ["%@ prochain"],
            countLeads: ["dans "], days: ["jours", "jour", "j"], weeks: ["semaines", "semaine", "sem", "s"], months: ["mois", "m"]
        ),
        DateWords(
            language: "es", today: ["hoy"], tomorrow: ["mañana"], dayAfterTomorrow: ["pasado mañana"],
            nextWeek: ["la próxima semana", "próxima semana", "la semana que viene", "semana que viene"],
            endOfWeek: ["final de la semana", "fin de la semana"], endOfMonth: ["fin de mes", "final de mes", "fin del mes"],
            nextMonth: ["el próximo mes", "próximo mes", "el mes que viene", "mes que viene"],
            nextWeekday: ["próximo %@", "el próximo %@", "%@ que viene"],
            countLeads: ["dentro de ", "en "], days: ["días", "día", "d"], weeks: ["semanas", "semana", "sem", "s"],
            months: ["meses", "mes", "m"]
        ),
        DateWords(
            language: "pt", today: ["hoje"], tomorrow: ["amanhã"], dayAfterTomorrow: ["depois de amanhã"],
            nextWeek: ["próxima semana", "semana que vem"], endOfWeek: ["fim da semana", "final da semana"],
            endOfMonth: ["fim do mês", "final do mês"], nextMonth: ["próximo mês", "mês que vem"],
            nextWeekday: ["próxima %@", "próximo %@", "%@ que vem", "%@ da próxima semana"],
            countLeads: ["daqui a ", "em "], days: ["dias", "dia", "d"], weeks: ["semanas", "semana", "sem", "s"],
            months: ["meses", "mês", "m"]
        ),
        DateWords(
            language: "ru", today: ["сегодня"], tomorrow: ["завтра"], dayAfterTomorrow: ["послезавтра"],
            nextWeek: ["следующая неделя", "на следующей неделе", "след неделя"], endOfWeek: ["конец недели", "в конце недели"],
            endOfMonth: ["конец месяца", "в конце месяца"], nextMonth: ["следующий месяц", "в следующем месяце"],
            nextWeekday: ["следующий %@", "следующую %@", "следующее %@", "в следующий %@", "в следующую %@", "в следующее %@"],
            countLeads: ["через "], days: ["дней", "дня", "день", "дн", "д"],
            weeks: ["недель", "недели", "неделю", "неделя", "нед", "н"], months: ["месяцев", "месяца", "месяц", "мес", "м"],
            moreWeekdays: [1: ["в воскресенье"], 2: ["в понедельник"], 3: ["во вторник"], 4: ["среду", "в среду"],
                           5: ["в четверг"], 6: ["пятницу", "в пятницу"], 7: ["субботу", "в субботу"]]
        ),
        DateWords(
            language: "ja", today: ["今日", "きょう"], tomorrow: ["明日", "あした", "あす"], dayAfterTomorrow: ["明後日", "あさって"],
            nextWeek: ["来週"], endOfWeek: ["今週中", "週の終わり"], endOfMonth: ["月末", "今月末"], nextMonth: ["来月"],
            nextWeekday: ["来週の%@", "来週%@"],
            days: ["日後", "日"], weeks: ["週間後", "週後", "週間", "週"], months: ["か月後", "ヶ月後", "カ月後", "ヵ月後", "か月", "ヶ月", "カ月", "ヵ月"]
        ),
        DateWords(
            language: "zh", today: ["今天"], tomorrow: ["明天"], dayAfterTomorrow: ["后天"],
            nextWeek: ["下周", "下星期", "下个星期"], endOfWeek: ["本周内", "这周内"], endOfMonth: ["月底", "本月底"],
            nextMonth: ["下个月", "下月"], nextWeekday: ["下%@", "下个%@"],
            days: ["天后", "天", "日后"], weeks: ["周后", "周", "个星期后", "星期后"], months: ["个月后", "个月", "月后"]
        ),
        DateWords(
            language: "ko", today: ["오늘"], tomorrow: ["내일"], dayAfterTomorrow: ["모레"],
            nextWeek: ["다음 주", "다음주"], endOfWeek: ["이번 주 안", "이번 주 중"], endOfMonth: ["월말", "이번 달 말"],
            nextMonth: ["다음 달", "다음달"], nextWeekday: ["다음 주 %@", "다음주 %@"],
            days: ["일 후", "일 뒤", "일후", "일뒤", "일"], weeks: ["주 후", "주 뒤", "주후", "주"],
            months: ["개월 후", "개월 뒤", "개월", "달 후", "달"]
        ),
    ].map(folded)
}
