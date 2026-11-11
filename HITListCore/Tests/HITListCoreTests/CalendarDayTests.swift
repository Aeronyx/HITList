import Foundation
import XCTest
@testable import HITListCore

/// Brief 77: which calendar events a day shows and in what order. Events are read-only and never tasks; these rules
/// only place them beside the tasks.
final class CalendarDayTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = 2
        return c
    }

    private func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, calendarID: String = "work",
                       title: String? = nil) -> CalendarEvent {
        CalendarEvent(id: id, title: title ?? id, start: start, end: end, isAllDay: allDay,
                      calendarID: calendarID, colorHex: "#5E81F4")
    }

    /// The narrow and thin spaces the formatters put around "–" and before "AM", as plain spaces.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
    }

    // MARK: Which events, in what order

    func testAllDayFirstThenTimedByStart() {
        let c = calendar("Europe/London")
        let day = date(c, 2026, 11, 10)
        let events = [
            event("standup", date(c, 2026, 11, 10, 9, 30), date(c, 2026, 11, 10, 10, 15)),
            event("lunch", date(c, 2026, 11, 10, 12), date(c, 2026, 11, 10, 13)),
            event("holiday", day, date(c, 2026, 11, 11), allDay: true),
            event("early", date(c, 2026, 11, 10, 8), date(c, 2026, 11, 10, 8, 30)),
            event("birthday", day, date(c, 2026, 11, 10, 23, 59), allDay: true, title: "Alex's birthday"),
            event("tomorrow", date(c, 2026, 11, 11, 9), date(c, 2026, 11, 11, 10)),
            event("yesterday", date(c, 2026, 11, 9, 9), date(c, 2026, 11, 9, 10)),
        ]
        let shown = CalendarDay.events(events, on: day, calendar: c).map(\.event.id)
        XCTAssertEqual(shown, ["birthday", "holiday", "early", "standup", "lunch"],
                       "all-day first by title, then timed by start; other days' events left out")
    }

    func testSameStartOrdersByEndThenTitle() {
        let c = calendar("UTC")
        let day = date(c, 2026, 11, 10)
        let events = [
            event("b-long", date(c, 2026, 11, 10, 9), date(c, 2026, 11, 10, 11)),
            event("b-short", date(c, 2026, 11, 10, 9), date(c, 2026, 11, 10, 9, 30)),
            event("a-long", date(c, 2026, 11, 10, 9), date(c, 2026, 11, 10, 11)),
        ]
        XCTAssertEqual(CalendarDay.events(events, on: day, calendar: c).map(\.event.id), ["b-short", "a-long", "b-long"])
    }

    func testMultiDayTimedEventShowsOnEachDayItCovers() {
        let c = calendar("UTC")
        let trip = event("trip", date(c, 2026, 11, 10, 22), date(c, 2026, 11, 12, 2))
        let first = CalendarDay.events([trip], on: date(c, 2026, 11, 10), calendar: c)
        let middle = CalendarDay.events([trip], on: date(c, 2026, 11, 11), calendar: c)
        let last = CalendarDay.events([trip], on: date(c, 2026, 11, 12), calendar: c)
        let after = CalendarDay.events([trip], on: date(c, 2026, 11, 13), calendar: c)
        XCTAssertEqual(first.map(\.span), [.from(date(c, 2026, 11, 10, 22))])
        XCTAssertEqual(middle.map(\.span), [.allDay], "a day it covers end to end reads as all day")
        XCTAssertEqual(last.map(\.span), [.until(date(c, 2026, 11, 12, 2))])
        XCTAssertTrue(after.isEmpty)
    }

    func testMultiDayTimedMiddleDaySortsWithAllDay() {
        let c = calendar("UTC")
        let day = date(c, 2026, 11, 11)
        let events = [
            event("meeting", date(c, 2026, 11, 11, 9), date(c, 2026, 11, 11, 10)),
            event("conference", date(c, 2026, 11, 10, 9), date(c, 2026, 11, 12, 17)),
            event("overnight", date(c, 2026, 11, 10, 23), date(c, 2026, 11, 11, 7)),
        ]
        XCTAssertEqual(CalendarDay.events(events, on: day, calendar: c).map(\.event.id),
                       ["conference", "overnight", "meeting"], "the whole-day one first; one ending at 7 sorts from midnight")
    }

    func testMultiDayAllDayEventShowsOnEveryDay() {
        let c = calendar("America/New_York")
        let holiday = event("holiday", date(c, 2026, 12, 24), date(c, 2026, 12, 27), allDay: true)
        for d in 24...26 {
            XCTAssertEqual(CalendarDay.events([holiday], on: date(c, 2026, 12, d), calendar: c).map(\.span), [.allDay], "Dec \(d)")
        }
        XCTAssertTrue(CalendarDay.events([holiday], on: date(c, 2026, 12, 27), calendar: c).isEmpty)
        XCTAssertTrue(CalendarDay.events([holiday], on: date(c, 2026, 12, 23), calendar: c).isEmpty)
    }

    /// EventKit ends an all-day event a second before the next midnight.
    func testEventKitStyleAllDayEndShowsOnOneDay() {
        let c = calendar("Europe/London")
        let off = event("off", date(c, 2026, 11, 10), date(c, 2026, 11, 10, 23, 59).addingTimeInterval(59), allDay: true)
        XCTAssertEqual(CalendarDay.events([off], on: date(c, 2026, 11, 10), calendar: c).count, 1)
        XCTAssertTrue(CalendarDay.events([off], on: date(c, 2026, 11, 11), calendar: c).isEmpty)
    }

    func testEventEndingAtMidnightStaysOnItsDay() {
        let c = calendar("UTC")
        let late = event("late", date(c, 2026, 11, 10, 22), date(c, 2026, 11, 11))
        XCTAssertEqual(CalendarDay.events([late], on: date(c, 2026, 11, 10), calendar: c).map(\.span),
                       [.timed(start: date(c, 2026, 11, 10, 22), end: date(c, 2026, 11, 11))])
        XCTAssertTrue(CalendarDay.events([late], on: date(c, 2026, 11, 11), calendar: c).isEmpty)
    }

    func testZeroLengthEventShowsAtItsTime() {
        let c = calendar("UTC")
        let reminder = event("call", date(c, 2026, 11, 10, 15), date(c, 2026, 11, 10, 15))
        XCTAssertEqual(CalendarDay.events([reminder], on: date(c, 2026, 11, 10), calendar: c).count, 1)
        let atMidnight = event("midnight", date(c, 2026, 11, 11), date(c, 2026, 11, 11))
        XCTAssertTrue(CalendarDay.events([atMidnight], on: date(c, 2026, 11, 10), calendar: c).isEmpty)
        XCTAssertEqual(CalendarDay.events([atMidnight], on: date(c, 2026, 11, 11), calendar: c).count, 1)
    }

    // MARK: Time zones and daylight saving

    func testDayFollowsTheDevicesTimeZone() {
        let newYork = calendar("America/New_York"), london = calendar("Europe/London")
        // 23:30 in New York is 04:30 the next morning in London.
        let late = event("late", date(newYork, 2026, 11, 10, 23, 30), date(newYork, 2026, 11, 11, 0, 15))
        XCTAssertEqual(CalendarDay.events([late], on: date(newYork, 2026, 11, 10), calendar: newYork).count, 1)
        XCTAssertTrue(CalendarDay.events([late], on: date(london, 2026, 11, 10), calendar: london).isEmpty)
        XCTAssertEqual(CalendarDay.events([late], on: date(london, 2026, 11, 11), calendar: london).map(\.span),
                       [.timed(start: late.start, end: late.end)])
    }

    func testSpringForwardDayIs23Hours() {
        let c = calendar("America/New_York")
        // 2026-03-08: clocks go from 2:00 to 3:00. A day of 23 hours; 24 h after midnight is already Mar 9, 1:00.
        let day = date(c, 2026, 3, 8)
        let late = event("late", date(c, 2026, 3, 8, 23, 30), date(c, 2026, 3, 8, 23, 50))
        let early = event("early", date(c, 2026, 3, 9, 0, 30), date(c, 2026, 3, 9, 0, 45))
        XCTAssertEqual(CalendarDay.events([late, early], on: day, calendar: c).map(\.event.id), ["late"])
        XCTAssertEqual(CalendarDay.events([late, early], on: date(c, 2026, 3, 9), calendar: c).map(\.event.id), ["early"])
        let allDay = event("all", day, date(c, 2026, 3, 9), allDay: true)
        XCTAssertEqual(CalendarDay.events([allDay], on: day, calendar: c).map(\.span), [.allDay])
        XCTAssertTrue(CalendarDay.events([allDay], on: date(c, 2026, 3, 9), calendar: c).isEmpty)
    }

    func testFallBackDayIs25Hours() {
        let c = calendar("America/New_York")
        // 2026-11-01: clocks go from 2:00 back to 1:00. 24 h after midnight is still Nov 1, 23:00.
        let day = date(c, 2026, 11, 1)
        let late = event("late", date(c, 2026, 11, 1, 23, 30), date(c, 2026, 11, 1, 23, 45))
        XCTAssertEqual(CalendarDay.events([late], on: day, calendar: c).map(\.event.id), ["late"])
        XCTAssertTrue(CalendarDay.events([late], on: date(c, 2026, 11, 2), calendar: c).isEmpty)
        let overnight = event("overnight", date(c, 2026, 10, 31, 20), date(c, 2026, 11, 2, 9))
        XCTAssertEqual(CalendarDay.events([overnight], on: day, calendar: c).map(\.span), [.allDay])
    }

    // MARK: The second line

    func testTimeText() {
        let c = calendar("UTC")
        let locale = Locale(identifier: "en_US")
        let day = date(c, 2026, 11, 10)
        func text(_ e: CalendarEvent) -> String {
            plain(CalendarDay.timeText(CalendarDay.events([e], on: day, calendar: c)[0], calendar: c, locale: locale))
        }
        XCTAssertEqual(text(event("a", date(c, 2026, 11, 10, 9, 30), date(c, 2026, 11, 10, 10, 15))), "9:30 – 10:15 AM")
        XCTAssertEqual(text(event("b", date(c, 2026, 11, 10, 11, 30), date(c, 2026, 11, 10, 13))), "11:30 AM – 1:00 PM")
        XCTAssertEqual(text(event("c", day, date(c, 2026, 11, 11), allDay: true)), "All day")
        XCTAssertEqual(text(event("d", date(c, 2026, 11, 10, 22), date(c, 2026, 11, 12))), "From 10:00 PM")
        XCTAssertEqual(text(event("e", date(c, 2026, 11, 9, 22), date(c, 2026, 11, 10, 2))), "Until 2:00 AM")
        XCTAssertEqual(text(event("f", date(c, 2026, 11, 10, 15), date(c, 2026, 11, 10, 15))), "3:00 PM")
    }

    func testTimeTextIn24HourLocale() {
        let c = calendar("Europe/Berlin")
        let e = event("a", date(c, 2026, 11, 10, 9, 30), date(c, 2026, 11, 10, 17))
        let shown = CalendarDay.events([e], on: date(c, 2026, 11, 10), calendar: c)[0]
        XCTAssertEqual(plain(CalendarDay.timeText(shown, calendar: c, locale: Locale(identifier: "de_DE"))), "09:30 – 17:00")
    }

    // MARK: Past events dim

    func testPastEventsOfToday() {
        let c = calendar("UTC")
        let day = date(c, 2026, 11, 10)
        let now = date(c, 2026, 11, 10, 12)
        let shown = CalendarDay.events([
            event("done", date(c, 2026, 11, 10, 9), date(c, 2026, 11, 10, 10)),
            event("endsNow", date(c, 2026, 11, 10, 11), now),
            event("running", date(c, 2026, 11, 10, 11, 30), date(c, 2026, 11, 10, 12, 30)),
            event("later", date(c, 2026, 11, 10, 15), date(c, 2026, 11, 10, 16)),
            event("allDay", day, date(c, 2026, 11, 11), allDay: true),
            event("overnight", date(c, 2026, 11, 9, 22), date(c, 2026, 11, 10, 2)),
        ], on: day, calendar: c)
        let past = Dictionary(uniqueKeysWithValues: shown.map { ($0.event.id, CalendarDay.isPast($0, now: now)) })
        XCTAssertEqual(past, ["done": true, "endsNow": true, "running": false, "later": false, "allDay": false,
                              "overnight": true])
    }

    // MARK: Which calendars

    func testHiddenCalendarsAreLeftOut() {
        let c = calendar("UTC")
        let day = date(c, 2026, 11, 10)
        let events = [
            event("work", date(c, 2026, 11, 10, 9), date(c, 2026, 11, 10, 10), calendarID: "work"),
            event("home", date(c, 2026, 11, 10, 11), date(c, 2026, 11, 10, 12), calendarID: "home"),
        ]
        XCTAssertEqual(CalendarDay.events(events, on: day, hiding: ["home"], calendar: c).map(\.event.id), ["work"])
        XCTAssertEqual(CalendarDay.events(events, on: day, hiding: [], calendar: c).count, 2, "all calendars by default")
    }

    func testCalendarSelectionSummary() {
        let ids = ["work", "home", "birthdays"]
        XCTAssertEqual(CalendarDay.selectionSummary(calendarIDs: ids, hidden: []), "All")
        XCTAssertEqual(CalendarDay.selectionSummary(calendarIDs: ids, hidden: ["home"]), "2 of 3")
        XCTAssertEqual(CalendarDay.selectionSummary(calendarIDs: ids, hidden: Set(ids)), "None")
        XCTAssertEqual(CalendarDay.selectionSummary(calendarIDs: ids, hidden: ["gone"]), "All",
                       "a calendar deleted since it was hidden doesn't count")
    }
}
