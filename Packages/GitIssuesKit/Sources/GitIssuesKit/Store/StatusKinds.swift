import Foundation
import Observation

/// The kind each status was given in the app, where its name says otherwise: Backlog, Todo, In Progress, Done or
/// Canceled, which draws its circle and says whether an issue in it is closed. GitHub has no place for it, so it lives in
/// iCloud's key-value store, like project icons (`ProjectLooks`), and is mirrored on the device for builds without
/// iCloud. A status without one has the kind its name suggests (`StatusCategory.infer`).
@MainActor
@Observable
public final class StatusKinds {
    /// One record per status, with when it last changed: iCloud keeps the last write per key, and a device that changed
    /// a kind while offline keeps its change when it is the newer one. No kind means back to the name's.
    struct Record: Codable, Equatable, Sendable {
        var kind: Int?
        var modified: Date
    }

    /// By "projectId/optionId": GitHub gives every project's default options the same ids.
    private(set) var records: [String: Record] = [:]

    /// Called when a kind changed, here or on another device.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let prefix = "statusKind."
    private static let mirrorKey = "statusKinds"

    /// `persistent: false` keeps everything in memory, starting from `initial`, for the sample data and tests.
    public init(persistent: Bool, initial: [String: StatusCategory] = [:]) {
        cloud = persistent ? NSUbiquitousKeyValueStore.default : nil
        defaults = persistent ? .standard : nil
        guard persistent else {
            records = initial.mapValues { Record(kind: $0.rawValue, modified: .distantPast) }
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

    static func key(projectId: String, optionId: String) -> String { "\(projectId)/\(optionId)" }

    /// The kind chosen for a status, nil when it goes by its name.
    public func kind(projectId: String, optionId: String) -> StatusCategory? {
        records[Self.key(projectId: projectId, optionId: optionId)]?.kind.flatMap(StatusCategory.init(rawValue:))
    }

    /// Gives a status a kind, or nil to let its name say again.
    public func set(_ kind: StatusCategory?, projectId: String, optionId: String) {
        guard kind != self.kind(projectId: projectId, optionId: optionId) else { return }
        let key = Self.key(projectId: projectId, optionId: optionId)
        let record = Record(kind: kind?.rawValue, modified: Date())
        records[key] = record
        save(key, record)
        onChange()
    }

    // MARK: Storage

    private func save(_ key: String, _ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        cloud?.set(data, forKey: Self.prefix + key)
        guard let defaults else { return }
        var mirror = defaults.dictionary(forKey: Self.mirrorKey) as? [String: Data] ?? [:]
        mirror[key] = data
        defaults.set(mirror, forKey: Self.mirrorKey)
    }

    /// Takes what other devices wrote when it is newer, and hands them what this one has that is newer.
    private func mergeFromCloud() {
        guard let cloud else { return }
        var seen = Set<String>()
        var changed = false
        for (cloudKey, value) in cloud.dictionaryRepresentation where cloudKey.hasPrefix(Self.prefix) {
            let key = String(cloudKey.dropFirst(Self.prefix.count))
            seen.insert(key)
            guard let data = value as? Data, let theirs = try? JSONDecoder().decode(Record.self, from: data) else { continue }
            if let mine = records[key], mine.modified >= theirs.modified {
                if mine != theirs { save(key, mine) }
            } else {
                changed = changed || records[key]?.kind != theirs.kind
                records[key] = theirs
                save(key, theirs)
            }
        }
        // Written here while iCloud wasn't reachable.
        for (key, record) in records where !seen.contains(key) {
            save(key, record)
        }
        if changed { onChange() }
    }
}
