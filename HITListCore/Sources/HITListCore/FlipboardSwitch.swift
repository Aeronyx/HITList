import Foundation

/// The Flipboard's switch, judged from any `FilterableTask` (brief 59). A switch is not a model of its own:
/// it is an open recurring task that carries the `flipboard` label, with or without a time of day (brief 72 lets a
/// switch have one: "Take meds 21:00"). Green = done for now, red = due, overdue, or never flipped (no date yet).
///
/// A loose switch (on no Switchboard) is green while its due day is after today, red from that day on. A switch on a
/// Switchboard follows the board's clock instead (`SwitchboardSchedule`): its day starts at the board's reset time.
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

    /// An open recurring task with the label. A time of day no longer keeps a task off the board (brief 72).
    public static func isMember(isRecurring: Bool, isCompleted: Bool, labelNames: [String]) -> Bool {
        isRecurring && !isCompleted && hasLabel(labelNames)
    }

    public static func isMember<T: FilterableTask>(_ task: T) -> Bool {
        isMember(isRecurring: task.filterIsRecurring, isCompleted: task.filterIsCompleted, labelNames: task.filterLabelNames)
    }

    // MARK: - Sides

    /// A loose switch's side by its due day (a time on that day doesn't matter: red all of its day); a board's switch
    /// by its board day. A switch with no due date has never been flipped; it shows red until it is.
    public static func side(due: Date?, hasTime: Bool = false, board: SwitchboardSchedule? = nil, now: Date,
                            calendar: Calendar = .current) -> Side {
        if let board { return board.side(due: due, hasTime: hasTime, now: now, calendar: calendar) }
        guard let due else { return .red }
        return calendar.startOfDay(for: due) > calendar.startOfDay(for: now) ? .green : .red
    }

    /// A loose switch red and past its due day (not merely due today). Overdue LEDs pulse. A board's switches are
    /// never overdue by days (a board resets; see `isLate`).
    public static func isOverdue(due: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    /// Red and past its time today (or this board period), or a loose switch past its day: the Flipboard's quiet
    /// "late" (the breathing light). An untimed switch on a board is never late.
    public static func isLate(due: Date?, hasTime: Bool, board: SwitchboardSchedule? = nil, now: Date,
                              calendar: Calendar = .current) -> Bool {
        if let board { return board.isLate(due: due, hasTime: hasTime, now: now, calendar: calendar) }
        guard let due else { return false }
        if isOverdue(due: due, now: now, calendar: calendar) { return true }
        return hasTime && side(due: due, now: now, calendar: calendar) == .red && now >= due
    }

    /// Red and its moment has come (brief 72, rule 2): a switch without a time is due from the start of its day (a
    /// board's: from its reset), one with a time from that time. A never-flipped switch is due now.
    public static func isDueNow(due: Date?, hasTime: Bool, board: SwitchboardSchedule? = nil, now: Date,
                                calendar: Calendar = .current) -> Bool {
        if let board { return board.isDueNow(due: due, hasTime: hasTime, now: now, calendar: calendar) }
        guard let due else { return true }
        guard side(due: due, now: now, calendar: calendar) == .red else { return false }
        return !hasTime || isOverdue(due: due, now: now, calendar: calendar) || now >= due
    }

    /// The task's side, or nil when it isn't a switch.
    public static func side<T: FilterableTask>(of task: T, now: Date, calendar: Calendar = .current) -> Side? {
        guard isMember(task) else { return nil }
        return side(due: task.filterDueDate, hasTime: task.filterHasDueTime, board: task.filterSwitchboard,
                    now: now, calendar: calendar)
    }

    /// Whether the switch's moment has come (`isDueNow`); false for anything that isn't a switch.
    public static func isDueNow<T: FilterableTask>(_ task: T, now: Date, calendar: Calendar = .current) -> Bool {
        isMember(task) && isDueNow(due: task.filterDueDate, hasTime: task.filterHasDueTime, board: task.filterSwitchboard,
                                   now: now, calendar: calendar)
    }
}

// MARK: - Listing (briefs 59 and 72)

/// George, 2026-11-10 (brief 72): switches are routines first. "By default, switches should not become tasks when
/// overdue unless the user toggles that option on", so "looking at your Flipboard becomes more like a personal status
/// check without the stress of your real todolist". A switch is on the Flipboard only, green or red, in no list: not
/// Today, the Inbox, Upcoming, search, filters, the badge, the morning summary, the sidebar counts, Siri's lists or
/// Claude's. "Overdue becomes task" (on the switch or its Switchboard: `filterSwitchOptedIn`) brings it back as round
/// 13 listed every red switch: a task for today, never overdue, once, from the moment it is due.
///
/// Every list (Inbox, Today, Upcoming, filters, search, Siri) asks `listing(for:now:)`, so they all agree. A query
/// that names `@flipboard` opts out (`FilterQuery.namesFlipboard`): it sees every switch as the task it is, so
/// "switches" filters work.
extension FlipboardSwitch {
    public enum Listing: Sendable, Equatable {
        /// A switch: on the Flipboard only.
        case hidden
        /// An opted-in switch whose moment has come: listed as due today, never as overdue.
        case today
        /// Not a switch: listed by its own date.
        case unchanged
    }

    /// The rule from plain values (the notification plan's items, which are not `FilterableTask`s).
    public static func listing(isSwitch: Bool, optedIn: Bool, due: Date?, hasTime: Bool, board: SwitchboardSchedule?,
                               now: Date, calendar: Calendar = .current) -> Listing {
        guard isSwitch else { return .unchanged }
        guard optedIn, isDueNow(due: due, hasTime: hasTime, board: board, now: now, calendar: calendar) else { return .hidden }
        return .today
    }

    public static func listing<T: FilterableTask>(for task: T, now: Date, calendar: Calendar = .current) -> Listing {
        listing(isSwitch: isMember(task), optedIn: task.filterSwitchOptedIn, due: task.filterDueDate,
                hasTime: task.filterHasDueTime, board: task.filterSwitchboard, now: now, calendar: calendar)
    }

    /// The date a list files the task under: the start of today for a switch listed as today's, its own otherwise.
    public static func listedDueDate<T: FilterableTask>(for task: T, now: Date, calendar: Calendar = .current) -> Date? {
        listing(for: task, now: now, calendar: calendar) == .today ? calendar.startOfDay(for: now) : task.filterDueDate
    }

    /// The task as lists see it: a switch listed as today's is due at the start of today, without a time; anything
    /// else as it is.
    public static func listed<T: FilterableTask>(_ task: T, now: Date, calendar: Calendar = .current) -> Listed<T> {
        let today = listing(for: task, now: now, calendar: calendar) == .today
        return Listed(base: task, filterDueDate: today ? calendar.startOfDay(for: now) : task.filterDueDate,
                      filterHasDueTime: today ? false : task.filterHasDueTime, isListedToday: today)
    }

    /// A task with the due date a list files it under (`listed(_:now:)`).
    /// Judged again, a switch listed as today's stays today's: it reads as an opted-in loose switch due today.
    public struct Listed<Base: FilterableTask>: FilterableTask {
        public let base: Base
        public let filterDueDate: Date?
        public let filterHasDueTime: Bool
        let isListedToday: Bool

        public var filterTitle: String { base.filterTitle }
        public var filterNotes: String { base.filterNotes }
        public var filterPriority: Int { base.filterPriority }
        public var filterIsCompleted: Bool { base.filterIsCompleted }
        public var filterProjectName: String? { base.filterProjectName }
        public var filterLabelNames: [String] { base.filterLabelNames }
        public var filterIsRecurring: Bool { base.filterIsRecurring }
        public var filterCreatedDate: Date? { base.filterCreatedDate }
        public var filterIsSubtask: Bool { base.filterIsSubtask }
        public var filterSwitchOptedIn: Bool { isListedToday || base.filterSwitchOptedIn }
        public var filterSwitchboard: SwitchboardSchedule? { isListedToday ? nil : base.filterSwitchboard }
    }
}
