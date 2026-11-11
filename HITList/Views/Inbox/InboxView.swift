import SwiftUI
import SwiftData
import HITListCore

/// The inbox: every dated task (in any Group) plus undated tasks with no Group, sorted by Priority (one flat
/// list, priority then due date: `TaskOrdering`), by Group or by Date (view options → Sort by, brief 61;
/// `GroupedOrdering`), under the large title "Inbox" and nothing else (the name once), with an
/// "Inbox zero" state when it's empty and Review Inbox in the view options. Undated tasks in a Group are
/// notes and stay in their Group. Rows, completion, and the undo toast behave as in every other list.
/// Shared tasks with a date are rows here too, among yours (brief 62); sorted by Group they are one section, Shared
/// Tasks, after your Groups and before "Ungrouped" (brief 64).
struct InboxView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PopoutController.self) private var popouts
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    /// View options → Sort by, remembered for the Inbox (brief 61), read through `Preferences.sort`.
    @AppStorage(Preferences.inboxSort, store: AppGroup.defaults) private var storedSort = ""
    @State private var showCompleted = false
    @State private var now = Date()
    /// Rows animating out after a completion, each anchored at the due date it had when tapped.
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()
    @State private var processing = false
    private var sharedRows: SharedRows { SharedRows.shared }
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: the island's "+" is the only way to add; lists show no "Add task" row.
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private func matchedTasks() -> [TaskItem] {
        TaskOrdering.inbox(allTasks, includeCompleted: showCompleted, now: now)
    }

    /// The shared tasks in the Inbox, by the same rule as yours: dated ones (an undated one stays in its list).
    private func matchedShared() -> [SharedRow] {
        TaskOrdering.inbox(sharedRows.rows, includeCompleted: showCompleted, now: now)
    }

    /// The matched tasks, yours and shared ones, plus the recently completed ones, by priority then due date. Each
    /// is listed at its own date, or while its completion animates the one it had when tapped (a completed
    /// recurring task has already moved to its next date).
    private var rows: [TaskListRow] {
        let matched = ListRows.rows(own: matchedTasks(), shared: matchedShared())
        guard !completions.isEmpty else { return TaskOrdering.sorted(matched, now: now) }
        let held = completions.heldIDs
        let anchors = completions.anchors
        let shown = matched.filter { !held.contains($0.id) }
        let animating = allTasks.compactMap { task in
            anchors[task.id].map { TaskListRow(.own(task), listedAt: $0, isCompleted: task.isCompleted) }
        } + sharedRows.rows.compactMap { row in
            anchors[row.id].map { TaskListRow(.shared(row), listedAt: $0, isCompleted: row.filterIsCompleted) }
        }
        return TaskOrdering.sorted(shown + animating, now: now)
    }

    private var sort: ListSort { Preferences.sort(storedSort, offered: ListSort.inbox) }

    private var sortBinding: Binding<ListSort> {
        Binding(get: { sort }, set: { storedSort = $0.rawValue })
    }

    /// The rows in the chosen sort's sections (`GroupedOrdering`), each in `TaskOrdering`'s order. By Group: your
    /// Groups, then Shared Tasks, then "Ungrouped".
    private func sections(_ rows: [TaskListRow]) -> [ListSection<ListRowGroup, TaskListRow>] {
        GroupedOrdering.sections(rows, by: sort, groupOrder: ListRows.groupOrder(groups: projects.map(\.id)), now: now) { $0.group }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            SwiftUI.Group {
                if rows.isEmpty {
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
        // The name once, as the system large title (brief 61); the count is on Browse's Inbox row and the
        // Mac sidebar.
        .navigationBarTitleDisplayMode(.large)
        #endif
        // Show completed and Sort by behind the filter-lines icon, the only control beside the magnifying glass;
        // reviewing the inbox one task at a time in the "…".
        .screenChrome {
            ViewOptionsMenu {
                Toggle("Show completed", isOn: $showCompleted)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                SortPicker(selection: sortBinding, choices: ListSort.inbox)
            }
        } menu: {
            if let title = InboxText.reviewMenuItem(count: InboxReview.count(allTasks)) { Button { processing = true } label: { Label(title, systemImage: "tray.and.arrow.down") } }
        }
        .sheet(isPresented: $processing) {
            InboxProcessView(selectedTask: $selectedTask)
        }
        .onReceive(clock) { now = $0 }
        .onReceive(CalendarChange.moments) { now = $0 } // brief 82's follow-up: a new zone or day shows at once, not at the next minute
        .onAppear {
            CompletionFeedback.shared.prepare()
            sharedRows.start()
        }
    }

    private func list(_ rows: [TaskListRow]) -> some View {
        List(selection: popouts.listSelection) {
            ForEach(sections(rows), id: \.key) { section in
                Section {
                    ForEach(section.tasks) { item in
                        switch item.kind {
                        case .own(let task): row(task, hidesDay: Self.namesDay(section.key))
                        case .shared(let shared): sharedRow(shared, hidesDay: Self.namesDay(section.key))
                        }
                    }
                } header: {
                    if section.key != .all {
                        GroupSectionHeader(heading: .make(row: section.key, count: section.openCount, projects: projects, now: now))
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

    /// Rows under a header that names their one day ("Today", "Tomorrow", "Friday, Nov 13") show only their time.
    private static func namesDay(_ key: ListSectionKey<ListRowGroup>) -> Bool {
        switch key {
        case .due(.today), .due(.tomorrow), .due(.day): true
        default: false
        }
    }

    /// Rows name their Group except under that Group's own header.
    private func row(_ task: TaskItem, hidesDay: Bool) -> some View {
        let phase = completions.phase(of: task.id)
        return TaskRow(task: task, now: now, showProject: sort != .group, hidesDay: hidesDay, completionPhase: phase,
                       onToggleCompletion: { toggleCompletion(task) })
            .opacity(phase == .animating ? 0 : 1)
            .tag(ListSelection.task(task))
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

    /// A shared task (briefs 62, 64): drawn as yours, the people where labels go and Shared Tasks where a Group sits
    /// (except under its own header); completing goes through the shared store; selecting it opens its editor.
    private func sharedRow(_ row: SharedRow, hidesDay: Bool) -> some View {
        let phase = completions.phase(of: row.id)
        return SharedTaskListRow(row: row, now: now, showGroup: sort != .group, hidesDay: hidesDay, completionPhase: phase,
                                 onToggleCompletion: { toggleCompletion(row) })
            .opacity(phase == .animating ? 0 : 1)
            .tag(ListSelection.shared(SharedTaskRef(row)))
            .completionRowBackground(flashing: phase == .pending)
            .swipeActions(edge: .trailing) {
                if row.canWrite {
                    Button(role: .destructive) {
                        popouts.requestDelete(title: row.filterTitle) { try? sharedRows.delete(row) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .swipeActions(edge: .leading) {
                if row.canWrite {
                    Button {
                        try? sharedRows.reschedule(row, to: TaskRescheduling.QuickDate.tomorrow.date(now: now))
                    } label: { Label("Tomorrow", systemImage: "sunrise") }
                    .tint(.orange)
                }
            }
    }

    // MARK: - Completion (the same behaviour as TaskListView)

    /// A shared row: completed in the shared store (who and when, so the others see it), with the same check, toast
    /// and Undo as yours.
    private func toggleCompletion(_ row: SharedRow) {
        let record = toast.record(for: row.id)
        switch completions.tap(on: row.id, isCompleted: row.task.isCompleted, undoable: record != nil) {
        case .ignore:
            return
        case .undo:
            withAnimation(HITMotion.exit) { toast.remove(row.id) }
            revert(record.map { [$0] } ?? [])
            return
        case .uncheck:
            withAnimation(HITMotion.standard) { try? sharedRows.setCompleted(false, row) }
            return
        case .complete:
            break
        }
        guard (try? sharedRows.setCompleted(true, row)) != nil else { return }
        let token = withAnimation(HITMotion.quick) { completions.begin(row.id, anchor: row.filterDueDate) }
        CompletionFeedback.shared.taskCompleted()
        Task { await finishCompletion(of: row.id, token: token) }
        showToast(CompletedTask(id: row.id, title: row.filterTitle, revert: .uncomplete))
    }

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

        // A Flipboard switch's row flips instead of completing (brief 59); its toast says "Flipped".
        let completed = Flipboard.completion(for: task)
        let token = withAnimation(HITMotion.quick) { completions.begin(task.id, anchor: task.dueDate) }
        Flipboard.completeRow(task, in: context)
        CompletionFeedback.shared.taskCompleted()
        Task { await finishCompletion(of: task.id, token: token) }
        showToast(completed)
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
                if let shared = sharedRows.row(record.id) {
                    // Reopened in the shared store: the others see it back too.
                    if shared.task.isCompleted { try? sharedRows.setCompleted(false, shared) }
                    continue
                }
                guard let task = allTasks.first(where: { $0.id == record.id }) else { continue }
                if Flipboard.undo(record, on: task, in: context) { continue } // a flipped switch goes back as it was
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
        if matchedTasks().contains(where: { $0.id == id }) || matchedShared().contains(where: { $0.id == id }) {
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
