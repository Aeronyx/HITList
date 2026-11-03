import XCTest
@testable import HITListCore

/// The date rules on a real calendar (final review before 0.4.0): George's time zone (America/New_York)
/// with its 2027 daylight-saving days, month ends across a year, leap years, weeks that start on Monday or
/// Sunday, and "every weekday" across a weekend. The other suites run on UTC, which has none of these.
final class RealCalendarTests: XCTestCase {
    private let ny: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        ny.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// The wall clock in New York.
    private func assertWall(_ date: Date?, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let date else { return XCTFail("no date", file: file, line: line) }
        let c = ny.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [y, m, d, h, min], file: file, line: line)
    }

    private func parser(now: Date, weekStart: Int = 2) -> QuickAddParser {
        QuickAddParser(now: now, calendar: ny, weekStart: weekStart)
    }

    // MARK: Spring forward, Sunday 2027-03-14: 2:00 → 3:00

    func testTimesTypedAroundTheSkippedHour() {
        let p = parser(now: at(2027, 3, 13, 20))
        assertWall(p.parse("Feed cat tom 1:30am").dueDate, 2027, 3, 14, 1, 30)
        // 2:30 doesn't exist that night: the first moment after the gap, never a missing date.
        for text in ["Feed cat tom 2:30", "Feed cat tom 2", "Feed cat tom 2am", "Feed cat at 2:30"] {
            let r = p.parse(text)
            XCTAssertEqual(r.title, "Feed cat", text)
            XCTAssertTrue(r.hasDueTime, text)
            assertWall(r.dueDate, 2027, 3, 14, 3, 0)
        }
        assertWall(p.parse("Feed cat tom 3").dueDate, 2027, 3, 14, 3, 0)
        assertWall(p.parse("Feed cat tom").dueDate, 2027, 3, 14)
        XCTAssertNil(p.dateParser.parse("tom 24"))
    }

    func testRepeatsKeepTheirWallClockTimeAcrossTheChange() {
        let nine = at(2027, 3, 13, 9)
        assertWall(RecurrenceRule.daily.nextOccurrence(after: nine, calendar: ny), 2027, 3, 14, 9)
        assertWall(RecurrenceRule.weekly.nextOccurrence(after: at(2027, 3, 10, 9), calendar: ny), 2027, 3, 17, 9)
        assertWall(RecurrenceRule(frequency: .monthly, anchorDay: 14).nextOccurrence(after: at(2027, 2, 14, 9), calendar: ny),
                   2027, 3, 14, 9)
        // Overdue since Friday, completed Sunday afternoon: today at 9, not a day in the past.
        assertWall(RecurrenceRule.daily.nextDueDate(from: at(2027, 3, 12, 9), now: at(2027, 3, 14, 15), calendar: ny),
                   2027, 3, 14, 9)
    }

    func testRelativePhrasesOnTheSpringForwardNight() {
        // "in 1 day" late on Saturday: Sunday, all day.
        let saturday = parser(now: at(2027, 3, 13, 23))
        let r = saturday.parse("Feed cat in 1 day")
        assertWall(r.dueDate, 2027, 3, 14)
        XCTAssertFalse(r.hasDueTime)
        assertWall(saturday.parse("Feed cat in one day 2:30").dueDate, 2027, 3, 14, 3, 0)
        // "in 2 hours" at 1:30: two real hours later, which the clock calls 4:30.
        let night = parser(now: at(2027, 3, 14, 1, 30)).parse("Feed cat in 2 hours")
        assertWall(night.dueDate, 2027, 3, 14, 4, 30)
        XCTAssertEqual(night.dueDate?.timeIntervalSince(at(2027, 3, 14, 1, 30)), 2 * 3600)
    }

    /// Known, not fixed in 0.4.0 (final review): a repeat timed inside the skipped hour lands after the gap
    /// that night (right), then stays an hour late, because the rule keeps no time of its own and steps from
    /// the stored due date. Needs the wall-clock time in the rule string, like the anchor day.
    func testARepeatInsideTheSkippedHourComesBackToItsTime() {
        var due = at(2027, 3, 13, 2, 30)
        due = RecurrenceRule.daily.nextOccurrence(after: due, calendar: ny)
        XCTAssertGreaterThanOrEqual(ny.component(.hour, from: due), 3, "the night of the change: after the gap")
        due = RecurrenceRule.daily.nextOccurrence(after: due, calendar: ny)
        XCTExpectFailure("a repeat at 2:30 stays at 3:30 after the spring change")
        assertWall(due, 2027, 3, 15, 2, 30)
    }

    // MARK: Fall back, Sunday 2027-11-07: 1:00–2:00 happens twice

    func testTimesTypedInTheRepeatedHour() {
        let p = parser(now: at(2027, 11, 6, 20))
        let r = p.parse("Feed cat tom 1:30")
        assertWall(r.dueDate, 2027, 11, 7, 1, 30)
        XCTAssertEqual(ny.timeZone.secondsFromGMT(for: r.dueDate!), -4 * 3600, "the first 1:30 (still EDT)")
        assertWall(p.parse("Feed cat tom 9").dueDate, 2027, 11, 7, 9)
    }

    func testRepeatsKeepTheirTimeAcrossTheFallBack() {
        var due = at(2027, 11, 6, 1, 30)
        for day in 7...9 {
            due = RecurrenceRule.daily.nextOccurrence(after: due, calendar: ny)
            assertWall(due, 2027, 11, day, 1, 30)
        }
        assertWall(RecurrenceRule.weekdays.nextOccurrence(after: at(2027, 11, 5, 9), calendar: ny), 2027, 11, 8, 9)
    }

    // MARK: Month ends across a year, leap years

    func testEveryMonthFromNewYearsEve() {
        let r = parser(now: at(2026, 12, 31, 10)).parse("Pay rent every month")
        assertWall(r.dueDate, 2026, 12, 31)
        XCTAssertEqual(r.recurrence?.anchorDay, 31)
        var due = r.dueDate!
        for (y, m, d) in [(2027, 1, 31), (2027, 2, 28), (2027, 3, 31), (2027, 4, 30)] {
            due = r.recurrence!.nextOccurrence(after: due, calendar: ny)
            assertWall(due, y, m, d)
        }
        assertWall(RecurrenceRule.yearly.anchored(to: at(2026, 12, 31), calendar: ny)
                    .nextOccurrence(after: at(2026, 12, 31, 18), calendar: ny), 2027, 12, 31, 18)
    }

    func testEveryMonthTypedOnThe31stAfterItsTime() {
        let r = parser(now: at(2027, 1, 31, 14)).parse("Invoice every month 9am")
        assertWall(r.dueDate, 2027, 2, 28, 9)
        XCTAssertEqual(r.recurrence?.anchorDay, 31, "still the 31st after February")
        assertWall(r.recurrence!.nextOccurrence(after: r.dueDate!, calendar: ny), 2027, 3, 31, 9)
    }

    func testLeapDays() {
        // Feb 29 typed in a common year is next year's leap day.
        assertWall(parser(now: at(2027, 1, 10, 12)).parse("Party feb 29").dueDate, 2028, 2, 29)
        // A 29th, monthly, through a common and a leap February.
        var due = at(2027, 1, 29)
        let rule = RecurrenceRule(frequency: .monthly, anchorDay: 29)
        for (y, m, d) in [(2027, 2, 28), (2027, 3, 29)] {
            due = rule.nextOccurrence(after: due, calendar: ny)
            assertWall(due, y, m, d)
        }
        assertWall(rule.nextOccurrence(after: at(2028, 1, 29), calendar: ny), 2028, 2, 29)
        // Yearly from a leap day: Feb 28 three times, then Feb 29.
        let yearly = parser(now: at(2028, 2, 29, 8)).parse("Birthday every year")
        XCTAssertEqual(yearly.recurrence?.anchorDay, 29)
        due = yearly.dueDate!
        for (y, d) in [(2029, 28), (2030, 28), (2031, 28), (2032, 29)] {
            due = yearly.recurrence!.nextOccurrence(after: due, calendar: ny)
            assertWall(due, y, 2, d)
        }
    }

    // MARK: Weeks that start on Monday or Sunday (Settings → Week starts on)

    func testWeekWordsFollowTheWeekStart() {
        let sunday = at(2026, 11, 1, 12), monday = at(2026, 11, 2, 12)
        // Monday weeks: on Sunday, next week starts tomorrow.
        var p = parser(now: sunday, weekStart: 2).dateParser
        assertWall(p.parse("next week")?.date, 2026, 11, 2)
        assertWall(p.parse("next mon")?.date, 2026, 11, 2)
        assertWall(p.parse("end of week")?.date, 2026, 11, 1)
        assertWall(p.parse("this mon")?.date, 2026, 10, 26)
        // Sunday weeks: today starts the week.
        p = parser(now: sunday, weekStart: 1).dateParser
        assertWall(p.parse("next week")?.date, 2026, 11, 8)
        assertWall(p.parse("next mon")?.date, 2026, 11, 9)
        assertWall(p.parse("end of week")?.date, 2026, 11, 7)
        assertWall(p.parse("this mon")?.date, 2026, 11, 2)
        // On Monday the two agree on "next mon", not on "next week".
        assertWall(parser(now: monday, weekStart: 2).dateParser.parse("next week")?.date, 2026, 11, 9)
        assertWall(parser(now: monday, weekStart: 1).dateParser.parse("next week")?.date, 2026, 11, 8)
        assertWall(parser(now: monday, weekStart: 2).dateParser.parse("next mon")?.date, 2026, 11, 9)
        assertWall(parser(now: monday, weekStart: 1).dateParser.parse("next mon")?.date, 2026, 11, 9)
        // A bare weekday doesn't depend on the week start: the next one after today.
        for start in [1, 2] { assertWall(parser(now: sunday, weekStart: start).dateParser.parse("sun")?.date, 2026, 11, 8) }
    }

    func testRepeatsDoNotDependOnTheDevicesFirstWeekday() {
        var monday = ny
        monday.firstWeekday = 2
        for cal in [ny, monday] {
            let every2 = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2])
            assertWall(every2.nextOccurrence(after: at(2026, 10, 19, 9), calendar: cal), 2026, 11, 2, 9)
            assertWall(RecurrenceRule.weekdays.nextOccurrence(after: at(2026, 11, 6, 9), calendar: cal), 2026, 11, 9, 9)
        }
    }

    // MARK: "every weekday" across a weekend

    func testEveryWeekdayAcrossAWeekend() {
        let friday = at(2026, 11, 6, 9)
        // Done on Friday, on Saturday, or late on Monday: Monday.
        for now in [at(2026, 11, 6, 10), at(2026, 11, 7, 10), at(2026, 11, 9, 8)] {
            assertWall(RecurrenceRule.weekdays.nextDueDate(from: friday, now: now, calendar: ny), 2026, 11, 9, 9)
        }
        // Typed on Friday after 9, or on Saturday: it starts Monday.
        assertWall(parser(now: at(2026, 11, 6, 14)).parse("Standup every weekday 9am").dueDate, 2026, 11, 9, 9)
        assertWall(parser(now: at(2026, 11, 7, 11)).parse("Standup every weekday").dueDate, 2026, 11, 9)
        assertWall(parser(now: at(2026, 11, 7, 11)).parse("Standup every weekday 9am").dueDate, 2026, 11, 9, 9)
        // Across the spring change: Friday 9:00 EST → Monday 9:00 EDT.
        assertWall(RecurrenceRule.weekdays.nextOccurrence(after: at(2027, 3, 12, 9), calendar: ny), 2027, 3, 15, 9)
    }
}
