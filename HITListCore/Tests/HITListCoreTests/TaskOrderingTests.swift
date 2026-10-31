import XCTest
@testable import HITListCore

/// The round-3 list rules: priority-then-due order, Inbox membership, Today's sections, Browse search.
final class TaskOrderingTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func titles(_ tasks: [PlainTask]) -> [String] { tasks.map(\.filterTitle) }

    // MARK: - Comparator

    func testPriorityComesBeforeDueDate() {
        let tasks = [
            PlainTask(title: "p4 today", priority: 4, dueDate: Fixed.date(2026, 10, 21)),
            PlainTask(title: "p1 next week", priority: 1, dueDate: Fixed.date(2026, 10, 28)),
            PlainTask(title: "p2 tomorrow", priority: 2, dueDate: Fixed.date(2026, 10, 22)),
        ]
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks)), ["p1 next week", "p2 tomorrow", "p4 today"])
    }

    func testSamePriorityGoesByDueDateAndTimeThenUndatedLast() {
        let tasks = [
            PlainTask(title: "undated", priority: 3),
            PlainTask(title: "today 5pm", priority: 3, dueDate: Fixed.date(2026, 10, 21, 17), hasDueTime: true),
            PlainTask(title: "today all day", priority: 3, dueDate: Fixed.date(2026, 10, 21)),
            PlainTask(title: "yesterday", priority: 3, dueDate: Fixed.date(2026, 10, 20)),
            PlainTask(title: "today 9am", priority: 3, dueDate: Fixed.date(2026, 10, 21, 9), hasDueTime: true),
        ]
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks)),
                       ["yesterday", "today all day", "today 9am", "today 5pm", "undated"])
    }

    func testTiesBreakOnTitleIgnoringCase() {
        let day = Fixed.date(2026, 10, 21)
        let tasks = [
            PlainTask(title: "banana", dueDate: day), PlainTask(title: "Apple", dueDate: day),
            PlainTask(title: "zebra"), PlainTask(title: "Mango"),
        ]
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks)), ["Apple", "banana", "Mango", "zebra"])
    }

    func testUndatedHighPriorityStillBeatsDatedLowPriority() {
        let tasks = [
            PlainTask(title: "dated p4", priority: 4, dueDate: Fixed.date(2026, 10, 21)),
            PlainTask(title: "undated p1", priority: 1),
        ]
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks)), ["undated p1", "dated p4"])
    }

    // MARK: - Inbox membership

    func testInboxMembership() {
        let datedInGroup = PlainTask(title: "dated in a group", dueDate: Fixed.date(2026, 10, 25), projectName: "Work")
        let undatedInGroup = PlainTask(title: "note in a group", projectName: "Work")
        let undatedNoGroup = PlainTask(title: "loose")
        let datedNoGroup = PlainTask(title: "dated loose", dueDate: Fixed.date(2026, 10, 19))
        XCTAssertTrue(TaskOrdering.isInInbox(datedInGroup))
        XCTAssertFalse(TaskOrdering.isInInbox(undatedInGroup))
        XCTAssertTrue(TaskOrdering.isInInbox(undatedNoGroup))
        XCTAssertTrue(TaskOrdering.isInInbox(datedNoGroup))
    }

    func testInboxListIsOneListByPriorityThenDueWithoutCompletedOrGroupNotes() {
        let tasks = [
            PlainTask(title: "loose undated p1", priority: 1),
            PlainTask(title: "work dated p4", priority: 4, dueDate: Fixed.date(2026, 10, 30), projectName: "Work"),
            PlainTask(title: "work note", priority: 1, projectName: "Work"),
            PlainTask(title: "loose dated p1", priority: 1, dueDate: Fixed.date(2026, 11, 2)),
            PlainTask(title: "done", priority: 1, dueDate: Fixed.date(2026, 10, 21), isCompleted: true),
            PlainTask(title: "loose undated p4"),
        ]
        XCTAssertEqual(titles(TaskOrdering.inbox(tasks)),
                       ["loose dated p1", "loose undated p1", "work dated p4", "loose undated p4"])
        XCTAssertEqual(titles(TaskOrdering.inbox(tasks, includeCompleted: true)),
                       ["done", "loose dated p1", "loose undated p1", "work dated p4", "loose undated p4"])
    }

    // MARK: - Today

    func testTodaySectionsSplitOverdueFromTodayAndDropUndatedAndFuture() {
        let tasks = [
            PlainTask(title: "last week", priority: 4, dueDate: Fixed.date(2026, 10, 14)),
            PlainTask(title: "yesterday p1", priority: 1, dueDate: Fixed.date(2026, 10, 20)),
            PlainTask(title: "this morning (passed)", priority: 4, dueDate: Fixed.date(2026, 10, 21, 9), hasDueTime: true),
            PlainTask(title: "today all day", priority: 4, dueDate: Fixed.date(2026, 10, 21)),
            PlainTask(title: "today p2 late", priority: 2, dueDate: Fixed.date(2026, 10, 21, 23, 30), hasDueTime: true),
            PlainTask(title: "tomorrow", priority: 1, dueDate: Fixed.date(2026, 10, 22)),
            PlainTask(title: "undated", priority: 1),
            PlainTask(title: "undated in group", priority: 1, projectName: "Work"),
            PlainTask(title: "done today", dueDate: Fixed.date(2026, 10, 21), isCompleted: true),
            PlainTask(title: "done last week", dueDate: Fixed.date(2026, 10, 14), isCompleted: true),
        ]
        let list = TaskOrdering.today(tasks, now: now, calendar: cal)
        XCTAssertEqual(titles(list.overdue), ["yesterday p1", "last week"], "priority first, then date")
        XCTAssertEqual(titles(list.today), ["today p2 late", "today all day", "this morning (passed)"])

        let withDone = TaskOrdering.today(tasks, now: now, calendar: cal, includeCompleted: true)
        XCTAssertEqual(titles(withDone.overdue), ["yesterday p1", "last week"], "old completed tasks stay out")
        XCTAssertEqual(titles(withDone.today), ["today p2 late", "done today", "today all day", "this morning (passed)"])
    }

    func testTodaySectionBoundaries() {
        XCTAssertNil(TaskOrdering.todaySection(for: nil, now: now, calendar: cal))
        XCTAssertEqual(TaskOrdering.todaySection(for: Fixed.date(2026, 10, 20, 23, 59), now: now, calendar: cal), .overdue)
        XCTAssertEqual(TaskOrdering.todaySection(for: Fixed.date(2026, 10, 21), now: now, calendar: cal), .today)
        XCTAssertEqual(TaskOrdering.todaySection(for: Fixed.date(2026, 10, 21, 23, 59), now: now, calendar: cal), .today)
        XCTAssertNil(TaskOrdering.todaySection(for: Fixed.date(2026, 10, 22), now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInToday(PlainTask(title: "x", dueDate: Fixed.date(2026, 10, 1)), now: now, calendar: cal))
        XCTAssertFalse(TaskOrdering.isInToday(PlainTask(title: "x"), now: now, calendar: cal))
        XCTAssertFalse(TaskOrdering.isInToday(PlainTask(title: "x", dueDate: Fixed.date(2026, 10, 21), isCompleted: true), now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInToday(PlainTask(title: "x", dueDate: Fixed.date(2026, 10, 21), isCompleted: true),
                                             now: now, calendar: cal, includeCompleted: true))
    }

    // MARK: - Search

    func testSearchMatchesTitlesAndNotesIncludingCompletedTasks() {
        let tasks = [
            PlainTask(title: "Renew passport", isCompleted: true),
            PlainTask(title: "Call the bank", notes: "about the passport fee"),
            PlainTask(title: "Buy milk"),
            PlainTask(title: "Passport photos", priority: 1, projectName: "Travel"),
        ]
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "PASSPORT")),
                       ["Passport photos", "Call the bank", "Renew passport"], "open first, completed last")
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "renew")), ["Renew passport"])
    }

    func testSearchNeedsEveryWordAndIgnoresAccents() {
        let tasks = [PlainTask(title: "Café with Ana", notes: "Friday"), PlainTask(title: "Cafe run")]
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "cafe friday")), ["Café with Ana"])
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "café")).sorted(), ["Cafe run", "Café with Ana"])
        XCTAssertTrue(TaskOrdering.search(tasks, text: "   ").isEmpty)
    }
}
