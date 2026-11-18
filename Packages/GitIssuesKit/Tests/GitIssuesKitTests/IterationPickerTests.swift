import Testing
@testable import GitIssuesKit

@Suite("Putting issues into an iteration")
@MainActor
struct IterationPickerTests {
    /// Weekly cycles around Monday, November 9, 2026: 3 is over, 4 is under way, 5 and 6 are to come.
    static let field = ProjectField(
        id: "F-it", projectId: "P1", databaseId: 3, name: "Sprint", dataType: "ITERATION", position: 2,
        iterations: [
            IterationSpan(id: "c5", title: "Cycle 5", startDate: "2026-11-16", duration: 7, completed: false),
            IterationSpan(id: "c3", title: "Cycle 3", startDate: "2026-11-02", duration: 7, completed: true),
            IterationSpan(id: "c4", title: "Cycle 4", startDate: "2026-11-09", duration: 7, completed: false),
            IterationSpan(id: "c6", title: "Cycle 6", startDate: "2026-11-23", duration: 7, completed: false),
        ]
    )
    static let today = CalendarDay(year: 2026, month: 11, day: 10)

    private func item(_ id: String, projectId: String? = "P1", iteration: String? = nil) -> Item {
        var item = Item(id: id, projectId: projectId, kind: .issue, position: 0, number: 1, title: id, body: "", state: "OPEN")
        if let iteration { item.fieldValues["F-it"] = FieldValue(iterationId: iteration) }
        return item
    }

    @Test("The one under way and those to come, earliest first; one that is over only for issues in it")
    func choices() {
        #expect(AppModel.iterationChoices(Self.field, today: Self.today).map(\.id) == ["c4", "c5", "c6"])
        #expect(AppModel.iterationChoices(Self.field, keeping: ["c3"], today: Self.today).map(\.id) == ["c3", "c4", "c5", "c6"])
        // GitHub moves an iteration to the completed ones a little after it ends; until then it is over all the same.
        let later = CalendarDay(year: 2026, month: 11, day: 16)
        #expect(AppModel.iterationChoices(Self.field, today: later).map(\.id) == ["c5", "c6"])
    }

    @Test("The current and the next iteration say so, by GitHub's count")
    func places() {
        let place = { (id: String, day: CalendarDay) in
            AppModel.iterationPlace(Self.field.iterations.first { $0.id == id }!, field: Self.field, today: day)
        }
        #expect(place("c4", Self.today) == String(localized: .currentIteration))
        #expect(place("c5", Self.today) == String(localized: .nextIteration))
        #expect(place("c6", Self.today) == nil)
        #expect(place("c3", Self.today) == nil)
    }

    @Test("No iteration comes first; the issues' shared iteration is checked, and none when they differ")
    func rows() {
        let rows = AppModel.iterationItems(field: Self.field, current: ["c5"], today: Self.today)
        #expect(rows.map(\.id) == ["", "c4", "c5", "c6"])
        #expect(rows.map(\.selected) == [false, false, true, false])
        #expect(rows.map(\.shortcut) == ["0", "1", "2", "3"])
        #expect(rows.map(\.subtitle) == [nil, String(localized: .currentIteration), String(localized: .nextIteration), nil])
        #expect(rows[0].title == String(localized: .noIteration))

        let none = AppModel.iterationItems(field: Self.field, current: [nil], today: Self.today)
        #expect(none.map(\.selected) == [true, false, false, false])

        let mixed = AppModel.iterationItems(field: Self.field, current: [nil, "c4"], today: Self.today)
        #expect(mixed.allSatisfy { !$0.selected })
    }

    @Test("An issue in an iteration that is over keeps it among the choices, checked")
    func pastIterationStays() {
        let rows = AppModel.iterationItems(field: Self.field, current: ["c3"], today: Self.today)
        #expect(rows.map(\.id) == ["", "c3", "c4", "c5", "c6"])
        #expect(rows[1].selected)
    }

    @Test("Names that start with digits aren't picked by number keys, which would type them")
    func digitNames() {
        var field = Self.field
        field.iterations = [IterationSpan(id: "a", title: "2026-W46", startDate: "2026-11-09", duration: 7, completed: false)]
        let rows = AppModel.iterationItems(field: field, current: [nil], today: Self.today)
        #expect(rows.map(\.shortcut) == [nil, nil])
    }

    @Test("What picked issues share counts only the field's own board")
    func sharedValue() {
        let items = [item("a", iteration: "c4"), item("b", iteration: "c4"), item("c", projectId: "P2")]
        #expect(AppModel.iterationIds(of: items, field: Self.field) == ["c4"])
        #expect(AppModel.iterationIds(of: [item("a", iteration: "c4"), item("b")], field: Self.field) == ["c4", nil])
    }

    @Test("The picker is one per iteration field, and ⇧C opens it")
    func pickerKind() {
        let kind = PickerKind.iteration(fieldId: "F-it")
        #expect(kind == .iteration(fieldId: "F-it"))
        #expect(kind != .iteration(fieldId: "F-other"))
        #expect(kind.hint == "⇧C")
        #expect(!kind.multiple)
        #expect(kind.opensOnSelection)
        #expect(!kind.picksIssues)
    }
}
