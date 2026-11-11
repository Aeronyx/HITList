import Foundation
import XCTest
@testable import HITListCore

/// Brief 82, item 1: a store written in one time zone and read in another. Each test writes a value the way the app's
/// writers do in the writer's zone (the quick-add parser, the pickers' start of day, a repeat's roll-over), keeps it
/// the way the store keeps it (`stored`), and reads it back with core's own rules in the reader's zone.
///
/// The zones: Honolulu (UTC−10), Los Angeles, Chicago, UTC, London, Kolkata (+5:30), Tokyo, Auckland in summer (+13)
/// and Chatham in summer (+13:45), the widest the stored form serves. November dates, so the southern zones are on
/// summer time. Every clock here is injected: nothing reads the wall clock or this Mac's zone.
final class TimeZoneAuditTests: XCTestCase {
    static let zoneIDs = ["Pacific/Honolulu", "America/Los_Angeles", "America/Chicago", "UTC", "Europe/London",
                          "Asia/Kolkata", "Asia/Tokyo", "Pacific/Auckland", "Pacific/Chatham"]

    static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        c.firstWeekday = 1
        return c
    }

    static var zones: [Calendar] { zoneIDs.map(calendar) }

    /// `hour:minute` on a day, wall clock in `calendar`.
    static func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// The calendar day `date` falls on in `calendar`'s zone.
    static func day(of date: Date, in calendar: Calendar) -> [Int] {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return [parts.year!, parts.month!, parts.day!]
    }

    /// What the store keeps for a date with no time written in `written`'s zone. Before brief 82: the value as the
    /// writer made it, a midnight in the writer's zone.
    func stored(_ value: Date, written: Calendar) -> Date { value }

    /// "thu" typed on Wednesday 2026-11-11 at noon in `calendar`: the parser's due date for Thursday the 12th.
    func typedThursday(in calendar: Calendar) -> Date {
        let now = Self.local(2026, 11, 11, 12, in: calendar)
        let parsed = QuickAddParser(now: now, calendar: calendar).parse("Call Sam thu")
        XCTAssertFalse(parsed.hasDueTime)
        return parsed.dueDate!
    }

    // MARK: - A day is a day (rule 1): these fail before brief 82

    /// "Due Thursday" typed anywhere is Thursday everywhere: the day it falls on, Today's section on Thursday, Upcoming's
    /// day and the Date sort's section.
    func testADayWithNoTimeIsTheSameCalendarDayInEveryZone() {
        XCTExpectFailure("Before brief 82 a day is stored as the writer's local midnight: a day early to the west")
        for written in Self.zones {
            let value = stored(typedThursday(in: written), written: written)
            for read in Self.zones {
                let pair = "\(written.timeZone.identifier) → \(read.timeZone.identifier)"
                XCTAssertEqual(Self.day(of: value, in: read), [2026, 11, 12], pair)
                let noonThursday = Self.local(2026, 11, 12, 12, in: read)
                XCTAssertEqual(TaskOrdering.todaySection(for: value, now: noonThursday, calendar: read), .today, pair)
                XCTAssertEqual(DueSection(due: value, now: noonThursday, calendar: read), .today, pair)
                let task = PlainTask(title: "Call Sam", dueDate: value)
                let days = UpcomingDays.days([task], now: Self.local(2026, 11, 11, 12, in: read), dayCount: 7, calendar: read)
                XCTAssertEqual(days.map { Self.day(of: $0.date, in: read) }, [[2026, 11, 12]], pair)
            }
        }
    }

    /// A deadline is a day too (the card's and the editor's pickers store the picked day's start).
    func testADeadlineIsTheSameCalendarDayInEveryZone() {
        XCTExpectFailure("Before brief 82 a deadline is stored as the writer's local midnight")
        for written in Self.zones {
            let picked = Self.local(2026, 11, 13, 12, in: written)
            let deadline = stored(written.startOfDay(for: picked), written: written)
            for read in Self.zones {
                XCTAssertEqual(Self.day(of: deadline, in: read), [2026, 11, 13],
                               "\(written.timeZone.identifier) → \(read.timeZone.identifier)")
            }
        }
    }

    /// A daily date-only repeat completed abroad rolls on to the next calendar day, never to the day it already was.
    func testADateOnlyRepeatRollsOnByCalendarDaysAfterAFlight() {
        XCTExpectFailure("Before brief 82 the roll-over starts from a local midnight read a day early to the west")
        for written in Self.zones {
            let due = stored(typedThursday(in: written), written: written)
            for read in Self.zones {
                // Done on Thursday afternoon where the person is now.
                let next = RecurrenceRule.daily.nextDueDate(from: due, now: Self.local(2026, 11, 12, 15, in: read),
                                                            calendar: read)
                XCTAssertEqual(Self.day(of: stored(next, written: read), in: read), [2026, 11, 13],
                               "\(written.timeZone.identifier) → \(read.timeZone.identifier)")
            }
        }
    }

    /// The Flipboard: a loose switch flipped today is still flipped (green) after the zone changes.
    func testALooseSwitchFlippedTodayIsStillFlippedAfterTheZoneChanges() {
        XCTExpectFailure("Before brief 82 a flip stores tomorrow's local midnight, which is today to the west")
        for written in Self.zones {
            // Flipped on Wednesday evening: due again Thursday (the start of the next day, as `Flipboard` writes it).
            let flippedAt = Self.local(2026, 11, 11, 19, in: written)
            let due = stored(written.date(byAdding: .day, value: 1, to: written.startOfDay(for: flippedAt))!, written: written)
            for read in Self.zones {
                // Later the same Wednesday evening, wherever the person is now (an hour after the flip).
                let later = flippedAt.addingTimeInterval(3600)
                guard Self.day(of: later, in: read) == [2026, 11, 11] else { continue }
                XCTAssertEqual(FlipboardSwitch.side(due: due, now: later, calendar: read), .green,
                               "\(written.timeZone.identifier) → \(read.timeZone.identifier)")
            }
        }
    }

    /// A Switchboard resets at its hour where the person is, once: a switch done on Wednesday evening stays done until
    /// Thursday's 04:00 there, and is due again from it.
    func testASwitchboardResetsAtItsHourWhereThePersonIs() {
        XCTExpectFailure("Before brief 82 the board day after a flip is a local midnight, which is the same day to the west")
        let board = SwitchboardSchedule(cadence: .daily, resetMinutes: 4 * 60)
        for written in Self.zones {
            let flippedAt = Self.local(2026, 11, 11, 19, in: written)
            let due = stored(board.dueAfterFlip(due: nil, hasTime: false, now: flippedAt, calendar: written), written: written)
            for read in Self.zones {
                let pair = "\(written.timeZone.identifier) → \(read.timeZone.identifier)"
                XCTAssertEqual(board.side(due: due, hasTime: false, now: Self.local(2026, 11, 12, 3, 59, in: read),
                                          calendar: read), .green, pair)
                XCTAssertEqual(board.side(due: due, hasTime: false, now: Self.local(2026, 11, 12, 4, 0, in: read),
                                          calendar: read), .red, pair)
            }
        }
    }

    // MARK: - Pins that hold before and after brief 82

    /// A time is a moment (rule 2): 09:00 written in Chicago is 07:00 in Los Angeles, as Calendar and Reminders do.
    func testATimedTaskKeepsItsMoment() {
        let chicago = Self.calendar("America/Chicago"), la = Self.calendar("America/Los_Angeles")
        let now = Self.local(2026, 11, 11, 12, in: chicago)
        let parsed = QuickAddParser(now: now, calendar: chicago).parse("Call Sam thu 9am")
        XCTAssertTrue(parsed.hasDueTime)
        let due = parsed.dueDate!
        XCTAssertEqual(due, Self.local(2026, 11, 12, 9, in: chicago))
        XCTAssertEqual(la.dateComponents([.day, .hour, .minute], from: due), DateComponents(day: 12, hour: 7, minute: 0))
        let tokyo = Self.calendar("Asia/Tokyo")
        XCTAssertEqual(tokyo.dateComponents([.day, .hour], from: due), DateComponents(day: 13, hour: 0))
    }

    /// A timed repeat stores a time of day (rule 2): its next occurrence is at that hour where the person is.
    func testATimedRepeatComesBackAtItsHourWhereThePersonIs() {
        let chicago = Self.calendar("America/Chicago")
        let due = Self.local(2026, 11, 12, 9, in: chicago)
        let rule = RecurrenceRule.daily.timed(to: due, hasTime: true, calendar: chicago)
        for read in Self.zones {
            let next = rule.nextDueDate(from: due, now: Self.local(2026, 11, 13, 12, in: read), calendar: read)
            XCTAssertEqual(read.dateComponents([.hour, .minute], from: next), DateComponents(hour: 9, minute: 0),
                           read.timeZone.identifier)
            // The roll-over lands on today at the earliest (`nextDueDate`), never on a day already gone.
            XCTAssertGreaterThanOrEqual(read.startOfDay(for: next), Self.local(2026, 11, 13, in: read), read.timeZone.identifier)
        }
    }

    /// Overdue (rule "Overdue"): a date-only task due Thursday is today's all of Thursday in every zone, to 23:59, and
    /// overdue from Friday's first minute; never from some hour on Thursday.
    func testADateOnlyTaskIsOverdueFromTheDayAfterNeverDuringItsDay() throws {
        let overdue = try FilterQuery("overdue")
        for zone in Self.zones {
            let due = stored(typedThursday(in: zone), written: zone)
            let task = PlainTask(title: "Call Sam", dueDate: due)
            for (h, m) in [(0, 0), (9, 59), (10, 1), (19, 0), (23, 59)] {
                let now = Self.local(2026, 11, 12, h, m, in: zone)
                XCTAssertEqual(TaskOrdering.todaySection(for: due, now: now, calendar: zone), .today, "\(zone.timeZone.identifier) \(h):\(m)")
                XCTAssertFalse(overdue.matches(task, now: now, calendar: zone), "\(zone.timeZone.identifier) \(h):\(m)")
                XCTAssertFalse(FlipboardSwitch.isOverdue(due: due, now: now, calendar: zone))
            }
            let friday = Self.local(2026, 11, 13, 0, 1, in: zone)
            XCTAssertEqual(TaskOrdering.todaySection(for: due, now: friday, calendar: zone), .overdue, zone.timeZone.identifier)
            XCTAssertTrue(overdue.matches(task, now: friday, calendar: zone), zone.timeZone.identifier)
        }
    }

    /// Ordering: within a day a date-only task comes before the day's timed ones, at every hour, in every zone, in
    /// every list order (priority-then-due, the filters' due-then-priority, Today, Upcoming, the Date sort).
    func testADaysDateOnlyTasksSortBeforeItsTimedOnesInEveryZone() {
        for zone in Self.zones {
            let id = zone.timeZone.identifier
            let created = Self.local(2026, 11, 1, in: zone)
            let early = PlainTask(title: "early", dueDate: Self.local(2026, 11, 12, 0, 30, in: zone), hasDueTime: true,
                                  createdDate: created)
            let allDay = PlainTask(title: "all day", dueDate: stored(typedThursday(in: zone), written: zone),
                                   createdDate: created.addingTimeInterval(60))
            let late = PlainTask(title: "late", dueDate: Self.local(2026, 11, 12, 21, 0, in: zone), hasDueTime: true,
                                 createdDate: created.addingTimeInterval(120))
            let tasks = [late, early, allDay]
            let now = Self.local(2026, 11, 12, 0, 5, in: zone)
            let titles: ([PlainTask]) -> [String] = { $0.map(\.filterTitle) }
            XCTAssertEqual(titles(TaskOrdering.sorted(tasks, now: now, calendar: zone)), ["all day", "early", "late"], id)
            XCTAssertEqual(titles(tasks.sorted(by: TaskOrdering.priorityThenDue)), ["all day", "early", "late"], id)
            XCTAssertEqual(titles(FilterQuery.defaultSort(tasks, now: now, calendar: zone)), ["all day", "early", "late"], id)
            XCTAssertEqual(titles(TaskOrdering.today(tasks, now: now, calendar: zone).today), ["all day", "early", "late"], id)
            let upcoming = UpcomingDays.days(tasks, now: now, dayCount: 3, calendar: zone)
            XCTAssertEqual(upcoming.map { titles($0.tasks) }, [["all day", "early", "late"]], id)
            let sections = GroupedOrdering.sections(tasks, by: .date, groupOrder: [String](), now: now, calendar: zone,
                                                    groupOf: { _ in nil })
            XCTAssertEqual(sections.map { titles($0.tasks) }, [["all day", "early", "late"]], id)
        }
    }

    /// Two date-only tasks on one day keep the order they were added in, whatever form each one's day is stored in (a
    /// value from an older build beside one written now).
    func testTwoDateOnlyTasksOnOneDayKeepTheirAddedOrder() {
        for zone in Self.zones {
            let created = Self.local(2026, 11, 1, in: zone)
            let older = PlainTask(title: "zebra", dueDate: zone.startOfDay(for: Self.local(2026, 11, 12, 12, in: zone)),
                                  createdDate: created)
            let newer = PlainTask(title: "apple", dueDate: stored(typedThursday(in: zone), written: zone),
                                  createdDate: created.addingTimeInterval(60))
            let now = Self.local(2026, 11, 12, 8, in: zone)
            XCTAssertEqual(TaskOrdering.sorted([newer, older], now: now, calendar: zone).map(\.filterTitle), ["zebra", "apple"],
                           zone.timeZone.identifier)
            XCTAssertEqual(FilterQuery.defaultSort([newer, older], now: now, calendar: zone).map(\.filterTitle), ["zebra", "apple"],
                           zone.timeZone.identifier)
        }
    }
}
