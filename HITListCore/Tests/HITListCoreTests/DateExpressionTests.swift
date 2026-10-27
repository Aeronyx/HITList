import XCTest
@testable import HITListCore

final class DateExpressionTests: XCTestCase {
    let p = Fixed.dateParser

    func testRelativeDays() {
        assertDate(p.parse("today")?.date, 2026, 10, 21)
        assertDate(p.parse("tomorrow")?.date, 2026, 10, 22)
        assertDate(p.parse("tom")?.date, 2026, 10, 22)
        assertDate(p.parse("yesterday")?.date, 2026, 10, 20)
        assertDate(p.parse("in 3 days")?.date, 2026, 10, 24)
        assertDate(p.parse("in a week")?.date, 2026, 10, 28)
        assertDate(p.parse("2 weeks")?.date, 2026, 11, 4)
        assertDate(p.parse("in 1 month")?.date, 2026, 11, 21)
    }

    func testWeekdays() {
        // Today is Wednesday. Bare weekday = next occurrence strictly after today.
        assertDate(p.parse("fri")?.date, 2026, 10, 23)
        assertDate(p.parse("friday")?.date, 2026, 10, 23)
        assertDate(p.parse("mon")?.date, 2026, 10, 26)
        assertDate(p.parse("wed")?.date, 2026, 10, 28)
        // "next <weekday>" = that weekday in next week (week starts Monday).
        assertDate(p.parse("next fri")?.date, 2026, 10, 30)
        assertDate(p.parse("next mon")?.date, 2026, 10, 26)
        // "this <weekday>" = this week's occurrence even if it has passed.
        assertDate(p.parse("this mon")?.date, 2026, 10, 19)
        assertDate(p.parse("this fri")?.date, 2026, 10, 23)
    }

    func testWeeksAndMonths() {
        assertDate(p.parse("next week")?.date, 2026, 10, 26)
        assertDate(p.parse("next month")?.date, 2026, 11, 1)
        assertDate(p.parse("next year")?.date, 2027, 1, 1)
        assertDate(p.parse("eom")?.date, 2026, 10, 31)
        assertDate(p.parse("end of month")?.date, 2026, 10, 31)
        assertDate(p.parse("end of week")?.date, 2026, 10, 25)
        assertDate(p.parse("weekend")?.date, 2026, 10, 24)
    }

    func testAbsoluteDates() {
        assertDate(p.parse("jan 5")?.date, 2027, 1, 5)
        assertDate(p.parse("5 jan")?.date, 2027, 1, 5)
        assertDate(p.parse("january 5th")?.date, 2027, 1, 5)
        assertDate(p.parse("dec 25")?.date, 2026, 12, 25)
        assertDate(p.parse("oct 1")?.date, 2027, 10, 1)   // already passed this year → next year
        assertDate(p.parse("oct 21")?.date, 2026, 10, 21) // today counts as upcoming
        assertDate(p.parse("jan 5 2028")?.date, 2028, 1, 5)
        assertDate(p.parse("2026-11-03")?.date, 2026, 11, 3)
        assertDate(p.parse("10/31")?.date, 2026, 10, 31)
        assertDate(p.parse("1/5")?.date, 2027, 1, 5)
        assertDate(p.parse("1/5/2027")?.date, 2027, 1, 5)
        assertDate(p.parse("1/5/27")?.date, 2027, 1, 5)
        XCTAssertNil(p.parse("feb 30"))
        XCTAssertNil(p.parse("2026-13-01"))
    }

    func testTimes() {
        let r = p.parse("tomorrow 5pm")
        assertDate(r?.date, 2026, 10, 22, 17, 0)
        XCTAssertEqual(r?.hasTime, true)
        assertDate(p.parse("fri at 9")?.date, 2026, 10, 23, 9, 0)
        assertDate(p.parse("fri at 5")?.date, 2026, 10, 23, 17, 0)
        assertDate(p.parse("jan 5 at 5:30pm")?.date, 2027, 1, 5, 17, 30)
        assertDate(p.parse("17:45 tomorrow")?.date, 2026, 10, 22, 17, 45)
        assertDate(p.parse("tomorrow noon")?.date, 2026, 10, 22, 12, 0)
        assertDate(p.parse("tomorrow 12am")?.date, 2026, 10, 22, 0, 0)
        assertDate(p.parse("tomorrow 12pm")?.date, 2026, 10, 22, 12, 0)
        assertDate(p.parse("tomorrow 5 pm")?.date, 2026, 10, 22, 17, 0)
        // Time only: later today if still ahead, otherwise tomorrow (now is 14:30).
        assertDate(p.parse("3pm")?.date, 2026, 10, 21, 15, 0)
        assertDate(p.parse("9am")?.date, 2026, 10, 22, 9, 0)
    }

    func testRejectsNonsense() {
        XCTAssertNil(p.parse("banana"))
        XCTAssertNil(p.parse("tomorrow banana"))
        XCTAssertNil(p.parse(""))
        XCTAssertNil(p.parse("5"))          // bare number is not a time
        XCTAssertNil(p.parse("may"))        // month without a day
    }

    func testSpans() {
        XCTAssertEqual(p.spanThisWeek(), DateSpan(start: Fixed.date(2026, 10, 19), end: Fixed.date(2026, 10, 26)))
        XCTAssertEqual(p.spanNextWeek(), DateSpan(start: Fixed.date(2026, 10, 26), end: Fixed.date(2026, 11, 2)))
        XCTAssertEqual(p.spanWeekend(), DateSpan(start: Fixed.date(2026, 10, 24), end: Fixed.date(2026, 10, 26)))
        XCTAssertEqual(p.spanNextDays(7), DateSpan(start: Fixed.date(2026, 10, 21), end: Fixed.date(2026, 10, 29)))
        XCTAssertEqual(p.spanThisMonth(), DateSpan(start: Fixed.date(2026, 10, 1), end: Fixed.date(2026, 11, 1)))
        XCTAssertEqual(p.spanNextMonth(), DateSpan(start: Fixed.date(2026, 11, 1), end: Fixed.date(2026, 12, 1)))
        // Weekend when today is Sunday → this weekend (started yesterday).
        let sunday = DateExpressionParser(calendar: Fixed.calendar, now: Fixed.date(2026, 10, 25, 10))
        XCTAssertEqual(sunday.spanWeekend(), DateSpan(start: Fixed.date(2026, 10, 24), end: Fixed.date(2026, 10, 26)))
    }
}
