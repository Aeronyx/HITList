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

    // MARK: - Taps on their way (brief 81)

    /// How a task shows on a widget once the taps are counted.
    public enum Shown: Equatable, Sendable {
        /// As itself: unchecked, or a switch on its own side.
        case open
        /// Checked (a row) or flipping (a pill): a tap is on its way and iCloud doesn't have it yet.
        case checked
        /// Not on the widget.
        case gone
    }

    /// The quiet line a widget adds: never an alarm.
    public enum Note: Equatable, Sendable {
        /// A tap has waited `pickupPatience` without the app picking it up (the Mac app isn't running): "Open HITList to
        /// finish".
        case openApp
        /// An applied tap is waiting for iCloud: sync is offline, stuck or retrying, or the export is slow
        /// (`exportPatience`). "Waiting for iCloud".
        case waitingForICloud
        /// The snapshot is older than a day (`staleAfter`): "As of yesterday".
        case asOf(Date)
    }

    /// The widget as it draws: the snapshot with each pending row in place of its task, the tasks drawn checked, and the
    /// quiet line.
    public struct Marks: Equatable, Sendable {
        public var snapshot: WidgetSnapshot
        public var checked: Set<UUID>
        public var note: Note?

        public func isChecked(_ id: UUID) -> Bool { checked.contains(id) }

        public func shown(_ id: UUID) -> Shown {
            checked.contains(id) ? .checked : snapshot.task(id) != nil ? .open : .gone
        }
    }

    /// How long a tap waits in the outbox, unseen by the app, before the widget says to open it.
    public static let pickupPatience: TimeInterval = 20
    /// How long an applied tap waits for its export, with sync looking fine, before the widget says it is waiting.
    public static let exportPatience: TimeInterval = 30
    /// How old a snapshot is before the widget says when it was written.
    public static let staleAfter: TimeInterval = 86_400

    /// `snapshot` as the widget draws it with the taps in its outbox (`requests`, read by the extension): a row the app
    /// has picked up is drawn as the widget showed it (`WidgetSnapshot.pending`), in place of the task the store has
    /// now (completed, or rolled on to its next date), until iCloud has the completion; a tap the app hasn't picked up
    /// checks the row the snapshot has.
    public static func marks(_ snapshot: WidgetSnapshot, requests: [WidgetRequest], at now: Date) -> Marks {
        let pending = snapshot.pending ?? []
        let pendingIDs = Set(pending.map(\.taskID))
        var drawn = snapshot
        drawn.tasks = snapshot.tasks.filter { !pendingIDs.contains($0.id) } + pending.map(\.task)
        let heard = Set(pending.map(\.requestID))
        let unheard = requests.filter { !heard.contains($0.id) }
        let checked = pendingIDs.union(unheard.map(\.taskID))
        return Marks(snapshot: drawn, checked: checked, note: note(snapshot, pending: pending, unheard: unheard, at: now))
    }

    private static func note(_ snapshot: WidgetSnapshot, pending: [WidgetSnapshot.Pending], unheard: [WidgetRequest],
                             at now: Date) -> Note? {
        // Unseen: the app hasn't written the snapshot since the tap (a running app writes it as it applies).
        let unseen = unheard.filter { snapshot.writtenAt < $0.askedAt }
        if unseen.contains(where: { now.timeIntervalSince($0.askedAt) >= pickupPatience }) { return .openApp }
        if !pending.isEmpty {
            if snapshot.sync == .waiting { return .waitingForICloud }
            if pending.contains(where: { now.timeIntervalSince($0.appliedAt ?? $0.askedAt) >= exportPatience }) {
                return .waitingForICloud
            }
        }
        if now.timeIntervalSince(snapshot.writtenAt) >= staleAfter { return .asOf(snapshot.writtenAt) }
        return nil
    }

    /// The moments after `now` at which the quiet line can change by itself: a tap's patience running out, the
    /// snapshot turning a day old. A widget's timeline has an entry at each.
    public static func noteChanges(_ snapshot: WidgetSnapshot, requests: [WidgetRequest], after now: Date) -> [Date] {
        let heard = Set((snapshot.pending ?? []).map(\.requestID))
        var moments = requests.filter { !heard.contains($0.id) }.map { $0.askedAt.addingTimeInterval(pickupPatience) }
        moments += (snapshot.pending ?? []).map { ($0.appliedAt ?? $0.askedAt).addingTimeInterval(exportPatience) }
        moments.append(snapshot.writtenAt.addingTimeInterval(staleAfter))
        return Set(moments.filter { $0 > now }).sorted()
    }

    /// "As of yesterday", "As of Sunday" within the week, then "As of Nov 8".
    public static func asOfText(_ written: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: written),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...1: return "As of yesterday"
        case 2...6: return "As of \(written.formatted(.dateTime.weekday(.wide)))"
        default: return "As of \(written.formatted(.dateTime.month(.abbreviated).day()))"
        }
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
