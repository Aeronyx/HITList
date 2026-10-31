import Foundation
import HITListCore

/// The list a quick-add was opened from, which decides the new task's defaults: Today adds for today,
/// a project adds into that project, an Upcoming day adds on that day, Inbox adds undated to the Inbox.
/// Text typed in the card always wins over these.
enum QuickAddContext: Hashable {
    case inbox
    case today
    /// Upcoming's "+" and ⌘N: today, like Today.
    case upcoming
    /// An Upcoming day's "Add task" row.
    case day(Date)
    case project(name: String)
    case label(name: String)
    /// Saved filters, Completed, the Flipboard: no defaults.
    case plain

    /// The due day a task added here gets when its text names none (all day, no time).
    func defaultDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today, .upcoming: return calendar.startOfDay(for: now)
        case .day(let day): return calendar.startOfDay(for: day)
        case .inbox, .project, .label, .plain: return nil
        }
    }

    /// The project a task added here goes to when its text names none; nil is the Inbox.
    var defaultProjectName: String? {
        if case .project(let name) = self { return name }
        return nil
    }

    /// The label every task added here carries.
    var defaultLabelName: String? {
        if case .label(let name) = self { return name }
        return nil
    }
}
