import Foundation
import Observation
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The calendar events Today and Upcoming show (brief 77), read-only and on the device. Off by default: while off it
/// loads nothing and never prompts (Settings only reads the permission to say what it is), and every day has no
/// events, so every screen is as it was. Switched on (Settings → General → Calendar events) it asks for full access once, then keeps the events of
/// the days ahead in memory only, reloading when the calendars change (`EKEventStoreChanged`), at midnight, when the
/// app becomes active and when the setting or the choice of calendars changes. A load never blocks a list: the
/// events arrive after the tasks if they must.
@MainActor
@Observable
final class CalendarEvents {
    static let shared = CalendarEvents(source: CalendarEvents.defaultSource())

    /// EventKit on a device.
    static func defaultSource(arguments: [String] = CommandLine.arguments) -> any CalendarEventSource {
        EventKitSource()
    }

    @ObservationIgnored private let source: any CalendarEventSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendarProvider: () -> Calendar
    @ObservationIgnored private let clock: () -> Date

    /// The setting (`Preferences.calendarEvents`).
    private(set) var isOn: Bool
    private(set) var access: CalendarAccess = .notDetermined
    /// The device's calendars, once access allows reading them.
    private(set) var calendars: [CalendarInfo] = []
    /// Calendars the person switched off (`Preferences.calendarEventsHidden`); new calendars show.
    private(set) var hidden: Set<String>
    /// Every occurrence from the start of today up to `horizon`.
    private(set) var loaded: [CalendarEvent] = []
    /// How many loads have finished (tests wait on it).
    private(set) var loads = 0

    /// The end of the days loaded; a list that reaches further asks for more (`cover(through:)`).
    @ObservationIgnored private(set) var horizon: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var dayCache: [String: [DayEvent]] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Days loaded past today at first, and each time a list reaches the end of them.
    static let pageDays = 62

    init(source: any CalendarEventSource, defaults: UserDefaults = AppGroup.defaults,
         calendar: @escaping () -> Calendar = { .current }, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.defaults = defaults
        self.calendarProvider = calendar
        self.clock = now
        isOn = defaults.object(forKey: Preferences.calendarEvents) as? Bool ?? Preferences.calendarEventsDefault
        hidden = Set(defaults.stringArray(forKey: Preferences.calendarEventsHidden) ?? [])
    }

    /// Showing events: switched on and allowed to read.
    var isShowing: Bool { isOn && access.canRead }

    /// The events `day` shows, in order (`CalendarDay`); none while off or not allowed.
    func events(on day: Date, calendar: Calendar = .current) -> [DayEvent] {
        // Read the observed state first so a view that asks is redrawn when it changes.
        guard isShowing else { return [] }
        let all = loaded, hidden = hidden
        let key = "\(calendar.startOfDay(for: day).timeIntervalSinceReferenceDate)|\(calendar.timeZone.identifier)"
        if let cached = dayCache[key] { return cached }
        let shown = CalendarDay.events(all, on: day, hiding: hidden, calendar: calendar)
        dayCache[key] = shown
        return shown
    }

    // MARK: - Starting

    /// Called by every list that shows events; once is enough. Off, it only reads the setting.
    func start() {
        guard !started else { return }
        started = true
        guard isOn else { return }
        beginWatching()
        Task { await reload() }
    }

    private func beginWatching() {
        guard observers.isEmpty else { return }
        source.observeChanges { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
        let center = NotificationCenter.default
        // Midnight (and a change of the clock or time zone): today's events are tomorrow's now.
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.reload() }
            })
        }
        #if os(iOS)
        let active = UIApplication.didBecomeActiveNotification
        #else
        let active = NSApplication.didBecomeActiveNotification
        #endif
        // Back from the system's settings, or after a while away: the permission or the events may have changed.
        observers.append(center.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        })
    }

    // MARK: - The setting

    /// Switches events on or off. On asks for access the first time; refused, the setting stays off and `access`
    /// says why. Returns whether it is on.
    @discardableResult
    func setOn(_ on: Bool) async -> Bool {
        guard on else {
            isOn = false
            defaults.set(false, forKey: Preferences.calendarEvents)
            clear()
            return false
        }
        var current = source.access()
        if current == .notDetermined { current = await source.requestAccess() }
        access = current
        guard current.canRead else {
            isOn = false
            defaults.set(false, forKey: Preferences.calendarEvents)
            clear()
            return false
        }
        isOn = true
        defaults.set(true, forKey: Preferences.calendarEvents)
        started = true
        beginWatching()
        await reload()
        return true
    }

    /// Shows or hides one calendar's events.
    func setShown(_ shown: Bool, calendarID: String) {
        if shown { hidden.remove(calendarID) } else { hidden.insert(calendarID) }
        defaults.set(hidden.sorted(), forKey: Preferences.calendarEventsHidden)
        dayCache = [:]
    }

    /// Reads the permission again without loading anything (Settings shows it while the setting is off).
    func refreshAccess() {
        access = source.access()
    }

    // MARK: - Loading

    /// Makes sure the events reach `day` (the end of an Upcoming list, a board window moved ahead).
    func cover(through day: Date) {
        guard isShowing, let horizon, day >= horizon else { return }
        let calendar = calendarProvider()
        self.horizon = calendar.date(byAdding: .day, value: Self.pageDays, to: calendar.startOfDay(for: day))
        Task { await reload() }
    }

    /// Reads the permission, the calendars and the events again, from the start of today to `horizon` (at least
    /// `pageDays` ahead). A newer reload wins over one still running.
    func reload() async {
        access = source.access()
        guard isOn, access.canRead else {
            clear()
            return
        }
        generation += 1
        let mine = generation
        let calendar = calendarProvider()
        let start = calendar.startOfDay(for: clock())
        let minimum = calendar.date(byAdding: .day, value: Self.pageDays, to: start)!
        let end = max(minimum, horizon ?? minimum)
        horizon = end
        let source = source
        let (calendars, events) = await Task.detached(priority: .userInitiated) {
            (source.calendars(), source.events(from: start, to: end))
        }.value
        guard mine == generation, isOn else { return }
        self.calendars = calendars
        loaded = events
        dayCache = [:]
        loads += 1
    }

    private func clear() {
        generation += 1
        if !loaded.isEmpty { loaded = [] }
        if !calendars.isEmpty { calendars = [] }
        dayCache = [:]
        horizon = nil
    }
}

extension Preferences {
    /// Settings → General → Calendar events (brief 77). Device-local, like every preference: calendars differ per
    /// device, and the permission is the device's.
    static let calendarEvents = "pref.calendarEvents.enabled"
    static let calendarEventsDefault = false
    /// The calendar identifiers switched off in the calendar card; every other calendar shows (all by default).
    static let calendarEventsHidden = "pref.calendarEvents.hiddenCalendars"
}
