import SwiftUI
import SwiftData
import HITListCore

/// The inbox: every dated task (in any Group) plus undated tasks with no Group, as one list by priority
/// then due date (`TaskOrdering`), under an "Inbox · 7" header, with an "Inbox zero" state when it's
/// empty and a Process button that steps through it one task at a time. Undated tasks in a Group are
/// notes and stay in their Group. Rows, completion, and the undo toast behave as in every other list.
struct InboxView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PopoutController.self) private var popouts
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @State private var showCompleted = false
    @State private var now = Date()
    /// Rows animating out after a completion, each anchored at the due date it had when tapped.
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()
    @State private var processing = false

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// A row's task and the due date it is listed under: its own, or while its completion animates,
    /// the one it had when tapped (a completed recurring task has already moved to its next date).
    private struct Placed: FilterableTask {
        let task: TaskItem
        let filterDueDate: Date?
        var filterTitle: String { task.filterTitle }
        var filterNotes: String { task.filterNotes }
        var filterPriority: Int { task.filterPriority }
        var filterHasDueTime: Bool { task.filterHasDueTime }
        var filterIsCompleted: Bool { task.filterIsCompleted }
        var filterProjectName: String? { task.filterProjectName }
        var filterLabelNames: [String] { task.filterLabelNames }
        var filterIsRecurring: Bool { task.filterIsRecurring }
    }

    private func matchedTasks() -> [TaskItem] {
        TaskOrdering.inbox(allTasks, includeCompleted: showCompleted)
    }

    /// Open inbox tasks, for the header.
    private var openCount: Int { allTasks.filter(\.isInInbox).count }

    /// The matched tasks plus the recently completed ones, by priority then due date.
    private var rows: [TaskItem] {
        let matched = matchedTasks()
        guard !completions.isEmpty else { return matched }
        let held = completions.heldIDs
        let anchors = completions.anchors
        let shown = matched.filter { !held.contains($0.id) }.map { Placed(task: $0, filterDueDate: $0.dueDate) }
        let animating = allTasks.compactMap { task in anchors[task.id].map { Placed(task: task, filterDueDate: $0) } }
        return TaskOrdering.sorted(shown + animating).map(\.task)
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            header
            SwiftUI.Group {
                if rows.isEmpty {
                    InboxZeroView()
                        .transition(.opacity)
                } else {
                    list(rows)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if toast.isVisible {
                    CompletionToast(message: toast.message, onUndo: undoToast)
                        .transition(CompletionMotion.toastTransition(reduceMotion: reduceMotion))
                }
            }
        }
        .quickAddEntry(.inbox)
        .background(Theme.background)
        .navigationTitle("Inbox")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { processing = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.and.arrow.down")
                        Text("Process")
                    }
                }
                .accessibilityLabel("Process")
                .disabled(openCount == 0)
                .help("Go through the inbox one task at a time")
            }
        }
        #endif
        // iPhone and iPad: Show completed behind the filter-lines icon, Process in the "…" beside it.
        .screenChrome {
            ViewOptionsMenu {
                Toggle("Show completed", isOn: $showCompleted)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        } menu: {
            Button { processing = true } label: { Label("Process…", systemImage: "tray.and.arrow.down") }
                .disabled(openCount == 0)
        }
        .sheet(isPresented: $processing) {
            InboxProcessView(selectedTask: $selectedTask)
        }
        .onReceive(clock) { now = $0 }
        .onAppear { CompletionFeedback.shared.prepare() }
    }

    private var header: some View {
        Text(InboxText.header(count: openCount))
            .font(HITType.title2Bold)
            .contentTransition(.numericText(value: Double(openCount)))
            .animation(reduceMotion ? nil : .snappy, value: openCount)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Inbox, \(openCount) \(openCount == 1 ? "task" : "tasks")")
    }

    private func list(_ rows: [TaskItem]) -> some View {
        List(selection: $selectedTask) {
            Section {
                ForEach(rows) { row($0) }
            }
            Section { InlineAddRow(context: .inbox, key: "inbox") }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .slateList()
    }

    private func row(_ task: TaskItem) -> some View {
        let phase = completions.phase(of: task.id)
        return TaskRow(task: task, now: now, completionPhase: phase, onToggleCompletion: { toggleCompletion(task) })
            .opacity(phase == .animating ? 0 : 1)
            .tag(task)
            .completionRowBackground(flashing: phase == .pending)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    popouts.requestDelete(task) {
                        if selectedTask?.id == task.id { selectedTask = nil }
                        TaskActions.delete(task, in: context)
                    }
                } label: { Label("Delete", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                Button {
                    TaskActions.reschedule(task, to: TaskRescheduling.QuickDate.tomorrow.date(now: now), in: context)
                    Task { await NotificationScheduler.reschedule(context: context) }
                } label: { Label("Tomorrow", systemImage: "sunrise") }
                .tint(.orange)
            }
    }

    // MARK: - Completion (the same behaviour as TaskListView)

    private func toggleCompletion(_ task: TaskItem) {
        let checked = task.isCompleted || completions.phase(of: task.id) != nil
        if checked, let record = toast.record(for: task.id) {
            withAnimation(HITMotion.exit) { toast.remove(task.id) }
            revert([record])
            return
        }
        if task.isCompleted {
            withAnimation(HITMotion.standard) {
                completions.cancel(task.id)
                TaskActions.toggleCompletion(task, in: context)
            }
            return
        }
        // A recurring task mid-animation already advanced; a second tap must not advance it again.
        guard completions.phase(of: task.id) == nil else { return }

        let revert: CompletedTask.Revert = if task.recurrenceRule != nil, let due = task.dueDate {
            .restoreDueDate(due)
        } else {
            .uncomplete
        }
        let token = withAnimation(HITMotion.quick) { completions.begin(task.id, anchor: task.dueDate) }
        TaskActions.toggleCompletion(task, in: context)
        CompletionFeedback.shared.taskCompleted()
        Task { await finishCompletion(of: task.id, token: token) }
        showToast(CompletedTask(id: task.id, title: task.title, revert: revert))
    }

    private func showToast(_ completed: CompletedTask) {
        let generation = withAnimation(HITMotion.enter) { toast.add(completed) }
        AccessibilityNotification.Announcement(toast.message).post()
        Task {
            try? await Task.sleep(for: CompletionToastState.lifetime)
            withAnimation(HITMotion.exit) { _ = toast.expire(generation: generation) }
        }
    }

    private func undoToast() {
        let records = withAnimation(HITMotion.exit) { toast.takeAll() }
        revert(records)
    }

    private func revert(_ records: [CompletedTask]) {
        withAnimation(HITMotion.standard) {
            for record in records {
                completions.cancel(record.id)
                guard let task = allTasks.first(where: { $0.id == record.id }) else { continue }
                switch record.revert {
                case .uncomplete:
                    if task.isCompleted { TaskActions.toggleCompletion(task, in: context) }
                case .restoreDueDate(let due):
                    TaskActions.reschedule(task, to: due, keepTime: false, in: context)
                }
            }
        }
    }

    /// Check, strike and flash, then the row fades and the gap closes; with Show Completed on it just
    /// settles. When it was the last task, the list gives way to "Inbox zero" once the row is gone.
    private func finishCompletion(of id: UUID, token: Int) async {
        try? await Task.sleep(for: .milliseconds(600))
        if matchedTasks().contains(where: { $0.id == id }) {
            withAnimation(HITMotion.standard) { _ = completions.remove(id, token: token) }
            return
        }
        guard withAnimation(HITMotion.exit, { completions.collapse(id, token: token) }) else { return }
        try? await Task.sleep(for: .milliseconds(180))
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { _ = completions.remove(id, token: token) }
        } else {
            withAnimation(HITMotion.standard) { _ = completions.remove(id, token: token) }
        }
    }
}
