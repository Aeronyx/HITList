import Foundation

/// Review Inbox (brief 60): the Inbox as a brain dump. A task typed in with no date and no Group lands at the
/// bottom of the Inbox; the review goes through exactly those, one card at a time, so each gets a day, a
/// Group, or is deleted. Dated tasks and tasks in a Group already have a place and are never reviewed.
public enum InboxReview {
    /// An open, top-level task with no due date and no Group. Priority and labels do not count: only a date
    /// or a Group gives a task its place. Every such task is in the Inbox (`TaskOrdering.isInInbox`).
    public static func needsReview<T: FilterableTask>(_ task: T) -> Bool {
        !task.filterIsCompleted && !task.filterIsSubtask && task.filterDueDate == nil && task.filterProjectName == nil
    }

    /// How many of `tasks` need review, for the menu item ("Review 3 unsorted…").
    public static func count<T: FilterableTask>(_ tasks: [T]) -> Int {
        tasks.reduce(0) { $0 + (needsReview($1) ? 1 : 0) }
    }
}
