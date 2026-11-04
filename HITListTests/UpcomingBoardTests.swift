import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// The board's actions on real tasks (brief 38): dropping a card on a day.
/// `TaskActions` uses `Calendar.current`, so dates here are relative to today in the current calendar.
@MainActor
final class UpcomingBoardTests: XCTestCase {
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

    private var now: Date { Date() }
    private var today: Date { cal.startOfDay(for: now) }

    /// `offset` days from today at `hour:minute` (or the start of the day).
    private func day(_ offset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: offset, to: today)!
        guard let hour else { return day }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @discardableResult
    private func task(_ title: String = "t", due: Date?, time: Bool = false, recurrence: RecurrenceRule? = nil,
                      done: Bool = false) throws -> TaskItem {
        let t = TaskItem(title: title, dueDate: due, hasDueTime: time, recurrence: recurrence)
        if done { t.isCompleted = true; t.completedAt = now }
        context.insert(t)
        try context.save()
        return t
    }

    private func payload(_ tasks: TaskItem...) -> [String] { tasks.map { TaskRescheduling.dragPayload(for: $0.id) } }

    private func allTasks() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }

    // MARK: - Drag to reschedule

    func testDroppingOnADayKeepsTheTimeAndTheRepeatsTime() throws {
        let t = try task(due: day(1, 9, 30), time: true, recurrence: RecurrenceRule.daily.withTime(hour: 9, minute: 30))
        let moved = TaskRescheduling.drop(payload(t), on: day(4), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(moved.map(\.id), [t.id])
        XCTAssertEqual(t.dueDate, day(4, 9, 30), "the day changes, the time of day stays")
        XCTAssertTrue(t.hasDueTime)
        XCTAssertEqual(t.recurrence, "daily;1;;;09:30", "the repeat keeps its time")
    }

    func testDroppingARepeatWhoseRuleHadNoTimeYetTimesTheRule() throws {
        // A repeat written before 0.4.1 has no time in its rule; the move stores the task's time there,
        // as the editor's time setters do (`TaskActions.syncRepeatTime`).
        let t = try task(due: day(1, 7, 15), time: true, recurrence: .weekly)
        TaskRescheduling.drop(payload(t), on: day(2), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(t.dueDate, day(2, 7, 15))
        XCTAssertEqual(t.recurrenceRule?.time, RecurrenceRule.TimeOfDay(hour: 7, minute: 15))
    }

    func testDroppingAnAllDayTaskKeepsItAllDay() throws {
        let t = try task(due: day(0))
        TaskRescheduling.drop(payload(t), on: day(3), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(t.dueDate, day(3))
        XCTAssertFalse(t.hasDueTime)
    }

    func testAnOverdueTaskDropsOntoToday() throws {
        let t = try task(due: day(-3, 8, 0), time: true)
        TaskRescheduling.drop(payload(t), on: day(0), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(t.dueDate, day(0, 8, 0))
    }

    func testDaysBeforeTodayTakeNoDrops() throws {
        let t = try task(due: day(2))
        let moved = TaskRescheduling.drop(payload(t), on: day(-1), among: try allTasks(), now: now, in: context)
        XCTAssertTrue(moved.isEmpty)
        XCTAssertEqual(t.dueDate, day(2))
    }

    func testCompletedUnknownAndSameDayDropsChangeNothing() throws {
        let done = try task("done", due: day(1), done: true)
        let sameDay = try task("same", due: day(3, 10, 0), time: true)
        let before = sameDay.updatedAt
        let moved = TaskRescheduling.drop(payload(done, sameDay) + ["not an id", UUID().uuidString], on: day(3),
                                          among: try allTasks(), now: now, in: context)
        XCTAssertTrue(moved.isEmpty)
        XCTAssertEqual(done.dueDate, day(1))
        XCTAssertEqual(sameDay.dueDate, day(3, 10, 0))
        XCTAssertEqual(sameDay.updatedAt, before, "a drop on its own day doesn't touch the task (no sync)")
    }

    func testOverdueColumnTakesNoDropsAndDayColumnsDo() throws {
        try task("late", due: day(-2))
        try task("soon", due: day(1))
        let entries = try allTasks().map { UpcomingView.Entry(task: $0, filterDueDate: $0.dueDate, filterIsCompleted: $0.isCompleted) }
        let board = UpcomingBoardModel(items: entries, window: UpcomingWindow(), now: now, showOverdue: true, calendar: cal)
        XCTAssertEqual(board.columns.first?.id, .overdue)
        XCTAssertFalse(board.columns[0].acceptsDrops)
        XCTAssertTrue(board.columns.dropFirst().allSatisfy(\.acceptsDrops))
    }
}
