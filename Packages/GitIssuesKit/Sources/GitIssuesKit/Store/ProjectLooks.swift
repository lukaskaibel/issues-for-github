import Foundation
import Observation

/// How a project shows in the app: a glyph in one of GitHub's option colours. GitHub has no icon for a project, so
/// this one is the app's own. It starts as GitHub's table in grey, as quiet as a repository's book.
public struct ProjectLook: Codable, Hashable, Sendable {
    public var glyph: ProjectGlyph
    /// One of GitHub's option colours (`Defaults.optionColors`). "GRAY" is the grey of secondary text.
    public var color: String

    public static let standard = ProjectLook(glyph: .table, color: "GRAY")

    public init(glyph: ProjectGlyph, color: String) {
        self.glyph = glyph
        self.color = color
    }
}

/// Each project's look. It lives in iCloud's key-value store, so the user's Mac, iPhone and iPad show a project the
/// same, and is mirrored on the device for builds without iCloud. The sample data keeps it in memory only.
@MainActor
@Observable
public final class ProjectLooks {
    /// One record per project, with when it last changed: iCloud keeps the last write per key, and a device that
    /// changed a look while offline keeps its change when it is the newer one.
    struct Record: Codable, Equatable, Sendable {
        var look: ProjectLook
        var modified: Date
    }

    private(set) var records: [String: Record] = [:]

    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let prefix = "projectLook."
    private static let mirrorKey = "projectLooks"

    /// `persistent: false` keeps everything in memory, starting from `initial`, for the sample data and tests.
    public init(persistent: Bool, initial: [String: ProjectLook] = [:]) {
        cloud = persistent ? NSUbiquitousKeyValueStore.default : nil
        defaults = persistent ? .standard : nil
        guard persistent else {
            records = initial.mapValues { Record(look: $0, modified: .distantPast) }
            return
        }
        for (key, data) in defaults?.dictionary(forKey: Self.mirrorKey) as? [String: Data] ?? [:] {
            if let record = try? JSONDecoder().decode(Record.self, from: data) { records[key] = record }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeFromCloud() }
        }
        cloud?.synchronize()
        mergeFromCloud()
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func look(_ projectId: String) -> ProjectLook {
        records[projectId]?.look ?? .standard
    }

    public func set(_ look: ProjectLook, for projectId: String) {
        guard look != self.look(projectId) else { return }
        // Going back to the table in grey is a record too, so other devices follow.
        let record = Record(look: look, modified: Date())
        records[projectId] = record
        save(projectId, record)
    }

    // MARK: Storage

    private func save(_ projectId: String, _ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        cloud?.set(data, forKey: Self.prefix + projectId)
        guard let defaults else { return }
        var mirror = defaults.dictionary(forKey: Self.mirrorKey) as? [String: Data] ?? [:]
        mirror[projectId] = data
        defaults.set(mirror, forKey: Self.mirrorKey)
    }

    /// Takes what other devices wrote when it is newer, and hands them what this one has that is newer.
    private func mergeFromCloud() {
        guard let cloud else { return }
        var seen = Set<String>()
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(Self.prefix) {
            let projectId = String(key.dropFirst(Self.prefix.count))
            seen.insert(projectId)
            guard let data = value as? Data, let theirs = try? JSONDecoder().decode(Record.self, from: data) else { continue }
            if let mine = records[projectId], mine.modified >= theirs.modified {
                if mine != theirs { save(projectId, mine) }
            } else {
                records[projectId] = theirs
                save(projectId, theirs)
            }
        }
        // Written here while iCloud wasn't reachable.
        for (projectId, record) in records where !seen.contains(projectId) {
            save(projectId, record)
        }
    }
}
