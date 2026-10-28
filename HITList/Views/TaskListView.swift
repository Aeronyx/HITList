import SwiftUI
import SwiftData
import HITListCore

struct TaskListView: View {
    let selection: SidebarItem
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query private var projects: [Project]
    @Query private var labels: [TaskLabel]
    @Query private var filters: [SavedFilter]
    @State private var showCompleted = false
    @State private var now = Date()
    /// Rows animating out after a completion, each anchored at the due date it had when tapped.
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var currentProject: Project? {
        if case .project(let id) = selection { return projects.first { $0.id == id } }
        return nil
    }
    private var currentLabel: TaskLabel? {
        if case .label(let id) = selection { return labels.first { $0.id == id } }
        return nil
    }
    private var currentFilter: SavedFilter? {
        if case .filter(let id) = selection { return filters.first { $0.id == id } }
        return nil
    }

    private var title: String {
        switch selection {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        case .filter: return currentFilter?.name ?? "Filter"
        case .project: return currentProject?.name ?? "Project"
        case .label: return currentLabel.map { "@" + $0.name } ?? "Label"
        }
    }

    /// The filter-language query behind each sidebar item. Smart views are just saved queries.
    private var queryString: String {
        switch selection {
        case .inbox: return "no project"
        case .today: return "overdue | today"
        case .upcoming: return "due after: today"
        case .completed: return "completed"
        case .filter: return currentFilter?.query ?? "all"
        case .project: return currentProject.map { "#\"\($0.name)\"" } ?? "all"
        case .label: return currentLabel.map { "@\"\($0.name)\"" } ?? "all"
        }
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
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

    /// Tasks completed here in the last moment, which the list keeps showing until their animation ends.
    private var recentlyCompleted: Set<UUID> { completions.heldIDs }

    private func matchedTasks() throws -> [TaskItem] {
        var source = queryString
        if showCompleted, selection != .completed { source = "(\(source)) & (completed | !completed)" }
        return try FilterQuery(source, now: now).apply(to: allTasks, now: now)
    }

    /// The matched tasks plus the recently completed ones, in list order.
    private func placed(_ matched: [TaskItem]) -> [Placed] {
        guard !completions.isEmpty else { return matched.map { Placed(task: $0, filterDueDate: $0.dueDate) } }
        let held = recentlyCompleted
        let anchors = completions.anchors
        let shown = matched.filter { !held.contains($0.id) }.map { Placed(task: $0, filterDueDate: $0.dueDate) }
        let animating = allTasks.compactMap { task in anchors[task.id].map { Placed(task: task, filterDueDate: $0) } }
        return FilterQuery.defaultSort(shown + animating)
    }

    private var result: Result<[Group], FilterQueryError> {
        do {
            let matched = try matchedTasks()
            if selection == .completed {
                let sorted = matched.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                return .success([Group(id: "completed", title: "", tasks: sorted)])
            }
            var groups: [Group] = []
            for row in placed(matched) {
                let key = DueFormatter.sectionTitle(for: row.filterDueDate, now: now)
                if let i = groups.firstIndex(where: { $0.id == key }) {
                    groups[i] = Group(id: key, title: key, tasks: groups[i].tasks + [row.task])
                } else {
                    groups.append(Group(id: key, title: key, tasks: [row.task]))
                }
            }
            return .success(groups)
        } catch let error as FilterQueryError {
            return .failure(error)
        } catch {
            return .failure(FilterQueryError(message: error.localizedDescription, position: 0))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SwiftUI.Group {
                switch result {
                case .success(let groups):
                    if groups.isEmpty {
                        ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle", description: Text(emptyDescription))
                            .frame(maxHeight: .infinity)
                    } else {
                        List(selection: $selectedTask) {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.tasks) { task in
                                        let phase = completions.phase(of: task.id)
                                        TaskRow(task: task, now: now, showProject: currentProject == nil,
                                                completionPhase: phase, onToggleCompletion: { toggleCompletion(task) })
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
                                                    TaskActions.reschedule(task, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)), in: context)
                                                } label: { Label("Tomorrow", systemImage: "sunrise") }
                                                .tint(.orange)
                                            }
                                    }
                                } header: {
                                    if !group.title.isEmpty {
                                        Text(group.title)
                                            .foregroundStyle(group.id == "Overdue" ? .red : .secondary)
                                    }
                                }
                            }
                        }
                        #if os(macOS)
                        .listStyle(.inset)
                        #endif
                        .slateList()
                    }
                case .failure(let error):
                    ContentUnavailableView {
                        Label("Filter Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.message)
                        Text(queryString).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottom) {
                if toast.isVisible {
                    CompletionToast(message: toast.message, onUndo: undoToast)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }

            if selection != .completed {
                Divider()
                QuickAddBar(defaultProject: currentProject, defaultLabel: currentLabel)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
            }
        }
        .background(Theme.background)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if selection != .completed {
                ToolbarItem(placement: .automatic) {
                    Toggle(isOn: $showCompleted) { Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash") }
                        .toggleStyle(.button)
                        .help("Show completed tasks")
                }
            }
            if let filter = currentFilter {
                ToolbarItem(placement: .automatic) {
                    Text(filter.query).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .onReceive(clock) { now = $0 }
        .onAppear { CompletionFeedback.shared.prepare() }
        // Held rows belong to the list they were completed in.
        .onChange(of: selection) { _, _ in completions.cancelAll() }
    }

    // MARK: - Completion

    /// Completing saves at once (sync isn't held back by the animation) and keeps the row on screen
    /// while it celebrates, then collapses it; un-completing just fades the row back to normal.
    private func toggleCompletion(_ task: TaskItem) {
        let checked = task.isCompleted || completions.phase(of: task.id) != nil
        if checked, let record = toast.record(for: task.id) {
            // Un-checking a row the toast still offers to undo is that undo (it knows how to put a
            // recurring task's date back).
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
        // A recurring task mid-animation: it already advanced; a second tap must not advance it again.
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

    /// Puts tasks back the way they were before they were completed; their rows reappear (or stop
    /// animating out) because they match the list again.
    private func revert(_ records: [CompletedTask]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            for record in records {
                completions.cancel(record.id)
                guard let task = allTasks.first(where: { $0.id == record.id }) else { continue }
                switch record.revert {
                case .uncomplete:
                    if task.isCompleted { TaskActions.toggleCompletion(task, in: context) }
                case .restoreDueDate(let due):
                    // Not toggleCompletion: on a recurring task that would advance the date again.
                    TaskActions.reschedule(task, to: due, keepTime: false, in: context)
                }
            }
        }
    }

    /// ~600 ms of check, strike and flash, then the row fades and the list closes the gap. Rows that
    /// still belong in the list (Show Completed is on) just settle. Every step checks `token`, so an
    /// undo or a newer completion of the same task wins.
    private func finishCompletion(of id: UUID, token: Int) async {
        try? await Task.sleep(for: .milliseconds(600))
        if (try? matchedTasks())?.contains(where: { $0.id == id }) == true {
            withAnimation(.easeOut(duration: 0.25)) { _ = completions.remove(id, token: token) }
            return
        }
        guard withAnimation(.easeIn(duration: 0.18), { completions.collapse(id, token: token) }) else { return }
        try? await Task.sleep(for: .milliseconds(180))
        if reduceMotion {
            // Reduce Motion: the fade above is the whole effect; the gap closes without sliding.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { _ = completions.remove(id, token: token) }
        } else {
            withAnimation(.snappy(duration: 0.3)) { _ = completions.remove(id, token: token) }
        }
    }

    private var emptyTitle: String {
        switch selection {
        case .today: return "All clear for today"
        case .inbox: return "Inbox zero"
        case .completed: return "Nothing completed yet"
        default: return "No tasks"
        }
    }
    private var emptyDescription: String {
        selection == .completed ? "Completed tasks show up here." : "Add one below. Try: Call mom tomorrow 5pm p2 #Family"
    }
}
