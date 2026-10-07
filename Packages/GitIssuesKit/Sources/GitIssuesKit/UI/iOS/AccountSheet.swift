#if os(iOS)
import SwiftUI
import UIKit

/// Account and settings: who is signed in, how syncing is going, appearance, app icon, and signing out.
struct AccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        AccountAvatar(size: 68)
                        Text(model.viewer?.login ?? "GitHub")
                            .font(.title3.weight(.semibold))
                        Text(model.isDemo ? String(localized: .sampleDataNothingSent) : (model.viewer?.name ?? String(localized: .signedInWithGitHub)))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    HStack {
                        SyncStatusLine()
                        Spacer()
                        Button(.syncNow) { model.refresh() }
                            .disabled(model.status.phase == .syncing)
                    }
                    NavigationLink {
                        QueueScreen()
                    } label: {
                        LabeledContent(.queuedChanges, value: model.pendingCount == 0 ? String(localized: .noQueuedChanges) : "\(model.pendingCount)")
                    }
                } header: {
                    Text(.syncSection)
                } footer: {
                    Text(UIDevice.current.userInterfaceIdiom == .pad ? LocalizedStringResource.changesSavedOnIPad : .changesSavedOnIPhone)
                }

                Section(.appearance) {
                    Picker(.appearance, selection: $model.appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                ReminderSettingsSection()

                if UIApplication.shared.supportsAlternateIcons {
                    Section(.appIcon) {
                        HStack(spacing: 0) {
                            ForEach(AppIconChoice.mobile) { choice in
                                AppIconButton(choice: choice, selected: model.appIcon == choice) {
                                    model.appIcon = choice
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    if model.isDemo {
                        Button(.leaveSampleData) {
                            dismiss()
                            model.leaveDemo()
                        }
                    } else {
                        Button(.signOut, role: .destructive) { confirmSignOut = true }
                            .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(footer)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.window)
            .navigationTitle(.account)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog(.signOutOfGitHubQuestion, isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(UIDevice.current.userInterfaceIdiom == .pad ? LocalizedStringResource.signOutOnThisIPad : .signOutOnThisIPhone, role: .destructive) {
                    dismiss()
                    model.signOut()
                }
                Button(.signOutEverywhere, role: .destructive) {
                    dismiss()
                    model.signOut(everywhere: true)
                }
                Button(.cancel, role: .cancel) {}
            } message: {
                Text(.signOutEverywhereExplanation)
            }
        }
    }

    private var footer: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return model.isDemo
            ? String(localized: .appVersion(version: version))
            : String(localized: .appVersionLoginNote(version: version))
    }
}

/// One of the app icons to choose from, with a ring around the current one.
private struct AppIconButton: View {
    var choice: AppIconChoice
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                AppIconImage(choice: choice, size: 58)
                    .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Theme.accent : .clear, lineWidth: 2.5)
                )
                Text(choice.shortTitle)
                    .font(.caption)
                    .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Changes saved on this device and waiting to be sent, with the one that needs a decision marked.
struct QueueScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Shown on its own in a sheet (from the sidebar's offline card) rather than inside the account sheet.
    var showsDone = false

    var body: some View {
        let waiting = model.outbox.filter { $0.state != .sent }
        List {
            if waiting.isEmpty {
                ContentUnavailableView(.everythingSavedToGitHub, systemImage: "checkmark.circle", description: Text(.changesSavedHereFirst))
                    .listRowBackground(Color.clear)
            }
            ForEach(waiting) { entry in
                let summary = model.summary(of: entry)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(summary.number)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.text)
                        if entry.state == .conflict {
                            Text(.needsYourDecision).font(.footnote).foregroundStyle(Theme.warning)
                        } else if let error = entry.lastError {
                            Text(error).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(entry.createdAt, style: .relative)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .navigationTitle(.queuedChangesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(.syncNow) { model.refresh() }
            }
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

/// An app icon the way the Home Screen shows it: filling a rounded square.
struct AppIconImage: View {
    var choice: AppIconChoice
    var size: CGFloat

    var body: some View {
        Group {
            if let image = choice.image {
                // The images carry the Mac Dock's margin around the icon; here the icon fills the square.
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaleEffect(1.243)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2337, style: .continuous))
    }
}
#endif
