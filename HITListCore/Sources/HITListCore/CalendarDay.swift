import Foundation

// Brief 77: the person's calendar events beside their tasks, read-only and on the device. These are the rules for
// which events a day shows and in what order; the app reads the events (EventKit) and draws them. An event is never
// a task: it is not a `FilterableTask`, so no filter, count, badge, search or export can take one.

/// One occurrence of a calendar event, as the app read it. Only what a row draws.
public struct CalendarEvent: Hashable, Sendable, Identifiable {
    /// Unique per occurrence: a repeating event's occurrences share their event's identifier, so the app adds the start.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// The calendar it belongs to (`EKCalendar.calendarIdentifier`), for the person's choice of calendars.
    public let calendarID: String
    /// The calendar's colour, "#RRGGBB".
    public let colorHex: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, colorHex: String) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.colorHex = colorHex
    }
}

/// An event as one day shows it.
public struct DayEvent: Hashable, Sendable, Identifiable {
    /// How much of the day it takes.
    public enum Span: Hashable, Sendable {
        /// An all-day event, or a longer one that covers this day from midnight to midnight.
        case allDay
        /// Starts and ends on this day (an event ending at the next midnight counts as ending on this day).
        case timed(start: Date, end: Date)
        /// Starts on this day and runs past its end.
        case from(Date)
        /// Started before this day and ends on it.
        case until(Date)
    }

    public let event: CalendarEvent
    /// The day, at its start.
    public let day: Date
    /// The day's end: the next day's start (23 or 25 hours later on a daylight-saving day).
    public let dayEnd: Date
    public let span: Span

    public var id: String { event.id }
    public var isAllDay: Bool { span == .allDay }

    /// Where it sorts among the day's timed events: its start, or the day's start for one that began before it.
    var sortStart: Date { max(event.start, day) }
    /// When it stops taking up this day.
    var shownEnd: Date { isAllDay ? dayEnd : min(event.end, dayEnd) }
}

public enum CalendarDay {
    /// The events `day` shows (the day containing it, in `calendar`'s time zone): all-day ones first by title, then
    /// timed ones by start, then end, then title. An event shows on every day it covers; one that ends exactly at
    /// midnight is not on the next day. Events from a calendar in `hidden` are left out.
    public static func events(_ events: [CalendarEvent], on day: Date, hiding hidden: Set<String> = [],
                              calendar: Calendar) -> [DayEvent] {
        let start = calendar.startOfDay(for: day)
        // Never start + 24 h: a daylight-saving day is 23 or 25 hours long.
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let shown = events.compactMap { event -> DayEvent? in
            guard !hidden.contains(event.calendarID), covers(event, from: start, to: end) else { return nil }
            return DayEvent(event: event, day: start, dayEnd: end, span: span(of: event, from: start, to: end))
        }
        return shown.sorted(by: order)
    }

    /// Whether the event takes up any of [start, end). An instant event counts on the day of its instant.
    static func covers(_ event: CalendarEvent, from start: Date, to end: Date) -> Bool {
        if event.start == event.end { return event.start >= start && event.start < end }
        return event.start < end && event.end > start
    }

    static func span(of event: CalendarEvent, from start: Date, to end: Date) -> DayEvent.Span {
        if event.isAllDay { return .allDay }
        let startsBefore = event.start < start, endsAfter = event.end > end
        switch (startsBefore, endsAfter) {
        case (true, true): return .allDay
        case (true, false): return event.end == end ? .allDay : .until(event.end)
        case (false, true): return .from(event.start)
        case (false, false): return .timed(start: event.start, end: event.end)
        }
    }

    static func order(_ a: DayEvent, _ b: DayEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if !a.isAllDay {
            if a.sortStart != b.sortStart { return a.sortStart < b.sortStart }
            if a.shownEnd != b.shownEnd { return a.shownEnd < b.shownEnd }
        }
        let byTitle = a.event.title.localizedStandardCompare(b.event.title)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return a.event.id < b.event.id
    }

    /// The row's second line: "9:30 – 10:15 AM", "11:30 AM – 1:00 PM", "All day", "From 10:00 PM", "Until 2:00 AM";
    /// "3:00 PM" for an instant. In the locale's own clock ("09:30 – 17:00" in German).
    public static func timeText(_ shown: DayEvent, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = style.hour().minute()
        switch shown.span {
        case .allDay:
            return "All day"
        case .from(let start):
            return "From \(start.formatted(time))"
        case .until(let end):
            return "Until \(end.formatted(time))"
        case .timed(let start, let end):
            if start == end { return start.formatted(time) }
            // "9:30 – 10:15 AM": a 12-hour clock says AM or PM once when both ends share it.
            let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? ""
            if pattern.contains("a"), period(of: start, calendar: calendar) == period(of: end, calendar: calendar) {
                // The locale's own pattern less its day period ("h:mm a" → "h:mm"; FormatStyle's `amPM: .omitted`
                // pads the hour to "09").
                let bare = DateFormatter()
                bare.locale = locale
                bare.calendar = calendar
                bare.timeZone = calendar.timeZone
                bare.dateFormat = pattern.replacingOccurrences(of: "a", with: "")
                    .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{202F}\u{00A0}")))
                return "\(bare.string(from: start)) – \(end.formatted(time))"
            }
            return "\(start.formatted(time)) – \(end.formatted(time))"
        }
    }

    private static func period(of date: Date, calendar: Calendar) -> Bool { calendar.component(.hour, from: date) < 12 }

    /// Past events dim: one whose time on this day is over (an all-day one once its day is).
    public static func isPast(_ shown: DayEvent, now: Date) -> Bool { shown.shownEnd <= now }

    /// The calendar row's value: "All", "2 of 3", "None". A hidden calendar that is gone doesn't count.
    public static func selectionSummary(calendarIDs: [String], hidden: Set<String>) -> String {
        let shown = calendarIDs.filter { !hidden.contains($0) }.count
        if shown == calendarIDs.count { return "All" }
        if shown == 0 { return "None" }
        return "\(shown) of \(calendarIDs.count)"
    }
}
