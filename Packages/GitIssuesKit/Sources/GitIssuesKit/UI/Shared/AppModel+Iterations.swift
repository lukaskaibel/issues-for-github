import SwiftUI

/// An issue's iteration: the cycle of a GitHub project it is planned for. GitHub works out which one is current from
/// the dates, so nobody sets that; here an issue is put into one, or taken out of its own.
extension AppModel {
    /// A board's iteration fields, in GitHub's order. Most boards have one at most; ⇧C opens the first.
    func iterationFields(projectId: String?) -> [ProjectField] {
        fields(projectId: projectId).filter { $0.kind == .iteration }.sorted { $0.position < $1.position }
    }

    /// The iteration fields an issue can have a value of: those of its board. Every card can, drafts and pull
    /// requests too.
    func iterationFields(for item: Item) -> [ProjectField] {
        guard item.isOnBoard, !item.isDetached else { return [] }
        return iterationFields(projectId: item.projectId)
    }

    func iteration(of item: Item, field: ProjectField) -> IterationSpan? {
        guard let id = item.fieldValues[field.id]?.iterationId else { return nil }
        return field.iterations.first { $0.id == id }
    }

    func iterationChoices(_ field: ProjectField, keeping: Set<String> = [], today: CalendarDay = .today()) -> [IterationSpan] {
        Self.iterationChoices(field, keeping: keeping, today: today)
    }

    /// The iterations to choose from, earliest first: the one under way and those to come, and one whose time is over
    /// only while an issue in `keeping` is in it.
    static func iterationChoices(_ field: ProjectField, keeping: Set<String> = [], today: CalendarDay = .today()) -> [IterationSpan] {
        field.orderedIterations.filter { iteration in
            keeping.contains(iteration.id) || !iteration.completed && (iteration.end.map { $0 >= today } ?? true)
        }
    }

    func iterationPlace(_ iteration: IterationSpan, field: ProjectField, today: CalendarDay = .today()) -> String? {
        Self.iterationPlace(iteration, field: field, today: today)
    }

    /// "Current" or "Next", in GitHub's sense: between two iterations the coming one is current.
    static func iterationPlace(_ iteration: IterationSpan, field: ProjectField, today: CalendarDay = .today()) -> String? {
        if field.iteration(offset: 0, from: today)?.id == iteration.id { return String(localized: .currentIteration) }
        if field.iteration(offset: 1, from: today)?.id == iteration.id { return String(localized: .nextIteration) }
        return nil
    }

    /// A menu row's title, "Cycle 5 · Next": menus show no second line in a picker, so the place goes with the name.
    func iterationMenuTitle(_ iteration: IterationSpan, field: ProjectField) -> String {
        iterationPlace(iteration, field: field).map { "\(iteration.title) · \($0)" } ?? iteration.title
    }

    /// Whether it is the iteration under way, as GitHub's `@current` counts.
    func isRunning(_ iteration: IterationSpan, field: ProjectField, today: CalendarDay = .today()) -> Bool {
        field.iteration(offset: 0, from: today)?.id == iteration.id
    }

    func iterationIds(of items: [Item], field: ProjectField) -> Set<String?> {
        Self.iterationIds(of: items, field: field)
    }

    /// The iterations issues are in, by id (nil for none). Picked issues of another board can't be in this one's.
    static func iterationIds(of items: [Item], field: ProjectField) -> Set<String?> {
        Set(items.filter { $0.projectId == field.projectId }.map { $0.fieldValues[field.id]?.iterationId })
    }

    /// Puts issues into an iteration, or takes them out of theirs (nil). Issues of another board stay as they are.
    func setIteration(of items: [Item], field: ProjectField, to iteration: IterationSpan?) {
        withAnimation(Theme.spring) {
            setValue(iteration.map { FieldValue(iterationId: $0.id) }, of: field, for: items)
        }
    }

    /// What VoiceOver and tooltips say about an issue's iteration: "Iteration: Cycle 5", or "No iteration".
    func iterationDescription(of item: Item, field: ProjectField) -> String {
        guard let iteration = iteration(of: item, field: field) else { return String(localized: .noIteration) }
        return String(localized: .fieldValueSpoken(field: field.name, value: iteration.title))
    }

    // MARK: Picker rows

    func iterationItems(field: ProjectField, current: Set<String?>) -> [PickerItem] {
        Self.iterationItems(field: field, current: current)
    }

    /// No iteration, then the iterations to choose from with the one `current` holds checked (the issues' when they
    /// share one): the current and the next one say so, every one its days. Number keys pick them, unless their names
    /// start with digits.
    static func iterationItems(field: ProjectField, current: Set<String?>, today: CalendarDay = .today()) -> [PickerItem] {
        let choices = iterationChoices(field, keeping: Set(current.compactMap { $0 }), today: today)
        let numbered = numbersPickMilestones(choices.map(\.title))
        let running = field.iteration(offset: 0, from: today)?.id
        var rows = [PickerItem(
            id: "", title: String(localized: .noIteration), selected: current == [nil],
            icon: AnyView(NoIterationIcon()), shortcut: numbered ? "0" : nil
        )]
        for (index, iteration) in choices.enumerated() {
            rows.append(PickerItem(
                id: iteration.id, title: iteration.title,
                subtitle: iterationPlace(iteration, field: field, today: today),
                selected: current == [iteration.id],
                icon: AnyView(IterationIcon().foregroundStyle(iteration.id == running ? Theme.started : Theme.textSecondary)),
                shortcut: numbered && index < 9 ? "\(index + 1)" : nil,
                trailing: iterationRange(iteration).map { days in
                    AnyView(Text(days).font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary).lineLimit(1))
                }
            ))
        }
        return rows
    }
}

/// No iteration: the iteration's arrows, faint.
struct NoIterationIcon: View {
    var size: CGFloat = 14

    var body: some View {
        IterationIcon(size: size).foregroundStyle(Theme.textTertiary.opacity(0.6))
    }
}
