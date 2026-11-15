import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
#endif

/// Settings → Calendar (brief 136; the switch was in General from brief 77): a page on the iPhone and iPad, a section
/// on the Mac's Settings page. Groups, top to bottom:
///
/// - **Calendar events**: the switch, what the permission says, and the system's settings when it was refused.
///   Switching on asks for full access (the system's prompt, once); nothing asks before that.
/// - **The calendars, by account** (iCloud, Gmail, Exchange, Subscribed Calendars, Birthdays…), each account a group
///   of its own with its calendars, each with its colour and a tick while it shows; all show by default.
/// - **Add to Calendar**: "Add tasks to", the calendar a task's Add to Calendar writes to (only calendars that take
///   changes; the device's default until one is picked), and a footer: the event is a copy.
/// - **Google Calendar**: how it gets onto this device, in words, as a real path for the platform; or, once a Google
///   account is among the calendars' accounts, that it is connected through the device. No button that leaves the app.
struct CalendarSettingsPage: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var events: CalendarEvents { CalendarEvents.shared }
    /// The switch as drawn: flips at once, then back if access is refused.
    @State private var isOn = CalendarEvents.shared.isOn

    var body: some View {
        HITGroup {
            Toggle(isOn: Binding(get: { isOn }, set: { switchTo($0) })) {
                HITMenuRowLabel("Calendar events", subtitle: Self.subtitle(for: events.access), systemImage: "calendar.badge.clock")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .accessibilityIdentifier("settings-calendar-events")
            if events.access.isRefused {
                HITMenuRow("Open system settings", subtitle: Self.settingsPath, systemImage: "gearshape", accessory: .chevron) {
                    openSystemSettings()
                }
                .accessibilityIdentifier("settings-calendar-open-settings")
            }
        }
        .onAppear {
            events.refreshAccess()
            events.start()
            isOn = events.isOn
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's settings: the permission may have changed.
            if phase == .active { events.refreshAccess() }
        }
        if events.isShowing {
            ForEach(Self.accounts(events.calendars), id: \.name) { account in
                HITGroup(account.name.isEmpty ? "Other" : account.name) {
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
        HITGroup("Add to Calendar", footer: Self.copyNote) {
            addTargetRow
        }
        HITGroup("Google Calendar") {
            SettingsNote(text: Self.googleWords(connected: events.isShowing ? events.hasGoogleAccount : nil))
                .accessibilityIdentifier("settings-calendar-google")
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
                        Text(Self.defaultChoice).tag("")
                        ForEach(Self.accounts(writable), id: \.name) { account in
                            Section(account.name) {
                                ForEach(account.calendars) { calendar in Text(calendar.title).tag(calendar.id) }
                            }
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    MenuValueLabel(text: events.addTargetCalendar?.title ?? Self.defaultChoice)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
            })
            .accessibilityIdentifier("settings-calendar-add-target")
        } else {
            HITMenuRow("Add tasks to", subtitle: "Switch on Calendar events to pick one", systemImage: "calendar.badge.plus",
                       value: Self.defaultChoice)
                .accessibilityIdentifier("settings-calendar-add-target")
        }
    }

    // MARK: - Words

    /// The switch's subtitle: what it does, or why it can't.
    static func subtitle(for access: CalendarAccess) -> String {
        switch access {
        case .denied:
            "HITList isn't allowed to read your calendars. Allow full access below."
        case .writeOnly:
            "HITList may add events but not read them. Switch on to ask, or allow full access below."
        case .restricted:
            "Calendar access is restricted on this device."
        case .notDetermined, .fullAccess:
            "Today and Upcoming show your events. Read-only, and they stay on this device."
        }
    }

    /// Where the switch is, under the system's settings (the row above it opens them).
    static let settingsPath = "Privacy & Security → Calendars → HITList"

    /// "Add tasks to" before anything is picked.
    static let defaultChoice = "Default calendar"

    /// The Add to Calendar group's footer: said once, here.
    static let copyNote = "A dated task's menu has Add to Calendar: one event at its time (30 minutes) or all day. "
        + "It's a copy: changing the task later doesn't change the event."

    /// How Google Calendar gets here, for the device it is read on. `connected`: nil while HITList can't read the
    /// calendars to tell.
    static func googleWords(connected: Bool?, device: CalendarSettingsDevice = .current) -> String {
        if connected == true {
            return "Google Calendar is connected through this \(device.name)'s accounts."
        }
        return "HITList never signs in to Google: Google Calendar comes in through this \(device.name)'s own accounts. "
            + "To add it: \(device.googlePath)."
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
    var googlePath: String {
        switch self {
        case .iPhone, .iPad:
            "Settings → Apps → Calendar → Calendar Accounts → Add Account → Google"
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
