import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Process mode's queue (order, advancing, skipping, tasks leaving the inbox) and the inbox's texts.
final class InboxProcessQueueTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let ids = (0..<5).map { _ in UUID() }

    /// Five tasks created a minute apart, handed to the queue newest first.
    private func makeQueue(_ count: Int = 5) -> InboxProcessQueue {
        InboxProcessQueue(tasks: (0..<count).reversed().map { (id: ids[$0], createdAt: base.addingTimeInterval(Double($0) * 60)) })
    }

    func testOldestFirst() {
        let queue = makeQueue()
        XCTAssertEqual(queue.remaining, ids)
        XCTAssertEqual(queue.current, ids[0])
    }

    func testTiesOnCreationDateKeepAStableOrder() {
        let a = UUID(), b = UUID()
        let one = InboxProcessQueue(tasks: [(id: a, createdAt: base), (id: b, createdAt: base)])
        let other = InboxProcessQueue(tasks: [(id: b, createdAt: base), (id: a, createdAt: base)])
        XCTAssertEqual(one.remaining, other.remaining)
    }

    func testAdvanceStepsThroughToTheEnd() {
        var queue = makeQueue(3)
        XCTAssertEqual(queue.progressText, "1 of 3")
        queue.advance()
        XCTAssertEqual(queue.current, ids[1])
        XCTAssertEqual(queue.progressText, "2 of 3")
        queue.advance()
        queue.advance()
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isFinished)
        XCTAssertEqual(queue.finished, 3)
        queue.advance()
        XCTAssertEqual(queue.finished, 3, "advancing past the end does nothing")
    }

    func testSkipSendsATaskToTheEndOnceThenDropsIt() {
        var queue = makeQueue(3)
        queue.skip()
        XCTAssertEqual(queue.remaining, [ids[1], ids[2], ids[0]])
        queue.advance()
        queue.advance()
        XCTAssertEqual(queue.current, ids[0], "the skipped task comes back last")
        queue.skip()
        XCTAssertTrue(queue.isFinished, "a second skip drops it")
        XCTAssertEqual(queue.finished, 3)
    }

    func testSkippingTheOnlyTaskShowsItAgainThenFinishes() {
        var queue = makeQueue(1)
        queue.skip()
        XCTAssertEqual(queue.current, ids[0])
        queue.skip()
        XCTAssertTrue(queue.isFinished)
    }

    func testProgressCountsSkippedTasksAsPassedAndNeverGoesBack() {
        var queue = makeQueue(3)
        queue.skip()
        XCTAssertEqual(queue.progressText, "2 of 3")
        queue.advance()
        XCTAssertEqual(queue.progressText, "3 of 3")
        queue.advance()
        XCTAssertEqual(queue.current, ids[0])
        XCTAssertEqual(queue.progressText, "3 of 3", "the skipped task's second look is still the last")
    }

    func testTasksThatLeaveTheInboxDropOut() {
        var queue = makeQueue()
        // ids[2] moved to a project, ids[4] deleted on another device.
        queue.retain(Set([ids[0], ids[1], ids[3]]))
        XCTAssertEqual(queue.remaining, [ids[0], ids[1], ids[3]])
        XCTAssertEqual(queue.total, 3)
        XCTAssertEqual(queue.progressText, "1 of 3")
    }

    func testTheCurrentTaskLeavingTheInboxShowsTheNextOne() {
        var queue = makeQueue(3)
        queue.retain(Set([ids[1], ids[2]]))
        XCTAssertEqual(queue.current, ids[1])
    }

    func testRetainDropsASkippedTaskWaitingAtTheEnd() {
        var queue = makeQueue(3)
        queue.skip()
        queue.retain(Set([ids[1], ids[2]]))
        XCTAssertEqual(queue.remaining, [ids[1], ids[2]])
        XCTAssertEqual(queue.progressText, "1 of 2")
    }

    func testRestoreUndoesAnAdvance() {
        var queue = makeQueue(3)
        queue.advance()
        queue.restore(ids[0])
        XCTAssertEqual(queue.remaining, ids.prefix(3).map { $0 })
        XCTAssertEqual(queue.progressText, "1 of 3")
    }

    func testEmptyQueueIsFinished() {
        let queue = InboxProcessQueue(tasks: [])
        XCTAssertTrue(queue.isFinished)
        XCTAssertEqual(queue.total, 0)
    }

    func testTexts() {
        XCTAssertEqual(InboxText.header(count: 7), "Inbox · 7")
        XCTAssertEqual(InboxText.header(count: 0), "Inbox · 0")
        XCTAssertEqual(InboxText.progress(3, of: 7), "3 of 7")
        XCTAssertEqual(InboxText.reviewMenuItem(count: 3), "Review 3 unsorted…")
        XCTAssertEqual(InboxText.reviewMenuItem(count: 1), "Review 1 unsorted…")
        XCTAssertNil(InboxText.reviewMenuItem(count: 0), "no item when nothing needs review")
    }
}

/// The queue against real tasks: only the unsorted (no date, no Group), and tasks leaving it through `TaskActions`.
@MainActor
final class InboxProcessStoreTests: XCTestCase {
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

    @discardableResult
    private func task(_ title: String, minutesAgo: Double, project: Project? = nil, due: Date? = nil) -> TaskItem {
        let t = TaskItem(title: title, project: project)
        t.dueDate = due
        t.createdAt = Date().addingTimeInterval(-minutesAgo * 60)
        context.insert(t)
        return t
    }

    private func allTasks() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }

    func testQueueHoldsOnlyUnsortedTasksOldestFirst() throws {
        let work = Project(name: "Work")
        context.insert(work)
        let newer = task("newer", minutesAgo: 1)
        let older = task("older", minutesAgo: 10)
        task("in a Group", minutesAgo: 20, project: work)
        task("dated, in the Inbox", minutesAgo: 25, due: Date())
        task("dated in a Group", minutesAgo: 26, project: work, due: Date())
        let done = task("done", minutesAgo: 30)
        done.isCompleted = true
        let parent = task("parent", minutesAgo: 40, project: work)
        let step = task("step", minutesAgo: 35)
        step.parent = parent
        try context.save()

        let queue = InboxProcessQueue(reviewOf: try allTasks())
        XCTAssertEqual(queue.remaining, [older.id, newer.id])
        XCTAssertEqual(InboxReview.count(try allTasks()), 2, "the menu item's count")
    }

    func testMovingTheCurrentTaskToAGroupRemovesItFromTheQueue() throws {
        let first = task("first", minutesAgo: 10)
        let second = task("second", minutesAgo: 5)
        try context.save()
        var queue = InboxProcessQueue(reviewOf: try allTasks())

        first.project = try TaskActions.findOrCreateProject(named: "Garden", in: context)
        try context.save()
        queue.retainReview(of: try allTasks())

        XCTAssertEqual(queue.remaining, [second.id])
        XCTAssertEqual(queue.progressText, "1 of 1")
    }

    func testDeletedCompletedAndScheduledTasksLeaveTheQueue() throws {
        let a = task("a", minutesAgo: 30)
        let b = task("b", minutesAgo: 20)
        let c = task("c", minutesAgo: 10)
        let d = task("d", minutesAgo: 5)
        try context.save()
        var queue = InboxProcessQueue(reviewOf: try allTasks())

        TaskActions.delete(a, in: context)
        TaskActions.toggleCompletion(b, in: context)
        TaskActions.reschedule(c, to: Date(), in: context)
        queue.retainReview(of: try allTasks())

        XCTAssertEqual(queue.remaining, [d.id], "a dated task has its place: it leaves the review")
    }
}
