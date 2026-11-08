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
/// The actions go through the shared store as `SharedListScreen`'s do: each change is stamped and sent to the others.
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
    var rows: [SharedRow] { Self.rows(in: store?.lists ?? []) }

    /// The open ones.
    var open: [SharedRow] { rows.filter { !$0.task.isCompleted } }

    /// The lists, in the order the Shared screen and the sidebar show them (by name): Sort by Group's order too.
    var lists: [SharedList] { store?.sortedLists ?? [] }

    func row(_ id: UUID) -> SharedRow? {
        for list in store?.lists ?? [] {
            if let task = list.task(id) { return SharedRow(task: task, list: list) }
        }
        return nil
    }

    func list(_ id: UUID) -> SharedList? { store?.list(id) }

    /// Whether `id` names a shared list (the Mac sidebar's rows select one).
    func isList(_ id: UUID) -> Bool { list(id) != nil }

    static func rows(in lists: [SharedList]) -> [SharedRow] {
        lists.flatMap { list in list.tasks.map { SharedRow(task: $0, list: list) } }
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

    /// A due date moved to `day`: its time of day kept when it has one, else all day.
    nonisolated static func due(movedTo day: Date, from old: SharedDue?, calendar: Calendar = .current) -> SharedDue {
        let start = calendar.startOfDay(for: day)
        guard let old, old.hasTime else { return SharedDue(date: start, hasTime: false) }
        let time = calendar.dateComponents([.hour, .minute], from: old.date)
        let moved = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: start) ?? start
        return SharedDue(date: moved, hasTime: true)
    }
}
