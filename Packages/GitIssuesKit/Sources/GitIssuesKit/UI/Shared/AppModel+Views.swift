import SwiftUI

/// A column of a board by a field other than Status: the field and the value its cards share (nil: none).
struct ColumnValue: Equatable, Hashable {
    var fieldId: String
    var value: FieldValue?
}

/// What the issues of a view's group share: a value of the field the view groups by.
enum GroupKey: Equatable, Hashable {
    /// An option of a single-select field, or an iteration.
    case field(fieldId: String, value: FieldValue?)
    case priority(optionId: String?)
    case assignee(login: String?)
    case milestone(title: String?)
    case parent(contentId: String?)
    case repository(id: String?)
    case issueType(String?)
}

/// How you chose to see a view where it differs from the view on GitHub. Nil keeps the view's own.
struct ViewDisplay: Codable, Equatable {
    var layout: ViewMode?
    var columnFieldId: String?
    var groupFieldId: String?
    var sort: [ViewSort]?
    var visibleFieldIds: [String]?
    /// The board's columns you hid, by their ids. Only here: hiding a column changes nothing on GitHub.
    var hiddenColumnIds: [String]?

    var isEmpty: Bool { self == ViewDisplay() }
}

/// What a new issue starts with in a view: the values its filter asks for, and those of the column or group it was
/// started in.
struct NewIssuePreset: Equatable {
    var statusId: String?
    var priorityId: String?
    var labels: [String] = []
    var assignees: [String] = []
    var milestoneTitle: String?
    var parentContentId: String?
    /// Started in a group by repository: that repository.
    var repoId: String?
    var fieldValues: [String: FieldValue] = [:]
}

/// One of a project's own fields as a card or a row shows it: an iteration, an option of a field like "Workstream",
/// a text or a number.
struct FieldChip: Equatable, Hashable {
    enum Icon: Equatable, Hashable {
        case iteration
        case option(color: String)
        case text
        case date
    }
    var fieldId: String
    var text: String
    var icon: Icon
}

extension AppModel {
    static func decoded<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func store<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    // MARK: Looking up

    func views(projectId: String?) -> [ProjectView] {
        guard let projectId else { return [] }
        return views.filter { $0.projectId == projectId }
    }

    func view(id: String?) -> ProjectView? {
        guard let id else { return nil }
        return views.first { $0.id == id }
    }

    func fields(projectId: String?) -> [ProjectField] {
        guard let projectId else { return [] }
        return fields.filter { $0.projectId == projectId }
    }

    func field(id: String?) -> ProjectField? {
        guard let id else { return nil }
        return fields.first { $0.id == id }
    }

    func currentStatusFieldId(projectId: String?) -> String? {
        projects.first { $0.id == projectId }?.statusFieldId
    }

    /// The view open in a project: the one opened last, else the first tab.
    func currentView(projectId: String?) -> ProjectView? {
        let list = views(projectId: projectId)
        guard let projectId, !list.isEmpty else { return nil }
        return list.first { $0.id == selectedViewIds[projectId] } ?? list.first
    }

    /// The view on screen: the one open in the project shown, but not on its milestones and roadmap.
    var currentView: ProjectView? {
        guard case .project(let id) = scope else { return nil }
        return currentView(projectId: id)
    }

    /// Whether the view on screen is a list grouped by milestone, whose rows then don't repeat their milestone.
    var groupsByMilestone: Bool {
        guard let view = currentView, layout(of: view) == .list else { return false }
        return groupField(of: view)?.kind == .milestone
    }

    /// Whether the view open in a project asks for one milestone, which its rows then don't repeat, as a milestone's
    /// page doesn't.
    func viewPinsMilestone(projectId: String?) -> Bool {
        guard let view = currentView(projectId: projectId) else { return false }
        return filter(of: view).terms.contains { !$0.negated && $0.key == "milestone" && $0.values.count == 1 }
    }

    /// The project a view belongs to.
    func project(of view: ProjectView) -> Project? {
        projects.first { $0.id == view.projectId }
    }

    /// Whether you may change the views of a project.
    func canEditViews(projectId: String?) -> Bool {
        projects.first { $0.id == projectId }?.viewerCanUpdate == true
    }

    // MARK: Opening

    /// Opens a view in its project; on the Mac, the project too.
    func show(_ view: ProjectView) {
        let changed = selectedViewIds[view.projectId] != view.id
        selectedViewIds[view.projectId] = view.id
        #if os(macOS)
        if scope != .project(view.projectId) {
            select(.project(view.projectId))
            return
        }
        #endif
        followLayout(of: view)
        guard changed else { return }
        closeDetail()
        clearSelection()
        rebuild()
        recordNavigation()
        requestDraftMatches(view)
    }

    /// The next or previous tab of the project on screen.
    func showView(by delta: Int) {
        guard let current = currentView else { return }
        let list = views(projectId: current.projectId)
        guard let index = list.firstIndex(of: current), list.count > 1 else { return }
        show(list[(index + delta + list.count) % list.count])
    }

    /// Board or list as the view shows, without that counting as a choice of yours.
    func followLayout(of view: ProjectView) {
        let mode = layout(of: view)
        guard viewMode != mode else { return }
        isFollowingView = true
        withAnimation(Theme.spring) { viewMode = mode }
        isFollowingView = false
    }

    /// After the scope changed: board or list as the view now on screen has it.
    func followCurrentView() {
        if let view = currentView { followLayout(of: view) }
    }

    // MARK: Display

    func display(of view: ProjectView) -> ViewDisplay {
        viewDisplays[view.id] ?? ViewDisplay()
    }

    /// Board or list: yours, else the view's. A table or roadmap on GitHub is a list here.
    func layout(of view: ProjectView) -> ViewMode {
        display(of: view).layout ?? (view.layout == .board ? .board : .list)
    }

    /// The field a board has its columns by: a single select or an iteration, Status unless said otherwise.
    func columnField(of view: ProjectView) -> ProjectField? {
        let wanted = field(id: display(of: view).columnFieldId ?? view.columnFieldId)
        if let wanted, wanted.kind == .singleSelect || wanted.kind == .iteration { return wanted }
        return field(id: currentStatusFieldId(projectId: view.projectId))
    }

    /// The field a list groups by. Lists without one on GitHub are grouped by status, as Linear's are.
    func groupField(of view: ProjectView) -> ProjectField? {
        let wanted = field(id: display(of: view).groupFieldId ?? view.groupByFieldId)
        if let wanted, Self.groupable(wanted.kind) { return wanted }
        return field(id: currentStatusFieldId(projectId: view.projectId))
    }

    static func groupable(_ kind: ProjectFieldKind) -> Bool {
        switch kind {
        case .singleSelect, .iteration, .assignees, .milestone, .parentIssue, .repository, .issueType: true
        default: false
        }
    }

    func sort(of view: ProjectView) -> [ViewSort] {
        display(of: view).sort ?? view.sortBy
    }

    func shownFieldIds(of view: ProjectView) -> [String] {
        display(of: view).visibleFieldIds ?? view.visibleFieldIds
    }

    /// The project's own fields cards and rows show as chips in this view: iterations, options of fields like
    /// "Workstream", texts and numbers. Status, Priority, labels, people, the due date and the milestone have places
    /// of their own on every card.
    func chipFields(of view: ProjectView) -> [ProjectField] {
        let project = project(of: view)
        let own: Set<String?> = [project?.statusFieldId, project?.priorityFieldId, project?.dueFieldId]
        return shownFieldIds(of: view).compactMap { field(id: $0) }.filter { $0.kind.isProjectValue && !own.contains($0.id) }
    }

    /// Fields that can be shown as chips, for the Display options.
    func chipCandidates(projectId: String) -> [ProjectField] {
        let project = projects.first { $0.id == projectId }
        let own: Set<String?> = [project?.statusFieldId, project?.priorityFieldId, project?.dueFieldId]
        return fields(projectId: projectId).filter { $0.kind.isProjectValue && !own.contains($0.id) }
    }

    func changeDisplay(of view: ProjectView, _ change: (inout ViewDisplay) -> Void) {
        var display = display(of: view)
        change(&display)
        // What is the same as the view's own isn't a choice of yours. A roadmap's own is its timeline, so a board or a
        // list chosen for it is.
        if view.layout != .roadmap, display.layout == (view.layout == .board ? .board : .list) { display.layout = nil }
        if display.columnFieldId == view.columnFieldId { display.columnFieldId = nil }
        if display.groupFieldId == view.groupByFieldId { display.groupFieldId = nil }
        if display.sort == view.sortBy { display.sort = nil }
        if display.visibleFieldIds == view.visibleFieldIds { display.visibleFieldIds = nil }
        if display.hiddenColumnIds?.isEmpty == true { display.hiddenColumnIds = nil }
        viewDisplays[view.id] = display.isEmpty ? nil : display
        rebuild()
    }

    func setLayout(_ mode: ViewMode, of view: ProjectView) {
        changeDisplay(of: view) { $0.layout = mode }
    }

    /// Board or list for a project on screen: for its open view, as your own choice, or as before where the project
    /// has no views. Without a project, such as for a milestone, for what is on screen.
    func showLayout(_ mode: ViewMode, projectId: String?) {
        if let projectId, let view = currentView(projectId: projectId) {
            setLayout(mode, of: view)
            followLayout(of: view)
        } else {
            withAnimation(Theme.spring) { viewMode = mode }
        }
    }

    func setColumnField(_ fieldId: String?, of view: ProjectView) {
        changeDisplay(of: view) { $0.columnFieldId = fieldId }
    }

    func setGroupField(_ fieldId: String?, of view: ProjectView) {
        changeDisplay(of: view) { $0.groupFieldId = fieldId }
    }

    func setSort(_ sort: [ViewSort], of view: ProjectView) {
        changeDisplay(of: view) { $0.sort = sort }
    }

    func toggleChip(_ fieldId: String, of view: ProjectView) {
        var shown = shownFieldIds(of: view)
        if let index = shown.firstIndex(of: fieldId) { shown.remove(at: index) } else { shown.append(fieldId) }
        changeDisplay(of: view) { $0.visibleFieldIds = shown }
    }

    /// The columns of a view's board you hid.
    func hiddenColumnIds(of view: ProjectView) -> Set<String> {
        Set(display(of: view).hiddenColumnIds ?? [])
    }

    /// Hides a column of a view's board, or shows it again. Its cards leave the board with it, and picks or the
    /// keyboard focus on them go.
    func setColumn(_ columnId: String, hidden: Bool, of view: ProjectView) {
        var ids = display(of: view).hiddenColumnIds ?? []
        ids.removeAll { $0 == columnId }
        if hidden { ids.append(columnId) }
        withAnimation(Theme.spring) {
            changeDisplay(of: view) { $0.hiddenColumnIds = ids }
        }
        guard hidden else { return }
        // The focus moves on by itself (`rebuild`); the cards stay in the list, so their picks are let go here.
        let gone = Set(columns(projectId: view.projectId).filter { $0.id == columnId }.flatMap(\.nesting.members).map(\.id))
        selectedIds.subtract(gone)
        if let hovered = hoveredItemId, gone.contains(hovered) { hoveredItemId = nil }
    }

    /// The columns a board shows: a view's, without those you hid. A milestone's board shows every column.
    func shownColumns(for scope: Scope) -> [BoardColumn] {
        let all = columns(for: scope)
        guard case .project(let projectId) = scope, let view = currentView(projectId: projectId) else { return all }
        let hidden = hiddenColumnIds(of: view)
        return hidden.isEmpty ? all : all.filter { !hidden.contains($0.id) }
    }

    /// The columns you hid on the board of a project's open view, in the board's order, with their cards.
    func hiddenColumns(projectId: String) -> [BoardColumn] {
        guard let view = currentView(projectId: projectId) else { return [] }
        let hidden = hiddenColumnIds(of: view)
        guard !hidden.isEmpty else { return [] }
        return columns(projectId: projectId).filter { hidden.contains($0.id) }
    }

    func resetDisplay(of view: ProjectView) {
        viewDisplays[view.id] = nil
        followLayout(of: view)
        rebuild()
    }

    /// Whether you see the view differently from how it is on GitHub.
    func displayDiffers(_ view: ProjectView) -> Bool {
        !display(of: view).isEmpty
    }

    /// Whether some of your display choices can be saved to the view: GitHub takes a view's layout and fields, but
    /// its columns, grouping and order only when it is created.
    func displayCanBeSaved(_ view: ProjectView) -> Bool {
        let display = display(of: view)
        return canEditViews(projectId: view.projectId) && (display.layout != nil || display.visibleFieldIds != nil)
    }

    /// Whether some of your display choices stay yours, because GitHub can't change them in an existing view.
    func displayStaysYours(_ view: ProjectView) -> Bool {
        let display = display(of: view)
        return display.columnFieldId != nil || display.groupFieldId != nil || display.sort != nil || display.hiddenColumnIds != nil
    }

    // MARK: Filter

    func filterText(of view: ProjectView) -> String {
        draftFilters[view.id] ?? view.filter
    }

    func filter(of view: ProjectView) -> ProjectFilter {
        ProjectFilter(filterText(of: view))
    }

    /// Whether the filter was changed here and not saved yet.
    func filterChanged(_ view: ProjectView) -> Bool {
        guard let draft = draftFilters[view.id] else { return false }
        return draft != view.filter
    }

    /// Changes the filter for you, until it is saved or reset.
    func setFilter(_ filter: ProjectFilter, of view: ProjectView) {
        let text = filter.text
        draftFilters[view.id] = text == view.filter ? nil : text
        rebuild()
        requestDraftMatches(view)
    }

    func resetFilter(of view: ProjectView) {
        draftFilters[view.id] = nil
        rebuild()
    }

    func filterContext(projectId: String) -> FilterContext? {
        if let cached = filterContexts[projectId] { return cached }
        guard let project = projects.first(where: { $0.id == projectId }) else { return nil }
        let context = FilterContext(
            project: project, fields: fields(projectId: projectId), options: options.filter { $0.projectId == projectId },
            viewerLogin: viewer?.login,
            parentReference: { [weak self] item in
                guard let number = item.parentNumber else { return nil }
                let repo = item.parentId.flatMap { self?.issue(contentId: $0)?.repo } ?? item.repo ?? ""
                return "\(repo)#\(number)"
            }
        )
        filterContexts[projectId] = context
        return context
    }

    /// Asks GitHub which items an unsaved filter matches, when it has parts only GitHub understands.
    func requestDraftMatches(_ view: ProjectView) {
        let text = filterText(of: view)
        guard text != view.filter, let context = filterContext(projectId: view.projectId),
              ProjectFilter(text).needsServer(context), draftMatches[view.id]?.filter != text else { return }
        let engine = self.engine
        let viewId = view.id
        let projectId = view.projectId
        Task {
            // Typing a search goes on for a moment; ask once it rests.
            try? await Task.sleep(for: .milliseconds(400))
            guard self.view(id: viewId).map({ self.filterText(of: $0) }) == text else { return }
            guard let ids = try? await engine.matchingItemIds(projectId: projectId, filter: text) else { return }
            draftMatches[viewId] = (text, Set(ids))
            rebuild()
        }
    }

    /// The items of a project a view shows, in its order. Epics stay on the roadmap, unless the filter asks for them.
    func items(of view: ProjectView) -> [Item] {
        sorted(matchingItems(of: view), by: sort(of: view))
    }

    /// The items a view shows, in no particular order: enough to count them.
    func matchingItems(of view: ProjectView) -> [Item] {
        let all = allItems.filter { $0.projectId == view.projectId }
        guard let context = filterContext(projectId: view.projectId) else { return all }
        let text = filterText(of: view)
        let filter = ProjectFilter(text)
        var shown = all.filter { filter.matches($0, context) }
        if filter.needsServer(context) {
            let known: Set<String>? = if text == view.filter, view.matchesFilter == text, let matches = view.matches {
                Set(matches)
            } else if let draft = draftMatches[view.id], draft.filter == text {
                draft.ids
            } else {
                nil
            }
            // Issues made here since GitHub was asked are kept until it is asked again.
            if let known { shown = shown.filter { known.contains($0.id) || $0.isLocalOnly } }
        }
        if !Self.asksForEpics(filter) { shown = shown.filter { !$0.isEpic } }
        return shown
    }

    /// Whether a filter asks for epics by name: the label or the issue type.
    static func asksForEpics(_ filter: ProjectFilter) -> Bool {
        filter.terms.contains { term in
            guard !term.negated else { return false }
            switch term.key {
            case "label", "labels": return term.values.contains { Item.isEpicLabel($0) }
            case "type": return term.values.contains { $0.caseInsensitiveCompare("epic") == .orderedSame }
            default: return false
            }
        }
    }

    /// The view open in a project when its filter leaves out every issue the project has: its empty list then says so,
    /// instead of that the project has none.
    func viewHidingEverything(projectId: String) -> ProjectView? {
        guard let view = currentView(projectId: projectId), items(of: view).isEmpty,
              allItems.contains(where: { $0.projectId == projectId && !$0.isEpic }) else { return nil }
        return view
    }

    /// Whether an item is in a view, for saying so when a new issue isn't.
    func view(_ view: ProjectView, shows item: Item) -> Bool {
        guard let context = filterContext(projectId: view.projectId) else { return true }
        return filter(of: view).matches(item, context)
    }

    // MARK: Order

    func sorted(_ items: [Item], by sort: [ViewSort]) -> [Item] {
        let keys = sort.compactMap { step in field(id: step.fieldId).map { (field: $0, descending: step.descending) } }
        guard !keys.isEmpty else { return items }
        // Each card's values once, not again for every comparison.
        let values = items.map { item in keys.map { sortValue(item, $0.field) } }
        return items.enumerated().sorted { a, b in
            for (index, key) in keys.enumerated() {
                let first = values[a.offset][index]
                let second = values[b.offset][index]
                switch (first, second) {
                case (nil, nil): continue
                // Without a value last, whichever way the order goes, as GitHub does.
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?):
                    if x == y { continue }
                    return key.descending ? y < x : x < y
                }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    enum SortValue: Comparable {
        case number(Double)
        case text(String)

        static func < (a: SortValue, b: SortValue) -> Bool {
            switch (a, b) {
            case (.number(let x), .number(let y)): x < y
            case (.text(let x), .text(let y)): x.localizedStandardCompare(y) == .orderedAscending
            case (.number, .text): true
            case (.text, .number): false
            }
        }
    }

    /// What an item is ordered by for a field.
    func sortValue(_ item: Item, _ field: ProjectField) -> SortValue? {
        let context = filterContext(projectId: field.projectId)
        switch field.kind {
        case .title: return .text(item.title)
        case .assignees: return item.assignees.first.map { .text($0.login) }
        case .labels: return item.labels.first.map { .text($0.name) }
        case .milestone:
            guard let title = item.milestoneTitle else { return nil }
            if let due = milestoneGroup(of: item)?.due { return .number(due.date().timeIntervalSince1970) }
            return .text(title)
        case .repository: return item.repo.map { .text($0) }
        case .parentIssue: return item.parentNumber.map { .number(Double($0)) }
        case .issueType: return item.issueType.map { .text($0) }
        case .subIssuesProgress:
            guard item.subTotal > 0 else { return nil }
            return .number(Double(item.subCompleted) / Double(item.subTotal))
        case .singleSelect:
            guard let optionId = context?.value(of: field, in: item)?.optionId else { return nil }
            if field.id == currentStatusFieldId(projectId: field.projectId),
               let index = statusOptions(projectId: field.projectId).firstIndex(where: { $0.id == optionId }) {
                return .number(Double(index))
            }
            if field.id == projects.first(where: { $0.id == field.projectId })?.priorityFieldId,
               let index = priorityOptions(projectId: field.projectId).firstIndex(where: { $0.id == optionId }) {
                return .number(Double(index))
            }
            return field.options.firstIndex { $0.id == optionId }.map { .number(Double($0)) }
        case .iteration:
            guard let id = context?.value(of: field, in: item)?.iterationId else { return nil }
            return field.iterations.first { $0.id == id }.map { .text($0.startDate) }
        case .date: return context?.value(of: field, in: item)?.date.map { .text($0) }
        case .number: return context?.value(of: field, in: item)?.number.map { .number($0) }
        case .text: return context?.value(of: field, in: item)?.text.map { .text($0) }
        case .created: return item.createdAt.map { .number($0.timeIntervalSince1970) }
        case .updated: return [item.updatedAt, item.remoteUpdatedAt.flatMap(ProjectFilter.Term.date)].compactMap { $0 }.max().map { .number($0.timeIntervalSince1970) }
        case .closed: return item.closedAt.map { .number($0.timeIntervalSince1970) }
        case .linkedPullRequests, .reviewers, .other: return nil
        }
    }

    /// Fields a view can be ordered by, for the Display options.
    func sortCandidates(projectId: String) -> [ProjectField] {
        fields(projectId: projectId).filter { field in
            switch field.kind {
            case .title, .assignees, .milestone, .singleSelect, .iteration, .date, .number, .text, .created, .updated: true
            default: false
            }
        }
    }

    // MARK: Columns and groups

    /// The columns by status a project's list is made of: the board's, unless the view's board has its columns by
    /// another field.
    func listColumns(projectId: String) -> [BoardColumn] {
        guard let view = currentView(projectId: projectId), let field = columnField(of: view),
              field.id != currentStatusFieldId(projectId: projectId) else { return columns(projectId: projectId) }
        return statusColumns(projectId: projectId, items: items(in: .project(projectId)))
    }

    func arranged(_ items: [Item]) -> (items: [Item], nesting: Nesting) {
        Nesting.arrange(items, folded: foldedParents, epic: { self.epic(of: $0) }, foldedEpics: foldedEpics)
    }

    /// A board's columns by a single select or an iteration: one per option or iteration, and one for cards
    /// without a value when there are such. Iterations that are over show only while cards are in them.
    func valueColumns(_ items: [Item], field: ProjectField, view: ProjectView) -> [BoardColumn] {
        let context = filterContext(projectId: view.projectId)
        var result: [BoardColumn] = []
        func value(_ item: Item) -> FieldValue? { context?.value(of: field, in: item) }
        let empty = items.filter { (value($0)?.isEmpty ?? true) }
        if !empty.isEmpty {
            let (shown, nesting) = arranged(empty)
            result.append(BoardColumn(
                id: "\(field.id)/none", option: nil, glyph: .none, items: shown, nesting: nesting,
                value: ColumnValue(fieldId: field.id, value: nil), label: String(localized: .noFieldValue(field: field.name))
            ))
        }
        switch field.kind {
        case .iteration:
            let today = CalendarDay.today()
            for iteration in field.orderedIterations {
                let members = items.filter { value($0)?.iterationId == iteration.id }
                if iteration.completed, members.isEmpty { continue }
                let (shown, nesting) = arranged(members)
                result.append(BoardColumn(
                    id: "\(field.id)/\(iteration.id)", option: nil, glyph: .none, items: shown, nesting: nesting,
                    value: ColumnValue(fieldId: field.id, value: FieldValue(iterationId: iteration.id)),
                    label: iteration.title, detail: iterationDays(iteration, today: today)
                ))
            }
        default:
            for option in field.options {
                let (shown, nesting) = arranged(items.filter { value($0)?.optionId == option.id })
                result.append(BoardColumn(
                    id: "\(field.id)/\(option.id)", option: nil, glyph: .none, items: shown, nesting: nesting,
                    value: ColumnValue(fieldId: field.id, value: FieldValue(optionId: option.id)),
                    label: option.name, dot: option.color
                ))
            }
        }
        return result
    }

    /// "Oct 12 – 18", or "Current" for the iteration under way.
    func iterationDays(_ iteration: IterationSpan, today: CalendarDay = .today()) -> String? {
        if iteration.contains(today) { return String(localized: .currentIteration) }
        guard let start = iteration.start, let end = iteration.end else { return nil }
        let first = start.date().formatted(.dateTime.day().month(.abbreviated))
        let last = start.month == end.month ? end.date().formatted(.dateTime.day()) : end.date().formatted(.dateTime.day().month(.abbreviated))
        return "\(first) – \(last)"
    }

    /// A view's list grouped by its field, or nil when it groups by status, which the project's list does already.
    func groupedSections(of view: ProjectView) -> [ListSection]? {
        guard let field = groupField(of: view), field.id != currentStatusFieldId(projectId: view.projectId) else { return nil }
        let items = items(of: view)
        let context = filterContext(projectId: view.projectId)
        var groups: [(key: GroupKey, title: String, icon: SectionIcon, detail: String?, members: [Item])] = []
        var empty: [Item] = []
        let noneTitle = String(localized: .noFieldValue(field: field.name))
        let priorityFieldId = projects.first { $0.id == view.projectId }?.priorityFieldId

        switch field.kind {
        case .singleSelect where field.id == priorityFieldId:
            for option in priorityOptions(projectId: view.projectId) {
                let members = items.filter { $0.priorityId == option.id }
                if !members.isEmpty { groups.append((.priority(optionId: option.id), option.name, .priority(option.priorityLevel), nil, members)) }
            }
            empty = items.filter { $0.priorityId == nil }
            if !empty.isEmpty { groups.append((.priority(optionId: nil), noneTitle, .plain, nil, empty)) }
            empty = []
        case .singleSelect:
            for option in field.options {
                let members = items.filter { context?.value(of: field, in: $0)?.optionId == option.id }
                if !members.isEmpty {
                    groups.append((.field(fieldId: field.id, value: FieldValue(optionId: option.id)), option.name, .dot(option.color), nil, members))
                }
            }
            empty = items.filter { context?.value(of: field, in: $0)?.optionId == nil }
        case .iteration:
            let today = CalendarDay.today()
            for iteration in field.orderedIterations {
                let members = items.filter { context?.value(of: field, in: $0)?.iterationId == iteration.id }
                if !members.isEmpty {
                    groups.append((
                        .field(fieldId: field.id, value: FieldValue(iterationId: iteration.id)), iteration.title,
                        .iteration(current: iteration.contains(today)), iterationDays(iteration, today: today), members
                    ))
                }
            }
            empty = items.filter { context?.value(of: field, in: $0)?.iterationId == nil }
        case .assignees:
            var people: [String: Person] = [:]
            for item in items { for person in item.assignees { people[person.login] = person } }
            // You first, then everyone else by name.
            let logins = people.keys.sorted { a, b in
                if a == viewer?.login { return true }
                if b == viewer?.login { return false }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            for login in logins {
                let members = items.filter { $0.assignees.contains { $0.login == login } }
                groups.append((.assignee(login: login), login, .person(people[login]!), nil, members))
            }
            empty = items.filter { $0.assignees.isEmpty }
        case .milestone:
            let today = CalendarDay.today()
            let titles = Set(items.compactMap(\.milestoneTitle))
            let ordered = titles.sorted { a, b in
                let da = milestoneGroup(projectId: view.projectId, title: a)?.due
                let db = milestoneGroup(projectId: view.projectId, title: b)?.due
                switch (da, db) {
                case (let x?, let y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.localizedStandardCompare(b) == .orderedAscending
                }
            }
            for title in ordered {
                let group = milestoneGroup(projectId: view.projectId, title: title)
                let members = items.filter { $0.milestoneTitle == title }
                let icon: SectionIcon = group.map { .milestone(mark(of: $0, projectId: view.projectId, today: today)) } ?? .milestone(.upcoming)
                groups.append((.milestone(title: title), title, icon, group?.due.map { $0.shortLabel(today: today) }, members))
            }
            empty = items.filter { $0.milestoneTitle == nil }
        case .parentIssue:
            var parents: [String: (number: Int?, title: String)] = [:]
            for item in items {
                guard let id = item.parentId else { continue }
                parents[id] = (item.parentNumber, item.parentTitle ?? "")
            }
            let ordered = parents.keys.sorted { (parents[$0]?.number ?? 0) < (parents[$1]?.number ?? 0) }
            for id in ordered {
                let members = items.filter { $0.parentId == id }
                let parent = issue(contentId: id)
                let total = parent?.subTotal ?? members.count
                let done = parent?.subCompleted ?? members.filter(\.isClosed).count
                let title = parents[id].map { entry in entry.number.map { "\($0) · " }.map { "#" + $0 + entry.title } ?? entry.title } ?? ""
                groups.append((
                    .parent(contentId: id), title, .progress(done: done, total: total),
                    total > 0 ? "\(done)/\(total)" : nil, members
                ))
            }
            empty = items.filter { $0.parentId == nil }
        case .repository:
            let repos = Set(items.compactMap(\.repoId))
            for repoId in repos.sorted(by: { (repository(id: $0)?.shortName ?? $0) < (repository(id: $1)?.shortName ?? $1) }) {
                let members = items.filter { $0.repoId == repoId }
                groups.append((.repository(id: repoId), members.first?.repoShortName ?? repoId, .repository, nil, members))
            }
            empty = items.filter { $0.repoId == nil }
        case .issueType:
            for type in Set(items.compactMap(\.issueType)).sorted() {
                groups.append((.issueType(type), type, .plain, nil, items.filter { $0.issueType == type }))
            }
            empty = items.filter { $0.issueType == nil }
        default:
            return nil
        }
        if !empty.isEmpty {
            let key: GroupKey = switch field.kind {
            case .assignees: .assignee(login: nil)
            case .milestone: .milestone(title: nil)
            case .parentIssue: .parent(contentId: nil)
            case .repository: .repository(id: nil)
            case .issueType: .issueType(nil)
            default: .field(fieldId: field.id, value: nil)
            }
            groups.append((key, noneTitle, .plain, nil, empty))
        }
        let style = Self.groupStyle(of: field)
        return groups.map { group in
            // Grouped by parent, the parent is the group; its sub-issues don't hang under it again.
            let (shown, nesting) = field.kind == .parentIssue
                ? (group.members, Nesting.arrange(group.members, folded: []).nesting)
                : arranged(group.members)
            // A group with progress counts what the view shows of it, in its bar and in its header's "4/6".
            let progress = style == .plain ? nil : progress(of: group.members)
            let icon: SectionIcon = if case .progress = group.icon, let progress { .progress(done: progress.done, total: progress.total) } else { group.icon }
            return ListSection(
                id: Self.sectionId(group.key), title: group.title, glyph: .none, option: nil, kind: .group(group.key),
                detail: field.kind == .parentIssue ? nil : group.detail, groupIcon: icon,
                items: shown, nesting: nesting, style: style, progress: progress
            )
        }
    }

    /// Groups by something that gets finished show their progress; groups by person, each one's load.
    static func groupStyle(of field: ProjectField) -> GroupStyle {
        switch field.kind {
        case .parentIssue, .milestone, .iteration: .progress
        case .assignees: .people
        default: .plain
        }
    }

    /// How far issues are, by the kind of their status: done (or closed), under way, or not started.
    func progress(of items: [Item]) -> GroupProgress {
        var done = 0
        var started = 0
        for item in items {
            if isDone(item) {
                done += 1
            } else if statusOption(of: item)?.statusCategory == .started {
                started += 1
            }
        }
        return GroupProgress(done: done, started: started, total: items.count)
    }

    /// Whether a group starts folded: a group of something that gets finished, with nothing under way in it, so a
    /// view of work packages opens as their overview while the work in progress stays in sight.
    func foldsByDefault(_ section: ListSection) -> Bool {
        Self.foldsByDefault(section)
    }

    static func foldsByDefault(_ section: ListSection) -> Bool {
        section.style == .progress && (section.progress?.started ?? 0) == 0 && section.count > 0
    }

    /// The same in every language and on every device, so folded groups and the order of groups are kept by it.
    static func sectionId(_ key: GroupKey) -> String {
        switch key {
        case .field(let fieldId, let value): "group/\(fieldId)/\(value?.optionId ?? value?.iterationId ?? "none")"
        case .priority(let id): "group/priority/\(id ?? "none")"
        case .assignee(let login): "group/assignee/\(login ?? "none")"
        case .milestone(let title): "group/milestone/\(title ?? "none")"
        case .parent(let id): "group/parent/\(id ?? "none")"
        case .repository(let id): "group/repository/\(id ?? "none")"
        case .issueType(let type): "group/type/\(type ?? "none")"
        }
    }

    // MARK: Chips

    /// The chips a card or row shows for the project's own fields, in the view's order: only in the project's view,
    /// not in lists that mix projects or show a milestone.
    func fieldChips(of item: Item, in scope: Scope?) -> [FieldChip] {
        guard let projectId = item.projectId, scope == .project(projectId), let view = currentView(projectId: projectId),
              let context = filterContext(projectId: projectId) else { return [] }
        // The field the columns or groups are by goes without saying.
        let implied = layout(of: view) == .board ? columnField(of: view)?.id : groupField(of: view)?.id
        return chipFields(of: view).filter { $0.id != implied }.compactMap { field in
            guard let value = context.value(of: field, in: item) else { return nil }
            switch field.kind {
            case .iteration:
                guard let iteration = field.iterations.first(where: { $0.id == value.iterationId }) else { return nil }
                return FieldChip(fieldId: field.id, text: iteration.title, icon: .iteration)
            case .singleSelect:
                guard let option = field.options.first(where: { $0.id == value.optionId }) else { return nil }
                return FieldChip(fieldId: field.id, text: option.name, icon: .option(color: option.color))
            case .text:
                return value.text.map { FieldChip(fieldId: field.id, text: $0, icon: .text) }
            case .number:
                return value.number.map { FieldChip(fieldId: field.id, text: "\(field.name) \($0.formatted())", icon: .text) }
            case .date:
                return value.date.flatMap(CalendarDay.init).map {
                    FieldChip(fieldId: field.id, text: $0.date().formatted(.dateTime.day().month(.abbreviated)), icon: .date)
                }
            default:
                return nil
            }
        }
    }

    /// A field's chip as VoiceOver reads it: the field's name, then its value.
    func spokenChip(_ chip: FieldChip) -> String {
        guard let name = field(id: chip.fieldId)?.name, !chip.text.hasPrefix(name) else { return chip.text }
        return String(localized: .fieldValueSpoken(field: name, value: chip.text))
    }

    // MARK: Changing values

    /// Gives issues an option of a single-select field or an iteration, or clears it.
    func setValue(_ value: FieldValue?, of field: ProjectField, for items: [Item]) {
        perform(items.flatMap { valueMutations($0, field: field, value: value) })
    }

    func valueMutations(_ item: Item, field: ProjectField, value: FieldValue?) -> [Mutation] {
        guard let projectId = item.projectId, projectId == field.projectId else { return [] }
        if field.id == currentStatusFieldId(projectId: projectId) {
            return statusMutations(item, statusOptions(projectId: projectId).first { $0.id == value?.optionId })
        }
        if field.id == projects.first(where: { $0.id == projectId })?.priorityFieldId {
            guard item.priorityId != value?.optionId, let fieldId = project(of: item)?.priorityFieldId else { return [] }
            return [.setField(.init(itemId: item.id, projectId: projectId, fieldId: fieldId, kind: .priority, optionId: value?.optionId, base: item.priorityId))]
        }
        let current = item.fieldValues[field.id]
        let next = (value?.isEmpty ?? true) ? nil : value
        guard current != next else { return [] }
        let name: String? = if let id = next?.iterationId {
            field.iterations.first { $0.id == id }?.title
        } else if let id = next?.optionId {
            field.options.first { $0.id == id }?.name
        } else {
            nil
        }
        return [.setProjectField(.init(
            itemId: item.id, projectId: projectId, fieldId: field.id, fieldName: field.name, value: next, valueName: name, base: current
        ))]
    }

    /// The changes that move an issue into a group of a view's list.
    func groupMutations(_ item: Item, into key: GroupKey) -> [Mutation] {
        switch key {
        case .field(let fieldId, let value):
            guard let field = field(id: fieldId) else { return [] }
            return valueMutations(item, field: field, value: value)
        case .priority(let optionId):
            guard let projectId = item.projectId, let fieldId = project(of: item)?.priorityFieldId, item.priorityId != optionId else { return [] }
            return [.setField(.init(itemId: item.id, projectId: projectId, fieldId: fieldId, kind: .priority, optionId: optionId, base: item.priorityId))]
        case .assignee(let login):
            guard let contentId = item.contentId, item.kind != .draft || login == nil else { return [] }
            guard let login else {
                // Into "No assignees": everyone comes off it.
                return item.assignees.isEmpty ? [] : [.editAssignees(.init(contentId: contentId, add: [], remove: item.assignees))]
            }
            guard !item.assignees.contains(where: { $0.login == login }),
                  let person = people(for: item).first(where: { $0.login == login })
                    ?? allItems.lazy.flatMap(\.assignees).first(where: { $0.login == login }) else { return [] }
            // From one person's group to another's, the issue changes hands; shared issues gain the person.
            let remove = item.assignees.count == 1 ? item.assignees : []
            return [.editAssignees(.init(contentId: contentId, add: [person], remove: remove))]
        case .milestone(let title):
            return milestoneMutations([item], to: title.flatMap { title in item.projectId.flatMap { milestoneGroup(projectId: $0, title: title) } })
        case .parent(let contentId):
            guard canRelate(item), let summary = item.summary, item.parentId != contentId else { return [] }
            let parent = contentId.flatMap { issue(contentId: $0) }
            return [.setParent(.init(child: summary, parentId: contentId, parentNumber: parent?.number, parentTitle: parent?.title, base: item.parentId))]
        case .repository, .issueType:
            return []
        }
    }

    /// Whether an issue can be dropped into a group: GitHub can't move an issue to another repository, nor change
    /// its type, from a board.
    func canDrop(_ item: Item, into key: GroupKey) -> Bool {
        guard canEditViews(projectId: item.projectId) || item.kind == .issue else { return false }
        switch key {
        case .repository, .issueType: return false
        case .parent: return canRelate(item)
        default: return !groupMutations(item, into: key).isEmpty
        }
    }

    // MARK: New issues

    /// What a new issue starts with in the view open in a project: the values its filter asks for, one each, then
    /// those of the column or group it was started in.
    func newIssuePreset(projectId: String?, group: GroupKey? = nil, column: ColumnValue? = nil) -> NewIssuePreset? {
        guard let projectId, let view = currentView(projectId: projectId) else { return nil }
        var preset = NewIssuePreset()
        let project = projects.first { $0.id == projectId }
        let context = filterContext(projectId: projectId)
        for term in filter(of: view).terms where !term.negated && term.values.count == 1 {
            guard let key = term.key, let value = term.values.first, !value.contains("*") else { continue }
            switch key {
            case "label", "labels": preset.labels.append(value)
            case "assignee", "assignees": preset.assignees.append(value == "@me" ? (viewer?.login ?? value) : value)
            case "milestone": preset.milestoneTitle = value
            case "parent-issue":
                if let number = Int(value.split(separator: "#").last ?? ""),
                   let parent = allItems.first(where: { $0.number == number && value.lowercased().hasPrefix(($0.repo ?? "").lowercased()) }) {
                    preset.parentContentId = parent.contentId
                }
            default:
                guard let field = context?.fieldsByKey[key] else { continue }
                if field.kind == .singleSelect {
                    let options: [(id: String, name: String)] = field.id == project?.statusFieldId
                        ? statusOptions(projectId: projectId).map { ($0.id, $0.name) }
                        : field.id == project?.priorityFieldId
                        ? priorityOptions(projectId: projectId).map { ($0.id, $0.name) }
                        : field.options.map { ($0.id, $0.name) }
                    guard let option = options.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { continue }
                    if field.id == project?.statusFieldId {
                        preset.statusId = option.id
                    } else if field.id == project?.priorityFieldId {
                        preset.priorityId = option.id
                    } else {
                        preset.fieldValues[field.id] = FieldValue(optionId: option.id)
                    }
                } else if field.kind == .iteration, !value.hasPrefix(">"), !value.hasPrefix("<"), !value.contains("..") {
                    let today = CalendarDay.today()
                    let index = IterationBound.index(value, field: field, today: today)
                    let ordered = field.orderedIterations
                    if let index, ordered.indices.contains(index) {
                        preset.fieldValues[field.id] = FieldValue(iterationId: ordered[index].id)
                    }
                }
            }
        }
        if let column {
            if let field = field(id: column.fieldId) { preset.apply(column.value, of: field, project: project) }
        }
        switch group {
        case .field(let fieldId, let value)?:
            if let field = field(id: fieldId) { preset.apply(value, of: field, project: project) }
        case .priority(let optionId)?: preset.priorityId = optionId
        case .assignee(let login)?:
            preset.assignees = login.map { [$0] } ?? []
        case .milestone(let title)?: preset.milestoneTitle = title
        case .parent(let contentId)?: preset.parentContentId = contentId
        case .repository(let id)?: preset.repoId = id
        case .issueType?, nil: break
        }
        return preset
    }

    /// Starts a new issue in a group of a view's list.
    func addIssue(in key: GroupKey) {
        newIssuePreset = newIssuePreset(projectId: scopeProjectId, group: key)
        let parent: String? = if case .parent(let contentId) = key { contentId.flatMap { issue(contentId: $0)?.id } } else { nil }
        overlay = .newIssue(statusId: newIssuePreset?.statusId, parentItemId: parent)
    }

    /// After an issue was made in a view: says so when the view doesn't show it, because its filter leaves it out.
    /// On a board, also when it went into a column you hid.
    func noteIfHidden(_ itemId: String) {
        guard let item = item(id: itemId), let projectId = item.projectId, let view = currentView(projectId: projectId) else { return }
        if !self.view(view, shows: item) {
            status.post(Notice(
                title: String(localized: .createdNotInView(number: item.displayNumber, view: view.name)),
                message: String(localized: .createdNotInViewMessage),
                action: .openItem(item.id)
            ))
            return
        }
        #if os(iOS)
        // The iPhone has no board.
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        #endif
        let hidden = hiddenColumnIds(of: view)
        guard layout(of: view) == .board, !hidden.isEmpty,
              let column = columns(projectId: projectId).first(where: { $0.nesting.members.contains { $0.id == item.id } }),
              hidden.contains(column.id) else { return }
        status.post(Notice(
            title: String(localized: .createdInHiddenColumn(number: item.displayNumber, column: column.title)),
            message: String(localized: .createdInHiddenColumnMessage),
            action: .openItem(item.id)
        ))
    }
}

extension NewIssuePreset {
    mutating func apply(_ value: FieldValue?, of field: ProjectField, project: Project?) {
        if field.id == project?.statusFieldId {
            statusId = value?.optionId
        } else if field.id == project?.priorityFieldId {
            priorityId = value?.optionId
        } else if let value, !value.isEmpty {
            fieldValues[field.id] = value
        } else {
            fieldValues[field.id] = nil
        }
    }
}

extension AppModel {
    /// Fills a new issue with what a view's preset asks for, where the issue doesn't have a value already.
    func apply(_ preset: NewIssuePreset, to draft: inout NewIssueDraft) {
        // The group's repository, where the board has it and the issue isn't a sub-issue, which lives with its parent.
        if draft.parent == nil, let repoId = preset.repoId, repos(projectId: draft.projectId).contains(where: { $0.id == repoId }) {
            draft.repoId = repoId
        }
        if let status = preset.statusId { draft.statusId = status }
        if let priority = preset.priorityId { draft.priorityId = priority }
        if draft.milestoneTitle == nil { draft.milestoneTitle = preset.milestoneTitle }
        if draft.parent == nil, let parent = preset.parentContentId.flatMap({ issue(contentId: $0) }) { draft.parent = parent }
        let available = labels(projectId: draft.projectId, repoId: draft.repoId)
        for name in preset.labels {
            guard let label = available.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  !draft.labels.contains(where: { $0.id == label.id }) else { continue }
            draft.labels.append(label)
        }
        let people = people(projectId: draft.projectId, repoId: draft.repoId)
        for login in preset.assignees {
            guard let person = people.first(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame })
                    ?? (viewer?.login == login ? viewer?.person : nil),
                  !draft.assignees.contains(where: { $0.id == person.id }) else { continue }
            draft.assignees.append(person)
        }
        for (fieldId, value) in preset.fieldValues { draft.fieldValues[fieldId] = value }
    }
}

extension AppModel {
    /// Fields a board can have its columns by: single selects and iterations.
    func columnChoices(projectId: String) -> [ProjectField] {
        fields(projectId: projectId).filter { $0.kind == .singleSelect || $0.kind == .iteration }
    }

    /// Fields a list can be grouped by, Status first.
    func groupChoices(projectId: String) -> [ProjectField] {
        let status = currentStatusFieldId(projectId: projectId)
        return fields(projectId: projectId).filter { Self.groupable($0.kind) && $0.id != status }
    }

    func statusFieldTitle(projectId: String) -> String {
        field(id: currentStatusFieldId(projectId: projectId))?.name ?? String(localized: .status)
    }
}
