#if os(macOS)
import AppKit
import SwiftUI

/// The Inbox on the Mac, as in Mail: the notifications on the left, the issue of the selected one on the right, and
/// what can be done to it in the toolbar.
struct InboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            InboxList()
                .frame(width: Theme.inboxListWidth)
            Rectangle().fill(Theme.panelBorder).frame(width: 1)
                .ignoresSafeArea(edges: .top)
            InboxPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The Inbox's buttons in the toolbar: for the notification on screen snooze, archive, read, its link, the issue and
/// GitHub, and everything at once under ⋯.
struct InboxToolbarControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            if model.inboxPicked.count <= 1, let entry = model.inboxSelected {
                InboxEntryActions(entry: entry)
            }
            InboxMoreButton()
        }
    }
}

/// For You and Watching, in the middle of the toolbar once something is watched.
struct InboxBuckets: View {
    var body: some View {
        BucketSwitch()
    }
}

extension AppModel {
    var showsInboxBuckets: Bool { !inbox(.watching).isEmpty }
}

/// Snooze, archive, read or unread, the link, the issue full size and GitHub, in one piece of glass as Mail groups
/// them. Icons only, so they fit beside search with For You and Watching in the middle.
private struct InboxEntryActions: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry

    var body: some View {
        let item = model.inboxItem(for: entry)
        let unread = model.isUnread(entry)
        HStack(spacing: 0) {
            SnoozeButton(entries: [entry])
            ToolbarIconButton(systemImage: "archivebox", label: .archiveWithShortcut) { model.archive([entry]) }
            ToolbarIconButton(systemImage: unread ? "envelope.open" : "envelope.badge", label: unread ? .markAsReadWithShortcut : .markAsUnreadWithShortcut) {
                model.toggleRead([entry])
            }
            ToolbarIconButton(systemImage: "link", label: .copyLinkWithShortcut) {
                if let url = entry.webURL { model.copyLink(url.absoluteString, for: entry.label) }
            }
            if let item, !item.isDetached {
                ToolbarIconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: .openIssueWithShortcut) { model.open(item) }
            }
            if let url = entry.webURL {
                ToolbarIconButton(systemImage: "arrow.up.right.square", label: .openOnGitHub) { NSWorkspace.shared.open(url) }
            }
        }
    }
}

/// ⋯: everything at once, and GitHub's own Inbox.
private struct InboxMoreButton: View {
    @State private var open = false

    var body: some View {
        ToolbarIconButton(systemImage: "ellipsis", label: .inboxActionsMac) { open = true }
            .dropdown(isPresented: $open) { close in
                InboxActionsMenu(close: close)
            }
    }
}

// MARK: - The list

private struct InboxList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .overlay(alignment: .bottom) {
            if let undo = model.inboxUndo {
                InboxUndoToast(undo: undo)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .animation(Theme.overlay, value: model.inboxUndo)
    }

    @ViewBuilder
    private var content: some View {
        let entries = model.visibleInbox
        if model.inboxMeta.access == .denied {
            EmptyState(
                title: String(localized: .inboxTokenCantReadTitle),
                message: String(localized: .inboxTokenCantReadMessage)
            ) {
                Button(.signInAgain) { model.signOut() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else if model.inboxMeta.access == .unknown, model.inboxEntries.isEmpty {
            if model.status.phase == .offline {
                EmptyState(title: String(localized: .youreOffline), message: String(localized: .inboxOfflineMessage))
            } else {
                EmptyState(
                    title: String(localized: .loadingNotifications), message: String(localized: .fetchingNotifications), showsProgress: true
                )
            }
        } else if entries.isEmpty {
            InboxCaughtUp()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            InboxRow(entry: entry)
                                .id(entry.id)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                        if model.inboxMeta.otherCount > 0 {
                            OtherNotifications(count: model.inboxMeta.otherCount)
                        }
                    }
                    .padding(.vertical, 6)
                    .animation(Theme.spring, value: entries.map(\.id))
                }
                .scrollIndicators(.never)
                .pageUnderToolbar()
                .onChange(of: model.focusScrollToken) {
                    guard let id = model.inboxSelectedId else { return }
                    withAnimation(Theme.quick) { proxy.scrollTo(id) }
                }
            }
        }
    }
}

/// For you and Watching, with what's unread in each, as a segmented control in the toolbar.
private struct BucketSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker(selection: Binding(
            get: { model.currentInboxBucket },
            set: { bucket in
                withAnimation(Theme.spring) {
                    model.inboxBucket = bucket
                    model.inboxPicked = []
                }
            }
        )) {
            ForEach([InboxBucket.forYou, .watching], id: \.self) { bucket in
                let unread = model.inbox(bucket).filter(model.isUnread).count
                Text(unread > 0 ? "\(bucket.title) \(unread)" : bucket.title).tag(bucket)
            }
        } label: {
            Text(.inbox)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// The ⋯ menu: everything at once, and GitHub's own Inbox.
private struct InboxActionsMenu: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void
    @State private var cursor = MenuCursor<Int>()

    private var rows: [(title: LocalizedStringResource, image: String, shortcut: String?, action: () -> Void)] {
        [
            (.markAllAsRead, "circle", "⌥U", { model.markAllRead() }),
            (.archiveAllRead, "archivebox", "⇧⌫", { model.archiveAllRead() }),
            (.openGitHubNotifications, "arrow.up.right.square", nil, {
                if let url = URL(string: "https://github.com/notifications") { NSWorkspace.shared.open(url) }
            }),
        ]
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index == 2 { MenuDivider() }
                MenuRow(
                    title: String(localized: row.title), systemImage: row.image, shortcut: row.shortcut, cursor: cursor, key: index,
                    action: { pick(row.action) }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: 250)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { cursor.step($0, through: Array(rows.indices)) },
            onActivate: { if let active = cursor.key { pick(rows[active].action) } },
            onBack: close
        ))
    }

    private func pick(_ action: () -> Void) {
        close()
        action()
    }
}

/// One notification: who did what to which issue, and when.
private struct InboxRow: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry
    @State private var hovering = false
    @State private var menuRegion = UUID()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let item = model.inboxItem(for: entry)
        let summary = model.inboxSummary(entry)
        let unread = model.isUnread(entry)
        let picked = model.inboxPicked.contains(entry.id)
        let selected = model.inboxSelectedId == entry.id && model.inboxPicked.isEmpty
        // As in Mail: the one on screen in the accent colour, picked ones tinted, the one under the pointer lit.
        let ground = selected ? Theme.accentFill : picked ? Theme.selectionFill : hovering ? Theme.hover : Theme.panel
        let onAccent = selected
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(unread ? (onAccent ? Color.white : Theme.accent) : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 13)
            InboxAvatar(summary: summary, size: 30, ground: ground, signTint: onAccent ? .white : nil)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    line(summary)
                        .font(unread ? .uiSemibold : .ui)
                        .foregroundStyle(onAccent ? Color.white : Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !hovering {
                        Text(inboxTime(entry.updatedAt, now: model.inboxClock))
                            .font(.small)
                            .monospacedDigit()
                            .foregroundStyle(onAccent ? Color.white.opacity(0.8) : Theme.textTertiary)
                    }
                }
                HStack(spacing: 6) {
                    InboxSubjectIcon(entry: entry, item: item, tint: onAccent ? .white : nil)
                    Text(model.inboxNumber(entry, item: item))
                        .font(.small)
                        .monospacedDigit()
                        .foregroundStyle(onAccent ? Color.white.opacity(0.8) : Theme.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(entry.title)
                        .font(.ui)
                        .foregroundStyle(onAccent ? Color.white.opacity(0.92) : unread ? Theme.text : Theme.textBody)
                        .lineLimit(1)
                }
                if let excerpt = summary.excerpt {
                    Text(excerpt)
                        .font(.small)
                        .foregroundStyle(onAccent ? Color.white.opacity(0.8) : Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            if hovering {
                HStack(spacing: 2) {
                    IconButton(systemName: unread ? "circle.inset.filled" : "circle", label: String(localized: unread ? .markAsReadWithShortcut : .markAsUnreadWithShortcut), size: 24) {
                        model.toggleRead(model.inboxTargets(for: entry))
                    }
                    IconButton(systemName: "archivebox", label: String(localized: .archiveWithShortcut), size: 24) {
                        model.archive(model.inboxTargets(for: entry))
                    }
                }
                .environment(\.colorScheme, onAccent ? .dark : colorScheme)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ground))
        .overlay(alignment: .bottom) {
            if !selected, !picked, !hovering {
                Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 56).padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 6)
        // Placed as a whole: without it the avatar, the issue's icon and every text, even one that stays as it is, each
        // take on the hover fade themselves, so they are drawn again on every frame of it, each time waiting for the
        // window server, and the pointer stutters down the Inbox.
        .geometryGroup()
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(Theme.quick) { hovering = inside } }
        .onTapGesture { click() }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            let id = entry.id
            ContextMenus.shared.register(menuRegion, frame: frame) { [model] _ in
                model.inboxEntry(id: id).map { InboxMenuBuilder(model: model, entry: $0).menu() }
            }
        }
        .onDisappear { ContextMenus.shared.remove(menuRegion) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.spoken(summary, unread: unread))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selectInboxEntry(entry) }
        .accessibilityAction(named: unread ? Text(.markAsRead) : Text(.markAsUnread)) { model.toggleRead([entry]) }
        .accessibilityAction(named: Text(.archive)) { model.archive([entry]) }
    }

    /// Who did what, such as "Mira Patel mentioned you"; what they wrote is the line under the issue, so the colon
    /// that led into it goes.
    private func line(_ summary: InboxSummary) -> Text {
        guard summary.excerpt != nil else { return Text(summary.lead) }
        return Text(summary.lead.trimmingCharacters(in: CharacterSet(charactersIn: ":：").union(.whitespaces)))
    }

    /// A click shows the issue; with ⌘ or Shift it picks entries to act on together, as in the list.
    private func click() {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.shift) {
            model.extendInboxPick(to: entry)
        } else if modifiers.contains(.command) {
            model.toggleInboxPick(entry)
        } else {
            model.inboxPicked = []
            model.inboxPickAnchor = entry.id
            model.selectInboxEntry(entry)
        }
    }
}

/// Notifications that aren't about issues stay on GitHub; the list says how many, and where.
private struct OtherNotifications: View {
    var count: Int

    var body: some View {
        Button {
            if let url = URL(string: "https://github.com/notifications") { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 5) {
                Text(.moreOnGitHub(count: count))
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.small)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .help(Text(.otherNotificationsTooltip))
    }
}

private struct InboxCaughtUp: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 6)
            Text(.allCaughtUp).font(.uiSemibold)
            Text(.allCaughtUpMessage)
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InboxUndoToast: View {
    @Environment(AppModel.self) private var model
    var undo: InboxUndo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: undo.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(undo.message).lineLimit(1)
            Button {
                model.undoInbox()
            } label: {
                HStack(spacing: 6) {
                    Text(.undo)
                    Text("⌘Z").foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .font(.ui)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassPanel(in: Capsule())
    }
}

// MARK: - The issue beside it

private struct InboxPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.inboxPicked.count > 1 {
            InboxPickedSummary()
        } else if let entry = model.inboxSelected {
            InboxEntryPane(entry: entry)
                .id(entry.id)
                .transition(.opacity)
        } else {
            EmptyState(
                title: model.visibleInbox.isEmpty ? "" : String(localized: .noNotificationSelected),
                message: model.visibleInbox.isEmpty ? "" : String(localized: .pickNotificationHint)
            )
        }
    }
}

private struct InboxEntryPane: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry

    var body: some View {
        let item = model.inboxItem(for: entry)
        VStack(spacing: 0) {
            if entry.missing {
                EmptyState(
                    title: String(localized: .issueNotAvailable),
                    message: String(localized: .issueNotAvailableMessage)
                ) {
                    HStack(spacing: 8) {
                        Button(.openOnGitHub) { openOnGitHub() }
                            .buttonStyle(SecondaryButtonStyle())
                        Button(.archive) { model.archive([entry]) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else if let item {
                InboxIssue(item: item, entry: entry)
                    .id(item.id)
            } else {
                EmptyState(
                    title: String(localized: .loadingTheIssue), message: String(localized: .readingItFromGitHub),
                    showsProgress: true
                )
            }
        }
    }

    private func openOnGitHub() {
        if let url = entry.webURL { NSWorkspace.shared.open(url) }
    }
}

/// The issue, narrower than the full issue view: what's new on top, its properties as chips under the title, as in
/// the peek. Everything changes in place.
private struct InboxIssue: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var entry: InboxEntry
    @State private var titleLink = TitleLink()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if entry.isDue {
                        DueEntryBanner(entry: entry, item: item)
                    } else if !entry.activity.isEmpty {
                        InboxNews(entry: entry) { commentId in
                            withAnimation(Theme.spring) { proxy.scrollTo(commentId, anchor: .top) }
                        }
                    }
                    ForEach(model.conflict(for: item)) { conflict in
                        ConflictBanner(entry: conflict)
                    }
                    TitleField(item: item, link: titleLink)
                    PropertyChipRow(item: item)
                    DescriptionView(item: item, titleLink: titleLink)
                    if item.kind == .issue, !item.isDetached {
                        SubIssuesSection(item: item)
                    }
                    if item.kind != .draft {
                        ActivitySection(item: item, highlighted: entry.newCommentIds)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .pageUnderToolbar()
            .pageFootBar {
                if item.kind != .draft {
                    CommentComposer(item: item)
                        .frame(maxWidth: 680)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { model.detailAppeared(item) }
        .onDisappear { model.detailDisappeared(item) }
    }
}

/// What happened since you last looked, with names; a comment among it jumps to the comment.
private struct InboxNews: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry
    var showComment: (String) -> Void

    var body: some View {
        let events = Array(entry.activity.prefix(5))
        VStack(alignment: .leading, spacing: 8) {
            Text(model.inboxNewsTitle(entry))
                .font(.tinySemibold)
                .foregroundStyle(entry.activityIsNew ? Theme.accent : Theme.textSecondary)
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                let name = event.actor.map(InboxEntry.name) ?? String(localized: .someone)
                let row = HStack(spacing: 8) {
                    if let actor = event.actor {
                        Avatar(login: actor.login, url: actor.avatarUrl, size: 16)
                    }
                    sentence(model.inboxEventLine(event, entry: entry, name: name), emphasizing: name) {
                        $0.fontWeight(.semibold).foregroundStyle(Theme.text)
                    }
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(inboxTime(event.at, now: model.inboxClock))
                        .font(.small)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(.small)
                if let commentId = event.commentId {
                    Button { showComment(commentId) } label: { row.contentShape(Rectangle()) }
                        .buttonStyle(PlainPressStyle())
                        .help(Text(.showComment))
                } else {
                    row
                }
            }
            if entry.activity.count > events.count {
                Text(.moreEventsBelow(count: entry.activity.count - events.count))
                    .font(.small)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(entry.activityIsNew ? Theme.selectionFill : Theme.lane))
    }
}

/// Several entries picked: what can be done to all of them.
private struct InboxPickedSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.visibleInbox.filter { model.inboxPicked.contains($0.id) }
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(.notificationsPicked(count: entries.count)).font(.uiSemibold)
                HStack(spacing: 8) {
                    Button(entries.contains(where: model.isUnread) ? .markAsRead : .markAsUnread) { model.toggleRead(entries) }
                        .buttonStyle(SecondaryButtonStyle())
                    SnoozeButton(entries: entries, titled: true)
                    Button(.archive) { model.archive(entries) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text(.escClearsPick).font(.small).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Snoozing

/// A button that opens the snooze menu; H and the right-click menu open it too.
private struct SnoozeButton: View {
    @Environment(AppModel.self) private var model
    var entries: [InboxEntry]
    var titled = false
    @State private var open = false
    @State private var pickDate = false

    var body: some View {
        Group {
            if titled {
                Button(.snoozeEllipsis) { show(pickDate: false) }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                IconButton(systemName: "clock", label: String(localized: .snoozeWithShortcut)) { show(pickDate: false) }
            }
        }
        .dropdown(isPresented: $open) { close in
            SnoozeMenu(entries: entries, startsWithDate: pickDate, close: close)
        }
        .onChange(of: model.inboxSnoozeRequest) { _, request in
            show(pickDate: request.pickDate)
        }
    }

    private func show(pickDate: Bool) {
        self.pickDate = pickDate
        open = true
    }
}

private struct SnoozeMenu: View {
    @Environment(AppModel.self) private var model
    var entries: [InboxEntry]
    var startsWithDate: Bool
    var close: () -> Void

    @State private var cursor = MenuCursor<Int>()
    @State private var picking = false
    @State private var date = SnoozeChoice.tomorrow.date()

    var body: some View {
        Group {
            if picking {
                VStack(alignment: .leading, spacing: 10) {
                    Text(.snoozeUntil).font(.tinySemibold).foregroundStyle(Theme.textSecondary)
                    DatePicker(.snoozeUntil, selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    HStack {
                        Spacer()
                        Button(.cancel, action: close)
                            .buttonStyle(SecondaryButtonStyle())
                            .keyboardShortcut(.cancelAction)
                        Button(.snooze) { snooze(until: date) }
                            .buttonStyle(PrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(SnoozeChoice.allCases.enumerated()), id: \.offset) { index, choice in
                        MenuRow(
                            title: choice.title, systemImage: nil, value: choice.hint(), cursor: cursor, key: index,
                            action: { snooze(until: choice.date()) }
                        )
                    }
                    MenuDivider()
                    MenuRow(
                        title: String(localized: .pickADate), systemImage: nil, cursor: cursor, key: SnoozeChoice.allCases.count,
                        action: { picking = true }
                    )
                }
                .padding(.vertical, 4)
                .frame(width: 230)
                .background(MenuKeys(
                    onMove: { cursor.step($0, through: Array(0...SnoozeChoice.allCases.count)) },
                    onActivate: {
                        guard let active = cursor.key else { return }
                        if active < SnoozeChoice.allCases.count {
                            snooze(until: SnoozeChoice.allCases[active].date())
                        } else {
                            picking = true
                        }
                    },
                    onBack: close
                ))
            }
        }
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear { picking = startsWithDate }
    }

    private func snooze(until: Date) {
        close()
        model.snooze(entries, until: until)
    }
}

// MARK: - Right-click

/// The right-click menu of an Inbox entry: read, snooze, archive, unsubscribe, and the issue's own properties.
@MainActor
struct InboxMenuBuilder {
    let model: AppModel
    let entry: InboxEntry

    func menu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let targets = model.inboxTargets(for: entry)
        if targets.count > 1 {
            let title = NSMenuItem(title: String(localized: .selectedNotificationCount(count: targets.count)), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }
        let unread = model.isUnread(targets[0])
        let read = ClosureMenuItem(String(localized: unread ? .markAsRead : .markAsUnread)) { [model] in model.toggleRead(targets) }
        read.image = MenuIcons.symbol(unread ? "circle" : "circle.inset.filled")
        hint(read, "u")
        menu.addItem(read)

        let snooze = NSMenu()
        for choice in SnoozeChoice.allCases {
            let entry = ClosureMenuItem("\(choice.title)   \(choice.hint())") { [model] in model.snooze(targets, until: choice.date()) }
            snooze.addItem(entry)
        }
        snooze.addItem(.separator())
        snooze.addItem(ClosureMenuItem(String(localized: .pickADate)) { [model, entry] in
            if targets.count == 1 { model.selectInboxEntry(entry) }
            model.inboxSnoozeRequest = InboxSnoozeRequest(token: model.inboxSnoozeRequest.token + 1, pickDate: true)
        })
        let snoozeItem = NSMenuItem(title: String(localized: .snooze), action: nil, keyEquivalent: "")
        snoozeItem.image = MenuIcons.symbol("clock")
        snoozeItem.submenu = snooze
        menu.addItem(snoozeItem)

        let archive = ClosureMenuItem(String(localized: .archive)) { [model] in model.archive(targets) }
        archive.image = MenuIcons.symbol("archivebox")
        hint(archive, "e")
        menu.addItem(archive)
        // The app's own entries (an issue being due, an assignment with your own account) aren't GitHub notifications
        // to unsubscribe from.
        if targets.contains(where: { !$0.isAppMade }) {
            let unsubscribe = ClosureMenuItem(String(localized: .unsubscribe)) { [model] in model.unsubscribe(targets) }
            unsubscribe.image = MenuIcons.symbol("bell.slash")
            unsubscribe.keyEquivalent = "S"
            unsubscribe.keyEquivalentModifierMask = [.shift]
            menu.addItem(unsubscribe)
        }

        let builder = targets.count == 1 && !entry.missing ? model.inboxItem(for: entry).map { ItemMenuBuilder(model: model, item: $0) } : nil
        if let builder {
            let properties = builder.propertyItems(targets: [builder.item])
            if !properties.isEmpty {
                menu.addItem(.separator())
                for property in properties { menu.addItem(property) }
            }
        }

        if targets.count == 1, let url = entry.webURL {
            menu.addItem(.separator())
            let copy = ClosureMenuItem(String(localized: .copyLink)) { [model, entry] in model.copyLink(url.absoluteString, for: entry.label) }
            copy.image = MenuIcons.symbol("link")
            menu.addItem(copy)
            let github = ClosureMenuItem(String(localized: .openOnGitHub)) { NSWorkspace.shared.open(url) }
            github.image = MenuIcons.symbol("arrow.up.right.square")
            menu.addItem(github)
        }
        ItemMenuBuilder.showImages(in: menu)
        return menu
    }

    private func hint(_ entry: NSMenuItem, _ key: String) {
        entry.keyEquivalent = key
        entry.keyEquivalentModifierMask = []
    }
}
#endif
