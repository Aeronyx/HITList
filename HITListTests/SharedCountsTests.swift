import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 64, item 7: the sidebar's Today and Inbox counts, the app badge and the morning summary count shared tasks
/// exactly as Today shows them, and a red Flipboard switch as one of today's tasks, never as overdue (round 13's rule:
/// a red switch waits in Today as today's task until flipped). In-memory stores only.
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

    private func item(_ title: String, due: Date?, timed: Bool = false, isSwitch: Bool = false) -> NotificationPlan.Item {
        NotificationPlan.Item(id: UUID(), title: title, projectName: nil, priority: .p4, dueDate: due, hasDueTime: timed,
                              isCompleted: false, updatedAt: now, isSwitch: isSwitch)
    }

    // MARK: - Red switches: today's, never overdue

    func testARedSwitchIsOneOfTodaysTasksInTheBadge() {
        let tasks = [
            item("due today", due: day(0)),
            item("overdue", due: day(-2)),
            item("red switch, two days late", due: day(-2), isSwitch: true),
            item("red switch, never flipped", due: nil, isSwitch: true),
            item("green switch", due: day(3), isSwitch: true),
            item("tomorrow", due: day(1)),
        ]
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: tasks, now: now, calendar: calendar), 4)
    }

    func testTheMorningSummaryCountsARedSwitchAsTodaysNotOverdue() throws {
        let tasks = [
            item("Call Sam", due: day(1, hour: 11), timed: true),
            item("Report", due: day(-1)),
            item("Water the plants", due: day(-1), isSwitch: true),
            item("Bins", due: day(1), isSwitch: true),
        ]
        // Tomorrow 08:00: the plants' switch is still red (today's), the bins' turns red, the report is overdue.
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
        let greenSwitch = TaskItem(title: "filter", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: realToday),
                                   labels: [flipboard], recurrence: RecurrenceRule(frequency: .monthly))
        let later = TaskItem(title: "later", dueDate: Calendar.current.date(byAdding: .day, value: 3, to: realToday))
        for task in [dueToday, overdue, redSwitch, neverFlipped, greenSwitch, later] { context.insert(task) }
        try context.save()

        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        let list = try store.createList(title: "Shared Tasks")
        try store.addTask(to: list.id, title: "Oat milk", due: SharedDue(date: realToday, hasTime: false))
        let rows = SharedRows(store: { store })

        let open = try context.fetch(FetchDescriptor<TaskItem>()).filter { !$0.isCompleted }
        XCTAssertEqual(SidebarCounts.today(open, shared: rows, now: realNow), 5,
                       "due today, overdue, both red switches once each, and the shared task; not the green switch")
        XCTAssertEqual(SidebarCounts.inbox(open, shared: rows, now: realNow), open.filter(\.isInInbox).count + 1)
    }
}
