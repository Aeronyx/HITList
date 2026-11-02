import Foundation

/// Where a just-completed row is in its animation; see `CompletionAnimator`.
enum CompletionPhase: Equatable {
    case pending
    case animating
}

/// The life of a row the user just completed. The task is saved as complete at once (so sync isn't
/// delayed), which usually means it stops matching the list's filter; the list keeps showing every
/// row the animator holds until its animation ends.
///
/// `pending` (check pops, title strikes through, row flashes) → `animating` (row fades and collapses)
/// → removed (no entry; the list drops the row). `cancel` (undo) ends a row at any point. Each
/// `begin` hands out a token; transitions carry it, so a timer left over from an earlier completion
/// of the same task, or one that fires after a cancel, does nothing.
///
/// `Anchor` is whatever the list needs to keep the row in place (TaskListView: the due date at tap time).
struct CompletionAnimator<Anchor> {
    private struct Entry {
        var phase: CompletionPhase
        let token: Int
        let anchor: Anchor
    }

    private var entries: [UUID: Entry] = [:]
    private var lastToken = 0

    /// Nil once the row is removed (or was never completed here).
    func phase(of id: UUID) -> CompletionPhase? { entries[id]?.phase }

    var heldIDs: Set<UUID> { Set(entries.keys) }
    var anchors: [UUID: Anchor] { entries.mapValues(\.anchor) }
    var isEmpty: Bool { entries.isEmpty }

    /// Starts (or restarts) a row's animation. Returns the token its timers must present.
    mutating func begin(_ id: UUID, anchor: Anchor) -> Int {
        lastToken += 1
        entries[id] = Entry(phase: .pending, token: lastToken, anchor: anchor)
        return lastToken
    }

    /// pending → animating. False if the row was cancelled or restarted since `token` was issued.
    @discardableResult
    mutating func collapse(_ id: UUID, token: Int) -> Bool {
        guard let entry = entries[id], entry.token == token, entry.phase == .pending else { return false }
        entries[id]?.phase = .animating
        return true
    }

    /// Ends the animation and releases the row. Allowed straight from `pending` for a row that still
    /// belongs in the list (showing completed tasks), which has nothing to collapse.
    @discardableResult
    mutating func remove(_ id: UUID, token: Int) -> Bool {
        guard entries[id]?.token == token else { return false }
        entries[id] = nil
        return true
    }

    /// Undo: releases the row whatever its phase. False if it wasn't held.
    @discardableResult
    mutating func cancel(_ id: UUID) -> Bool {
        entries.removeValue(forKey: id) != nil
    }

    mutating func cancelAll() { entries.removeAll() }

    /// What a tap on a row's checkbox does. Completing is final until Undo (George, 2026-11-02): a row
    /// still in its completion animation ignores taps (a second tap used to undo it), and only a task
    /// that is actually showing as completed (the Completed list, Show completed) unchecks. When the
    /// toast still lists that task, unchecking goes through the toast's record (`undoable`), which knows
    /// how to put a recurring task's date back.
    func tap(on id: UUID, isCompleted: Bool, undoable: Bool) -> CompletionTap {
        if phase(of: id) != nil { return .ignore }
        if isCompleted { return undoable ? .undo : .uncheck }
        return .complete
    }
}

/// The outcome of tapping a row's checkbox; see `CompletionAnimator.tap(on:isCompleted:undoable:)`.
enum CompletionTap: Equatable {
    /// The row is animating out: nothing happens. Undo is the toast's.
    case ignore
    /// Save it as complete and start the animation.
    case complete
    /// A completed task shown as completed: mark it incomplete.
    case uncheck
    /// A completed task the toast still offers to undo: undo it through the toast's record.
    case undo
}
