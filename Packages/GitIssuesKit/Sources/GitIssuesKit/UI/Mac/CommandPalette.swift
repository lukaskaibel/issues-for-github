#if os(macOS)
import SwiftUI

/// ⌘K. Runs commands on the issue in focus, jumps to issues by title or number, and hosts the
/// keyboard-driven pickers (S, P, A, L).
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    var mode: PaletteMode

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .root:
                RootPalette()
            case .status(let id):
                step(.status, id)
            case .priority(let id):
                step(.priority, id)
            case .assignees(let id):
                step(.assignees, id)
            case .labels(let id):
                step(.labels, id)
            case .dueDate(let id):
                step(.dueDate, id)
            case .parent(let id):
                step(.parent, id)
            case .addSubIssue(let id):
                step(.addSubIssue, id)
            case .blockedBy(let id):
                step(.blockedBy, id)
            case .blocking(let id):
                step(.blocking, id)
            case .projects:
                PickerList(
                    placeholder: "Switch project or repository…",
                    items: model.projects.filter { !$0.closed }.map { project in
                        PickerItem(
                            id: project.id, title: project.title, subtitle: project.ownerLogin,
                            selected: model.scope == .project(project.id),
                            icon: AnyView(ProjectSwatch(title: project.title))
                        )
                    } + model.boardRepositories.map { repo in
                        PickerItem(
                            id: Self.repositoryPrefix + repo.id, title: repo.shortName, subtitle: repo.nameWithOwner,
                            selected: model.scope == .repository(repo.id),
                            icon: AnyView(RepositoryIcon().foregroundStyle(Theme.textSecondary))
                        )
                    },
                    width: 640, maxRows: 10, fieldFont: .system(size: 15),
                    onPick: { id in
                        if id.hasPrefix(Self.repositoryPrefix) {
                            model.select(.repository(String(id.dropFirst(Self.repositoryPrefix.count))))
                        } else {
                            model.select(.project(id))
                        }
                    },
                    onClose: { model.overlay = nil }
                )
            }
        }
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Theme.shadow, radius: 40, y: 24)
    }

    private static let repositoryPrefix = "repository:"

    @ViewBuilder
    private func step(_ kind: PickerKind, _ itemId: String) -> some View {
        if let item = model.item(id: itemId) {
            ContextChip(item: item, count: model.targets(for: item).count)
            // A pick can open something else, such as the new-issue dialog; that stays.
            ItemPicker(kind: kind, itemId: itemId, width: 640, fieldFont: .system(size: 15)) { [mode] in
                if model.overlay == .palette(mode) { model.overlay = nil }
            }
        }
    }
}

private struct ContextChip: View {
    var item: Item
    /// How many issues the command applies to; more than one when several are picked.
    var count = 1

    var body: some View {
        HStack(spacing: 6) {
            if count > 1 {
                Text("\(count) issues")
            } else {
                Text(item.displayNumber).foregroundStyle(Theme.textSecondary)
                Text(item.title).lineLimit(1)
            }
        }
        .font(.small)
        .foregroundStyle(Theme.textBody)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.controlActive))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

private struct PaletteCommand: Identifiable {
    var id: String
    var title: String
    var section: String
    var icon: AnyView
    var keys: [String] = []
    var run: () -> Void
}

private struct RootPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let rows = results
        VStack(spacing: 0) {
            if let target = model.actionItem {
                ContextChip(item: target, count: model.targets(for: target).count)
            }
            TextField("Type a command or search issues…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .focusOnAppear()
                .padding(.horizontal, 16)
                .frame(height: 48)
                .onKeyPress(.downArrow) {
                    index = min(index + 1, max(rows.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    index = max(index - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.overlay = nil
                    return .handled
                }
                .onSubmit {
                    if rows.indices.contains(index) { run(rows[index]) }
                }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, command in
                            if position == 0 || rows[position - 1].section != command.section {
                                Text(command.section)
                                    .font(.tinySemibold)
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                            }
                            HStack(spacing: 10) {
                                command.icon.frame(width: 16, height: 16)
                                Text(command.title).lineLimit(1)
                                Spacer(minLength: 8)
                                HStack(spacing: 4) {
                                    ForEach(command.keys, id: \.self) { Keycap($0, emphasized: position == index) }
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(position == index ? Theme.popoverSelected : .clear))
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                            .id(command.id)
                            .onTapGesture { run(command) }
                            .onHover { if $0 { index = position } }
                        }
                        if rows.isEmpty {
                            Text("Nothing matches \"\(query)\"")
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: index) {
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                }
            }
        }
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear { focused = true }
        .onChange(of: query) { index = 0 }
    }

    private func run(_ command: PaletteCommand) {
        // Commands that open another palette step set the overlay themselves.
        model.overlay = nil
        command.run()
    }

    private func symbol(_ name: String) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary))
    }

    private var results: [PaletteCommand] {
        let commands = self.commands
        guard !query.isEmpty else { return commands }
        let matchedCommands = commands
            .compactMap { command in fuzzyScore(query, command.title).map { (command, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let pool = model.scope == .myIssues || model.scope == .inbox ? model.allItems : model.scopedItems
        let digits = query.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let issues = pool
            .compactMap { item -> (Item, Int)? in
                if let number = item.number, !digits.isEmpty, String(number).hasPrefix(digits) { return (item, 1000 - String(number).count) }
                return fuzzyScore(query, item.title).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { item, _ in
                PaletteCommand(
                    id: "issue-\(item.id)", title: "\(item.displayNumber)  \(item.title)", section: "Issues",
                    icon: AnyView(StatusIcon(glyph: model.glyph(of: item)))
                ) { model.open(item) }
            }
        return issues + matchedCommands.map { command in
            var command = command
            command.section = "Commands"
            return command
        }
    }

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = []
        if let item = model.actionItem {
            let targets = model.targets(for: item)
            let several = targets.count > 1
            let section = several ? "\(targets.count) issues" : "This issue"
            list.append(PaletteCommand(id: "status", title: item.isOnBoard ? "Change status…" : "Add to project…", section: section, icon: AnyView(StatusIcon(glyph: model.glyph(of: item))), keys: ["S"]) {
                model.overlay = .palette(.status(itemId: item.id))
            })
            if model.project(of: item)?.priorityFieldId != nil {
                list.append(PaletteCommand(id: "priority", title: "Set priority…", section: section, icon: AnyView(PriorityIcon(level: .high)), keys: ["P"]) {
                    model.overlay = .palette(.priority(itemId: item.id))
                })
            }
            if item.kind != .draft {
                list.append(PaletteCommand(id: "assign", title: "Assign to…", section: section, icon: symbol("person"), keys: ["A"]) {
                    model.overlay = .palette(.assignees(itemId: item.id))
                })
                if let viewer = model.viewer {
                    let mine = targets.allSatisfy { target in target.assignees.contains { $0.id == viewer.id } }
                    list.append(PaletteCommand(id: "assign-me", title: mine ? "Unassign me" : "Assign to me", section: section, icon: symbol("person.fill"), keys: ["I"]) {
                        model.toggleAssignMe(targets)
                    })
                }
                list.append(PaletteCommand(id: "labels", title: "Add labels…", section: section, icon: symbol("tag"), keys: ["L"]) {
                    model.overlay = .palette(.labels(itemId: item.id))
                })
            }
            if targets.contains(where: model.canHaveDueDate) {
                list.append(PaletteCommand(id: "due", title: "Set due date…", section: section, icon: symbol("calendar"), keys: ["D"]) {
                    model.overlay = .palette(.dueDate(itemId: item.id))
                })
            }
            if targets.contains(where: { $0.dueDate != nil }) {
                list.append(PaletteCommand(id: "due-remove", title: "Remove due date", section: section, icon: symbol("calendar.badge.minus")) {
                    model.setDueDate(of: targets, to: nil)
                })
            }
            if model.canRelate(item) {
                let subIcon = AnyView(SubIssueGlyph().frame(width: 12, height: 12).foregroundStyle(Theme.textSecondary))
                if !several {
                    list.append(PaletteCommand(id: "sub", title: "Create sub-issue", section: section, icon: subIcon) {
                        model.overlay = .newIssue(statusId: nil, parentItemId: item.id)
                    })
                    list.append(PaletteCommand(id: "sub-existing", title: "Add existing issue as sub-issue…", section: section, icon: subIcon) {
                        model.overlay = .palette(.addSubIssue(itemId: item.id))
                    })
                }
                list.append(PaletteCommand(id: "parent", title: "Set parent issue…", section: section, icon: symbol("arrow.turn.left.up"), keys: ["M", "P"]) {
                    model.overlay = .palette(.parent(itemId: item.id))
                })
                if targets.contains(where: { $0.parentId != nil }) {
                    list.append(PaletteCommand(id: "parent-remove", title: "Remove from parent", section: section, icon: symbol("xmark")) {
                        model.setParent(of: targets, to: nil)
                    })
                }
                list.append(PaletteCommand(id: "blocked-by", title: "Mark as blocked by…", section: section, icon: AnyView(BlockedIcon()), keys: ["M", "B"]) {
                    model.overlay = .palette(.blockedBy(itemId: item.id))
                })
                list.append(PaletteCommand(id: "blocking", title: "Mark as blocking…", section: section, icon: AnyView(BlockingIcon()), keys: ["M", "X"]) {
                    model.overlay = .palette(.blocking(itemId: item.id))
                })
            }
            if model.canDelete(item), !several {
                list.append(PaletteCommand(id: "delete", title: item.kind == .draft ? "Delete draft…" : "Delete issue…", section: section, icon: symbol("trash"), keys: ["⌘", "⌫"]) {
                    model.requestDelete(item)
                })
            }
            if item.url != nil {
                list.append(PaletteCommand(id: "copy", title: several ? "Copy GitHub links" : "Copy GitHub link", section: section, icon: symbol("link"), keys: ["⌘", "⇧", "C"]) {
                    model.copyLinks(targets)
                })
                if !several {
                    list.append(PaletteCommand(id: "github", title: "Open on GitHub", section: section, icon: symbol("arrow.up.right")) {
                        model.openOnGitHub(item)
                    })
                }
            }
        }
        if model.openItem == nil, !model.orderedItems.isEmpty {
            list.append(PaletteCommand(id: "select-all", title: "Select all issues", section: "Selection", icon: symbol("checkmark.circle"), keys: ["⌘", "A"]) {
                model.selectAll()
            })
            if !model.selectedIds.isEmpty {
                list.append(PaletteCommand(id: "select-none", title: "Clear selection", section: "Selection", icon: symbol("xmark.circle"), keys: ["Esc"]) {
                    model.clearSelection()
                })
            }
        }
        if model.scope == .inbox {
            let entries = model.inboxPicked.isEmpty
                ? model.inboxSelected.map { [$0] } ?? []
                : model.visibleInbox.filter { model.inboxPicked.contains($0.id) }
            let section = entries.count > 1 ? "\(entries.count) notifications" : "Inbox"
            if let first = entries.first {
                let unread = model.isUnread(first)
                list.append(PaletteCommand(id: "inbox-read", title: unread ? "Mark as read" : "Mark as unread", section: section, icon: symbol(unread ? "circle" : "circle.inset.filled"), keys: ["U"]) {
                    model.toggleRead(entries)
                })
                list.append(PaletteCommand(id: "inbox-archive", title: "Archive", section: section, icon: symbol("archivebox"), keys: ["E"]) {
                    model.archive(entries)
                })
                for choice in SnoozeChoice.allCases {
                    list.append(PaletteCommand(id: "inbox-snooze-\(choice)", title: "Snooze until \(choice.title.lowercased()) (\(choice.hint()))", section: section, icon: symbol("clock")) {
                        model.snooze(entries, until: choice.date())
                    })
                }
                list.append(PaletteCommand(id: "inbox-unsubscribe", title: "Unsubscribe", section: section, icon: symbol("bell.slash"), keys: ["⇧", "S"]) {
                    model.unsubscribe(entries)
                })
            }
            list.append(PaletteCommand(id: "inbox-read-all", title: "Mark all as read", section: "Inbox", icon: symbol("circle"), keys: ["⌥", "U"]) {
                model.markAllRead()
            })
            list.append(PaletteCommand(id: "inbox-archive-read", title: "Archive all read", section: "Inbox", icon: symbol("archivebox"), keys: ["⇧", "⌫"]) {
                model.archiveAllRead()
            })
        }
        let go = "Go to"
        if model.scope != .inbox {
            list.append(PaletteCommand(id: "inbox", title: "Inbox", section: go, icon: symbol("tray"), keys: ["G", "I"]) {
                model.select(.inbox)
            })
        }
        if model.currentProjectId != nil || model.currentRepositoryId != nil {
            list.append(PaletteCommand(id: "new", title: "New issue", section: go, icon: symbol("plus"), keys: ["C"]) {
                model.overlay = .newIssue(statusId: nil, parentItemId: nil)
            })
        }
        if model.currentProjectId != nil {
            list.append(PaletteCommand(id: "board", title: "Board", section: go, icon: symbol("rectangle.split.3x1"), keys: ["G", "B"]) {
                model.closeDetail()
                model.viewMode = .board
            })
            list.append(PaletteCommand(id: "list", title: "List", section: go, icon: symbol("list.bullet"), keys: ["G", "L"]) {
                model.closeDetail()
                model.viewMode = .list
            })
        }
        list.append(PaletteCommand(id: "mine", title: "My Issues", section: go, icon: symbol("scope"), keys: ["G", "M"]) {
            model.select(.myIssues)
        })
        list.append(PaletteCommand(id: "projects", title: "Switch project or repository…", section: go, icon: symbol("square.stack"), keys: ["G", "P"]) {
            model.overlay = .palette(.projects)
        })
        if model.canGoBack {
            list.append(PaletteCommand(id: "back", title: "Back", section: go, icon: symbol("chevron.left"), keys: ["⌘", "["]) {
                model.goBack()
            })
        }
        if model.canGoForward {
            list.append(PaletteCommand(id: "forward", title: "Forward", section: go, icon: symbol("chevron.right"), keys: ["⌘", "]"]) {
                model.goForward()
            })
        }
        for setting in AppearanceSetting.allCases where setting != model.appearance {
            list.append(PaletteCommand(id: "appearance-\(setting.rawValue)", title: "Appearance: \(setting.title)", section: "Settings", icon: symbol("circle.lefthalf.filled")) {
                model.appearance = setting
            })
        }
        list.append(PaletteCommand(id: "settings", title: "Settings…", section: "Settings", icon: symbol("gearshape"), keys: ["⌘", ","]) {
            model.settingsRequest += 1
        })
        list.append(PaletteCommand(id: "refresh", title: "Sync with GitHub now", section: go, icon: symbol("arrow.triangle.2.circlepath"), keys: ["⌘", "R"]) {
            model.refresh()
        })
        return list
    }
}
#endif
