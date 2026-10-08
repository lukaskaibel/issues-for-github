#if os(macOS)
import AppKit
import SwiftUI

/// The app's single window and its menu commands. The app target only has to show this scene.
public struct GitIssuesScene: Scene {
    @State private var model = AppModel.shared

    public init() {}

    public var body: some Scene {
        Window("Issues", id: "main") {
            RootView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(.newIssue) {
                    model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.signedIn || model.projects.isEmpty)
            }
            CommandMenu(.goMenu) {
                Button(.back) { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                Button(.forward) { model.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!model.canGoForward)
                Divider()
                Button(.commandPaletteEllipsis) {
                    model.overlay = model.overlay == .palette(.root) ? nil : .palette(.root)
                }
                .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button(.board) {
                    model.closeDetail()
                    withAnimation(Theme.spring) { model.viewMode = .board }
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(model.currentProjectId == nil)
                Button(.list) {
                    model.closeDetail()
                    withAnimation(Theme.spring) { model.viewMode = .list }
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(model.scope == .inbox)
                Button(.myIssues) { model.select(.myIssues) }
                    .keyboardShortcut("3", modifiers: .command)
                Button(.inbox) { model.select(.inbox) }
                Button(.switchProjectEllipsis) { model.overlay = .palette(.projects) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button(.syncWithGitHubNow) { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu(.issueMenu) {
                Button(.copyGitHubLink) {
                    if let item = model.targetItem { model.copyLink(item) }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.targetItem?.url == nil)
                Button(.copyBranchName) {
                    if let item = model.targetItem { model.copyBranchName(item) }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.targetItem?.number == nil)
                Button(.openOnGitHub) {
                    if let item = model.targetItem { model.openOnGitHub(item) }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.targetItem?.url == nil)
                Divider()
                // ⌘⌫ is handled by the key monitor, so it keeps deleting text inside text fields.
                Button(.deleteIssue) {
                    if let item = model.targetItem { model.requestDelete(item) }
                }
                .disabled(model.targetItem.map { !model.canDelete($0) } ?? true)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker(.appearance, selection: $model.appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle(.showDockBadgeSetting, isOn: $model.showsDockBadge)

            LabeledContent(.appIconMac) {
                VStack(alignment: .trailing, spacing: 8) {
                    iconRow(AppIconChoice.cards)
                    iconRow(AppIconChoice.light)
                    iconRow(AppIconChoice.dark)
                    Text(.appIconFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ReminderSettingsSection()

            // Sample data has no login to share.
            if !model.isDemo {
                LabeledContent(.iPhoneAndIPad) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if model.loginIsShared {
                            Text(.loginSharedWithDevices)
                                .foregroundStyle(.secondary)
                        } else if model.signedIn, KeychainTokenStore.canShare {
                            Button(.shareLoginWithDevices) { model.shareLoginWithOtherDevices() }
                        } else {
                            Text(.sharingNeedsSignedBuild)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }

            LabeledContent(.gitHubAccount) {
                HStack {
                    Text(model.isDemo ? String(localized: .sampleData) : model.viewer?.login ?? String(localized: .notSignedIn))
                    if model.isDemo {
                        Button(.leaveSampleData) { model.leaveDemo() }
                    } else if model.signedIn {
                        Button(.signOut) { model.signOut() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func iconRow(_ choices: [AppIconChoice]) -> some View {
        HStack(spacing: 10) {
            ForEach(choices) { choice in
                Button {
                    model.appIcon = choice
                } label: {
                    Group {
                        if let image = choice.image {
                            Image(nsImage: image).resizable().interpolation(.high)
                        } else {
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(model.appIcon == choice ? Color.accentColor : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(model.appIcon == choice ? .isSelected : [])
            }
        }
    }
}
#endif
