import Foundation
import Observation
import HITListCore

/// The shared tasks your lists show (brief 62): every task of every shared list you are in (the ones you made and the
/// ones you joined), as rows, read from `SharedTasksCenter`'s store. Nothing while Shared Tasks is off (no store).
///
/// The rows are worked out from the store on every read, so a view that reads them is redrawn whenever the store
/// changes (a sync, a completion here or on another member's device): the store and the centre are observable, and
/// this reads through them. Completed tasks are rows too, for Show completed and for a completion still animating;
/// the lists' own rules leave them out otherwise.
///
/// The actions go through the shared store: each change is stamped and sent to the others.
@MainActor
@Observable
final class SharedRows {
    static let shared = SharedRows()

    @ObservationIgnored private let source: @MainActor () -> SharedTasksStore?

    init(store source: @escaping @MainActor () -> SharedTasksStore? = { SharedTasksCenter.shared.store }) {
        self.source = source
    }

    private var store: SharedTasksStore? { source() }

    /// Every task of every list, open and completed.
    var rows: [SharedRow] { Self.rows(in: store?.lists ?? [], me: store?.me) }

    /// The open ones.
    var open: [SharedRow] { rows.filter { !$0.task.isCompleted } }

    /// The shared lists underneath Shared Tasks (each a set of people), by name.
    var lists: [SharedList] { store?.sortedLists ?? [] }

    /// This account in the shared container, once known.
    var me: SharedMemberID? { store?.me }

    func row(_ id: UUID) -> SharedRow? {
        for list in store?.lists ?? [] {
            if let task = list.task(id) { return SharedRow(task: task, list: list, me: store?.me) }
        }
        return nil
    }

    func list(_ id: UUID) -> SharedList? { store?.list(id) }

    /// Each list's people are worked out once for all its rows.
    static func rows(in lists: [SharedList], me: SharedMemberID? = nil) -> [SharedRow] {
        lists.flatMap { list in
            let people = SharedPeople.others(in: list, me: me)
            return list.tasks.map { SharedRow(task: $0, list: list, people: people) }
        }
    }

    /// Starts Shared Tasks when its switch is on (the lists call it as they appear, so a launch straight into Today
    /// shows the shared tasks without a visit to the Shared screen first). Cheap; nothing when off.
    func start() { SharedTasksCenter.shared.startIfOn() }

    // MARK: - Actions

    enum Refusal: Error, Equatable, LocalizedError {
        /// The member's share is view-only.
        case cannotChange(list: String)
        /// The task or its list went (deleted or left on another device), or the store isn't running.
        case gone

        var errorDescription: String? {
            switch self {
            case .cannotChange(let list): "You can see “\(list)” but not change it."
            case .gone: "That task isn't here any more."
            }
        }
    }

    /// Completes the task (who: me, when: now) or reopens it.
    func setCompleted(_ completed: Bool, _ row: SharedRow) throws {
        try edit(row) { try $0.setCompleted(completed, task: row.id, in: row.listID) }
    }

    /// Moves the task to `day`, keeping its time of day (as `TaskActions.reschedule` does for yours); nil removes the
    /// date.
    func reschedule(_ row: SharedRow, to day: Date?, calendar: Calendar = .current) throws {
        let due = day.map { Self.due(movedTo: $0, from: row.task.due.value, calendar: calendar) }
        try edit(row) { try $0.setDue(due, task: row.id, in: row.listID) }
    }

    func setPriority(_ priority: Int, _ row: SharedRow) throws {
        try edit(row) { try $0.setPriority(priority, task: row.id, in: row.listID) }
    }

    func delete(_ row: SharedRow) throws {
        try edit(row) { try $0.deleteTask(row.id, in: row.listID) }
    }

    private func edit(_ row: SharedRow, _ change: (SharedTasksStore) throws -> Void) throws {
        guard let store, let list = store.list(row.listID), list.task(row.id) != nil else { throw Refusal.gone }
        guard SharedTasksPermissions.allows(.editTask, in: list) else { throw Refusal.cannotChange(list: row.listTitle) }
        do {
            try change(store)
        } catch SharedTasksStore.StoreError.noSuchTask, SharedTasksStore.StoreError.noSuchList {
            throw Refusal.gone
        } catch SharedTasksStore.StoreError.notAllowed {
            throw Refusal.cannotChange(list: row.listTitle)
        }
    }

    // MARK: - Dragged to another day

    /// Dragged task ids dropped on `day` (Upcoming's board, its day headers and week strip): each open shared task
    /// named there moves to that day, keeping its time of day, as `TaskRescheduling.drop` moves yours. Days before
    /// today take nothing (they are Overdue's), and a task already on `day` is left alone, so a card dropped back
    /// where it came from sends nothing. A task in a list that is view-only for you stays put, and `refusal` says so.
    @discardableResult
    func drop(_ payload: [String], on day: Date, now: Date, calendar: Calendar = .current) -> (moved: [SharedRow], refusal: String?) {
        let target = calendar.startOfDay(for: day)
        guard target >= calendar.startOfDay(for: now) else { return ([], nil) }
        let ids = Set(TaskRescheduling.taskIDs(in: payload))
        let named = rows.filter { row in
            guard ids.contains(row.id), !row.task.isCompleted else { return false }
            return row.filterDueDate.map { calendar.startOfDay(for: $0) } != target
        }
        var moved: [SharedRow] = []
        var refusal: String?
        for row in named {
            do {
                try reschedule(row, to: target, calendar: calendar)
                moved.append(row)
            } catch let refused as Refusal where refused != .gone {
                refusal = refused.localizedDescription
            } catch {}
        }
        return (moved, refusal)
    }

    // MARK: - Counts

    /// The shared tasks the Inbox shows (the dated open ones), for the sidebar's count beside it.
    func inboxCount(now: Date = Date()) -> Int {
        open.filter { TaskOrdering.isInInbox($0, now: now) }.count
    }

    /// The shared tasks Today shows (due today or overdue, open), for the sidebar's count beside it.
    func todayCount(now: Date = Date()) -> Int {
        open.filter { TaskOrdering.isInToday($0, now: now) }.count
    }

    /// The Shared Tasks Group's count: every open shared task, dated or not, as a Group's count counts them (brief 64).
    var openCount: Int { open.count }

    /// A due date moved to `day`: its time of day kept when it has one, else all day.
    nonisolated static func due(movedTo day: Date, from old: SharedDue?, calendar: Calendar = .current) -> SharedDue {
        let start = calendar.startOfDay(for: day)
        guard let old, old.hasTime else { return SharedDue(date: start, hasTime: false) }
        let time = calendar.dateComponents([.hour, .minute], from: old.date)
        let moved = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: start) ?? start
        return SharedDue(date: moved, hasTime: true)
    }
}
