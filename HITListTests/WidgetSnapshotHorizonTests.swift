import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 32, brief 158 (review 154's finding 5): the widgets' snapshot fetches only what a widget can show (open
/// top-level tasks dated within two months, overdue ones too, and every repeating one, where the switches are) instead of
/// every open task. What each widget draws from it is what it drew from the whole store's snapshot, at every moment of a
/// timeline and for a month of the app not writing again.
@MainActor
final class WidgetSnapshotHorizonTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    /// The snapshot's tasks as they were before: every open top-level task with a date or that is a switch.
    private func wholeStoreTasks(weekStart: Int) throws -> [WidgetSnapshot.Task] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted }))
            .filter { !$0.isSubtask && ($0.dueDate != nil || Flipboard.isMember($0)) }
            .map { WidgetSnapshotBuilder.task($0, weekStart: weekStart) }
    }

    /// Upcoming as a widget draws it: the days and their tasks, and the dots of the week strip and of the month's grid
    /// (`UpcomingWidgetView`: a day outside the month shows none). `counts` itself holds every dated day.
    private func drawn(_ upcoming: WidgetContent.Upcoming, at moment: Date) -> WidgetContent.Upcoming {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: moment)!
        var drawn = upcoming
        drawn.counts = upcoming.counts.filter { day, _ in upcoming.week.contains(day) || month.contains(day) }
        return drawn
    }

    func testTheWidgetsDrawTheSameFromTheFetchedTasks() throws {
        let now = Date()
        try ListSamenessStore.fill(context, now: now)
        // Far ahead: a plain task (left out now) and a yearly switch (kept: it is on the Flipboard whatever its date).
        let far = Calendar.current.date(byAdding: .day, value: 200, to: now)!
        context.insert(TaskItem(title: "Far plain", dueDate: far))
        context.insert(TaskItem(title: "Far switch", dueDate: far, labels: [try Flipboard.label(in: context)],
                                recurrence: RecurrenceRule(frequency: .yearly)))
        try context.save()

        let weekStart = 2
        // A task's labels are a set: their order in the array is whatever the store's fetch gave, and differs between
        // two fetches of the same task (no widget draws them; the rules ask only whether one is `flipboard`).
        func labelsInOrder(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
            var sorted = snapshot
            sorted.tasks = snapshot.tasks.map { task in
                var task = task
                task.labelNames.sort()
                return task
            }
            return sorted
        }
        let fetched = labelsInOrder(try WidgetSnapshotBuilder.build(from: context, shared: [], themeID: "slate",
                                                                    weekStart: weekStart, now: now))
        var whole = fetched
        whole.tasks = try wholeStoreTasks(weekStart: weekStart)
        whole = labelsInOrder(whole)
        XCTAssertLessThan(fetched.tasks.count, whole.tasks.count, "the far plain task is no longer read")
        XCTAssertTrue(fetched.tasks.contains { $0.title == "Far switch" })
        XCTAssertFalse(fetched.tasks.contains { $0.title == "Far plain" })
        XCTAssertEqual(Set(fetched.tasks.map(\.id)).subtracting(whole.tasks.map(\.id)), [], "nothing new")

        // Every hour of a timeline, then each day of a month without a new snapshot.
        let moments = (0...36).map { now.addingTimeInterval(Double($0) * 3600) }
            + (2...31).map { now.addingTimeInterval(Double($0) * 86_400) }
        for moment in moments {
            XCTAssertEqual(WidgetContent.today(fetched, at: moment), WidgetContent.today(whole, at: moment), "\(moment)")
            XCTAssertEqual(drawn(WidgetContent.upcoming(fetched, at: moment), at: moment),
                           drawn(WidgetContent.upcoming(whole, at: moment), at: moment), "\(moment)")
            XCTAssertEqual(WidgetContent.flipboard(fetched, board: nil, at: moment),
                           WidgetContent.flipboard(whole, board: nil, at: moment), "\(moment)")
            for board in fetched.switchboards {
                XCTAssertEqual(WidgetContent.flipboard(fetched, board: board.id, at: moment),
                               WidgetContent.flipboard(whole, board: board.id, at: moment), "\(board.name) \(moment)")
            }
        }
        XCTAssertEqual(WidgetContent.changes(fetched, after: now), WidgetContent.changes(whole, after: now))
    }
}
