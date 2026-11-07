import Foundation
import SwiftData
import HITListCore

/// The Flipboard's rules. A switch is not a new model: it is an open recurring task without a time of
/// day that carries the `flipboard` label. Green side = due in the future; red side = due today or
/// overdue; flipping it back completes the task, which rolls the due date forward by its recurrence.
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

    /// A repeat that doesn't decode is no repeat: the board can't step it.
    static func isMember(recurrence: String?, hasDueTime: Bool, isCompleted: Bool, labelNames: [String]) -> Bool {
        FlipboardSwitch.isMember(isRecurring: recurrence.flatMap(RecurrenceRule.init(encoded:)) != nil,
                                 hasDueTime: hasDueTime, isCompleted: isCompleted, labelNames: labelNames)
    }

    static func isMember(_ task: TaskItem) -> Bool {
        isMember(recurrence: task.recurrence, hasDueTime: task.hasDueTime, isCompleted: task.isCompleted,
                 labelNames: task.filterLabelNames)
    }

    static func hasLabel(_ task: TaskItem) -> Bool { FlipboardSwitch.hasLabel(task.filterLabelNames) }

    /// The switch's side, or nil when the task isn't a switch.
    static func side(of task: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> Side? {
        isMember(task) ? side(due: task.dueDate, now: now, calendar: calendar) : nil
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

    /// A charger has also started once its first flip is counted, though its due date hasn't moved.
    static func hasStarted(_ task: TaskItem, now: Date = Date()) -> Bool {
        hasStarted(due: task.dueDate, createdAt: task.createdAt) || effectiveCount(task, now: now) > 0
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
        guard let rule = task.recurrenceRule else { return .ignored }
        let (next, outcome) = afterFlip(Charge(task), target: task.flipTarget, rule: rule, now: now)
        apply(next, outcome: outcome, to: task, in: context, now: now)
        return outcome
    }

    /// "Mark done" from the switch's menu (see `afterMarkDone`).
    @MainActor
    @discardableResult
    static func markDone(_ task: TaskItem, in context: ModelContext, now: Date = Date()) -> FlipOutcome {
        guard let rule = task.recurrenceRule else { return .ignored }
        let (next, outcome) = afterMarkDone(Charge(task), target: task.flipTarget, rule: rule, now: now)
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

    /// Undoes the last flip (see `afterFlipBack`).
    @MainActor
    static func flipBack(_ task: TaskItem, in context: ModelContext, now: Date = Date()) {
        guard let rule = task.recurrenceRule,
              let next = afterFlipBack(Charge(task), target: task.flipTarget, rule: rule, now: now) else { return }
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
        if let rule = task.recurrenceRule {
            let next = afterTargetChange(Charge(task), from: task.flipTarget, to: target, rule: rule, now: now)
            task.dueDate = next.due
            task.flipCount = next.count
            task.flipPeriodStart = next.periodStart
        }
        task.flipTarget = target
        task.touch()
        try? context.save()
    }

    static func effectiveCount(_ task: TaskItem, now: Date = Date()) -> Int {
        effectiveCount(Charge(task), target: task.flipTarget, rule: task.recurrenceRule ?? defaultRule, now: now)
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

    /// True when `periodStart` belongs to an earlier interval than the one a red switch is counting.
    static func isStale(periodStart: Date?, due: Date?, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Bool {
        guard let periodStart else { return true }
        guard let start = countingIntervalStart(due: due, rule: rule, now: now, calendar: calendar) else { return false }
        return calendar.startOfDay(for: periodStart) < start
    }

    /// The flips that count right now: the full target while green (done for the interval), otherwise
    /// the stored count unless it is stale, never reaching the target while red.
    static func effectiveCount(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Int {
        let target = clampedTarget(target)
        if side(due: charge.due, now: now, calendar: calendar) == .green { return target }
        if isStale(periodStart: charge.periodStart, due: charge.due, rule: rule, now: now, calendar: calendar) { return 0 }
        return min(target - 1, max(0, charge.count))
    }

    /// A red switch with at least one flip counted in the current interval.
    static func isCharging(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Bool {
        side(due: charge.due, now: now, calendar: calendar) == .red
            && effectiveCount(charge, target: target, rule: rule, now: now, calendar: calendar) > 0
    }

    /// What one flip does. Red: count one more (the first flip of an interval resets a stale count and
    /// sets `periodStart`), charging at the target. Green: a plain switch is flipped early (the interval
    /// restarts from today, as before); a charger ignores it.
    static func afterFlip(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date,
                          calendar: Calendar = .current) -> (charge: Charge, outcome: FlipOutcome) {
        let target = clampedTarget(target)
        if side(due: charge.due, now: now, calendar: calendar) == .green {
            guard target == 1 else { return (charge, .ignored) }
            return (Charge(due: dueAfterFlip(due: charge.due, rule: rule, now: now, calendar: calendar), count: 1, periodStart: now),
                    .charged)
        }
        let counted = effectiveCount(charge, target: target, rule: rule, now: now, calendar: calendar)
        let periodStart = counted == 0 ? now : charge.periodStart ?? now
        let flips = counted + 1
        if flips >= target {
            return (Charge(due: dueAfterFlip(due: charge.due, rule: rule, now: now, calendar: calendar), count: target,
                           periodStart: periodStart), .charged)
        }
        // A dateless switch gets today, so the interval it is counting has a start.
        return (Charge(due: charge.due ?? calendar.startOfDay(for: now), count: flips, periodStart: periodStart), .counted(flips))
    }

    /// "Mark done": charges a red switch at once, whatever its count. Green, a plain switch is flipped
    /// early and a charger is left alone (the menu disables it).
    static func afterMarkDone(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date,
                              calendar: Calendar = .current) -> (charge: Charge, outcome: FlipOutcome) {
        let target = clampedTarget(target)
        guard side(due: charge.due, now: now, calendar: calendar) == .red else {
            return afterFlip(charge, target: target, rule: rule, now: now, calendar: calendar)
        }
        let counted = effectiveCount(charge, target: target, rule: rule, now: now, calendar: calendar)
        return (Charge(due: dueAfterFlip(due: charge.due, rule: rule, now: now, calendar: calendar), count: target,
                       periodStart: counted == 0 ? now : charge.periodStart ?? now), .charged)
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
    /// of its target. Red: a charger loses one counted flip. Nil when there is nothing to undo (red with
    /// no flips counted).
    static func afterFlipBack(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date,
                              calendar: Calendar = .current) -> Charge? {
        let target = clampedTarget(target)
        if side(due: charge.due, now: now, calendar: calendar) == .green, let due = charge.due {
            let flips = charge.periodStart == nil ? 0 : min(target - 1, max(0, charge.count - 1))
            var back = dueAfterFlipBack(due: due, rule: rule, now: now, calendar: calendar)
            if flips > 0, let periodStart = charge.periodStart { back = min(back, calendar.startOfDay(for: periodStart)) }
            return Charge(due: back, count: flips, periodStart: flips > 0 ? charge.periodStart : nil)
        }
        let counted = effectiveCount(charge, target: target, rule: rule, now: now, calendar: calendar)
        guard counted > 0 else { return nil }
        return Charge(due: charge.due, count: counted - 1, periodStart: counted > 1 ? charge.periodStart : nil)
    }

    static func canFlipBack(_ charge: Charge, target: Int, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Bool {
        afterFlipBack(charge, target: target, rule: rule, now: now, calendar: calendar) != nil
    }

    /// A new "flips per interval". Green stays green (full at the new target if it was full). Red with
    /// at least the new target already counted charges now; otherwise the count carries over.
    static func afterTargetChange(_ charge: Charge, from oldTarget: Int, to newTarget: Int, rule: RecurrenceRule, now: Date,
                                  calendar: Calendar = .current) -> Charge {
        let oldTarget = clampedTarget(oldTarget), newTarget = clampedTarget(newTarget)
        if side(due: charge.due, now: now, calendar: calendar) == .green {
            return Charge(due: charge.due, count: charge.count >= oldTarget ? newTarget : min(charge.count, newTarget),
                          periodStart: charge.periodStart)
        }
        let counted = effectiveCount(charge, target: oldTarget, rule: rule, now: now, calendar: calendar)
        guard counted > 0, counted >= newTarget else { return charge }
        return Charge(due: dueAfterFlip(due: charge.due, rule: rule, now: now, calendar: calendar), count: newTarget,
                      periodStart: charge.periodStart)
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
    /// day without a time, and the label. A task without a future due date is due today, so it joins red
    /// and waits for its first flip; one due in the future keeps that day and joins green.
    @MainActor
    static func add(_ task: TaskItem, in context: ModelContext, now: Date = Date()) throws {
        let cal = Calendar.current
        let rule = task.recurrenceRule ?? defaultRule
        task.recurrenceRule = rule
        let today = cal.startOfDay(for: now)
        if let due = task.dueDate, cal.startOfDay(for: due) > today {
            task.dueDate = cal.startOfDay(for: due)
        } else {
            task.dueDate = today
        }
        task.hasDueTime = false
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

    /// A new switch, due today: it starts red ("Flip to start") until the chore is first done and flipped.
    /// George's call, 2026-10-31: a green switch reads as "already done".
    /// `flipTarget` above 1 makes it a charger.
    @MainActor
    @discardableResult
    static func createSwitch(title: String, rule: RecurrenceRule, flipTarget: Int = 1, in context: ModelContext,
                             now: Date = Date()) throws -> TaskItem {
        let due = Calendar.current.startOfDay(for: now)
        let parsed = QuickAddResult(title: title, dueDate: due, recurrence: rule)
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: try label(in: context), in: context)
        let target = clampedTarget(flipTarget)
        if task.flipTarget != target {
            task.flipTarget = target
            try context.save()
        }
        return task
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
        task.recurrenceRule = rule
        task.touch()
        try? context.save()
    }
}

extension Flipboard.Charge {
    init(_ task: TaskItem) {
        self.init(due: task.dueDate, count: task.flipCount, periodStart: task.flipPeriodStart)
    }
}

/// "Every N days / weeks", the two shapes the board's editors offer.
struct FlipInterval: Equatable {
    enum Unit: String, CaseIterable, Identifiable {
        case days, weeks
        var id: Self { self }
    }

    var count: Int
    var unit: Unit

    static let `default` = FlipInterval(count: 3, unit: .days)

    /// Nil for rules the editors can't show as N days/weeks (monthly, chosen weekdays, ...).
    init?(_ rule: RecurrenceRule) {
        switch rule.frequency {
        case .daily: self.init(count: rule.interval, unit: .days)
        case .weekly where rule.weekdays == nil: self.init(count: rule.interval, unit: .weeks)
        default: return nil
        }
    }

    init(count: Int, unit: Unit) {
        self.count = max(1, count)
        self.unit = unit
    }

    var rule: RecurrenceRule {
        RecurrenceRule(frequency: unit == .days ? .daily : .weekly, interval: count)
    }
}
