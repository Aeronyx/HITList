import XCTest
import HITListCore
@testable import HITList

/// Day-section grouping and week-strip date math behind `UpcomingView`, on a fixed calendar.
final class UpcomingScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()
    private let locale = Locale(identifier: "en_US")

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Wednesday, Oct 28 2026, 10:00.
    private var now: Date { date(2026, 10, 28, 10) }

    private func task(_ title: String, _ due: Date?, time: Bool = false, priority: Int = 4, done: Bool = false) -> PlainTask {
        PlainTask(title: title, priority: priority, dueDate: due, hasDueTime: time, isCompleted: done)
    }

    private func schedule(_ tasks: [PlainTask], days: Int = 30) -> UpcomingSchedule<PlainTask> {
        UpcomingSchedule(items: tasks, now: now, dayCount: days, calendar: calendar)
    }

    // MARK: - Day sections

    func testEveryDayHasASectionStartingToday() {
        let s = schedule([], days: 30)
        XCTAssertEqual(s.days.count, 30)
        XCTAssertEqual(s.days.first?.date, date(2026, 10, 28))
        XCTAssertEqual(s.days.last?.date, date(2026, 11, 26))
        XCTAssertTrue(s.days.allSatisfy(\.items.isEmpty))
        XCTAssertTrue(s.overdue.isEmpty)
    }

    func testTasksLandOnTheirDayWithOrWithoutTime() {
        let s = schedule([
            task("Dentist", date(2026, 10, 29, 10), time: true),
            task("Groceries", date(2026, 10, 28)),
            task("Call mom", date(2026, 10, 28, 17), time: true),
            task("Late night", date(2026, 10, 28, 23, 59), time: true),
        ])
        XCTAssertEqual(s.days[0].items.map(\.filterTitle), ["Groceries", "Call mom", "Late night"],
                       "all-day first, then timed tasks in time order")
        XCTAssertEqual(s.days[1].items.map(\.filterTitle), ["Dentist"])
    }

    func testTodaysPassedTimeStaysUnderToday() {
        // 9:00 has passed at 10:00, but the task is still today's, not overdue.
        let s = schedule([task("Standup", date(2026, 10, 28, 9), time: true)])
        XCTAssertTrue(s.overdue.isEmpty)
        XCTAssertEqual(s.days[0].items.map(\.filterTitle), ["Standup"])
    }

    func testOverdueCollectsEverythingBeforeTodayOldestFirst() {
        let s = schedule([
            task("Yesterday 3pm", date(2026, 10, 27, 15), time: true),
            task("Last month", date(2026, 9, 2)),
            task("Yesterday", date(2026, 10, 27), priority: 1),
        ])
        XCTAssertEqual(s.overdue.map(\.filterTitle), ["Last month", "Yesterday", "Yesterday 3pm"])
        XCTAssertTrue(s.days.allSatisfy(\.items.isEmpty))
    }

    func testSameDayTiesBreakOnPriorityThenTitle() {
        let s = schedule([
            task("b", date(2026, 10, 30)), task("a", date(2026, 10, 30)), task("urgent", date(2026, 10, 30), priority: 1),
        ])
        XCTAssertEqual(s.days[2].items.map(\.filterTitle), ["urgent", "a", "b"])
    }

    func testFarFutureIsLeftOutUntilTheListGrows() {
        let far = task("Car inspection", date(2026, 12, 7))  // 40 days out
        XCTAssertTrue(schedule([far], days: 30).days.allSatisfy(\.items.isEmpty))
        let grown = schedule([far], days: 60)
        XCTAssertEqual(grown.days[40].date, date(2026, 12, 7))
        XCTAssertEqual(grown.days[40].items.map(\.filterTitle), ["Car inspection"])
    }

    func testUndatedAndCompletedAreLeftOut() {
        let s = schedule([task("Someday", nil), task("Done", date(2026, 10, 28), done: true), task("Done late", date(2026, 10, 1), done: true)])
        XCTAssertTrue(s.overdue.isEmpty)
        XCTAssertTrue(s.days.allSatisfy(\.items.isEmpty))
    }

    func testSectionsSurviveTheDaylightSavingChange() {
        // US clocks fall back on Nov 1 2026; every section must still start at midnight, one per day.
        let s = schedule([task("After DST", date(2026, 11, 2, 8), time: true)], days: 10)
        XCTAssertEqual(s.days.map { calendar.component(.hour, from: $0.date) }, Array(repeating: 0, count: 10))
        XCTAssertEqual(s.days[5].date, date(2026, 11, 2))
        XCTAssertEqual(s.days[5].items.map(\.filterTitle), ["After DST"])
    }

    func testCountsPerDayIncludeOverdueAndFarDaysButNotDone() {
        let counts = UpcomingSchedule.counts(of: [
            task("a", date(2026, 10, 28, 9), time: true), task("b", date(2026, 10, 28)),
            task("c", date(2026, 10, 20)), task("d", date(2027, 3, 1)),
            task("e", date(2026, 10, 28), done: true), task("f", nil),
        ], calendar: calendar)
        XCTAssertEqual(counts, [date(2026, 10, 28): 2, date(2026, 10, 20): 1, date(2027, 3, 1): 1])
    }

    func testHeaderTitles() {
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 28), now: now, calendar: calendar, locale: locale), "Wed · Oct 28 · Today")
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 29), now: now, calendar: calendar, locale: locale), "Thu · Oct 29 · Tomorrow")
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 30), now: now, calendar: calendar, locale: locale), "Fri · Oct 30")
        XCTAssertEqual(UpcomingFormat.header(for: date(2027, 1, 1), now: now, calendar: calendar, locale: locale), "Fri · Jan 1, 2027")
    }

    func testInlineAddDefaultsToTheRowsDayOnlyWithoutADate() {
        let day = date(2026, 11, 3)
        let plain = QuickAddResult(title: "Buy milk").dueDefaulting(to: day)
        XCTAssertEqual(plain.dueDate, day)
        XCTAssertFalse(plain.hasDueTime)

        let dated = QuickAddResult(title: "Dentist", dueDate: date(2026, 11, 5, 10), hasDueTime: true).dueDefaulting(to: day)
        XCTAssertEqual(dated.dueDate, date(2026, 11, 5, 10), "a date typed in the text wins")
        XCTAssertTrue(dated.hasDueTime)
    }

    // MARK: - Week strip

    private var strip: WeekStrip { WeekStrip(calendar: calendar) }

    func testWeeksStartOnMonday() {
        XCTAssertEqual(strip.startOfWeek(containing: now), date(2026, 10, 26))
        XCTAssertEqual(strip.startOfWeek(containing: date(2026, 11, 1, 23)), date(2026, 10, 26), "Sunday ends the week")
        XCTAssertEqual(strip.startOfWeek(containing: date(2026, 11, 2)), date(2026, 11, 2))
    }

    func testDaysAcrossAMonthBoundary() {
        let days = strip.days(ofWeekStarting: date(2026, 10, 26))
        XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, [26, 27, 28, 29, 30, 31, 1])
        XCTAssertEqual(days.last, date(2026, 11, 1))
        XCTAssertEqual(strip.title(forWeekStarting: days[0], locale: locale), "Oct – Nov 2026")
    }

    func testDaysAcrossAYearBoundary() {
        let start = strip.startOfWeek(containing: date(2026, 12, 31))
        XCTAssertEqual(start, date(2026, 12, 28))
        let days = strip.days(ofWeekStarting: start)
        XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, [28, 29, 30, 31, 1, 2, 3])
        XCTAssertEqual(calendar.component(.year, from: days[4]), 2027)
        XCTAssertEqual(strip.title(forWeekStarting: start, locale: locale), "Dec 2026 – Jan 2027")
    }

    func testTitleForAWeekInsideOneMonth() {
        XCTAssertEqual(strip.title(forWeekStarting: date(2026, 11, 9), locale: locale), "November 2026")
    }

    func testWeekOffsetsRoundTrip() {
        XCTAssertEqual(strip.week(1, from: now), date(2026, 11, 2))
        XCTAssertEqual(strip.week(-1, from: now), date(2026, 10, 19))
        XCTAssertEqual(strip.week(10, from: now), date(2027, 1, 4), "across the year and both DST changes")
        for offset in [-4, -1, 0, 1, 5, 10, 52] {
            XCTAssertEqual(strip.weekOffset(of: strip.week(offset, from: now), from: now), offset)
        }
        XCTAssertEqual(strip.weekOffset(of: date(2027, 1, 1), from: now), 9)
        XCTAssertEqual(strip.weekOffset(of: date(2026, 10, 25, 23), from: now), -1, "Sunday before is last week")
    }

    func testSundayStartingWeeks() {
        let sunday = WeekStrip(calendar: calendar, weekStart: 1)
        XCTAssertEqual(sunday.startOfWeek(containing: now), date(2026, 10, 25))
        XCTAssertEqual(sunday.days(ofWeekStarting: date(2026, 10, 25)).last, date(2026, 10, 31))
    }
}
