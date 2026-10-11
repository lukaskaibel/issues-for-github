import Foundation

/// How a column of the board or a group of the list shows sub-issues. A sub-issue whose parent is in the same
/// group hangs right under it, indented, so a parent and the sub-issues being worked on with it read as one. A
/// sub-issue whose parent is anywhere else stands on its own and names its parent.
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

    func place(of id: String) -> Place {
        places[id] ?? Place()
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
        return (shown, nesting)
    }

    // MARK: Dropping an issue into the group

    /// Where an issue lands when it is dropped into this group.
    struct Landing: Equatable {
        /// The issues it takes its place among, in board order: the other sub-issues of its parent here, or the
        /// group's issues that stand on their own.
        var peers: [Item]
        /// How many of `peers` come before it.
        var rank: Int
        /// The parent it hangs under here, by item id.
        var parentId: String?
        /// Where it shows among `shown`, and how deep.
        var slot: Int
        var depth: Int
    }

    /// Where `item` lands when dropped at `slot` among `shown`, the group's issues as shown without the item and
    /// what hangs under it. A sub-issue whose parent is here always joins its parent's sub-issues; any other issue
    /// goes in front of or after another one that stands on its own, never between a parent and its sub-issues.
    func landing(of item: Item, at slot: Int, shown: [Item]) -> Landing {
        let moving = descendants(of: item.id).union([item.id])
        let parent = members.first { member in
            !moving.contains(member.id) && member.contentId != nil && member.contentId == item.parentId
        }
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
        // Issues under the one moving come along with it, and issues it is the parent of will hang under it.
        let peers = members.filter { member in
            guard !moving.contains(member.id), member.id != parent?.id else { return false }
            if let contentId = item.contentId, member.parentId == contentId { return false }
            let memberParent = parents[member.id].flatMap { id in moving.contains(id) ? nil : id }
            return memberParent == parent?.id
        }
        let clamped = min(max(slot, 0), shown.count)
        let rank = peers.filter { position(of: $0.id) < Double(clamped) }.count

        // Where it shows: in front of the next peer, or after the last one and everything under it.
        let depth = parent.map { self.depth(of: $0.id) + 1 } ?? 0
        let shownSlot: Int
        if rank < peers.count {
            shownSlot = Int(position(of: peers[rank].id).rounded(.up))
        } else if let parent, let start = index[parent.id] {
            var end = Int(start) + 1
            while end < shown.count, self.depth(of: shown[end].id) >= depth { end += 1 }
            shownSlot = end
        } else {
            shownSlot = shown.count
        }
        return Landing(peers: peers, rank: rank, parentId: parent?.id, slot: min(shownSlot, shown.count), depth: depth)
    }
}

extension BoardColumn {
    /// The cards shown, without `item` and what hangs under it: what a card being moved is dropped among.
    func shown(without item: Item) -> [Item] {
        let moving = nesting.descendants(of: item.id).union([item.id])
        return items.filter { !moving.contains($0.id) }
    }

    /// Where `item` lands when dropped at `index` among `shown(without: item)`.
    func landing(of item: Item, at index: Int) -> Nesting.Landing {
        nesting.landing(of: item, at: index, shown: shown(without: item))
    }
}
