import Foundation

/// What each widget shows at a moment (brief 74), worked out from the app's snapshot by the rules the app's own screens
/// use, never a copy of them: Today by `TaskOrdering.today`, Upcoming by `UpcomingDays`, the Flipboard by
/// `FlipboardSwitch` and `SwitchboardSchedule`. Pure, so a widget's timeline can ask for any moment ahead.
public enum WidgetContent {
    public typealias Task = WidgetSnapshot.Task

    // MARK: - Today

    /// Today's screen: Overdue, then today, each in the list's order.
    public struct Today: Equatable, Sendable {
        public var overdue: [Task]
        public var today: [Task]

        /// "Today" and its count: the sidebar's count (`SidebarCounts.today`), overdue included.
        public var count: Int { overdue.count + today.count }
        /// Every row in the screen's order.
        public var rows: [Task] { overdue + today }
        public var isEmpty: Bool { overdue.isEmpty && today.isEmpty }
    }

    public static func today(_ snapshot: WidgetSnapshot, at now: Date, calendar: Calendar = .current) -> Today {
        let list = TaskOrdering.today(snapshot.tasks, now: now, calendar: calendar)
        return Today(overdue: list.overdue, today: list.today)
    }

    // MARK: - Upcoming

    /// A little calendar and the next tasks.
    public struct Upcoming: Equatable, Sendable {
        public struct Day: Equatable, Sendable {
            /// The start of the day.
            public var date: Date
            public var tasks: [Task]
        }

        /// The start of today.
        public var today: Date
        /// The seven days of this week, from the week start in Settings.
        public var week: [Date]
        /// Scheduled tasks per day (each a start of day), for the dots.
        public var counts: [Date: Int]
        /// From today on, the days that have tasks (up to the horizon), each in Today's order.
        public var days: [Day]
        /// The week start, for a month grid.
        public var weekStart: Int
    }

    /// How far ahead Upcoming lists tasks.
    public static let upcomingDays = 31

    public static func upcoming(_ snapshot: WidgetSnapshot, at now: Date, dayCount: Int = upcomingDays,
                                calendar: Calendar = .current) -> Upcoming {
        let parser = DateExpressionParser(calendar: calendar, now: now, weekStart: snapshot.weekStart)
        let start = parser.startOfWeek(containing: now)
        return Upcoming(
            today: calendar.startOfDay(for: now),
            week: (0..<7).map { parser.day($0, from: start) },
            counts: UpcomingDays.counts(snapshot.tasks, now: now, calendar: calendar),
            days: UpcomingDays.days(snapshot.tasks, now: now, dayCount: dayCount, calendar: calendar)
                .map { Upcoming.Day(date: $0.date, tasks: $0.tasks) },
            weekStart: snapshot.weekStart)
    }

    // MARK: - Flipboard

    /// The board as a status check: one Switchboard, or the loose switches.
    public struct Flipboard: Equatable, Sendable {
        public struct Light: Equatable, Sendable, Identifiable {
            public var task: Task
            public var side: FlipboardSwitch.Side
            public var id: UUID { task.id }
        }

        /// The Switchboard shown; nil for the loose switches.
        public var boardID: UUID?
        /// The board's name, or "Flipboard" for the loose switches.
        public var title: String
        /// The board's cadence line ("Daily · resets 4:00 AM"); nil for the loose switches.
        public var line: String?
        /// Its switches in the board's order, each green or red as the board judges it now.
        public var lights: [Light]

        public var done: Int { lights.filter { $0.side == .green }.count }
        /// "2 of 4" switches done; nil for a board without switches.
        public var doneText: String? { lights.isEmpty ? nil : "\(done) of \(lights.count)" }
        /// The header's line: "Daily · resets 4:00 AM · 2 of 4".
        public var summary: String { [line, doneText].compactMap { $0 }.joined(separator: " · ") }
    }

    public static let looseTitle = "Flipboard"

    /// The Switchboard `board` names, or the loose switches when it is nil or no longer exists.
    public static func flipboard(_ snapshot: WidgetSnapshot, board: UUID?, at now: Date,
                                 calendar: Calendar = .current) -> Flipboard {
        let chosen = board.flatMap { id in snapshot.switchboards.first { $0.id == id } }
        let ids = chosen?.switchIDs ?? snapshot.looseSwitchIDs
        let lights = ids.compactMap(snapshot.task).compactMap { task -> Flipboard.Light? in
            guard let side = FlipboardSwitch.side(of: task, now: now, calendar: calendar) else { return nil }
            return Flipboard.Light(task: task, side: side)
        }
        return Flipboard(boardID: chosen?.id, title: chosen?.name ?? looseTitle, line: chosen?.line, lights: lights)
    }

    // MARK: - Timeline

    /// How far ahead a timeline looks; WidgetKit asks for the next one when it ends.
    public static let horizon: TimeInterval = 36 * 3600

    /// The moments after `now` (within `horizon`) at which some widget's content can change, in order: each midnight
    /// (Today and Upcoming move on a day, a loose switch turns red), each Switchboard's reset (its switches turn red
    /// together), each timed task's due time (its time turns red; an opted-in switch becomes Today's).
    public static func changes(_ snapshot: WidgetSnapshot, after now: Date, within horizon: TimeInterval = horizon,
                               calendar: Calendar = .current) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var moments = Set<Date>()
        var day = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: day).map({ calendar.startOfDay(for: $0) }), next <= end {
            moments.insert(next)
            day = next
        }
        for board in snapshot.switchboards {
            let schedule = board.clock.schedule
            var period = schedule.period(containing: now, calendar: calendar)
            while period.end > now, period.end <= end {
                moments.insert(period.end)
                let following = schedule.period(containing: period.end, calendar: calendar)
                guard following.end > period.end else { break }
                period = following
            }
        }
        for task in snapshot.tasks {
            if task.hasTime, let due = task.due { moments.insert(due) }
            if FlipboardSwitch.isMember(task), task.switchOptedIn, let schedule = task.clock?.schedule {
                moments.insert(schedule.dueMoment(due: task.due, hasTime: task.hasTime, now: now, calendar: calendar))
            }
        }
        return moments.filter { $0 > now && $0 <= end }.sorted()
    }
}
