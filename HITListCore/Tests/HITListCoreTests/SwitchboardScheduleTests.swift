import XCTest
@testable import HITListCore

/// Brief 72: a Switchboard's day starts at its reset time. The arithmetic around midnight, the reset, daylight-saving
/// changes and a weekly reset day.
final class SwitchboardScheduleTests: XCTestCase {
    private let utc = Fixed.calendar
    /// A daily board resetting at 04:00.
    private let daily = SwitchboardSchedule(cadence: .daily, resetMinutes: 4 * 60)
    /// A weekly board resetting on Mondays at 04:00.
    private let weekly = SwitchboardSchedule(cadence: .weekly, resetMinutes: 4 * 60, resetWeekday: 2)

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date { Fixed.date(y, m, day, h, min) }

    /// New York, for the daylight-saving changes (2026: Mar 8 springs forward at 02:00, Nov 1 falls back at 02:00).
    private var newYork: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1
        return c
    }

    private func ny(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
    }

    // MARK: - Defaults and stored values

    func testANewBoardResetsAtFour() {
        XCTAssertEqual(SwitchboardSchedule.defaultResetMinutes, 240)
        XCTAssertEqual(SwitchboardSchedule(cadence: .daily).resetMinutes, 240)
    }

    func testStoredValuesAreClamped() {
        XCTAssertEqual(SwitchboardSchedule(cadence: .daily, resetMinutes: -5).resetMinutes, 0)
        XCTAssertEqual(SwitchboardSchedule(cadence: .daily, resetMinutes: 5000).resetMinutes, 1439)
        XCTAssertEqual(SwitchboardSchedule(cadence: .weekly, resetWeekday: 9).resetWeekday, 2)
    }

    func testTheStoredWeekdayZeroIsTheWeekStart() {
        XCTAssertEqual(SwitchboardSchedule.weekday(stored: 0, weekStart: 2), 2, "0 = the week start from Settings")
        XCTAssertEqual(SwitchboardSchedule.weekday(stored: 0, weekStart: 1), 1)
        XCTAssertEqual(SwitchboardSchedule.weekday(stored: 7, weekStart: 2), 7, "a chosen day wins")
    }

    func testAnUnknownCadenceReadsAsDaily() {
        XCTAssertEqual(SwitchboardSchedule.cadence(stored: "weekly"), .weekly)
        XCTAssertEqual(SwitchboardSchedule.cadence(stored: "fortnightly"), .daily, "a later build's cadence")
    }

    // MARK: - The board day

    func testHalfPastOneOnTuesdayIsStillMondaysBoardDay() {
        // 2026-10-19 is a Monday.
        XCTAssertEqual(daily.periodDay(containing: d(2026, 10, 20, 1, 30), calendar: utc), d(2026, 10, 19))
        XCTAssertEqual(daily.periodDay(containing: d(2026, 10, 20, 3, 59), calendar: utc), d(2026, 10, 19))
        XCTAssertEqual(daily.periodDay(containing: d(2026, 10, 20, 4, 0), calendar: utc), d(2026, 10, 20), "the reset itself")
        XCTAssertEqual(daily.periodDay(containing: d(2026, 10, 20, 23, 59), calendar: utc), d(2026, 10, 20))
    }

    func testAMidnightResetIsTheCalendarDay() {
        let midnight = SwitchboardSchedule(cadence: .daily, resetMinutes: 0)
        XCTAssertEqual(midnight.periodDay(containing: d(2026, 10, 20, 0, 0), calendar: utc), d(2026, 10, 20))
        XCTAssertEqual(midnight.periodDay(containing: d(2026, 10, 19, 23, 59), calendar: utc), d(2026, 10, 19))
    }

    func testThePeriodRunsFromResetToReset() {
        let period = daily.period(containing: d(2026, 10, 20, 1, 30), calendar: utc)
        XCTAssertEqual(period.start, d(2026, 10, 19, 4))
        XCTAssertEqual(period.end, d(2026, 10, 20, 4))
    }

    func testAWeeklyBoardsWeekRunsFromItsResetDay() {
        // Monday 04:00 to the next Monday 04:00.
        XCTAssertEqual(weekly.periodDay(containing: d(2026, 10, 21, 14, 30), calendar: utc), d(2026, 10, 19), "Wednesday")
        XCTAssertEqual(weekly.periodDay(containing: d(2026, 10, 25, 23), calendar: utc), d(2026, 10, 19), "Sunday night")
        XCTAssertEqual(weekly.periodDay(containing: d(2026, 10, 26, 3, 59), calendar: utc), d(2026, 10, 19), "Monday before four")
        XCTAssertEqual(weekly.periodDay(containing: d(2026, 10, 26, 4), calendar: utc), d(2026, 10, 26), "Monday at four")
        let period = weekly.period(containing: d(2026, 10, 21), calendar: utc)
        XCTAssertEqual(period.start, d(2026, 10, 19, 4))
        XCTAssertEqual(period.end, d(2026, 10, 26, 4))
    }

    func testAWeeklyBoardOnAnotherWeekday() {
        // Saturdays at 09:00: 2026-10-24 is a Saturday.
        let saturdays = SwitchboardSchedule(cadence: .weekly, resetMinutes: 9 * 60, resetWeekday: 7)
        XCTAssertEqual(saturdays.periodDay(containing: d(2026, 10, 21), calendar: utc), d(2026, 10, 17))
        XCTAssertEqual(saturdays.periodDay(containing: d(2026, 10, 24, 8, 59), calendar: utc), d(2026, 10, 17))
        XCTAssertEqual(saturdays.periodDay(containing: d(2026, 10, 24, 9), calendar: utc), d(2026, 10, 24))
        XCTAssertEqual(saturdays.nextPeriodDay(after: d(2026, 10, 24), calendar: utc), d(2026, 10, 31))
    }

    // MARK: - Sides

    func testFlippedMondayEveningStaysGreenUntilFour() {
        // Flipped Monday 21:00: due on Tuesday's board day.
        let due = daily.dueAfterFlip(due: d(2026, 10, 19), hasTime: false, now: d(2026, 10, 19, 21), calendar: utc)
        XCTAssertEqual(due, d(2026, 10, 20))
        XCTAssertEqual(daily.side(due: due, hasTime: false, now: d(2026, 10, 19, 23), calendar: utc), .green)
        XCTAssertEqual(daily.side(due: due, hasTime: false, now: d(2026, 10, 20, 1, 30), calendar: utc), .green, "past midnight")
        XCTAssertEqual(daily.side(due: due, hasTime: false, now: d(2026, 10, 20, 4), calendar: utc), .red, "the reset")
    }

    func testFlippedAfterMidnightCountsForTheBoardDayThatIsStillGoing() {
        // 01:30 Tuesday is Monday's board day: the flip is Monday's, and the switch is due again on Tuesday's.
        let due = daily.dueAfterFlip(due: d(2026, 10, 19), hasTime: false, now: d(2026, 10, 20, 1, 30), calendar: utc)
        XCTAssertEqual(due, d(2026, 10, 20))
        XCTAssertEqual(daily.side(due: due, hasTime: false, now: d(2026, 10, 20, 4), calendar: utc), .red)
    }

    func testEverySwitchOfADailyBoardTurnsRedTogether() {
        let flippedAt = [d(2026, 10, 19, 6), d(2026, 10, 19, 18), d(2026, 10, 20, 2)]
        let dues = flippedAt.map { daily.dueAfterFlip(due: nil, hasTime: false, now: $0, calendar: utc) }
        XCTAssertEqual(Set(dues), [d(2026, 10, 20)])
        XCTAssertTrue(dues.allSatisfy { daily.side(due: $0, hasTime: false, now: d(2026, 10, 20, 3, 59), calendar: utc) == .green })
        XCTAssertTrue(dues.allSatisfy { daily.side(due: $0, hasTime: false, now: d(2026, 10, 20, 4), calendar: utc) == .red })
    }

    func testANeverFlippedSwitchIsRedAndDueNow() {
        XCTAssertEqual(daily.side(due: nil, hasTime: false, now: d(2026, 10, 20, 12), calendar: utc), .red)
        XCTAssertTrue(daily.isDueNow(due: nil, hasTime: false, now: d(2026, 10, 20, 12), calendar: utc))
    }

    func testAWeeklyBoardTurnsRedOnItsResetDay() {
        // Flipped on Wednesday: green until next Monday 04:00.
        let due = weekly.dueAfterFlip(due: nil, hasTime: false, now: d(2026, 10, 21, 10), calendar: utc)
        XCTAssertEqual(due, d(2026, 10, 26))
        XCTAssertEqual(weekly.side(due: due, hasTime: false, now: d(2026, 10, 25, 22), calendar: utc), .green)
        XCTAssertEqual(weekly.side(due: due, hasTime: false, now: d(2026, 10, 26, 3), calendar: utc), .green)
        XCTAssertEqual(weekly.side(due: due, hasTime: false, now: d(2026, 10, 26, 4), calendar: utc), .red)
    }

    func testAnUntimedDueDayInsideAWeekStandsForThatWeek() {
        // Due Thursday (the reset day changed since): it belongs to the week that began on Monday.
        XCTAssertEqual(weekly.boardDay(ofDue: d(2026, 10, 22), hasTime: false, calendar: utc), d(2026, 10, 19))
        XCTAssertEqual(weekly.side(due: d(2026, 10, 22), hasTime: false, now: d(2026, 10, 21), calendar: utc), .red)
    }

    // MARK: - Times

    func testATimeBeforeTheResetBelongsToTheBoardDayThatBeganTheEveningBefore() {
        XCTAssertEqual(daily.boardDay(ofDue: d(2026, 10, 20, 0, 30), hasTime: true, calendar: utc), d(2026, 10, 19))
        XCTAssertEqual(daily.boardDay(ofDue: d(2026, 10, 20, 21), hasTime: true, calendar: utc), d(2026, 10, 20))
    }

    func testATimedFlipLandsOnTheNextBoardDaysTime() {
        // "Take meds 21:00": flipped at 20:00 Monday, due Tuesday 21:00.
        XCTAssertEqual(daily.dueAfterFlip(due: d(2026, 10, 19, 21), hasTime: true, now: d(2026, 10, 19, 20), calendar: utc),
                       d(2026, 10, 20, 21))
        // "Lights out 00:30": the board day Monday's step is at 00:30 on Tuesday; flipped then, due Wednesday 00:30.
        XCTAssertEqual(daily.dueAfterFlip(due: d(2026, 10, 20, 0, 30), hasTime: true, now: d(2026, 10, 20, 0, 35), calendar: utc),
                       d(2026, 10, 21, 0, 30))
    }

    func testBeforeItsTimeARedSwitchIsCalmAndAfterItLate() {
        // Due today (Monday's board day) at 21:00.
        let due = d(2026, 10, 19, 21)
        XCTAssertEqual(daily.side(due: due, hasTime: true, now: d(2026, 10, 19, 10), calendar: utc), .red)
        XCTAssertFalse(daily.isDueNow(due: due, hasTime: true, now: d(2026, 10, 19, 20, 59), calendar: utc))
        XCTAssertFalse(daily.isLate(due: due, hasTime: true, now: d(2026, 10, 19, 20, 59), calendar: utc))
        XCTAssertTrue(daily.isDueNow(due: due, hasTime: true, now: d(2026, 10, 19, 21), calendar: utc))
        XCTAssertTrue(daily.isLate(due: due, hasTime: true, now: d(2026, 10, 20, 1), calendar: utc), "after midnight, same board day")
    }

    func testAMissedTimedSwitchIsDueAgainAtThisPeriodsTimeNotLateAllDay() {
        // Due Monday 21:00, never flipped; on Tuesday at 10:00 it is red but calm until Tuesday 21:00.
        let due = d(2026, 10, 19, 21)
        let tuesday = d(2026, 10, 20, 10)
        XCTAssertEqual(daily.side(due: due, hasTime: true, now: tuesday, calendar: utc), .red)
        XCTAssertEqual(daily.dueMoment(due: due, hasTime: true, now: tuesday, calendar: utc), d(2026, 10, 20, 21))
        XCTAssertFalse(daily.isDueNow(due: due, hasTime: true, now: tuesday, calendar: utc))
        XCTAssertFalse(daily.isLate(due: due, hasTime: true, now: tuesday, calendar: utc))
    }

    func testAnUntimedRedSwitchIsDueFromTheBoardDaysStartAndNeverLate() {
        let due = d(2026, 10, 15)
        let now = d(2026, 10, 20, 4, 1)
        XCTAssertEqual(daily.dueMoment(due: due, hasTime: false, now: now, calendar: utc), d(2026, 10, 20, 4))
        XCTAssertTrue(daily.isDueNow(due: due, hasTime: false, now: now, calendar: utc))
        XCTAssertFalse(daily.isLate(due: due, hasTime: false, now: now, calendar: utc), "no counts of what is late")
    }

    func testAWeeklyTimedSwitchKeepsItsWeekday() {
        // Deep Clean, Mondays 04:00: "Vacuum" Saturday 10:00 in this week, flipped Saturday: next Saturday 10:00.
        let due = d(2026, 10, 24, 10)
        XCTAssertEqual(weekly.boardDay(ofDue: due, hasTime: true, calendar: utc), d(2026, 10, 19))
        XCTAssertEqual(weekly.dueAfterFlip(due: due, hasTime: true, now: d(2026, 10, 24, 11), calendar: utc), d(2026, 10, 31, 10))
        XCTAssertFalse(weekly.isDueNow(due: due, hasTime: true, now: d(2026, 10, 21), calendar: utc), "calm until Saturday")
    }

    // MARK: - Flip back

    func testFlipBackPutsItInThisPeriod() {
        XCTAssertEqual(daily.dueAfterFlipBack(due: d(2026, 10, 21), hasTime: false, now: d(2026, 10, 20, 1), calendar: utc),
                       d(2026, 10, 19), "01:00 Tuesday: Monday's board day")
        XCTAssertEqual(daily.dueAfterFlipBack(due: d(2026, 10, 21, 21), hasTime: true, now: d(2026, 10, 20, 12), calendar: utc),
                       d(2026, 10, 20, 21))
        let back = weekly.dueAfterFlipBack(due: d(2026, 10, 26), hasTime: false, now: d(2026, 10, 21), calendar: utc)
        XCTAssertEqual(weekly.side(due: back, hasTime: false, now: d(2026, 10, 21), calendar: utc), .red)
    }

    // MARK: - The light bar

    func testElapsedFractionRunsThroughThePeriod() {
        XCTAssertEqual(daily.elapsedFraction(now: d(2026, 10, 19, 4), calendar: utc), 0, accuracy: 0.001)
        XCTAssertEqual(daily.elapsedFraction(now: d(2026, 10, 19, 16), calendar: utc), 0.5, accuracy: 0.001)
        XCTAssertEqual(daily.elapsedFraction(now: d(2026, 10, 20, 3, 0), calendar: utc), 23.0 / 24, accuracy: 0.001)
    }

    // MARK: - Daylight saving (New York)

    func testTheResetHoldsItsWallClockTimeAcrossTheSpringChange() {
        // Mar 8, 2026: 02:00 jumps to 03:00. A 04:00 reset is still 04:00, and the board day is 23 hours long.
        let start = daily.start(ofPeriodDay: ny(2026, 3, 8), calendar: newYork)
        XCTAssertEqual(start, ny(2026, 3, 8, 4))
        let period = daily.period(containing: ny(2026, 3, 8, 12), calendar: newYork)
        XCTAssertEqual(period.duration, 24 * 3600)
        let saturday = daily.period(containing: ny(2026, 3, 7, 12), calendar: newYork)
        XCTAssertEqual(saturday.duration, 23 * 3600, "Saturday's board day runs to Sunday 04:00 across the gap")
    }

    func testAResetInsideTheSpringGapStartsWhenTheClockComesBack() {
        let half = SwitchboardSchedule(cadence: .daily, resetMinutes: 2 * 60 + 30)
        XCTAssertEqual(half.start(ofPeriodDay: ny(2026, 3, 8), calendar: newYork), ny(2026, 3, 8, 3))
        XCTAssertEqual(half.periodDay(containing: ny(2026, 3, 8, 1, 59), calendar: newYork), ny(2026, 3, 7))
        XCTAssertEqual(half.periodDay(containing: ny(2026, 3, 8, 3), calendar: newYork), ny(2026, 3, 8))
        XCTAssertEqual(half.start(ofPeriodDay: ny(2026, 3, 9), calendar: newYork), ny(2026, 3, 9, 2, 30), "back to 02:30 the next day")
    }

    func testTheResetHoldsAcrossTheAutumnChange() {
        // Nov 1, 2026: 02:00 falls back to 01:00. The board day before it is 25 hours long.
        XCTAssertEqual(daily.start(ofPeriodDay: ny(2026, 11, 1), calendar: newYork), ny(2026, 11, 1, 4))
        let saturday = daily.period(containing: ny(2026, 10, 31, 12), calendar: newYork)
        XCTAssertEqual(saturday.duration, 25 * 3600)
        let due = daily.dueAfterFlip(due: nil, hasTime: false, now: ny(2026, 10, 31, 22), calendar: newYork)
        XCTAssertEqual(due, ny(2026, 11, 1))
        XCTAssertEqual(daily.side(due: due, hasTime: false, now: ny(2026, 11, 1, 3, 59), calendar: newYork), .green)
        XCTAssertEqual(daily.side(due: due, hasTime: false, now: ny(2026, 11, 1, 4), calendar: newYork), .red)
    }

    func testATimedSwitchKeepsItsWallClockTimeAcrossTheChanges() {
        let springFlip = daily.dueAfterFlip(due: ny(2026, 3, 7, 21), hasTime: true, now: ny(2026, 3, 7, 21, 5), calendar: newYork)
        XCTAssertEqual(springFlip, ny(2026, 3, 8, 21))
        let autumnFlip = daily.dueAfterFlip(due: ny(2026, 10, 31, 21), hasTime: true, now: ny(2026, 10, 31, 21, 5), calendar: newYork)
        XCTAssertEqual(autumnFlip, ny(2026, 11, 1, 21))
        // 00:30 belongs to the board day before, across the autumn change too.
        XCTAssertEqual(daily.boardDay(ofDue: ny(2026, 11, 1, 0, 30), hasTime: true, calendar: newYork), ny(2026, 10, 31))
    }

    func testAWeeklyResetAcrossTheSpringChange() {
        // Sundays at 04:00: Mar 8, 2026 is a Sunday.
        let sundays = SwitchboardSchedule(cadence: .weekly, resetMinutes: 4 * 60, resetWeekday: 1)
        let due = sundays.dueAfterFlip(due: nil, hasTime: false, now: ny(2026, 3, 4, 12), calendar: newYork)
        XCTAssertEqual(due, ny(2026, 3, 8))
        XCTAssertEqual(sundays.side(due: due, hasTime: false, now: ny(2026, 3, 8, 3, 30), calendar: newYork), .green)
        XCTAssertEqual(sundays.side(due: due, hasTime: false, now: ny(2026, 3, 8, 4), calendar: newYork), .red)
    }
}
