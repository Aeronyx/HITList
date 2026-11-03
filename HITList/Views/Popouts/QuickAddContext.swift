import Foundation
import HITListCore

/// The list a quick-add was opened from, which decides the new task's defaults: Today adds for today,
/// a project adds into that project, an Upcoming day adds on that day, Inbox adds undated to the Inbox.
/// Text typed in the card always wins over these. Codable so an open card's list comes back with it after
/// the app was killed (`QuickAddDraftStore`).
enum QuickAddContext: Hashable, Codable {
    case inbox
    case today
    /// Upcoming's "+" and ⌘N: today, like Today.
    case upcoming
    /// An Upcoming day's "Add task" row.
    case day(Date)
    /// The Group's name, and its id so a card stored while the Group was renamed elsewhere still finds it
    /// (`resolvingGroup`). Cards stored by 0.4.0 (13) have no id.
    case project(name: String, id: UUID? = nil)
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
        if case .project(let name, _) = self { return name }
        return nil
    }

    /// This list with its Group looked up again among `projects`: by id first, then by name (case
    /// ignored). A Group that is gone is dropped, so the task goes to the Inbox rather than recreating the
    /// Group under a name it no longer has. Every other list is returned as it is.
    func resolvingGroup(in projects: [(id: UUID, name: String)]) -> QuickAddContext {
        guard case .project(let name, let id) = self else { return self }
        let found = id.flatMap { id in projects.first { $0.id == id } }
            ?? projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return found.map { .project(name: $0.name, id: $0.id) } ?? .inbox
    }

    /// The label every task added here carries.
    var defaultLabelName: String? {
        if case .label(let name) = self { return name }
        return nil
    }
}
