import Foundation
import UserNotifications

/// What Settings → Reminders shows about the system's side of notifications: the permission and the
/// pending requests. Pure text functions, so they are testable without `UNUserNotificationCenter`.
enum NotificationStatus {
    /// "Allowed", "Denied", "Not asked", "Provisional".
    static func authorizationText(_ status: UNAuthorizationStatus?) -> String {
        switch status {
        case .authorized?: return "Allowed"
        case .denied?: return "Denied"
        case .notDetermined?: return "Not asked"
        case .provisional?: return "Provisional"
        #if os(iOS)
        case .ephemeral?: return "Allowed for now"
        #endif
        case nil: return "Checking…"
        @unknown default: return "Unknown"
        }
    }

    /// The pending requests in a few words: "None", "1 · next 10:45 AM", "12 · next tomorrow 9:00 AM",
    /// "3 · next Nov 4, 9:00 AM". `fireDates` holds each request's next fire date (nil = immediately).
    static func pendingText(fireDates: [Date?], now: Date, calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        guard !fireDates.isEmpty else { return "None" }
        let next = fireDates.map { $0 ?? now }.min()!
        return "\(fireDates.count) · next \(when(next, now: now, calendar: calendar, locale: locale))"
    }

    /// "10:45 AM" today, "tomorrow 9:00 AM", otherwise "Nov 4, 9:00 AM".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                    timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(time) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(date.formatted(time))"
        }
        let day = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        return "\(date.formatted(day)), \(date.formatted(time))"
    }

    /// The pending requests' next fire dates, from their triggers.
    static func fireDates(_ requests: [UNNotificationRequest]) -> [Date?] {
        requests.map { request in
            switch request.trigger {
            case let trigger as UNCalendarNotificationTrigger: return trigger.nextTriggerDate()
            case let trigger as UNTimeIntervalNotificationTrigger: return trigger.nextTriggerDate()
            default: return nil
            }
        }
    }
}

/// The result of Settings → Reminders → "Send a test notification".
enum NotificationTestResult: Equatable {
    case scheduled
    case denied
    case failed(String)

    var message: String {
        switch self {
        #if os(iOS)
        case .scheduled: return "A test notification arrives in 5 seconds. Lock the phone or go to the Home Screen now; press and hold it to see Complete and Snooze."
        #else
        case .scheduled: return "A test notification arrives in 5 seconds. Switch to another app to see it as a banner; hover it and click Options for Complete and Snooze."
        #endif
        case .denied: return "Notifications are turned off for HITList. Open system settings to allow them."
        case .failed(let reason): return "Couldn't schedule the test: \(reason)"
        }
    }
}
