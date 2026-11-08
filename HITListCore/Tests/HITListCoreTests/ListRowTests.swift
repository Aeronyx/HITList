import XCTest
@testable import HITListCore

/// Brief 62 (George: shared tasks "are supposed to show up in my todo list as shared tasks, not in some other
/// list"): a list row is a task of yours or a shared task, and every rule in the core takes it unchanged. A shared
/// list is to its tasks what a Group is to yours.
final class ListRowTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private let work = UUID()
    private let home = UUID()
    private let trip = UUID()
    private let groceries = UUID()

    /// A task of yours: in the Group `group`, when it has one.
    private struct Mine: ListRowItem {
        var rowID = UUID()
        var filterTitle: String
        var filterNotes = ""
        var filterPriority = 4
        var filterDueDate: Date?
        var filterHasDueTime = false
        var filterIsCompleted = false
        var group: (id: UUID, name: String)?
        var filterLabelNames: [String] = []
        var filterIsRecurring = false
        var filterCreatedDate: Date?
        var filterIsSubtask = false

        var filterProjectName: String? { group?.name }
        var rowGroupID: UUID? { group?.id }
    }

    /// A task of a shared list: its list is its Group, so it always has one.
    private struct Theirs: ListRowItem {
        var rowID = UUID()
        var filterTitle: String
        var filterPriority = 4
        var filterDueDate: Date?
        var filterHasDueTime = false
        var filterIsCompleted = false
        var list: (id: UUID, name: String)
        var filterCreatedDate: Date?

        var filterNotes: String { "" }
        var filterProjectName: String? { list.name }
        var filterLabelNames: [String] { [] }
        var filterIsRecurring: Bool { false }
        var rowGroupID: UUID? { list.id }
    }

    private typealias Row = ListRow<Mine, Theirs>

    private func mine(_ title: String, priority: Int = 4, due: Date? = nil, group: UUID? = nil, done: Bool = false,
                      created: Date? = nil) -> Row {
        let name = group.map { $0 == work ? "Work" : $0 == home ? "Home" : "Other" }
        return .own(Mine(filterTitle: title, filterPriority: priority, filterDueDate: due, filterIsCompleted: done,
                         group: group.map { ($0, name!) }, filterCreatedDate: created))
    }

    private func theirs(_ title: String, priority: Int = 4, due: Date? = nil, list: UUID? = nil, done: Bool = false,
                        created: Date? = nil) -> Row {
        let id = list ?? trip
        let name = id == trip ? "Trip" : id == groceries ? "Groceries" : "Work"
        return .shared(Theirs(filterTitle: title, filterPriority: priority, filterDueDate: due, filterIsCompleted: done,
                              list: (id, name), filterCreatedDate: created))
    }

    private func titles(_ rows: [Row]) -> [String] { rows.map(\.filterTitle) }

    // MARK: - The row

    func testARowIsTheTaskBehindIt() throws {
        let task = Theirs(filterTitle: "Book the cabin", filterPriority: 1, filterDueDate: Fixed.date(2026, 10, 23),
                          filterHasDueTime: true, list: (trip, "Trip"), filterCreatedDate: Fixed.date(2026, 10, 1))
        let row = Row.shared(task)
        XCTAssertEqual(row.id, task.rowID)
        XCTAssertTrue(row.isShared)
        XCTAssertNil(row.ownTask)
        XCTAssertEqual(try XCTUnwrap(row.sharedTask).rowID, task.rowID)
        XCTAssertEqual(row.filterTitle, "Book the cabin")
        XCTAssertEqual(row.filterPriority, 1)
        XCTAssertEqual(row.filterDueDate, Fixed.date(2026, 10, 23))
        XCTAssertTrue(row.filterHasDueTime)
        XCTAssertEqual(row.filterProjectName, "Trip", "its list's name is its Group name")
        XCTAssertEqual(row.filterCreatedDate, Fixed.date(2026, 10, 1))
        XCTAssertFalse(row.filterIsSubtask)
        XCTAssertEqual(row.group, .shared(trip))

        let own = mine("Call Sam", group: work)
        XCTAssertFalse(own.isShared)
        XCTAssertNotNil(own.ownTask)
        XCTAssertEqual(own.group, .group(work))
        XCTAssertNil(mine("Loose").group, "a task in no Group is Ungrouped")
    }

    func testARowCompletingKeepsTheDateItWasListedUnder() {
        // While its completion animates, a row stays where it was tapped (a recurring task has already moved on).
        let row = mine("Water plants", due: Fixed.date(2026, 10, 28), done: true)
        let held = Row(row.kind, listedAt: Fixed.date(2026, 10, 21), isCompleted: false)
        XCTAssertEqual(held.filterDueDate, Fixed.date(2026, 10, 21))
        XCTAssertFalse(held.filterIsCompleted)
        XCTAssertEqual(held.id, row.id)
        XCTAssertEqual(held.filterTitle, "Water plants")
    }

    func testRowsTakeBothKinds() {
        let own = [Mine(filterTitle: "a"), Mine(filterTitle: "b")]
        let shared = [Theirs(filterTitle: "c", list: (trip, "Trip"))]
        let rows = ListRows.rows(own: own, shared: shared)
        XCTAssertEqual(titles(rows), ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.isShared), [false, false, true])
    }

    // MARK: - The lists' rules, unchanged

    func testSharedTasksSortAmongYoursByPriorityThenDate() {
        let rows = [
            mine("mine p4 today", due: Fixed.date(2026, 10, 21)),
            theirs("shared p1 tomorrow", priority: 1, due: Fixed.date(2026, 10, 22)),
            mine("mine p1 today", priority: 1, due: Fixed.date(2026, 10, 21)),
            theirs("shared p2 undated", priority: 2),
            theirs("shared p4 today 9:00", due: Fixed.date(2026, 10, 21, 9)),
        ]
        XCTAssertEqual(titles(TaskOrdering.sorted(rows, now: now, calendar: cal)),
                       ["mine p1 today", "shared p1 tomorrow", "shared p2 undated", "mine p4 today", "shared p4 today 9:00"])
    }

    func testADatedSharedTaskIsInTheInboxAndAnUndatedOneIsNot() {
        // Undated, it is a note in its list, as an undated task is in its Group: only on the list's own screen.
        let rows = [
            theirs("dated", due: Fixed.date(2026, 10, 30)),
            theirs("undated"),
            theirs("done", due: Fixed.date(2026, 10, 21), done: true),
            mine("loose"),
        ]
        XCTAssertEqual(titles(TaskOrdering.inbox(rows, now: now, calendar: cal)), ["dated", "loose"])
        XCTAssertEqual(titles(TaskOrdering.inbox(rows, includeCompleted: true, now: now, calendar: cal)),
                       ["done", "dated", "loose"])
    }

    func testTodayTakesSharedTasksDueTodayAndOverdue() {
        let rows = [
            theirs("shared overdue", due: Fixed.date(2026, 10, 19)),
            mine("mine today", priority: 2, due: Fixed.date(2026, 10, 21)),
            theirs("shared today", priority: 1, due: Fixed.date(2026, 10, 21, 18)),
            theirs("shared tomorrow", due: Fixed.date(2026, 10, 22)),
            theirs("shared undated"),
        ]
        let today = TaskOrdering.today(rows, now: now, calendar: cal)
        XCTAssertEqual(titles(today.overdue), ["shared overdue"])
        XCTAssertEqual(titles(today.today), ["shared today", "mine today"])
        XCTAssertEqual(rows.filter { TaskOrdering.isInToday($0, now: now, calendar: cal) }.count, 3)
    }

    func testASharedTaskIsNeverAFlipboardSwitch() {
        let row = theirs("Bins out", due: Fixed.date(2026, 10, 25))
        XCTAssertEqual(FlipboardSwitch.listing(for: row, now: now, calendar: cal), .unchanged)
        XCTAssertEqual(FlipboardSwitch.listedDueDate(for: row, now: now, calendar: cal), Fixed.date(2026, 10, 25))
    }

    // MARK: - Sort by Group

    func testTheGroupOrderIsYourGroupsThenTheSharedLists() {
        XCTAssertEqual(ListRows.groupOrder(groups: [work, home], sharedLists: [groceries, trip]),
                       [.group(work), .group(home), .shared(groceries), .shared(trip)])
    }

    private func groupSections(_ rows: [Row]) -> [ListSection<ListRowGroup, Row>] {
        GroupedOrdering.sections(rows, by: .group, groupOrder: ListRows.groupOrder(groups: [work, home], sharedLists: [groceries, trip]),
                                 now: now, calendar: cal, groupOf: \.group)
    }

    func testSortByGroupPutsEachSharedListAfterTheGroupsAndBeforeUngrouped() {
        let rows = [
            mine("loose", priority: 1),
            theirs("cabin", due: Fixed.date(2026, 10, 23)),
            mine("report", due: Fixed.date(2026, 10, 22), group: work),
            theirs("milk", due: Fixed.date(2026, 10, 21), list: groceries),
            mine("lawn", due: Fixed.date(2026, 10, 24), group: home),
        ]
        let sections = groupSections(rows)
        XCTAssertEqual(sections.map(\.key), [.group(.group(work)), .group(.group(home)), .group(.shared(groceries)),
                                             .group(.shared(trip)), .ungrouped])
        XCTAssertEqual(sections.map { titles($0.tasks) }, [["report"], ["lawn"], ["milk"], ["cabin"], ["loose"]])
    }

    func testASharedListNamedLikeAGroupHasASectionOfItsOwn() {
        // A list called "Work" shared by a friend is not your Work Group.
        let otherWork = UUID()
        let rows = [
            mine("yours", due: Fixed.date(2026, 10, 22), group: work),
            theirs("theirs", due: Fixed.date(2026, 10, 22), list: otherWork),
        ]
        let sections = GroupedOrdering.sections(rows, by: .group,
                                                groupOrder: ListRows.groupOrder(groups: [work], sharedLists: [otherWork]),
                                                now: now, calendar: cal, groupOf: \.group)
        XCTAssertEqual(sections.map(\.key), [.group(.group(work)), .group(.shared(otherWork))])
        XCTAssertEqual(rows.map(\.filterProjectName), ["Work", "Work"])
    }

    func testEachSharedSectionKeepsPriorityThenDateAndCountsItsOpenTasks() {
        let rows = [
            theirs("later p4", due: Fixed.date(2026, 10, 25)),
            theirs("sooner p4", due: Fixed.date(2026, 10, 22)),
            theirs("p1", priority: 1, due: Fixed.date(2026, 10, 30)),
            theirs("done", due: Fixed.date(2026, 10, 21), done: true),
        ]
        let section = groupSections(rows)[0]
        XCTAssertEqual(section.key, .group(.shared(trip)))
        XCTAssertEqual(titles(section.tasks), ["p1", "done", "sooner p4", "later p4"])
        XCTAssertEqual(section.openCount, 3)
    }

    func testTodayByGroupGivesSharedListsTheirSectionsInBothHalves() {
        let rows = [
            theirs("overdue cabin", due: Fixed.date(2026, 10, 20)),
            mine("overdue report", due: Fixed.date(2026, 10, 19), group: work),
            theirs("milk today", due: Fixed.date(2026, 10, 21), list: groceries),
            mine("loose today", due: Fixed.date(2026, 10, 21)),
            theirs("cabin next week", due: Fixed.date(2026, 10, 28)),
        ]
        let split = GroupedOrdering.today(rows, by: .group,
                                          groupOrder: ListRows.groupOrder(groups: [work, home], sharedLists: [groceries, trip]),
                                          now: now, calendar: cal, groupOf: \.group)
        XCTAssertEqual(split.overdue.map(\.key), [.group(.group(work)), .group(.shared(trip))])
        XCTAssertEqual(split.today.map(\.key), [.group(.shared(groceries)), .ungrouped])
    }

    func testSortByDateFilesSharedTasksByTheirDay() {
        let rows = [
            theirs("tomorrow", due: Fixed.date(2026, 10, 22)),
            mine("today", due: Fixed.date(2026, 10, 21)),
            theirs("overdue", due: Fixed.date(2026, 10, 18)),
        ]
        let sections = GroupedOrdering.sections(rows, by: .date, groupOrder: [ListRowGroup](), now: now, calendar: cal,
                                                groupOf: \.group)
        XCTAssertEqual(sections.map(\.key), [.due(.overdue), .due(.today), .due(.tomorrow)])
    }
}
