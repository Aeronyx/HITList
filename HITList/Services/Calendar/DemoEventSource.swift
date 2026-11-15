#if DEBUG
import Foundation
import HITListCore

/// A believable day of fake calendar events for screenshots and UI tests (brief 77): `HITList -seedDemoEvents YES`.
/// It never touches the system calendar or asks for its permission; access is simply granted, and while the
/// argument is there the setting is on for the run (switch it off in Settings to see the off state). Debug builds
/// only.
///
/// Three accounts (brief 136): iCloud (Work, Home, Family), a Google one named as the device names it ("Gmail":
/// Climbing club, Personal) and Subscribed Calendars (US Holidays, which can't be changed). Today has an all-day
/// birthday and five timed events around the hour the app launched, so some are past (dimmed) and some to come
/// whenever a screenshot is taken; weekday standups run for two weeks; the days ahead have a planning meeting, a
/// dinner, a climbing evening and a three-day trip.
///
/// It writes like a calendar would (Add to Calendar), into memory: `written` is what would have been saved, and a
/// written event shows and counts as "Already on your calendar" until its Undo removes it.
///
/// For the Calendar page's other states: `-demoCalendarAccess denied` (or `restricted`, `writeOnly`,
/// `notDetermined`, which a request turns into full access) and `-demoGoogle NO` (no Google account).
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
    static let climbing = CalendarInfo(id: "demo-climbing", title: "Climbing club", colorHex: "#E67C73", source: "Gmail",
                                       isGoogle: true)
    static let personal = CalendarInfo(id: "demo-personal", title: "Personal", colorHex: "#7986CB", source: "Gmail",
                                       isGoogle: true)
    static let holidays = CalendarInfo(id: "demo-holidays", title: "US Holidays", colorHex: "#BF5AF2",
                                       source: "Subscribed Calendars", allowsChanges: false)

    private let lock = NSLock()
    private var all: [CalendarEvent]
    private var state: CalendarAccess
    private let withGoogle: Bool
    private var onChange: (@Sendable () -> Void)?
    /// What Add to Calendar would have saved, in order, with the id its Undo names.
    private(set) var written: [(id: String, draft: CalendarDay.EventDraft, calendarID: String)] = []

    init(now: Date = Date(), calendar: Calendar = .current, arguments: [String] = CommandLine.arguments) {
        let google = Self.value(after: "-demoGoogle", in: arguments).map { !["NO", "0", "false"].contains($0) } ?? true
        let googleIDs: Set<String> = [Self.climbing.id, Self.personal.id]
        withGoogle = google
        all = Self.events(now: now, calendar: calendar).filter { google || !googleIDs.contains($0.calendarID) }
        state = Self.access(named: Self.value(after: "-demoCalendarAccess", in: arguments))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }

    static func access(named name: String?) -> CalendarAccess {
        switch name {
        case "denied": .denied
        case "restricted": .restricted
        case "writeOnly": .writeOnly
        case "notDetermined": .notDetermined
        default: .fullAccess
        }
    }

    func access() -> CalendarAccess { lock.withLock { state } }
    func requestAccess() async -> CalendarAccess {
        lock.withLock {
            if state == .notDetermined { state = .fullAccess }
            return state
        }
    }
    func requestWriteAccess() async -> CalendarAccess {
        lock.withLock {
            if state == .notDetermined { state = .writeOnly }
            return state
        }
    }
    func calendars() -> [CalendarInfo] {
        guard access().canRead else { return [] }
        return [Self.work, Self.home, Self.family] + (withGoogle ? [Self.climbing, Self.personal] : []) + [Self.holidays]
    }
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access().canRead else { return [] }
        return lock.withLock { all }.filter { $0.start < end && ($0.end > start || $0.start == $0.end && $0.start >= start) }
    }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        lock.withLock { self.onChange = onChange }
    }

    func add(_ draft: CalendarDay.EventDraft, calendarID: String?) throws -> AddedCalendarEvent {
        let writable = [Self.work, Self.home, Self.family, Self.climbing, Self.personal]
        let target = writable.first { $0.id == calendarID } ?? Self.work
        let id = "demo-written-\(UUID().uuidString)"
        let event = CalendarEvent(id: id, title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay,
                                  calendarID: target.id, colorHex: target.colorHex, calendarTitle: target.title,
                                  notes: draft.notes, url: draft.url)
        let notify = lock.withLock {
            written.append((id, draft, target.id))
            all.append(event)
            return onChange
        }
        notify?()
        return AddedCalendarEvent(eventID: id, calendarTitle: state == .writeOnly ? "" : target.title)
    }

    func remove(eventID: String) throws {
        let notify = lock.withLock {
            written.removeAll { $0.id == eventID }
            all.removeAll { $0.id == eventID }
            return onChange
        }
        notify?()
    }

    /// The device's default calendar for new events, as the demo has it.
    static let defaultCalendar = work

    /// The demo's events. Today's timed ones sit around `now`'s hour (kept between 10:00 and 17:00 so the day reads
    /// as a working day): two before it, three after.
    static func events(now: Date, calendar: Calendar) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
        }
        func event(_ title: String, _ info: CalendarInfo, _ start: Date, _ end: Date, allDay: Bool = false,
                   location: String? = nil, notes: String? = nil, url: String? = nil, zone: String? = nil) -> CalendarEvent {
            CalendarEvent(id: "demo-\(title)@\(start.timeIntervalSinceReferenceDate)", title: title, start: start, end: end,
                          isAllDay: allDay, calendarID: info.id, colorHex: info.colorHex, calendarTitle: info.title,
                          location: location, notes: notes, url: url.flatMap(URL.init(string:)),
                          timeZoneID: allDay ? nil : (zone ?? calendar.timeZone.identifier))
        }
        let hour = min(max(calendar.component(.hour, from: now), 10), 17)
        var events = [
            event("Sam's birthday", family, day(0), day(1), allDay: true),
            event("Design review", work, at(0, hour - 2), at(0, hour - 1), location: "Room 4B",
                  notes: "Agenda\n- The new onboarding flow\n- Settings, page by page\n- What ships Friday\n- Q&A",
                  url: "https://meet.example.com/design-review"),
            event("Coffee with Alex", home, at(0, hour - 1, 30), at(0, hour, 15)),
            event("1:1 with Priya", work, at(0, hour + 1), at(0, hour + 1, 30), location: "Video call",
                  notes: "Priya is in San Francisco this month.", url: "https://meet.example.com/priya",
                  zone: "America/Los_Angeles"),
            event("Pick up the dry cleaning", home, at(0, hour + 1, 45), at(0, hour + 2)),
            event("Yoga", home, at(0, 19), at(0, 20)),
            event("Quarterly planning", work, at(1, 14), at(1, 15, 30)),
            event("Dinner at Jo's", family, at(2, 19), at(2, 21, 30)),
            event("Lisbon", family, day(5), day(8), allDay: true, location: "Lisbon, Portugal"),
            event("Bouldering night", climbing, at(1, 18, 30), at(1, 20, 30), location: "The Cliffs, Long Island City"),
            event("Call the plumber back", personal, at(3, 9), at(3, 9, 15)),
            event("Thanksgiving", holidays, day(12), day(13), allDay: true),
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
