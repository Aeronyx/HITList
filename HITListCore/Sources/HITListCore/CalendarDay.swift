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
    // Brief 136: what an event's card shows. Read with the event, kept in memory only, like everything here.
    /// The calendar's name ("Work").
    public let calendarTitle: String
    /// Where it happens, as the calendar has it.
    public let location: String?
    /// Its notes.
    public let notes: String?
    /// Its link (a video call, a ticket), shown as text.
    public let url: URL?
    /// The time zone it was made in (`EKEvent.timeZone`); nil for a floating or all-day event.
    public let timeZoneID: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, colorHex: String,
                calendarTitle: String = "", location: String? = nil, notes: String? = nil, url: URL? = nil,
                timeZoneID: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.colorHex = colorHex
        self.calendarTitle = calendarTitle
        self.location = location
        self.notes = notes
        self.url = url
        self.timeZoneID = timeZoneID
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

    // MARK: - An event's card (brief 136)

    /// The card's lines about when: the day ("Saturday, November 14", or "Nov 14 – Nov 16" for an event over
    /// several days), the time ("9:30 – 10:15 AM", "All day", "10:00 PM – Nov 15 at 2:00 AM"), and the time in the
    /// event's own zone when that zone's clock differs from the device's ("2:30 – 3:15 PM London time"), else nil.
    public struct CardWhen: Equatable, Sendable {
        public let day: String
        public let time: String
        public let ownZone: String?
    }

    public static func cardWhen(_ event: CalendarEvent, calendar: Calendar = .current, locale: Locale = .current) -> CardWhen {
        let zone = calendar.timeZone
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
        let start = event.start
        // An all-day event's end is the next midnight; its last day is the one before.
        let lastMoment = event.isAllDay ? max(start, event.end.addingTimeInterval(-1)) : event.end
        let oneDay = calendar.isDate(start, inSameDayAs: lastMoment)
            || (!event.isAllDay && event.end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)))
        let day: String
        if oneDay {
            day = start.formatted(dayStyle.weekday(.wide).month(.wide).day())
        } else {
            let short = dayStyle.month(.abbreviated).day()
            day = "\(start.formatted(short)) – \(lastMoment.formatted(short))"
        }
        let time: String
        if event.isAllDay {
            time = "All day"
        } else if oneDay {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? event.end
            let shown = DayEvent(event: event, day: calendar.startOfDay(for: start), dayEnd: dayEnd,
                                 span: .timed(start: start, end: event.end))
            time = timeText(shown, calendar: calendar, locale: locale)
        } else {
            let clock = dayStyle.hour().minute()
            let withDay = dayStyle.month(.abbreviated).day().hour().minute()
            time = "\(start.formatted(clock)) – \(event.end.formatted(withDay))"
        }
        var ownZone: String?
        if !event.isAllDay, let id = event.timeZoneID, let own = TimeZone(identifier: id),
           own.secondsFromGMT(for: start) != zone.secondsFromGMT(for: start) {
            var there = calendar
            there.timeZone = own
            let inner = cardWhen(CalendarEvent(id: event.id, title: event.title, start: event.start, end: event.end,
                                               isAllDay: false, calendarID: event.calendarID, colorHex: event.colorHex),
                                 calendar: there, locale: locale)
            let name = own.localizedName(for: .generic, locale: locale) ?? id
            ownZone = "\(inner.time) \(name)"
        }
        return CardWhen(day: day, time: time, ownZone: ownZone)
    }

    /// The first lines of an event's notes for its card: at most `lines` non-empty lines, trimmed; nil when none.
    public static func notesPreview(_ notes: String?, lines: Int = 3) -> String? {
        guard let notes else { return nil }
        let kept = notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(lines)
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }

    // MARK: - Accounts (brief 136)

    /// Whether a calendar account (an `EKSource`) is a Google one. The device names a Google account "Gmail" or
    /// "Google" unless the person renamed it, and the Mac often by its address; a renamed one on a Google
    /// address still ends in gmail.com or googlemail.com. Only an account HITList reads through the device:
    /// CalDAV (how iOS and macOS add Google), never a subscribed calendar that merely came from Google.
    public static func isGoogleAccount(title: String, isCalDAV: Bool) -> Bool {
        guard isCalDAV else { return false }
        let name = title.lowercased()
        return name.contains("google") || name.contains("gmail")
    }

    // MARK: - Add to Calendar (brief 136)

    /// How long the event Add to Calendar makes for a task with a time.
    public static let addedEventMinutes = 30

    /// The event a task becomes: titled as the task, at its time for 30 minutes (all day when it has no time), its
    /// notes as the event's notes, its link (`hitlist://task/<id>`) as the event's URL. No alarm: HITList reminds.
    public struct EventDraft: Equatable, Sendable {
        public let title: String
        public let start: Date
        /// The end; an all-day event's is the next day's start.
        public let end: Date
        public let isAllDay: Bool
        public let notes: String?
        public let url: URL
    }

    public static func draft(title: String, notes: String, due: Date, hasTime: Bool, link: URL,
                             calendar: Calendar = .current) -> EventDraft {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasTime {
            let end = due.addingTimeInterval(TimeInterval(addedEventMinutes * 60))
            return EventDraft(title: title, start: due, end: end, isAllDay: false, notes: trimmed.isEmpty ? nil : trimmed, url: link)
        }
        let day = calendar.startOfDay(for: due)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return EventDraft(title: title, start: day, end: next, isAllDay: true, notes: trimmed.isEmpty ? nil : trimmed, url: link)
    }

    /// Whether the task is already on the calendar: an event with its link on the draft's day.
    public static func isAlreadyAdded(_ draft: EventDraft, among events: [CalendarEvent], calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: draft.start)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return events.contains { $0.url == draft.url && covers($0, from: day, to: next) && calendar.isDate(max($0.start, day), inSameDayAs: day) }
    }
}
