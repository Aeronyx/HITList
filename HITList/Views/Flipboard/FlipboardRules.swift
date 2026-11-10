import Foundation
import SwiftData
import HITListCore

/// The Flipboard's rules. A switch is not a new model: it is an open recurring task that carries the `flipboard`
/// label, with or without a time of day (brief 72). Green side = done for now; red side = due today or
/// overdue; flipping it back completes the task, which rolls the due date forward by its recurrence. A switch
/// on a Switchboard follows the board's clock (`SwitchboardSchedule`): its day starts at the board's reset time.
enum Flipboard {
    static let labelName = FlipboardSwitch.labelName
    /// Every device creates the label with this id, so copies made before a CloudKit import collapse.
    static let labelID = SeedIdentity.uuid(for: "TaskLabel/flipboard")
    /// The rule a task gets when it joins the board without one.
    static let defaultRule = RecurrenceRule.weekly

    typealias Side = FlipboardSwitch.Side

    // MARK: Membership

    // The pure rules (membership, sides, overdue) live in HITListCore's `FlipboardSwitch`, so every list
    // judges a task the way the board does (brief 59).

    /// A repeat that doesn't decode is no repeat: the board can't step it. A time of day is allowed (brief 72).
    static func isMember(recurrence: String?, isCompleted: Bool, labelNames: [String]) -> Bool {
        FlipboardSwitch.isMember(isRecurring: recurrence.flatMap(RecurrenceRule.init(encoded:)) != nil,
                                 isCompleted: isCompleted, labelNames: labelNames)
    }

    static func isMember(_ task: TaskItem) -> Bool {
        isMember(recurrence: task.recurrence, isCompleted: task.isCompleted, labelNames: task.filterLabelNames)
    }

    static func hasLabel(_ task: TaskItem) -> Bool { FlipboardSwitch.hasLabel(task.filterLabelNames) }

    /// The switch's side, or nil when the task isn't a switch: a loose one by its due day, one on a Switchboard by
    /// the board's day.
    static func side(of task: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> Side? {
        isMember(task) ? FlipboardSwitch.side(due: task.dueDate, hasTime: task.hasDueTime, board: task.filterSwitchboard,
                                              now: now, calendar: calendar) : nil
    }

    // MARK: The clock (brief 72)

    /// How a switch keeps time: a loose switch by its interval (`rule`), its day ending at midnight; one on a
    /// Switchboard by the board's clock (`board`), its day starting at the board's reset. `hasTime`: the switch has a
    /// time of day ("Take meds 21:00"), which its due date carries.
    struct Clock: Equatable {
        var rule: RecurrenceRule
        var board: SwitchboardSchedule? = nil
        var hasTime = false

        init(rule: RecurrenceRule, board: SwitchboardSchedule? = nil, hasTime: Bool = false) {
            self.rule = rule
            self.board = board
            self.hasTime = hasTime
        }

        init(_ task: TaskItem) {
            self.init(rule: task.recurrenceRule ?? Flipboard.defaultRule, board: task.filterSwitchboard,
                      hasTime: task.hasDueTime && task.dueDate != nil)
        }

        func side(_ due: Date?, now: Date, calendar: Calendar = .current) -> Side {
            FlipboardSwitch.side(due: due, hasTime: hasTime, board: board, now: now, calendar: calendar)
        }

        /// The breathing light: a loose switch past its day, or any red switch past its time (`FlipboardSwitch.isLate`).
        func isLate(_ due: Date?, now: Date, calendar: Calendar = .current) -> Bool {
            FlipboardSwitch.isLate(due: due, hasTime: hasTime, board: board, now: now, calendar: calendar)
        }

        /// Where a flip lands: a board's next period, or (loose) the interval from the flip day, at the switch's time.
        func dueAfterFlip(_ due: Date?, now: Date, calendar: Calendar = .current) -> Date {
            if let board { return board.dueAfterFlip(due: due, hasTime: hasTime, now: now, calendar: calendar) }
            let next = Flipboard.dueAfterFlip(due: due, rule: rule, now: now, calendar: calendar)
            return Flipboard.keepingTime(of: hasTime ? due : nil, on: next, calendar: calendar)
        }
    }

    /// `day` at `due`'s wall-clock time; the day's start without a time.
    static func keepingTime(of due: Date?, on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        guard let due else { return start }
        let parts = calendar.dateComponents([.hour, .minute], from: due)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: start) ?? start
    }

    // MARK: Sides and the light bar

    /// A switch with no due date has never been flipped; it shows red until it is.
    static func side(due: Date?, now: Date, calendar: Calendar = .current) -> Side {
        FlipboardSwitch.side(due: due, now: now, calendar: calendar)
    }

    /// True once the switch has been flipped. A new switch is due the day it was created and shows red
    /// with "Flip to start" and an empty light bar until its first flip moves the due date past that day.
    /// A switch with no due date has never been flipped either.
    static func hasStarted(due: Date?, createdAt: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return calendar.startOfDay(for: due) > calendar.startOfDay(for: createdAt)
    }

    /// A charger has also started once its first flip is counted, though its due date hasn't moved. A switch on a
    /// Switchboard is always under way: its board day says whether it is done (brief 72), never "Flip to start".
    static func hasStarted(_ task: TaskItem, now: Date = Date()) -> Bool {
        task.switchboard != nil || hasStarted(due: task.dueDate, createdAt: task.createdAt) || effectiveCount(task, now: now) > 0
    }

    /// The line under the light bar: "Flip to start", "2 of 3 days", "Due today" or "3 days overdue".
    static func caption(due: Date?, rule: RecurrenceRule, started: Bool, now: Date, calendar: Calendar = .current) -> String {
        guard let due, started else { return "Flip to start" }
        switch side(due: due, now: now, calendar: calendar) {
        case .green:
            let total = intervalDays(due: due, rule: rule, calendar: calendar)
            let done = elapsedDays(due: due, rule: rule, now: now, calendar: calendar)
            return "\(done) of \(total) \(total == 1 ? "day" : "days")"
        case .red:
            let late = daysOverdue(due: due, now: now, calendar: calendar)
            return late == 0 ? "Due today" : "\(late) \(late == 1 ? "day" : "days") overdue"
        }
    }

    /// Red and past its due day (not merely due today). Overdue LEDs pulse.
    static func isOverdue(due: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        FlipboardSwitch.isOverdue(due: due, now: now, calendar: calendar)
    }

    /// Whole days `due` is past, 0 when it isn't.
    static func daysOverdue(due: Date?, now: Date, calendar: Calendar = .current) -> Int {
        guard let due else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: due), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// When the interval that ends at `due` began: the occurrence before it. `RecurrenceRule` only steps
    /// forward, so this steps back by the same amount. For weekly rules on chosen weekdays it is the
    /// nearest earlier chosen weekday (exact for every-week rules, an approximation for every N weeks).
    static func intervalStart(due: Date, rule: RecurrenceRule, calendar: Calendar = .current) -> Date {
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: -rule.interval, to: due)!
        case .monthly:
            return calendar.date(byAdding: .month, value: -rule.interval, to: due)!
        case .yearly:
            return calendar.date(byAdding: .year, value: -rule.interval, to: due)!
        case .weekly:
            if let weekdays = rule.weekdays, !weekdays.isEmpty {
                for back in 1...(7 * rule.interval) {
                    let candidate = calendar.date(byAdding: .day, value: -back, to: due)!
                    if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
                }
            }
            return calendar.date(byAdding: .day, value: -7 * rule.interval, to: due)!
        }
    }

    /// Length in days of the interval that ends at `due` (3 for "every 3 days", 7 for "every week").
    static func intervalDays(due: Date, rule: RecurrenceRule, calendar: Calendar = .current) -> Int {
        let start = intervalStart(due: due, rule: rule, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: due)).day ?? 1
        return max(1, days)
    }

    /// How much of the interval has gone by, 0...1. It reaches 1 the moment the switch turns red.
    static func elapsedFraction(due: Date?, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Double {
        guard let due else { return 1 }
        let start = intervalStart(due: due, rule: rule, calendar: calendar)
        let end = calendar.startOfDay(for: due)
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// Whole days gone by in the interval, 0...`intervalDays` (the "2" in "2 of 3 days").
    static func elapsedDays(due: Date, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Int {
        let start = intervalStart(due: due, rule: rule, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        return min(intervalDays(due: due, rule: rule, calendar: calendar), max(0, days))
    }

    // MARK: Order

    /// Red first with the most overdue at the top, then green by soonest due. Both halves are "earliest
    /// due first", and a never-flipped switch counts as the most overdue. Ties go alphabetically.
    static func isOrderedBefore(_ a: (due: Date?, title: String), _ b: (due: Date?, title: String),
                                calendar: Calendar = .current) -> Bool {
        let da = a.due.map { calendar.startOfDay(for: $0) } ?? .distantPast
        let db = b.due.map { calendar.startOfDay(for: $0) } ?? .distantPast
        if da != db { return da < db }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    static func sorted(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        tasks.sorted { isOrderedBefore(($0.dueDate, $0.title), ($1.dueDate, $1.title), calendar: calendar) }
    }

    /// A Switchboard's order (brief 72), steady as its switches flip, as a routine's steps are: the timed ones by
    /// their time within the board day (with a 04:00 reset, 00:30 comes after 21:00), then the untimed ones in the
    /// order they were added. Returns the titles in order.
    static func boardOrder(_ switches: [(title: String, minutes: Int?, created: Date)], resetMinutes: Int) -> [String] {
        func sinceReset(_ minutes: Int) -> Int { (minutes - resetMinutes + 24 * 60) % (24 * 60) }
        return switches.sorted { a, b in
            switch (a.minutes, b.minutes) {
            case let (ma?, mb?) where ma != mb: return sinceReset(ma) < sinceReset(mb)
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if a.created != b.created { return a.created < b.created }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }.map(\.title)
    }

    /// `tasks`, the switches of `board`, in the board's order (`boardOrder`).
    static func sorted(onBoard tasks: [TaskItem], _ board: Switchboard, calendar: Calendar = .current) -> [TaskItem] {
        func minutes(_ task: TaskItem) -> Int? {
            guard task.hasDueTime, let due = task.dueDate else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: due)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        func sinceReset(_ m: Int) -> Int { (m - board.resetMinutes + 24 * 60) % (24 * 60) }
        return tasks.sorted { a, b in
            switch (minutes(a), minutes(b)) {
            case let (ma?, mb?) where ma != mb: return sinceReset(ma) < sinceReset(mb)
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
                return a.id.uuidString < b.id.uuidString
            }
        }
    }

    // MARK: Flipping

    /// The due date a flip lands on. Like a physical switch, flipping restarts the interval from the day
    /// you flip it (shave on Thursday, every 3 days: due Sunday) rather than continuing the old schedule,
    /// so a flipped switch always shows green with a full interval ahead. George's call, 2026-10-28.
    /// For weekday rules this is the next chosen weekday after today.
    static func dueAfterFlip(due: Date?, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = rule.nextOccurrence(after: today, calendar: calendar)
        var guardCount = 0
        while calendar.startOfDay(for: next) <= today && guardCount < 1000 {
            next = rule.nextOccurrence(after: next, calendar: calendar)
            guardCount += 1
        }
        return next
    }

    /// Flips a switch (see `afterFlip`). A flip that charges it rolls the task on through
    /// `TaskActions.toggleCompletion`, as a plain switch always has; a flip that only counts toward a
    /// charger's target leaves the due date alone.
    @MainActor
    @discardableResult
    static func flip(_ task: TaskItem, in context: ModelContext, now: Date = Date()) -> FlipOutcome {
        guard task.recurrenceRule != nil else { return .ignored }
        let (next, outcome) = afterFlip(Charge(task), target: task.flipTarget, clock: Clock(task), now: now)
        apply(next, outcome: outcome, to: task, in: context, now: now)
        return outcome
    }

    /// "Mark done" from the switch's menu (see `afterMarkDone`).
    @MainActor
    @discardableResult
    static func markDone(_ task: TaskItem, in context: ModelContext, now: Date = Date()) -> FlipOutcome {
        guard task.recurrenceRule != nil else { return .ignored }
        let (next, outcome) = afterMarkDone(Charge(task), target: task.flipTarget, clock: Clock(task), now: now)
        apply(next, outcome: outcome, to: task, in: context, now: now)
        return outcome
    }

    @MainActor
    private static func apply(_ next: Charge, outcome: FlipOutcome, to task: TaskItem, in context: ModelContext, now: Date) {
        switch outcome {
        case .ignored:
            return
        case .counted:
            task.dueDate = next.due
        case .charged:
            // Without a due date toggleCompletion would mark a recurring task done instead of rolling it.
            if task.dueDate == nil { task.dueDate = Calendar.current.startOfDay(for: now) }
            TaskActions.toggleCompletion(task, in: context)
            // toggleCompletion continues the old schedule; a flip restarts it from today (see dueAfterFlip).
            if task.dueDate != next.due { TaskActions.reschedule(task, to: next.due, keepTime: false, in: context) }
        }
        task.flipCount = next.count
        task.flipPeriodStart = next.periodStart
        task.touch()
        try? context.save()
    }

    // MARK: Completing a switch's row (brief 59)

    /// A red switch is a task in Today (and the Inbox); completing its row is a flip. The lists call
    /// these three around their completion: `completion(for:)` before, `completeRow` instead of
    /// `TaskActions.toggleCompletion`, and `undo` first in their Undo.

    /// What a switch's row flip changes, so Undo can put it back exactly (a counted flip moves no date).
    struct RowFlip: Equatable {
        let charge: Charge
        let recurrence: String?
        let reminderDate: Date?
    }

    /// The toast's record for a row about to be completed. A switch's says "Flipped" and carries its
    /// state; its `revert` (the due date) still undoes the flip in a list that doesn't call `undo`.
    static func completion(for task: TaskItem) -> CompletedTask {
        if isMember(task) {
            let flip = RowFlip(charge: Charge(task), recurrence: task.recurrence, reminderDate: task.reminderDate)
            return CompletedTask(id: task.id, title: task.title,
                                 revert: .restoreDueDate(task.dueDate ?? Calendar.current.startOfDay(for: Date())), flip: flip)
        }
        let revert: CompletedTask.Revert = if task.recurrenceRule != nil, let due = task.dueDate {
            .restoreDueDate(due)
        } else {
            .uncomplete
        }
        return CompletedTask(id: task.id, title: task.title, revert: revert)
    }

    /// Completes a row: a switch flips (the interval restarts from today; a charger counts one flip),
    /// anything else goes through `TaskActions.toggleCompletion`.
    @MainActor
    static func completeRow(_ task: TaskItem, in context: ModelContext, now: Date = Date()) {
        if isMember(task) {
            flip(task, in: context, now: now)
        } else {
            TaskActions.toggleCompletion(task, in: context, now: now)
        }
    }

    /// Undo for a flipped row: puts the switch back as `record` found it. False when the record is not
    /// a flip (the list undoes it as before).
    @MainActor
    @discardableResult
    static func undo(_ record: CompletedTask, on task: TaskItem, in context: ModelContext) -> Bool {
        guard let flip = record.flip else { return false }
        task.dueDate = flip.charge.due
        task.flipCount = flip.charge.count
        task.flipPeriodStart = flip.charge.periodStart
        task.recurrence = flip.recurrence
        task.reminderDate = flip.reminderDate
        task.touch()
        try? context.save()
        return true
    }

    /// Undoes the last flip (see `afterFlipBack`).
    @MainActor
    static func flipBack(_ task: TaskItem, in context: ModelContext, now: Date = Date()) {
        guard task.recurrenceRule != nil,
              let next = afterFlipBack(Charge(task), target: task.flipTarget, clock: Clock(task), now: now) else { return }
        task.dueDate = next.due
        task.flipCount = next.count
        task.flipPeriodStart = next.periodStart
        task.touch()
        try? context.save()
    }

    /// Sets "flips per interval", 1 to `maxFlipTarget` (see `afterTargetChange`).
    @MainActor
    static func setTarget(_ target: Int, for task: TaskItem, in context: ModelContext, now: Date = Date()) {
        let target = clampedTarget(target)
        guard target != task.flipTarget else { return }
        if task.recurrenceRule != nil {
            let next = afterTargetChange(Charge(task), from: task.flipTarget, to: target, clock: Clock(task), now: now)
            task.dueDate = next.due
            task.flipCount = next.count
            task.flipPeriodStart = next.periodStart
        }
        task.flipTarget = target
        task.touch()
        try? context.save()
    }

    static func effectiveCount(_ task: TaskItem, now: Date = Date()) -> Int {
        effectiveCount(Charge(task), target: task.flipTarget, clock: Clock(task), now: now)
    }

    // MARK: Charging

    /// A switch with `flipTarget` > 1 is a charger: it needs that many flips within one interval before
    /// it turns green ("go to the gym 3 times a week"). Each flip while red adds one to `flipCount`; the
    /// flip that reaches the target charges it, and the due date moves on exactly as a single flip moves
    /// it. `flipCount` then stays at the target, so the lamps read full while green. When the date rule
    /// turns the switch red again, a `flipPeriodStart` from before the current interval makes the count
    /// stale: it reads as 0 and the next flip starts counting afresh. A plain switch is a charger with a
    /// target of 1, so it follows the same rules and behaves as it always has.
    static let maxFlipTarget = 10

    static func clampedTarget(_ target: Int) -> Int { min(maxFlipTarget, max(1, target)) }

    /// The parts of a switch that flipping changes.
    struct Charge: Equatable {
        var due: Date?
        var count: Int
        var periodStart: Date?
    }

    enum FlipOutcome: Equatable {
        /// A charger took one more flip and is still red: `n` of its target now.
        case counted(Int)
        /// The switch turned (or, flipped early, stayed) green for a new interval.
        case charged
        /// A charger that is already green: nothing changes, the rocker just bounces.
        case ignored
    }

    /// The start of the interval a red switch is counting flips for: its due day, moved on by the rule
    /// for every whole interval that has since gone by, so an overdue weekly charger counts this week's
    /// flips only. Nil without a due date.
    static func countingIntervalStart(due: Date?, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Date? {
        guard let due else { return nil }
        let today = calendar.startOfDay(for: now)
        var start = calendar.startOfDay(for: due)
        var steps = 0
        while steps < 1000 {
            let next = calendar.startOfDay(for: rule.nextOccurrence(after: start, calendar: calendar))
            guard next > start, next <= today else { break }
            start = next
            steps += 1
        }
        return start
    }

    /// True when `periodStart` belongs to an earlier interval than the one a red switch is counting. On a Switchboard
    /// the interval is the board day (or week) now, from its reset (brief 72: chargers count within the board's period).
    static func isStale(periodStart: Date?, due: Date?, clock: Clock, now: Date, calendar: Calendar = .current) -> Bool {
        guard let periodStart else { return true }
        if let board = clock.board { return periodStart < board.period(containing: now, calendar: calendar).start }
        guard let start = countingIntervalStart(due: due, rule: clock.rule, now: now, calendar: calendar) else { return false }
        return calendar.startOfDay(for: periodStart) < start
    }

    static func isStale(periodStart: Date?, due: Date?, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Bool {
        isStale(periodStart: periodStart, due: due, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// The flips that count right now: the full target while green (done for the interval), otherwise
    /// the stored count unless it is stale, never reaching the target while red.
    static func effectiveCount(_ charge: Charge, target: Int, clock: Clock, now: Date, calendar: Calendar = .current) -> Int {
        let target = clampedTarget(target)
        if clock.side(charge.due, now: now, calendar: calendar) == .green { return target }
        if isStale(periodStart: charge.periodStart, due: charge.due, clock: clock, now: now, calendar: calendar) { return 0 }
        return min(target - 1, max(0, charge.count))
    }

    static func effectiveCount(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Int {
        effectiveCount(charge, target: target, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// A red switch with at least one flip counted in the current interval.
    static func isCharging(_ charge: Charge, target: Int, clock: Clock, now: Date, calendar: Calendar = .current) -> Bool {
        clock.side(charge.due, now: now, calendar: calendar) == .red
            && effectiveCount(charge, target: target, clock: clock, now: now, calendar: calendar) > 0
    }

    static func isCharging(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Bool {
        isCharging(charge, target: target, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// What one flip does. Red: count one more (the first flip of an interval resets a stale count and
    /// sets `periodStart`), charging at the target. Green: a plain loose switch is flipped early (the interval
    /// restarts from today, as before); a charger ignores it, and so does a switch on a Switchboard, which is
    /// done for its board day (brief 72).
    static func afterFlip(_ charge: Charge, target: Int, clock: Clock, now: Date,
                          calendar: Calendar = .current) -> (charge: Charge, outcome: FlipOutcome) {
        let target = clampedTarget(target)
        if clock.side(charge.due, now: now, calendar: calendar) == .green {
            guard target == 1, clock.board == nil else { return (charge, .ignored) }
            return (Charge(due: clock.dueAfterFlip(charge.due, now: now, calendar: calendar), count: 1, periodStart: now),
                    .charged)
        }
        let counted = effectiveCount(charge, target: target, clock: clock, now: now, calendar: calendar)
        let periodStart = counted == 0 ? now : charge.periodStart ?? now
        let flips = counted + 1
        if flips >= target {
            return (Charge(due: clock.dueAfterFlip(charge.due, now: now, calendar: calendar), count: target,
                           periodStart: periodStart), .charged)
        }
        // A dateless switch gets this day (a board's: this board day), so the interval it is counting has a start.
        let today = clock.board.map { $0.dueAfterFlipBack(due: nil, hasTime: false, now: now, calendar: calendar) }
            ?? calendar.startOfDay(for: now)
        return (Charge(due: charge.due ?? today, count: flips, periodStart: periodStart), .counted(flips))
    }

    static func afterFlip(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date,
                          calendar: Calendar = .current) -> (charge: Charge, outcome: FlipOutcome) {
        afterFlip(charge, target: target, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// "Mark done": charges a red switch at once, whatever its count. Green, a plain loose switch is flipped
    /// early and a charger (or a board's switch) is left alone (the menu disables it).
    static func afterMarkDone(_ charge: Charge, target: Int, clock: Clock, now: Date,
                              calendar: Calendar = .current) -> (charge: Charge, outcome: FlipOutcome) {
        let target = clampedTarget(target)
        guard clock.side(charge.due, now: now, calendar: calendar) == .red else {
            return afterFlip(charge, target: target, clock: clock, now: now, calendar: calendar)
        }
        let counted = effectiveCount(charge, target: target, clock: clock, now: now, calendar: calendar)
        return (Charge(due: clock.dueAfterFlip(charge.due, now: now, calendar: calendar), count: target,
                       periodStart: counted == 0 ? now : charge.periodStart ?? now), .charged)
    }

    static func afterMarkDone(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date,
                              calendar: Calendar = .current) -> (charge: Charge, outcome: FlipOutcome) {
        afterMarkDone(charge, target: target, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// Where "Flip back to red" puts a green switch's due date: the day its interval began, which is the
    /// day it was flipped (a flip restarts the interval from the flip day), and never later than today,
    /// so the switch is red again. The due date before the flip is not stored, so a switch that was
    /// overdue comes back due on its flip day rather than on the older date.
    static func dueAfterFlipBack(due: Date, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: intervalStart(due: due, rule: rule, calendar: calendar))
        return min(start, calendar.startOfDay(for: now))
    }

    /// "Flip back to red" undoes the last flip. Green: the switch turns red, due on the day it was flipped
    /// (or on the day the interval's first flip was counted, so those flips still count), one flip short
    /// of its target; on a Switchboard, due again in this board day (at its time). Red: a charger loses one counted
    /// flip. Nil when there is nothing to undo (red with no flips counted).
    static func afterFlipBack(_ charge: Charge, target: Int, clock: Clock, now: Date,
                              calendar: Calendar = .current) -> Charge? {
        let target = clampedTarget(target)
        if clock.side(charge.due, now: now, calendar: calendar) == .green, let due = charge.due {
            let flips = charge.periodStart == nil ? 0 : min(target - 1, max(0, charge.count - 1))
            if let board = clock.board {
                let back = board.dueAfterFlipBack(due: due, hasTime: clock.hasTime, now: now, calendar: calendar)
                let inPeriod = charge.periodStart.map { $0 >= board.period(containing: now, calendar: calendar).start } ?? false
                return Charge(due: back, count: inPeriod ? flips : 0, periodStart: inPeriod && flips > 0 ? charge.periodStart : nil)
            }
            var back = dueAfterFlipBack(due: due, rule: clock.rule, now: now, calendar: calendar)
            if flips > 0, let periodStart = charge.periodStart { back = min(back, calendar.startOfDay(for: periodStart)) }
            back = keepingTime(of: clock.hasTime ? due : nil, on: back, calendar: calendar)
            return Charge(due: back, count: flips, periodStart: flips > 0 ? charge.periodStart : nil)
        }
        let counted = effectiveCount(charge, target: target, clock: clock, now: now, calendar: calendar)
        guard counted > 0 else { return nil }
        return Charge(due: charge.due, count: counted - 1, periodStart: counted > 1 ? charge.periodStart : nil)
    }

    static func afterFlipBack(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date,
                              calendar: Calendar = .current) -> Charge? {
        afterFlipBack(charge, target: target, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    static func canFlipBack(_ charge: Charge, target: Int, clock: Clock, now: Date, calendar: Calendar = .current) -> Bool {
        afterFlipBack(charge, target: target, clock: clock, now: now, calendar: calendar) != nil
    }

    static func canFlipBack(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Bool {
        canFlipBack(charge, target: target, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// A new "flips per interval". Green stays green (full at the new target if it was full). Red with
    /// at least the new target already counted charges now; otherwise the count carries over.
    static func afterTargetChange(_ charge: Charge, from oldTarget: Int, to newTarget: Int, clock: Clock, now: Date,
                                  calendar: Calendar = .current) -> Charge {
        let oldTarget = clampedTarget(oldTarget), newTarget = clampedTarget(newTarget)
        if clock.side(charge.due, now: now, calendar: calendar) == .green {
            return Charge(due: charge.due, count: charge.count >= oldTarget ? newTarget : min(charge.count, newTarget),
                          periodStart: charge.periodStart)
        }
        let counted = effectiveCount(charge, target: oldTarget, clock: clock, now: now, calendar: calendar)
        guard counted > 0, counted >= newTarget else { return charge }
        return Charge(due: clock.dueAfterFlip(charge.due, now: now, calendar: calendar), count: newTarget,
                      periodStart: charge.periodStart)
    }

    static func afterTargetChange(_ charge: Charge, from oldTarget: Int, to newTarget: Int, rule: RecurrenceRule, now: Date,
                                  calendar: Calendar = .current) -> Charge {
        afterTargetChange(charge, from: oldTarget, to: newTarget, clock: Clock(rule: rule), now: now, calendar: calendar)
    }

    /// The span a charger counts within, for its caption: "this week", "today", "these 2 weeks".
    static func periodPhrase(_ rule: RecurrenceRule) -> String {
        if let weekdays = rule.weekdays, !weekdays.isEmpty { return "this round" }
        let n = rule.interval
        switch rule.frequency {
        case .daily: return n == 1 ? "today" : "these \(n) days"
        case .weekly: return n == 1 ? "this week" : "these \(n) weeks"
        case .monthly: return n == 1 ? "this month" : "these \(n) months"
        case .yearly: return n == 1 ? "this year" : "these \(n) years"
        }
    }

    /// The caption of any switch. A plain switch reads as before; a charger reads "Flip to start",
    /// "2 of 3 this week" while red and "Done this week" once charged.
    static func caption(due: Date?, rule: RecurrenceRule, started: Bool, count: Int, target: Int, now: Date,
                        calendar: Calendar = .current) -> String {
        let target = clampedTarget(target)
        guard target > 1 else { return caption(due: due, rule: rule, started: started, now: now, calendar: calendar) }
        if side(due: due, now: now, calendar: calendar) == .green { return "Done \(periodPhrase(rule))" }
        guard started else { return "Flip to start" }
        return "\(count) of \(target) \(periodPhrase(rule))"
    }

    /// The caption of any switch on any clock (brief 72). A loose untimed switch reads as before. On a Switchboard:
    /// "Done today" / "Done this week" while green; red, "Due today" / "Due this week", a charger "2 of 3 today", a
    /// timed one "Due 21:00", calm, then "Due since 21:00" (never a count of days: a board resets). A loose timed
    /// switch reads "Due 21:00" / "Due since 21:00" on its day and counts days once past it, as any loose switch.
    static func caption(clock: Clock, due: Date?, started: Bool, count: Int, target: Int, now: Date,
                        calendar: Calendar = .current, locale: Locale = .current) -> String {
        let target = clampedTarget(target)
        let side = clock.side(due, now: now, calendar: calendar)
        if let board = clock.board {
            let span = board.cadence == .daily ? "today" : "this week"
            if side == .green { return "Done \(span)" }
            if target > 1 { return "\(count) of \(target) \(span)" }
            guard clock.hasTime, due != nil else { return "Due \(span)" }
            let moment = board.dueMoment(due: due, hasTime: true, now: now, calendar: calendar)
            let time = timeText(moment, calendar: calendar, locale: locale)
            return now >= moment ? "Due since \(time)" : "Due \(time)"
        }
        if clock.hasTime, target == 1, started, let due, side == .red, !isOverdue(due: due, now: now, calendar: calendar) {
            let time = timeText(due, calendar: calendar, locale: locale)
            return now >= due ? "Due since \(time)" : "Due \(time)"
        }
        return caption(due: due, rule: clock.rule, started: started, count: count, target: target, now: now, calendar: calendar)
    }

    /// "21:00" (or "9:00 PM" where the clock is 12-hour), as the switch card and the tiles write a time.
    static func timeText(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// The light bar: a board's switch fills through the board day (or week) while green and is full while red; a
    /// loose one as before.
    static func elapsedFraction(clock: Clock, due: Date?, now: Date, calendar: Calendar = .current) -> Double {
        guard let board = clock.board else { return elapsedFraction(due: due, rule: clock.rule, now: now, calendar: calendar) }
        return clock.side(due, now: now, calendar: calendar) == .green ? board.elapsedFraction(now: now, calendar: calendar) : 1
    }

    /// The lamps showed full for the interval ending on `recordedDue` the last time the board was on
    /// screen; now that interval is over and nothing is counted yet, so the lamps should drain once.
    static func shouldDrain(recordedDue: Date?, due: Date?, count: Int, now: Date, calendar: Calendar = .current) -> Bool {
        guard let recordedDue, let due, count == 0, side(due: due, now: now, calendar: calendar) == .red else { return false }
        return recordedDue == due
    }

    // MARK: Joining and leaving

    /// The `flipboard` label, created with its stable id the first time.
    @MainActor
    static func label(in context: ModelContext) throws -> TaskLabel {
        let existed = try context.fetch(FetchDescriptor<TaskLabel>())
            .contains { $0.name.caseInsensitiveCompare(labelName) == .orderedSame }
        let label = try TaskActions.findOrCreateLabel(named: labelName, in: context)
        if !existed {
            label.id = labelID
            label.colorHex = "#30A46C"
        }
        return label
    }

    /// Puts a task on the board, giving it what a switch needs: a repeat (weekly if it had none), a due
    /// day, and the label. A task without a future due date is due today, so it joins red and waits for its
    /// first flip; one due in the future keeps that day and joins green. A time of day stays (brief 72: a switch
    /// may have one); it is due at that time.
    @MainActor
    static func add(_ task: TaskItem, in context: ModelContext, now: Date = Date()) throws {
        let cal = Calendar.current
        let rule = task.recurrenceRule ?? defaultRule
        let today = cal.startOfDay(for: now)
        let timed = task.hasDueTime && task.dueDate != nil
        let day: Date
        if let due = task.dueDate, cal.startOfDay(for: due) > today {
            day = cal.startOfDay(for: due)
        } else {
            day = today
        }
        task.dueDate = keepingTime(of: timed ? task.dueDate : nil, on: day, calendar: cal)
        task.hasDueTime = timed
        task.recurrenceRule = rule.timed(to: task.dueDate, hasTime: timed)
        task.isCompleted = false
        task.completedAt = nil
        let label = try label(in: context)
        if !(task.labels ?? []).contains(where: { $0.id == label.id }) { task.labels = (task.labels ?? []) + [label] }
        task.touch()
        try context.save()
    }

    /// Takes a task off the board. It keeps its repeat and due date; only the label goes.
    @MainActor
    static func remove(_ task: TaskItem, in context: ModelContext) {
        task.labels = (task.labels ?? []).filter { $0.name.caseInsensitiveCompare(labelName) != .orderedSame }
        task.touch()
        try? context.save()
    }

    // MARK: Deleting (brief 59)

    /// A deleted switch, kept by the Flipboard's toast so Undo can bring it back as it was: its fields,
    /// its Group and labels (by id; they outlive it) and its sub-tasks.
    struct DeletedSwitch: Equatable {
        struct Subtask: Equatable {
            let id: UUID
            let title: String
            let isCompleted: Bool
            let completedAt: Date?
            let sortOrder: Int
            let createdAt: Date
        }

        let id: UUID
        let title: String
        let notes: String
        let priority: Int
        let dueDate: Date?
        let hasDueTime: Bool
        let recurrence: String?
        let sortOrder: Int
        let createdAt: Date
        let reminderOffsetMinutes: Int?
        let reminderDate: Date?
        let deadline: Date?
        let locationName: String?
        let flipTarget: Int
        let flipCount: Int
        let flipPeriodStart: Date?
        let projectID: UUID?
        let labelIDs: [UUID]
        let subtasks: [Subtask]
        /// Brief 72: its Switchboard (by id; it outlives it) and its own "Overdue becomes task".
        let switchboardID: UUID?
        let overdueBecomesTask: Bool

        init(_ task: TaskItem) {
            id = task.id; title = task.title; notes = task.notes; priority = task.priority
            dueDate = task.dueDate; hasDueTime = task.hasDueTime; recurrence = task.recurrence
            sortOrder = task.sortOrder; createdAt = task.createdAt
            reminderOffsetMinutes = task.reminderOffsetMinutes; reminderDate = task.reminderDate
            deadline = task.deadline; locationName = task.locationName
            flipTarget = task.flipTarget; flipCount = task.flipCount; flipPeriodStart = task.flipPeriodStart
            projectID = task.project?.id
            labelIDs = (task.labels ?? []).map(\.id)
            switchboardID = task.switchboard?.id
            overdueBecomesTask = task.overdueBecomesTask
            subtasks = task.orderedSubtasks.map {
                Subtask(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, completedAt: $0.completedAt,
                        sortOrder: $0.sortOrder, createdAt: $0.createdAt)
            }
        }
    }

    /// Deletes a switch and its sub-tasks from the store at once (`TaskActions.delete`, saved now, so the
    /// delete is on its way to iCloud before the toast has gone). Returns what Undo needs.
    @MainActor
    @discardableResult
    static func delete(_ task: TaskItem, in context: ModelContext) -> DeletedSwitch {
        let deleted = DeletedSwitch(task)
        TaskActions.delete(task, in: context)
        return deleted
    }

    /// Undo: the switch again, with its id, dates, flips, Group, labels and sub-tasks.
    @MainActor
    @discardableResult
    static func restore(_ deleted: DeletedSwitch, in context: ModelContext) -> TaskItem? {
        let projectID = deleted.projectID
        let project = projectID.flatMap { id in try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })).first }
        let labelIDs = Set(deleted.labelIDs)
        let labels = ((try? context.fetch(FetchDescriptor<TaskLabel>())) ?? []).filter { labelIDs.contains($0.id) }
        let task = TaskItem(title: deleted.title, notes: deleted.notes, priority: deleted.priority, dueDate: deleted.dueDate,
                            hasDueTime: deleted.hasDueTime, project: project, labels: labels)
        task.id = deleted.id
        task.recurrence = deleted.recurrence
        task.sortOrder = deleted.sortOrder
        task.createdAt = deleted.createdAt
        task.reminderOffsetMinutes = deleted.reminderOffsetMinutes
        task.reminderDate = deleted.reminderDate
        task.deadline = deleted.deadline
        task.locationName = deleted.locationName
        task.flipTarget = deleted.flipTarget
        task.flipCount = deleted.flipCount
        task.flipPeriodStart = deleted.flipPeriodStart
        task.overdueBecomesTask = deleted.overdueBecomesTask
        context.insert(task)
        if let boardID = deleted.switchboardID {
            task.switchboard = try? context.fetch(FetchDescriptor<Switchboard>(predicate: #Predicate { $0.id == boardID })).first
        }
        for sub in deleted.subtasks {
            let item = TaskItem(title: sub.title, project: project)
            item.id = sub.id
            item.isCompleted = sub.isCompleted
            item.completedAt = sub.completedAt
            item.sortOrder = sub.sortOrder
            item.createdAt = sub.createdAt
            context.insert(item)
            item.parent = task
        }
        do {
            try context.save()
        } catch {
            return nil
        }
        return task
    }

    /// A new switch, due today: it starts red ("Flip to start") until the chore is first done and flipped.
    /// George's call, 2026-10-31: a green switch reads as "already done".
    /// `flipTarget` above 1 makes it a charger. Brief 72: `time` gives it a time of day (due today at that time);
    /// `board` puts it on a Switchboard, following the board's cadence and due in this board day (at its time);
    /// `overdueBecomesTask` opts it in to Today once it is due.
    @MainActor
    @discardableResult
    static func createSwitch(title: String, rule: RecurrenceRule, flipTarget: Int = 1, time: PickerTime? = nil,
                             board: Switchboard? = nil, overdueBecomesTask: Bool = false, in context: ModelContext,
                             now: Date = Date()) throws -> TaskItem {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        var rule = rule
        if let board {
            rule = cadenceRule(board.cadenceValue)
            day = board.schedule().periodDay(containing: now, calendar: cal)
        }
        let due = time.map { onBoardDay(day, at: $0, board: board, calendar: cal) } ?? day
        let parsed = QuickAddResult(title: title, dueDate: due, hasDueTime: time != nil,
                                    recurrence: rule.timed(to: due, hasTime: time != nil, calendar: cal))
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: try label(in: context), in: context)
        let target = clampedTarget(flipTarget)
        var changed = false
        if task.flipTarget != target { task.flipTarget = target; changed = true }
        if let board { task.switchboard = board; changed = true }
        if overdueBecomesTask { task.overdueBecomesTask = true; changed = true }
        if changed { try context.save() }
        return task
    }

    /// `time` within the board day `day` stands for: on that day, or the next calendar day for a time before the
    /// board's reset ("00:30" belongs to the board day that began the evening before). Loose: that day.
    static func onBoardDay(_ day: Date, at time: PickerTime, board: Switchboard?, calendar: Calendar = .current) -> Date {
        let moment = time.on(day, calendar: calendar)
        guard let board, time.hour * 60 + time.minute < board.resetMinutes else { return moment }
        return calendar.date(byAdding: .day, value: 1, to: moment) ?? moment
    }

    /// The rule a Switchboard's switches carry: every day, or every week. A build from before Switchboards reads a
    /// board's switch as a loose switch on this interval, so it flips there the way it does here.
    static func cadenceRule(_ cadence: SwitchboardSchedule.Cadence) -> RecurrenceRule {
        cadence == .daily ? .daily : .weekly
    }

    /// Changes a switch's interval, keeping when the current interval began: shortening "every 3 days"
    /// to "every 2 days" pulls the due date one day closer. A switch not yet started stays red.
    /// A red charger keeps its due date (and its count): moving it could turn the switch green without
    /// the flips.
    @MainActor
    static func setRule(_ rule: RecurrenceRule, for task: TaskItem, in context: ModelContext, now: Date = Date()) {
        let redCharger = clampedTarget(task.flipTarget) > 1 && side(due: task.dueDate, now: now) == .red
        if !redCharger, hasStarted(due: task.dueDate, createdAt: task.createdAt), let due = task.dueDate,
           let old = task.recurrenceRule {
            let start = intervalStart(due: due, rule: old)
            task.dueDate = rule.nextOccurrence(after: start)
        }
        // A timed switch keeps its time in the rule (brief 72), as any timed repeat.
        task.recurrenceRule = rule.timed(to: task.dueDate, hasTime: task.hasDueTime)
        task.touch()
        try? context.save()
    }
}

extension Flipboard.Charge {
    init(_ task: TaskItem) {
        self.init(due: task.dueDate, count: task.flipCount, periodStart: task.flipPeriodStart)
    }
}

/// "Every N days / weeks / months", the shapes the switch card's dial offers (brief 69 added months, for
/// the Monthly quick choice).
struct FlipInterval: Hashable {
    enum Unit: String, CaseIterable, Identifiable {
        case days, weeks, months
        var id: Self { self }

        /// "day" / "days", for the dial's unit and the phrase.
        func word(_ count: Int) -> String {
            switch self {
            case .days: count == 1 ? "day" : "days"
            case .weeks: count == 1 ? "week" : "weeks"
            case .months: count == 1 ? "month" : "months"
            }
        }
    }

    var count: Int
    var unit: Unit

    static let `default` = FlipInterval(count: 3, unit: .days)
    /// The dial's numbers.
    static let range = 1...99

    /// Nil for rules the card can't show as N days, weeks or months (chosen weekdays, yearly).
    init?(_ rule: RecurrenceRule) {
        switch rule.frequency {
        case .daily: self.init(count: rule.interval, unit: .days)
        case .weekly where rule.weekdays == nil: self.init(count: rule.interval, unit: .weeks)
        case .monthly: self.init(count: rule.interval, unit: .months)
        default: return nil
        }
    }

    init(count: Int, unit: Unit) {
        self.count = min(Self.range.upperBound, max(Self.range.lowerBound, count))
        self.unit = unit
    }

    var rule: RecurrenceRule {
        let frequency: RecurrenceRule.Frequency = switch unit {
        case .days: .daily
        case .weeks: .weekly
        case .months: .monthly
        }
        return RecurrenceRule(frequency: frequency, interval: count)
    }

    /// The words the switch card writes into a name that already has a repeat phrase: "every 3 days",
    /// "every week". The quick-add grammar reads each one back as `rule`.
    var phrase: String { count == 1 ? "every \(unit.word(1))" : "every \(count) \(unit.word(count))" }

    /// One dial detent along, within `range`.
    func stepped(by delta: Int) -> FlipInterval { FlipInterval(count: count + delta, unit: unit) }

    /// One of the card's quick choices.
    struct Choice: Identifiable, Hashable {
        let title: String
        let interval: FlipInterval
        var id: String { title }
    }

    /// The row of quick choices under a switch's name (brief 69): the intervals most chores have.
    static let quickChoices: [Choice] = [
        Choice(title: "Daily", interval: FlipInterval(count: 1, unit: .days)),
        Choice(title: "3 days", interval: FlipInterval(count: 3, unit: .days)),
        Choice(title: "Weekly", interval: FlipInterval(count: 1, unit: .weeks)),
        Choice(title: "2 weeks", interval: FlipInterval(count: 2, unit: .weeks)),
        Choice(title: "Monthly", interval: FlipInterval(count: 1, unit: .months)),
    ]

    /// The quick choice that is `rule`, if one is.
    static func choice(for rule: RecurrenceRule) -> Choice? {
        quickChoices.first { $0.interval.rule == rule }
    }
}
