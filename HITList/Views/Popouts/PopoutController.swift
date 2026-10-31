import SwiftUI
import SwiftData
import HITListCore

/// What is popped out over the lists, as plain values so tests can drive it: at most one quick-add card
/// (floating, or expanded in place inside a list) and at most one task. Opening one closes the other.
struct PopoutState: Equatable {
    /// Where the quick-add card shows.
    enum Placement: Hashable {
        /// iPhone: docked above the keyboard. Mac and iPad: the panel near the top of the window.
        case floating
        /// Expanded in place of the "Add task" row whose key this is (the Mac's inline add).
        case inline(String)
    }

    /// One open quick-add card. `savedCount` counts the tasks added without closing it.
    struct QuickAdd: Equatable {
        var context: QuickAddContext
        var placement: Placement
        var savedCount = 0
    }

    private(set) var quickAdd: QuickAdd?
    private(set) var taskID: UUID?

    var isQuickAddOpen: Bool { quickAdd != nil }
    var isFloatingQuickAddOpen: Bool { quickAdd?.placement == .floating }
    var isTaskOpen: Bool { taskID != nil }
    /// The floating "+" hides while anything is popped out.
    var showsAddButton: Bool { quickAdd == nil && taskID == nil }

    func isInlineOpen(_ key: String) -> Bool { quickAdd?.placement == .inline(key) }

    mutating func openQuickAdd(_ context: QuickAddContext, placement: Placement = .floating) {
        taskID = nil
        quickAdd = QuickAdd(context: context, placement: placement)
    }

    /// A task was added: the card stays open (empty) for the next one.
    mutating func didSave() {
        quickAdd?.savedCount += 1
    }

    mutating func closeQuickAdd() {
        quickAdd = nil
    }

    /// Closes the inline card only if it is the one at `key` (another row may have opened since).
    mutating func closeInline(_ key: String) {
        if isInlineOpen(key) { quickAdd = nil }
    }

    mutating func openTask(_ id: UUID) {
        quickAdd = nil
        taskID = id
    }

    mutating func closeTask() {
        taskID = nil
    }

    mutating func closeAll() {
        quickAdd = nil
        taskID = nil
    }
}

/// The one presenter for HITList's popouts, shared through the environment by every list (Today,
/// projects, labels, filters, Inbox, Upcoming, Flipboard). `ContentView` owns it and draws the popouts.
@MainActor
@Observable
final class PopoutController {
    private(set) var state = PopoutState()
    /// The task the task popout shows; kept in step with `state.taskID`.
    private(set) var task: TaskItem?
    /// The list on screen, so ⌘N and the toolbar "+" add into it.
    var listContext: QuickAddContext = .today
    /// "Completed ‘Title’ · Undo" after completing a task from its popout (the lists keep their own).
    var toast = CompletionToastState()

    // MARK: Quick add

    func openQuickAdd(_ context: QuickAddContext? = nil, placement: PopoutState.Placement = .floating) {
        task = nil
        state.openQuickAdd(context ?? listContext, placement: placement)
    }

    func closeQuickAdd() { state.closeQuickAdd() }
    func closeInline(_ key: String) { state.closeInline(key) }
    func didSave() { state.didSave() }

    // MARK: Task

    func open(_ task: TaskItem) {
        self.task = task
        state.openTask(task.id)
    }

    func closeTask() {
        task = nil
        state.closeTask()
    }

    func closeAll() {
        task = nil
        state.closeAll()
    }

    /// For lists that select rows (`List(selection:)`): selecting a row presents its popout, and the
    /// selection reads back as the task on show, so the row stays highlighted while it is open.
    var selection: Binding<TaskItem?> {
        Binding(
            get: { self.task },
            set: { picked in
                if let picked { self.open(picked) } else { self.closeTask() }
            }
        )
    }
}

extension FocusedValues {
    /// The focused window's popouts, for the New Task command (⌘N).
    @Entry var popouts: PopoutController?
}
