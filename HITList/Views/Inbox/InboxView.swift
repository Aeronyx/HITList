import SwiftUI
import SwiftData
import HITListCore

/// The inbox: tasks without a project, under an "Inbox · 7" header, with an "Inbox zero" state when
/// it's empty. Rows, completion, and the undo toast behave as in every other task list.
struct InboxView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @State private var showCompleted = false
    @State private var now = Date()
    /// Rows animating out after a completion, each anchored at the due date it had when tapped.
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// The same query the sidebar's Inbox has always meant.
    private static let query = "no project"

    private struct Group: Identifiable {
        let id: String
        let tasks: [TaskItem]
    }

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
        let source = showCompleted ? "(\(Self.query)) & (completed | !completed)" : Self.query
        return (try? FilterQuery(source, now: now).apply(to: allTasks, now: now)) ?? []
    }

    /// Open inbox tasks, for the header.
    private var openCount: Int { allTasks.filter { $0.project == nil && !$0.isCompleted }.count }

    /// The matched tasks plus the recently completed ones, grouped by due day in list order.
    private var groups: [Group] {
        let matched = matchedTasks()
        let rows: [Placed]
        if completions.isEmpty {
            rows = matched.map { Placed(task: $0, filterDueDate: $0.dueDate) }
        } else {
            let held = completions.heldIDs
            let anchors = completions.anchors
            let shown = matched.filter { !held.contains($0.id) }.map { Placed(task: $0, filterDueDate: $0.dueDate) }
            let animating = allTasks.compactMap { task in anchors[task.id].map { Placed(task: task, filterDueDate: $0) } }
            rows = FilterQuery.defaultSort(shown + animating)
        }
        var groups: [Group] = []
        for row in rows {
            let key = DueFormatter.sectionTitle(for: row.filterDueDate, now: now)
            if let i = groups.firstIndex(where: { $0.id == key }) {
                groups[i] = Group(id: key, tasks: groups[i].tasks + [row.task])
            } else {
                groups.append(Group(id: key, tasks: [row.task]))
            }
        }
        return groups
    }

    var body: some View {
        let groups = groups
        VStack(spacing: 0) {
            header
            SwiftUI.Group {
                if groups.isEmpty {
                    InboxZeroView()
                        .transition(.opacity)
                } else {
                    list(groups)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if toast.isVisible {
                    CompletionToast(message: toast.message, onUndo: undoToast)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }

            Divider()
            QuickAddBar(defaultProject: nil, defaultLabel: nil)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Theme.surface)
        }
        .background(Theme.background)
        .navigationTitle("Inbox")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $showCompleted) {
                    Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash")
                        .labelStyle(.iconOnly)
                        .imageScale(.medium)
                        .font(.body)
                }
                .toggleStyle(.button)
                .help("Show completed tasks")
            }
        }
        .onReceive(clock) { now = $0 }
        .onAppear { CompletionFeedback.shared.prepare() }
    }

    private var header: some View {
        Text(InboxText.header(count: openCount))
            .font(.title2.weight(.bold))
            .contentTransition(.numericText(value: Double(openCount)))
            .animation(reduceMotion ? nil : .snappy, value: openCount)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Inbox, \(openCount) \(openCount == 1 ? "task" : "tasks")")
    }

    private func list(_ groups: [Group]) -> some View {
        List(selection: $selectedTask) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.tasks) { row($0) }
                } header: {
                    Text(group.id)
                        .foregroundStyle(group.id == "Overdue" ? .red : .secondary)
                }
            }
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
                    if selectedTask?.id == task.id { selectedTask = nil }
                    TaskActions.delete(task, in: context)
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
            withAnimation(.snappy) { toast.remove(task.id) }
            revert([record])
            return
        }
        if task.isCompleted {
            withAnimation(.easeInOut(duration: 0.25)) {
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
        let token = withAnimation(.easeOut(duration: 0.12)) { completions.begin(task.id, anchor: task.dueDate) }
        TaskActions.toggleCompletion(task, in: context)
        CompletionFeedback.shared.taskCompleted()
        Task { await finishCompletion(of: task.id, token: token) }
        showToast(CompletedTask(id: task.id, title: task.title, revert: revert))
    }

    private func showToast(_ completed: CompletedTask) {
        let generation = withAnimation(.snappy) { toast.add(completed) }
        AccessibilityNotification.Announcement(toast.message).post()
        Task {
            try? await Task.sleep(for: CompletionToastState.lifetime)
            withAnimation(.easeOut(duration: 0.25)) { _ = toast.expire(generation: generation) }
        }
    }

    private func undoToast() {
        let records = withAnimation(.snappy) { toast.takeAll() }
        revert(records)
    }

    private func revert(_ records: [CompletedTask]) {
        withAnimation(.easeInOut(duration: 0.25)) {
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
            withAnimation(.easeOut(duration: 0.25)) { _ = completions.remove(id, token: token) }
            return
        }
        guard withAnimation(.easeIn(duration: 0.18), { completions.collapse(id, token: token) }) else { return }
        try? await Task.sleep(for: .milliseconds(180))
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { _ = completions.remove(id, token: token) }
        } else {
            withAnimation(.snappy(duration: 0.3)) { _ = completions.remove(id, token: token) }
        }
    }
}
