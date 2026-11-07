import XCTest
@testable import HITListCore

/// Review Inbox goes through the unsorted tasks only (brief 60): no date, no Group, still open, not a subtask.
final class InboxReviewTests: XCTestCase {
    func testAnUndatedTaskWithNoGroupNeedsReview() {
        XCTAssertTrue(InboxReview.needsReview(PlainTask(title: "Brain dump")))
    }

    func testPriorityAndLabelsDoNotSortATask() {
        // Only a date or a Group gives a task its place; a p1 with labels still sits unsorted in the Inbox.
        XCTAssertTrue(InboxReview.needsReview(PlainTask(title: "Urgent idea", priority: 1, labelNames: ["phone"])))
    }

    func testADatedTaskIsSorted() {
        XCTAssertFalse(InboxReview.needsReview(PlainTask(title: "Dentist", dueDate: Fixed.now)))
        XCTAssertFalse(InboxReview.needsReview(PlainTask(title: "Dentist at 3", dueDate: Fixed.now, hasDueTime: true)))
    }

    func testATaskInAGroupIsSorted() {
        XCTAssertFalse(InboxReview.needsReview(PlainTask(title: "Note", projectName: "Garden")))
        XCTAssertFalse(InboxReview.needsReview(PlainTask(title: "Dated in a Group", dueDate: Fixed.now, projectName: "Work")))
    }

    func testCompletedTasksAndSubtasksAreNeverReviewed() {
        XCTAssertFalse(InboxReview.needsReview(PlainTask(title: "Done", isCompleted: true)))
        XCTAssertFalse(InboxReview.needsReview(PlainTask(title: "Step", isSubtask: true)))
    }

    func testEveryTaskNeedingReviewIsInTheInbox() {
        let tasks = [
            PlainTask(title: "a"), PlainTask(title: "b", dueDate: Fixed.now), PlainTask(title: "c", projectName: "G"),
            PlainTask(title: "d", isCompleted: true), PlainTask(title: "e", isSubtask: true), PlainTask(title: "f", priority: 2),
        ]
        for task in tasks where InboxReview.needsReview(task) {
            XCTAssertTrue(TaskOrdering.isInInbox(task), task.filterTitle)
        }
        XCTAssertEqual(InboxReview.count(tasks), 2)
    }

    func testCountOfNone() {
        XCTAssertEqual(InboxReview.count([PlainTask]()), 0)
    }
}
