import Foundation
import HITListCore

extension Preferences {
    /// Settings → Delight → Holiday touches: the completion bursts and the small seasonal accents during a
    /// holiday's window (`Holiday`). On by default.
    static let holidayTouches = "delight.holidayTouches"
}

/// The holiday side of completion delight: which holiday it is (the calendar, or a Debug launch argument)
/// and whether its touches are on.
enum HolidayDelight {
    /// The holiday `date` falls in, or the one `-forceHoliday` names in a Debug build.
    static func holiday(at date: Date, calendar: Calendar = .current,
                        launch: DelightLaunchOptions = .current) -> Holiday? {
        launch.forcedHoliday ?? Holiday.on(date, calendar: calendar)
    }

    static func holidayTouchesEnabled(in defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: Preferences.holidayTouches) as? Bool ?? true
    }
}

/// What a completion shows besides the sound, haptic and row motion (which never change).
struct CompletionCelebration: Equatable {
    /// The holiday's particle burst from the checkbox.
    var burst: HolidayBurstKind?
    /// The rare visitor crossing the top of the window.
    var visitor = false

    static let none = CompletionCelebration(burst: nil)

    /// Reduce Motion or Reduce Effects (`calmMotion`) turns both off; each also needs its own toggle.
    /// `visitorRoll` is the 1-in-10,000 draw (or the Debug launch argument).
    static func decide(holiday: Holiday?, holidayTouches: Bool, rareSurprises: Bool,
                       calmMotion: Bool, visitorRoll: Bool) -> CompletionCelebration {
        guard !calmMotion else { return .none }
        return CompletionCelebration(burst: holidayTouches ? holiday?.burst : nil,
                                     visitor: rareSurprises && visitorRoll)
    }
}

/// Debug-only launch arguments that demo the delight without waiting for a holiday:
/// `-forceHoliday christmas` (any `Holiday(argument:)` name) treats every day as that holiday.
/// Release builds ignore them (`current` reads no arguments there).
struct DelightLaunchOptions: Equatable {
    var forcedHoliday: Holiday?

    static let none = DelightLaunchOptions(arguments: [])

    static let current: DelightLaunchOptions = {
        #if DEBUG
        DelightLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        .none
        #endif
    }()

    init(arguments: [String]) {
        if let i = arguments.firstIndex(of: "-forceHoliday"), i + 1 < arguments.count {
            forcedHoliday = Holiday(argument: arguments[i + 1])
        }
    }
}
