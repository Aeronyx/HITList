import XCTest
import SwiftData
import UserNotifications
import HITListCore
@testable import HITList

/// The handlers behind the notification actions. They call the static functions directly rather than
/// `NotificationResponder.handle`, which reschedules through the real notification center of the host app.
@MainActor
final class NotificationActionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func task(due: Date, timed: Bool = true, recurrence: RecurrenceRule? = nil) throws -> TaskItem {
        let task = TaskItem(title: "Call", dueDate: due, hasDueTime: timed, recurrence: recurrence)
        context.insert(task)
        try context.save()
        return task
    }

    func testSnoozeLandsExactlyOneHourLaterAndStaysTimed() throws {
        let now = Date(timeIntervalSinceReferenceDate: 815_000_000.25)
        let task = try task(due: now.addingTimeInterval(-90))
        NotificationResponder.snooze(task, now: now, in: context)
        XCTAssertEqual(task.dueDate, now.addingTimeInterval(3600))
        XCTAssertTrue(task.hasDueTime)
        XCTAssertFalse(task.isCompleted)
        XCTAssertFalse(context.hasChanges, "snooze saves")
    }

    func testSnoozeAcrossMidnightMovesToTheNextDay() throws {
        let cal = Calendar.current
        let lateEvening = cal.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        let task = try task(due: lateEvening)
        NotificationResponder.snooze(task, now: lateEvening, in: context)
        XCTAssertEqual(task.dueDate, lateEvening.addingTimeInterval(3600))
        XCTAssertEqual(cal.component(.hour, from: task.dueDate!), 0)
    }

    func testCompleteMarksTaskDone() throws {
        let task = try task(due: Date())
        NotificationResponder.complete(task, in: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertNotNil(task.completedAt)
    }

    func testCompleteOnAnAlreadyCompletedTaskLeavesItCompleted() throws {
        let task = try task(due: Date())
        TaskActions.toggleCompletion(task, in: context)
        let completedAt = task.completedAt
        NotificationResponder.complete(task, in: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completedAt, completedAt)
    }

    func testCompleteRollsRecurringTaskForward() throws {
        let due = Date().addingTimeInterval(-60)
        let task = try task(due: due, recurrence: RecurrenceRule(frequency: .daily))
        NotificationResponder.complete(task, in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertGreaterThan(task.dueDate!, Date())
        XCTAssertTrue(task.hasDueTime)
    }

    func testFindsTaskByID() throws {
        let task = try task(due: Date())
        XCTAssertTrue(NotificationResponder.task(id: task.id, in: context) === task)
        XCTAssertNil(NotificationResponder.task(id: UUID(), in: context))
    }

    func testTappingTheBodyPostsOpenTaskWithTheTaskID() async throws {
        let id = UUID()
        let responder = NotificationResponder(container: container)
        let posted = expectation(forNotification: .openTask, object: nil) { note in
            note.userInfo?[NotificationScheduler.taskIDKey] as? UUID == id
        }
        await responder.handle(action: UNNotificationDefaultActionIdentifier, taskID: id)
        await fulfillment(of: [posted], timeout: 1)
    }

    func testCategoryOffersCompleteAndSnooze() {
        let category = NotificationResponder.category
        XCTAssertEqual(category.identifier, "TASK_DUE")
        XCTAssertEqual(category.actions.map(\.identifier), ["COMPLETE", "SNOOZE_1H"])
        XCTAssertEqual(category.actions.map(\.title), ["Complete", "Snooze 1 hour"])
    }

    // MARK: - What keeps the pending reminders current (beta review)

    /// Records the reasons `NotificationScheduler` would reschedule for while `body` runs.
    private func triggers(during body: () throws -> Void) async throws -> [String] {
        var reasons: [String] = []
        let observers = NotificationScheduler.observeTriggers { reasons.append($0) }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }
        try body()
        // The observers run on the main queue, one turn later.
        try await Task.sleep(for: .milliseconds(200))
        return reasons
    }

    /// Completing, deleting or rescheduling a task from Today, a Group, the Inbox or Upcoming (and from a
    /// row's context menu) never told the scheduler: the reminder of a task completed at 2:30 for 3:00
    /// still went off at 3:00, a deleted task's reminder fired, and a recurring task's next reminder
    /// waited for the app's next activation. Every local save is now a trigger.
    func testCompletingATaskFromAListAsksForAReschedule() async throws {
        let task = try task(due: Date().addingTimeInterval(1800))
        let reasons = try await triggers { TaskActions.toggleCompletion(task, in: context) }
        XCTAssertTrue(reasons.contains("local change"), "got \(reasons)")
    }

    func testDeletingAndReschedulingAskForAReschedule() async throws {
        let moved = try task(due: Date().addingTimeInterval(1800))
        let deleted = try task(due: Date().addingTimeInterval(3600))
        let reasons = try await triggers {
            TaskActions.reschedule(moved, to: Date().addingTimeInterval(86_400), in: context)
            TaskActions.delete(deleted, in: context)
        }
        XCTAssertTrue(reasons.contains("local change"), "got \(reasons)")
    }
}
