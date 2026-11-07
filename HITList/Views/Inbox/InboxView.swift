import SwiftUI
import SwiftData
import HITListCore

/// The inbox: every dated task (in any Group) plus undated tasks with no Group, by priority then due date
/// (`TaskOrdering`) in sections by priority, by Group or none (view options → Group by, brief 57;
/// `GroupedOrdering`), under an "Inbox · 7" header, with an "Inbox zero" state when it's
/// empty and a Process button that steps through it one task at a time. Undated tasks in a Group are
/// notes and stay in their Group. Rows, completion, and the undo toast behave as in every other list.
struct InboxView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PopoutController.self) private var popouts
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    /// The filter control's choices (brief 57), kept while the window is open (a tab switch rebuilds this
    /// view) as `ListFilter` JSON.
    @SceneStorage("inboxFilter") private var storedFilter = ""
    @State private var savedFilter: SavedFilter?
    /// View options → Group by, remembered for the Inbox (brief 57).
    @AppStorage(Preferences.inboxGrouping, store: AppGroup.defaults)
    private var grouping: ListGrouping = Preferences.inboxGroupingDefault
    @State private var showCompleted = false
    @State private var now = Date()
    /// Rows animating out after a completion, each anchored at the due date it had when tapped.
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()
    @State private var processing = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: the island's "+" is the only way to add; lists show no "Add task" row.
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private let isCompact = false
    #endif

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
        var filterCreatedDate: Date? { task.filterCreatedDate }
    }

    private func matchedTasks() -> [TaskItem] {
        let inbox = TaskOrdering.inbox(allTasks, includeCompleted: showCompleted)
        guard let source = filter.query, let query = try? FilterQuery(source, now: now) else { return inbox }
        return inbox.filter { query.matches($0, now: now) }
    }

    /// The filter control's choices: the list shows the Inbox's tasks that match `filter.query`.
    private var filter: ListFilter {
        get { storedFilter.data(using: .utf8).flatMap { try? JSONDecoder().decode(ListFilter.self, from: $0) } ?? ListFilter() }
        nonmutating set {
            storedFilter = newValue.isEmpty ? "" : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    private var filterBinding: Binding<ListFilter> {
        Binding(get: { filter }, set: { filter = $0 })
    }

    /// Why a filter shows nothing. A Group with No date is always empty here: undated tasks in a Group are
    /// notes that live in the Group, never in the Inbox (the Inbox rule, `TaskOrdering.isInInbox`).
    private var noMatchExplanation: String {
        let names = filter.chips.compactMap { chip -> String? in if case .group(let name) = chip { name } else { nil } }
        if filter.contains(.noDate), let name = names.first, names.count == 1 {
            return "Undated tasks in \(name) are notes: they stay in \(name), not the Inbox."
        }
        if filter.contains(.noDate), !names.isEmpty {
            return "Undated tasks in a Group are notes: they stay in their Group, not the Inbox."
        }
        return "Nothing in the Inbox matches this filter."
    }

    /// "Save as filter…": a saved filter with the Inbox rule and these choices, opened in its editor to name it.
    private func saveFilter() {
        guard let query = filter.savedQuery(within: ListFilter.inboxQuery) else { return }
        let count = (try? context.fetchCount(FetchDescriptor<SavedFilter>())) ?? 0
        let saved = SavedFilter(name: filter.suggestedName, query: query, sortOrder: count)
        context.insert(saved)
        try? context.save()
        savedFilter = saved
    }

    /// Drops choices naming a Group or label that was renamed or deleted (here or on another device).
    private func pruneFilter() {
        var pruned = filter
        pruned.keep(groups: Set(projects.map(\.name)), labels: Set(labels.map(\.name)))
        if pruned != filter { filter = pruned }
    }

    /// Open inbox tasks, for the header.
    private var openCount: Int { allTasks.filter(\.isInInbox).count }

    /// The matched tasks plus the recently completed ones, by priority then due date.
    private var rows: [Placed] {
        let matched = matchedTasks()
        guard !completions.isEmpty else { return matched.map { Placed(task: $0, filterDueDate: $0.dueDate) } }
        let held = completions.heldIDs
        let anchors = completions.anchors
        let shown = matched.filter { !held.contains($0.id) }.map { Placed(task: $0, filterDueDate: $0.dueDate) }
        let animating = allTasks.compactMap { task in anchors[task.id].map { Placed(task: task, filterDueDate: $0) } }
        return TaskOrdering.sorted(shown + animating)
    }

    /// The rows in the chosen grouping's sections (`GroupedOrdering`), each in `TaskOrdering`'s order.
    private func sections(_ rows: [Placed]) -> [ListSection<UUID, Placed>] {
        GroupedOrdering.sections(rows, by: grouping, groupOrder: projects.map(\.id)) { $0.task.project?.id }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            header
            if !filter.isEmpty {
                ListFilterChips(filter: filterBinding, projects: projects, labels: labels)
                    .transition(.opacity)
            }
            SwiftUI.Group {
                if rows.isEmpty, !filter.isEmpty {
                    ContentUnavailableView {
                        Label("No matching tasks", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(noMatchExplanation)
                    } actions: {
                        Button("Clear Filter") { withAnimation(HITMotion.quick) { filter = ListFilter() } }
                            .buttonStyle(.hitPrimary)
                    }
                    .transition(.opacity)
                } else if rows.isEmpty {
                    InboxZeroView()
                        .transition(.opacity)
                } else {
                    list(rows)
                }
            }
            .frame(maxHeight: .infinity)
            // iPhone: drawn by PopoutHost above the island and the "+".
            .completionToast(toast.isVisible ? toast.message : nil, onUndo: undoToast,
                             onDismiss: { withAnimation(HITMotion.exit) { _ = toast.takeAll() } })
        }
        .quickAddEntry(.inbox)
        .background(Theme.background)
        .navigationTitle("Inbox")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // The filter control, then Show completed and Group by behind the filter-lines icon; reviewing the inbox one task at a time in the "…".
        .screenChrome {
            ListFilterMenu(filter: filterBinding, projects: projects, labels: labels, onSave: saveFilter)
            ViewOptionsMenu {
                Toggle("Show completed", isOn: $showCompleted)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                GroupByPicker(selection: $grouping)
            }
        } menu: {
            Button { processing = true } label: { Label("Review Inbox…", systemImage: "tray.and.arrow.down") }
                .disabled(openCount == 0)
        }
        .sheet(isPresented: $processing) {
            InboxProcessView(selectedTask: $selectedTask)
        }
        .sheet(item: $savedFilter) { FilterEditorView(filter: $0).slateSheet() }
        .onReceive(clock) { now = $0 }
        .onAppear {
            CompletionFeedback.shared.prepare()
            pruneFilter()
        }
        .onChange(of: projects.map(\.name)) { _, _ in pruneFilter() }
        .onChange(of: labels.map(\.name)) { _, _ in pruneFilter() }
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

    private func list(_ rows: [Placed]) -> some View {
        List(selection: $selectedTask) {
            ForEach(sections(rows), id: \.key) { section in
                Section {
                    ForEach(section.tasks, id: \.task.id) { row($0.task) }
                } header: {
                    if section.key != .all {
                        GroupSectionHeader(heading: .make(for: section.key, count: section.openCount, projects: projects))
                    }
                }
            }
            if !isCompact {
                Section { InlineAddRow(context: .inbox, key: "inbox") }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.plain)
        .listSectionSpacing(0)
        #endif
        .environment(\.defaultMinListHeaderHeight, 0)
        .slateList()
    }

    private func row(_ task: TaskItem) -> some View {
        let phase = completions.phase(of: task.id)
        return TaskRow(task: task, now: now, showProject: grouping != .group, completionPhase: phase, onToggleCompletion: { toggleCompletion(task) })
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
        let record = toast.record(for: task.id)
        switch completions.tap(on: task.id, isCompleted: task.isCompleted, undoable: record != nil) {
        case .ignore:
            return
        case .undo:
            withAnimation(HITMotion.exit) { toast.remove(task.id) }
            revert(record.map { [$0] } ?? [])
            return
        case .uncheck:
            withAnimation(HITMotion.standard) { TaskActions.toggleCompletion(task, in: context) }
            return
        case .complete:
            break
        }

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
        try? await Task.sleep(for: CompletionMotion.hold)
        if matchedTasks().contains(where: { $0.id == id }) {
            withAnimation(HITMotion.standard) { _ = completions.remove(id, token: token) }
            return
        }
        guard withAnimation(HITMotion.exit, { completions.collapse(id, token: token) }) else { return }
        try? await Task.sleep(for: CompletionMotion.collapseSettle)
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { _ = completions.remove(id, token: token) }
        } else {
            withAnimation(HITMotion.standard) { _ = completions.remove(id, token: token) }
        }
    }
}
