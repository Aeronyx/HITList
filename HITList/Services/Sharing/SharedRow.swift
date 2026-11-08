import Foundation
import Observation
import HITListCore

/// A task of a shared list as your lists show it (brief 62): the task, and what its row needs of its list. Its Group is
/// the forced Shared Tasks Group (brief 64); its list, underneath, is the set of people it is shared with.
struct SharedRow: Identifiable, Equatable {
    let task: SharedTask
    let listID: UUID
    /// The list's name ("Shared list" while it has none): what a refusal names, never a Group (brief 64).
    let listTitle: String
    let listColorHex: String
    /// Whether this account may complete, edit and move it (`SharedTasksPermissions`).
    let canWrite: Bool
    /// Who it is shared with, never me (brief 64): their pictures stand where a task of yours has its labels.
    let people: [SharedPerson]

    var id: UUID { task.id }

    init(task: SharedTask, list: SharedList, people: [SharedPerson]) {
        self.task = task
        listID = list.id
        listTitle = list.title.isEmpty ? SharedRow.untitled : list.title
        listColorHex = list.colorHex
        canWrite = SharedTasksPermissions.allows(.completeTask, in: list)
        self.people = people
    }

    /// The row with its list's people other than `me` (`SharedPeople.others`).
    init(task: SharedTask, list: SharedList, me: SharedMemberID? = nil) {
        self.init(task: task, list: list, people: SharedPeople.others(in: list, me: me))
    }

    static let untitled = "Shared list"
}

/// A shared task is a task to every list rule (`ListRow`): its Group is Shared Tasks (brief 64), so dated it is in Today,
/// Upcoming and the Inbox and undated it stays in that Group, as a note stays in its Group. It has no labels, no repeat
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
    var filterProjectName: String? { SharedTasksGroup.name }
    var filterLabelNames: [String] { [] }
    var filterIsRecurring: Bool { false }
    var filterCreatedDate: Date? { task.createdAt }
}

/// A list row: a task of yours or a shared one (brief 62).
typealias TaskListRow = ListRow<TaskItem, SharedRow>
