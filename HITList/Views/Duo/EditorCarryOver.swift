import SwiftUI

/// The task editor's unconfirmed typing, kept above the shells so it outlives the editor's own view (brief 50).
///
/// On the iPhone Duo the editor is a sheet on the outer display and a column beside the list on the inner
/// one; folding or unfolding puts away one `TaskPopout` and builds another, which used to start from the task
/// as stored, so a title half typed on the outer display was gone once the phone opened (round 10's open
/// item). Each editor now writes its draft here as it changes, and the next editor for the same task starts
/// from it. `PopoutHost` owns one and tells it which task the editor shows (`editorShows`): closing the
/// editor (Confirm, ×, Discard, a swipe) or opening another task drops what was kept, so a reopened editor
/// starts fresh as before.
@MainActor
final class EditorCarryOver {
    struct Kept: Equatable {
        let taskID: UUID
        var draft: TaskEditorDraft
        /// The description field was open (typed into, or opened with the Description pill).
        var showsNotes: Bool
    }

    private(set) var kept: Kept?

    /// The editor for `task` has this typing now. With nothing left to confirm there is nothing to carry: what
    /// was kept goes, so a later editor starts from the task as stored, which may have changed since.
    func keep(_ draft: TaskEditorDraft, showsNotes: Bool, for task: TaskItem) {
        kept = draft.hasPendingChanges(for: task) ? Kept(taskID: task.id, draft: draft, showsNotes: showsNotes) : nil
    }

    /// What an earlier editor left for `taskID`, if anything.
    func kept(for taskID: UUID) -> Kept? {
        kept?.taskID == taskID ? kept : nil
    }

    /// The editor now shows `taskID` (nil: it closed). Anything kept for another task is dropped.
    func editorShows(_ taskID: UUID?) {
        if kept?.taskID != taskID { kept = nil }
    }

    /// Where a new editor for `task` starts: the typing an earlier editor left for it, else the task as stored.
    static func start(for task: TaskItem, from carryOver: EditorCarryOver?) -> (draft: TaskEditorDraft, showsNotes: Bool) {
        if let kept = carryOver?.kept(for: task.id) { return (kept.draft, kept.showsNotes || !task.notes.isEmpty) }
        return (TaskEditorDraft(task: task), !task.notes.isEmpty)
    }
}

extension EnvironmentValues {
    /// Set by `PopoutHost` around the shells, the editor sheet and the panel; nil elsewhere (tests, previews).
    @Entry var editorCarryOver: EditorCarryOver? = nil
}
