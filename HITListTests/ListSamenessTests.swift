import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 32, brief 158 (review 154's finding 2): the lists fetch their own tasks (a), hold their rows between bodies (b)
/// and group a Group's, a label's or a filter's rows by day without copying a section per row (c). What a list shows,
/// and in what order, must not change at all: each list's rules over its own fetch give exactly the rows they gave over
/// every task, for the demo week and for a store with completed tasks, sub-tasks, repeats and switches, at several
/// moments and with Show completed off and on; the day sections are the ones the old loop made; and the held rows are
/// let go when anything they came from changes.
@MainActor
final class ListSamenessTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    // MARK: - (a) each list's own fetch

    /// Every task, oldest first: what every list read before.
    private func everyTask() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// The tasks a list shows, by `TaskListView`'s rules (`matchedTasks`), from `tasks`.
    private func matched(_ selection: SidebarItem, query: String?, showCompleted: Bool, tasks: [TaskItem],
                         now: Date) throws -> [UUID] {
        switch selection {
        case .today:
            return tasks.filter { TaskOrdering.isInToday($0, now: now, includeCompleted: showCompleted) }.map(\.id)
        case .inbox:
            return TaskOrdering.inbox(tasks, includeCompleted: showCompleted, now: now).map(\.id)
        default:
            var source = query ?? "all"
            if showCompleted, selection != .completed { source = "(\(source)) & (completed | !completed)" }
            return try FilterQuery(source, now: now).apply(to: tasks, now: now).map(\.id)
        }
    }

    /// Every list a sidebar shows, with the query behind it (`TaskListView.queryString`), and saved filters of every kind,
    /// those that name completion among them.
    private func lists() throws -> [(SidebarItem, String?)] {
        var lists: [(SidebarItem, String?)] = [(.today, nil), (.inbox, nil), (.upcoming, "due after: today"),
                                               (.completed, "completed")]
        for project in try context.fetch(FetchDescriptor<Project>()) {
            lists.append((.project(project.id), "#\"\(project.name)\""))
        }
        for label in try context.fetch(FetchDescriptor<TaskLabel>()) {
            lists.append((.label(label.id), "@\"\(label.name)\""))
        }
        for query in ["all", "p1", "completed", "!completed", "completed & #Errands", "overdue | today", "@urgent & p2",
                      "#Side*", "#Errands", "no date", "@flipboard", "recurring", "7 days", "search: words",
                      "due before: +4 hours"] {
            lists.append((.filter(UUID()), query))
        }
        return lists
    }

    private func assertEachListShowsTheSame(at moments: [Date], file: StaticString = #filePath,
                                            line: UInt = #line) throws {
        let every = try everyTask()
        for (selection, query) in try lists() {
            for showCompleted in [false, true] {
                for now in moments {
                    // Today's query reaches from the day it was built on: built at `now`, and a day before it (a list
                    // whose moment moved past midnight before its query was built again).
                    for built in [now, now.addingTimeInterval(-86_400)] {
                    let own = try context.fetch(TaskListView.tasks(for: selection, showCompleted: showCompleted,
                                                                   today: built))
                    XCTAssertLessThanOrEqual(own.count, every.count)
                    let before = try? matched(selection, query: query, showCompleted: showCompleted, tasks: every, now: now)
                    let after = try? matched(selection, query: query, showCompleted: showCompleted, tasks: own, now: now)
                    XCTAssertNotNil(before, "\(selection) \(query ?? "")", file: file, line: line)
                    XCTAssertEqual(before, after, "\(selection) \(query ?? "") completed \(showCompleted) at \(now)",
                                   file: file, line: line)
                    }
                }
            }
        }
    }

    func testEachListShowsTheSameRowsForTheDemoWeek() throws {
        let now = Date()
        TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: "HITList-158.store",
                                            now: now)
        try assertEachListShowsTheSame(at: [now, now.addingTimeInterval(5 * 3600), now.addingTimeInterval(30 * 3600)])
    }

    func testEachListShowsTheSameRowsForAMixedStore() throws {
        let now = Date()
        try ListSamenessStore.fill(context, now: now)
        XCTAssertTrue(try everyTask().contains { $0.isCompleted }, "the store has completed tasks")
        XCTAssertTrue(try everyTask().contains { $0.isSubtask }, "and sub-tasks")
        try assertEachListShowsTheSame(at: [now, now.addingTimeInterval(4 * 3600), now.addingTimeInterval(26 * 3600),
                                            now.addingTimeInterval(8 * 86_400)])
    }

    /// Upcoming from its open tasks: the same overdue, days, dots and board columns as from every task.
    func testUpcomingShowsTheSameFromItsOpenTasks() throws {
        let now = Date()
        try ListSamenessStore.fill(context, now: now)
        let every = try everyTask()
        let open = try context.fetch(UpcomingView.openTasks)
        XCTAssertLessThan(open.count, every.count)
        func entries(_ tasks: [TaskItem]) -> [TaskListRow] {
            tasks.map { TaskListRow(task: $0, filterDueDate: $0.dueDate, filterIsCompleted: $0.isCompleted) }
        }
        for moment in [now, now.addingTimeInterval(5 * 3600), now.addingTimeInterval(3 * 86_400)] {
            for dayCount in [14, 30, 60] {
                let before = UpcomingSchedule(items: entries(every), now: moment, dayCount: dayCount)
                let after = UpcomingSchedule(items: entries(open), now: moment, dayCount: dayCount)
                XCTAssertEqual(after.overdue.map(\.id), before.overdue.map(\.id))
                XCTAssertEqual(after.days.map(\.date), before.days.map(\.date))
                XCTAssertEqual(after.days.map { $0.items.map(\.id) }, before.days.map { $0.items.map(\.id) })
                XCTAssertFalse(before.days.allSatisfy(\.items.isEmpty))
            }
            XCTAssertEqual(UpcomingSchedule.counts(of: entries(open), now: moment),
                           UpcomingSchedule.counts(of: entries(every), now: moment))
            for days in [0, 7, 9] {
                var window = UpcomingWindow()
                window.move(by: days)
                for overdue in [false, true] {
                    let before = UpcomingBoardModel(items: entries(every), window: window, now: moment, showOverdue: overdue)
                    let after = UpcomingBoardModel(items: entries(open), window: window, now: moment, showOverdue: overdue)
                    XCTAssertEqual(after.columns.map(\.id), before.columns.map(\.id))
                    XCTAssertEqual(after.columns.map { $0.items.map(\.id) }, before.columns.map { $0.items.map(\.id) })
                }
            }
        }
    }

    /// The tasks a completion holds come back in the order every list's query lists them, completed or not.
    func testHeldTasksComeInTheQuerysOrder() throws {
        try ListSamenessStore.fill(context, now: Date())
        let every = try everyTask().filter { !$0.isSubtask }
        let ids = Set(every.enumerated().filter { $0.offset % 3 == 0 }.map(\.element.id))
        XCTAssertTrue(every.contains { ids.contains($0.id) && $0.isCompleted })
        XCTAssertEqual(context.heldTasks(ids).map(\.id), every.filter { ids.contains($0.id) }.map(\.id))
        XCTAssertEqual(context.heldTasks([UUID]()), [])
        XCTAssertEqual(context.storedTask(every[4].id)?.id, every[4].id)
    }

    // MARK: - (c) the day sections

    /// The loop the lists had: the section searched for by its title and copied with each row.
    private func oldDaySections(_ rows: [TaskListRow], now: Date) -> [(String, Date?, [UUID])] {
        var groups: [(id: String, due: Date?, rows: [TaskListRow])] = []
        for row in rows {
            let due = FlipboardSwitch.listedDueDate(for: row, now: now)
            let key = DueFormatter.sectionTitle(for: due, now: now, style: .dated)
            if let i = groups.firstIndex(where: { $0.id == key }) {
                groups[i] = (key, groups[i].due, groups[i].rows + [row])
            } else {
                groups.append((key, due, [row]))
            }
        }
        return groups.map { ($0.id, $0.due, $0.rows.map(\.id)) }
    }

    func testTheDaySectionsAreTheOldLoops() throws {
        let now = Date()
        try ListSamenessStore.fill(context, now: now)
        let every = try everyTask()
        for query in ["all", "(all) & (completed | !completed)", "#Errands", "@urgent", "@flipboard", "no date"] {
            for moment in [now, now.addingTimeInterval(30 * 3600)] {
                let rows = ListRows.rows(own: try FilterQuery(query, now: moment).apply(to: every, now: moment), shared: [SharedRow]())
                let new = TaskListView.daySections(rows, now: moment).map { ($0.title, $0.firstDue, $0.rows.map(\.id)) }
                let old = oldDaySections(rows, now: moment)
                XCTAssertEqual(new.map { $0.0 }, old.map { $0.0 }, query)
                XCTAssertEqual(new.map { $0.1 }, old.map { $0.1 }, query)
                XCTAssertEqual(new.map { $0.2 }, old.map { $0.2 }, query)
                if query != "no date" { XCTAssertGreaterThan(new.count, 1, "\(query): several days") }
            }
        }
    }

    // MARK: - (b) the held rows

    /// Lets the main queue deliver what was posted to it.
    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func testHeldRowsAreWorkedOutOnceForTheSameInputs() throws {
        let task = TaskItem(title: "one")
        context.insert(task)
        try context.save()
        let cache = ListCache<Int, String>()
        var runs = 0
        let compute = { () -> String in runs += 1; return task.title }
        XCTAssertEqual(cache.value(key: 1, sources: [ListSources.of([task])], compute: compute), "one")
        XCTAssertEqual(cache.value(key: 1, sources: [ListSources.of([task])], compute: compute), "one")
        XCTAssertEqual(runs, 1, "an animation's step: the same rows")
        _ = cache.value(key: 2, sources: [ListSources.of([task])], compute: compute)
        XCTAssertEqual(runs, 2, "a new moment, option or held row: worked out again")
        let other = TaskItem(title: "two")
        context.insert(other)
        _ = cache.value(key: 2, sources: [ListSources.of([task, other])], compute: compute)
        XCTAssertEqual(runs, 3, "a task more in the query")
    }

    func testAChangeToAnythingTheRowsReadLetsThemGo() throws {
        let task = TaskItem(title: "one")
        context.insert(task)
        try context.save()
        let cache = ListCache<Int, String>()
        let sources = [ListSources.of([task])]
        XCTAssertEqual(cache.value(key: 1, sources: sources) { task.title }, "one")
        let version = cache.version
        task.title = "changed, not saved"
        XCTAssertNotEqual(cache.version, version, "the body is told")
        XCTAssertEqual(cache.value(key: 1, sources: sources) { task.title }, "changed, not saved")
        // A property the rows never read does not.
        let read = cache.version
        task.notes = "unread"
        XCTAssertEqual(cache.version, read)
    }

    func testASaveElsewhereOrAnImportLetsTheRowsGo() throws {
        let task = TaskItem(title: "one")
        context.insert(task)
        try context.save()
        let cache = ListCache<Int, Int>()
        cache.watch(context)
        let sources = [ListSources.of([task])]
        _ = cache.value(key: 1, sources: sources) { 1 }
        var version = cache.version

        let elsewhere = ModelContext(container)
        elsewhere.insert(TaskItem(title: "from the engine"))
        try elsewhere.save()
        spin()
        XCTAssertNotEqual(cache.version, version, "another context's save")

        _ = cache.value(key: 1, sources: sources) { 1 }
        version = cache.version
        NotificationCenter.default.post(name: .cloudKitImportSucceeded, object: nil)
        spin()
        XCTAssertNotEqual(cache.version, version, "an import")

        _ = cache.value(key: 1, sources: sources) { 1 }
        version = cache.version
        try context.save()
        spin()
        XCTAssertEqual(cache.version, version, "the main context's own save: its changes were heard as they were made")
        XCTAssertEqual(cache.computations, 3)
    }
}
