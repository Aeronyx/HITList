import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
#endif

/// Settings → Calendar (brief 136; the switch was in General from brief 77; brief 163 made it read in ten seconds): a
/// page on the iPhone and iPad, a section on the Mac's Settings page. Groups, top to bottom:
///
/// - **Show calendar events**: the switch, and under it Access, the permission in one word ("Not asked yet",
///   "Allowed", "Not allowed"…); refused, the Access row is the one tap to the system's settings. Switching on asks
///   for full access (the system's prompt, once); nothing asks before that.
/// - **The calendars, by account** (iCloud, Gmail, Exchange, Subscribed Calendars, Birthdays…), only while events
///   show: each account a group of its own with its calendars, each with its colour and a tick while it shows; all
///   show by default.
/// - **Google Calendar**: one row, connected through the device's accounts, or the device's own path to add it. No
///   button that leaves the app.
/// - **Add to Calendar**: "Add tasks to", the calendar a task's Add to Calendar writes to (only calendars that take
///   changes; the device's default until one is picked), and a footer: the event is a copy.
struct CalendarSettingsPage: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var events: CalendarEvents { CalendarEvents.shared }
    /// The switch as drawn: flips at once, then back if access is refused. Off whenever access is refused, even if the
    /// setting is on (access withdrawn in the system's settings afterwards): nothing shows then.
    @State private var isOn = Self.drawnOn(CalendarEvents.shared)

    static func drawnOn(_ events: CalendarEvents) -> Bool { events.isOn && !events.access.isRefused }

    var body: some View {
        HITGroup(footer: Self.switchFooter) {
            Toggle(isOn: Binding(get: { isOn }, set: { switchTo($0) })) {
                HITMenuRowLabel(Self.switchTitle, subtitle: Self.switchSubtitle, systemImage: "calendar.badge.clock")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-calendar-events")
            if events.access.isRefused {
                // Refused: the row is the one tap that fixes it.
                HITMenuRow("Access", subtitle: Self.subtitle(for: events.access), systemImage: "hand.raised",
                           iconTint: HITColor.dueTomorrow, value: Self.accessWord(events.access), accessory: .chevron) {
                    openSystemSettings()
                }
                .accessibilityIdentifier("settings-calendar-open-settings")
            } else {
                HITMenuRow("Access", systemImage: "hand.raised", value: Self.accessWord(events.access))
                    .accessibilityIdentifier("settings-calendar-access")
            }
        }
        .onAppear {
            events.refreshAccess()
            events.start()
            isOn = Self.drawnOn(events)
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's settings: the permission may have changed.
            if phase == .active { events.refreshAccess() }
        }
        .onChange(of: events.access) { _, _ in isOn = Self.drawnOn(events) }
        if events.isShowing {
            let accounts = Self.accounts(events.calendars)
            ForEach(accounts, id: \.name) { account in
                // The last account's group says what a tap does, once.
                HITGroup(account.name.isEmpty ? "Other" : account.name,
                         footer: account.name == accounts.last?.name ? Self.calendarsFooter : nil) {
                    ForEach(account.calendars) { calendar in
                        CalendarChoiceRow(calendar: calendar, isShown: !events.hidden.contains(calendar.id)) {
                            events.setShown(events.hidden.contains(calendar.id), calendarID: calendar.id)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings-calendar-account-\(account.name)")
            }
        }
        HITGroup {
            let connected = events.isShowing && events.hasGoogleAccount
            // Words only: no button that leaves the app.
            HITMenuRowLabel("Google Calendar", subtitle: Self.googleWords(connected: events.isShowing ? events.hasGoogleAccount : nil),
                            systemImage: connected ? "checkmark.circle" : "person.crop.circle.badge.plus",
                            iconTint: connected ? Theme.accent : Theme.secondaryText)
                .foregroundStyle(HITColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .hitRowPadding()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings-calendar-google")
        }
        HITGroup("Add to Calendar", footer: Self.copyNote) {
            addTargetRow
        }
    }

    @ViewBuilder private var addTargetRow: some View {
        let writable = events.writableCalendars
        if events.isShowing, !writable.isEmpty {
            // `trailing:` spelled out: a bare trailing closure picks HITMenuRow's action initializer.
            HITMenuRow("Add tasks to", systemImage: "calendar.badge.plus", trailing: {
                Menu {
                    Picker("Add tasks to", selection: Binding(get: { events.addTargetCalendar?.id ?? "" },
                                                              set: { events.setAddTarget($0.isEmpty ? nil : $0) })) {
                        Text(Self.defaultChoice(events.defaultCalendar)).tag("")
                        ForEach(Self.accounts(writable), id: \.name) { account in
                            Section(account.name) {
                                ForEach(account.calendars) { calendar in Text(calendar.title).tag(calendar.id) }
                            }
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuValueLabel(text: Self.addTargetValue(picked: events.addTargetCalendar, default: events.defaultCalendar))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
            })
            .accessibilityIdentifier("settings-calendar-add-target")
        } else {
            HITMenuRow("Add tasks to", subtitle: Self.addTargetOffNote, systemImage: "calendar.badge.plus",
                       value: Self.defaultChoice(nil))
                .accessibilityIdentifier("settings-calendar-add-target")
        }
    }

    // MARK: - Words

    static let switchTitle = "Show calendar events"
    /// What the switch does, in one line.
    static let switchSubtitle = "Your events in Today and Upcoming"
    /// Under the switch and Access: when it asks, and what it does with what it reads.
    static let switchFooter = "HITList asks for access when you switch this on. It only reads your events, and they stay on this device."
    static let calendarsFooter = "Tap a calendar to show or hide its events."

    /// The permission in a word or two, as Access's value.
    static func accessWord(_ access: CalendarAccess) -> String {
        switch access {
        case .notDetermined: "Not asked yet"
        case .fullAccess: "Allowed"
        case .denied: "Not allowed"
        case .writeOnly: "Add only"
        case .restricted: "Restricted"
        }
    }

    /// Under Access when it is refused: what fixes it (the row opens the system's settings). Nil while it is fine.
    static func subtitle(for access: CalendarAccess) -> String? {
        switch access {
        case .denied: "HITList isn't allowed to read your calendars. Tap to allow it in \(settingsPath)"
        case .writeOnly: "HITList can add events but not read them. Tap to allow full access in \(settingsPath)"
        case .restricted: "Calendar access is restricted on this device (Screen Time or a device profile)"
        case .notDetermined, .fullAccess: nil
        }
    }

    /// Where the permission is, under the system's settings (the Access row opens them).
    static let settingsPath = "Privacy & Security → Calendars → HITList"

    /// "Add tasks to"'s subtitle while it can't list the calendars.
    static let addTargetOffNote = "Switch on events above to pick one"

    /// The menu's first choice: the device's default calendar, by name once it can be read.
    static func defaultChoice(_ calendar: CalendarInfo?) -> String {
        calendar.map { "Default (\($0.title))" } ?? "Default calendar"
    }

    /// "Add tasks to"'s value: the picked calendar, or the default one named ("Work (default)").
    static func addTargetValue(picked: CalendarInfo?, default fallback: CalendarInfo?) -> String {
        if let picked { return picked.title }
        return fallback.map { "\($0.title) (default)" } ?? "Default calendar"
    }

    /// The Add to Calendar group's footer: said once, here.
    static let copyNote = "Add to Calendar is in a dated task's menu. The event is a copy: later changes to the task don't change it."

    /// The Google Calendar row's subtitle, for the device it is read on. `connected`: nil while HITList can't read the
    /// calendars to tell.
    static func googleWords(connected: Bool?, device: CalendarSettingsDevice = .current) -> String {
        if connected == true {
            return "Connected through this \(device.name)'s accounts"
        }
        return "Add your Google account to this \(device.name): \(device.googlePath)"
    }

    /// Accounts in the order their calendars come (`EventKitSource` sorts by account, then title).
    static func accounts(_ calendars: [CalendarInfo]) -> [(name: String, calendars: [CalendarInfo])] {
        var order: [String] = []
        var byAccount: [String: [CalendarInfo]] = [:]
        for calendar in calendars {
            if byAccount[calendar.source] == nil { order.append(calendar.source) }
            byAccount[calendar.source, default: []].append(calendar)
        }
        return order.map { ($0, byAccount[$0] ?? []) }
    }

    private func switchTo(_ on: Bool) {
        isOn = on
        Task {
            let result = await events.setOn(on)
            withAnimation(HITMotion.emphasis(reduceMotion: reduceMotion)) { isOn = result }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        // The app's own page in Settings, where its Calendars permission is.
        let url = URL(string: UIApplication.openSettingsURLString)
        #else
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #endif
        if let url { openURL(url) }
    }
}

/// The device the Calendar page's words are read on, for the path to its own settings.
enum CalendarSettingsDevice: Equatable {
    case iPhone, iPad, mac

    static var current: CalendarSettingsDevice {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }

    /// The way a Google account's calendars come onto the device, as its own settings name it.
    var googlePath: String { googlePath(systemMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) }

    /// Read on the real things (brief 136): iOS 27's Settings → Apps → Calendar has "Add Account…" in its header,
    /// which asks for an address or offers "choose from a list" (iOS 27.0 simulator, 2026-11-14); iOS 18 had a
    /// Calendar Accounts row first. The Mac's from its Internet Accounts strings (macOS 26.7.1).
    func googlePath(systemMajor: Int) -> String {
        switch self {
        case .iPhone, .iPad:
            systemMajor >= 27
                ? "Settings → Apps → Calendar → Add Account…, then your Google address (or choose from a list → Google)"
                : "Settings → Apps → Calendar → Calendar Accounts → Add Account → Google"
        case .mac:
            "System Settings → Internet Accounts → Add Account… → Google, with Calendars switched on"
        }
    }
}

/// One calendar on the Calendar page: its colour, its name, a tick while it shows. A row of a `HITGroup`.
struct CalendarChoiceRow: View {
    let calendar: CalendarInfo
    let isShown: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.m) {
                Circle()
                    .fill(Color(hex: calendar.colorHex))
                    .frame(width: 12, height: 12)
                    .frame(width: HITRowMetrics.iconColumn)
                Text(calendar.title)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                Spacer(minLength: HITSpacing.s)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isShown ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HITRowButtonStyle())
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isShown)
        .accessibilityLabel(calendar.title)
        .accessibilityValue(isShown ? "Shown" : "Hidden")
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .accessibilityIdentifier("settings-calendar-\(calendar.title)")
    }
}
