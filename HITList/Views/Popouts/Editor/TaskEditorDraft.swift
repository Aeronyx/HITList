import Foundation
import SwiftData
import HITListCore

/// What the task editor holds until Confirm: the typing. The title, the description, the open "Add
/// Sub-task" field and a sub-task being renamed wait here; Confirm (`commit`) saves them all and the
/// editor closes in the same tap. × and Esc ask Discard first, then drop them (brief 41). Everything picked
/// rather than typed (date, Group, priority, labels, reminder, repeat, deadline, location, ticking a sub-task)
/// lands at once, as before.
struct TaskEditorDraft: Equatable {
    /// A sub-task's title being edited in place.
    struct Rename: Equatable {
        let id: UUID
        var text: String
    }

    var title: String
    var notes: String
    /// The "Add Sub-task" row is a text field.
    var isAddingSubtask = false
    var newSubtask = ""
    var renaming: Rename?

    init(task: TaskItem) {
        title = task.title
        notes = task.notes
    }

    /// The title as Confirm saves it: one line, capped; nil keeps the stored one (left blank, or unchanged).
    static func titleToSave(_ edited: String, current: String) -> String? {
        let title = TaskLimits.clampedTitle(TaskLimits.singleLine(edited))
        return title.isEmpty || title == current ? nil : title
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func notesToSave(for task: TaskItem) -> String? {
        let notes = Self.trimmed(notes)
        return notes == Self.trimmed(task.notes) ? nil : notes
    }

    private func renameToSave(for task: TaskItem) -> (subtask: TaskItem, title: String)? {
        guard let renaming, let subtask = (task.subtasks ?? []).first(where: { $0.id == renaming.id }),
              let title = Self.titleToSave(renaming.text, current: subtask.title) else { return nil }
        return (subtask, title)
    }

    /// Whether Confirm would save anything.
    func hasPendingChanges(for task: TaskItem) -> Bool {
        Self.titleToSave(title, current: task.title) != nil || notesToSave(for: task) != nil
            || !Self.trimmed(newSubtask).isEmpty || renameToSave(for: task) != nil
    }

    /// A swipe down on the iPhone sheet (brief 36): with typing Confirm would save, the sheet stays and asks
    /// Discard (George's rule for the quick-add card: "tapping away asks Discard whenever the card has any
    /// content"); otherwise it just closes. Picked values have already landed and never count.
    func asksBeforeSwipeClose(for task: TaskItem) -> Bool {
        hasPendingChanges(for: task)
    }

    /// What × (and Esc on the Mac) does (brief 41, George: "'X' should still ask Discard").
    enum CloseStep: Equatable {
        /// Show "Discard" above the footer; the typing stays until it is tapped.
        case askDiscard
        /// Close, dropping any typing.
        case close
    }

    /// × with typing Confirm would save asks Discard first, on the iPhone and the Mac alike; × again while
    /// asking is the Discard. With no typing it closes at once.
    func closeStep(for task: TaskItem, asking: Bool) -> CloseStep {
        !asking && hasPendingChanges(for: task) ? .askDiscard : .close
    }

    /// Confirm: saves what was typed. True if anything changed. The sub-task field's text becomes a sub-task;
    /// the field closes.
    @MainActor
    @discardableResult
    mutating func commit(to task: TaskItem, in context: ModelContext) throws -> Bool {
        var changed = false
        if let title = Self.titleToSave(title, current: task.title) {
            task.title = title
            changed = true
        }
        if let notes = notesToSave(for: task) {
            task.notes = notes
            changed = true
        }
        if let rename = renameToSave(for: task) {
            rename.subtask.title = rename.title
            rename.subtask.touch()
            changed = true
        }
        renaming = nil
        title = task.title
        notes = task.notes
        if changed {
            task.touch()
            try context.save()
        }
        if !Self.trimmed(newSubtask).isEmpty {
            try TaskActions.addSubtask(newSubtask, to: task, in: context)
            changed = true
        }
        newSubtask = ""
        isAddingSubtask = false
        return changed
    }

    // MARK: Sub-tasks

    mutating func startAddingSubtask() {
        isAddingSubtask = true
    }

    /// Return in the sub-task field: adds it and keeps the field open, empty, for the next; an empty
    /// Return closes the field. True if a sub-task was added.
    @MainActor
    @discardableResult
    mutating func submitNewSubtask(to task: TaskItem, in context: ModelContext) throws -> Bool {
        guard !Self.trimmed(newSubtask).isEmpty else {
            newSubtask = ""
            isAddingSubtask = false
            return false
        }
        try TaskActions.addSubtask(newSubtask, to: task, in: context)
        newSubtask = ""
        return true
    }

    mutating func beginRenaming(_ subtask: TaskItem) {
        renaming = Rename(id: subtask.id, text: subtask.title)
    }

    /// Return in a sub-task's title, or leaving it: the new name lands (a blank one keeps the old).
    @MainActor
    mutating func finishRenaming(in context: ModelContext) {
        guard let renaming else { return }
        self.renaming = nil
        let id = renaming.id
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        guard let subtask = try? context.fetch(descriptor).first,
              let title = Self.titleToSave(renaming.text, current: subtask.title) else { return }
        subtask.title = title
        subtask.touch()
        try? context.save()
    }
}
