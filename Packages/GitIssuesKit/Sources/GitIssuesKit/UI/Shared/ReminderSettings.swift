import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Settings for reminders of due issues: on or off, the time, and the reminder the morning after. Kept per
/// device, since each device reminds you itself.
struct ReminderSettingsSection: View {
    @Bindable private var notifier = Notifier.shared

    var body: some View {
        Section {
            Toggle("Remind me when issues assigned to me are due", isOn: $notifier.enabled)
            if notifier.enabled {
                DatePicker("Time on the due date", selection: time, displayedComponents: .hourAndMinute)
                Toggle("Again the next morning if still open", isOn: $notifier.remindsWhenOverdue)
                permission
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("The \(device) reminds you itself, from the due dates on GitHub. Nothing is sent anywhere for it.")
        }
        .onAppear { notifier.refreshAuthorization() }
    }

    @ViewBuilder
    private var permission: some View {
        switch notifier.authorization {
        case .notDetermined:
            Button("Allow Notifications") { notifier.requestPermissionIfNeeded(force: true) }
        case .denied:
            LabeledContent {
                Button("Open Settings") { openNotificationSettings() }
            } label: {
                Text("Notifications for Issues are off")
                Text("Turn them on to get reminders.")
            }
        default:
            EmptyView()
        }
    }

    private var device: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: notifier.minutes / 60, minute: notifier.minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                notifier.minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func openNotificationSettings() {
        #if os(macOS)
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
