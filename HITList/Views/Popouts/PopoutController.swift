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
    /// A shared task open in its editor (brief 62): one task at a time, a shared one or one of yours.
    private(set) var sharedTask: SharedTaskRef?

    var isQuickAddOpen: Bool { quickAdd != nil }
    var isFloatingQuickAddOpen: Bool { quickAdd?.placement == .floating }
    var isQuickAddClosing: Bool { quickAdd?.isClosing == true }
    var isTaskOpen: Bool { taskID != nil }
    var isSharedTaskOpen: Bool { sharedTask != nil }
    /// The floating "+" hides while anything is popped out.
    var showsAddButton: Bool { quickAdd == nil && taskID == nil && sharedTask == nil }

    func isInlineOpen(_ key: String) -> Bool { quickAdd?.placement == .inline(key) }

    /// A new card, unless `id` names one being put back after a relaunch.
    mutating func openQuickAdd(_ context: QuickAddContext, placement: Placement = .floating, id: UUID = UUID()) {
        taskID = nil
        sharedTask = nil
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
        sharedTask = nil
        taskID = id
    }

    mutating func closeTask() {
        taskID = nil
    }

    mutating func openSharedTask(_ ref: SharedTaskRef) {
        quickAdd = nil
        taskID = nil
        sharedTask = ref
    }

    mutating func closeSharedTask() {
        sharedTask = nil
    }

    mutating func closeAll() {
        quickAdd = nil
        taskID = nil
        sharedTask = nil
    }
}

/// A task of a shared list, by its id and its list's (brief 62).
struct SharedTaskRef: Hashable, Identifiable {
    let taskID: UUID
    let listID: UUID
    var id: UUID { taskID }

    init(taskID: UUID, listID: UUID) {
        self.taskID = taskID
        self.listID = listID
    }

    init(_ row: SharedRow) {
        self.init(taskID: row.id, listID: row.listID)
    }
}

/// What a list's selection holds (briefs 62, 64): a task of yours or a shared task; the popout host draws the editor
/// of either.
enum ListSelection: Hashable {
    case task(TaskItem)
    case shared(SharedTaskRef)
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

    /// The shared tasks (brief 64): completing and undoing one from its editor; tests pass their own.
    @ObservationIgnored let sharedRows: SharedRows

    init(draftDefaults: UserDefaults = AppGroup.defaults, center: NotificationCenter = .default, sharedRows: SharedRows = .shared) {
        self.draftDefaults = draftDefaults
        self.sharedRows = sharedRows
        // Another Apple account took over this device (`AccountSwitch`): nothing the previous person typed
        // or completed stays on screen for the next one.
        accountObserver = center.addObserver(forName: .accountDidSwitch, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accountDidSwitch() }
        }
        // Claude completed a task through the connector (brief 43): the same Undo toast a completion in the
        // app shows, so it is one click from undone (brief 49).
        claudeObserver = center.addObserver(forName: .claudeDidCompleteTask, object: nil, queue: .main) { [weak self] note in
            guard let record = note.userInfo?[ClaudeConnector.completedTaskKey] as? CompletedTask else { return }
            MainActor.assumeIsolated { self?.showToast(record) }
        }
    }

    /// Live as long as the controller (one per window); the blocks hold it weakly.
    @ObservationIgnored private var accountObserver: NSObjectProtocol?
    @ObservationIgnored private var claudeObserver: NSObjectProtocol?

    /// Closes every popout (the card's stored draft goes with it) and drops the undo toasts without undoing.
    func accountDidSwitch() {
        closeAll()
        _ = toast.takeAll()
        listToast = nil
    }
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
        /// The list's side margin (`listMargin`), for the toast to start on its rows' left edge (brief 114: on the
        /// Duo's outer display it sat 15.5 pt in, the rows 20); nil keeps the island's side inset.
        var margin: CGFloat? = nil
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
        requestDelete(title: task.title, perform: perform)
    }

    /// The same for a task known by its title alone (a shared task, brief 62).
    func requestDelete(title: String, perform: @escaping () -> Void) {
        if Preferences.value(Preferences.confirmDelete, default: Preferences.confirmDeleteDefault) {
            pendingDelete = PendingDelete(title: title, perform: perform)
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
        #if DEBUG
        if openDebugInlineCard() { return true }
        #endif
        guard state.quickAdd == nil, let stored = QuickAddDraftStore.load(from: draftDefaults),
              !Self.liveCards.contains(stored.cardID) else { return false }
        task = nil
        update { $0.openQuickAdd(stored.draft.context, placement: .floating, id: stored.cardID) }
        return true
    }

    #if DEBUG
    /// Developer aid for window captures without clicks (brief 49), Debug builds only: launched with
    /// `-debugInlineCard "Call Sam"`, the list's inline "Add task" card (key "list") opens with that typed in;
    /// `-debugAskDiscard YES` has it ask "Discard this task?" at once (`InlineAddRow`).
    static var debugInlineCardText: String? { UserDefaults.standard.string(forKey: "debugInlineCard") }
    static var debugAsksDiscard: Bool { UserDefaults.standard.bool(forKey: "debugAskDiscard") }

    private func openDebugInlineCard() -> Bool {
        guard state.quickAdd == nil, let text = Self.debugInlineCardText else { return false }
        let id = UUID()
        update { $0.openQuickAdd(listContext, placement: .inline("list"), id: id) }
        QuickAddDraftStore.save(QuickAddDraft(context: listContext, text: text), card: id, to: draftDefaults)
        return true
    }
    #endif

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

    // MARK: Shared task (briefs 62, 64)

    /// Opens a shared task's editor (`SharedTaskPopout`), which `PopoutHost` draws as it draws yours: the panel on the
    /// Mac and iPad, the sheet on the iPhone.
    func openShared(_ ref: SharedTaskRef) {
        task = nil
        update { $0.openSharedTask(ref) }
    }

    func closeSharedTask() {
        update { $0.closeSharedTask() }
    }

    /// Completes a shared task from its editor (who: me, when: now), closes it and shows the toast, whose Undo reopens
    /// it for everyone (`undoCompletions`).
    func completeShared(_ row: SharedRow) throws {
        try sharedRows.setCompleted(true, row)
        if state.sharedTask?.taskID == row.id { closeSharedTask() }
        showToast(CompletedTask(id: row.id, title: row.filterTitle, revert: .uncomplete))
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
        showToast(CompletedTask(id: task.id, title: task.title, revert: revert))
    }

    /// "Completed ‘Title’ · Undo" for a completion that has already been saved (from a popout, or by Claude),
    /// gone after `CompletionToastState.lifetime` unless another completion joins it.
    func showToast(_ record: CompletedTask) {
        let generation = withAnimation(HITMotion.enter) { toast.add(record) }
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
            if let shared = sharedRows.row(record.id) {
                // A shared task completed from its editor: reopened in the shared store, so the others see it back.
                if shared.task.isCompleted { try? sharedRows.setCompleted(false, shared) }
                continue
            }
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

    /// The same for lists that show shared tasks among yours (briefs 62, 64): selecting a shared row opens its editor,
    /// and the row stays highlighted while it is open.
    var listSelection: Binding<ListSelection?> {
        Binding(
            get: {
                if let task = self.task { return .task(task) }
                return self.state.sharedTask.map(ListSelection.shared)
            },
            set: { picked in
                switch picked {
                case .task(let task)?: self.open(task)
                case .shared(let ref)?: self.openShared(ref)
                case nil:
                    self.closeTask()
                    self.closeSharedTask()
                }
            }
        )
    }
}

extension FocusedValues {
    /// The focused window's popouts, for the New Task command (⌘N).
    @Entry var popouts: PopoutController?
}
