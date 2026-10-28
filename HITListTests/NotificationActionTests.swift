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
}
