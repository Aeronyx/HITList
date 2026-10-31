import Foundation

/// The order Process mode steps through the inbox: oldest first, one task at a time. Skipping sends a
/// task to the back once; skipping it again drops it. Tasks that leave the inbox (moved to a project,
/// deleted, completed, here or on another device) drop out.
struct InboxProcessQueue: Equatable {
    /// Still to show, the current task first.
    private(set) var remaining: [UUID]
    /// Tasks already sent to the back once.
    private var skipped: Set<UUID> = []
    /// Tasks acted on, or dropped after a second skip.
    private(set) var finished = 0

    /// `tasks` in any order; ties on `createdAt` go by id so the order is the same every time.
    init(tasks: [(id: UUID, createdAt: Date)]) {
        remaining = tasks
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
            .map(\.id)
    }

    var current: UUID? { remaining.first }
    var isFinished: Bool { remaining.isEmpty }
    var total: Int { finished + remaining.count }

    /// 1-based. A skipped task waiting at the back already counts as passed, so the number never goes
    /// down and reaches `total` on the last task.
    var position: Int {
        let waiting = remaining.dropFirst().filter { skipped.contains($0) }.count
        return min(total, finished + waiting + 1)
    }

    /// "3 of 7".
    var progressText: String { InboxText.progress(position, of: total) }

    /// The current task was handled (scheduled, moved, labelled, deleted).
    mutating func advance() {
        guard !remaining.isEmpty else { return }
        remaining.removeFirst()
        finished += 1
    }

    /// The current task goes to the back the first time; the second time it is dropped.
    mutating func skip() {
        guard let id = remaining.first else { return }
        remaining.removeFirst()
        if skipped.contains(id) {
            finished += 1
        } else {
            skipped.insert(id)
            remaining.append(id)
        }
    }

    /// Drops every task that is no longer in the inbox.
    mutating func retain(_ inbox: Set<UUID>) {
        remaining.removeAll { !inbox.contains($0) }
    }

    /// Undo of the last `advance()`: `id` is the current task again.
    mutating func restore(_ id: UUID) {
        remaining.removeAll { $0 == id }
        remaining.insert(id, at: 0)
        finished = max(0, finished - 1)
    }
}

extension InboxProcessQueue {
    /// A queue over the open inbox tasks among `tasks`.
    init(inboxOf tasks: [TaskItem]) {
        self.init(tasks: tasks.filter(\.isInInbox).map { (id: $0.id, createdAt: $0.createdAt) })
    }

    /// Drops every task among `tasks` that is no longer an open inbox task, and any that is gone.
    mutating func retainInbox(of tasks: [TaskItem]) {
        retain(Set(tasks.filter(\.isInInbox).map(\.id)))
    }
}

extension TaskItem {
    /// Open and without a project: what the Inbox shows (its query is "no project").
    var isInInbox: Bool { project == nil && !isCompleted }
}
