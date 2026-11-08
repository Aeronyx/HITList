import Foundation
import Observation
import HITListCore

/// A task of a shared list as your lists show it (brief 62): the task, and what its row needs of its list. Its list
/// is to it what a Group is to a task of yours.
struct SharedRow: Identifiable, Equatable {
    let task: SharedTask
    let listID: UUID
    /// The list's name ("Shared list" while it has none), drawn where a Group's name sits on a row of yours.
    let listTitle: String
    let listColorHex: String
    /// Whether this account may complete, edit and move it (`SharedTasksPermissions`).
    let canWrite: Bool

    var id: UUID { task.id }

    init(task: SharedTask, list: SharedList) {
        self.task = task
        listID = list.id
        listTitle = list.title.isEmpty ? SharedRow.untitled : list.title
        listColorHex = list.colorHex
        canWrite = SharedTasksPermissions.allows(.completeTask, in: list)
    }

    static let untitled = "Shared list"
}

/// A shared task is a task to every list rule (`ListRow`): its list's name is its Group name, so dated it is in Today,
/// Upcoming and the Inbox and undated it stays in its list, as a note stays in its Group. It has no labels, no repeat
/// and no sub-tasks, so it is never a Flipboard switch.
extension SharedRow: ListRowItem {
    var rowID: UUID { task.id }
    var rowGroupID: UUID? { listID }
    var filterTitle: String { task.title.value }
    var filterNotes: String { task.notes.value }
    var filterPriority: Int { task.priority.value }
    var filterDueDate: Date? { task.due.value?.date }
    var filterHasDueTime: Bool { task.due.value?.hasTime ?? false }
    var filterIsCompleted: Bool { task.isCompleted }
    var filterProjectName: String? { listTitle }
    var filterLabelNames: [String] { [] }
    var filterIsRecurring: Bool { false }
    var filterCreatedDate: Date? { task.createdAt }
}

/// A list row: a task of yours or a shared one (brief 62).
typealias TaskListRow = ListRow<TaskItem, SharedRow>
