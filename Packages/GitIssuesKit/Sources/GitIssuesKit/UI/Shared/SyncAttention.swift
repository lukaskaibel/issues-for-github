import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The state of syncing as the dot on the account's avatar shows it.
enum SyncDotStyle: Equatable {
    /// Everything is on GitHub.
    case synced
    /// Changes are waiting to be sent.
    case queued
    /// Changes are going out right now.
    case sending
    /// No connection; changes wait on this device.
    case offline
    /// A conflict to decide or a sync that failed.
    case attention
}

/// Something about syncing the user has to know or act on, shown as a card at the bottom of the sidebar.
/// Everything else (synced, sending) stays a dot on the avatar.
enum SyncAttention: Hashable {
    case conflict(count: Int, number: String, itemId: String?)
    case failed(String)
    case offline(pending: Int)

    var title: String {
        switch self {
        case .conflict(let count, _, _): count == 1 ? "1 change needs your decision" : "\(count) changes need your decision"
        case .failed: "Sync problem"
        case .offline: "Offline"
        }
    }

    @MainActor
    var message: String {
        switch self {
        case .conflict(let count, let number, _):
            return count == 1 ? "\(number) was edited on GitHub too." : "They were edited on GitHub too."
        case .failed(let message):
            return message
        case .offline(let pending):
            if pending == 0 { return "Changes are saved on this \(Platform.deviceName) and sent when you’re back online." }
            return pending == 1
                ? "1 change waits here and goes out when you’re back online."
                : "\(pending) changes wait here and go out when you’re back online."
        }
    }

    /// The button on the card, if there is something to do.
    var actionTitle: String? {
        switch self {
        case .conflict(_, _, let itemId): itemId == nil ? nil : "Review"
        case .failed: "Try Again"
        case .offline(let pending): pending > 0 ? "Show Changes" : nil
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .conflict, .failed: "exclamationmark.triangle"
        }
    }
}

extension AppModel {
    var syncDotStyle: SyncDotStyle {
        #if DEBUG
        switch debugSyncAttention {
        case .offline?: return .offline
        case .conflict?, .failed?: return .attention
        case nil: break
        }
        #endif
        if outbox.contains(where: { $0.state == .conflict }) { return .attention }
        switch status.phase {
        case .failed, .unauthorized: return .attention
        case .offline: return .offline
        case .syncing: return .sending
        case .idle: return pendingCount > 0 ? .queued : .synced
        }
    }

    var syncAttention: SyncAttention? {
        #if DEBUG
        if let forced = debugSyncAttention { return forced }
        #endif
        let conflicts = outbox.filter { $0.state == .conflict }
        if let first = conflicts.first {
            let mutation = first.mutation
            return .conflict(
                count: conflicts.count,
                number: summary(of: first).number,
                itemId: mutation.itemId.flatMap { item(id: $0)?.id } ?? mutation.contentId.flatMap { item(contentId: $0)?.id }
            )
        }
        switch status.phase {
        case .failed(let message): return .failed(message)
        case .offline: return .offline(pending: pendingCount)
        case .idle, .syncing, .unauthorized: return nil
        }
    }

    #if DEBUG
    /// A state to show instead of the real one, for checking the cards on a device without a debug remote:
    /// launch with `-debugSyncAttention offline|offline0|conflict|failed`.
    private var debugSyncAttention: SyncAttention? {
        switch UserDefaults.standard.string(forKey: "debugSyncAttention") {
        case "offline": .offline(pending: 3)
        case "offline0": .offline(pending: 0)
        case "conflict": .conflict(count: 1, number: "#15", itemId: allItems.first { $0.number == 15 }?.id)
        case "failed": .failed("The network connection was lost.")
        default: nil
        }
    }
    #endif

    /// The account and how syncing is going, for the avatar's tooltip and accessibility.
    func accountSummary(at now: Date = Date()) -> String {
        "\(viewer?.login ?? "GitHub") · \(syncLine(at: now))"
    }
}

extension Platform {
    /// "Mac", "iPad" or "iPhone", for text that talks about this device.
    @MainActor
    static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

/// The dot for the state of syncing: green when everything is on GitHub, the accent while changes wait or go out,
/// a hollow amber ring offline, and amber when something needs you.
struct SyncDot: View {
    var style: SyncDotStyle
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch style {
            case .synced:
                Circle().fill(Theme.positive)
            case .queued:
                Circle().fill(Theme.accent)
            case .sending:
                if reduceMotion {
                    Circle().fill(Theme.accent)
                } else {
                    PhaseAnimator([1.0, 0.35]) { opacity in
                        Circle().fill(Theme.accent).opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.7)
                    }
                }
            case .offline:
                Circle().strokeBorder(Theme.warning, lineWidth: max(1.5, size * 0.2))
            case .attention:
                Circle().fill(Theme.warning)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The signed-in person's avatar, or a placeholder until it is known.
struct AccountAvatar: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat

    var body: some View {
        if let viewer = model.viewer {
            Avatar(login: viewer.login, url: viewer.avatarUrl, size: size)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: size, height: size)
        }
    }
}

/// The account's avatar with the state of syncing as a dot cut into its lower right corner, as Linear marks
/// presence. The cut-out shows whatever is behind, so it works on any background and on hover.
struct StatusAvatar: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat
    /// Shows this state instead of the current one, for checking how each looks.
    var style: SyncDotStyle?

    var body: some View {
        let dot = (size * 0.4).rounded()
        let gap = (size * 0.09).rounded(.up)
        // The dot reaches a little past the avatar's edge.
        let outset = (dot * 0.25).rounded()
        AccountAvatar(size: size)
            .mask {
                Rectangle()
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .frame(width: dot + gap * 2, height: dot + gap * 2)
                            .offset(x: outset + gap, y: outset + gap)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .overlay(alignment: .bottomTrailing) {
                SyncDot(style: style ?? model.syncDotStyle, size: dot)
                    .offset(x: outset, y: outset)
            }
            .animation(Theme.quick, value: model.syncDotStyle)
            // The avatar's own tooltip names only the person; the button around it says how syncing is going.
            .allowsHitTesting(false)
    }
}
