import Foundation

/// The list rules George asked for in round 3, kept pure so they are tested once and every screen uses
/// the same ones:
/// - Inbox and Today sort by priority (P1 first), then due date and time (undated last), then creation
///   (older first), then title.
///   (`FilterQuery.defaultSort`, due-then-priority, stays the order of saved filters.)
/// - The Inbox holds every dated task, in any Group, plus undated tasks with no Group. An undated task
///   inside a Group is a note: it shows only when browsing that Group.
/// - Today is two sections, overdue and today, and never shows undated or future tasks.
/// - Browse search looks through titles and notes of every task, completed ones too.
/// - Subtasks (brief 32) are never rows of their own anywhere: they live inside their parent.
public enum TaskOrdering {

    // MARK: - Subtasks

    /// `tasks` without the subtasks: every list starts from these.
    public static func topLevel<T: FilterableTask>(_ tasks: [T]) -> [T] {
        tasks.filter { !$0.filterIsSubtask }
    }

    // MARK: - Order

    /// Priority (P1 first), then due date and time ascending with undated last, then creation order.
    public static func priorityThenDue<T: FilterableTask>(_ a: T, _ b: T) -> Bool {
        if a.filterPriority != b.filterPriority { return a.filterPriority < b.filterPriority }
        switch (a.filterDueDate, b.filterDueDate) {
        case let (da?, db?) where da != db: return da < db
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        return createdThenTitle(a, b)
    }

    /// The last tiebreak of every list: the order tasks were added in, older first (George, 2026-11-03:
    /// with the title deciding, a task just added jumped among its equals), then the title. A task with
    /// no creation date counts as the oldest.
    public static func createdThenTitle<T: FilterableTask>(_ a: T, _ b: T) -> Bool {
        let ca = a.filterCreatedDate ?? .distantPast, cb = b.filterCreatedDate ?? .distantPast
        if ca != cb { return ca < cb }
        return a.filterTitle.localizedCaseInsensitiveCompare(b.filterTitle) == .orderedAscending
    }

    /// `tasks` in `priorityThenDue` order.
    public static func sorted<T: FilterableTask>(_ tasks: [T]) -> [T] {
        tasks.sorted(by: priorityThenDue)
    }

    // MARK: - Inbox

    /// Whether a task belongs in the Inbox, whatever its completion: it has a date (in any Group), or
    /// it has no Group.
    public static func isInInbox<T: FilterableTask>(_ task: T) -> Bool {
        guard !task.filterIsSubtask else { return false }
        return task.filterDueDate != nil || task.filterProjectName == nil
    }

    /// The Inbox's tasks in list order: open ones, plus completed ones when `includeCompleted`.
    public static func inbox<T: FilterableTask>(_ tasks: [T], includeCompleted: Bool = false) -> [T] {
        sorted(tasks.filter { isInInbox($0) && (includeCompleted || !$0.filterIsCompleted) })
    }

    // MARK: - Today

    /// Which of Today's two sections a due date falls in; nil for undated and future dates.
    public enum TodaySection: String, Sendable, CaseIterable {
        case overdue
        case today
    }

    /// Overdue is any day before today (a time earlier today is still today's).
    public static func todaySection(for due: Date?, now: Date, calendar: Calendar = .current) -> TodaySection? {
        guard let due else { return nil }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        if day < today { return .overdue }
        return day == today ? .today : nil
    }

    /// Today's screen: open tasks due before today in `overdue`, open tasks due today in `today`, both
    /// in `priorityThenDue` order. With `includeCompleted`, completed tasks due today join `today`
    /// (completed overdue ones would be every old task, so they stay out).
    public struct TodayList<T: FilterableTask> {
        public let overdue: [T]
        public let today: [T]
        public var isEmpty: Bool { overdue.isEmpty && today.isEmpty }
    }

    public static func today<T: FilterableTask>(_ tasks: [T], now: Date, calendar: Calendar = .current,
                                                includeCompleted: Bool = false) -> TodayList<T> {
        var overdue: [T] = [], today: [T] = []
        for task in topLevel(tasks) {
            switch todaySection(for: task.filterDueDate, now: now, calendar: calendar) {
            case .overdue? where !task.filterIsCompleted: overdue.append(task)
            case .today? where includeCompleted || !task.filterIsCompleted: today.append(task)
            default: break
            }
        }
        return TodayList(overdue: sorted(overdue), today: sorted(today))
    }

    /// Whether a task is on the Today screen (the membership half of `today(_:now:)`).
    public static func isInToday<T: FilterableTask>(_ task: T, now: Date, calendar: Calendar = .current,
                                                    includeCompleted: Bool = false) -> Bool {
        guard !task.filterIsSubtask else { return false }
        switch todaySection(for: task.filterDueDate, now: now, calendar: calendar) {
        case .overdue?: return !task.filterIsCompleted
        case .today?: return includeCompleted || !task.filterIsCompleted
        case nil: return false
        }
    }

    // MARK: - Search

    /// Browse search: every task whose title or notes contain each word of `text` (case and accent
    /// insensitive), completed ones included. Open tasks first in `priorityThenDue` order, then
    /// completed ones. Blank text matches nothing.
    public static func search<T: FilterableTask>(_ tasks: [T], text: String) -> [T] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let matches = topLevel(tasks).filter { task in
            words.allSatisfy { word in
                task.filterTitle.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || task.filterNotes.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        return sorted(matches.filter { !$0.filterIsCompleted }) + sorted(matches.filter(\.filterIsCompleted))
    }
}
