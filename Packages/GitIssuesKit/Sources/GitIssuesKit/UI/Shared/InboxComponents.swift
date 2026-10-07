import SwiftUI

/// Parts of the Inbox that look the same on the Mac, iPhone and iPad.

extension InboxSummary.Sign {
    /// The small sign on the avatar that says what happened, without reading.
    var systemImage: String {
        switch self {
        case .assigned: "person.fill.badge.plus"
        case .mentioned: "at"
        case .commented: "bubble.left.fill"
        case .comments: "bubble.left.and.bubble.right.fill"
        case .reviewRequested: "eye.fill"
        case .approved: "checkmark"
        case .changesRequested: "exclamationmark"
        case .completed: "checkmark"
        case .notPlanned: "xmark"
        case .reopened: "arrow.counterclockwise"
        case .merged: "arrow.triangle.merge"
        case .opened: "plus"
        case .statusChanged: "arrow.right"
        case .activity: "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .assigned, .mentioned, .completed, .merged: Theme.accent
        case .reviewRequested, .approved, .reopened, .opened: Theme.positive
        case .changesRequested: Theme.warning
        case .statusChanged: Theme.started
        case .commented, .comments: Theme.textSecondary
        case .notPlanned, .activity: Theme.textTertiary
        }
    }

    /// How VoiceOver names the kind of entry.
    var spoken: String {
        switch self {
        case .assigned: "Assigned"
        case .mentioned: "Mention"
        case .commented, .comments: "Comment"
        case .reviewRequested: "Review requested"
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .completed: "Completed"
        case .notPlanned: "Closed"
        case .reopened: "Reopened"
        case .merged: "Merged"
        case .opened: "New issue"
        case .statusChanged: "Status changed"
        case .activity: "Activity"
        }
    }
}

/// Who did it, with what they did as a small sign in the corner. The sign sits on a ring of the row's own
/// background, so it reads as cut out of the avatar.
struct InboxAvatar: View {
    var summary: InboxSummary
    var size: CGFloat = 24
    var ground: Color = Theme.panel

    var body: some View {
        let badge = (size * 0.62).rounded()
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let actor = summary.actor {
                    Avatar(login: actor.login, url: actor.avatarUrl, size: size)
                } else {
                    // GitHub said something happened, not who did it.
                    Circle().fill(Theme.control)
                        .overlay(Image(systemName: "bell.fill").font(.system(size: size * 0.42)).foregroundStyle(Theme.textTertiary))
                        .frame(width: size, height: size)
                }
            }
            .frame(width: size, height: size, alignment: .topLeading)
            Image(systemName: summary.sign.systemImage)
                .font(.system(size: badge * 0.56, weight: .bold))
                .foregroundStyle(summary.sign.color)
                .frame(width: badge, height: badge)
                .background(Circle().fill(ground))
                .offset(x: badge * 0.3, y: badge * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The issue's state where its row shows a status: its column on a board, else GitHub's open, closed or merged.
struct InboxSubjectIcon: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry
    var item: Item?

    var body: some View {
        if let item, item.isOnBoard, item.statusId != nil {
            StatusIcon(glyph: model.glyph(of: item))
        } else if entry.isPullRequest {
            Image(systemName: entry.state == "MERGED" ? "arrow.triangle.merge" : "arrow.triangle.pull")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.state == "MERGED" ? Theme.accent : entry.state == "CLOSED" ? Theme.textTertiary : Theme.positive)
                .frame(width: 14, height: 14)
        } else {
            StatusIcon(glyph: openClosedGlyph)
        }
    }

    /// As a sub-issue that isn't on the board shows it: open, done or not planned.
    private var openClosedGlyph: StatusGlyph {
        switch (entry.state, entry.stateReason) {
        case ("CLOSED", "NOT_PLANNED"), ("CLOSED", "DUPLICATE"): StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary)
        case ("CLOSED", _): StatusGlyph(category: .completed, progress: 1, color: Theme.accent)
        default: StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody)
        }
    }
}

/// "now", "12m", "3h", "Yesterday", "Mon", "Oct 3": as short as the Inbox's time column, as in Linear.
func inboxTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if calendar.isDateInToday(date) || seconds < 6 * 3600 { return "\(Int(seconds / 3600))h" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
    if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
    return date.formatted(.dateTime.month(.abbreviated).day().year())
}

extension InboxEntry {
    /// What VoiceOver reads for a row.
    func spoken(_ summary: InboxSummary, unread: Bool) -> String {
        var parts: [String] = []
        if unread { parts.append("Unread") }
        parts.append(summary.sign.spoken)
        parts.append("\(displayNumber(withRepo: false)) \(title)")
        parts.append([summary.lead, summary.excerpt].compactMap { $0 }.joined(separator: " "))
        parts.append(updatedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: ", ")
    }
}

extension AppModel {
    /// "#12" for an issue on a board, "website#12" for one that isn't, or that is on a board from a repository
    /// the board doesn't otherwise use, so you know where it lives.
    func inboxNumber(_ entry: InboxEntry, item: Item?) -> String {
        entry.displayNumber(withRepo: inboxNamesRepository(item))
    }

    func inboxNamesRepository(_ item: Item?) -> Bool {
        guard let item, item.isOnBoard else { return true }
        return repo(of: item) == nil
    }

    /// The heading of what happened on the issue: news since you last read it, or what happened lately.
    func inboxNewsTitle(_ entry: InboxEntry) -> String {
        guard entry.activityIsNew else { return "Latest activity" }
        guard let since = entry.activitySince else { return "New" }
        if Calendar.current.isDateInToday(since) { return "New since \(since.formatted(.dateTime.hour().minute()))" }
        if Calendar.current.isDateInYesterday(since) { return "New since yesterday" }
        return "New since \(since.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// One line of what happened, for the list at the top of the issue.
    func inboxEventLine(_ event: InboxActivity, entry: InboxEntry) -> String {
        let me = viewer?.login.lowercased()
        func whom(_ login: String?) -> String { login?.lowercased() == me ? "you" : (login ?? "someone") }
        switch event.kind {
        case .commented: return InboxEntry.mentions(event.text, login: viewer?.login) ? "mentioned you" : "commented"
        case .assigned: return "assigned \(whom(event.detail))"
        case .unassigned: return "unassigned \(whom(event.detail))"
        case .mentioned: return "mentioned you"
        case .opened: return entry.isPullRequest ? "opened this pull request" : "opened the issue"
        case .closed:
            switch event.detail {
            case "NOT_PLANNED": return "closed it as not planned"
            case "DUPLICATE": return "closed it as a duplicate"
            default: return entry.isPullRequest ? "closed it" : "closed it as completed"
            }
        case .reopened: return "reopened it"
        case .merged: return "merged it"
        case .reviewRequested: return event.detail?.lowercased() == me ? "requested your review" : "requested a review from \(event.detail ?? "someone")"
        case .reviewed:
            switch event.detail {
            case "APPROVED": return "approved it"
            case "CHANGES_REQUESTED": return "requested changes"
            default: return "reviewed it"
            }
        case .statusChanged: return "moved it to \(event.detail ?? "another status")\(event.project.map { " in \($0)" } ?? "")"
        }
    }
}
