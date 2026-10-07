import Foundation
import Observation

/// Something the user should know about a change made elsewhere or a change that could not be saved.
public struct Notice: Identifiable, Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// Offer to adopt the value GitHub had, e.g. "Switch to In Progress".
        case applyField(Mutation.SetField, label: String)
        /// Offer to adopt the due date GitHub had.
        case applyDate(Mutation.SetDate, label: String)
        case openItem(String)

        /// The button that takes GitHub's value, for the actions that offer one.
        public var adoptLabel: String? {
            switch self {
            case .applyField(_, let label), .applyDate(_, let label): label
            case .openItem: nil
            }
        }
    }

    public var id = UUID()
    public var title: String
    public var message: String
    public var isWarning = false
    public var action: Action?

    public init(title: String, message: String, isWarning: Bool = false, action: Action? = nil) {
        self.title = title
        self.message = message
        self.isWarning = isWarning
        self.action = action
    }
}

/// What the sync engine is doing, for the sidebar indicator and the toasts.
@MainActor
@Observable
public final class SyncStatus {
    public enum Phase: Equatable, Sendable {
        case idle
        case syncing
        case offline
        case unauthorized
        case failed(String)
    }

    public var phase: Phase = .idle
    public var lastSyncedAt: Date?
    public var notices: [Notice] = []
    /// Temporary ids that have since been replaced by GitHub's, so open views can follow along.
    public var idRemaps: [String: String] = [:]

    public init() {}

    public func post(_ notice: Notice) {
        notices.append(notice)
        if notices.count > 4 { notices.removeFirst(notices.count - 4) }
    }

    public func dismiss(_ id: Notice.ID) {
        notices.removeAll { $0.id == id }
    }
}
