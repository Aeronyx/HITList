import Foundation
import HITListCore

/// The order Review Inbox steps through the unsorted tasks (`InboxReview.needsReview`): oldest first, one
/// task at a time. Later leaves a task as it is and moves on. Tasks that stop needing review (given a date or a
/// Group, deleted, completed, here or on another device) drop out.
struct InboxProcessQueue: Equatable {
    /// Still to show, the current task first.
    private(set) var remaining: [UUID]
    /// Tasks acted on or put off with Later.
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

    /// 1-based; reaches `total` on the last task.
    var position: Int { min(total, finished + 1) }

    /// "3 of 7".
    var progressText: String { InboxText.progress(position, of: total) }

    /// The current task was handled (given today or a date, moved to a Group, deleted).
    mutating func advance() {
        guard !remaining.isEmpty else { return }
        remaining.removeFirst()
        finished += 1
    }

    /// Later: the current task stays in the Inbox as it is, and this review is done with it.
    mutating func later() { advance() }

    /// Drops every task that no longer needs review. The current one leaving (sorted in the editor, from its
    /// card) counts as reviewed; one further back leaving (sorted on another device) just shortens the review.
    mutating func retain(_ unsorted: Set<UUID>) {
        if let current, !unsorted.contains(current) { finished += 1 }
        remaining.removeAll { !unsorted.contains($0) }
    }

    /// Undo of the last `advance()`: `id` is the current task again.
    mutating func restore(_ id: UUID) {
        remaining.removeAll { $0 == id }
        remaining.insert(id, at: 0)
        finished = max(0, finished - 1)
    }
}

extension InboxProcessQueue {
    /// A queue over the tasks among `tasks` that need review (`InboxReview.needsReview`: no date, no Group).
    init(reviewOf tasks: [TaskItem]) {
        self.init(tasks: tasks.filter(\.needsReview).map { (id: $0.id, createdAt: $0.createdAt) })
    }

    /// Drops every task among `tasks` that no longer needs review (it got a date or a Group, was completed),
    /// and any that is gone.
    mutating func retainReview(of tasks: [TaskItem]) {
        retain(Set(tasks.filter(\.needsReview).map(\.id)))
    }
}

extension TaskItem {
    /// An open task the Inbox shows (`TaskOrdering.isInInbox`): it has a date, in any Group, or it has
    /// no Group. An undated task in a Group is a note and only shows in that Group.
    var isInInbox: Bool { !isCompleted && TaskOrdering.isInInbox(self) }

    /// An open task with no date and no Group, which Review Inbox goes through (`InboxReview`).
    var needsReview: Bool { InboxReview.needsReview(self) }
}
