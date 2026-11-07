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

/// The review card's horizontal swipe (brief 60), as a pure state machine the view feeds with the drag's
/// offset and, on release, its velocity. Right is Today, left is Delete. Past `threshold` the card is armed
/// (its stamp shows); letting go while armed commits it, and so does a quick flick after a short drag. A
/// flick back towards the middle, or letting go short of the threshold, springs it back.
public struct InboxReviewSwipe: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        /// Swipe right: due today.
        case today
        /// Swipe left: deleted (with the undo toast).
        case delete
    }

    public enum Phase: Equatable, Sendable {
        case none
        /// Past the threshold while dragging: letting go now commits.
        case armed(Direction)
        /// Let go: the card leaves in this direction. Later drags are ignored until `reset()`.
        case committed(Direction)
    }

    /// Points of horizontal drag that arm the card.
    public static let threshold: Double = 96
    /// Points per second that count as a flick.
    public static let flickVelocity: Double = 800
    /// The least drag a flick needs, so a tap that wobbles is never a swipe.
    public static let flickMinimum: Double = 24

    /// Horizontal points from the card's resting place; positive is right.
    public private(set) var offset: Double = 0
    public private(set) var phase: Phase = .none

    public init() {}

    /// The way the card leans, nil at rest.
    public var direction: Direction? {
        if case .committed(let d) = phase { return d }
        return Self.direction(of: offset)
    }

    /// 0 at rest, 1 at the threshold and beyond: how strong the edge glow is.
    public var progress: Double { min(1, abs(offset) / Self.threshold) }

    public var isCommitted: Bool {
        if case .committed = phase { return true }
        return false
    }

    public mutating func drag(to offset: Double) {
        guard !isCommitted else { return }
        self.offset = offset
        phase = abs(offset) >= Self.threshold ? Self.direction(of: offset).map(Phase.armed) ?? .none : .none
    }

    /// The finger lifts with `velocity` (points per second, positive is right). Returns the new phase:
    /// `.committed` when the card should leave, `.none` (offset back to 0) when it springs back.
    @discardableResult
    public mutating func release(velocity: Double) -> Phase {
        guard !isCommitted else { return phase }
        let lean = Self.direction(of: offset)
        let flick = Self.direction(of: abs(velocity) >= Self.flickVelocity ? velocity : 0)
        let commits: Direction? = switch (lean, flick) {
        case (nil, _): nil
        case (let lean?, let flick?) where flick != lean: nil   // flung back towards the middle
        case (let lean?, _?): abs(offset) >= Self.flickMinimum ? lean : nil
        case (let lean?, nil): abs(offset) >= Self.threshold ? lean : nil
        }
        if let commits {
            phase = .committed(commits)
        } else {
            phase = .none
            offset = 0
        }
        return phase
    }

    /// Back to rest, for the next card (or after a commit's action was refused).
    public mutating func reset() { self = InboxReviewSwipe() }

    private static func direction(of value: Double) -> Direction? {
        value > 0 ? .today : value < 0 ? .delete : nil
    }
}
