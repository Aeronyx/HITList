import Foundation
import SwiftData
import HITListCore

/// The Flipboard's rules. A switch is not a new model: it is an open recurring task without a time of
/// day that carries the `flipboard` label. Green side = due in the future; red side = due today or
/// overdue; flipping it back completes the task, which rolls the due date forward by its recurrence.
enum Flipboard {
    static let labelName = "flipboard"
    /// Every device creates the label with this id, so copies made before a CloudKit import collapse.
    static let labelID = SeedIdentity.uuid(for: "TaskLabel/flipboard")
    /// The rule a task gets when it joins the board without one.
    static let defaultRule = RecurrenceRule.weekly

    enum Side: Equatable { case green, red }

    // MARK: Membership

    static func isMember(recurrence: String?, hasDueTime: Bool, isCompleted: Bool, labelNames: [String]) -> Bool {
        guard let recurrence, RecurrenceRule(encoded: recurrence) != nil, !hasDueTime, !isCompleted else { return false }
        return labelNames.contains { $0.caseInsensitiveCompare(labelName) == .orderedSame }
    }

    static func isMember(_ task: TaskItem) -> Bool {
        isMember(recurrence: task.recurrence, hasDueTime: task.hasDueTime, isCompleted: task.isCompleted,
                 labelNames: task.filterLabelNames)
    }

    static func hasLabel(_ task: TaskItem) -> Bool {
        task.filterLabelNames.contains { $0.caseInsensitiveCompare(labelName) == .orderedSame }
    }

    // MARK: Sides and the light bar

    /// A switch with no due date has never been flipped; it shows red until it is.
    static func side(due: Date?, now: Date, calendar: Calendar = .current) -> Side {
        guard let due else { return .red }
        return calendar.startOfDay(for: due) > calendar.startOfDay(for: now) ? .green : .red
    }

    /// Red and past its due day (not merely due today). Overdue LEDs pulse.
    static func isOverdue(due: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
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

    /// The due date a flip lands on: what completing the task gives (`RecurrenceRule.nextDueDate`), moved
    /// on again if that is still today, so a flipped switch always shows green.
    static func dueAfterFlip(due: Date?, rule: RecurrenceRule, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = rule.nextDueDate(from: due ?? today, now: now, calendar: calendar)
        var guardCount = 0
        while calendar.startOfDay(for: next) <= today && guardCount < 1000 {
            next = rule.nextOccurrence(after: next, calendar: calendar)
            guardCount += 1
        }
        return next
    }

    /// Flips a switch back to green through `TaskActions.toggleCompletion`.
    @MainActor
    static func flip(_ task: TaskItem, in context: ModelContext, now: Date = Date()) {
        guard let rule = task.recurrenceRule else { return }
        let target = dueAfterFlip(due: task.dueDate, rule: rule, now: now)
        // Without a due date toggleCompletion would mark a recurring task done instead of rolling it.
        if task.dueDate == nil { task.dueDate = Calendar.current.startOfDay(for: now) }
        TaskActions.toggleCompletion(task, in: context)
        // toggleCompletion can land on today (e.g. due Monday every 3 days, flipped on Thursday).
        if task.dueDate != target { TaskActions.reschedule(task, to: target, keepTime: false, in: context) }
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
    /// day without a time (one interval from today if it had none), and the label.
    @MainActor
    static func add(_ task: TaskItem, in context: ModelContext, now: Date = Date()) throws {
        let cal = Calendar.current
        let rule = task.recurrenceRule ?? defaultRule
        task.recurrenceRule = rule
        if let due = task.dueDate {
            task.dueDate = cal.startOfDay(for: due)
        } else {
            task.dueDate = rule.nextOccurrence(after: cal.startOfDay(for: now), calendar: cal)
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

    /// A new switch, green and one interval from today (it starts as if just flipped).
    @MainActor
    @discardableResult
    static func createSwitch(title: String, rule: RecurrenceRule, in context: ModelContext, now: Date = Date()) throws -> TaskItem {
        let cal = Calendar.current
        let due = rule.nextOccurrence(after: cal.startOfDay(for: now), calendar: cal)
        let parsed = QuickAddResult(title: title, dueDate: due, recurrence: rule)
        return try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: try label(in: context), in: context)
    }

    /// Changes a switch's interval, keeping when the current interval began: shortening "every 3 days"
    /// to "every 2 days" pulls the due date one day closer.
    @MainActor
    static func setRule(_ rule: RecurrenceRule, for task: TaskItem, in context: ModelContext) {
        if let due = task.dueDate, let old = task.recurrenceRule {
            let start = intervalStart(due: due, rule: old)
            task.dueDate = rule.nextOccurrence(after: start)
        }
        task.recurrenceRule = rule
        task.touch()
        try? context.save()
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
