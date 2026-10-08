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
            Toggle(.remindWhenAssignedIssuesDue, isOn: $notifier.enabled)
            if notifier.enabled {
                DatePicker(.reminderTimeOnDueDate, selection: time, displayedComponents: .hourAndMinute)
                Toggle(.remindAgainNextMorning, isOn: $notifier.remindsWhenOverdue)
                permission
            }
        } header: {
            Text(.reminders)
        } footer: {
            Text(footer)
        }
        .onAppear { notifier.refreshAuthorization() }
    }

    @ViewBuilder
    private var permission: some View {
        switch notifier.authorization {
        case .notDetermined:
            Button(.allowNotifications) { notifier.requestPermissionIfNeeded(force: true) }
        case .denied:
            LabeledContent {
                Button(.openNotificationSettings) { openNotificationSettings() }
            } label: {
                Text(.notificationsAreOff)
                Text(.turnOnNotificationsHint)
            }
        default:
            EmptyView()
        }
    }

    private var footer: LocalizedStringResource {
        switch Platform.device {
        case .mac: .remindersFooterMac
        case .iPad: .remindersFooterIPad
        case .iPhone: .remindersFooterIPhone
        }
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
