import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// `TaskActions.toggleCompletion` and `reschedule`. These use `Calendar.current` and `Date()`, so every
/// due date here is in the future relative to the run and expectations are computed with the same calendar.
@MainActor
final class TaskActionsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    /// Tomorrow at `hour:minute`, local time.
    private func tomorrow(_ hour: Int = 0, _ minute: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func task(due: Date?, hasDueTime: Bool = false, recurrence: RecurrenceRule? = nil) throws -> TaskItem {
        let t = TaskItem(title: "t", dueDate: due, hasDueTime: hasDueTime, recurrence: recurrence)
        context.insert(t)
        try context.save()
        return t
    }

    private func allTasks() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }

    // MARK: Recurring completion

    private func assertRolls(_ rule: RecurrenceRule, by component: Calendar.Component, _ value: Int,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let due = tomorrow()
        let t = try task(due: due, recurrence: rule)
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, cal.date(byAdding: component, value: value, to: due), file: file, line: line)
        XCTAssertFalse(t.isCompleted, "a recurring task rolls forward instead of completing", file: file, line: line)
        XCTAssertNil(t.completedAt, file: file, line: line)
        XCTAssertEqual(t.recurrenceRule, rule, "same repeat (a monthly rule gains its anchor day)", file: file, line: line)
        XCTAssertEqual(try allTasks().count, 1, "the occurrence rolls in place; no copy is created", file: file, line: line)
    }

    func testDailyRollsOneDay() throws { try assertRolls(.daily, by: .day, 1) }
    func testWeeklyRollsSevenDays() throws { try assertRolls(.weekly, by: .day, 7) }
    func testMonthlyRollsOneMonth() throws { try assertRolls(.monthly, by: .month, 1) }
    func testEveryThreeDaysRollsThreeDays() throws { try assertRolls(RecurrenceRule(frequency: .daily, interval: 3), by: .day, 3) }

    func testMonthlyFromJanuary31ClampsToEndOfFebruary() throws {
        let nextYear = cal.component(.year, from: Date()) + 1
        let due = cal.date(from: DateComponents(year: nextYear, month: 1, day: 31))!
        let t = try task(due: due, recurrence: .monthly)
        TaskActions.toggleCompletion(t, in: context)
        let next = try XCTUnwrap(t.dueDate)
        XCTAssertEqual(cal.component(.month, from: next), 2)
        XCTAssertEqual(cal.component(.day, from: next), cal.range(of: .day, in: .month, for: next)!.count)
    }

    // MARK: Anchor day (George, 2026-11-02)

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func lastDayOfFebruary(_ year: Int) -> Int { cal.range(of: .day, in: .month, for: day(year, 2, 1))!.count }

    /// A rule from the Repeat menu (no anchor) on Jan 31: Feb 28 (or 29), then Mar 31, not Mar 28.
    func testMonthlyOnThe31stComesBackToThe31st() throws {
        let year = cal.component(.year, from: Date()) + 1
        let t = try task(due: day(year, 1, 31, hour: 9), hasDueTime: true, recurrence: .monthly)
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, day(year, 2, lastDayOfFebruary(year), hour: 9))
        XCTAssertEqual(t.recurrence, "monthly;1;;31;09:00", "the anchor (and the time) is stored on the first roll")
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, day(year, 3, 31, hour: 9))
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, day(year, 4, 30, hour: 9))
        XCTAssertEqual(t.recurrenceRule, .monthly)
    }

    func testCompletingOnTheLastDayOfFebruaryLandsOnMarch31() throws {
        let year = cal.component(.year, from: Date()) + 1
        let t = try task(due: day(year, 2, lastDayOfFebruary(year)), recurrence: RecurrenceRule(frequency: .monthly, anchorDay: 31))
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, day(year, 3, 31))
        XCTAssertEqual(t.recurrence, "monthly;1;;31")
    }

    func testYearlyOnFebruary29ReturnsInTheNextLeapYear() throws {
        var leap = cal.component(.year, from: Date()) + 1
        while lastDayOfFebruary(leap) != 29 { leap += 1 }
        let t = try task(due: day(leap, 2, 29), recurrence: .yearly)
        for offset in 1...4 {
            TaskActions.toggleCompletion(t, in: context)
            XCTAssertEqual(t.dueDate, day(leap + offset, 2, offset == 4 ? 29 : 28), "year +\(offset)")
        }
        XCTAssertEqual(t.recurrence, "yearly;1;;29")
    }

    /// A "31st" task the user moved to the 15th repeats on the 15th, and its stored anchor follows.
    func testAMovedMonthlyTaskRepeatsOnItsNewDay() throws {
        let year = cal.component(.year, from: Date()) + 1
        let t = try task(due: day(year, 3, 15), recurrence: RecurrenceRule(frequency: .monthly, anchorDay: 31))
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, day(year, 4, 15))
        XCTAssertEqual(t.recurrence, "monthly;1;;15")
    }

    // MARK: The Repeat menu (final review): picking a repeat again keeps the day it returns to

    /// The Repeat menu ticks "Every month" for a "31st" task rolled to Feb 28 (the anchor doesn't make a
    /// different repeat). Picking it again stored the plain rule, so the next roll anchored on the 28th
    /// and the task repeated on the 28th from then on.
    func testPickingEveryMonthAgainKeepsThe31st() throws {
        let year = cal.component(.year, from: Date()) + 1
        let t = try task(due: day(year, 2, lastDayOfFebruary(year), hour: 9), hasDueTime: true,
                         recurrence: RecurrenceRule(frequency: .monthly, anchorDay: 31))
        TaskActions.setRecurrence(.monthly, on: t, in: context)
        XCTAssertEqual(t.recurrence, "monthly;1;;31;09:00")
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.dueDate, day(year, 3, 31, hour: 9), "back on the 31st, not the 28th")
    }

    func testAnotherMonthlyIntervalKeepsTheDayAndOtherRepeatsTakeTheDueDay() throws {
        let year = cal.component(.year, from: Date()) + 1
        let feb = day(year, 2, lastDayOfFebruary(year))
        let t = try task(due: feb, recurrence: RecurrenceRule(frequency: .monthly, anchorDay: 31))
        TaskActions.setRecurrence(RecurrenceRule(frequency: .monthly, interval: 3), on: t, in: context)
        XCTAssertEqual(t.recurrence, "monthly;3;;31", "every 3 months, still the 31st")
        TaskActions.setRecurrence(.yearly, on: t, in: context)
        XCTAssertEqual(t.recurrence, "yearly;1;;\(lastDayOfFebruary(year))", "a yearly repeat keeps the day it is due on")
        TaskActions.setRecurrence(.weekly, on: t, in: context)
        XCTAssertEqual(t.recurrence, "weekly;1", "weeks have no anchor")
        TaskActions.setRecurrence(nil, on: t, in: context)
        XCTAssertNil(t.recurrence)
        XCTAssertEqual(t.dueDate, feb, "Don't repeat leaves the date")
    }

    /// A task the user moved off its anchor follows its new day, as a completion would make it.
    func testPickingARepeatOnAMovedTaskFollowsTheDueDate() throws {
        let year = cal.component(.year, from: Date()) + 1
        let t = try task(due: day(year, 3, 15), recurrence: RecurrenceRule(frequency: .monthly, anchorDay: 31))
        TaskActions.setRecurrence(.monthly, on: t, in: context)
        XCTAssertEqual(t.recurrence, "monthly;1;;15")
        let undated = try task(due: nil)
        TaskActions.setRecurrence(.monthly, on: undated, in: context)
        XCTAssertEqual(undated.dueDate, cal.startOfDay(for: Date()), "a repeat on an undated task starts today")
        XCTAssertEqual(undated.recurrenceRule?.anchorDay, cal.component(.day, from: Date()))
    }

    func testWeeklyRuleStringIsLeftAlone() throws {
        let t = try task(due: tomorrow(), recurrence: nil)
        t.recurrence = "weekly;1;4,2"   // as an older build or an import might have written it
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.recurrence, "weekly;1;4,2", "only an anchor change rewrites the rule")
    }

    func testRecurringKeepsTimeOfDayWhenHasDueTime() throws {
        let t = try task(due: tomorrow(17, 45), hasDueTime: true, recurrence: RecurrenceRule(frequency: .daily, interval: 3))
        TaskActions.toggleCompletion(t, in: context)
        let next = try XCTUnwrap(t.dueDate)
        XCTAssertEqual(cal.dateComponents([.hour, .minute], from: next), DateComponents(hour: 17, minute: 45))
        XCTAssertEqual(cal.dateComponents([.day], from: tomorrow(), to: cal.startOfDay(for: next)).day, 3)
        XCTAssertTrue(t.hasDueTime)
    }

    // MARK: The repeat's time (brief 31)

    func testTheFirstRollOfATimedTaskStoresItsTimeInTheRule() throws {
        let t = try task(due: tomorrow(17, 45), hasDueTime: true, recurrence: .daily)
        XCTAssertEqual(t.recurrence, "daily;1", "as builds up to 0.4.0 wrote it")
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.recurrence, "daily;1;;;17:45")
    }

    /// A due time the clock pushed (the spring change) or anything else moved off the rule's time comes
    /// back to the rule's time on the next roll.
    func testRollingRebuildsTheTimeFromTheRule() throws {
        let t = try task(due: tomorrow(3, 30), hasDueTime: true, recurrence: RecurrenceRule.daily.withTime(hour: 2, minute: 30))
        TaskActions.toggleCompletion(t, in: context)
        let next = try XCTUnwrap(t.dueDate)
        XCTAssertEqual(cal.dateComponents([.hour, .minute], from: next), DateComponents(hour: 2, minute: 30))
        XCTAssertEqual(cal.dateComponents([.day], from: tomorrow(), to: cal.startOfDay(for: next)).day, 1)
        XCTAssertEqual(t.recurrence, "daily;1;;;02:30", "the rule's time is kept, not taken from the pushed due date")
    }

    func testAnAllDayTasksRuleLosesAStrayTime() throws {
        let t = try task(due: tomorrow(), recurrence: RecurrenceRule.daily.withTime(hour: 9, minute: 0))
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertEqual(t.recurrence, "daily;1")
        XCTAssertEqual(t.dueDate, cal.date(byAdding: .day, value: 1, to: tomorrow()), "still all day")
    }

    func testPickingARepeatTimesItToTheTask() throws {
        let timed = try task(due: tomorrow(7, 30), hasDueTime: true)
        TaskActions.setRecurrence(.daily, on: timed, in: context)
        XCTAssertEqual(timed.recurrence, "daily;1;;;07:30")
        let allDay = try task(due: tomorrow())
        TaskActions.setRecurrence(.weekdays, on: allDay, in: context)
        XCTAssertEqual(allDay.recurrence, "weekly;1;2,3,4,5,6")
    }

    /// The editor's time setters call this after changing the time (session 32 owns the editor).
    func testSyncingTheRepeatTimeFollowsTheTasksTime() throws {
        let t = try task(due: tomorrow(7, 30), hasDueTime: true, recurrence: RecurrenceRule.daily.withTime(hour: 7, minute: 30))
        t.dueDate = tomorrow(18, 0)
        TaskActions.syncRepeatTime(of: t)
        XCTAssertEqual(t.recurrence, "daily;1;;;18:00")
        t.hasDueTime = false
        TaskActions.syncRepeatTime(of: t)
        XCTAssertEqual(t.recurrence, "daily;1")
        let plain = try task(due: tomorrow(9, 0), hasDueTime: true)
        TaskActions.syncRepeatTime(of: plain)
        XCTAssertNil(plain.recurrence, "no repeat, nothing to do")
    }

    func testOverdueDailySkipsToTodayNotThePast() throws {
        let due = cal.date(byAdding: .day, value: -10, to: tomorrow(8, 0))!
        let t = try task(due: due, hasDueTime: true, recurrence: .daily)
        TaskActions.toggleCompletion(t, in: context)
        let next = try XCTUnwrap(t.dueDate)
        XCTAssertEqual(cal.startOfDay(for: next), cal.startOfDay(for: Date()))
        XCTAssertEqual(cal.component(.hour, from: next), 8)
    }

    func testRecurringTaskWithoutDueDateCompletesNormally() throws {
        let t = try task(due: nil, recurrence: .daily)
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertTrue(t.isCompleted)
        XCTAssertNotNil(t.completedAt)
    }

    // MARK: Plain completion

    func testCompletingSetsCompletedAtAndTouches() throws {
        let t = try task(due: tomorrow())
        let before = Date()
        t.updatedAt = before.addingTimeInterval(-60)
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertTrue(t.isCompleted)
        let completedAt = try XCTUnwrap(t.completedAt)
        XCTAssertGreaterThanOrEqual(completedAt, before)
        XCTAssertGreaterThanOrEqual(t.updatedAt, before)
        XCTAssertEqual(t.dueDate, tomorrow(), "completion leaves the due date alone")
    }

    func testUncompletingClearsCompletedAt() throws {
        let t = try task(due: nil)
        TaskActions.toggleCompletion(t, in: context)
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertFalse(t.isCompleted)
        XCTAssertNil(t.completedAt)
    }

    func testUncompletingARecurringTaskDoesNotRollIt() throws {
        // A recurring task can only be completed by older builds or an import; un-completing must not advance it.
        let due = tomorrow()
        let t = try task(due: due, recurrence: .weekly)
        t.isCompleted = true
        t.completedAt = Date()
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertFalse(t.isCompleted)
        XCTAssertNil(t.completedAt)
        XCTAssertEqual(t.dueDate, due)
    }

    func testCompletionIsSaved() throws {
        let t = try task(due: nil)
        TaskActions.toggleCompletion(t, in: context)
        XCTAssertFalse(context.hasChanges)
        let other = ModelContext(container)
        XCTAssertEqual(try other.fetch(FetchDescriptor<TaskItem>()).first?.isCompleted, true)
    }

    // MARK: Reschedule

    func testRescheduleKeepsTimeWhenTaskHasOne() throws {
        let t = try task(due: tomorrow(9, 30), hasDueTime: true)
        let target = cal.date(byAdding: .day, value: 5, to: tomorrow(23, 0))!
        TaskActions.reschedule(t, to: target, in: context)
        XCTAssertEqual(t.dueDate, cal.date(byAdding: .day, value: 5, to: tomorrow(9, 30)))
        XCTAssertTrue(t.hasDueTime)
    }

    func testRescheduleWithoutKeepTimeUsesTheGivenDate() throws {
        let t = try task(due: tomorrow(9, 30), hasDueTime: true)
        let target = cal.date(byAdding: .day, value: 2, to: tomorrow(14, 15))!
        TaskActions.reschedule(t, to: target, keepTime: false, in: context)
        XCTAssertEqual(t.dueDate, target)
    }

    func testRescheduleAllDayTaskIgnoresKeepTime() throws {
        let t = try task(due: tomorrow())
        let target = cal.date(byAdding: .day, value: 3, to: tomorrow())!
        TaskActions.reschedule(t, to: target, in: context)
        XCTAssertEqual(t.dueDate, target)
        XCTAssertFalse(t.hasDueTime)
    }

    func testRescheduleUndatedTaskSetsTheDate() throws {
        let t = try task(due: nil)
        TaskActions.reschedule(t, to: tomorrow(), in: context)
        XCTAssertEqual(t.dueDate, tomorrow())
    }

    func testRescheduleToNilClearsDateAndTime() throws {
        let t = try task(due: tomorrow(9, 30), hasDueTime: true, recurrence: .weekly)
        let before = Date()
        TaskActions.reschedule(t, to: nil, in: context)
        XCTAssertNil(t.dueDate)
        XCTAssertFalse(t.hasDueTime)
        XCTAssertEqual(t.recurrence, RecurrenceRule.weekly.encoded, "removing the date keeps the rule")
        XCTAssertGreaterThanOrEqual(t.updatedAt, before)
        XCTAssertFalse(context.hasChanges)
    }
}
