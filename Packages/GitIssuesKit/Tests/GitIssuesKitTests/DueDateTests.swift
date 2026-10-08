import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Due dates: reading GitHub's days and dates typed in a few words")
struct DueDateTests {
    /// Wednesday, 7 October 2026, in a calendar whose weeks start on Monday, as in Germany.
    static let today = CalendarDay(year: 2026, month: 10, day: 7)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "en_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    private func days(_ query: String) -> [String] {
        DueDateParser.suggestions(for: query, today: Self.today, calendar: Self.calendar).map(\.day.string)
    }

    private func first(_ query: String) -> String? {
        days(query).first
    }

    @Test func readsAndWritesGitHubsForm() {
        #expect(CalendarDay("2026-10-09")?.string == "2026-10-09")
        #expect(CalendarDay("2026-10-09T00:00:00Z") == CalendarDay(year: 2026, month: 10, day: 9))
        #expect(CalendarDay("2026-13-01") == nil)
        #expect(CalendarDay("soon") == nil)
    }

    @Test func countsDaysAcrossMonthsAndClockChanges() {
        let c = Self.calendar
        #expect(Self.today.adding(days: 25, calendar: c).string == "2026-11-01")
        // Summer time ends on 25 October in Germany; a day is still a day.
        #expect(CalendarDay(year: 2026, month: 10, day: 26).days(from: CalendarDay(year: 2026, month: 10, day: 24), calendar: c) == 2)
        #expect(CalendarDay(year: 2026, month: 1, day: 31).adding(months: 1, calendar: c).string == "2026-02-28")
    }

    @Test func offersTodayTomorrowFridayNextWeekAndTwoWeeks() {
        let picks = DueDateParser.quickPicks(today: Self.today, calendar: Self.calendar)
        #expect(picks.map(\.title) == ["Today", "Tomorrow", "Friday", "Next week", "In two weeks"])
        #expect(picks.map(\.day.string) == ["2026-10-07", "2026-10-08", "2026-10-09", "2026-10-12", "2026-10-21"])
    }

    @Test func leavesOutFridayWhenItIsTomorrow() {
        let thursday = CalendarDay(year: 2026, month: 10, day: 8)
        let picks = DueDateParser.quickPicks(today: thursday, calendar: Self.calendar)
        #expect(picks.map(\.title) == ["Today", "Tomorrow", "Next week", "In two weeks"])
    }

    @Test func readsNamedDaysFromTheirFirstLetters() {
        #expect(first("today") == "2026-10-07")
        #expect(first("tom") == "2026-10-08")
        #expect(first("tmrw") == "2026-10-08")
        #expect(first("fri") == "2026-10-09")
        #expect(first("Friday") == "2026-10-09")
        // Today is Wednesday, so "wed" is next week's.
        #expect(first("wed") == "2026-10-14")
        #expect(first("next week") == "2026-10-12")
        #expect(first("next fri") == "2026-10-16")
        #expect(first("end of week") == "2026-10-09")
        #expect(first("end of month") == "2026-10-31")
        // Today, tomorrow (which is Thursday) and Tuesday, each day once.
        #expect(days("t") == ["2026-10-07", "2026-10-08", "2026-10-13"])
    }

    @Test func readsCountsOfDaysWeeksAndMonths() {
        #expect(first("in 3 days") == "2026-10-10")
        #expect(first("3d") == "2026-10-10")
        #expect(first("+3") == "2026-10-10")
        #expect(first("2w") == "2026-10-21")
        #expect(first("in 2 weeks") == "2026-10-21")
        #expect(first("in 1 month") == "2026-11-07")
        // Without a unit, every unit is offered.
        #expect(days("in 3") == ["2026-10-10", "2026-10-28", "2027-01-07"])
    }

    @Test func readsDatesTypedOut() {
        #expect(first("12.10.") == "2026-10-12")
        #expect(first("12.10.2027") == "2027-10-12")
        #expect(first("12.10.27") == "2027-10-12")
        #expect(first("2026-12-24") == "2026-12-24")
        #expect(first("oct 12") == "2026-10-12")
        #expect(first("12 October") == "2026-10-12")
        #expect(first("12. oct") == "2026-10-12")
        // In a German calendar the day comes first.
        #expect(first("1/12") == "2026-12-01")
    }

    @Test func movesDatesWithoutAYearToTheNextTimeTheyComeRound() {
        #expect(first("1.3.") == "2027-03-01")
        #expect(first("12") == "2026-10-12")
        #expect(first("3") == "2026-11-03")
        #expect(first("7") == "2026-10-07")
    }

    /// Words in the app's language, read besides English; today is Wednesday, 7 October.
    @Test(arguments: [
        ("de_DE", "morgen", "2026-10-08"), ("de_DE", "übermorgen", "2026-10-09"), ("de_DE", "fr", "2026-10-09"),
        ("de_DE", "nächste woche", "2026-10-12"), ("de_DE", "nächsten fr", "2026-10-16"), ("de_DE", "in 3 tagen", "2026-10-10"),
        ("de_DE", "2 wochen", "2026-10-21"), ("de_DE", "12. okt", "2026-10-12"), ("de_DE", "tomorrow", "2026-10-08"),
        ("fr_FR", "demain", "2026-10-08"), ("fr_FR", "ven", "2026-10-09"), ("fr_FR", "vendredi prochain", "2026-10-16"),
        ("fr_FR", "dans 3 jours", "2026-10-10"), ("fr_FR", "fin du mois", "2026-10-31"),
        ("es_ES", "mañana", "2026-10-08"), ("es_ES", "manana", "2026-10-08"), ("es_ES", "miercoles", "2026-10-14"),
        ("es_ES", "próximo viernes", "2026-10-16"), ("es_ES", "en 2 semanas", "2026-10-21"),
        ("pt_BR", "amanhã", "2026-10-08"), ("pt_BR", "sexta", "2026-10-09"), ("pt_BR", "próxima sexta", "2026-10-16"),
        ("pt_BR", "em 3 dias", "2026-10-10"),
        ("ru_RU", "завтра", "2026-10-08"), ("ru_RU", "пятницу", "2026-10-09"), ("ru_RU", "в пятницу", "2026-10-09"),
        ("ru_RU", "в следующую пятницу", "2026-10-16"), ("ru_RU", "через 3 дня", "2026-10-10"), ("ru_RU", "через 2 недели", "2026-10-21"),
        ("ja_JP", "明日", "2026-10-08"), ("ja_JP", "金", "2026-10-09"), ("ja_JP", "来週の金曜", "2026-10-16"),
        ("ja_JP", "来週", "2026-10-12"), ("ja_JP", "3日後", "2026-10-10"), ("ja_JP", "10月12日", "2026-10-12"),
        ("zh_CN", "明天", "2026-10-08"), ("zh_CN", "周五", "2026-10-09"), ("zh_CN", "下周五", "2026-10-16"),
        ("zh_CN", "3天后", "2026-10-10"), ("zh_CN", "10月12号", "2026-10-12"), ("zh_CN", "12号", "2026-10-12"),
        ("ko_KR", "내일", "2026-10-08"), ("ko_KR", "금요일", "2026-10-09"), ("ko_KR", "다음 주 금요일", "2026-10-16"),
        ("ko_KR", "3일 후", "2026-10-10"), ("ko_KR", "10월 12일", "2026-10-12"),
    ])
    func readsTheAppsLanguage(locale: String, query: String, expected: String) {
        var calendar = Self.calendar
        calendar.locale = Locale(identifier: locale)
        let found = DueDateParser.suggestions(for: query, today: Self.today, calendar: calendar).first?.day.string
        #expect(found == expected, "\(locale): \(query)")
    }

    @Test func readsOnlyEnglishAndTheAppsLanguage() {
        // German words mean nothing in an English app.
        #expect(days("morgen").isEmpty)
    }

    @Test func turnsDownWhatIsNoDate() {
        #expect(days("31.2.").isEmpty)
        #expect(days("banana").isEmpty)
        #expect(days("").isEmpty)
        #expect(days("in 0 days").isEmpty)
    }
}
