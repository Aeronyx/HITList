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
        /// iPhone: the card is being put away (fading while it rides the keyboard down); the host removes
        /// it when the keyboard has gone.
        var isClosing = false
    }

    private(set) var quickAdd: QuickAdd?
    private(set) var taskID: UUID?

    var isQuickAddOpen: Bool { quickAdd != nil }
    var isFloatingQuickAddOpen: Bool { quickAdd?.placement == .floating }
    var isQuickAddClosing: Bool { quickAdd?.isClosing == true }
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

    /// Starts putting the card away; `closeQuickAdd` finishes it.
    mutating func beginClosingQuickAdd() {
        quickAdd?.isClosing = true
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
    /// iPhone: the undo toast the list on screen is showing, which `PopoutHost` draws (`completionToast`).
    private(set) var listToast: ListToast?

    /// A list's toast as `PopoutHost` draws it. `owner` is the list that showed it, so a list leaving
    /// the screen only takes down its own.
    struct ListToast {
        let owner: UUID
        let message: String
        let undo: () -> Void
    }
    /// A deletion waiting for the user's yes (Settings → General → Confirm before deleting); `PopoutHost`
    /// shows the dialog. Nil when nothing is pending.
    private(set) var pendingDelete: PendingDelete?

    struct PendingDelete {
        let title: String
        let perform: () -> Void
    }

    // MARK: Delete

    /// Every delete path comes through here with what deleting means for it (`perform`): it runs at
    /// once, or after the confirmation dialog when the preference asks for one.
    func requestDelete(_ task: TaskItem, perform: @escaping () -> Void) {
        if Preferences.value(Preferences.confirmDelete, default: Preferences.confirmDeleteDefault) {
            pendingDelete = PendingDelete(title: task.title, perform: perform)
        } else {
            perform()
        }
    }

    func confirmPendingDelete() {
        let pending = pendingDelete
        pendingDelete = nil
        pending?.perform()
    }

    func cancelPendingDelete() { pendingDelete = nil }

    // MARK: Quick add

    func openQuickAdd(_ context: QuickAddContext? = nil, placement: PopoutState.Placement = .floating) {
        task = nil
        state.openQuickAdd(context ?? listContext, placement: placement)
    }

    func closeQuickAdd() { state.closeQuickAdd() }
    func beginClosingQuickAdd() { state.beginClosingQuickAdd() }
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

    /// Closes the popout if its task no longer exists: deleted on another device (arriving with a sync
    /// import), in another window, or by a script (George, 2026-11-02). True if it closed. `PopoutHost`
    /// calls it when its query for the task comes back empty and after every import.
    ///
    /// The model the popout holds can't be asked: after another context's deletion is merged it still
    /// says `isDeleted == false` and keeps its context (`PopoutTests`), so this asks the store, by the
    /// id kept in `state` (never reading the possibly gone model's attributes).
    @discardableResult
    func closeTaskIfDeleted(in context: ModelContext) -> Bool {
        guard let id = state.taskID else { return false }
        let deletedHere = task?.isDeleted == true
        guard deletedHere || !Self.taskExists(id, in: context) else { return false }
        // At once, without the panel's fade: nothing should draw a task that is gone.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { closeTask() }
        return true
    }

    /// Whether a task with this id is in the store or pending insertion (and not pending deletion). A
    /// failed fetch counts as present, so a hiccup never closes a popout.
    static func taskExists(_ id: UUID, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        return ((try? context.fetchCount(descriptor)) ?? 1) > 0
    }

    /// Completes a task from its popout: saves, closes the popout, and shows the undo toast. (The
    /// popout has already played the check and the completion feedback.)
    func complete(_ task: TaskItem, in context: ModelContext) {
        let revert: CompletedTask.Revert = if task.recurrenceRule != nil, let due = task.dueDate {
            .restoreDueDate(due)
        } else {
            .uncomplete
        }
        TaskActions.toggleCompletion(task, in: context)
        Task { await NotificationScheduler.reschedule(context: context) }
        if self.task?.id == task.id { closeTask() }
        let generation = withAnimation(HITMotion.enter) { toast.add(CompletedTask(id: task.id, title: task.title, revert: revert)) }
        AccessibilityNotification.Announcement(toast.message).post()
        Task {
            try? await Task.sleep(for: CompletionToastState.lifetime)
            withAnimation(HITMotion.exit) { _ = toast.expire(generation: generation) }
        }
    }

    /// ⌘← / ⌘→ and the popout's "A day earlier / later": the task's due day moves by `offset` days,
    /// keeping its time of day. An undated task counts from today. Completed tasks stay put.
    func shiftDay(_ task: TaskItem, by offset: Int, in context: ModelContext, now: Date = Date()) {
        guard !task.isCompleted else { return }
        let day = TaskRescheduling.day(offset, from: task.dueDate, now: now)
        TaskActions.reschedule(task, to: day, in: context)
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    // MARK: List toasts (iPhone)

    /// A list's toast appeared or changed ("2 completed"); it replaces any other list's.
    func showListToast(_ toast: ListToast) {
        listToast = toast
    }

    /// The list's toast went away (expired, undone, or the list left the screen).
    func hideListToast(owner: UUID) {
        if listToast?.owner == owner { listToast = nil }
    }

    /// The toast's Undo: puts every task it lists back as it was.
    func undoCompletions(in context: ModelContext) {
        let records = withAnimation(HITMotion.exit) { toast.takeAll() }
        for record in records {
            let id = record.id
            guard let task = try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first else { continue }
            switch record.revert {
            case .uncomplete:
                if task.isCompleted { TaskActions.toggleCompletion(task, in: context) }
            case .restoreDueDate(let due):
                // Not toggleCompletion: on a recurring task that would advance the date again.
                TaskActions.reschedule(task, to: due, keepTime: false, in: context)
            }
        }
        Task { await NotificationScheduler.reschedule(context: context) }
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
