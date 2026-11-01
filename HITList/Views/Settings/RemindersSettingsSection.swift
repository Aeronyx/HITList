import SwiftUI
import SwiftData
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Settings → Reminders: the on/off switch, the system's side (permission, what is scheduled, a link
/// to the system settings) and a test notification.
struct RemindersSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var notificationsEnabled = NotificationScheduler.isEnabled
    @AppStorage(Preferences.defaultReminderOffsetMinutes, store: AppGroup.defaults)
    private var defaultOffset = Preferences.defaultReminderOffsetDefault
    @AppStorage(Preferences.morningSummaryEnabled, store: AppGroup.defaults)
    private var morningSummary = Preferences.morningSummaryEnabledDefault
    @AppStorage(Preferences.morningSummaryMinutes, store: AppGroup.defaults)
    private var morningMinutes = Preferences.morningSummaryMinutesDefault

    /// The summary time as a Date today, for the time picker; stored as minutes after midnight.
    private var morningTime: Binding<Date> {
        Binding {
            let minutes = min(max(0, morningMinutes), 24 * 60 - 1)
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            morningMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
        }
    }
    @State private var authorization: UNAuthorizationStatus?
    @State private var scheduled = "…"
    @State private var testMessage: String?
    @State private var isSendingTest = false

    var body: some View {
        HITGroup("Reminders", footer: footer) {
            Toggle(isOn: $notificationsEnabled) {
                HITMenuRowLabel("Notify at due time", subtitle: "Only tasks with a specific time get a notification.",
                                systemImage: "bell")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .onChange(of: notificationsEnabled) { _, on in
                Task {
                    if on, !(await NotificationScheduler.requestPermission()) { notificationsEnabled = false }
                    NotificationScheduler.isEnabled = notificationsEnabled
                    await rescheduleAndRefresh()
                }
            }

            HITMenuRow("Default reminder", subtitle: "For timed tasks without a ! offset of their own.",
                       systemImage: "bell.badge", trailing: {
                Menu {
                    Picker("Default reminder", selection: $defaultOffset) {
                        ForEach(Preferences.defaultReminderOffsetChoices, id: \.self) { minutes in
                            Text(Preferences.defaultReminderLabel(minutes: minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuValueLabel(text: Preferences.defaultReminderLabel(minutes: defaultOffset))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("settings-default-reminder")
            })
            .onChange(of: defaultOffset) { _, _ in Task { await rescheduleAndRefresh() } }

            Toggle(isOn: $morningSummary) {
                HITMenuRowLabel("Morning summary",
                                subtitle: "One notification a day: today's and overdue tasks. Skipped when nothing is due.",
                                systemImage: "sun.horizon")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-morning-summary")
            .onChange(of: morningSummary) { _, on in
                Task {
                    if on, !(await NotificationScheduler.requestPermission()) { morningSummary = false }
                    await rescheduleAndRefresh()
                }
            }
            if morningSummary {
                HITMenuRow("Summary time", systemImage: "clock", trailing: {
                    DatePicker("Summary time", selection: morningTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .fixedSize()
                })
                .onChange(of: morningMinutes) { _, _ in Task { await rescheduleAndRefresh() } }
            }

            HITMenuRow("Authorization", systemImage: "hand.raised",
                       value: NotificationStatus.authorizationText(authorization))
                .accessibilityIdentifier("settings-notification-authorization")
            HITMenuRow("Open system settings", systemImage: "gearshape", accessory: .chevron) { openSystemSettings() }
            HITMenuRow("Scheduled", systemImage: "clock.badge", value: scheduled)
                .accessibilityIdentifier("settings-notification-scheduled")
            HITMenuRow("Send a test notification", systemImage: "paperplane", accessory: .none) { sendTest() }
                .disabled(isSendingTest)
                .accessibilityIdentifier("settings-notification-test")
            if let testMessage {
                Text(testMessage)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hitRowPadding()
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system settings: the permission may have changed.
            if phase == .active { Task { await refresh() } }
        }
    }

    private let footer = "Reminders are scheduled on each device from the tasks it has synced."

    private func refresh() async {
        authorization = await NotificationScheduler.authorizationStatus()
        scheduled = await NotificationScheduler.pendingSummary()
    }

    private func rescheduleAndRefresh() async {
        await NotificationScheduler.reschedule(context: context, reason: "settings")
        await refresh()
    }

    private func sendTest() {
        isSendingTest = true
        Task {
            let result = await NotificationScheduler.sendTest()
            testMessage = result.message
            isSendingTest = false
            await refresh()
            // The test has gone out (or not) by now; show the count without it.
            try? await Task.sleep(for: .seconds(NotificationScheduler.testDelay + 1))
            await refresh()
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        let url = URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #endif
        if let url { openURL(url) }
    }
}

/// The label of a Menu in a settings row: the current value in grey with an up-down chevron, like a
/// pop-up button drawn in the design system's colours.
struct MenuValueLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: HITSpacing.xs) {
            Text(text)
                .font(HITType.body)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.secondaryText)
        .contentShape(Rectangle())
    }
}
