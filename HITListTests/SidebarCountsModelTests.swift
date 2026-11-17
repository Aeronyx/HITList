import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 32, brief 158 (review 154's finding 1): the sidebar's and Browse's counts are kept by one model, one fetch and
/// one loop after each save, instead of being worked out in each body from a query of every open task. Each count it
/// keeps is the one `SidebarCounts` gives for the same tasks, for the demo week and for a store with completed tasks,
/// sub-tasks, repeats and switches; and it counts again after a save, on its own.
@MainActor
final class SidebarCountsModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let noShared = SharedRows(store: { nil })

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
    }

    override func tearDown() async throws { container = nil }

    private func openTopLevel() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>()).filter { !$0.isCompleted && !$0.isSubtask }
    }

    /// Every count the model keeps against `SidebarCounts`' for the same tasks at `now`.
    private func assertSameAsTheRules(now: Date, file: StaticString = #filePath, line: UInt = #line) throws {
        let model = SidebarCountsModel()
        model.start(context, labels: true)
        model.recompute(now: now)
        let open = try openTopLevel()
        XCTAssertEqual(model.today, SidebarCounts.today(open, shared: noShared, now: now), "Today", file: file, line: line)
        XCTAssertEqual(model.inbox, SidebarCounts.inbox(open, shared: noShared, now: now), "Inbox", file: file, line: line)
        for project in try context.fetch(FetchDescriptor<Project>()) {
            XCTAssertEqual(model.group(project.id), SidebarCounts.group(open, id: project.id, now: now), project.name,
                           file: file, line: line)
        }
        for label in try context.fetch(FetchDescriptor<TaskLabel>()) {
            XCTAssertEqual(model.label(label.id), SidebarCounts.label(open, label, now: now), "@" + label.name,
                           file: file, line: line)
        }
    }

    func testTheDemoWeeksCountsAreTheRulesCounts() throws {
        let now = Date()
        TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: "HITList-158.store",
                                            now: now)
        XCTAssertGreaterThan(try openTopLevel().count, 10)
        try assertSameAsTheRules(now: now)
        // Later the same day, the next day and a week on: what moves with the clock moves the same way.
        for hours in [5.0, 26, 24 * 7 + 3] { try assertSameAsTheRules(now: now.addingTimeInterval(hours * 3600)) }
    }

    func testAMixedStoresCountsAreTheRulesCounts() throws {
        let now = Date()
        try ListSamenessStore.fill(context, now: now)
        try assertSameAsTheRules(now: now)
        for hours in [3.0, 30, 24 * 9] { try assertSameAsTheRules(now: now.addingTimeInterval(hours * 3600)) }
    }

    /// A save counts again by itself, after the debounce.
    func testASaveCountsAgain() async throws {
        let home = Project(name: "Home")
        context.insert(home)
        try context.save()
        let model = SidebarCountsModel()
        model.start(context)
        XCTAssertEqual(model.group(home.id), 0)
        context.insert(TaskItem(title: "fix the tap", dueDate: Calendar.current.startOfDay(for: Date()), project: home))
        try context.save()
        try await Task.sleep(for: SidebarCountsModel.delay + .milliseconds(200))
        XCTAssertEqual(model.group(home.id), 1)
        XCTAssertEqual(model.today, 1)
        XCTAssertEqual(model.inbox, 1)
    }
}

/// A store with what the demo week lacks, for the counts' and the lists' sameness tests: completed tasks (dated, undated,
/// repeating), sub-tasks under open and completed parents, repeats, timed tasks, opted-in switches on and off a board,
/// a Group whose name another Group shares, a Group named like a wildcard, and tasks with several labels.
@MainActor
enum ListSamenessStore {
    static func fill(_ context: ModelContext, now: Date) throws {
        TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: "HITList-158.store",
                                            now: now)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: today)!
            return hour.map { calendar.date(byAdding: .hour, value: $0, to: d)! } ?? d
        }
        let work = Project(name: "Errands")
        let twin = Project(name: "Errands")
        let star = Project(name: "Side*")
        let sideline = Project(name: "Sideline")
        for project in [work, twin, star, sideline] { context.insert(project) }
        let urgent = TaskLabel(name: "urgent")
        let later = TaskLabel(name: "later")
        context.insert(urgent); context.insert(later)
        let flipboard = try Flipboard.label(in: context)

        var tasks: [TaskItem] = []
        for i in 0..<60 {
            let due: Date? = i % 7 == 0 ? nil : day(i % 23 - 8, hour: i % 4 == 0 ? 8 + i % 12 : nil)
            let project: Project? = [nil, work, twin, star, sideline][i % 5]
            let labels: [TaskLabel] = i % 3 == 0 ? [urgent] : i % 3 == 1 ? [urgent, later] : []
            let task = TaskItem(title: "Mixed \(i % 17) \(i)", notes: i % 4 == 0 ? "note with words \(i)" : "",
                                priority: 1 + i % 4, dueDate: due, project: project, labels: labels,
                                recurrence: i % 6 == 0 ? RecurrenceRule(frequency: .weekly) : nil)
            task.hasDueTime = due != nil && i % 4 == 0
            task.createdAt = now.addingTimeInterval(Double(-i * 3_600))
            if i % 5 == 0 {
                task.isCompleted = true
                task.completedAt = now.addingTimeInterval(Double(-i * 600))
            }
            if i % 9 == 0 { task.reminderDate = now.addingTimeInterval(Double(i * 900)) }
            context.insert(task)
            tasks.append(task)
        }
        // Two tasks with the same moment and title: the lists' last tiebreak.
        let twinA = TaskItem(title: "Same", dueDate: day(0), project: work)
        let twinB = TaskItem(title: "Same", dueDate: day(0), project: work)
        twinB.createdAt = twinA.createdAt
        context.insert(twinA); context.insert(twinB)
        try context.save()

        // Sub-tasks, under an open and under a completed parent, one of them completed.
        _ = try TaskActions.addSubtask("Sub open", to: tasks[1], in: context)
        let done = try TaskActions.addSubtask("Sub done", to: tasks[2], in: context)
        done.isCompleted = true
        _ = try TaskActions.addSubtask("Sub of completed", to: tasks[5], in: context)

        // Switches: loose and opted in (red, overdue, timed today), on a daily board that opts in, one green.
        let board = Switchboard(name: "Mornings")
        board.cadence = "daily"
        board.resetMinutes = 4 * 60
        board.overdueBecomesTask = true
        context.insert(board)
        let loose = TaskItem(title: "Loose opted in", dueDate: day(-2), project: work, labels: [flipboard],
                             recurrence: RecurrenceRule(frequency: .daily))
        loose.overdueBecomesTask = true
        let timed = TaskItem(title: "Timed switch", dueDate: day(0, hour: 21), project: star, labels: [flipboard, urgent],
                             recurrence: RecurrenceRule(frequency: .daily))
        timed.hasDueTime = true
        timed.overdueBecomesTask = true
        let onBoard = TaskItem(title: "On the board", dueDate: day(-1), labels: [flipboard],
                               recurrence: RecurrenceRule(frequency: .daily))
        onBoard.switchboard = board
        let green = TaskItem(title: "Green switch", dueDate: day(3), project: sideline, labels: [flipboard],
                             recurrence: RecurrenceRule(frequency: .weekly))
        green.overdueBecomesTask = true
        let quiet = TaskItem(title: "Quiet switch", dueDate: day(-3), project: work, labels: [flipboard, later],
                             recurrence: RecurrenceRule(frequency: .weekly))
        for task in [loose, timed, onBoard, green, quiet] { context.insert(task) }
        try context.save()
    }
}
