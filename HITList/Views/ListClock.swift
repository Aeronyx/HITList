import SwiftUI
import HITListCore

/// When a list must be drawn again with nothing else having happened (round 32, review 154's finding 3): the lists had
/// a 60-second clock that re-ran every one of them at rest, against round 26's rule (no timer with nothing pending).
/// A row changes by itself only at a few moments: a timed task's time passes (its date turns red, a filter's
/// `overdue` takes it), a reminder goes off (its chip goes), a switch's board resets (its side) or an opted-in switch
/// falls due (it joins today's tasks), a calendar event ends (it dims). A new day, zone or clock is `CalendarChange`'s,
/// which every list already hears. So each list sleeps once, to the soonest of these among what it lists or could list,
/// and is drawn again then; with none pending, nothing runs.
enum ListClock {
    /// The soonest moment after `now` at which one of `tasks` (open ones only: a completed task never changes by
    /// itself), `shared` or `events` shows differently; nil when none will.
    @MainActor
    static func next<Tasks: Sequence>(after now: Date, tasks: Tasks, shared: [SharedRow] = [], events: [DayEvent] = [],
                                      calendar: Calendar = .current) -> Date? where Tasks.Element == TaskItem {
        var soonest: Date?
        func consider(_ moment: Date?) {
            guard let moment, moment > now else { return }
            if soonest.map({ moment < $0 }) ?? true { soonest = moment }
        }
        for task in tasks where !task.isCompleted {
            if task.hasDueTime { consider(task.dueDate) }
            consider(task.reminderDate)
            // A switch is a repeating task first: its labels are read only for those.
            guard task.recurrence != nil, Flipboard.isMember(task) else { continue }
            if let board = task.filterSwitchboard {
                consider(board.period(containing: now, calendar: calendar).end)
                if task.filterSwitchOptedIn {
                    consider(board.dueMoment(due: task.dueDate, hasTime: task.hasDueTime, now: now, calendar: calendar))
                }
            }
        }
        for row in shared where !row.filterIsCompleted && row.filterHasDueTime { consider(row.filterDueDate) }
        // `CalendarDay.isPast`'s moment: when it stops taking up its day (an all-day one at the day's end).
        for event in events { consider(event.isAllDay ? event.dayEnd : min(event.event.end, event.dayEnd)) }
        return soonest
    }
}

extension View {
    /// Sets `now` at `moment` (`ListClock.next`), once; a new moment (the list changed, or `now` moved) starts over.
    func listClock(_ moment: Date?, now: Binding<Date>) -> some View {
        task(id: moment) {
            guard let moment else { return }
            try? await Task.sleep(for: .seconds(max(0, moment.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            now.wrappedValue = Date()
        }
    }
}
