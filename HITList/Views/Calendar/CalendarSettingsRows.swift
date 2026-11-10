import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
#endif

/// Settings → General → Calendar events (brief 77): the toggle, what the permission says, and the calendars. Rows
/// for a `HITGroup` (they are its direct children, so the group draws its hairlines between them).
///
/// - Off: the toggle alone. Switching it on asks for full access (the system's prompt, once).
/// - Refused (denied, restricted or write-only): the toggle stays off, its subtitle says so, and a row opens the
///   system's settings, as Reminders does for notifications.
/// - On: a "Calendars" row ("All", "2 of 3") that opens the card of calendars, each with its colour.
struct CalendarSettingsRows: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var events: CalendarEvents { CalendarEvents.shared }
    /// The switch as drawn: flips at once, then back if access is refused.
    @State private var isOn = CalendarEvents.shared.isOn
    @State private var showsCalendars = false

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { switchTo($0) })) {
            HITMenuRowLabel("Calendar events", subtitle: Self.subtitle(for: events.access), systemImage: "calendar.badge.clock")
        }
        .toggleStyle(.hit)
        .hitRowPadding()
        .accessibilityIdentifier("settings-calendar-events")
        .onAppear {
            events.refreshAccess()
            events.start()
            isOn = events.isOn
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's settings: the permission may have changed.
            if phase == .active { events.refreshAccess() }
        }
        if events.access.isRefused {
            HITMenuRow("Open system settings", subtitle: Self.settingsPath, systemImage: "gearshape", accessory: .chevron) {
                openSystemSettings()
            }
            .accessibilityIdentifier("settings-calendar-open-settings")
        }
        if events.isShowing {
            // One child of the group, so no hairline cuts the row from its card.
            VStack(spacing: 0) {
                HITMenuRow("Calendars", systemImage: "checklist",
                           value: CalendarDay.selectionSummary(calendarIDs: events.calendars.map(\.id), hidden: events.hidden),
                           accessory: .expand(isExpanded: showsCalendars)) {
                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showsCalendars.toggle() }
                }
                .accessibilityIdentifier("settings-calendar-choice")
                if showsCalendars {
                    CalendarPickerCard(calendars: events.calendars, hidden: events.hidden) { id, shown in
                        events.setShown(shown, calendarID: id)
                    }
                    .padding(.horizontal, HITSpacing.l)
                    .padding(.bottom, HITSpacing.m)
                    .transition(.opacity)
                }
            }
        }
    }

    /// The toggle's subtitle: what it does, or why it can't.
    static func subtitle(for access: CalendarAccess) -> String {
        switch access {
        case .denied, .writeOnly:
            "HITList isn't allowed to read your calendars. Allow full access below."
        case .restricted:
            "Calendar access is restricted on this device."
        case .notDetermined, .fullAccess:
            "Today and Upcoming show your events. Read-only, and they stay on this device."
        }
    }

    /// Where the switch is, under the system's settings (the row above it opens them).
    static let settingsPath = "Privacy & Security → Calendars → HITList"

    private func switchTo(_ on: Bool) {
        isOn = on
        Task {
            let result = await events.setOn(on)
            withAnimation(HITMotion.emphasis(reduceMotion: reduceMotion)) { isOn = result }
            if !result { showsCalendars = false }
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

/// The calendars, each with its colour and a tick while it shows, grouped by account. A small card inside the
/// General group, in the design system's look (elevated, 14 pt corners, a hairline).
struct CalendarPickerCard: View {
    let calendars: [CalendarInfo]
    let hidden: Set<String>
    let onToggle: (_ calendarID: String, _ shown: Bool) -> Void

    /// Accounts in the order their calendars come (`EventKitSource` sorts by account, then title).
    private var accounts: [(name: String, calendars: [CalendarInfo])] {
        var order: [String] = []
        var byAccount: [String: [CalendarInfo]] = [:]
        for calendar in calendars {
            if byAccount[calendar.source] == nil { order.append(calendar.source) }
            byAccount[calendar.source, default: []].append(calendar)
        }
        return order.map { ($0, byAccount[$0] ?? []) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if calendars.isEmpty {
                Text("No calendars on this device.")
                    .font(HITType.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(HITSpacing.m)
            }
            ForEach(Array(accounts.enumerated()), id: \.element.name) { index, account in
                if !account.name.isEmpty {
                    Text(account.name)
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, HITSpacing.m)
                        .padding(.top, index == 0 ? HITSpacing.m : HITSpacing.l)
                        .padding(.bottom, HITSpacing.xs)
                }
                ForEach(account.calendars) { calendar in
                    CalendarChoiceRow(calendar: calendar, isShown: !hidden.contains(calendar.id)) {
                        onToggle(calendar.id, hidden.contains(calendar.id))
                    }
                }
            }
        }
        .padding(.bottom, HITSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.elevated))
        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        .clipShape(shape)
        .accessibilityIdentifier("calendarPickerCard")
    }
}

private struct CalendarChoiceRow: View {
    let calendar: CalendarInfo
    let isShown: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.m) {
                Circle()
                    .fill(Color(hex: calendar.colorHex))
                    .frame(width: 10, height: 10)
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
            .padding(.horizontal, HITSpacing.m)
            .frame(minHeight: HITRowMetrics.minHeight - 4)
            // A step lighter than the elevated card, as a row on a surface lights to elevated.
            .background(hovering ? Theme.separator.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: hovering)
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isShown)
        .accessibilityLabel(calendar.title)
        .accessibilityValue(isShown ? "Shown" : "Hidden")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}
