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

// MARK: - Listing (brief 59)

/// George, 2026-11-07: the Flipboard is a visual aid for chores that repeat within an interval, not on a
/// date. A switch stays off the lists until it is due: green, it is on the Flipboard only; red, it is a
/// task for today, every day, until it is flipped. Every list (Inbox, Today, Upcoming, filters, search,
/// Siri) asks `listing(for:now:)`, so they all agree. A query that names `@flipboard` opts out
/// (`FilterQuery.namesFlipboard`): it sees switches as the tasks they are, so "switches" filters work.
extension FlipboardSwitch {
    public enum Listing: Sendable, Equatable {
        /// A green switch: on the Flipboard only.
        case hidden
        /// A red switch (due today, overdue or never flipped): listed as due today, never as overdue.
        case today
        /// Not a switch: listed by its own date.
        case unchanged
    }

    public static func listing<T: FilterableTask>(for task: T, now: Date, calendar: Calendar = .current) -> Listing {
        switch side(of: task, now: now, calendar: calendar) {
        case .green?: return .hidden
        case .red?: return .today
        case nil: return .unchanged
        }
    }

    /// The date a list files the task under: the start of today for a red switch, its own otherwise.
    public static func listedDueDate<T: FilterableTask>(for task: T, now: Date, calendar: Calendar = .current) -> Date? {
        listing(for: task, now: now, calendar: calendar) == .today ? calendar.startOfDay(for: now) : task.filterDueDate
    }

    /// The task as lists see it: a red switch due at the start of today, anything else as it is.
    public static func listed<T: FilterableTask>(_ task: T, now: Date, calendar: Calendar = .current) -> Listed<T> {
        Listed(base: task, filterDueDate: listedDueDate(for: task, now: now, calendar: calendar))
    }

    /// A task with the due date a list files it under (`listed(_:now:)`).
    public struct Listed<Base: FilterableTask>: FilterableTask {
        public let base: Base
        public let filterDueDate: Date?

        public var filterTitle: String { base.filterTitle }
        public var filterNotes: String { base.filterNotes }
        public var filterPriority: Int { base.filterPriority }
        public var filterHasDueTime: Bool { base.filterHasDueTime }
        public var filterIsCompleted: Bool { base.filterIsCompleted }
        public var filterProjectName: String? { base.filterProjectName }
        public var filterLabelNames: [String] { base.filterLabelNames }
        public var filterIsRecurring: Bool { base.filterIsRecurring }
        public var filterCreatedDate: Date? { base.filterCreatedDate }
        public var filterIsSubtask: Bool { base.filterIsSubtask }
    }
}
