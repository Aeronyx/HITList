import Foundation
import SwiftData
import HITListCore

/// The widgets' snapshot from the store (brief 74): every open top-level task that has a date (up to two months ahead,
/// `datedHorizonDays`) or is a Flipboard switch, yours and the shared ones, with what the rules need to judge it, plus the Switchboards. Undated tasks are
/// never in a widget, so they stay out. The Flipboard's order is the board's own (`Flipboard.sorted`,
/// `Flipboard.sorted(onBoard:)`), and each board's line is its header's (`SwitchboardDraft.cadenceLine`).
enum WidgetSnapshotBuilder {
    @MainActor
    static func build(from context: ModelContext, shared: [SharedRow], themeID: String, weekStart: Int,
                      now: Date = Date(), pending: [WidgetSnapshot.Pending] = [],
                      sync: WidgetSnapshot.Sync? = nil) throws -> WidgetSnapshot {
        let open = try context.fetch(widgetTasks(now: now))
        let switches = open.filter(Flipboard.isMember)
        let switchIDs = Set(switches.map(\.id))
        let boards = Flipboard.ordered(try context.fetch(FetchDescriptor<Switchboard>()))
        let boardIDs = Set(boards.map(\.id))

        var tasks = open.filter { $0.dueDate != nil || switchIDs.contains($0.id) }.map { task($0, weekStart: weekStart) }
        tasks += shared.filter { !$0.task.isCompleted && $0.filterDueDate != nil }.map(task)

        // As the Flipboard has them: on no board, or on one this device hasn't received yet.
        let loose = switches.filter { $0.switchboard.map { !boardIDs.contains($0.id) } ?? true }
        return WidgetSnapshot(
            writtenAt: now, themeID: themeID, weekStart: weekStart, tasks: tasks,
            looseSwitchIDs: Flipboard.sorted(loose).map(\.id),
            switchboards: boards.map { board in
                WidgetSnapshot.Switchboard(
                    id: board.id, name: board.name,
                    line: SwitchboardDraft.cadenceLine(cadence: board.cadenceValue, resetMinutes: board.resetMinutes,
                                                       resetWeekday: board.resetWeekday, weekStart: weekStart),
                    clock: WidgetSnapshot.Clock(board.schedule(weekStart: weekStart)),
                    switchIDs: Flipboard.sorted(onBoard: switches.filter { $0.switchboard?.id == board.id }, board).map(\.id))
            },
            // Brief 81: the widgets' taps the app is finishing, each row as the widget showed it, and the sync state.
            pending: pending, sync: sync)
    }

    /// How far ahead a dated task is kept (round 32, review 154's finding 5): Upcoming lists 31 days from the moment a
    /// widget draws, and a timeline is drawn from the snapshot until the app writes the next one (at least every six
    /// hours while it runs; days later when it doesn't). Two months covers a month of the app not running.
    static let datedHorizonDays = 62

    /// What a widget can show, fetched rather than filtered (review 154, finding 5: every save rebuilt the snapshot from
    /// every open task, about 0.3 s at 5,000): the open top-level tasks dated before the horizon (overdue ones too), and
    /// every repeating one, which is where the switches are (`Flipboard.isMember` needs a repeat), dated or not. An
    /// undated task that doesn't repeat is never in a widget, and is no longer read. Their labels come in the fetch.
    static func widgetTasks(now: Date, calendar: Calendar = .current) -> FetchDescriptor<TaskItem> {
        let horizon = calendar.date(byAdding: .day, value: datedHorizonDays, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(Double(datedHorizonDays) * 86_400)
        let never = Date.distantFuture
        // Two predicates, so neither takes the compiler long.
        let soon = #Predicate<TaskItem> { task in (task.dueDate ?? never) < horizon }
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            !task.isCompleted && task.parent == nil && (task.recurrence != nil || soon.evaluate(task))
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.labels]
        return descriptor
    }

    static func task(_ task: TaskItem, weekStart: Int) -> WidgetSnapshot.Task {
        WidgetSnapshot.Task(
            id: task.id, title: task.title, priority: task.priority, due: task.dueDate, hasTime: task.hasDueTime,
            groupName: task.project?.name, groupColorHex: task.project?.colorHex, labelNames: task.filterLabelNames,
            isRecurring: task.filterIsRecurring, createdAt: task.createdAt, isShared: false,
            switchOptedIn: task.filterSwitchOptedIn, switchboardID: task.switchboard?.id,
            clock: task.resetBoard.map { WidgetSnapshot.Clock($0.schedule(weekStart: weekStart)) })
    }

    /// A shared task (brief 62) in its forced Group, Shared Tasks (brief 64). It is never a switch.
    static func task(_ row: SharedRow) -> WidgetSnapshot.Task {
        WidgetSnapshot.Task(
            id: row.id, title: row.filterTitle, priority: row.filterPriority, due: row.filterDueDate,
            hasTime: row.filterHasDueTime, groupName: SharedTasksGroup.name, groupColorHex: SharedTasksGroup.colorHex,
            labelNames: [], isRecurring: false, createdAt: row.filterCreatedDate, isShared: true, switchOptedIn: false,
            switchboardID: nil, clock: nil)
    }
}
