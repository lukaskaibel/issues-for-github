#if os(macOS)
import AppKit
import SwiftUI

/// The app's single window and its menu commands. The app target only has to show this scene.
public struct GitIssuesScene: Scene {
    @State private var model = AppModel()

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
                Button("New Issue") {
                    model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.signedIn || model.projects.isEmpty)
            }
            CommandMenu("Go") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!model.canGoForward)
                Divider()
                Button("Command Palette…") {
                    model.overlay = model.overlay == .palette(.root) ? nil : .palette(.root)
                }
                .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Board") {
                    model.closeDetail()
                    withAnimation(Theme.spring) { model.viewMode = .board }
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(model.currentProjectId == nil)
                Button("List") {
                    model.closeDetail()
                    withAnimation(Theme.spring) { model.viewMode = .list }
                }
                .keyboardShortcut("2", modifiers: .command)
                Button("My Issues") { model.select(.myIssues) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Switch Project…") { model.overlay = .palette(.projects) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Sync with GitHub Now") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Issue") {
                Button("Copy GitHub Link") {
                    if let item = model.targetItem { model.copyLink(item) }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.targetItem?.url == nil)
                Button("Copy Branch Name") {
                    if let item = model.targetItem { model.copyBranchName(item) }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.targetItem?.number == nil)
                Button("Open on GitHub") {
                    if let item = model.targetItem { model.openOnGitHub(item) }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.targetItem?.url == nil)
                Divider()
                // ⌘⌫ is handled by the key monitor, so it keeps deleting text inside text fields.
                Button("Delete Issue…") {
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
            Picker("Appearance", selection: $model.appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            LabeledContent("App icon") {
                VStack(alignment: .trailing, spacing: 8) {
                    iconRow(AppIconChoice.cards)
                    iconRow(AppIconChoice.light)
                    iconRow(AppIconChoice.dark)
                    Text("The first one follows light and dark mode. Others show in the Dock while the app is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("iPhone and iPad") {
                VStack(alignment: .trailing, spacing: 6) {
                    if model.loginIsShared {
                        Text("They sign in with this login through iCloud Keychain.")
                            .foregroundStyle(.secondary)
                    } else if model.signedIn, KeychainTokenStore.canShare {
                        Button("Share Login with iPhone and iPad") { model.shareLoginWithOtherDevices() }
                    } else {
                        Text("Sharing the login needs a build signed with your team.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }

            LabeledContent("GitHub account") {
                HStack {
                    Text(model.viewer?.login ?? "Not signed in")
                    if model.signedIn {
                        Button("Sign Out") { model.signOut() }
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
