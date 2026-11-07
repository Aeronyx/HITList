import Foundation

/// The Flipboard's switch, judged from any `FilterableTask` (brief 59). A switch is not a model of its own:
/// it is an open recurring task without a time of day that carries the `flipboard` label. Green = due
/// after today (done for now), red = due today, overdue, or never flipped (no date yet).
///
/// The app's `Flipboard` (Views/Flipboard/FlipboardRules.swift) keeps the flipping and charging rules and
/// calls these for membership and sides, so the board and every list judge a task the same way.
public enum FlipboardSwitch {
    /// The label that makes a recurring task a switch.
    public static let labelName = "flipboard"

    public enum Side: Sendable, Equatable { case green, red }

    // MARK: - Membership

    /// Whether `labelNames` holds the `flipboard` label, in any case.
    public static func hasLabel(_ labelNames: [String]) -> Bool {
        labelNames.contains { $0.caseInsensitiveCompare(labelName) == .orderedSame }
    }

    public static func isMember(isRecurring: Bool, hasDueTime: Bool, isCompleted: Bool, labelNames: [String]) -> Bool {
        isRecurring && !hasDueTime && !isCompleted && hasLabel(labelNames)
    }

    public static func isMember<T: FilterableTask>(_ task: T) -> Bool {
        isMember(isRecurring: task.filterIsRecurring, hasDueTime: task.filterHasDueTime,
                 isCompleted: task.filterIsCompleted, labelNames: task.filterLabelNames)
    }

    // MARK: - Sides

    /// A switch with no due date has never been flipped; it shows red until it is.
    public static func side(due: Date?, now: Date, calendar: Calendar = .current) -> Side {
        guard let due else { return .red }
        return calendar.startOfDay(for: due) > calendar.startOfDay(for: now) ? .green : .red
    }

    /// Red and past its due day (not merely due today). Overdue LEDs pulse.
    public static func isOverdue(due: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    /// The task's side, or nil when it isn't a switch.
    public static func side<T: FilterableTask>(of task: T, now: Date, calendar: Calendar = .current) -> Side? {
        guard isMember(task) else { return nil }
        return side(due: task.filterDueDate, now: now, calendar: calendar)
    }
}
