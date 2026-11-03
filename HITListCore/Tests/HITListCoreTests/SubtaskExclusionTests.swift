import XCTest
@testable import HITListCore

/// Subtasks (brief 32) live inside their parent: no list shows one as a row of its own.
final class SubtaskExclusionTests: XCTestCase {
    private let today = Fixed.date(2026, 10, 21)
    private let overdue = Fixed.date(2026, 10, 19)

    private var tasks: [PlainTask] {
        [PlainTask(title: "Pack for trip"),
         PlainTask(title: "Socks", isSubtask: true),
         PlainTask(title: "Passport due today", dueDate: today, isSubtask: true),
         PlainTask(title: "Charger overdue", dueDate: overdue, isSubtask: true),
         PlainTask(title: "Old socks", isCompleted: true, isSubtask: true),
         PlainTask(title: "Call mum", dueDate: today)]
    }

    func testPlainTasksAreNotSubtasksByDefault() {
        XCTAssertFalse(PlainTask(title: "x").filterIsSubtask)
    }

    func testTopLevelDropsSubtasks() {
        XCTAssertEqual(TaskOrdering.topLevel(tasks).map(\.filterTitle), ["Pack for trip", "Call mum"])
    }

    func testTheInboxNeverListsASubtask() {
        XCTAssertFalse(TaskOrdering.isInInbox(PlainTask(title: "Socks", isSubtask: true)))
        XCTAssertEqual(TaskOrdering.inbox(tasks, includeCompleted: true).map(\.filterTitle), ["Call mum", "Pack for trip"])
    }

    func testTodayNeverListsASubtask() {
        let list = TaskOrdering.today(tasks, now: Fixed.now, calendar: Fixed.calendar, includeCompleted: true)
        XCTAssertEqual(list.today.map(\.filterTitle), ["Call mum"])
        XCTAssertEqual(list.overdue.map(\.filterTitle), [])
        XCTAssertFalse(TaskOrdering.isInToday(PlainTask(title: "x", dueDate: today, isSubtask: true), now: Fixed.now,
                                              calendar: Fixed.calendar))
    }

    func testSearchNeverListsASubtask() {
        XCTAssertEqual(TaskOrdering.search(tasks, text: "socks").map(\.filterTitle), [])
    }

    func testSavedFiltersNeverListASubtask() throws {
        for query in ["no date", "today | overdue", "completed", "search: socks", "!recurring"] {
            let matched = try FilterQuery(query, calendar: Fixed.calendar, now: Fixed.now)
                .apply(to: tasks, now: Fixed.now, calendar: Fixed.calendar)
            XCTAssertTrue(matched.allSatisfy { !$0.filterIsSubtask }, "\(query) listed a subtask")
        }
    }
}
