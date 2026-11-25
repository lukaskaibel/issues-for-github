import Foundation

/// How a column of the board or a group of the list shows sub-issues. A sub-issue whose parent is in the same
/// group hangs right under it, indented, so a parent and the sub-issues being worked on with it read as one. On a
/// board's columns and in its list, the issues of an epic stand together under a header of the epic, one level in,
/// even a single one; so do the sub-issues of a parent that stands elsewhere, under a quiet header of that parent,
/// where that is switched on. The header over a single issue only says whose it is: it has no count and doesn't fold.
/// Where parents don't make headers, a sub-issue whose parent is elsewhere names its parent.
struct Nesting: Equatable {
    /// Where an issue shown in the group hangs, or a header inside an epic's group.
    struct Place: Equatable {
        /// 0 for an issue that stands on its own.
        var depth = 0
        /// One entry per level down to this issue: whether the line of that level goes on below this issue. The
        /// last one says whether more sub-issues of the same parent follow; the others are the levels above.
        var continues: [Bool] = []
    }

    /// Every issue shown that hangs under another one or under a header, by item id, and every header inside an
    /// epic's group, by the group's id. Issues that stand on their own aren't listed.
    var places: [String: Place] = [:]
    /// The parent each nested issue hangs under, by item id, folded ones included.
    var parents: [String: String] = [:]
    /// How many issues hang under each parent here, at every level and folded ones included.
    var nestedCounts: [String: Int] = [:]
    /// Parents whose sub-issues are folded away here, by item id.
    var folded: Set<String> = []
    /// The whole group in the order it reads when nothing is folded.
    var members: [Item] = []
    /// Whether sub-issues of a parent that stands elsewhere stand together here (`ParentGrouping`).
    var groupsByParent = false

    /// Issues standing together in the group under a header: the issues of an epic, at any level, or the sub-issues
    /// of a parent that isn't among the group's cards, with what hangs under them; a single one too.
    struct Group: Equatable, Identifiable {
        enum Kind: Equatable {
            case epic
            /// Sub-issues of a parent that stands elsewhere: in another status, filtered out, or on no board here.
            case parent
        }

        var kind: Kind
        /// The epic, or the parent the sub-issues are of.
        var head: Item
        /// The issues under the header, at every level, folded ones included.
        var count: Int
        var folded: Bool

        /// Whether its issues fold away under it: two or more. Over a single issue the header only says whose it is,
        /// without a count or an arrow, and a click on it opens the epic or the parent.
        var canFold: Bool { count > 1 }

        /// The head's node id.
        var contentId: String { head.contentId ?? head.id }
        var id: String { kind == .epic ? Self.id(epic: contentId) : Self.id(parent: contentId) }

        /// The id of the group of an epic's issues, by the epic's node id.
        static func id(epic contentId: String) -> String { "epic-group:\(contentId)" }
        /// The id of the group of a parent's sub-issues, by the parent's node id.
        static func id(parent contentId: String) -> String { "parent-group:\(contentId)" }
    }

    /// How sub-issues whose parent stands elsewhere are put together. `head` gives the issue the header over a
    /// sub-issue's group names, from its parent: the issue itself where the app has it, or one made from what the
    /// sub-issue knows; nil where its parent is an epic, whose own header it stands under. `folded` are the parents
    /// (node ids) whose sub-issues are folded away under their header.
    struct ParentGrouping {
        var head: (Item) -> Item?
        var folded: Set<String> = []
    }

    /// One line of the group as it shows: an issue, or the header over an epic's issues or a parent's sub-issues.
    enum Row: Equatable, Identifiable {
        case item(Item)
        case group(Group)

        var id: String {
            switch self {
            case .item(let item): item.id
            case .group(let group): group.id
            }
        }

        var item: Item? {
            if case .item(let item) = self { item } else { nil }
        }

        var group: Group? {
            if case .group(let group) = self { group } else { nil }
        }
    }

    /// The group as it shows, headers included.
    var rows: [Row] = []
    /// The groups whose headers show here, in the order they show: those of epics, and those of parents, also
    /// inside an epic's group.
    var groups: [Group] = []
    /// The epic each issue stands under here, as its node id, by item id; folded ones included.
    var groupOf: [String: String] = [:]
    /// The parent each issue stands under here with other sub-issues of it, where that parent is elsewhere, as its
    /// node id, by item id; at every level and folded ones included.
    var parentGroupOf: [String: String] = [:]
    /// The epic of each issue here, as its node id, by item id, also where it stands alone.
    var epicOf: [String: String] = [:]

    func place(of id: String) -> Place {
        places[id] ?? Place()
    }

    /// Whether an issue names its parent where it shows: one that doesn't hang under its parent here, nor stands
    /// under a header of it.
    func namesParent(of item: Item) -> Bool {
        guard item.parentNumber != nil, parents[item.id] == nil else { return false }
        if let head = parentGroupOf[item.id], head == item.parentId { return false }
        return groupOf[item.id] == nil || groupOf[item.id] != item.parentId
    }

    func depth(of id: String) -> Int {
        places[id]?.depth ?? 0
    }

    /// Whether issues hang under this one here, shown or folded away.
    func hasNested(_ id: String) -> Bool {
        nestedCounts[id] != nil
    }

    /// The issues that hang under `id` here, at every level.
    func descendants(of id: String) -> Set<String> {
        var result = Set<String>()
        var found = true
        while found {
            found = false
            for (child, parent) in parents where !result.contains(child) && (parent == id || result.contains(parent)) {
                result.insert(child)
                found = true
            }
        }
        return result
    }

    /// The issues under a group's header here, at every level, folded ones included, in reading order.
    func members(of group: Group) -> [Item] {
        switch group.kind {
        case .epic: members.filter { groupOf[$0.id] == group.contentId }
        case .parent: members.filter { parentGroupOf[$0.id] == group.contentId }
        }
    }

    /// Puts a group's issues in reading order: each sub-issue right after its parent, when the parent is in the
    /// group too, among the parent's other sub-issues in board order. `items` come in board order; `folded` are
    /// the issues (node ids) whose sub-issues are folded away, which are left out of the result. With `parents`, the
    /// sub-issues of a parent that isn't in the group stand together under a header of it, one level in, where the
    /// first of them stands; a single one too.
    static func arrange(
        _ items: [Item], folded foldedIssues: Set<String> = [], parents grouping: ParentGrouping? = nil
    ) -> (items: [Item], nesting: Nesting) {
        // An issue on two boards can be in My Issues twice; its sub-issues hang under the first.
        var indexOfIssue: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            if let contentId = item.contentId, indexOfIssue[contentId] == nil { indexOfIssue[contentId] = index }
        }
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for (index, item) in items.enumerated() {
            if let parent = item.parentId.flatMap({ indexOfIssue[$0] }), parent != index {
                children[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }

        // Sub-issues whose parent isn't here, by that parent, in board order, with what their header names.
        var siblings: [String: [Int]] = [:]
        var heads: [String: Item] = [:]
        if let grouping {
            for root in roots {
                guard let parentId = items[root].parentId, indexOfIssue[parentId] == nil else { continue }
                if heads[parentId] == nil {
                    guard var head = grouping.head(items[root]) else { continue }
                    head.contentId = parentId
                    heads[parentId] = head
                }
                siblings[parentId, default: []].append(root)
            }
        }

        var nesting = Nesting()
        nesting.groupsByParent = grouping != nil
        var rows: [Row] = []
        var visited = Set<Int>()

        /// Adds an issue and everything under it; returns how many issues hang under it.
        @discardableResult
        func visit(_ index: Int, continues: [Bool], hidden: Bool) -> Int {
            guard visited.insert(index).inserted else { return 0 }
            let item = items[index]
            nesting.members.append(item)
            if !hidden {
                rows.append(.item(item))
                if !continues.isEmpty { nesting.places[item.id] = Place(depth: continues.count, continues: continues) }
            }
            // Sub-issues met again through a loop in stale data stand on their own instead.
            let kids = (children[index] ?? []).filter { !visited.contains($0) }
            guard !kids.isEmpty else { return 0 }
            let folds = item.contentId.map { foldedIssues.contains($0) } ?? false
            if folds, !hidden { nesting.folded.insert(item.id) }
            var count = 0
            for (position, kid) in kids.enumerated() {
                guard !visited.contains(kid) else { continue }
                nesting.parents[items[kid].id] = item.id
                count += 1 + visit(kid, continues: continues + [position < kids.count - 1], hidden: hidden || folds)
            }
            if count > 0 { nesting.nestedCounts[item.id] = count }
            return count
        }

        var headed = Set<String>()
        for root in roots {
            guard let parentId = items[root].parentId, let together = siblings[parentId], let head = heads[parentId] else {
                visit(root, continues: [], hidden: false)
                continue
            }
            // The header goes where the first of them stands, and all of them under it. Over a single issue, with
            // nothing hanging under it, it doesn't fold.
            guard headed.insert(parentId).inserted else { continue }
            let foldable = together.count > 1 || together.contains { !(children[$0] ?? []).isEmpty }
            let folds = foldable && (grouping?.folded.contains(parentId) ?? false)
            let header = rows.count
            let first = nesting.members.count
            rows.append(.group(Group(kind: .parent, head: head, count: 0, folded: folds)))
            for (position, member) in together.enumerated() {
                visit(member, continues: [position < together.count - 1], hidden: folds)
            }
            let inside = nesting.members[first...]
            for member in inside { nesting.parentGroupOf[member.id] = parentId }
            rows[header] = .group(Group(kind: .parent, head: head, count: inside.count, folded: folds))
        }
        // Issues that are each other's parent, which GitHub doesn't allow but stale data might show.
        for index in items.indices where !visited.contains(index) { visit(index, continues: [], hidden: false) }
        nesting.rows = rows
        nesting.groups = rows.compactMap(\.group)
        return (rows.compactMap(\.item), nesting)
    }

    /// Arranges a group as `arrange(_:folded:parents:)` does, and puts the issues of each epic here together, under a
    /// header of the epic, where the first of them stands on the board; a single one too. `epic` finds
    /// an issue's epic; `foldedEpics` are the epics (node ids) whose issues are folded away under their header. A
    /// header over sub-issues of a parent elsewhere stands inside the epic's group, one level in, like an issue.
    static func arrange(
        _ items: [Item], folded foldedIssues: Set<String> = [], epic: (Item) -> Item?, foldedEpics: Set<String> = [],
        parents grouping: ParentGrouping? = nil
    ) -> (items: [Item], nesting: Nesting) {
        var epics: [Int: Item] = [:]
        for (index, item) in items.enumerated() {
            guard let found = epic(item), found.contentId != nil, found.contentId != item.contentId else { continue }
            epics[index] = found
        }
        var loose: [Int] = []
        var grouped: [String: [Int]] = [:]
        for index in items.indices {
            if let id = epics[index]?.contentId {
                grouped[id, default: []].append(index)
            } else {
                loose.append(index)
            }
        }
        // Sub-issues of an epic itself stand under the epic's header, or name the epic.
        let underEpic = Set(epics.compactMap { index, found in items[index].parentId == found.contentId ? items[index].id : nil })
        let byParent = grouping.map { grouping in
            ParentGrouping(head: { item in underEpic.contains(item.id) ? nil : grouping.head(item) }, folded: grouping.folded)
        }
        var nesting = Nesting()
        nesting.groupsByParent = grouping != nil
        for (index, found) in epics {
            if let id = found.contentId { nesting.epicOf[items[index].id] = id }
        }
        guard !grouped.isEmpty else {
            var (shown, plain) = arrange(items, folded: foldedIssues, parents: byParent)
            plain.epicOf = nesting.epicOf
            return (shown, plain)
        }

        // Each issue that stands on its own, with what hangs under it, is a block; so is each group under a header.
        // Blocks show in the board order of their first issue.
        let boardIndex = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let (_, looseNesting) = arrange(loose.map { items[$0] }, folded: foldedIssues, parents: byParent)
        nesting.places = looseNesting.places
        nesting.parents = looseNesting.parents
        nesting.nestedCounts = looseNesting.nestedCounts
        nesting.folded = looseNesting.folded
        nesting.parentGroupOf = looseNesting.parentGroupOf
        var blocks = looseNesting.blocks { boardIndex[$0.id] ?? 0 }

        for (id, indices) in grouped {
            guard let found = epics[indices[0]] else { continue }
            let members = indices.map { items[$0] }
            let (_, inner) = arrange(members, folded: foldedIssues, parents: byParent)
            let group = Group(kind: .epic, head: found, count: members.count, folded: members.count > 1 && foldedEpics.contains(id))
            for member in inner.members { nesting.groupOf[member.id] = id }
            nesting.parents.merge(inner.parents) { first, _ in first }
            nesting.nestedCounts.merge(inner.nestedCounts) { first, _ in first }
            nesting.parentGroupOf.merge(inner.parentGroupOf) { first, _ in first }
            var block = Block(position: indices.min() ?? 0, rows: [.group(group)], members: inner.members)
            if !group.folded {
                nesting.folded.formUnion(inner.folded)
                // Every issue and header of the group hangs one level in, under the epic's header.
                let roots = inner.rows.filter(inner.standsAlone).count
                var root = -1
                for row in inner.rows {
                    if inner.standsAlone(row) { root += 1 }
                    let place = inner.place(of: row.id)
                    nesting.places[row.id] = Place(depth: place.depth + 1, continues: [root < roots - 1] + place.continues)
                    block.rows.append(row)
                }
            }
            blocks.append(block)
        }

        blocks.sort { $0.position < $1.position }
        nesting.rows = blocks.flatMap(\.rows)
        nesting.members = blocks.flatMap(\.members)
        nesting.groups = nesting.rows.compactMap(\.group)
        return (nesting.rows.compactMap(\.item), nesting)
    }

    /// An issue standing on its own with what hangs under it, or a header with the issues under it: what an epic's
    /// group is made of, and a column outside them.
    private struct Block {
        /// Where its first issue is on the board.
        var position: Int
        var rows: [Row] = []
        var members: [Item] = []
    }

    /// Whether a row starts a block of its own: a header, or an issue that hangs under nothing here.
    private func standsAlone(_ row: Row) -> Bool {
        switch row {
        case .item(let item): places[item.id] == nil
        case .group: true
        }
    }

    /// The group's rows and members cut into blocks, each placed by its first issue.
    private func blocks(position: (Item) -> Int) -> [Block] {
        /// The block an issue is in: its parent's header, or the issue it hangs under at the top.
        func key(_ id: String) -> String {
            if let head = parentGroupOf[id] { return Group.id(parent: head) }
            var current = id
            while let up = parents[current] { current = up }
            return current
        }
        var order: [String] = []
        var found: [String: Block] = [:]
        for member in members {
            let at = key(member.id)
            if found[at] == nil {
                order.append(at)
                found[at] = Block(position: position(member))
            }
            found[at]?.members.append(member)
        }
        for row in rows {
            switch row {
            case .item(let item): found[key(item.id)]?.rows.append(row)
            case .group(let group): found[group.id]?.rows.append(row)
            }
        }
        return order.compactMap { found[$0] }
    }

    // MARK: Dropping an issue into the group

    /// Where an issue lands when it is dropped into this group.
    struct Landing: Equatable {
        /// The issues it takes its place among, in the order they show: the other sub-issues of its parent here, the
        /// issues of the epic it stands under here, or what stands outside every group (each group counted by its
        /// first issue on the board).
        var peers: [Item]
        /// How many of `peers` come before it.
        var rank: Int
        /// The parent it hangs under here, by item id.
        var parentId: String?
        /// The epic whose issues it stands among here, as its node id: under its header, or with another issue of
        /// it that stands alone so far.
        var epic: String?
        /// The parent elsewhere whose other sub-issues it stands among here, as its node id: under their header, or
        /// with the one that stands alone so far.
        var parentGroup: String? = nil
        /// Where it shows among `shown`, and how deep.
        var slot: Int
        var depth: Int
        /// Where it shows among the group's rows without it and what it brings along, headers included.
        var row: Int
    }

    /// Where `item` lands when dropped at `slot` among `shown`, the group's issues as shown without the item and
    /// what hangs under it. A sub-issue whose parent is here always joins its parent's sub-issues, and one whose
    /// parent is elsewhere the other sub-issues of that parent here, where they stand together; any other issue goes
    /// in front of or after another one that stands on its own, never between a parent and its sub-issues nor
    /// among the issues under a header of a parent. Dropped between two issues of an epic's group, it joins the
    /// epic, when the epic can be its parent; an issue of an epic stays with the epic's other issues here. `epic` is
    /// the item's epic (node id). `belowHeader` names an epic whose header the slot is right below, where a list's
    /// own reordering put it: there it joins the epic.
    func landing(of item: Item, at slot: Int, shown: [Item], epic: String? = nil, belowHeader: String? = nil) -> Landing {
        let moving = descendants(of: item.id).union([item.id])
        let itemEpic = epic ?? epicOf[item.id]
        let parent = members.first { member in
            !moving.contains(member.id) && member.contentId != nil && member.contentId == item.parentId
        }
        let clamped = min(max(slot, 0), shown.count)

        // Other sub-issues of its parent, which stands elsewhere: it stands with them, as it will after the drop.
        if parent == nil, groupsByParent, let parentId = item.parentId, parentId != itemEpic,
           members.contains(where: { isSibling($0, of: parentId, moving: moving) }) {
            return landing(moving: moving, parent: nil, siblings: parentId, area: nil, at: clamped, shown: shown) { member in
                item.contentId != nil && member.parentId == item.contentId
            }
        }

        // The epic whose issues it stands among.
        let area: String?
        if let parent {
            area = groupOf[parent.id]
        } else {
            let before = clamped > 0 ? groupOf[shown[clamped - 1].id] : nil
            let after = clamped < shown.count ? groupOf[shown[clamped].id] : nil
            // An issue can only change its epic where the epic would be its parent: one in no epic and under no
            // other issue, or one right under its epic.
            let canChange = item.parentId == nil || item.parentId == itemEpic
            if let header = belowHeader, after == header, header == itemEpic || canChange {
                area = header
            } else if let group = after, group == before, group == itemEpic || canChange {
                area = group
            } else if let itemEpic, before == itemEpic || after == itemEpic {
                area = itemEpic
            } else if let itemEpic, members.contains(where: { !moving.contains($0.id) && epicOf[$0.id] == itemEpic }) {
                // Anywhere else, an issue of an epic stays with the epic's other issues here.
                area = itemEpic
            } else {
                area = nil
            }
        }
        // Issues it is the parent of will hang under it.
        return landing(moving: moving, parent: parent, area: area, at: clamped, shown: shown) { member in
            item.contentId != nil && member.parentId == item.contentId
        }
    }

    /// Whether `member` is a sub-issue of `parentId` that stands here without its parent, and isn't moving.
    private func isSibling(_ member: Item, of parentId: String, moving: Set<String>) -> Bool {
        !moving.contains(member.id) && member.parentId == parentId && parents[member.id] == nil
    }

    /// Where the issues under a group's header land when the whole group is dropped at `slot` among `shown`, the
    /// group's issues as shown without the ones `moving`. An epic's issues join the epic's issues here, at the top,
    /// between them or at the end. A parent's sub-issues hang under the parent where it stands here, and join its
    /// other sub-issues here, as an epic's do. Anywhere else they go together in front of or after what stands
    /// outside every group, or among their epic's issues here: `epic` is the epic (node id) of a parent's sub-issues.
    func landing(ofGroup group: Group, moving: Set<String>, at slot: Int, shown: [Item], epic: String? = nil) -> Landing {
        let clamped = min(max(slot, 0), shown.count)
        func joining(_ epic: String?) -> String? {
            epic.flatMap { epic in members.contains { !moving.contains($0.id) && epicOf[$0.id] == epic } ? epic : nil }
        }
        switch group.kind {
        case .epic:
            return landing(moving: moving, parent: nil, area: joining(group.contentId), at: clamped, shown: shown) { _ in false }
        case .parent:
            if let parent = members.first(where: { !moving.contains($0.id) && $0.contentId == group.contentId }) {
                return landing(moving: moving, parent: parent, area: groupOf[parent.id], at: clamped, shown: shown) { _ in false }
            }
            if groupsByParent, members.contains(where: { isSibling($0, of: group.contentId, moving: moving) }) {
                return landing(moving: moving, parent: nil, siblings: group.contentId, area: nil, at: clamped, shown: shown) { _ in false }
            }
            return landing(moving: moving, parent: nil, area: joining(epic), at: clamped, shown: shown) { _ in false }
        }
    }

    /// Where several picked issues land when they are dropped together at `slot` among `shown`, the group's issues as
    /// shown without the ones `moving`: the picked ones and what hangs under them. When they are all sub-issues of
    /// `parent`, a parent elsewhere with other sub-issues here, they stand with those; when they all belong to `epic`,
    /// they stand with its other issues here, as an epic's group does; otherwise they go in front of or after what
    /// stands outside every group. `parents` are the picked issues' node ids: issues they are the parent of will hang
    /// under them.
    func landing(
        ofPicked moving: Set<String>, epic: String?, parent: String? = nil, parents: Set<String>, at slot: Int, shown: [Item]
    ) -> Landing {
        if groupsByParent, let parent, parent != epic, !members.contains(where: { !moving.contains($0.id) && $0.contentId == parent }),
           members.contains(where: { isSibling($0, of: parent, moving: moving) }) {
            return landing(moving: moving, parent: nil, siblings: parent, area: nil, at: min(max(slot, 0), shown.count), shown: shown) { member in
                member.parentId.map(parents.contains) ?? false
            }
        }
        let joins = epic.map { epic in members.contains { !moving.contains($0.id) && epicOf[$0.id] == epic } } ?? false
        return landing(moving: moving, parent: nil, area: joins ? epic : nil, at: min(max(slot, 0), shown.count), shown: shown) { member in
            member.parentId.map(parents.contains) ?? false
        }
    }

    /// The rows shown without the issues `moving`: a header goes too when all of the issues under it do.
    func rows(without moving: Set<String>) -> [Row] {
        guard !moving.isEmpty else { return rows }
        let staying = members.filter { !moving.contains($0.id) }
        let epics = Set(staying.compactMap { groupOf[$0.id] })
        let heads = Set(staying.compactMap { parentGroupOf[$0.id] })
        return rows.filter { row in
            switch row {
            case .item(let item): !moving.contains(item.id)
            case .group(let group): group.kind == .epic ? epics.contains(group.contentId) : heads.contains(group.contentId)
            }
        }
    }

    /// Where issues land among their `peers`: under `parent`, among the other sub-issues of `siblings`, a parent
    /// elsewhere, or among the issues of the epic `area`, at `slot` among `shown`. `adopts` names the issues that will
    /// hang under the one moving, which aren't its peers.
    private func landing(
        moving: Set<String>, parent: Item?, siblings: String? = nil, area: String?, at clamped: Int, shown: [Item],
        adopts: (Item) -> Bool
    ) -> Landing {
        // Where each header stands among `shown`, by its group's id; a folded one just above what follows it.
        let rowsShown = rows(without: moving)
        var headerAt: [String: Double] = [:]
        var headerRow: [String: Int] = [:]
        var rowOf: [String: Int] = [:]
        var seen = 0
        for (number, row) in rowsShown.enumerated() {
            switch row {
            case .group(let group):
                headerAt[group.id] = Double(seen) - (group.folded ? 0.5 : 0)
                headerRow[group.id] = number
            case .item(let shownItem):
                rowOf[shownItem.id] = number
                seen += 1
            }
        }
        // Where the group's issues stand: a folded one counts as just below the parent it is folded into, or as
        // where the header it is folded under is.
        var index: [String: Double] = [:]
        for (position, shownItem) in shown.enumerated() { index[shownItem.id] = Double(position) }
        func position(of id: String) -> Double {
            if let found = index[id] { return found }
            var current = id
            while let up = parents[current] {
                if let found = index[up] { return found + 0.5 }
                current = up
            }
            if let head = parentGroupOf[current], let header = headerAt[Group.id(parent: head)] { return header }
            return Double(shown.count)
        }

        // The issue of each group that comes first on the board, which places the group, by the group's id.
        var anchors: [String: Item] = [:]
        for member in members where !moving.contains(member.id) {
            let groups = [groupOf[member.id].map(Group.id(epic:)), parentGroupOf[member.id].map(Group.id(parent:))]
            for group in groups.compactMap(\.self) {
                if let current = anchors[group], current.position <= member.position { continue }
                anchors[group] = member
            }
        }
        /// The group an issue counts as among peers that stand outside it: an epic's outside every epic, otherwise
        /// a parent's header it stands under.
        func counted(_ member: Item) -> String? {
            guard parent == nil, siblings == nil else { return nil }
            if area == nil, let epic = groupOf[member.id] { return Group.id(epic: epic) }
            return parentGroupOf[member.id].map(Group.id(parent:))
        }
        func key(_ member: Item) -> Double {
            if let group = counted(member), let header = headerAt[group] { return header }
            return position(of: member.id)
        }
        // Issues under the one moving come along with it, and issues it is the parent of will hang under it.
        let peers = members.filter { member in
            guard !moving.contains(member.id), member.id != parent?.id, !adopts(member) else { return false }
            if let siblings { return isSibling(member, of: siblings, moving: moving) }
            // Outside a group, the group counts once, by the issue that places it.
            if let group = counted(member) {
                guard anchors[group]?.id == member.id else { return false }
                return area.map { epicOf[member.id] == $0 } ?? true
            }
            let memberParent = parents[member.id].flatMap { id in moving.contains(id) ? nil : id }
            guard memberParent == parent?.id else { return false }
            if parent == nil, let area { return epicOf[member.id] == area }
            return true
        }.sorted { key($0) < key($1) }
        let rank = peers.filter { key($0) < Double(clamped) }.count

        let grouped = area.map { headerRow[Group.id(epic: $0)] != nil } ?? false
        let depth = if let parent {
            self.depth(of: parent.id) + 1
        } else if siblings != nil, let first = peers.first {
            self.depth(of: first.id)
        } else {
            grouped ? 1 : 0
        }
        // Where it shows: in front of the next peer, or after the last one and everything under it.
        let shownSlot: Int
        let row: Int
        func rowAfter(_ itemIndex: Int) -> Int {
            itemIndex > 0 ? (rowOf[shown[itemIndex - 1].id] ?? rowsShown.count - 1) + 1 : 0
        }
        if rank < peers.count {
            let next = peers[rank]
            shownSlot = Int(key(next).rounded(.up))
            if let group = counted(next), let header = headerRow[group] {
                row = header
            } else {
                row = rowOf[next.id] ?? rowsShown.count
            }
        } else if let parent, let start = index[parent.id] {
            var end = Int(start) + 1
            while end < shown.count, self.depth(of: shown[end].id) >= depth { end += 1 }
            shownSlot = end
            row = rowAfter(end)
        } else if let area, grouped {
            // At the end of the epic's issues.
            let last = shown.lastIndex { groupOf[$0.id] == area }
            shownSlot = last.map { $0 + 1 } ?? Int((headerAt[Group.id(epic: area)] ?? Double(shown.count)).rounded(.up))
            row = last.map { rowAfter($0 + 1) } ?? (headerRow[Group.id(epic: area)].map { $0 + 1 } ?? rowsShown.count)
        } else if siblings != nil || area != nil, let alone = peers.last {
            // After the last of the other issues it stands with, and what hangs under it.
            var end = Int(position(of: alone.id)) + 1
            while end < shown.count, self.depth(of: shown[end].id) > self.depth(of: alone.id) { end += 1 }
            shownSlot = end
            row = rowAfter(end)
        } else {
            shownSlot = shown.count
            row = rowsShown.count
        }
        return Landing(
            peers: peers, rank: rank, parentId: parent?.id, epic: area, parentGroup: siblings, slot: min(shownSlot, shown.count),
            depth: depth, row: min(row, rowsShown.count)
        )
    }
}

extension BoardColumn {
    /// The cards shown, without `item` and what hangs under it: what a card being moved is dropped among.
    func shown(without item: Item) -> [Item] {
        let moving = nesting.descendants(of: item.id).union([item.id])
        return items.filter { !moving.contains($0.id) }
    }

    /// Where `item` lands when dropped at `index` among `shown(without: item)`. `epic` is the item's epic (node
    /// id), for an item that comes from another column.
    func landing(of item: Item, at index: Int, epic: String? = nil, belowHeader: String? = nil) -> Nesting.Landing {
        nesting.landing(of: item, at: index, shown: shown(without: item), epic: epic, belowHeader: belowHeader)
    }

    /// The rows shown, without `item` and what hangs under it, headers included.
    func rows(without item: Item) -> [Nesting.Row] {
        nesting.rows(without: nesting.descendants(of: item.id).union([item.id]))
    }

    /// The issues under a group's header here, folded ones included, in reading order.
    func members(of group: Nesting.Group) -> [Item] {
        nesting.members(of: group)
    }

    /// Where the issues `moving`, those under a group's header, land when the group is dropped at `index` among the
    /// column's issues as shown without them. `epic` is the epic (node id) of a parent's sub-issues.
    func landing(ofGroup group: Nesting.Group, moving: Set<String>, at index: Int, epic: String? = nil) -> Nesting.Landing {
        nesting.landing(ofGroup: group, moving: moving, at: index, shown: items.filter { !moving.contains($0.id) }, epic: epic)
    }

    /// Where several picked issues land when they are dropped together at `index` among the column's issues as shown
    /// without `picked.moving`.
    func landing(of picked: PickedIssues, at index: Int) -> Nesting.Landing {
        // Sub-issues of one parent, all of them.
        let parent = Set(picked.items.map(\.parentId)).count == 1 ? picked.items.first?.parentId : nil
        return nesting.landing(
            ofPicked: picked.moving, epic: picked.epic, parent: parent, parents: Set(picked.items.compactMap(\.contentId)),
            at: index, shown: items.filter { !picked.moving.contains($0.id) }
        )
    }
}
