#if DEBUG
import Foundation

/// Brief 82, item 6: a time-zone change while the app is open, without touching the system's settings (no session may
/// change a system setting). `-calendarChangeTo Asia/Tokyo` (and `-calendarChangeAfter 20`, seconds, default 15) sets
/// this process's zone (`NSTimeZone.default`, which `TimeZone.current` and `Calendar.current` follow) and then posts
/// the system's own `NSSystemTimeZoneDidChange`, so everything downstream runs as it would after a flight. Debug only.
@MainActor
enum CalendarChangeDebug {
    static func scheduleIfAsked(_ source: CalendarChange, arguments: UserDefaults = .standard) {
        guard let id = arguments.string(forKey: "calendarChangeTo"), let zone = TimeZone(identifier: id) else { return }
        let after = arguments.object(forKey: "calendarChangeAfter") as? Double ?? 15
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(after))
            NSTimeZone.default = zone
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
    }
}
#endif
