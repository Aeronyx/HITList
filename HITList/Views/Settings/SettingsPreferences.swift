import Foundation

/// Preference keys that Settings v2 added (brief 21). `Preferences.swift` holds the shared ones
/// (`startTab`, `defaultReminderOffsetMinutes`, …); these follow the same rules: stored in
/// `AppGroup.defaults`, names stable once shipped.
extension Preferences {
    // MARK: Reminders

    /// One local notification a day listing today's and overdue tasks (`NotificationPlan.summaryRequest`).
    static let morningSummaryEnabled = "pref.morningSummary.enabled"
    static let morningSummaryEnabledDefault = false
    /// When the morning summary goes out, in minutes after midnight; 480 = 8:00.
    static let morningSummaryMinutes = "pref.morningSummary.minutes"
    static let morningSummaryMinutesDefault = 8 * 60

    /// The choices of Settings → Reminders → Default reminder, in minutes before the due time.
    static let defaultReminderOffsetChoices = [0, 5, 10, 15, 30, 60]

    /// "At due time", "15 min before", "1 hr before".
    static func defaultReminderLabel(minutes: Int) -> String {
        switch minutes {
        case ...0: return "At due time"
        case 60: return "1 hr before"
        case let m where m % 60 == 0: return "\(m / 60) hr before"
        default: return "\(minutes) min before"
        }
    }

    // MARK: General

    /// "sunday", "monday" or "system" (the device calendar's first weekday). Default "monday", which is
    /// what `DateExpressionParser` has always used. Read through `weekStartWeekday(calendar:)`.
    static let weekStart = "pref.weekStart"
    static let weekStartDefault = "monday"

    /// The app icon badge shows the count of overdue + today's open tasks (set by `NotificationScheduler`).
    static let showBadge = "pref.showBadge"
    static let showBadgeDefault = false

    /// Ask before deleting a task. Stored here; the delete paths (task popout, swipe actions) read it.
    static let confirmDelete = "pref.confirmDelete"
    static let confirmDeleteDefault = false

    // MARK: Readers

    /// The calendar weekday (1 = Sunday, 2 = Monday) a week starts on, for `DateExpressionParser(weekStart:)`.
    static func weekStartWeekday(_ stored: String? = AppGroup.defaults.string(forKey: weekStart),
                                 calendar: Calendar = .current) -> Int {
        switch stored ?? weekStartDefault {
        case "sunday": return 1
        case "system": return calendar.firstWeekday
        default: return 2
        }
    }

    /// The default reminder offset in minutes (never negative).
    static var defaultReminderOffset: Int {
        max(0, value(defaultReminderOffsetMinutes, default: defaultReminderOffsetDefault))
    }

    static var isMorningSummaryOn: Bool { value(morningSummaryEnabled, default: morningSummaryEnabledDefault) }

    /// The summary's time of day, clamped to a valid minute of the day.
    static var morningSummaryTime: Int {
        min(max(0, value(morningSummaryMinutes, default: morningSummaryMinutesDefault)), 24 * 60 - 1)
    }

    static var isBadgeOn: Bool { value(showBadge, default: showBadgeDefault) }

    /// The tab the iPhone opens on: the stored one if it names a tab, otherwise Today.
    static func startTabValue(_ stored: String? = AppGroup.defaults.string(forKey: startTab)) -> MobileTab {
        stored.flatMap(MobileTab.init(rawValue:)) ?? MobileTab(rawValue: startTabDefault) ?? .today
    }
}
