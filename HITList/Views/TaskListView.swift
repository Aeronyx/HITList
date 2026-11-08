import SwiftUI
import SwiftData
import HITListCore

struct TaskListView: View {
    let selection: SidebarItem

    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var labels: [TaskLabel]
    /// Today's view options → Sort by (brief 61): Priority or Group, remembered for Today alone.
    @AppStorage(Preferences.todaySort, store: AppGroup.defaults) private var storedTodaySort = ""
    @Query private var filters: [SavedFilter]
    @State private var showCompleted = false
    @State private var editingProject: Project?
    @State private var editingLabel: TaskLabel?
    @State private var editingFilter: SavedFilter?
    @State private var now = Date()
    /// Rows animating out after a completion, each anchored at the due date it had when tapped.
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: the island's "+" is the only way to add; lists show no "Add task" row.
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private let isCompact = false
    #endif

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
        case .project: return currentProject?.name ?? "Group"
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
        /// The header's colour: "Overdue" red, today green, other days grey.
        var color: Color = Theme.secondaryText
        /// Rows under a header that names their day show only their time.
        var hidesDay = false
        /// A Group section of a Today sorted by Group (brief 57): drawn by `GroupSectionHeader` instead of
        /// `title`.
        var heading: GroupSectionHeading?
        /// Today by Group: "Overdue" or the day, above the first section of its half (in its header, not a
        /// section of its own, which left an empty gap on the Mac).
        var banner: String?
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
        var filterCreatedDate: Date? { task.filterCreatedDate }
    }

    /// Tasks completed here in the last moment, which the list keeps showing until their animation ends.
    private var recentlyCompleted: Set<UUID> { completions.heldIDs }

    private func matchedTasks() throws -> [TaskItem] {
        // Today and the Inbox follow `TaskOrdering`'s rules rather than a query (an undated task in a
        // Group is a note: never in Today or the Inbox, only in its Group).
        switch selection {
        case .today:
            return allTasks.filter { TaskOrdering.isInToday($0, now: now, includeCompleted: showCompleted) }
        case .inbox:
            return TaskOrdering.inbox(allTasks, includeCompleted: showCompleted, now: now)
        default: break
        }
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
            let rows = placed(matched)
            switch selection {
            case .today: return .success(todayGroups(rows))
            case .inbox:
                let tasks = TaskOrdering.sorted(rows, now: now).map(\.task)
                return .success(tasks.isEmpty ? [] : [Group(id: "inbox", title: "", tasks: tasks)])
            default: break
            }
            var groups: [Group] = []
            for row in rows {
                // A red switch files under today whatever its date (brief 59).
                let due = FlipboardSwitch.listedDueDate(for: row, now: now)
                let key = DueFormatter.sectionTitle(for: due, now: now)
                if let i = groups.firstIndex(where: { $0.id == key }) {
                    groups[i] = Group(id: key, title: key, tasks: groups[i].tasks + [row.task], color: groups[i].color)
                } else {
                    groups.append(Group(id: key, title: key, tasks: [row.task],
                                        color: DueFormatter.sectionColor(for: due, now: now)))
                }
            }
            return .success(groups)
        } catch let error as FilterQueryError {
            return .failure(error)
        } catch {
            return .failure(FilterQueryError(message: error.localizedDescription, position: 0))
        }
    }

    /// Today: "Overdue" (red), then the day, "Oct 31, Saturday" (green), each by priority then due time.
    /// The day header shows whenever the list isn't empty, so its "Add task" row sits under it.
    /// Sorted by Group (briefs 57, 61), the Overdue block stays on top: its header, then its tasks in Group
    /// sections, then the day's header and the day's tasks in Group sections the same way.
    private func todayGroups(_ rows: [Placed]) -> [Group] {
        if todaySort == .group { return groupedTodayGroups(rows) }
        var overdue: [Placed] = [], today: [Placed] = []
        for row in rows {
            switch TaskOrdering.todaySection(of: row, now: now) {
            case .overdue?: overdue.append(row)
            case .today?: today.append(row)
            case nil: break
            }
        }
        guard !(overdue.isEmpty && today.isEmpty) else { return [] }
        var groups: [Group] = []
        if !overdue.isEmpty {
            groups.append(Group(id: "Overdue", title: "Overdue", tasks: TaskOrdering.sorted(overdue, now: now).map(\.task),
                                color: HITColor.dueOverdue))
        }
        groups.append(Group(id: "today", title: DueFormatter.sectionTitle(for: now, now: now, style: .dated),
                            tasks: TaskOrdering.sorted(today, now: now).map(\.task), color: HITColor.dueToday, hidesDay: true))
        return groups
    }

    /// Today's sort: Priority (the flat Overdue and day sections) or Group.
    private var todaySort: ListSort { Preferences.sort(storedTodaySort, offered: ListSort.today) }

    private var todaySortBinding: Binding<ListSort> {
        Binding(get: { todaySort }, set: { storedTodaySort = $0.rawValue })
    }

    /// Rows name their Group, except in that Group's own list and under its header in a Today sorted by Group.
    private var showsProjectOnRows: Bool {
        currentProject == nil && !(selection == .today && todaySort == .group)
    }

    private func groupedTodayGroups(_ rows: [Placed]) -> [Group] {
        // The same section rule as Today by priority (`todayGroups`), so the two never disagree.
        let split = GroupedOrdering.today(rows, by: .group, groupOrder: projects.map(\.id), now: now,
                                          sectionOf: { TaskOrdering.todaySection(of: $0, now: now) }) {
            $0.task.project?.id
        }
        guard !split.isEmpty else { return [] }
        func sections(_ sections: [ListSection<UUID, Placed>], half: String, banner: String, color: Color,
                      hidesDay: Bool) -> [Group] {
            sections.enumerated().map { index, section in
                Group(id: "\(half)-\(section.key)", title: "", tasks: section.tasks.map(\.task), color: color,
                      hidesDay: hidesDay, heading: .make(for: section.key, count: section.openCount, projects: projects, now: now),
                      banner: index == 0 ? banner : nil)
            }
        }
        let day = DueFormatter.sectionTitle(for: now, now: now, style: .dated)
        var groups = sections(split.overdue, half: "overdue", banner: "Overdue", color: HITColor.dueOverdue, hidesDay: false)
        if split.today.isEmpty {
            // The day's header still shows, so its "Add task" row sits under it (as by priority).
            groups.append(Group(id: "today", title: day, tasks: [], color: HITColor.dueToday, hidesDay: true))
        } else {
            groups += sections(split.today, half: "today", banner: day, color: HITColor.dueToday, hidesDay: true)
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            SwiftUI.Group {
                switch result {
                case .success(let groups):
                    if groups.isEmpty, isCompact {
                        // iPhone: one quiet grey line; the "+" is right there.
                        Text(emptyTitle)
                            .font(HITType.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HITSpacing.xl)
                            .padding(.top, HITSpacing.l)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else if groups.isEmpty {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: "checkmark.circle")
                        } description: {
                            Text(emptyDescription)
                        } actions: {
                            if selection != .completed {
                                Button("Add Task") { popouts.openQuickAdd(addContext) }
                                    .buttonStyle(.hitPrimary)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List(selection: popouts.selection) {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.tasks) { task in
                                        let phase = completions.phase(of: task.id)
                                        TaskRow(task: task, now: now, showProject: showsProjectOnRows,
                                                hidesDay: group.hidesDay, completionPhase: phase, onToggleCompletion: { toggleCompletion(task) })
                                            .opacity(phase == .animating ? 0 : 1)
                                            .tag(task)
                                            .completionRowBackground(flashing: phase == .pending)
                                            .swipeActions(edge: .trailing) {
                                                Button(role: .destructive) {
                                                    popouts.requestDelete(task) {
                                                        if popouts.task?.id == task.id { popouts.closeTask() }
                                                        TaskActions.delete(task, in: context)
                                                    }
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
                                    if let heading = group.heading {
                                        VStack(spacing: 0) {
                                            if let banner = group.banner {
                                                Text(banner).taskSectionHeader(color: group.color)
                                            }
                                            GroupSectionHeader(heading: heading, belowBanner: group.banner != nil)
                                        }
                                        .listRowInsets(EdgeInsets())
                                    } else if !group.title.isEmpty {
                                        Text(group.title).taskSectionHeader(color: group.color)
                                    }
                                }
                            }
                            if selection != .completed, !isCompact {
                                Section { InlineAddRow(context: addContext, key: "list") }
                            }
                        }
                        #if os(macOS)
                        .listStyle(.inset)
                        #else
                        // Flat rows on the background with hairline separators, like the Mac (George, build
                        // 11: the inset-grouped cards were "a different and worse design").
                        .listStyle(.plain)
                        .listSectionSpacing(0)
                        #endif
                        .environment(\.defaultMinListHeaderHeight, 0)
                        .slateList()
                    }
                case .failure(let error):
                    ContentUnavailableView {
                        Label("Filter Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.message)
                        Text(queryString).font(HITType.mono).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            // iPhone: drawn by PopoutHost above the island and the "+".
            .completionToast(toast.isVisible ? toast.message : nil, onUndo: undoToast,
                             onDismiss: { withAnimation(HITMotion.exit) { _ = toast.takeAll() } })
        }
        .quickAddEntry(addContext, showsButton: selection != .completed)
        .background(Theme.background)
        .navigationTitle(title)
        #if os(iOS)
        // Every list's name once, as the system large title (brief 61): a Group's too, with no header under it.
        .navigationBarTitleDisplayMode(.large)
        #endif
        // The filter-lines icon holds the view options; the "…" beside it (iPhone, iPad) holds this
        // screen's actions, and on iPhone Settings and the sync dot too (`screenChrome`).
        .screenChrome {
            ViewOptionsMenu {
                if selection != .completed {
                    Toggle("Show completed", isOn: $showCompleted)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                if selection == .today {
                    SortPicker(selection: todaySortBinding, choices: ListSort.today)
                } else {
                    Section("Sort") {
                        Button("By due date") {}.disabled(true)
                        Button("By priority") {}.disabled(true)
                        Button("By name") {}.disabled(true)
                    }
                }
            }
        } menu: {
            if let project = currentProject {
                Button { editingProject = project } label: { Label("Edit Group…", systemImage: "pencil") }
            }
            if let label = currentLabel {
                Button { editingLabel = label } label: { Label("Edit Label…", systemImage: "pencil") }
            }
            if let filter = currentFilter {
                Button { editingFilter = filter } label: { Label("Edit Filter…", systemImage: "pencil") }
            }
        }
        #if os(macOS)
        .toolbar {
            if let filter = currentFilter {
                ToolbarItem(placement: .automatic) {
                    Text(filter.query).font(HITType.monoCaption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        #endif
        .sheet(item: $editingProject) { ProjectEditorView(project: $0).slateSheet() }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0).slateSheet() }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0).slateSheet() }
        .onReceive(clock) { now = $0 }
        .onAppear { CompletionFeedback.shared.prepare() }
        // Held rows belong to the list they were completed in.
        .onChange(of: selection) { _, _ in completions.cancelAll() }
    }

    // MARK: - Completion

    /// Completing saves at once (sync isn't held back by the animation) and keeps the row on screen
    /// while it celebrates, then collapses it. Completing is final until Undo: a tap on a row still in
    /// its animation does nothing (`CompletionAnimator.tap`); only a task showing as completed unchecks,
    /// fading back to normal.
    private func toggleCompletion(_ task: TaskItem) {
        let record = toast.record(for: task.id)
        switch completions.tap(on: task.id, isCompleted: task.isCompleted, undoable: record != nil) {
        case .ignore:
            return
        case .undo:
            // Un-checking a row the toast still offers to undo is that undo (it knows how to put a
            // recurring task's date back).
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

    /// Puts tasks back the way they were before they were completed; their rows reappear (or stop
    /// animating out) because they match the list again.
    private func revert(_ records: [CompletedTask]) {
        withAnimation(HITMotion.standard) {
            for record in records {
                completions.cancel(record.id)
                guard let task = allTasks.first(where: { $0.id == record.id }) else { continue }
                if Flipboard.undo(record, on: task, in: context) { continue } // a flipped switch goes back as it was
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
        try? await Task.sleep(for: CompletionMotion.hold)
        if (try? matchedTasks())?.contains(where: { $0.id == id }) == true {
            withAnimation(HITMotion.standard) { _ = completions.remove(id, token: token) }
            return
        }
        guard withAnimation(HITMotion.exit, { completions.collapse(id, token: token) }) else { return }
        try? await Task.sleep(for: CompletionMotion.collapseSettle)
        if reduceMotion {
            // Reduce Motion: the fade above is the whole effect; the gap closes without sliding.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { _ = completions.remove(id, token: token) }
        } else {
            withAnimation(HITMotion.standard) { _ = completions.remove(id, token: token) }
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
        selection == .completed ? "Completed tasks show up here." : "Try: Call mom tomorrow 5pm p2 #Family"
    }

    /// What a task added here defaults to: Today's date in Today, this project in a project, and so on.
    private var addContext: QuickAddContext {
        switch selection {
        case .inbox: return .inbox
        case .today: return .today
        case .upcoming: return .upcoming
        case .project: return currentProject.map { .project(name: $0.name, id: $0.id) } ?? .plain
        case .label: return currentLabel.map { .label(name: $0.name) } ?? .plain
        case .filter, .completed: return .plain
        }
    }
}
