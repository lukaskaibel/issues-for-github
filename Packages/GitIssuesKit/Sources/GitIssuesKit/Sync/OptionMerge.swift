import Foundation

/// A change to a single-select field's options, such as a project's statuses, made again on top of the options GitHub
/// has now. GitHub takes the whole list at once and drops every option left out of it, and with it every card's value
/// of that option. The app's copy can be behind, as when a status was just added on github.com, so the list sent is
/// never the app's own: it is GitHub's, with the change made to it.
public enum OptionMerge {
    /// `base` is the list as the app had it when the change was made, `mine` the list the change leaves (new options
    /// without an id), `theirs` the list GitHub has now.
    /// - An option only GitHub added stays, after the option before it there.
    /// - An option GitHub removed stays removed, even when it was changed here.
    /// - An option removed here goes, even when GitHub changed it.
    /// - A name, colour or description changed here wins; otherwise GitHub's stays.
    /// - A new option whose name GitHub already has, made there or by an earlier save of the same option, takes that
    ///   one instead of making a second.
    /// - The order is the change's own when it moved options, otherwise GitHub's, with new options after the option
    ///   before them in the change, or at the end when the change put them there.
    public static func merge(base: [RemoteOption], mine: [RemoteOption], theirs: [RemoteOption]) -> [RemoteOption] {
        let was = byId(base)
        let now = byId(theirs)
        let kept = Set(mine.compactMap(\.id))
        let removedHere = Set(was.keys).subtracting(kept)

        // Options that are new here but which GitHub has by now, by name.
        var adopted: [Int: RemoteOption] = [:]
        var taken = Set<String>()
        for (index, option) in mine.enumerated() where option.id == nil {
            let match = theirs.first { candidate in
                guard let id = candidate.id, was[id] == nil, !kept.contains(id), !taken.contains(id) else { return false }
                return sameName(candidate.name, option.name)
            }
            if let match, let id = match.id {
                adopted[index] = match
                taken.insert(id)
            }
        }

        /// One of mine as GitHub has it, with what was changed here; nil when GitHub no longer has it.
        func resolved(_ option: RemoteOption) -> RemoteOption? {
            guard let id = option.id else { return option }
            guard var current = now[id] else { return nil }
            let before = was[id]
            if option.name != before?.name { current.name = option.name }
            if option.color != before?.color { current.color = option.color }
            if option.descr != before?.descr { current.descr = option.descr }
            return current
        }

        let mineInOrder = mine.compactMap(\.id).filter { was[$0] != nil }
        let baseInOrder = base.compactMap(\.id).filter { kept.contains($0) }
        if mineInOrder != baseInOrder {
            // Moved here: the change's order, with what GitHub added since in its place there.
            var result = mine.enumerated().compactMap { index, option in adopted[index] ?? resolved(option) }
            for (index, option) in theirs.enumerated() {
                guard let id = option.id, was[id] == nil, !kept.contains(id), !taken.contains(id) else { continue }
                insert(option, after: theirs[..<index], into: &result)
            }
            return result
        }
        // GitHub's order, with the options made here after the one before them in the change.
        var result = theirs.compactMap { option -> RemoteOption? in
            guard let id = option.id, !removedHere.contains(id) else { return nil }
            if let changed = mine.first(where: { $0.id == id }) { return resolved(changed) }
            return option
        }
        for (index, option) in mine.enumerated() where option.id == nil && adopted[index] == nil {
            // Added at the end stays at the end, after what GitHub added too.
            if !mine[(index + 1)...].contains(where: { $0.id != nil }) {
                result.append(option)
                continue
            }
            let before = mine[..<index].enumerated().map { offset, earlier in adopted[offset] ?? earlier }
            insert(option, after: before[...], into: &result)
        }
        return result
    }

    /// Whether two option names are the same to a person: GitHub tells "Done" and "done" apart, but a board with both
    /// would be a mistake.
    public static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    private static func byId(_ options: [RemoteOption]) -> [String: RemoteOption] {
        var result: [String: RemoteOption] = [:]
        for option in options {
            if let id = option.id, result[id] == nil { result[id] = option }
        }
        return result
    }

    /// Puts `option` right after the last of `earlier` that is in `result`, or first when none is.
    private static func insert(_ option: RemoteOption, after earlier: ArraySlice<RemoteOption>, into result: inout [RemoteOption]) {
        func same(_ a: RemoteOption, _ b: RemoteOption) -> Bool {
            if let id = a.id, let other = b.id { return id == other }
            return a.id == nil && b.id == nil && sameName(a.name, b.name)
        }
        for previous in earlier.reversed() {
            if let found = result.firstIndex(where: { same($0, previous) }) {
                result.insert(option, at: found + 1)
                return
            }
        }
        result.insert(option, at: 0)
    }
}
