import XCTest
@testable import HITListCore

/// The round-3 list rules: priority-then-due order, Inbox membership, Today's sections, Browse search.
final class TaskOrderingTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func titles(_ tasks: [PlainTask]) -> [String] { tasks.map(\.filterTitle) }

    // MARK: - Comparator

    /// Round 34: `sorted` reads each task's place once and sorts those keys. Its order is the comparator's own, on
    /// lists made to tie in every way: equal priorities, equal days with and without a time, no date, equal ages,
    /// names that differ only in case, and switches listed as today's.
    func testSortedByKeysIsThePriorityThenDueOrderExactly() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let names = ["apple", "Apple", "banana", "Mango", "mango", "zebra", "Zebra", ""]
        for round in 0..<60 {
            var tasks: [PlainTask] = []
            for index in 0..<(5 + next(120)) {
                let day = Fixed.date(2026, 10, 15 + next(12))
                let due: Date? = next(4) == 0 ? nil : (next(2) == 0 ? day : day.addingTimeInterval(Double(next(24)) * 3_600))
                var task = PlainTask(title: names[next(names.count)] + (next(3) == 0 ? "" : " \(index % 4)"),
                                     priority: 1 + next(4), dueDate: due)
                task.filterHasDueTime = due != nil && next(2) == 0
                task.filterCreatedDate = next(6) == 0 ? nil : Fixed.date(2026, 9, 1 + next(5))
                if next(9) == 0 {
                    // A switch that opted in: listed as today's while it is due.
                    task.filterIsRecurring = true
                    task.filterLabelNames = ["Flipboard"]
                    task.filterSwitchOptedIn = next(2) == 0
                }
                tasks.append(task)
            }
            let byComparator = tasks.map { FlipboardSwitch.listed($0, now: now, calendar: cal) }
                .sorted { TaskOrdering.priorityThenDue($0, $1, calendar: cal) }
                .map(\.base)
            let byKeys = TaskOrdering.sorted(tasks, now: now, calendar: cal)
            XCTAssertEqual(byKeys.map(\.filterTitle), byComparator.map(\.filterTitle), "round \(round)")
            XCTAssertEqual(byKeys.map(\.filterDueDate), byComparator.map(\.filterDueDate), "round \(round)")
            XCTAssertEqual(byKeys.map(\.filterPriority), byComparator.map(\.filterPriority), "round \(round)")
        }
    }

    /// A task that does not repeat is no switch, and nothing more is asked of it: its labels, its Switchboard and
    /// its toggles are read only for a switch (every list asks this of every task it holds).
    func testOnlyASwitchIsAskedForMoreThanWhetherItRepeats() {
        struct Counting: FilterableTask {
            var base: PlainTask
            let reads: Reads
            final class Reads { var labels = 0, board = 0, optedIn = 0 }
            var filterTitle: String { base.filterTitle }
            var filterNotes: String { base.filterNotes }
            var filterPriority: Int { base.filterPriority }
            var filterDueDate: Date? { base.filterDueDate }
            var filterHasDueTime: Bool { base.filterHasDueTime }
            var filterIsCompleted: Bool { base.filterIsCompleted }
            var filterProjectName: String? { base.filterProjectName }
            var filterLabelNames: [String] { reads.labels += 1; return base.filterLabelNames }
            var filterIsRecurring: Bool { base.filterIsRecurring }
            var filterCreatedDate: Date? { base.filterCreatedDate }
            var filterIsSubtask: Bool { base.filterIsSubtask }
            var filterSwitchOptedIn: Bool { reads.optedIn += 1; return base.filterSwitchOptedIn }
            var filterSwitchboard: SwitchboardSchedule? { reads.board += 1; return base.filterSwitchboard }
        }
        let plain = Counting(base: PlainTask(title: "Milk", priority: 4, dueDate: Fixed.date(2026, 10, 21)), reads: .init())
        XCTAssertEqual(FlipboardSwitch.listing(for: plain, now: now, calendar: cal), .unchanged)
        XCTAssertTrue(TaskOrdering.isInInbox(plain, now: now, calendar: cal))
        XCTAssertEqual([plain.reads.labels, plain.reads.board, plain.reads.optedIn], [0, 0, 0])

        var repeating = PlainTask(title: "Rent", priority: 4, dueDate: Fixed.date(2026, 10, 21))
        repeating.filterIsRecurring = true
        let rent = Counting(base: repeating, reads: .init())
        XCTAssertEqual(FlipboardSwitch.listing(for: rent, now: now, calendar: cal), .unchanged)
        XCTAssertEqual([rent.reads.labels, rent.reads.board, rent.reads.optedIn], [1, 0, 0], "its labels, and nothing else")

        repeating.filterLabelNames = ["flipboard"]
        repeating.filterSwitchOptedIn = true
        let aSwitch = Counting(base: repeating, reads: .init())
        XCTAssertEqual(FlipboardSwitch.listing(for: aSwitch, now: now, calendar: cal), .today, "a switch is judged as before")
    }

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

    /// Same priority and date: the order they were added in, older first (George, 2026-11-03: tasks "fly
    /// out of order after being added" when the title decided). The title only breaks a tie on that too.
    func testTiesBreakOnCreationOrderBeforeTitle() {
        let day = Fixed.date(2026, 10, 21)
        let first = Fixed.date(2026, 10, 21, 9, 0), second = first.addingTimeInterval(3)
        let tasks = [
            PlainTask(title: "apple", priority: 2, dueDate: day, createdDate: second),
            PlainTask(title: "zebra", priority: 2, dueDate: day, createdDate: first),
            PlainTask(title: "mango", priority: 2, dueDate: day, createdDate: second),
            PlainTask(title: "undated b", priority: 2, createdDate: second),
            PlainTask(title: "undated a", priority: 2, createdDate: first),
        ]
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks)), ["zebra", "apple", "mango", "undated a", "undated b"])
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks.reversed())), ["zebra", "apple", "mango", "undated a", "undated b"])
        XCTAssertEqual(titles(FilterQuery.defaultSort(tasks)), ["zebra", "apple", "mango", "undated a", "undated b"],
                       "saved filters break ties the same way")
        // A task with no creation date (an old snapshot) counts as the oldest, so the order stays total.
        let unknown = PlainTask(title: "unknown", priority: 2, dueDate: day)
        XCTAssertEqual(titles(TaskOrdering.sorted(tasks + [unknown])).first, "unknown")
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
