import SwiftUI
import SwiftData
import HITListCore

/// Moving tasks between days: what a dragged row carries, and the quick dates the row menu offers.
enum TaskRescheduling {
    /// A dragged row carries its task's id as a plain string, so a drop elsewhere just pastes the id.
    static func dragPayload(for id: UUID) -> String { id.uuidString }

    /// The task ids in a drop, ignoring anything that isn't one.
    static func taskIDs(in payload: [String]) -> [UUID] {
        payload.compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Drops `payload` (dragged task ids) on `day`: each open task among `tasks` named there moves to
    /// that day, keeping its time of day and its repeat's time (`TaskActions.reschedule`). Days before
    /// today take nothing (they are the Overdue column's); a task already on `day` is left untouched, so
    /// dropping a card back where it came from saves and syncs nothing. Returns the tasks that moved.
    @MainActor @discardableResult
    static func drop(_ payload: [String], on day: Date, among tasks: [TaskItem], now: Date,
                     calendar: Calendar = .current, in context: ModelContext) -> [TaskItem] {
        let target = calendar.startOfDay(for: day)
        guard target >= calendar.startOfDay(for: now) else { return [] }
        let ids = Set(taskIDs(in: payload))
        let moving = tasks.filter { task in
            guard ids.contains(task.id), !task.isCompleted else { return false }
            return task.dueDate.map { calendar.startOfDay(for: $0) } != target
        }
        for task in moving { TaskActions.reschedule(task, to: target, in: context) }
        return moving
    }

    /// The Overdue column's Reschedule (and Upcoming's "Reschedule all to today"): every open task in
    /// `tasks` to `day`, each keeping its time of day and its repeat's time.
    @MainActor
    static func reschedule(_ tasks: [TaskItem], to day: Date, calendar: Calendar = .current, in context: ModelContext) {
        let target = calendar.startOfDay(for: day)
        for task in tasks where !task.isCompleted { TaskActions.reschedule(task, to: target, in: context) }
    }

    /// The day `offset` days from the task's due day, or from today for an undated task (⌘← / ⌘→).
    static func day(_ offset: Int, from due: Date?, now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: due ?? now))!
    }

    enum QuickDate: CaseIterable {
        case today, tomorrow, nextWeek

        var title: String {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .nextWeek: "Next Week"
            }
        }

        var symbol: String {
            switch self {
            case .today: "star"
            case .tomorrow: "sunrise"
            case .nextWeek: "arrow.right.circle"
            }
        }

        /// Next week is the Monday after this week, as in quick add's "next week".
        func date(now: Date, calendar: Calendar = .current) -> Date {
            let parser = DateExpressionParser(calendar: calendar, now: now, weekStart: Preferences.weekStartWeekday())
            switch self {
            case .today: return parser.today
            case .tomorrow: return parser.day(1)
            case .nextWeek: return parser.day(7, from: parser.startOfWeek(containing: now))
            }
        }
    }
}

/// Pick Date (Upcoming's swipe and row menu, Review Inbox): our date card in a popover, as everywhere else (brief 97;
/// the system's graphical picker it used began its weeks on Sunday whatever Settings said): the presets (Today,
/// Tomorrow, Next week, Weekend, No date) and `HITCalendar` from the first day of the week in Settings. A day applies
/// as soon as it is picked; No date removes the date where `onRemove` is given, and is off where it is not.
struct PickDatePopover: View {
    /// The task's day, ringed in the calendar; nil for an undated task.
    let selected: Date?
    var now = Date()
    var onPick: (Date) -> Void
    var onRemove: (() -> Void)?

    init(selected: Date?, now: Date = Date(), onPick: @escaping (Date) -> Void, onRemove: (() -> Void)? = nil) {
        self.selected = selected
        self.now = now
        self.onPick = onPick
        self.onRemove = onRemove
    }

    var body: some View {
        DatePickerCard(selected: selected, now: now, canClear: onRemove != nil, onPick: { day in
            if let day { onPick(day) } else { onRemove?() }
        })
        .frame(width: PickerKind.date.width)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .font(HITType.body)
        .presentationBackground(Theme.surface)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("pickDateCard")
    }
}
