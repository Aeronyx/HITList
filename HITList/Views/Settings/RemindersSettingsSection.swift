import SwiftUI
import SwiftData
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Settings → Reminders: the choices (notify at due time, the default reminder, the morning summary), then at the
/// foot "If reminders don't arrive": the system's side (the permission, a link to the system's settings, what is
/// scheduled) and a test notification, which matter only when something is wrong.
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

    /// The summary time for our time field (brief 99: it was the system's picker), stored as minutes after midnight.
    private var morningTime: PickerTime { Self.summaryTime(minutes: morningMinutes) }
    /// Rebuilds the field after its × (the summary always has a time), so it shows the stored one again.
    @State private var summaryFieldRevision = 0

    static func summaryTime(minutes: Int) -> PickerTime {
        let clamped = min(max(0, minutes), 24 * 60 - 1)
        return PickerTime(hour: clamped / 60, minute: clamped % 60)
    }

    static func summaryMinutes(_ time: PickerTime) -> Int { time.hour * 60 + time.minute }

    /// The field's width in the row: the widest time ("10:30 AM", 73 pt of Inter 17 on iPhone, 56 of 13 on the Mac) with
    /// the field's padding, its clock and its × (70 pt), growing with the text size.
    #if os(macOS)
    static let summaryFieldBaseWidth: CGFloat = 132
    #else
    static let summaryFieldBaseWidth: CGFloat = 156
    #endif
    @ScaledMetric(relativeTo: .body) private var summaryFieldWidth = RemindersSettingsSection.summaryFieldBaseWidth
    static let summaryFieldMinWidth: CGFloat = 120
    @State private var authorization: UNAuthorizationStatus?
    @State private var scheduled = "…"
    @State private var testMessage: String?
    @State private var isSendingTest = false

    var body: some View {
        // No header: the page's title says Reminders.
        HITGroup(footer: footer) {
            Toggle(isOn: $notificationsEnabled) {
                HITMenuRowLabel("Notify at due time", subtitle: "Only tasks with a time",
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

            HITMenuRow("Default reminder", subtitle: "For timed tasks without a !",
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
                                subtitle: "Today's and overdue tasks, once a day",
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
                    // The cards' time field (`PickerTimeField`): type "8am", "7:30", "noon", then Return.
                    PickerTimeField(time: morningTime) { time in
                        if let time { morningMinutes = Self.summaryMinutes(time) } else { summaryFieldRevision += 1 }
                    }
                    .id(summaryFieldRevision)
                    // The title keeps its one line first; the field takes the rest, up to its width (on iPhone 16 that
                    // is 153 pt, room for "10:30 AM").
                    .frame(minWidth: Self.summaryFieldMinWidth, maxWidth: summaryFieldWidth)
                    .layoutPriority(-1)
                })
                .onChange(of: morningMinutes) { _, _ in Task { await rescheduleAndRefresh() } }
            }
        }

        HITGroup(Self.troubleTitle) {
            HITMenuRow("Permission", systemImage: "hand.raised",
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

    private let footer = "Reminders are scheduled on each device from the tasks it has synced. The summary skips a day with nothing due."
    static let troubleTitle = "If reminders don't arrive"

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
