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
        /// Which card this is: its stored draft (`QuickAddDraftStore`) belongs to it and to no other.
        var id = UUID()
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

    /// A new card, unless `id` names one being put back after a relaunch.
    mutating func openQuickAdd(_ context: QuickAddContext, placement: Placement = .floating, id: UUID = UUID()) {
        taskID = nil
        quickAdd = QuickAdd(id: id, context: context, placement: placement)
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
    /// Changed only through `update`, which keeps the stored quick-add draft in step with the card.
    private(set) var state = PopoutState()
    /// Where the open card's draft is kept (`QuickAddDraftStore`); tests pass their own.
    @ObservationIgnored let draftDefaults: UserDefaults
    /// The quick-add cards open in this process, in any window, so a second Mac window does not open
    /// the same stored card again.
    private static var liveCards: Set<UUID> = []

    init(draftDefaults: UserDefaults = AppGroup.defaults) {
        self.draftDefaults = draftDefaults
    }
    /// The task the task popout shows; kept in step with `state.taskID`.
    private(set) var task: TaskItem?
    /// The list on screen, so ⌘N and the toolbar "+" add into it.
    var listContext: QuickAddContext = .today
    /// "Completed ‘Title’ · Undo" after completing a task from its popout (the lists keep their own).
    var toast = CompletionToastState()
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

    /// A fresh card: it starts empty, whatever is stored (only the card that was open gets that back).
    func openQuickAdd(_ context: QuickAddContext? = nil, placement: PopoutState.Placement = .floating) {
        task = nil
        update { $0.openQuickAdd(context ?? listContext, placement: placement) }
    }

    func closeQuickAdd() { update { $0.closeQuickAdd() } }
    func beginClosingQuickAdd() { update { $0.beginClosingQuickAdd() } }
    func closeInline(_ key: String) { update { $0.closeInline(key) } }
    func didSave() { update { $0.didSave() } }

    /// iPhone's Discard: the draft goes at once, before the card has finished fading.
    func discardQuickAddDraft() {
        if let id = state.quickAdd?.id { QuickAddDraftStore.clear(card: id, from: draftDefaults) }
    }

    /// Launch, and each new Mac window: if the app was killed (or quit) with a quick-add card open and
    /// something in it, that card opens again, floating, in the list it belonged to, with everything it
    /// held (the card reads it back by its id). Nothing happens if a card is already up here, or the
    /// stored card is open in another window.
    @discardableResult
    func reopenStoredQuickAdd() -> Bool {
        for key in Preferences.legacyQuickAddDraftKeys { draftDefaults.removeObject(forKey: key) }
        guard state.quickAdd == nil, let stored = QuickAddDraftStore.load(from: draftDefaults),
              !Self.liveCards.contains(stored.cardID) else { return false }
        task = nil
        update { $0.openQuickAdd(stored.draft.context, placement: .floating, id: stored.cardID) }
        return true
    }

    /// The window is going away (Mac): its card is no longer live here, but its draft stays stored, so
    /// the next window, or the next launch, opens it again.
    func windowClosed() {
        if let id = state.quickAdd?.id { Self.liveCards.remove(id) }
    }

    /// Every change to what is popped out goes through here: when a quick-add card goes (closed, replaced
    /// by another card or by a task), its stored draft goes with it.
    private func update(_ change: (inout PopoutState) -> Void) {
        let before = state.quickAdd?.id
        change(&state)
        let after = state.quickAdd?.id
        guard before != after else { return }
        if let before {
            Self.liveCards.remove(before)
            QuickAddDraftStore.clear(card: before, from: draftDefaults)
        }
        if let after { Self.liveCards.insert(after) }
    }

    // MARK: Task

    func open(_ task: TaskItem) {
        self.task = task
        update { $0.openTask(task.id) }
    }

    func closeTask() {
        task = nil
        update { $0.closeTask() }
    }

    func closeAll() {
        task = nil
        update { $0.closeAll() }
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
