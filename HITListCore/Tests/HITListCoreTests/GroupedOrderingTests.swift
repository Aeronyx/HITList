import XCTest
@testable import HITListCore

/// Briefs 57 and 61: the Inbox sorted by Priority (flat), Group or Date, and Today by Priority or Group,
/// each section keeping `TaskOrdering`'s order (priority, then date).
final class GroupedOrderingTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func titles(_ tasks: [PlainTask]) -> [String] { tasks.map(\.filterTitle) }
    private func keys(_ sections: [ListSection<String, PlainTask>]) -> [ListSectionKey<String>] { sections.map(\.key) }
    private func sections(_ tasks: [PlainTask], by sort: ListSort, groupOrder: [String] = []) -> [ListSection<String, PlainTask>] {
        GroupedOrdering.sections(tasks, by: sort, groupOrder: groupOrder, now: now, calendar: cal)
    }

    // MARK: - Priority

    func testPriorityIsOneFlatSectionInTaskOrder() {
        let tasks = [
            PlainTask(title: "p4", priority: 4, projectName: "Work"),
            PlainTask(title: "p1 later", priority: 1, dueDate: Fixed.date(2026, 10, 25)),
            PlainTask(title: "p1 sooner", priority: 1, dueDate: Fixed.date(2026, 10, 22)),
        ]
        let sorted = sections(tasks, by: .priority, groupOrder: ["Work"])
        XCTAssertEqual(keys(sorted), [.all], "no section headers")
        XCTAssertEqual(titles(sorted[0].tasks), ["p1 sooner", "p1 later", "p4"])
    }

    func testNoTasksIsNoSections() {
        for sort in ListSort.allCases {
            XCTAssertTrue(sections([], by: sort, groupOrder: ["Work"]).isEmpty, "\(sort)")
        }
    }

    // MARK: - Group

    func testGroupsFollowTheSidebarOrderWithUngroupedLast() {
        let tasks = [
            PlainTask(title: "loose", priority: 1),
            PlainTask(title: "home", projectName: "Home"),
            PlainTask(title: "work", projectName: "Work"),
        ]
        let sorted = sections(tasks, by: .group, groupOrder: ["Work", "Errands", "Home"])
        XCTAssertEqual(keys(sorted), [.group("Work"), .group("Home"), .ungrouped], "empty Groups are left out")
    }

    func testEachGroupKeepsPriorityThenDueOrder() {
        let tasks = [
            PlainTask(title: "w undated p1", priority: 1, projectName: "Work"),
            PlainTask(title: "w tomorrow p4", priority: 4, dueDate: Fixed.date(2026, 10, 22), projectName: "Work"),
            PlainTask(title: "w today p1", priority: 1, dueDate: Fixed.date(2026, 10, 21), projectName: "Work"),
            PlainTask(title: "w today p2", priority: 2, dueDate: Fixed.date(2026, 10, 21), projectName: "Work"),
        ]
        let sorted = sections(tasks, by: .group, groupOrder: ["Work"])
        XCTAssertEqual(titles(sorted[0].tasks), ["w today p1", "w undated p1", "w today p2", "w tomorrow p4"])
    }

    func testAGroupMissingFromTheOrderComesAfterTheKnownOnesBeforeUngrouped() {
        // A Group that arrived by sync a moment before the view's own list of Groups did.
        let tasks = [
            PlainTask(title: "new", projectName: "Zeta"),
            PlainTask(title: "loose"),
            PlainTask(title: "known", projectName: "Work"),
            PlainTask(title: "also new", projectName: "Alpha"),
        ]
        let sorted = sections(tasks, by: .group, groupOrder: ["Work"])
        XCTAssertEqual(keys(sorted), [.group("Work"), .group("Alpha"), .group("Zeta"), .ungrouped])
    }

    func testGroupingByIDKeepsTwoGroupsWithTheSameNameApart() {
        let a = UUID(), b = UUID()
        let tasks = [(PlainTask(title: "one", projectName: "Home"), a), (PlainTask(title: "two", projectName: "Home"), b)]
        let sorted = GroupedOrdering.sections(tasks.map(\.0), by: .group, groupOrder: [b, a], now: now, calendar: cal) { task in
            tasks.first { $0.0.filterTitle == task.filterTitle }?.1
        }
        XCTAssertEqual(sorted.map(\.key), [.group(b), .group(a)])
        XCTAssertEqual(sorted.map { $0.tasks.map(\.filterTitle) }, [["two"], ["one"]])
    }

    func testOpenCountLeavesCompletedTasksOut() {
        let tasks = [
            PlainTask(title: "open", projectName: "Work"),
            PlainTask(title: "done", isCompleted: true, projectName: "Work"),
        ]
        let section = sections(tasks, by: .group, groupOrder: ["Work"])[0]
        XCTAssertEqual(section.tasks.count, 2)
        XCTAssertEqual(section.openCount, 1)
    }

    // MARK: - Date

    func testDateSectionsRunOverdueTodayTomorrowTheWeeksDaysLaterNoDate() {
        // Wednesday Oct 21: the next five days by name run Friday Oct 23 to Tuesday Oct 27.
        let tasks = [
            PlainTask(title: "undated"),
            PlainTask(title: "in a week", dueDate: Fixed.date(2026, 10, 28)),
            PlainTask(title: "tuesday", dueDate: Fixed.date(2026, 10, 27)),
            PlainTask(title: "friday", dueDate: Fixed.date(2026, 10, 23, 9), hasDueTime: true),
            PlainTask(title: "tomorrow", dueDate: Fixed.date(2026, 10, 22)),
            PlainTask(title: "this morning", dueDate: Fixed.date(2026, 10, 21, 8), hasDueTime: true),
            PlainTask(title: "last week", dueDate: Fixed.date(2026, 10, 14)),
            PlainTask(title: "next year", dueDate: Fixed.date(2027, 1, 5)),
        ]
        let sorted = sections(tasks, by: .date)
        XCTAssertEqual(keys(sorted), [
            .due(.overdue), .due(.today), .due(.tomorrow), .due(.day(Fixed.date(2026, 10, 23))),
            .due(.day(Fixed.date(2026, 10, 27))), .due(.later), .due(.noDate),
        ])
        XCTAssertEqual(sorted.map { titles($0.tasks) }, [
            ["last week"], ["this morning"], ["tomorrow"], ["friday"], ["tuesday"], ["in a week", "next year"], ["undated"],
        ])
    }

    func testEachDaySortsByPriorityThenTime() {
        let tasks = [
            PlainTask(title: "6pm p4", priority: 4, dueDate: Fixed.date(2026, 10, 21, 18), hasDueTime: true),
            PlainTask(title: "5pm p1", priority: 1, dueDate: Fixed.date(2026, 10, 21, 17), hasDueTime: true),
            PlainTask(title: "9am p4", priority: 4, dueDate: Fixed.date(2026, 10, 21, 9), hasDueTime: true),
            PlainTask(title: "6pm p1", priority: 1, dueDate: Fixed.date(2026, 10, 21, 18), hasDueTime: true),
        ]
        let sorted = sections(tasks, by: .date)
        XCTAssertEqual(keys(sorted), [.due(.today)])
        XCTAssertEqual(titles(sorted[0].tasks), ["5pm p1", "6pm p1", "9am p4", "6pm p4"])
    }

    func testAnOptedInRedFlipboardSwitchIsFiledUnderToday() {
        // A switch last flipped long ago, with "Overdue becomes task" on, is listed as today's, never as overdue
        // (briefs 59 and 72).
        let red = PlainTask(title: "water plants", dueDate: Fixed.date(2026, 10, 10),
                            labelNames: [FlipboardSwitch.labelName], isRecurring: true, switchOptedIn: true)
        let sorted = sections([red], by: .date)
        XCTAssertEqual(keys(sorted), [.due(.today)])
    }

    func testDueSectionsOrderThemselves() {
        let friday = DueSection.day(Fixed.date(2026, 10, 23)), monday = DueSection.day(Fixed.date(2026, 10, 26))
        XCTAssertEqual([DueSection.noDate, .later, monday, friday, .tomorrow, .today, .overdue].sorted(),
                       [.overdue, .today, .tomorrow, friday, monday, .later, .noDate])
        XCTAssertEqual(DueSection(due: Fixed.date(2026, 10, 27, 23, 59), now: now, calendar: cal), .day(Fixed.date(2026, 10, 27)))
        XCTAssertEqual(DueSection(due: Fixed.date(2026, 10, 28), now: now, calendar: cal), .later, "a week ahead is Later")
        XCTAssertEqual(DueSection(due: Fixed.date(2026, 10, 20, 23, 59), now: now, calendar: cal), .overdue)
        XCTAssertEqual(DueSection(due: nil, now: now, calendar: cal), .noDate)
    }

    // MARK: - Today

    func testTodayKeepsOverdueOnTopAndGroupsWithinItAndBelow() {
        let tasks = [
            PlainTask(title: "late work", dueDate: Fixed.date(2026, 10, 19), projectName: "Work"),
            PlainTask(title: "late loose", priority: 1, dueDate: Fixed.date(2026, 10, 20)),
            PlainTask(title: "today home", dueDate: Fixed.date(2026, 10, 21), projectName: "Home"),
            PlainTask(title: "today work", dueDate: Fixed.date(2026, 10, 21, 9), hasDueTime: true, projectName: "Work"),
            PlainTask(title: "tomorrow", dueDate: Fixed.date(2026, 10, 22), projectName: "Work"),
            PlainTask(title: "undated", projectName: "Work"),
        ]
        let today = GroupedOrdering.today(tasks, by: .group, groupOrder: ["Work", "Home"], now: now, calendar: cal)
        XCTAssertEqual(keys(today.overdue), [.group("Work"), .ungrouped])
        XCTAssertEqual(today.overdue.map { titles($0.tasks) }, [["late work"], ["late loose"]])
        XCTAssertEqual(keys(today.today), [.group("Work"), .group("Home")])
        XCTAssertEqual(today.today.map { titles($0.tasks) }, [["today work"], ["today home"]])
        XCTAssertFalse(today.isEmpty)
    }

    func testTodayByPriorityIsOneSectionPerHalf() {
        let tasks = [
            PlainTask(title: "late", dueDate: Fixed.date(2026, 10, 19), projectName: "Work"),
            PlainTask(title: "today p4", dueDate: Fixed.date(2026, 10, 21), projectName: "Home"),
            PlainTask(title: "today p1", priority: 1, dueDate: Fixed.date(2026, 10, 21)),
        ]
        let today = GroupedOrdering.today(tasks, by: .priority, groupOrder: ["Work", "Home"], now: now, calendar: cal)
        XCTAssertEqual(keys(today.overdue), [.all])
        XCTAssertEqual(today.today.map { titles($0.tasks) }, [["today p1", "today p4"]])
    }

    func testTodayTakesTheListsOwnSectionRuleAndOrder() {
        // The list decides which half a row is in (brief 59: a switch due again is a today task whatever its
        // date) and how each section sorts; sorting by Group only lays them out.
        let tasks = [
            PlainTask(title: "switch", dueDate: Fixed.date(2026, 10, 1), projectName: "Home"),
            PlainTask(title: "b late", dueDate: Fixed.date(2026, 10, 19), projectName: "Home"),
            PlainTask(title: "a late", dueDate: Fixed.date(2026, 10, 18), projectName: "Home"),
        ]
        let today = GroupedOrdering.today(tasks, by: .group, groupOrder: ["Home"], now: now, calendar: cal,
                                          sectionOf: { $0.filterTitle == "switch" ? .today : .overdue },
                                          order: { $0.sorted { $0.filterTitle > $1.filterTitle } },
                                          groupOf: \.filterProjectName)
        XCTAssertEqual(today.overdue.map { titles($0.tasks) }, [["b late", "a late"]])
        XCTAssertEqual(today.today.map { titles($0.tasks) }, [["switch"]])
    }

    func testTodayWithNothingDueIsEmpty() {
        let today = GroupedOrdering.today([PlainTask(title: "undated")], by: .group, groupOrder: [String](),
                                          now: now, calendar: cal)
        XCTAssertTrue(today.isEmpty)
        XCTAssertTrue(today.overdue.isEmpty)
        XCTAssertTrue(today.today.isEmpty)
    }

    // MARK: - Names

    func testSortTitlesAndWhichListOffersWhich() {
        XCTAssertEqual(ListSort.allCases.map(\.title), ["Priority", "Group", "Date"])
        XCTAssertEqual(ListSort.inbox, [.priority, .group, .date])
        XCTAssertEqual(ListSort.today, [.priority, .group], "Today's sections are already by date")
        XCTAssertEqual(ListSort(rawValue: "group"), .group, "stored by raw value: never rename")
        XCTAssertNil(ListSort(rawValue: "none"), "0.8.0's \"Group by: None\" is not a sort")
    }
}
