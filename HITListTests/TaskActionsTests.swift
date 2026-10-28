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
        XCTAssertEqual(t.recurrence, rule.encoded, file: file, line: line)
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

    func testRecurringKeepsTimeOfDayWhenHasDueTime() throws {
        let t = try task(due: tomorrow(17, 45), hasDueTime: true, recurrence: RecurrenceRule(frequency: .daily, interval: 3))
        TaskActions.toggleCompletion(t, in: context)
        let next = try XCTUnwrap(t.dueDate)
        XCTAssertEqual(cal.dateComponents([.hour, .minute], from: next), DateComponents(hour: 17, minute: 45))
        XCTAssertEqual(cal.dateComponents([.day], from: tomorrow(), to: cal.startOfDay(for: next)).day, 3)
        XCTAssertTrue(t.hasDueTime)
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
