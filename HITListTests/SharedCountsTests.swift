import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 64, item 7: the sidebar's Today and Inbox counts, the app badge and the morning summary count shared tasks
/// exactly as Today shows them. A Flipboard switch counts for none of them (brief 72: a switch is never a task by
/// default), unless it opted in ("Overdue becomes task"): then as one of today's tasks once due, never as overdue.
/// In-memory stores only.
@MainActor
final class SharedCountsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Wednesday 2026-10-28 09:00 in New York.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9))!
    private var today: Date { calendar.startOfDay(for: now) }
    private func day(_ offset: Int, hour: Int? = nil) -> Date {
        let d = calendar.date(byAdding: .day, value: offset, to: today)!
        return hour.map { calendar.date(byAdding: .hour, value: $0, to: d)! } ?? d
    }

    private func item(_ title: String, due: Date?, timed: Bool = false, isSwitch: Bool = false,
                      optedIn: Bool = false, board: SwitchboardSchedule? = nil) -> NotificationPlan.Item {
        NotificationPlan.Item(id: UUID(), title: title, projectName: nil, priority: .p4, dueDate: due, hasDueTime: timed,
                              isCompleted: false, updatedAt: now, isSwitch: isSwitch, switchOptedIn: optedIn, switchboard: board)
    }

    // MARK: - Switches: none of today's by default; opted in, today's once due, never overdue

    func testNoSwitchIsInTheBadgeByDefault() {
        let tasks = [
            item("due today", due: day(0)),
            item("overdue", due: day(-2)),
            item("red switch, two days late", due: day(-2), isSwitch: true),
            item("red switch, never flipped", due: nil, isSwitch: true),
            item("green switch", due: day(3), isSwitch: true),
            item("tomorrow", due: day(1)),
        ]
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: tasks, now: now, calendar: calendar), 2)
    }

    func testAnOptedInRedSwitchIsOneOfTodaysTasksInTheBadge() {
        let tasks = [
            item("due today", due: day(0)),
            item("overdue", due: day(-2)),
            item("red switch, two days late", due: day(-2), isSwitch: true, optedIn: true),
            item("red switch, never flipped", due: nil, isSwitch: true, optedIn: true),
            item("green switch", due: day(3), isSwitch: true, optedIn: true),
            item("timed switch, due tonight", due: day(0, hour: 21), timed: true, isSwitch: true, optedIn: true),
            item("tomorrow", due: day(1)),
        ]
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: tasks, now: now, calendar: calendar), 4,
                       "the timed one counts from 21:00, not at 09:00")
    }

    func testABoardsSwitchCountsFromTheBoardsReset() {
        // A daily board resetting at 04:00; flipped yesterday, so due on today's board day.
        let board = SwitchboardSchedule(cadence: .daily)
        let floss = item("Floss", due: day(0), isSwitch: true, optedIn: true, board: board)
        let three = calendar.date(byAdding: .hour, value: 3, to: today)!
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: [floss], now: three, calendar: calendar), 0, "03:00: still yesterday's")
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: [floss], now: now, calendar: calendar), 1)
    }

    func testTheMorningSummaryCountsAnOptedInSwitchAsTodaysNotOverdue() throws {
        let tasks = [
            item("Call Sam", due: day(1, hour: 11), timed: true),
            item("Report", due: day(-1)),
            item("Water the plants", due: day(-1), isSwitch: true, optedIn: true),
            item("Bins", due: day(1), isSwitch: true, optedIn: true),
            item("Stretch", due: day(-1), isSwitch: true),
        ]
        // Tomorrow 08:00: the plants' switch is still red (today's), the bins' turns red, the report is overdue; the
        // stretch switch never opted in, so it is on the Flipboard only.
        let summary = try XCTUnwrap(NotificationPlan.summaryRequest(tasks: tasks, at: 8 * 60, now: now, calendar: calendar,
                                                                    locale: Locale(identifier: "en_US")))
        XCTAssertTrue(summary.body.hasPrefix("3 tasks today, 1 overdue"), summary.body)
    }

    // MARK: - Shared tasks, as Today shows them

    private let me = "_me000000000000000000000000000000"

    private func sharedRows() throws -> SharedRows {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        let list = try store.createList(title: "Shared Tasks")
        try store.addTask(to: list.id, title: "Oat milk", priority: 2, due: SharedDue(date: day(0), hasTime: false))
        try store.addTask(to: list.id, title: "Cabin", due: SharedDue(date: day(-3), hasTime: false))
        try store.addTask(to: list.id, title: "Tent", due: SharedDue(date: day(4), hasTime: false))
        try store.addTask(to: list.id, title: "Someday")
        let done = try store.addTask(to: list.id, title: "Bread", due: SharedDue(date: day(0), hasTime: false))
        try store.setCompleted(true, task: done.id, in: list.id)
        return SharedRows(store: { store })
    }

    func testSharedTasksJoinTheBadgeAndTheSummaryAsTodayShowsThem() throws {
        let rows = try sharedRows()
        let counted = NotificationPlan.todayItems(own: [item("mine", due: day(0))], shared: rows.open)
        XCTAssertEqual(Set(counted.map(\.title)), ["mine", "Oat milk", "Cabin", "Tent"], "the open dated ones; Someday has no date")
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: counted, now: now, calendar: calendar), 3)
        let shared = try XCTUnwrap(counted.first { $0.title == "Oat milk" })
        XCTAssertEqual(shared.projectName, "Shared Tasks")
        XCTAssertEqual(shared.priority, .p2)
        XCTAssertFalse(shared.isSwitch)
        XCTAssertNil(shared.reminderDate, "a shared task never reminds")
    }

    func testOwnTasksWithoutADateCountOnlyAsSwitches() {
        let counted = NotificationPlan.todayItems(own: [item("undated", due: nil), item("never flipped", due: nil, isSwitch: true)],
                                                  shared: [])
        XCTAssertEqual(counted.map(\.title), ["never flipped"])
    }

    // MARK: - The sidebar

    func testTheSidebarsTodayCountIsTodaysRowsYoursAndShared() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let realNow = Date()
        let realToday = Calendar.current.startOfDay(for: realNow)
        let dueToday = TaskItem(title: "due today", dueDate: realToday)
        let overdue = TaskItem(title: "overdue", dueDate: Calendar.current.date(byAdding: .day, value: -2, to: realToday))
        let flipboard = TaskLabel(name: "flipboard")
        context.insert(flipboard)
        let redSwitch = TaskItem(title: "plants", dueDate: Calendar.current.date(byAdding: .day, value: -2, to: realToday),
                                 labels: [flipboard], recurrence: RecurrenceRule(frequency: .weekly))
        let neverFlipped = TaskItem(title: "bins", labels: [flipboard], recurrence: RecurrenceRule(frequency: .weekly))
        let quiet = TaskItem(title: "stretch", dueDate: Calendar.current.date(byAdding: .day, value: -2, to: realToday),
                             labels: [flipboard], recurrence: RecurrenceRule(frequency: .weekly))
        // Brief 72: only switches with "Overdue becomes task" count, one through its Switchboard.
        redSwitch.overdueBecomesTask = true
        let board = Switchboard(name: "Chores")
        board.overdueBecomesTask = true
        context.insert(board)
        neverFlipped.switchboard = board
        let greenSwitch = TaskItem(title: "filter", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: realToday),
                                   labels: [flipboard], recurrence: RecurrenceRule(frequency: .monthly))
        let later = TaskItem(title: "later", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: realToday))
        for task in [dueToday, overdue, redSwitch, neverFlipped, quiet, greenSwitch, later] { context.insert(task) }
        try context.save()

        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        let list = try store.createList(title: "Shared Tasks")
        try store.addTask(to: list.id, title: "Oat milk", due: SharedDue(date: realToday, hasTime: false))
        let rows = SharedRows(store: { store })

        let open = try context.fetch(FetchDescriptor<TaskItem>()).filter { !$0.isCompleted }
        XCTAssertEqual(SidebarCounts.today(open, shared: rows, now: realNow), 5,
                       "due today, overdue, both opted-in red switches once each, and the shared task; not the green switch, nor the one that didn't opt in")
        XCTAssertEqual(SidebarCounts.inbox(open, shared: rows, now: realNow), open.filter(\.isInInbox).count + 1)
    }

    /// A Group's and a label's count are the rows their screens list (round 16): a switch counts only once it is
    /// opted in and due; the `flipboard` label's own count is every switch.
    func testGroupAndLabelCountsLeaveOutSwitchesThatAreNotListed() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let realNow = Date()
        let realToday = Calendar.current.startOfDay(for: realNow)
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: realToday)
        let home = Project(name: "Home")
        let flipboard = TaskLabel(name: "flipboard")
        let chores = TaskLabel(name: "chores")
        context.insert(home); context.insert(flipboard); context.insert(chores)
        let task = TaskItem(title: "fix the tap", project: home, labels: [chores])
        let quiet = TaskItem(title: "stretch", dueDate: twoDaysAgo, project: home, labels: [flipboard, chores],
                             recurrence: RecurrenceRule(frequency: .weekly))
        let optedIn = TaskItem(title: "plants", dueDate: twoDaysAgo, project: home, labels: [flipboard, chores],
                               recurrence: RecurrenceRule(frequency: .weekly))
        optedIn.overdueBecomesTask = true
        let green = TaskItem(title: "filter", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: realToday),
                             project: home, labels: [flipboard, chores], recurrence: RecurrenceRule(frequency: .monthly))
        green.overdueBecomesTask = true
        for item in [task, quiet, optedIn, green] { context.insert(item) }
        try context.save()

        let open = try context.fetch(FetchDescriptor<TaskItem>()).filter { !$0.isCompleted }
        XCTAssertEqual(SidebarCounts.group(open, id: home.id, now: realNow), 2, "the task and the opted-in red switch")
        XCTAssertEqual(SidebarCounts.label(open, chores, now: realNow), 2)
        XCTAssertEqual(SidebarCounts.label(open, flipboard, now: realNow), 3, "the flipboard label counts every switch")
    }
}
