#if DEBUG
import Foundation
import HITListCore

/// A believable day of fake calendar events for screenshots and UI tests (brief 77): `HITList -seedDemoEvents YES`.
/// It never touches the system calendar or asks for its permission; access is simply granted, and while the
/// argument is there the setting is on for the run (switch it off in Settings to see the off state). Debug builds
/// only.
///
/// Three calendars (Work, Home, Family). Today has an all-day birthday and five timed events around the hour the
/// app launched, so some are past (dimmed) and some to come whenever a screenshot is taken; weekday standups run
/// for two weeks; the days ahead have a planning meeting, a dinner and a three-day trip.
final class DemoEventSource: CalendarEventSource, @unchecked Sendable {
    static let argument = "-seedDemoEvents"

    static func isRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let index = arguments.firstIndex(of: argument) else { return false }
        let next = arguments.index(after: index)
        return next == arguments.endIndex || !["NO", "0", "false"].contains(arguments[next])
    }

    static let work = CalendarInfo(id: "demo-work", title: "Work", colorHex: "#5E81F4", source: "iCloud")
    static let home = CalendarInfo(id: "demo-home", title: "Home", colorHex: "#34C759", source: "iCloud")
    static let family = CalendarInfo(id: "demo-family", title: "Family", colorHex: "#FF9F0A", source: "iCloud")

    private let all: [CalendarEvent]

    init(now: Date = Date(), calendar: Calendar = .current) {
        all = Self.events(now: now, calendar: calendar)
    }

    func access() -> CalendarAccess { .fullAccess }
    func requestAccess() async -> CalendarAccess { .fullAccess }
    func calendars() -> [CalendarInfo] { [Self.work, Self.home, Self.family] }
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        all.filter { $0.start < end && ($0.end > start || $0.start == $0.end && $0.start >= start) }
    }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {}

    /// The demo's events. Today's timed ones sit around `now`'s hour (kept between 10:00 and 17:00 so the day reads
    /// as a working day): two before it, three after.
    static func events(now: Date, calendar: Calendar) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
        }
        func event(_ title: String, _ info: CalendarInfo, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
            CalendarEvent(id: "demo-\(title)@\(start.timeIntervalSinceReferenceDate)", title: title, start: start, end: end,
                          isAllDay: allDay, calendarID: info.id, colorHex: info.colorHex)
        }
        let hour = min(max(calendar.component(.hour, from: now), 10), 17)
        var events = [
            event("Sam's birthday", family, day(0), day(1), allDay: true),
            event("Design review", work, at(0, hour - 2), at(0, hour - 1)),
            event("Coffee with Alex", home, at(0, hour - 1, 30), at(0, hour, 15)),
            event("1:1 with Priya", work, at(0, hour + 1), at(0, hour + 1, 30)),
            event("Pick up the dry cleaning", home, at(0, hour + 1, 45), at(0, hour + 2)),
            event("Yoga", home, at(0, 19), at(0, 20)),
            event("Quarterly planning", work, at(1, 14), at(1, 15, 30)),
            event("Dinner at Jo's", family, at(2, 19), at(2, 21, 30)),
            event("Lisbon", family, day(5), day(8), allDay: true),
        ]
        // Weekday standups for two weeks.
        for offset in 0..<14 {
            let weekday = calendar.component(.weekday, from: day(offset))
            guard weekday != 1, weekday != 7 else { continue }
            events.append(event("Standup", work, at(offset, 9, 30), at(offset, 9, 45)))
        }
        return events
    }
}
#endif
