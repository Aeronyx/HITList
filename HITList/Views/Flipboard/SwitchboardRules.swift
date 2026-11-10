import Foundation
import SwiftData
import HITListCore

/// Switchboards (brief 72): named groups of switches, "Before Bed" or "Deep Clean", each with a day of its own (Daily
/// or Weekly, resetting at a time, a weekly one on a weekday). The arithmetic of that day is core's
/// `SwitchboardSchedule`; these are the store's actions. A switch belongs to at most one board; one with none is a
/// loose switch on the main board. Nothing is ever migrated onto a board and no default board is made, so two
/// devices can't each make one.
extension Flipboard {
    enum SwitchboardError: LocalizedError {
        case emptyName
        var errorDescription: String? { "A Switchboard needs a name." }
    }

    /// Every Switchboard in the Flipboard's order.
    @MainActor
    static func switchboards(in context: ModelContext) throws -> [Switchboard] {
        ordered(try context.fetch(FetchDescriptor<Switchboard>()))
    }

    /// `sortOrder`, then creation, then id, so every device shows the same order.
    static func ordered(_ boards: [Switchboard]) -> [Switchboard] {
        boards.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// A new board, after the others: Daily at 04:00 unless told otherwise (brief 72's choice), a weekly one on the
    /// week start from Settings (stored as 0, so it follows that setting).
    @MainActor
    @discardableResult
    static func createSwitchboard(name: String, cadence: SwitchboardSchedule.Cadence = .daily,
                                  resetMinutes: Int = SwitchboardSchedule.defaultResetMinutes, resetWeekday: Int = 0,
                                  overdueBecomesTask: Bool = false, in context: ModelContext) throws -> Switchboard {
        let name = TaskLimits.clampedTitle(name)
        guard !name.isEmpty else { throw SwitchboardError.emptyName }
        let existing = try context.fetch(FetchDescriptor<Switchboard>())
        let board = Switchboard(name: name, sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
        board.cadenceValue = cadence
        board.resetMinutes = SwitchboardSchedule(cadence: cadence, resetMinutes: resetMinutes).resetMinutes
        board.resetWeekday = (0...7).contains(resetWeekday) ? resetWeekday : 0
        board.overdueBecomesTask = overdueBecomesTask
        context.insert(board)
        try context.save()
        return board
    }

    /// The Switchboard card's Save. A change to the board's clock (cadence, reset time or day) re-lands its switches
    /// on the new clock as they were: done stays done (due on the new clock's next period), due stays due (this
    /// period); a cadence change gives them the cadence's rule.
    @MainActor
    static func update(_ board: Switchboard, name: String, cadence: SwitchboardSchedule.Cadence, resetMinutes: Int,
                       resetWeekday: Int, overdueBecomesTask: Bool, in context: ModelContext, now: Date = Date()) {
        let trimmed = TaskLimits.clampedTitle(name)
        let before = board.schedule()
        let sides = (board.switches ?? []).map { ($0, Clock($0).side($0.dueDate, now: now)) }
        if !trimmed.isEmpty { board.name = trimmed }
        board.cadenceValue = cadence
        board.resetMinutes = SwitchboardSchedule(cadence: cadence, resetMinutes: resetMinutes).resetMinutes
        board.resetWeekday = (0...7).contains(resetWeekday) ? resetWeekday : 0
        board.overdueBecomesTask = overdueBecomesTask
        board.touch()
        if board.schedule() != before {
            for (task, side) in sides { land(task, side: side, on: board, now: now) }
        }
        try? context.save()
    }

    /// One place up (`-1`) or down (`+1`) in the Flipboard's order of boards; every board is renumbered 0, 1, 2…
    @MainActor
    static func moveSwitchboard(_ board: Switchboard, by offset: Int, in context: ModelContext) {
        guard var boards = try? switchboards(in: context), let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        let target = min(boards.count - 1, max(0, index + offset))
        guard target != index else { return }
        boards.insert(boards.remove(at: index), at: target)
        for (order, item) in boards.enumerated() where item.sortOrder != order {
            item.sortOrder = order
            item.touch()
        }
        try? context.save()
    }

    /// Delete Switchboard…: the board goes, and its switches with it only when the person said so; otherwise they
    /// stay as loose switches. A delete syncs to every device, as the person means it; never use one as a reset.
    @MainActor
    static func deleteSwitchboard(_ board: Switchboard, deletingSwitches: Bool, in context: ModelContext, now: Date = Date()) {
        for task in board.switches ?? [] {
            if deletingSwitches {
                context.delete(task)
            } else {
                move(task, to: nil, in: context, now: now, save: false)
            }
        }
        context.delete(board)
        try? context.save()
    }

    // MARK: A switch's board, time and opt-in

    /// Moves a switch onto a board, to another, or off (nil) to the main board, keeping its side: done stays done,
    /// due stays due. On a board it takes the board's cadence as its rule; leaving one, it keeps that rule as its
    /// interval (the card can change it).
    @MainActor
    static func move(_ task: TaskItem, to board: Switchboard?, in context: ModelContext, now: Date = Date(), save: Bool = true) {
        guard task.switchboard?.id != board?.id else { return }
        let side = Clock(task).side(task.dueDate, now: now)
        task.switchboard = board
        if let board {
            land(task, side: side, on: board, now: now)
        } else {
            let cal = Calendar.current
            let timed = task.hasDueTime && task.dueDate != nil
            if side == .red {
                task.dueDate = keepingTime(of: timed ? task.dueDate : nil, on: now, calendar: cal)
            } else if let due = task.dueDate, cal.startOfDay(for: due) <= cal.startOfDay(for: now) {
                // Done for a board day that ends after midnight: done until tomorrow.
                task.dueDate = keepingTime(of: timed ? due : nil, on: cal.date(byAdding: .day, value: 1, to: now)!, calendar: cal)
            }
        }
        task.touch()
        if save { try? context.save() }
    }

    /// Puts a switch's due date on `board`'s clock with the side it had: green, on the board's next period; red, in
    /// this one (at its time, if it has one). Its rule becomes the board's cadence (timed to its time).
    private static func land(_ task: TaskItem, side: Side, on board: Switchboard, now: Date) {
        let schedule = board.schedule()
        let cal = Calendar.current
        let timed = task.hasDueTime && task.dueDate != nil
        if timed, let due = task.dueDate {
            let time = PickerTime(due, calendar: cal)
            let current = schedule.periodDay(containing: now, calendar: cal)
            let day = side == .green ? schedule.nextPeriodDay(after: current, calendar: cal) : current
            task.dueDate = onBoardDay(day, at: time, board: board, calendar: cal)
        } else {
            task.dueDate = side == .green
                ? schedule.dueAfterFlip(due: nil, hasTime: false, now: now, calendar: cal)
                : schedule.dueAfterFlipBack(due: nil, hasTime: false, now: now, calendar: cal)
        }
        task.recurrenceRule = cadenceRule(board.cadenceValue).timed(to: task.dueDate, hasTime: timed, calendar: cal)
    }

    /// The switch's time of day, if it has one.
    static func time(of task: TaskItem, calendar: Calendar = .current) -> PickerTime? {
        guard task.hasDueTime, let due = task.dueDate else { return nil }
        return PickerTime(due, calendar: calendar)
    }

    /// Gives a switch a time of day ("Take meds 21:00"), changes it, or (nil) takes it away, keeping its side: the
    /// time moves within the day (a board's: the board day) the switch is due in.
    @MainActor
    static func setTime(_ time: PickerTime?, for task: TaskItem, in context: ModelContext, now: Date = Date()) {
        let cal = Calendar.current
        guard time != self.time(of: task, calendar: cal) else { return }
        let clock = Clock(task)
        let due = task.dueDate ?? cal.startOfDay(for: now)
        let board = task.switchboard
        // The (board) day the switch is due in now.
        let day: Date = board.map { $0.schedule().boardDay(ofDue: due, hasTime: clock.hasTime, calendar: cal) }
            ?? cal.startOfDay(for: due)
        if let time {
            task.dueDate = onBoardDay(day, at: time, board: board, calendar: cal)
            task.hasDueTime = true
        } else {
            task.dueDate = day
            task.hasDueTime = false
        }
        task.recurrenceRule = task.recurrenceRule?.timed(to: task.dueDate, hasTime: task.hasDueTime, calendar: cal)
        task.touch()
        try? context.save()
    }

    /// "Overdue becomes task" on a switch.
    @MainActor
    static func setOverdueBecomesTask(_ on: Bool, for task: TaskItem, in context: ModelContext) {
        guard task.overdueBecomesTask != on else { return }
        task.overdueBecomesTask = on
        task.touch()
        try? context.save()
    }
}
