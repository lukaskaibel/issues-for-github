import SwiftUI

/// Something a view can be filtered by, as the filter menu lists it: Status, Assignee, Label, a field of the
/// project's own, and so on, with the values to pick from.
struct FilterProperty: Identifiable, Equatable {
    /// The qualifier the filter writes, such as "label" or "due-date".
    var id: String
    var title: String
    var icon: FilterIcon
    /// Whether several values can be picked, which then means "any of them".
    var takesSeveral = true
    /// Whether its values need its name beside them in a short line of chips: "Current" says little without
    /// "Iteration", where a person or a label speaks for itself.
    var namedWithValues = false
}

/// One value to pick in the filter menu: what it adds to the filter, how it reads, and how many issues it finds.
struct FilterValue: Identifiable, Equatable {
    /// The qualifier and value it adds, such as ("label", "AP2"), ("no", "assignee") or ("iteration", "@current").
    var key: String
    var value: String
    var title: String
    var subtitle: String?
    var icon: FilterIcon
    var count: Int = 0

    var id: String { "\(key):\(value)" }
}

/// The icon of a property, a value or a chip.
enum FilterIcon: Equatable {
    case status(StatusGlyph)
    case symbol(String)
    case person(Person)
    case label(String)
    case milestone(MilestoneMark)
    case dot(String)
    case iteration(current: Bool)
    case priority(PriorityLevel)
    case none
}

/// A filter term as a chip shows it: the property, how it compares, and the values.
struct FilterChipModel: Equatable {
    var property: String
    var icon: FilterIcon
    /// "is", "is not", "is any of", "is none of", "is empty"; nil for words to search for and terms only shown.
    var comparison: String?
    var values: String?
    /// Whether the values can be picked again from the filter menu.
    var picksValues: Bool
    /// Whether "is" can turn into "is not".
    var negatable: Bool
    /// A term the app shows as written, in GitHub's words.
    var isRaw = false
    /// Whether its values need the property's name beside them in a short line of chips.
    var namedWithValues = false
}

extension AppModel {
    // MARK: Properties

    /// What the filter menu offers for a project, in the order Linear lists them.
    func filterProperties(projectId: String) -> [FilterProperty] {
        let project = projects.first { $0.id == projectId }
        var result: [FilterProperty] = []
        if project?.statusFieldId != nil {
            let glyph = StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody)
            result.append(FilterProperty(id: "status", title: String(localized: .status), icon: .status(glyph)))
        }
        result.append(FilterProperty(id: "assignee", title: String(localized: .assignee), icon: .symbol("person")))
        result.append(FilterProperty(id: "label", title: String(localized: .filterLabel), icon: .symbol("tag")))
        if !milestoneGroups(projectId: projectId).isEmpty {
            result.append(FilterProperty(id: "milestone", title: String(localized: .milestone), icon: .milestone(.upcoming)))
        }
        let own: Set<String?> = [project?.statusFieldId, project?.priorityFieldId, project?.dueFieldId]
        for field in fields(projectId: projectId) where field.kind == .iteration {
            result.append(FilterProperty(id: field.filterKey, title: field.name, icon: .iteration(current: false), namedWithValues: true))
        }
        if project?.priorityFieldId != nil {
            result.append(FilterProperty(id: "priority", title: String(localized: .priority), icon: .priority(.high)))
        }
        for field in fields(projectId: projectId) where field.kind == .singleSelect && !own.contains(field.id) {
            result.append(FilterProperty(id: field.filterKey, title: field.name, icon: .symbol("chevron.down.circle"), namedWithValues: true))
        }
        let items = allItems.filter { $0.projectId == projectId }
        if items.contains(where: { $0.issueType != nil }) {
            result.append(FilterProperty(id: "type", title: String(localized: .filterIssueType), icon: .symbol("circle.grid.2x2")))
        }
        if items.contains(where: { $0.parentId != nil }) {
            result.append(FilterProperty(id: "parent-issue", title: String(localized: .filterParentIssue), icon: .symbol("arrow.turn.down.right")))
        }
        if repos(projectId: projectId).count > 1 {
            result.append(FilterProperty(id: "repo", title: String(localized: .repository), icon: .symbol("book.closed")))
        }
        if let due = project?.dueFieldId.flatMap({ field(id: $0) }) {
            result.append(FilterProperty(id: due.filterKey, title: String(localized: .dueDate), icon: .symbol("calendar"), takesSeveral: false, namedWithValues: true))
        }
        result.append(FilterProperty(id: "updated", title: String(localized: .filterUpdated), icon: .symbol("clock"), takesSeveral: false, namedWithValues: true))
        result.append(FilterProperty(id: "is", title: String(localized: .filterOpenOrClosed), icon: .symbol("circle.circle"), takesSeveral: false))
        return result
    }

    /// The values the filter menu offers for a property, with how many of the project's issues each finds.
    func filterValues(_ property: FilterProperty, projectId: String) -> [FilterValue] {
        let items = allItems.filter { $0.projectId == projectId && !$0.isEpic }
        let today = CalendarDay.today()
        var result: [FilterValue] = []
        let context = filterContext(projectId: projectId)
        func count(_ key: String, _ value: String) -> Int {
            guard let context else { return 0 }
            let filter = ProjectFilter(terms: [ProjectFilter.Term(key: key, values: [value])])
            return items.filter { filter.matches($0, context) }.count
        }
        func add(_ key: String, _ value: String, _ title: String, subtitle: String? = nil, icon: FilterIcon) {
            result.append(FilterValue(key: key, value: value, title: title, subtitle: subtitle, icon: icon, count: count(key, value)))
        }
        switch property.id {
        case "status":
            for option in statusOptions(projectId: projectId) {
                add("status", option.name, option.name, icon: .status(glyph(projectId: projectId, optionId: option.id)))
            }
        case "priority":
            for option in priorityOptions(projectId: projectId) {
                add("priority", option.name, option.name, icon: .priority(option.priorityLevel))
            }
            add("no", "priority", String(localized: .noFieldValue(field: property.title)), icon: .priority(.none))
        case "assignee":
            if let viewer { add("assignee", "@me", String(localized: .filterMe), subtitle: viewer.login, icon: .person(viewer.person)) }
            var seen = Set([viewer?.login])
            let people = (repos(projectId: projectId).flatMap(\.assignableUsers) + items.flatMap(\.assignees))
                .filter { seen.insert($0.login).inserted }
                .sorted { $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending }
            for person in people { add("assignee", person.login, person.login, subtitle: person.name, icon: .person(person)) }
            add("no", "assignee", String(localized: .filterNoAssignee), icon: .symbol("person.crop.circle.dashed"))
        case "label":
            var seen = Set<String>()
            let labels = (repos(projectId: projectId).flatMap(\.labels) + items.flatMap(\.labels))
                .filter { seen.insert($0.name.lowercased()).inserted }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for label in labels { add("label", label.name, label.name, icon: .label(label.color)) }
            add("no", "label", String(localized: .filterNoLabel), icon: .symbol("tag.slash"))
        case "milestone":
            for group in milestoneGroups(projectId: projectId).filter(\.isOpen) {
                add("milestone", group.title, group.title, subtitle: group.due?.shortLabel(today: today), icon: .milestone(mark(of: group, projectId: projectId, today: today)))
            }
            add("no", "milestone", String(localized: .noMilestone), icon: .milestone(.none))
        case "type":
            for type in Set(items.compactMap(\.issueType)).sorted() { add("type", type, type, icon: .symbol("circle.grid.2x2")) }
        case "parent-issue":
            var parents: [String: Item] = [:]
            for item in items { if let id = item.parentId, let parent = issue(contentId: id) { parents[id] = parent } }
            for parent in parents.values.sorted(by: { ($0.number ?? 0) < ($1.number ?? 0) }) {
                guard let number = parent.number, let repo = parent.repo else { continue }
                add("parent-issue", "\(repo)#\(number)", parent.title, subtitle: "#\(number)", icon: .symbol("arrow.turn.down.right"))
            }
            add("no", "parent-issue", String(localized: .filterNoParent), icon: .symbol("minus.circle"))
        case "repo":
            for repo in repos(projectId: projectId) { add("repo", repo.nameWithOwner, repo.shortName, subtitle: repo.nameWithOwner, icon: .symbol("book.closed")) }
        case "updated":
            add("updated", "@today", String(localized: .today), icon: .symbol("clock"))
            add("updated", ">@today-7d", String(localized: .filterLastWeek), icon: .symbol("clock"))
            add("updated", ">@today-30d", String(localized: .filterLastMonth), icon: .symbol("clock"))
            add("updated", "<@today-30d", String(localized: .filterLongerAgo), icon: .symbol("clock"))
        case "is":
            add("is", "open", String(localized: .filterOpen), icon: .symbol("circle"))
            add("is", "closed", String(localized: .filterClosed), icon: .symbol("checkmark.circle"))
        default:
            guard let field = context?.fieldsByKey[property.id] else { break }
            switch field.kind {
            case .iteration:
                // Current, next and previous move on with time; after them every other iteration by name, latest first.
                var relative = Set<String>()
                if let current = field.iteration(offset: 0, from: today) {
                    relative.insert(current.id)
                    add(field.filterKey, "@current", String(localized: .currentIteration), subtitle: current.title, icon: .iteration(current: true))
                }
                if let next = field.iteration(offset: 1, from: today), !next.completed {
                    relative.insert(next.id)
                    add(field.filterKey, "@next", String(localized: .nextIteration), subtitle: next.title, icon: .iteration(current: false))
                }
                if let previous = field.iteration(offset: -1, from: today) {
                    relative.insert(previous.id)
                    add(field.filterKey, "@previous", String(localized: .previousIteration), subtitle: previous.title, icon: .iteration(current: false))
                }
                for iteration in field.orderedIterations.reversed() where !relative.contains(iteration.id) {
                    add(field.filterKey, iteration.title, iteration.title, subtitle: iterationDays(iteration, today: today), icon: .iteration(current: false))
                }
                add("no", field.filterKey, String(localized: .noFieldValue(field: field.name)), icon: .symbol("minus.circle"))
            case .singleSelect:
                for option in field.options { add(field.filterKey, option.name, option.name, icon: .dot(option.color)) }
                add("no", field.filterKey, String(localized: .noFieldValue(field: field.name)), icon: .symbol("minus.circle"))
            case .date:
                add(field.filterKey, "<@today", String(localized: .filterOverdue), icon: .symbol("calendar"))
                add(field.filterKey, "@today", String(localized: .today), icon: .symbol("calendar"))
                add(field.filterKey, "@today..@today+7d", String(localized: .filterNextWeek), icon: .symbol("calendar"))
                add("has", field.filterKey, String(localized: .filterHasDate), icon: .symbol("calendar"))
                add("no", field.filterKey, String(localized: .noFieldValue(field: field.name)), icon: .symbol("calendar.badge.minus"))
            default:
                break
            }
        }
        return result
    }

    /// Every value of every property, for typing into the filter menu without picking a property first.
    func allFilterValues(projectId: String) -> [(property: FilterProperty, value: FilterValue)] {
        filterProperties(projectId: projectId).flatMap { property in
            filterValues(property, projectId: projectId).map { (property, $0) }
        }
    }

    /// The values of a term that a filter menu shows as picked.
    func pickedValues(_ term: ProjectFilter.Term) -> Set<String> {
        guard let key = term.key else { return [] }
        if key == "no" || key == "has" { return Set(term.values.map { "\(key):\($0.lowercased())" }) }
        return Set(term.values.map { "\(key):\($0)" })
    }

    // MARK: Chips

    /// How a term reads as a chip.
    func chip(for term: ProjectFilter.Term, projectId: String) -> FilterChipModel {
        guard let key = term.key else {
            return FilterChipModel(property: String(localized: .filterText), icon: .symbol("magnifyingglass"), comparison: String(localized: .filterContains),
                                   values: "“\(term.values.first ?? "")”", picksValues: false, negatable: false)
        }
        let properties = filterProperties(projectId: projectId)
        let several = term.values.count > 1
        let comparison = term.negated
            ? String(localized: several ? .filterIsNoneOf : .filterIsNot)
            : String(localized: several ? .filterIsAnyOf : .filterIs)
        switch key {
        case "is":
            let names = term.values.map { value -> String in
                switch value.lowercased() {
                case "open": String(localized: .filterOpen)
                case "closed": String(localized: .filterClosed)
                case "issue": String(localized: .filterIssues)
                case "pr": String(localized: .filterPullRequests)
                case "draft": String(localized: .filterDrafts)
                default: value
                }
            }
            return FilterChipModel(property: String(localized: .filterOpenOrClosed), icon: .symbol("circle.circle"),
                                   comparison: String(localized: term.negated ? .filterIsNot : .filterIs),
                                   values: names.joined(separator: ", "), picksValues: true, negatable: true)
        case "has", "no":
            let present = (key == "has") != term.negated
            let names = term.values.map { propertyTitle($0, properties: properties) }
            return FilterChipModel(property: names.joined(separator: ", "), icon: icon(ofKey: term.values.first ?? "", properties: properties),
                                   comparison: String(localized: present ? .filterIsNotEmpty : .filterIsEmpty),
                                   values: nil, picksValues: false, negatable: true)
        default:
            guard let property = properties.first(where: { $0.id == key || ($0.id == "assignee" && key == "assignees") || ($0.id == "label" && key == "labels") })
                ?? (key == "reason" ? FilterProperty(id: "reason", title: String(localized: .filterReason), icon: .symbol("checkmark.circle")) : nil),
                  filterContext(projectId: projectId).map({ term.isUnderstood($0) }) ?? false else {
                return FilterChipModel(property: term.raw, icon: .none, comparison: nil, values: nil, picksValues: false, negatable: false, isRaw: true)
            }
            let shown = term.values.prefix(3).map { valueTitle($0, key: key, projectId: projectId) }
            let more = term.values.count > 3 ? " +\(term.values.count - 3)" : ""
            return FilterChipModel(
                property: property.title, icon: property.icon, comparison: comparison,
                values: shown.joined(separator: ", ") + more, picksValues: key != "reason", negatable: true,
                namedWithValues: property.namedWithValues
            )
        }
    }

    private func propertyTitle(_ key: String, properties: [FilterProperty]) -> String {
        switch key.lowercased() {
        case "assignee", "assignees": String(localized: .assignee)
        case "label", "labels": String(localized: .filterLabel)
        case "milestone": String(localized: .milestone)
        case "parent-issue": String(localized: .filterParentIssue)
        case "type", "issue-type": String(localized: .filterIssueType)
        default: properties.first { $0.id == key.lowercased() }?.title ?? key
        }
    }

    private func icon(ofKey key: String, properties: [FilterProperty]) -> FilterIcon {
        switch key.lowercased() {
        case "assignee", "assignees": .symbol("person")
        case "label", "labels": .symbol("tag")
        default: properties.first { $0.id == key.lowercased() }?.icon ?? .none
        }
    }

    /// How a value reads: "me" for @me, "Current" for @current, "before today", "Oct 1", "#12".
    func valueTitle(_ value: String, key: String, projectId: String) -> String {
        let today = CalendarDay.today()
        var sign = ""
        var rest = value
        for prefix in [">=", "<=", ">", "<"] where rest.hasPrefix(prefix) {
            sign = prefix
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        if sign.isEmpty, let range = rest.range(of: "..") {
            let from = valueTitle(String(rest[..<range.lowerBound]), key: key, projectId: projectId)
            let to = valueTitle(String(rest[range.upperBound...]), key: key, projectId: projectId)
            return "\(from) – \(to)"
        }
        var name: String
        switch rest.lowercased() {
        case "@me": name = String(localized: .filterMe)
        case "@current": name = String(localized: .currentIteration)
        case "@next": name = String(localized: .nextIteration)
        case "@previous": name = String(localized: .previousIteration)
        case "*": name = "…"
        default:
            if let day = DateBound.day(rest, today: today) {
                name = day == today ? String(localized: .today) : day.date().formatted(.dateTime.day().month(.abbreviated))
            } else if key == "parent-issue", let hash = rest.lastIndex(of: "#") {
                name = String(rest[hash...])
            } else {
                name = rest
            }
        }
        switch sign {
        case "<": return String(localized: .filterBefore(value: name))
        case "<=": return String(localized: .filterOnOrBefore(value: name))
        case ">": return String(localized: .filterAfter(value: name))
        case ">=": return String(localized: .filterOnOrAfter(value: name))
        default: return name
        }
    }

    /// The values of a term after picking `value` in its menu: added, or taken away when it was there.
    func toggling(_ value: FilterValue, in filter: ProjectFilter, termIndex: Int?) -> ProjectFilter {
        if let index = termIndex, filter.terms.indices.contains(index) {
            let term = filter.terms[index]
            if term.values.contains(where: { $0.caseInsensitiveCompare(value.value) == .orderedSame }) {
                let remaining = term.values.filter { $0.caseInsensitiveCompare(value.value) != .orderedSame }
                return remaining.isEmpty ? filter.removing(index) : filter.replacing(index, with: term.changed { $0.values = remaining })
            }
            if term.key == value.key, ProjectFilter.takesSeveral(value.key) {
                return filter.replacing(index, with: term.changed { $0.values.append(value.value) })
            }
            return filter.replacing(index, with: ProjectFilter.Term(negated: term.negated, key: value.key, values: [value.value]))
        }
        return filter.adding(key: value.key, value: value.value)
    }

    /// The term of a filter that a property's values go into: the first that isn't turned around.
    func termIndex(for property: FilterProperty, in filter: ProjectFilter) -> Int? {
        filter.terms.firstIndex { term in
            term.key == property.id || (property.id == "assignee" && term.key == "assignees") || (property.id == "label" && term.key == "labels")
        }
    }
}

// MARK: - The iteration a view is about

/// The one iteration a view's filter asks for, such as `iteration:@current`: what the cycle header shows, and where
/// its arrows step from.
struct PinnedIteration: Equatable {
    var field: ProjectField
    var iteration: IterationSpan
    /// Iterations from the one under way: 0 for it, -1 for the one before.
    var offset: Int
    /// The term of the filter that names it.
    var termIndex: Int
    var previous: IterationSpan?
    var next: IterationSpan?
}

extension AppModel {
    /// The iteration a view's filter pins down: one value of an iteration field, not turned around, not a range.
    func pinnedIteration(of view: ProjectView) -> PinnedIteration? {
        guard let context = filterContext(projectId: view.projectId) else { return nil }
        for (index, term) in filter(of: view).terms.enumerated() where !term.negated && term.values.count == 1 {
            guard let key = term.key, let field = context.fieldsByKey[key], field.kind == .iteration else { continue }
            let value = term.values[0]
            guard !value.contains(".."), !value.hasPrefix("<"), !value.hasPrefix(">") else { continue }
            let ordered = field.orderedIterations
            guard let at = IterationBound.index(value, field: field, today: context.today), ordered.indices.contains(at) else { continue }
            let today = context.today
            let current = ordered.firstIndex { $0.contains(today) } ?? ordered.firstIndex { ($0.start ?? today) > today } ?? ordered.count
            return PinnedIteration(
                field: field, iteration: ordered[at], offset: at - current, termIndex: index,
                previous: at > 0 ? ordered[at - 1] : nil, next: at + 1 < ordered.count ? ordered[at + 1] : nil
            )
        }
        return nil
    }

    /// Changes the view's filter to the iteration before or after (`delta` -1 or 1).
    func stepIteration(of view: ProjectView, by delta: Int) {
        guard let pinned = pinnedIteration(of: view), let target = delta < 0 ? pinned.previous : pinned.next else { return }
        let filter = filter(of: view)
        let term = filter.terms[pinned.termIndex]
        let value = Self.iterationValue(after: term.values.first ?? "", offset: pinned.offset + delta, title: target.title)
        setFilter(filter.replacing(pinned.termIndex, with: term.changed { $0.values = [value] }), of: view)
    }

    /// Another iteration in a filter, said as the filter said the last one: relative to the one under way, so it keeps
    /// moving with the calendar (`@previous`, `@current`, `@next`, `@current+2`), or by its title.
    static func iterationValue(after value: String, offset: Int, title: String) -> String {
        value.hasPrefix("@") ? iterationToken(offset: offset) : title
    }

    /// An iteration in GitHub's words, counted from the one under way.
    static func iterationToken(offset: Int) -> String {
        switch offset {
        case 0: "@current"
        case 1: "@next"
        case -1: "@previous"
        default: offset > 0 ? "@current+\(offset)" : "@current\(offset)"
        }
    }

    /// "Oct 12 – 18".
    func iterationRange(_ iteration: IterationSpan) -> String? {
        guard let start = iteration.start, let end = iteration.end else { return nil }
        let first = start.date().formatted(.dateTime.day().month(.abbreviated))
        let last = start.month == end.month ? end.date().formatted(.dateTime.day()) : end.date().formatted(.dateTime.day().month(.abbreviated))
        return "\(first) – \(last)"
    }

    /// "4 days left", "Starts in 3 days" or "Ended", from today.
    func iterationTiming(_ iteration: IterationSpan, today: CalendarDay = .today()) -> String? {
        guard let start = iteration.start, let end = iteration.end else { return nil }
        if today > end { return String(localized: .iterationEnded) }
        if today < start { return String(localized: .iterationStartsIn(days: start.days(from: today))) }
        return String(localized: .iterationDaysLeft(days: end.days(from: today) + 1))
    }
}
