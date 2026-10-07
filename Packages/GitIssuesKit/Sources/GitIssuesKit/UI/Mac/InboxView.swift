#if os(macOS)
import AppKit
import SwiftUI

/// The Inbox on the Mac, as in Linear: the notifications on the left, the issue of the selected one on the right.
struct InboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            InboxList()
                .frame(width: Theme.inboxListWidth)
            Rectangle().fill(Theme.panelBorder).frame(width: 1)
            InboxPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - The list

private struct InboxList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            InboxHeader()
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
                title: "Your token can't read notifications",
                message: "GitHub doesn't let fine-grained tokens read them. Sign in with GitHub, or use a classic token with the repo scope. Everything else keeps working."
            ) {
                Button("Sign In Again") { model.signOut() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else if model.inboxMeta.access == .unknown, model.inboxEntries.isEmpty {
            if model.status.phase == .offline {
                EmptyState(title: "You're offline", message: "Your notifications load as soon as you're back online.")
            } else {
                EmptyState(title: "Loading your notifications…", message: "Fetching them from GitHub.", showsProgress: true)
            }
        } else if entries.isEmpty {
            InboxCaughtUp()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
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
                .onChange(of: model.focusScrollToken) {
                    guard let id = model.inboxSelectedId else { return }
                    withAnimation(Theme.quick) { proxy.scrollTo(id) }
                }
            }
        }
    }
}

private struct InboxHeader: View {
    @Environment(AppModel.self) private var model
    @State private var menuOpen = false

    var body: some View {
        HStack(spacing: 10) {
            Text("Inbox").font(.uiSemibold)
            // Watching is offered only while it has something.
            if !model.inbox(.watching).isEmpty {
                BucketSwitch()
            }
            Spacer()
            IconButton(systemName: "ellipsis", label: "Inbox actions") { menuOpen = true }
                .dropdown(isPresented: $menuOpen) { close in
                    InboxActionsMenu(close: close)
                }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: Theme.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.panelBorder).frame(height: 1)
        }
    }
}

/// For you and Watching, with what's unread in each.
private struct BucketSwitch: View {
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.forYou)
            segment(.watching)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
    }

    private func segment(_ bucket: InboxBucket) -> some View {
        let on = model.currentInboxBucket == bucket
        let unread = model.inbox(bucket).filter(model.isUnread).count
        return Button {
            withAnimation(Theme.spring) {
                model.inboxBucket = bucket
                model.inboxPicked = []
            }
        } label: {
            HStack(spacing: 5) {
                Text(bucket.title)
                if unread > 0 {
                    Text("\(unread)").monospacedDigit().foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.smallMedium)
            .foregroundStyle(on ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.segmentActive)
                        .matchedGeometryEffect(id: "bucket", in: namespace)
                }
            }
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The ⋯ menu: everything at once, and GitHub's own Inbox.
private struct InboxActionsMenu: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void
    @State private var active: Int?

    private var rows: [(title: String, image: String, shortcut: String?, action: () -> Void)] {
        [
            ("Mark All as Read", "circle", "⌥U", { model.markAllRead() }),
            ("Archive All Read", "archivebox", "⇧⌫", { model.archiveAllRead() }),
            ("Open GitHub Notifications", "arrow.up.right.square", nil, {
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
                    title: row.title, systemImage: row.image, shortcut: row.shortcut, active: active == index,
                    action: { pick(row.action) },
                    onHover: { inside in if inside { active = index } else if active == index { active = nil } }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: 250)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { active = menuStep(active, by: $0, count: rows.count) },
            onActivate: { if let active { pick(rows[active].action) } },
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

    var body: some View {
        let item = model.inboxItem(for: entry)
        let summary = model.inboxSummary(entry)
        let unread = model.isUnread(entry)
        let picked = model.inboxPicked.contains(entry.id)
        let selected = model.inboxSelectedId == entry.id && model.inboxPicked.isEmpty
        let ground = picked ? Theme.selectionFill : selected ? Theme.selected : hovering ? Theme.hover : Theme.panel
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(unread ? Theme.accent : .clear)
                .frame(width: 6, height: 6)
                .padding(.top, 10)
            InboxAvatar(summary: summary, size: 24, ground: ground)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    InboxSubjectIcon(entry: entry, item: item)
                    Text(model.inboxNumber(entry, item: item))
                        .font(.small)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(entry.title)
                        .font(unread ? .uiSemibold : .ui)
                        .foregroundStyle(unread ? Theme.text : Theme.textBody)
                        .lineLimit(1)
                }
                line(summary)
                    .font(.small)
                    .foregroundStyle(unread ? Theme.textSecondary : Theme.textTertiary)
                    .lineLimit(1)
                    .padding(.leading, 20)
            }
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 2) {
                    IconButton(systemName: unread ? "circle.inset.filled" : "circle", label: unread ? "Mark as read (U)" : "Mark as unread (U)", size: 24) {
                        model.toggleRead(model.inboxTargets(for: entry))
                    }
                    IconButton(systemName: "archivebox", label: "Archive (E)", size: 24) {
                        model.archive(model.inboxTargets(for: entry))
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            } else {
                Text(inboxTime(entry.updatedAt, now: model.inboxClock))
                    .font(.small)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ground))
        .overlay {
            if picked {
                RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Theme.selectionBorder, lineWidth: 1)
            }
        }
        .padding(.horizontal, 6)
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
        .accessibilityAction(named: unread ? "Mark as Read" : "Mark as Unread") { model.toggleRead([entry]) }
        .accessibilityAction(named: "Archive") { model.archive([entry]) }
    }

    /// "Mira Patel: The settle feels good now…", the lead set apart from the comment.
    private func line(_ summary: InboxSummary) -> Text {
        guard let excerpt = summary.excerpt else { return Text(summary.lead) }
        return Text("\(Text(summary.lead).fontWeight(.medium)) \(excerpt)")
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
                Text("\(count) more on GitHub")
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.small)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .help("Releases, CI runs, discussions and alerts aren't shown here. Open GitHub's notifications.")
    }
}

private struct InboxCaughtUp: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 6)
            Text("You're all caught up").font(.uiSemibold)
            Text("When someone assigns you, mentions you or comments on an issue you follow, it shows up here.")
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
            Image(systemName: undo.message.hasPrefix("Unsubscribed") ? "bell.slash" : "archivebox")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(undo.message).lineLimit(1)
            Button {
                model.undoInbox()
            } label: {
                HStack(spacing: 6) {
                    Text("Undo")
                    Text("⌘Z").foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .font(.ui)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 14, y: 6)
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
            VStack(spacing: 0) {
                Color.clear.frame(height: Theme.headerHeight)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
                EmptyState(
                    title: model.visibleInbox.isEmpty ? "" : "No notification selected",
                    message: model.visibleInbox.isEmpty ? "" : "Pick one on the left, or move through them with J and K."
                )
            }
        }
    }
}

private struct InboxEntryPane: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry

    var body: some View {
        let item = model.inboxItem(for: entry)
        VStack(spacing: 0) {
            header(item)
            if entry.missing {
                EmptyState(
                    title: "This issue isn't available any more",
                    message: "It was deleted or moved, or you no longer have access. GitHub's notification is still here."
                ) {
                    HStack(spacing: 8) {
                        Button("Open on GitHub") { openOnGitHub() }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Archive") { model.archive([entry]) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else if let item {
                InboxIssue(item: item, entry: entry)
                    .id(item.id)
            } else {
                EmptyState(title: "Loading the issue…", message: "Reading it from GitHub.", showsProgress: true)
            }
        }
    }

    private func header(_ item: Item?) -> some View {
        HStack(spacing: 8) {
            if let item, let project = model.project(of: item) {
                ProjectSwatch(title: project.title)
                Text(project.title).foregroundStyle(Theme.textSecondary).lineLimit(1)
            } else {
                Text(entry.repo).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            Text("›").foregroundStyle(Theme.textTertiary)
            Text(entry.displayNumber(withRepo: false)).font(.uiSemibold).monospacedDigit()
            Spacer(minLength: 8)
            SnoozeButton(entries: [entry])
            IconButton(systemName: "archivebox", label: "Archive (E)") { model.archive([entry]) }
            IconButton(systemName: "link", label: "Copy link (⌘⇧C)") {
                if let url = entry.webURL { model.copyLink(url.absoluteString, for: entry.label) }
            }
            if let item, !item.isDetached {
                IconButton(systemName: "arrow.up.left.and.arrow.down.right", label: "Open the issue (↵)") { model.open(item) }
            }
            Button(action: openOnGitHub) {
                HStack(spacing: 6) {
                    Text("Open on GitHub")
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.leading, 4)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: Theme.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.panelBorder).frame(height: 1)
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !entry.activity.isEmpty {
                        InboxNews(entry: entry) { commentId in
                            withAnimation(Theme.spring) { proxy.scrollTo(commentId, anchor: .top) }
                        }
                    }
                    ForEach(model.conflict(for: item)) { conflict in
                        ConflictBanner(entry: conflict)
                    }
                    TitleField(item: item)
                    PropertyChipRow(item: item)
                    DescriptionView(item: item)
                    if item.kind == .issue, !item.isDetached {
                        SubIssuesSection(item: item)
                    }
                    if item.kind != .draft {
                        ActivitySection(item: item, highlighted: entry.newCommentIds)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
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
                let row = HStack(spacing: 8) {
                    if let actor = event.actor {
                        Avatar(login: actor.login, url: actor.avatarUrl, size: 16)
                    }
                    Text("\(Text(event.actor.map(InboxEntry.name) ?? "Someone").fontWeight(.semibold).foregroundStyle(Theme.text)) \(model.inboxEventLine(event, entry: entry))")
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
                        .help("Show the comment")
                } else {
                    row
                }
            }
            if entry.activity.count > events.count {
                Text("and \(entry.activity.count - events.count) more below")
                    .font(.small)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(entry.activityIsNew ? Theme.selectionFill : Theme.groupHeader))
    }
}

/// Several entries picked: what can be done to all of them.
private struct InboxPickedSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.visibleInbox.filter { model.inboxPicked.contains($0.id) }
        VStack(spacing: 0) {
            Color.clear.frame(height: Theme.headerHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
            VStack(spacing: 12) {
                Text("\(entries.count) notifications picked").font(.uiSemibold)
                HStack(spacing: 8) {
                    Button(entries.contains(where: model.isUnread) ? "Mark as Read" : "Mark as Unread") { model.toggleRead(entries) }
                        .buttonStyle(SecondaryButtonStyle())
                    SnoozeButton(entries: entries, titled: true)
                    Button("Archive") { model.archive(entries) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text("Esc clears the pick").font(.small).foregroundStyle(Theme.textTertiary)
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
                Button("Snooze…") { show(pickDate: false) }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                IconButton(systemName: "clock", label: "Snooze (H)") { show(pickDate: false) }
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

    @State private var active: Int?
    @State private var picking = false
    @State private var date = SnoozeChoice.tomorrow.date()

    var body: some View {
        Group {
            if picking {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Snooze until").font(.tinySemibold).foregroundStyle(Theme.textSecondary)
                    DatePicker("Snooze until", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    HStack {
                        Spacer()
                        Button("Cancel", action: close)
                            .buttonStyle(SecondaryButtonStyle())
                            .keyboardShortcut(.cancelAction)
                        Button("Snooze") { snooze(until: date) }
                            .buttonStyle(PrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(SnoozeChoice.allCases.enumerated()), id: \.offset) { index, choice in
                        MenuRow(
                            title: choice.title, systemImage: nil, value: choice.hint(), active: active == index,
                            action: { snooze(until: choice.date()) },
                            onHover: { inside in hover(index, inside) }
                        )
                    }
                    MenuDivider()
                    MenuRow(
                        title: "Pick a Date…", systemImage: nil, active: active == SnoozeChoice.allCases.count,
                        action: { picking = true },
                        onHover: { inside in hover(SnoozeChoice.allCases.count, inside) }
                    )
                }
                .padding(.vertical, 4)
                .frame(width: 230)
                .background(MenuKeys(
                    onMove: { active = menuStep(active, by: $0, count: SnoozeChoice.allCases.count + 1) },
                    onActivate: {
                        guard let active else { return }
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

    private func hover(_ index: Int, _ inside: Bool) {
        if inside { active = index } else if active == index { active = nil }
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
            let title = NSMenuItem(title: "\(targets.count) notifications", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }
        let unread = model.isUnread(targets[0])
        let read = ClosureMenuItem(unread ? "Mark as Read" : "Mark as Unread") { [model] in model.toggleRead(targets) }
        read.image = MenuIcons.symbol(unread ? "circle" : "circle.inset.filled")
        hint(read, "u")
        menu.addItem(read)

        let snooze = NSMenu()
        for choice in SnoozeChoice.allCases {
            let entry = ClosureMenuItem("\(choice.title)   \(choice.hint())") { [model] in model.snooze(targets, until: choice.date()) }
            snooze.addItem(entry)
        }
        snooze.addItem(.separator())
        snooze.addItem(ClosureMenuItem("Pick a Date…") { [model, entry] in
            if targets.count == 1 { model.selectInboxEntry(entry) }
            model.inboxSnoozeRequest = InboxSnoozeRequest(token: model.inboxSnoozeRequest.token + 1, pickDate: true)
        })
        let snoozeItem = NSMenuItem(title: "Snooze", action: nil, keyEquivalent: "")
        snoozeItem.image = MenuIcons.symbol("clock")
        snoozeItem.submenu = snooze
        menu.addItem(snoozeItem)

        let archive = ClosureMenuItem("Archive") { [model] in model.archive(targets) }
        archive.image = MenuIcons.symbol("archivebox")
        hint(archive, "e")
        menu.addItem(archive)
        let unsubscribe = ClosureMenuItem("Unsubscribe") { [model] in model.unsubscribe(targets) }
        unsubscribe.image = MenuIcons.symbol("bell.slash")
        unsubscribe.keyEquivalent = "S"
        unsubscribe.keyEquivalentModifierMask = [.shift]
        menu.addItem(unsubscribe)

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
            let copy = ClosureMenuItem("Copy Link") { [model, entry] in model.copyLink(url.absoluteString, for: entry.label) }
            copy.image = MenuIcons.symbol("link")
            menu.addItem(copy)
            let github = ClosureMenuItem("Open on GitHub") { NSWorkspace.shared.open(url) }
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
