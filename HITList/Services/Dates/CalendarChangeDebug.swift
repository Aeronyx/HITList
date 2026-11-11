#if DEBUG
import Foundation

/// Brief 82, item 6: a time-zone change while the app is open, without touching the system's settings (no session may
/// change a system setting). `-calendarChangeTo Asia/Tokyo` (and `-calendarChangeAfter 20`, seconds, default 15) sets
/// this process's zone (`NSTimeZone.default`, which `Calendar.current` follows) and then posts
/// the system's own `NSSystemTimeZoneDidChange`, so everything downstream runs as it would after a flight. Debug only.
@MainActor
enum CalendarChangeDebug {
    static func scheduleIfAsked(_ source: CalendarChange, arguments: UserDefaults = .standard) {
        guard let id = arguments.string(forKey: "calendarChangeTo"), let zone = TimeZone(identifier: id) else { return }
        // A launch argument arrives as a string; `double(forKey:)` reads "90" as 90.
        let after = arguments.object(forKey: "calendarChangeAfter") == nil ? 15 : max(0, arguments.double(forKey: "calendarChangeAfter"))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(after))
            NSTimeZone.default = zone
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
    }
}
#endif
