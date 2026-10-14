import Foundation

/// How a column of the board or a group of the list shows sub-issues. A sub-issue whose parent is in the same
/// group hangs right under it, indented, so a parent and the sub-issues being worked on with it read as one. A
/// sub-issue whose parent is anywhere else stands on its own and names its parent. On a board's columns and in its
/// list, the issues of an epic that has two or more of them in the group also stand together, under a header of
/// the epic, one level in.
struct Nesting: Equatable {
    /// Where an issue shown in the group hangs.
    struct Place: Equatable {
        /// 0 for an issue that stands on its own.
        var depth = 0
        /// One entry per level down to this issue: whether the line of that level goes on below this issue. The
        /// last one says whether more sub-issues of the same parent follow; the others are the levels above.
        var continues: [Bool] = []
    }

    /// Every issue shown that hangs under another one, by item id. Issues that stand on their own aren't listed.
    var places: [String: Place] = [:]
    /// The parent each nested issue hangs under, by item id, folded ones included.
    var parents: [String: String] = [:]
    /// How many issues hang under each parent here, at every level and folded ones included.
    var nestedCounts: [String: Int] = [:]
    /// Parents whose sub-issues are folded away here, by item id.
    var folded: Set<String> = []
    /// The whole group in the order it reads when nothing is folded.
    var members: [Item] = []

    /// The issues of an epic standing together in the group under a header of the epic: two or more of them, at
    /// any level. A single issue of an epic names the epic itself instead.
    struct EpicGroup: Equatable, Identifiable {
        var epic: Item
        /// The epic's issues here, at every level, folded ones included.
        var count: Int
        var folded: Bool

        /// The epic's node id.
        var contentId: String { epic.contentId ?? epic.id }
        var id: String { "epic-group:\(contentId)" }
    }

    /// One line of the group as it shows: an issue, or the header over an epic's issues.
    enum Row: Equatable, Identifiable {
        case item(Item)
        case epic(EpicGroup)

        var id: String {
            switch self {
            case .item(let item): item.id
            case .epic(let group): group.id
            }
        }

        var item: Item? {
            if case .item(let item) = self { item } else { nil }
        }
    }

    /// The group as it shows, epic headers included.
    var rows: [Row] = []
    /// The epics whose issues stand together here, in the order they show.
    var groups: [EpicGroup] = []
    /// The epic each issue stands under here, as its node id, by item id; folded ones included.
    var groupOf: [String: String] = [:]
    /// The epic of each issue here, as its node id, by item id, also where it stands alone.
    var epicOf: [String: String] = [:]

    func place(of id: String) -> Place {
        places[id] ?? Place()
    }

    /// Whether an issue names its parent where it shows: one that doesn't hang under its parent here, nor stands
    /// in its parent's epic group.
    func namesParent(of item: Item) -> Bool {
        guard item.parentNumber != nil, parents[item.id] == nil else { return false }
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

    /// Puts a group's issues in reading order: each sub-issue right after its parent, when the parent is in the
    /// group too, among the parent's other sub-issues in board order. `items` come in board order; `folded` are
    /// the issues (node ids) whose sub-issues are folded away, which are left out of the result.
    static func arrange(_ items: [Item], folded foldedIssues: Set<String> = []) -> (items: [Item], nesting: Nesting) {
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

        var nesting = Nesting()
        var shown: [Item] = []
        var visited = Set<Int>()

        /// Adds an issue and everything under it; returns how many issues hang under it.
        @discardableResult
        func visit(_ index: Int, continues: [Bool], hidden: Bool) -> Int {
            guard visited.insert(index).inserted else { return 0 }
            let item = items[index]
            nesting.members.append(item)
            if !hidden {
                shown.append(item)
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

        for root in roots { visit(root, continues: [], hidden: false) }
        // Issues that are each other's parent, which GitHub doesn't allow but stale data might show.
        for index in items.indices where !visited.contains(index) { visit(index, continues: [], hidden: false) }
        nesting.rows = shown.map(Row.item)
        return (shown, nesting)
    }

    /// Arranges a group as `arrange(_:folded:)` does, and puts the issues of each epic that has two or more of them
    /// here together, under a header of the epic, where the first of them stands on the board. `epic` finds an
    /// issue's epic; `foldedEpics` are the epics (node ids) whose issues are folded away under their header.
    static func arrange(
        _ items: [Item], folded foldedIssues: Set<String> = [], epic: (Item) -> Item?, foldedEpics: Set<String> = []
    ) -> (items: [Item], nesting: Nesting) {
        var epics: [Int: Item] = [:]
        var counts: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            guard let found = epic(item), let id = found.contentId, id != item.contentId else { continue }
            epics[index] = found
            counts[id, default: 0] += 1
        }
        var loose: [Int] = []
        var grouped: [String: [Int]] = [:]
        for index in items.indices {
            if let id = epics[index]?.contentId, counts[id, default: 0] >= 2 {
                grouped[id, default: []].append(index)
            } else {
                loose.append(index)
            }
        }
        var nesting = Nesting()
        for (index, found) in epics {
            if let id = found.contentId { nesting.epicOf[items[index].id] = id }
        }
        guard !grouped.isEmpty else {
            var (shown, plain) = arrange(items, folded: foldedIssues)
            plain.epicOf = nesting.epicOf
            return (shown, plain)
        }

        // Each issue that stands on its own, with what hangs under it, is a block; so is each epic's group. Blocks
        // show in the board order of their first issue.
        struct Block {
            var position: Int
            var rows: [Row] = []
            var members: [Item] = []
            var group: EpicGroup?
        }
        var blocks: [Block] = []
        let boardIndex = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        let (looseShown, looseNesting) = arrange(loose.map { items[$0] }, folded: foldedIssues)
        nesting.places = looseNesting.places
        nesting.parents = looseNesting.parents
        nesting.nestedCounts = looseNesting.nestedCounts
        nesting.folded = looseNesting.folded
        let looseShownIds = Set(looseShown.map(\.id))
        var looseBlocks: [Block] = []
        for member in looseNesting.members {
            if looseNesting.parents[member.id] == nil || looseBlocks.isEmpty {
                looseBlocks.append(Block(position: boardIndex[member.id] ?? 0))
            }
            looseBlocks[looseBlocks.count - 1].members.append(member)
            if looseShownIds.contains(member.id) { looseBlocks[looseBlocks.count - 1].rows.append(.item(member)) }
        }
        blocks += looseBlocks

        for (id, indices) in grouped {
            guard let found = epics[indices[0]] else { continue }
            let members = indices.map { items[$0] }
            let (shown, inner) = arrange(members, folded: foldedIssues)
            let group = EpicGroup(epic: found, count: members.count, folded: foldedEpics.contains(id))
            for member in inner.members { nesting.groupOf[member.id] = id }
            nesting.parents.merge(inner.parents) { first, _ in first }
            nesting.nestedCounts.merge(inner.nestedCounts) { first, _ in first }
            var block = Block(position: indices.min() ?? 0, rows: [.epic(group)], members: inner.members, group: group)
            if !group.folded {
                nesting.folded.formUnion(inner.folded)
                let roots = shown.filter { inner.depth(of: $0.id) == 0 }.count
                var root = -1
                for item in shown {
                    let place = inner.place(of: item.id)
                    if place.depth == 0 { root += 1 }
                    // Every issue of the group hangs one level in, under the epic's header.
                    nesting.places[item.id] = Place(depth: place.depth + 1, continues: [root < roots - 1] + place.continues)
                    block.rows.append(.item(item))
                }
            }
            blocks.append(block)
        }

        blocks.sort { $0.position < $1.position }
        nesting.rows = blocks.flatMap(\.rows)
        nesting.members = blocks.flatMap(\.members)
        nesting.groups = blocks.compactMap(\.group)
        return (nesting.rows.compactMap(\.item), nesting)
    }

    // MARK: Dropping an issue into the group

    /// Where an issue lands when it is dropped into this group.
    struct Landing: Equatable {
        /// The issues it takes its place among, in the order they show: the other sub-issues of its parent here,
        /// the issues of the epic it stands under here, or what stands outside every epic's group (each group
        /// counted by its first issue on the board).
        var peers: [Item]
        /// How many of `peers` come before it.
        var rank: Int
        /// The parent it hangs under here, by item id.
        var parentId: String?
        /// The epic whose issues it stands among here, as its node id: under its header, or with another issue of
        /// it that stands alone so far.
        var epic: String?
        /// Where it shows among `shown`, and how deep.
        var slot: Int
        var depth: Int
        /// Where it shows among the group's rows without it and what it brings along, epic headers included.
        var row: Int
    }

    /// Where `item` lands when dropped at `slot` among `shown`, the group's issues as shown without the item and
    /// what hangs under it. A sub-issue whose parent is here always joins its parent's sub-issues; any other issue
    /// goes in front of or after another one that stands on its own, never between a parent and its sub-issues.
    /// Dropped between two issues of an epic's group, it joins the epic, when the epic can be its parent; an issue
    /// of an epic stays with the epic's other issues here. `epic` is the item's epic (node id). `belowHeader` names
    /// an epic whose header the slot is right below, where a list's own reordering put it: there it joins the epic.
    func landing(of item: Item, at slot: Int, shown: [Item], epic: String? = nil, belowHeader: String? = nil) -> Landing {
        let moving = descendants(of: item.id).union([item.id])
        let itemEpic = epic ?? epicOf[item.id]
        let parent = members.first { member in
            !moving.contains(member.id) && member.contentId != nil && member.contentId == item.parentId
        }
        let clamped = min(max(slot, 0), shown.count)

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

    /// Where the issues of an epic's group land when the whole group is dropped at `slot` among `shown`, the
    /// group's issues as shown without the ones `moving`. Where the epic has issues here already, they join them, at
    /// the top, between them or at the end; anywhere else they go together in front of or after what stands outside
    /// every epic's group, as a single issue of no epic does.
    func landing(ofGroup epic: String, moving: Set<String>, at slot: Int, shown: [Item]) -> Landing {
        let joins = members.contains { !moving.contains($0.id) && epicOf[$0.id] == epic }
        return landing(moving: moving, parent: nil, area: joins ? epic : nil, at: min(max(slot, 0), shown.count), shown: shown) { _ in false }
    }

    /// The rows shown without the issues `moving`: an epic's header goes too when all of its issues do.
    func rows(without moving: Set<String>) -> [Row] {
        guard !moving.isEmpty else { return rows }
        let staying = Set(members.filter { !moving.contains($0.id) }.compactMap { groupOf[$0.id] })
        return rows.filter { row in
            switch row {
            case .item(let item): !moving.contains(item.id)
            case .epic(let group): staying.contains(group.contentId)
            }
        }
    }

    /// Where issues land among their `peers`, under `parent` or among the issues of the epic `area`, at `slot` among
    /// `shown`. `adopts` names the issues that will hang under the one moving, which aren't its peers.
    private func landing(
        moving: Set<String>, parent: Item?, area: String?, at clamped: Int, shown: [Item], adopts: (Item) -> Bool
    ) -> Landing {
        // Where the group's issues stand: a folded one counts as just below the parent it is folded into.
        var index: [String: Double] = [:]
        for (position, shownItem) in shown.enumerated() { index[shownItem.id] = Double(position) }
        func position(of id: String) -> Double {
            if let found = index[id] { return found }
            var current = id
            while let up = parents[current] {
                if let found = index[up] { return found + 0.5 }
                current = up
            }
            return Double(shown.count)
        }
        // Where each epic's header stands among `shown`; a folded one just above what follows it.
        let rowsShown = rows(without: moving)
        var headerAt: [String: Double] = [:]
        var headerRow: [String: Int] = [:]
        var rowOf: [String: Int] = [:]
        var seen = 0
        for (number, row) in rowsShown.enumerated() {
            switch row {
            case .epic(let group):
                headerAt[group.contentId] = Double(seen) - (group.folded ? 0.5 : 0)
                headerRow[group.contentId] = number
            case .item(let shownItem):
                rowOf[shownItem.id] = number
                seen += 1
            }
        }

        // The issue of each epic's group that comes first on the board, which places the group.
        var anchors: [String: Item] = [:]
        for member in members where !moving.contains(member.id) {
            guard let group = groupOf[member.id] else { continue }
            if let current = anchors[group], current.position <= member.position { continue }
            anchors[group] = member
        }
        func key(_ member: Item) -> Double {
            if parent == nil, area == nil, let group = groupOf[member.id], let header = headerAt[group] { return header }
            return position(of: member.id)
        }
        // Issues under the one moving come along with it, and issues it is the parent of will hang under it.
        let peers = members.filter { member in
            guard !moving.contains(member.id), member.id != parent?.id, !adopts(member) else { return false }
            // Outside every group, a group counts once, by the issue that places it.
            if parent == nil, area == nil, let group = groupOf[member.id] { return anchors[group]?.id == member.id }
            let memberParent = parents[member.id].flatMap { id in moving.contains(id) ? nil : id }
            guard memberParent == parent?.id else { return false }
            if parent == nil, let area { return epicOf[member.id] == area }
            return true
        }.sorted { key($0) < key($1) }
        let rank = peers.filter { key($0) < Double(clamped) }.count

        let grouped = area.map { headerRow[$0] != nil } ?? false
        let depth = parent.map { self.depth(of: $0.id) + 1 } ?? (grouped ? 1 : 0)
        // Where it shows: in front of the next peer, or after the last one and everything under it.
        let shownSlot: Int
        let row: Int
        func rowAfter(_ itemIndex: Int) -> Int {
            itemIndex > 0 ? (rowOf[shown[itemIndex - 1].id] ?? rowsShown.count - 1) + 1 : 0
        }
        if rank < peers.count {
            let next = peers[rank]
            shownSlot = Int(key(next).rounded(.up))
            if parent == nil, area == nil, let group = groupOf[next.id], let header = headerRow[group] {
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
            shownSlot = last.map { $0 + 1 } ?? Int((headerAt[area] ?? Double(shown.count)).rounded(.up))
            row = last.map { rowAfter($0 + 1) } ?? (headerRow[area].map { $0 + 1 } ?? rowsShown.count)
        } else if area != nil, let alone = peers.last {
            // After the other issue of its epic, and what hangs under it.
            var end = Int(position(of: alone.id)) + 1
            while end < shown.count, self.depth(of: shown[end].id) > self.depth(of: alone.id) { end += 1 }
            shownSlot = end
            row = rowAfter(end)
        } else {
            shownSlot = shown.count
            row = rowsShown.count
        }
        return Landing(
            peers: peers, rank: rank, parentId: parent?.id, epic: area, slot: min(shownSlot, shown.count),
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

    /// The rows shown, without `item` and what hangs under it, epic headers included.
    func rows(without item: Item) -> [Nesting.Row] {
        nesting.rows(without: nesting.descendants(of: item.id).union([item.id]))
    }

    /// The issues of an epic's group here, folded ones included, in reading order.
    func members(of group: Nesting.EpicGroup) -> [Item] {
        nesting.members.filter { nesting.groupOf[$0.id] == group.contentId }
    }

    /// Where the issues `moving`, an epic's group, land when the group is dropped at `index` among the column's
    /// issues as shown without them.
    func landing(ofGroup epic: String, moving: Set<String>, at index: Int) -> Nesting.Landing {
        nesting.landing(ofGroup: epic, moving: moving, at: index, shown: items.filter { !moving.contains($0.id) })
    }
}
