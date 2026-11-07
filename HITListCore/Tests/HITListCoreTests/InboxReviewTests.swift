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

/// The review card's swipe (brief 60): right for Today, left to delete, armed past ~96 pt, committed on release.
final class InboxReviewSwipeTests: XCTestCase {
    private let t = InboxReviewSwipe.threshold

    func testThresholdIsAboutNinetySixPoints() {
        XCTAssertEqual(t, 96)
    }

    func testASmallDragIsNeitherArmedNorCommitted() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 40)
        XCTAssertEqual(swipe.phase, .none)
        XCTAssertEqual(swipe.offset, 40)
        XCTAssertEqual(swipe.release(velocity: 100), .none)
        XCTAssertEqual(swipe.offset, 0, "it springs back")
    }

    func testPastTheThresholdRightArmsTodayAndLeftArmsDelete() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: t)
        XCTAssertEqual(swipe.phase, .armed(.today), "exactly the threshold arms")
        swipe.drag(to: -t - 20)
        XCTAssertEqual(swipe.phase, .armed(.delete))
    }

    func testDraggingBackUnderTheThresholdDisarms() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 150)
        swipe.drag(to: 60)
        XCTAssertEqual(swipe.phase, .none)
        XCTAssertEqual(swipe.release(velocity: 0), .none)
    }

    func testReleasingWhileArmedCommits() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 130)
        XCTAssertEqual(swipe.release(velocity: 0), .committed(.today))
        XCTAssertEqual(swipe.phase, .committed(.today))
        XCTAssertEqual(swipe.offset, 130, "the card flies off from where it was let go")

        var left = InboxReviewSwipe()
        left.drag(to: -100)
        XCTAssertEqual(left.release(velocity: -50), .committed(.delete))
    }

    func testAFlickCommitsAShortDrag() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 40)
        XCTAssertEqual(swipe.release(velocity: InboxReviewSwipe.flickVelocity), .committed(.today))

        var left = InboxReviewSwipe()
        left.drag(to: -40)
        XCTAssertEqual(left.release(velocity: -1200), .committed(.delete))
    }

    func testAFlickNeedsSomeDragFirst() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 10)
        XCTAssertEqual(swipe.release(velocity: 2000), .none, "a tap that wobbles is not a swipe")
    }

    func testAFlickBackTheOtherWayCancels() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 120)
        XCTAssertEqual(swipe.release(velocity: -1000), .none, "flung back towards the middle")
        XCTAssertEqual(swipe.offset, 0)

        var short = InboxReviewSwipe()
        short.drag(to: -50)
        XCTAssertEqual(short.release(velocity: 1000), .none)
    }

    func testOnceCommittedFurtherDragsAreIgnored() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: -120)
        _ = swipe.release(velocity: 0)
        swipe.drag(to: 30)
        XCTAssertEqual(swipe.phase, .committed(.delete))
        XCTAssertEqual(swipe.offset, -120)
        XCTAssertEqual(swipe.release(velocity: 0), .committed(.delete))
    }

    func testResetStartsOver() {
        var swipe = InboxReviewSwipe()
        swipe.drag(to: 200)
        _ = swipe.release(velocity: 0)
        swipe.reset()
        XCTAssertEqual(swipe, InboxReviewSwipe())
    }

    func testProgressDrivesTheEdgeGlow() {
        var swipe = InboxReviewSwipe()
        XCTAssertEqual(swipe.progress, 0)
        XCTAssertNil(swipe.direction)
        swipe.drag(to: t / 2)
        XCTAssertEqual(swipe.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(swipe.direction, .today)
        swipe.drag(to: -t * 3)
        XCTAssertEqual(swipe.progress, 1, "clamped")
        XCTAssertEqual(swipe.direction, .delete)
    }
}
