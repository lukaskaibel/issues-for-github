#if os(iOS)
import SwiftUI

/// The Inbox on iPhone, and its list on a wide iPad: GitHub's notifications about issues and pull requests, newest
/// first. A tap opens the issue (and reads it), a swipe right reads, a swipe left snoozes or archives, a long press
/// shows everything.
struct InboxScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @Environment(\.wideLayout) private var wide
    /// Beside the issue on a wide iPad: a tap selects the entry instead of opening a screen.
    var selecting = false

    @State private var snoozing: SnoozeTarget?
    @State private var pickingDate: SnoozeTarget?
    @State private var archived = 0

    var body: some View {
        let entries = model.visibleInbox
        Group {
            if model.inboxMeta.access == .denied {
                MobileEmptyState(
                    title: "Your token can't read notifications",
                    message: "GitHub doesn't let fine-grained tokens read them. Sign in with GitHub, or use a classic token with the repo scope. Everything else keeps working.",
                    systemImage: "key"
                ) {
                    Button("Sign In Again") { model.signOut() }
                        .buttonStyle(.bordered)
                }
            } else if model.inboxMeta.access == .unknown, model.inboxEntries.isEmpty {
                if model.status.phase == .offline {
                    MobileEmptyState(title: "You're offline", message: "Your notifications load as soon as you're back online.", systemImage: "wifi.slash")
                } else {
                    MobileEmptyState(title: "Loading your notifications…", message: "Fetching them from GitHub.", showsProgress: true)
                }
            } else {
                list(entries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
        .navigationTitle("Inbox")
        .navigationSubtitle(SyncSubtitle.text(model))
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let undo = model.inboxUndo {
                MobileInboxUndo(undo: undo)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.overlay, value: model.inboxUndo)
        .confirmationDialog("Snooze until", isPresented: Binding(get: { snoozing != nil }, set: { if !$0 { snoozing = nil } }), presenting: snoozing) { target in
            ForEach(SnoozeChoice.allCases) { choice in
                Button("\(choice.title), \(choice.hint())") { model.snooze(target.entries, until: choice.date()) }
            }
            Button("Pick a Date…") { pickingDate = target }
        }
        .sheet(item: $pickingDate) { target in
            SnoozeDateSheet(entries: target.entries)
        }
        .sensoryFeedback(.success, trigger: archived)
        .onAppear { model.inboxAppeared() }
        .background { if selecting { keyboardShortcuts } }
    }

    @ViewBuilder
    private func list(_ entries: [InboxEntry]) -> some View {
        List {
            if !model.inbox(.watching).isEmpty {
                Picker("Show", selection: bucket) {
                    ForEach(InboxBucket.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                .accessibilityIdentifier("inbox-bucket")
            }
            if entries.isEmpty {
                MobileEmptyState(
                    title: "You're all caught up",
                    message: "When someone assigns you, mentions you or comments on an issue you follow, it shows up here.",
                    systemImage: "tray"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            ForEach(entries) { entry in
                row(entry)
            }
            if model.inboxMeta.otherCount > 0, !entries.isEmpty {
                Button {
                    if let url = URL(string: "https://github.com/notifications") { Platform.open(url) }
                } label: {
                    Label("\(model.inboxMeta.otherCount) more on GitHub", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabel())
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 58, bottom: 10, trailing: 16))
                .accessibilityHint("Releases, CI runs and discussions stay on GitHub.")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refreshInboxAndWait() }
        .animation(Theme.spring, value: entries.map(\.id))
    }

    @ViewBuilder
    private func row(_ entry: InboxEntry) -> some View {
        let unread = model.isUnread(entry)
        // Beside the issue, the selected row is marked quietly, as on the Mac, so its text stays readable.
        let selected = selecting && model.inboxSelectedId == entry.id
        Button {
            if selecting { model.selectInboxEntry(entry) } else { open(entry) }
        } label: {
            MobileInboxRow(entry: entry, ground: selected ? Theme.selected : Theme.panel)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .listRowInsets(EdgeInsets())
        .listRowBackground(selected ? Theme.selected : Theme.panel)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 58 }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(Theme.spring) { model.toggleRead([entry]) }
            } label: {
                Label(unread ? "Read" : "Unread", systemImage: unread ? "circle" : "circle.inset.filled")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                archived += 1
                model.archive([entry])
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(Theme.accentFill)
            Button {
                snoozing = SnoozeTarget(entries: [entry])
            } label: {
                Label("Snooze", systemImage: "clock")
            }
            .tint(Color(white: 0.45))
        }
        .contextMenu {
            InboxMenuContent(entry: entry, onSnoozeDate: { pickingDate = SnoozeTarget(entries: [entry]) })
        }
    }

    /// Opens the issue on its own screen; one that GitHub can't show any more opens on github.com.
    private func open(_ entry: InboxEntry) {
        if !entry.missing, let card = model.inboxItem(for: entry) {
            openRoute(.inboxIssue(entry: entry.id, item: card.id))
        } else {
            model.selectInboxEntry(entry)
            if let url = entry.webURL { Platform.open(url) }
        }
    }

    private var bucket: Binding<InboxBucket> {
        Binding(
            get: { model.currentInboxBucket },
            set: { value in withAnimation(Theme.spring) { model.inboxBucket = value } }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !wide {
            ToolbarItem(placement: .topBarLeading) { AccountButton() }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    withAnimation(Theme.spring) { model.markAllRead() }
                } label: {
                    Label("Mark All as Read", systemImage: "circle")
                }
                .disabled(!model.visibleInbox.contains(where: model.isUnread))
                Button {
                    model.archiveAllRead()
                } label: {
                    Label("Archive All Read", systemImage: "archivebox")
                }
                .disabled(!model.visibleInbox.contains { !model.isUnread($0) })
                Divider()
                Button {
                    if let url = URL(string: "https://github.com/notifications") { Platform.open(url) }
                } label: {
                    Label("Open GitHub Notifications", systemImage: "arrow.up.right.square")
                }
            } label: {
                Label("Inbox Actions", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("inbox-actions")
        }
    }

    /// With a keyboard on the iPad, the Mac's keys: J and K move, U reads, E archives, H snoozes, ⇧S unsubscribes.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Next") { model.stepInbox(1) }.keyboardShortcut("j", modifiers: [])
            Button("Previous") { model.stepInbox(-1) }.keyboardShortcut("k", modifiers: [])
            Button("Read or Unread") { if let entry = model.inboxSelected { model.toggleRead([entry]) } }.keyboardShortcut("u", modifiers: [])
            Button("Mark All as Read") { model.markAllRead() }.keyboardShortcut("u", modifiers: .option)
            Button("Archive") { if let entry = model.inboxSelected { model.archive([entry]) } }.keyboardShortcut("e", modifiers: [])
            Button("Archive All Read") { model.archiveAllRead() }.keyboardShortcut(.delete, modifiers: .shift)
            Button("Snooze") { if let entry = model.inboxSelected { snoozing = SnoozeTarget(entries: [entry]) } }.keyboardShortcut("h", modifiers: [])
            Button("Unsubscribe") { if let entry = model.inboxSelected { model.unsubscribe([entry]) } }.keyboardShortcut("s", modifiers: .shift)
            Button("Undo") { model.undoInbox() }.keyboardShortcut("z", modifiers: .command).disabled(model.inboxUndo == nil)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Entries to snooze, for the dialog and the date sheet.
private struct SnoozeTarget: Identifiable {
    let id = UUID()
    var entries: [InboxEntry]
}

/// One notification: who did what to which issue, and when.
struct MobileInboxRow: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry
    /// What the row sits on, for the ring around the sign on the avatar.
    var ground: Color = Theme.panel

    var body: some View {
        let item = model.inboxItem(for: entry)
        let summary = model.inboxSummary(entry)
        let unread = model.isUnread(entry)
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(unread ? Theme.accent : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 13)
            InboxAvatar(summary: summary, size: 32, ground: ground)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.title)
                        .font(unread ? .body.weight(.semibold) : .body)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(inboxTime(entry.updatedAt, now: model.inboxClock))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("\(Text(model.inboxNumber(entry, item: item)).foregroundStyle(Theme.textTertiary)) · \(line(summary))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.spoken(summary, unread: unread))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(Self.identifier(entry, item: item))
    }

    /// "inbox-row-25" for an issue on a board, "inbox-row-brand-4" for one that isn't.
    static func identifier(_ entry: InboxEntry, item: Item?) -> String {
        let number = entry.number.map(String.init) ?? entry.id
        return item == nil || item?.isDetached == true ? "inbox-row-\(entry.repoShortName)-\(number)" : "inbox-row-\(number)"
    }

    private func line(_ summary: InboxSummary) -> Text {
        guard let excerpt = summary.excerpt else { return Text(summary.lead) }
        return Text("\(Text(summary.lead).fontWeight(.medium)) \(excerpt)")
    }
}

/// What a long press on an entry shows: read, snooze, archive, unsubscribe, and the issue's own properties.
struct InboxMenuContent: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry
    var onSnoozeDate: () -> Void

    var body: some View {
        let unread = model.isUnread(entry)
        Button {
            withAnimation(Theme.spring) { model.toggleRead([entry]) }
        } label: {
            Label(unread ? "Mark as Read" : "Mark as Unread", systemImage: unread ? "circle" : "circle.inset.filled")
        }
        Menu {
            ForEach(SnoozeChoice.allCases) { choice in
                Button("\(choice.title), \(choice.hint())") { model.snooze([entry], until: choice.date()) }
            }
            Button("Pick a Date…", action: onSnoozeDate)
        } label: {
            Label("Snooze", systemImage: "clock")
        }
        Button {
            model.archive([entry])
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Button {
            model.unsubscribe([entry])
        } label: {
            Label("Unsubscribe", systemImage: "bell.slash")
        }
        if !entry.missing, let item = model.inboxItem(for: entry) {
            Divider()
            if !item.isDetached {
                StatusMenu(item: item)
            }
            if model.project(of: item)?.priorityFieldId != nil {
                PriorityMenu(item: item)
            }
            AssigneeMenu(item: item)
            LabelsMenu(item: item)
        }
        if let url = entry.webURL {
            Divider()
            Button {
                model.copyLink(url.absoluteString, for: entry.label)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            Button {
                Platform.open(url)
            } label: {
                Label("Open on GitHub", systemImage: "arrow.up.right.square")
            }
        }
    }
}

/// Choosing a date and time to snooze until.
private struct SnoozeDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var entries: [InboxEntry]
    @State private var date = SnoozeChoice.tomorrow.date()

    var body: some View {
        NavigationStack {
            DatePicker("Snooze until", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("Snooze Until")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Snooze") {
                            model.snooze(entries, until: date)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// "Archived #8 · Undo", for the few seconds an archive can be taken back.
private struct MobileInboxUndo: View {
    @Environment(AppModel.self) private var model
    var undo: InboxUndo

    var body: some View {
        // The whole capsule takes the tap: a small target is easy to miss in the moment it shows.
        Button {
            model.undoInbox()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: undo.message.hasPrefix("Unsubscribed") ? "bell.slash" : "archivebox")
                    .foregroundStyle(Theme.accent)
                Text(undo.message).foregroundStyle(Theme.text).lineLimit(1)
                Text("Undo").fontWeight(.semibold).foregroundStyle(Theme.accent)
            }
            .font(.subheadline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("\(undo.message). Undo")
        .accessibilityIdentifier("inbox-undo")
    }
}

/// A label with its icon after the text, for "2 more on GitHub ↗".
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

// MARK: - On the issue

/// What happened since you last looked, with names, on an issue opened from the Inbox.
struct MobileInboxNews: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry

    var body: some View {
        let events = Array(entry.activity.prefix(5))
        VStack(alignment: .leading, spacing: 8) {
            Text(model.inboxNewsTitle(entry))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(entry.activityIsNew ? Theme.accent : Theme.textSecondary)
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let actor = event.actor {
                        Avatar(login: actor.login, url: actor.avatarUrl, size: 18)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    }
                    Text("\(Text(event.actor.map(InboxEntry.name) ?? "Someone").fontWeight(.semibold)) \(model.inboxEventLine(event, entry: entry))")
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(inboxTime(event.at, now: model.inboxClock))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
            }
            if entry.activity.count > events.count {
                Text("and \(entry.activity.count - events.count) more below")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(entry.activityIsNew ? Theme.selectionFill : Theme.groupHeader))
        .accessibilityElement(children: .combine)
    }
}

/// An issue on none of your boards: say so, and offer to put it on one.
struct MobileDetachedBanner: View {
    @Environment(AppModel.self) private var model
    var entry: InboxEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.split.3x1")
                .foregroundStyle(Theme.textTertiary)
            Text("Not on any of your boards")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if !model.projectsAcceptingIssues.isEmpty {
                Menu("Add to Project") {
                    ForEach(model.projectsAcceptingIssues) { project in
                        Button {
                            model.addToProject(entry, projectId: project.id)
                        } label: {
                            Label {
                                Text(project.title)
                            } icon: {
                                Image(uiImage: SwatchImages.image(for: project.title))
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("add-to-project")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.groupHeader))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelBorder, lineWidth: 1))
    }
}

// MARK: - iPad

/// The Inbox on a wide iPad, as Mail: the list in a column, the selected entry's issue beside it.
struct InboxSplit: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation

    var body: some View {
        NavigationSplitView {
            // Handed on explicitly: the split's columns are hosted anew when the window turns and the tab bar becomes
            // a sidebar, and must not lose them on the way.
            InboxScreen(selecting: true)
                .environment(model)
                .environment(navigation)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 440)
        } detail: {
            NavigationStack(path: Binding(get: { navigation.inboxPath }, set: { navigation.inboxPath = $0 })) {
                detail
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                    }
            }
            .environment(\.openRoute, OpenRouteAction { [navigation] route in navigation.push(route, on: .inbox) })
            .environment(model)
            .environment(navigation)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.inboxSelectedId, initial: true) {
            navigation.inboxPath = []
            navigation.inboxRootItemId = model.inboxSelected.flatMap { model.inboxItem(for: $0)?.id }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = model.inboxSelected {
            if entry.missing {
                MobileEmptyState(
                    title: "This issue isn't available any more",
                    message: "It was deleted or moved, or you no longer have access. GitHub's notification is still here.",
                    systemImage: "lock"
                ) {
                    HStack {
                        Button("Open on GitHub") { if let url = entry.webURL { Platform.open(url) } }
                            .buttonStyle(.bordered)
                        Button("Archive") { model.archive([entry]) }
                            .buttonStyle(.bordered)
                    }
                }
            } else if let card = model.inboxItem(for: entry) {
                IssueScreen(itemId: card.id, inboxEntryId: entry.id)
                    .id(entry.id)
            } else {
                MobileEmptyState(title: "Loading the issue…", message: "Reading it from GitHub.", showsProgress: true)
            }
        } else {
            MobileEmptyState(
                title: model.visibleInbox.isEmpty ? "Nothing to read" : "No notification selected",
                message: model.visibleInbox.isEmpty ? "New notifications show up on the left." : "Pick one on the left, or move through them with J and K.",
                systemImage: "tray"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panel)
        }
    }
}
#endif
