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

    func testOverdueCollectsEverythingBeforeTodayByPriorityThenOldestFirst() {
        let s = schedule([
            task("Yesterday 3pm", date(2026, 10, 27, 15), time: true),
            task("Last month", date(2026, 9, 2)),
            task("Yesterday", date(2026, 10, 27), priority: 1),
        ])
        XCTAssertEqual(s.overdue.map(\.filterTitle), ["Yesterday", "Last month", "Yesterday 3pm"])
        XCTAssertTrue(s.days.allSatisfy(\.items.isEmpty))
    }

    func testSameDayTiesBreakOnPriorityThenTitle() {
        let s = schedule([
            task("b", date(2026, 10, 30)), task("a", date(2026, 10, 30)), task("urgent", date(2026, 10, 30), priority: 1),
        ])
        XCTAssertEqual(s.days[2].items.map(\.filterTitle), ["urgent", "a", "b"])
    }

    func testWithinADayPriorityComesBeforeTime() {
        let s = schedule([
            task("9am p4", date(2026, 10, 30, 9), time: true),
            task("6pm p1", date(2026, 10, 30, 18), time: true, priority: 1),
            task("all day p2", date(2026, 10, 30), priority: 2),
            task("noon p1", date(2026, 10, 30, 12), time: true, priority: 1),
        ])
        XCTAssertEqual(s.days[2].items.map(\.filterTitle), ["noon p1", "6pm p1", "all day p2", "9am p4"])
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

    /// The list's headers (iPhone, iPad) read as the board's and every list's (brief 99; they were "Wed · Oct 28 · Today").
    func testHeaderTitles() {
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 28), now: now, calendar: calendar, locale: locale), "Oct 28 · Today · Wednesday")
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 29), now: now, calendar: calendar, locale: locale), "Oct 29 · Tomorrow · Thursday")
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 30), now: now, calendar: calendar, locale: locale), "Oct 30 · Friday")
        XCTAssertEqual(UpcomingFormat.header(for: date(2027, 1, 1), now: now, calendar: calendar, locale: locale), "Jan 1, 2027 · Friday")
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 29), now: now, shortWeekday: true, calendar: calendar, locale: locale),
                       "Oct 29 · Tomorrow · Thu")
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

    func testSubtasksAreNeverRowsOfTheirOwn() {
        let s = schedule([PlainTask(title: "Sub", dueDate: date(2026, 10, 28), isSubtask: true),
                          PlainTask(title: "Old sub", dueDate: date(2026, 10, 2), isSubtask: true),
                          task("Parent", date(2026, 10, 28))])
        XCTAssertEqual(s.days[0].items.map(\.filterTitle), ["Parent"])
        XCTAssertTrue(s.overdue.isEmpty)
    }

    // MARK: - Board (brief 38)

    private func board(_ tasks: [PlainTask], offset: Int = 0, showOverdue: Bool = true) -> UpcomingBoardModel<PlainTask> {
        UpcomingBoardModel(items: tasks, window: UpcomingWindow(offset: offset), now: now, showOverdue: showOverdue, calendar: calendar)
    }

    func testBoardIsSevenDaysFromToday() {
        let b = board([])
        XCTAssertEqual(b.columns.map(\.id), (28...31).map { .day(date(2026, 10, $0)) } + (1...3).map { .day(date(2026, 11, $0)) })
        XCTAssertTrue(b.columns.allSatisfy { $0.items.isEmpty && $0.count == 0 })
    }

    func testBoardPutsOverdueFirstOnlyWhenShownAndNotEmpty() {
        let late = task("Late", date(2026, 10, 20))
        XCTAssertEqual(board([late]).columns.first?.id, .overdue)
        XCTAssertEqual(board([late]).columns.count, 8)
        XCTAssertEqual(board([late], showOverdue: false).columns.first?.id, .day(date(2026, 10, 28)))
        XCTAssertEqual(board([late], showOverdue: false).columns.count, 7)
        XCTAssertEqual(board([task("Soon", date(2026, 10, 29))]).columns.first?.id, .day(date(2026, 10, 28)),
                       "no overdue tasks, no Overdue column")
        XCTAssertEqual(board([late], offset: 9).columns.first?.id, .overdue, "Overdue stays first while looking ahead")
    }

    func testBoardColumnsOrderLikeUpcomingAndCount() {
        let b = board([
            task("9am p4", date(2026, 10, 30, 9), time: true),
            task("all day p2", date(2026, 10, 30), priority: 2),
            task("noon p1", date(2026, 10, 30, 12), time: true, priority: 1),
            task("Done", date(2026, 10, 30), done: true),
            PlainTask(title: "Sub", dueDate: date(2026, 10, 30), isSubtask: true),
            task("Yesterday 3pm", date(2026, 10, 27, 15), time: true),
            task("Last month", date(2026, 9, 2)),
            task("Someday", nil),
            task("Next month", date(2026, 11, 20)),
        ])
        XCTAssertEqual(b.columns[0].items.map(\.filterTitle), ["Last month", "Yesterday 3pm"])
        XCTAssertEqual(b.columns[0].count, 2)
        let friday = b.columns[3]
        XCTAssertEqual(friday.id, .day(date(2026, 10, 30)))
        XCTAssertEqual(friday.items.map(\.filterTitle), ["noon p1", "all day p2", "9am p4"])
        XCTAssertEqual(friday.count, 3)
        XCTAssertEqual(b.columns.map(\.count).reduce(0, +), 5, "undated, done, sub-tasks and later days are left out")
    }

    func testBoardWindowShowsTheDaysItHasMovedTo() {
        let b = board([task("Mon", date(2026, 11, 2)), task("Today", date(2026, 10, 28)), task("Nov 9", date(2026, 11, 9))], offset: 5)
        XCTAssertEqual(b.columns.first?.id, .day(date(2026, 11, 2)))
        XCTAssertEqual(b.columns.last?.id, .day(date(2026, 11, 8)))
        XCTAssertEqual(b.columns.first?.items.map(\.filterTitle), ["Mon"])
        XCTAssertTrue(b.columns.allSatisfy { !$0.items.map(\.filterTitle).contains("Today") }, "days before the window are left out")
        XCTAssertTrue(b.columns.allSatisfy { !$0.items.map(\.filterTitle).contains("Nov 9") })
    }

    func testWindowMovesADayAtATimeAndNeverBeforeToday() {
        var w = UpcomingWindow()
        XCTAssertTrue(w.isAtToday)
        w.move(by: -1)
        XCTAssertEqual(w.offset, 0, "‹ stops at today")
        w.move(by: 1)
        w.move(by: 1)
        XCTAssertEqual(w.offset, 2)
        XCTAssertFalse(w.isAtToday)
        XCTAssertEqual(w.start(now: now, calendar: calendar), date(2026, 10, 30))
        XCTAssertEqual(w.days(now: now, calendar: calendar).count, 7)
        XCTAssertEqual(w.days(now: now, calendar: calendar).last, date(2026, 11, 5))
        w.move(by: -1)
        XCTAssertEqual(w.offset, 1)
        w.goToToday()
        XCTAssertEqual(w, UpcomingWindow())
    }

    func testWindowFollowsTheClockAcrossMidnight() {
        let w = UpcomingWindow(offset: 1)
        XCTAssertEqual(w.start(now: now, calendar: calendar), date(2026, 10, 29))
        XCTAssertEqual(w.start(now: date(2026, 10, 29, 0, 5), calendar: calendar), date(2026, 10, 30),
                       "the window counts from today, so it moves with the date")
    }

    func testWindowJumpsToAPickedDay() {
        var w = UpcomingWindow()
        w.jump(to: date(2026, 12, 24, 15), now: now, calendar: calendar)
        XCTAssertEqual(w.start(now: now, calendar: calendar), date(2026, 12, 24))
        w.jump(to: date(2026, 10, 1), now: now, calendar: calendar)
        XCTAssertEqual(w.offset, 0, "a past day goes to today")
        // Across the fall-back change (Nov 1): still whole days.
        w.jump(to: date(2026, 11, 2), now: now, calendar: calendar)
        XCTAssertEqual(w.offset, 5)
        XCTAssertEqual(w.days(now: now, calendar: calendar).map { calendar.component(.hour, from: $0) }, Array(repeating: 0, count: 7))
    }

    func testWindowTitleFollowsTheFirstDayAndSpansAMonthEnd() {
        func title(_ offset: Int) -> String { UpcomingWindow(offset: offset).title(now: now, calendar: calendar, locale: locale) }
        XCTAssertEqual(title(0), "October – November 2026", "Oct 28 – Nov 3")
        XCTAssertEqual(title(5), "November 2026", "Nov 2 – 8")
        XCTAssertEqual(title(30), "November – December 2026", "Nov 27 – Dec 3")
        XCTAssertEqual(title(62), "December 2026 – January 2027", "Dec 29 – Jan 4")
        XCTAssertEqual(title(66), "January 2027")
    }

    func testBoardColumnHeaders() {
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 10, 28), now: now, calendar: calendar, locale: locale), "Oct 28 · Today · Wednesday")
        XCTAssertEqual(UpcomingFormat.header(for: date(2026, 11, 4), now: now, calendar: calendar, locale: locale), "Nov 4 · Wednesday")
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
