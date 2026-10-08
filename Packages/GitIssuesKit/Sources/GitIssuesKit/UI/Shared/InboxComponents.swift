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
        case .due, .overdue: "calendar"
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
        case .due: Theme.urgent
        case .overdue: Theme.overdue
        }
    }

    /// How VoiceOver names the kind of entry.
    var spoken: String {
        let kind: LocalizedStringResource = switch self {
        case .assigned: .inboxKindAssigned
        case .mentioned: .inboxKindMention
        case .commented, .comments: .inboxKindComment
        case .reviewRequested: .inboxKindReviewRequested
        case .approved: .inboxKindApproved
        case .changesRequested: .inboxKindChangesRequested
        case .completed: .inboxKindCompleted
        case .notPlanned: .inboxKindClosed
        case .reopened: .inboxKindReopened
        case .merged: .inboxKindMerged
        case .opened: .inboxKindNewIssue
        case .statusChanged: .inboxKindStatusChanged
        case .activity: .inboxKindActivity
        case .due: .inboxKindDueToday
        case .overdue: .inboxKindOverdue
        }
        return String(localized: kind)
    }

    /// An entry the app made from a due date rather than one GitHub sent.
    var isDue: Bool { self == .due || self == .overdue }
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
                if summary.sign.isDue {
                    // Nobody did anything: the day came. A calendar in the colour of how near it is.
                    Circle().fill(summary.sign.color.opacity(0.14))
                        .overlay(Image(systemName: "calendar").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(summary.sign.color))
                        .frame(width: size, height: size)
                } else if let actor = summary.actor {
                    Avatar(login: actor.login, url: actor.avatarUrl, size: size)
                } else {
                    // GitHub said something happened, not who did it.
                    Circle().fill(Theme.control)
                        .overlay(Image(systemName: "bell.fill").font(.system(size: size * 0.42)).foregroundStyle(Theme.textTertiary))
                        .frame(width: size, height: size)
                }
            }
            .frame(width: size, height: size, alignment: .topLeading)
            if !summary.sign.isDue {
                Image(systemName: summary.sign.systemImage)
                    .font(.system(size: badge * 0.56, weight: .bold))
                    .foregroundStyle(summary.sign.color)
                    .frame(width: badge, height: badge)
                    .background(Circle().fill(ground))
                    .offset(x: badge * 0.3, y: badge * 0.3)
            }
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
    if seconds < 60 { return String(localized: .inboxTimeNow) }
    if seconds < 3600 { return String(localized: .inboxTimeMinutes(minutes: Int(seconds / 60))) }
    if calendar.isDate(date, inSameDayAs: now) || seconds < 6 * 3600 { return String(localized: .inboxTimeHours(hours: Int(seconds / 3600))) }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
        return String(localized: .yesterday)
    }
    if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
    if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
    return date.formatted(.dateTime.month(.abbreviated).day().year())
}

extension InboxEntry {
    /// What VoiceOver reads for a row.
    func spoken(_ summary: InboxSummary, unread: Bool) -> String {
        var parts: [String] = []
        if unread { parts.append(String(localized: .unreadEntry)) }
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
        guard entry.activityIsNew else { return String(localized: .inboxLatestActivity) }
        guard let since = entry.activitySince else { return String(localized: .inboxNew) }
        if Calendar.current.isDateInToday(since) {
            return String(localized: .inboxNewSinceTime(time: since.formatted(.dateTime.hour().minute())))
        }
        if Calendar.current.isDateInYesterday(since) { return String(localized: .inboxNewSinceYesterday) }
        return String(localized: .inboxNewSinceDate(date: since.formatted(.dateTime.month(.abbreviated).day())))
    }

    /// One line of what happened, for the list at the top of the issue, naming who did it: "Kai commented".
    func inboxEventLine(_ event: InboxActivity, entry: InboxEntry, name: String) -> String {
        let me = viewer?.login.lowercased()
        /// Done to you, to someone named, or to someone GitHub doesn't name: a sentence for each.
        func whom(
            _ login: String?, you: LocalizedStringResource, named: (String) -> LocalizedStringResource, someone: LocalizedStringResource
        ) -> LocalizedStringResource {
            guard let login else { return someone }
            return login.lowercased() == me ? you : named(login)
        }
        let line: LocalizedStringResource
        switch event.kind {
        case .commented:
            line = InboxEntry.mentions(event.text, login: viewer?.login)
                ? .eventMentionedYou(name: name) : .eventCommented(name: name)
        case .assigned:
            line = whom(
                event.detail, you: .eventAssignedYou(name: name),
                named: { .eventAssignedPerson(name: name, login: $0) }, someone: .eventAssignedSomeone(name: name)
            )
        case .unassigned:
            line = whom(
                event.detail, you: .eventUnassignedYou(name: name),
                named: { .eventUnassignedPerson(name: name, login: $0) }, someone: .eventUnassignedSomeone(name: name)
            )
        case .mentioned:
            line = .eventMentionedYou(name: name)
        case .opened:
            line = entry.isPullRequest ? .eventOpenedPullRequest(name: name) : .eventOpenedIssue(name: name)
        case .closed:
            switch event.detail {
            case "NOT_PLANNED": line = .eventClosedNotPlanned(name: name)
            case "DUPLICATE": line = .eventClosedDuplicate(name: name)
            default: line = entry.isPullRequest ? .eventClosedPullRequest(name: name) : .eventClosedCompleted(name: name)
            }
        case .reopened:
            line = .eventReopened(name: name)
        case .merged:
            line = .eventMerged(name: name)
        case .reviewRequested:
            line = whom(
                event.detail, you: .eventRequestedYourReview(name: name),
                named: { .eventRequestedReviewFrom(name: name, login: $0) }, someone: .eventRequestedReviewFromSomeone(name: name)
            )
        case .reviewed:
            switch event.detail {
            case "APPROVED": line = .eventApproved(name: name)
            case "CHANGES_REQUESTED": line = .eventRequestedChanges(name: name)
            default: line = .eventReviewed(name: name)
            }
        case .statusChanged:
            line = switch (event.detail, event.project) {
            case let (status?, project?): .eventMovedToStatusInProject(name: name, status: status, project: project)
            case let (status?, nil): .eventMovedToStatus(name: name, status: status)
            case let (nil, project?): .eventMovedToAnotherStatusInProject(name: name, project: project)
            case (nil, nil): .eventMovedToAnotherStatus(name: name)
            }
        }
        return String(localized: line)
    }
}

/// A sentence with the name of who did something set off, wherever the language puts it: "**Kai** commented".
func sentence(_ text: String, emphasizing name: String, _ style: (Text) -> Text) -> Text {
    guard let range = text.range(of: name) else { return Text(text) }
    return Text("\(Text(text[..<range.lowerBound]))\(style(Text(name)))\(Text(text[range.upperBound...]))")
}
