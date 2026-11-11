import Combine
import Foundation
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Brief 82, rule 3: one source of "the calendar changed", which everything that decides what today is listens to
/// (Today, Overdue and Upcoming, the Mac board, the Flipboard's Switchboard resets, reminders, the badge and the
/// morning summary, the widgets' snapshot and timelines, calendar events). A change of time zone (a flight, Settings →
/// General → Date & Time), of the clock, of the day (midnight, or waking after it), or iOS's significant time change.
///
/// The system's own notifications come while the app runs; a change made while it was suspended is caught when it
/// comes forward: the zone and today are compared with the last ones seen. Before telling anyone, the source re-reads
/// the system zone (`NSTimeZone.resetSystemTimeZone`: Foundation keeps the zone it first read until told), so every
/// `Calendar.current` after `didChange` is the new one. Posted on the main queue, with the reason in `reasonKey`.
@MainActor
final class CalendarChange {
    static let shared = CalendarChange()

    static let didChange = Notification.Name("HITList.calendarDidChange")
    static let reasonKey = "reason"

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "dates")

    /// The system's notifications that mean the calendar changed, with the reason each is logged under.
    nonisolated static var systemTriggers: [(name: Notification.Name, reason: String)] {
        var triggers: [(name: Notification.Name, reason: String)] = [
            (.NSSystemTimeZoneDidChange, "time zone"),
            (.NSSystemClockDidChange, "clock"),
            (.NSCalendarDayChanged, "day changed"),
        ]
        #if os(iOS)
        triggers.append((UIApplication.significantTimeChangeNotification, "significant time change"))
        #endif
        return triggers
    }

    #if os(macOS)
    nonisolated static let becameActive = NSApplication.didBecomeActiveNotification
    #else
    nonisolated static let becameActive = UIApplication.didBecomeActiveNotification
    #endif

    private let center: NotificationCenter
    private let resetZone: () -> Void
    private let currentZone: () -> TimeZone
    private let clock: () -> Date
    private var observers: [NSObjectProtocol] = []
    /// The zone and the start of today last seen (at start, at each change, at each activation).
    private(set) var lastSeen: (zone: String, today: Date)?
    /// Changes posted, newest last (the Debug probe and tests read it).
    private(set) var heard: [String] = []

    init(center: NotificationCenter = .default, resetZone: @escaping () -> Void = { NSTimeZone.resetSystemTimeZone() },
         currentZone: @escaping () -> TimeZone = { TimeZone.current }, clock: @escaping () -> Date = { Date() }) {
        self.center = center
        self.resetZone = resetZone
        self.currentZone = currentZone
        self.clock = clock
    }

    var isStarted: Bool { !observers.isEmpty }

    /// Starts listening (once). `observe` calls it, so the first listener starts it.
    func start() {
        guard observers.isEmpty else { return }
        for trigger in Self.systemTriggers {
            observers.append(center.addObserver(forName: trigger.name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemSaid(trigger.reason) }
            })
        }
        observers.append(center.addObserver(forName: Self.becameActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameForward() }
        })
        remember()
        #if DEBUG
        CalendarChangeDebug.scheduleIfAsked(self)
        #endif
    }

    func stop() {
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    /// One of the system's notifications: re-read the zone, then tell everyone.
    func systemSaid(_ reason: String) {
        resetZone()
        post(reason)
    }

    /// The app came forward: a zone or a day that changed while it was suspended (or a notification that never came)
    /// is a change now.
    func cameForward() {
        resetZone()
        guard let lastSeen else { return remember() }
        let zone = currentZone()
        var calendar = Calendar.current
        calendar.timeZone = zone
        if zone.identifier != lastSeen.zone {
            post("back in another time zone")
        } else if calendar.startOfDay(for: clock()) != lastSeen.today {
            post("back on another day")
        }
    }

    private func post(_ reason: String) {
        let before = lastSeen?.zone
        remember()
        heard.append(reason)
        Self.log.notice("Calendar changed (\(reason, privacy: .public)): zone \(before ?? "?", privacy: .public) → \(self.lastSeen?.zone ?? "?", privacy: .public)")
        center.post(name: Self.didChange, object: nil, userInfo: [Self.reasonKey: reason])
    }

    private func remember() {
        let zone = currentZone()
        var calendar = Calendar.current
        calendar.timeZone = zone
        lastSeen = (zone.identifier, calendar.startOfDay(for: clock()))
    }

    // MARK: - Listening

    /// Calls `handle` with the reason each time the calendar changes, on the main actor; starts the shared source.
    /// Remove the returned observer from `center` to stop.
    static func observe(in center: NotificationCenter = .default, startShared: Bool = true,
                        _ handle: @escaping @MainActor (String) -> Void) -> NSObjectProtocol {
        if startShared { shared.start() }
        return center.addObserver(forName: didChange, object: nil, queue: .main) { note in
            let reason = note.userInfo?[reasonKey] as? String ?? "calendar"
            MainActor.assumeIsolated { handle(reason) }
        }
    }

    /// The same for a SwiftUI view's `.onReceive`: the moment the calendar changed (a view sets its `now` to it, so
    /// its body reads the new day and the new `Calendar.current`). One publisher for every view; the shared source is
    /// started at launch (`DateServices.start`).
    nonisolated static let moments: AnyPublisher<Date, Never> =
        NotificationCenter.default.publisher(for: didChange).map { _ in Date() }.eraseToAnyPublisher()
}
