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
    /// The shared tasks Today shows among yours (brief 62), and the Shared Tasks Group's (brief 64); nothing while
    /// Shared Tasks is off.
    private var sharedRows: SharedRows { SharedRows.shared }
    /// The Shared Tasks Group's "Sharing…" (brief 64).
    @State private var showSharing = false
    /// Today's calendar events above its tasks (brief 77): none while Settings → General → Calendar events is off.
    private var calendarEvents: CalendarEvents { CalendarEvents.shared }
    /// The events rows are as tall as task rows, Compact rows included.
    @AppStorage(Preferences.compactRows, store: AppGroup.defaults) private var compactRows = Preferences.compactRowsDefault
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

    /// The Shared Tasks Group (brief 64): a Group's screen whose tasks are every shared task, dated or not.
    private var isSharedTasks: Bool { selection == .sharedTasks }

    private var title: String {
        switch selection {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        case .filter: return currentFilter?.name ?? "Filter"
        case .project: return isSharedTasks ? SharedTasksGroup.name : currentProject?.name ?? "Group"
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
        let rows: [TaskListRow]
        /// A day's header with the weekday in three letters, drawn when `title` does not fit (`DayHeadingLine`).
        var shortTitle: String?
        /// The header's colour: "Overdue" red, today green, other days grey.
        var color: Color = Theme.secondaryText
        /// Rows under a header that names their day show only their time.
        var hidesDay = false
        /// A Group's or Shared Tasks' section of a Today sorted by Group (briefs 57, 62, 64): drawn by
        /// `GroupSectionHeader` instead of `title`.
        var heading: GroupSectionHeading?
        /// Today by Group: "Overdue" or the day, above the first section of its half (in its header, not a
        /// section of its own, which left an empty gap on the Mac).
        var banner: String?
        var shortBanner: String?
        /// A set of people's section in the Shared Tasks Group (brief 64): their faces and first names.
        var people: SharedSetHeading?
    }

    /// Tasks completed here in the last moment, which the list keeps showing until their animation ends.
    private var recentlyCompleted: Set<UUID> { completions.heldIDs }

    /// The shared tasks this list shows (brief 62): Today's, by the same rule as yours; the Shared Tasks Group's, all of
    /// them, dated or not (brief 64). The other lists (a Group, a label, a filter, Completed) are yours alone.
    private func matchedShared() -> [SharedRow] {
        if isSharedTasks { return sharedRows.rows.filter { showCompleted || !$0.filterIsCompleted } }
        guard selection == .today else { return [] }
        return sharedRows.rows.filter { TaskOrdering.isInToday($0, now: now, includeCompleted: showCompleted) }
    }

    /// Lists whose shared rows animate out here after a completion.
    private var showsSharedRows: Bool { selection == .today || isSharedTasks }

    /// Whether a row is still in this list, so a completion settles in place rather than collapsing.
    private func isListed(_ id: UUID) -> Bool {
        (try? matchedTasks())?.contains(where: { $0.id == id }) == true || matchedShared().contains { $0.id == id }
    }

    private func matchedTasks() throws -> [TaskItem] {
        // The Shared Tasks Group holds no task of yours.
        if isSharedTasks { return [] }
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

    /// The matched tasks (yours and shared ones) plus the recently completed ones, each under the due date it is
    /// listed at: its own, or while its completion animates the one it had when tapped (a completed recurring task
    /// has already moved to its next date).
    private func placed(_ matched: [TaskItem], shared: [SharedRow]) -> [TaskListRow] {
        let rows = ListRows.rows(own: matched, shared: shared)
        guard !completions.isEmpty else { return rows }
        let held = recentlyCompleted
        let anchors = completions.anchors
        let shown = rows.filter { !held.contains($0.id) }
        let animating = allTasks.compactMap { task in
            anchors[task.id].map { TaskListRow(.own(task), listedAt: $0, isCompleted: task.isCompleted) }
        } + (showsSharedRows ? sharedRows.rows : []).compactMap { row in
            anchors[row.id].map { TaskListRow(.shared(row), listedAt: $0, isCompleted: row.filterIsCompleted) }
        }
        return FilterQuery.defaultSort(shown + animating)
    }

    private var result: Result<[Group], FilterQueryError> {
        do {
            let matched = try matchedTasks()
            if selection == .completed {
                let sorted = matched.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                // None yet: no section, so the empty state shows (an empty section drew a blank page).
                return .success(sorted.isEmpty ? [] : [Group(id: "completed", title: "", rows: sorted.map { .own($0) })])
            }
            let rows = placed(matched, shared: matchedShared())
            if isSharedTasks { return .success(sharedTasksGroups(rows)) }
            switch selection {
            case .today: return .success(todayGroups(rows))
            case .inbox:
                let sorted = TaskOrdering.sorted(rows, now: now)
                return .success(sorted.isEmpty ? [] : [Group(id: "inbox", title: "", rows: sorted)])
            default: break
            }
            var groups: [Group] = []
            for row in rows {
                // A red switch files under today whatever its date (brief 59).
                let due = FlipboardSwitch.listedDueDate(for: row, now: now)
                let key = DueFormatter.sectionTitle(for: due, now: now, style: .dated)
                // A header that names one day ("Nov 12 · Tomorrow · Thursday", "Nov 13 · Friday") says it for its rows;
                // "Overdue" and "No date" do not.
                let singleDay = due != nil && key != "Overdue"
                if let i = groups.firstIndex(where: { $0.id == key }) {
                    groups[i] = Group(id: key, title: key, rows: groups[i].rows + [row], shortTitle: groups[i].shortTitle,
                                      color: groups[i].color, hidesDay: groups[i].hidesDay)
                } else {
                    let short = singleDay ? due.map { DueFormatter.dayHeading(for: $0, now: now, shortWeekday: true) } : nil
                    groups.append(Group(id: key, title: key, rows: [row], shortTitle: short,
                                        color: DueFormatter.sectionColor(for: due, now: now), hidesDay: singleDay))
                }
            }
            return .success(groups)
        } catch let error as FilterQueryError {
            return .failure(error)
        } catch {
            return .failure(FilterQueryError(message: error.localizedDescription, position: 0))
        }
    }

    /// Today: "Overdue" (red), then the day, "Oct 31 · Today · Saturday" (green), each by priority then due time.
    /// The day header shows whenever the list isn't empty, so its "Add task" row sits under it.
    /// Sorted by Group (briefs 57, 61), the Overdue block stays on top: its header, then its tasks in Group
    /// sections, then the day's header and the day's tasks in Group sections the same way.
    private func todayGroups(_ rows: [TaskListRow]) -> [Group] {
        if todaySort == .group { return groupedTodayGroups(rows) }
        var overdue: [TaskListRow] = [], today: [TaskListRow] = []
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
            groups.append(Group(id: "Overdue", title: "Overdue", rows: TaskOrdering.sorted(overdue, now: now),
                                color: HITColor.dueOverdue))
        }
        groups.append(Group(id: "today", title: DueFormatter.sectionTitle(for: now, now: now, style: .dated),
                            rows: TaskOrdering.sorted(today, now: now), shortTitle: todayShortTitle,
                            color: HITColor.dueToday, hidesDay: true))
        return groups
    }

    /// Today's calendar events (brief 77), all-day first then by time; none in every other list, and none while the
    /// setting is off. They are not tasks: no count, filter or sort takes them.
    private var todayEvents: [DayEvent] {
        selection == .today ? calendarEvents.events(on: now) : []
    }

    /// Today with events but no tasks: the day's header (and its "Add task" row) still show under the events, so the
    /// list reads as the day's; the iPhone, which has no "Add task" row, shows the events alone.
    private func withDayHeader(_ groups: [Group], events: [DayEvent]) -> [Group] {
        guard groups.isEmpty, !events.isEmpty, !isCompact else { return groups }
        return [Group(id: "today", title: DueFormatter.sectionTitle(for: now, now: now, style: .dated), rows: [],
                      shortTitle: todayShortTitle, color: HITColor.dueToday, hidesDay: true)]
    }

    /// Today's header with the weekday in three letters, for when the full one does not fit.
    private var todayShortTitle: String { DueFormatter.dayHeading(for: now, now: now, shortWeekday: true) }

    /// Today's sort: Priority (the flat Overdue and day sections) or Group.
    private var todaySort: ListSort { Preferences.sort(storedTodaySort, offered: ListSort.today) }

    private var todaySortBinding: Binding<ListSort> {
        Binding(get: { todaySort }, set: { storedTodaySort = $0.rawValue })
    }

    /// Rows name their Group, except in that Group's own list (Shared Tasks' too) and under its header in a Today
    /// sorted by Group.
    private var showsProjectOnRows: Bool {
        currentProject == nil && !isSharedTasks && !(selection == .today && todaySort == .group)
    }

    /// The Shared Tasks Group's rows (brief 64), priority then date, dated or not. With more than one set of people
    /// (shared lists underneath), a section per set headed by their faces and first names; with one, no sections.
    private func sharedTasksGroups(_ rows: [TaskListRow]) -> [Group] {
        guard !rows.isEmpty else { return [] }
        let me = sharedRows.me
        let lists = SharedSets.ordered(sharedRows.lists, me: me)
        guard lists.count > 1 else { return [Group(id: "shared", title: "", rows: TaskOrdering.sorted(rows, now: now))] }
        let sections = GroupedOrdering.sections(rows, by: .group, groupOrder: lists.map(\.id), now: now) { $0.sharedTask?.listID }
        return sections.map { section in
            let list: SharedList? = if case .group(let id) = section.key { lists.first { $0.id == id } } else { nil }
            return Group(id: "set-\(section.key)", title: "", rows: section.tasks,
                         people: SharedSetHeading(people: list.map { SharedPeople.others(in: $0, me: me) } ?? [],
                                                  count: section.openCount))
        }
    }

    private func groupedTodayGroups(_ rows: [TaskListRow]) -> [Group] {
        // The same section rule as Today by priority (`todayGroups`), so the two never disagree. Shared Tasks after
        // the Groups, "Ungrouped" last (briefs 62, 64).
        let order = ListRows.groupOrder(groups: projects.map(\.id))
        let split = GroupedOrdering.today(rows, by: .group, groupOrder: order, now: now,
                                          sectionOf: { TaskOrdering.todaySection(of: $0, now: now) }) { $0.group }
        guard !split.isEmpty else { return [] }
        func sections(_ sections: [ListSection<ListRowGroup, TaskListRow>], half: String, banner: String,
                      shortBanner: String? = nil, color: Color, hidesDay: Bool) -> [Group] {
            sections.enumerated().map { index, section in
                Group(id: "\(half)-\(section.key)", title: "", rows: section.tasks, color: color, hidesDay: hidesDay,
                      heading: .make(row: section.key, count: section.openCount, projects: projects, now: now),
                      banner: index == 0 ? banner : nil, shortBanner: index == 0 ? shortBanner : nil)
            }
        }
        let day = DueFormatter.sectionTitle(for: now, now: now, style: .dated)
        var groups = sections(split.overdue, half: "overdue", banner: "Overdue", color: HITColor.dueOverdue, hidesDay: false)
        if split.today.isEmpty {
            // The day's header still shows, so its "Add task" row sits under it (as by priority).
            groups.append(Group(id: "today", title: day, rows: [], shortTitle: todayShortTitle, color: HITColor.dueToday,
                                hidesDay: true))
        } else {
            groups += sections(split.today, half: "today", banner: day, shortBanner: todayShortTitle,
                               color: HITColor.dueToday, hidesDay: true)
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            SwiftUI.Group {
                switch result {
                case .success(let taskGroups):
                    let events = todayEvents
                    let groups = withDayHeader(taskGroups, events: events)
                    if isSharedTasks, !SharedTasksCenter.shared.isOn {
                        // Off: what sharing is, and one button to switch it on and invite (brief 64).
                        SharedTasksOff {
                            SharedTasksCenter.shared.setOn(true)
                            showSharing = true
                        }
                    } else if groups.isEmpty, events.isEmpty, isCompact {
                        // iPhone: one quiet grey line; the "+" is right there. It starts where the rows and headers
                        // do, under the title.
                        Text(emptyTitle)
                            .font(HITType.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, ListMetrics.horizontalInset)
                            .padding(.top, HITSpacing.l)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else if groups.isEmpty, events.isEmpty {
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
                        List(selection: popouts.listSelection) {
                            if !events.isEmpty {
                                // Above the day's tasks (and Overdue), under a quiet header of their own (brief 77).
                                Section {
                                    ForEach(events) { event in
                                        CalendarEventRow(event: event, now: now)
                                            .calendarEventListRow(compact: compactRows)
                                    }
                                } header: {
                                    CalendarEventsHeader()
                                }
                            }
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.rows) { row in
                                        switch row.kind {
                                        case .own(let task): taskRow(task, in: group)
                                        case .shared(let shared): sharedRow(shared, in: group)
                                        }
                                    }
                                } header: {
                                    if let people = group.people {
                                        SharedSetHeader(heading: people)
                                            .listRowInsets(EdgeInsets())
                                    } else if let heading = group.heading {
                                        VStack(spacing: 0) {
                                            if let banner = group.banner {
                                                DayHeadingLine(full: banner, short: group.shortBanner)
                                                    .taskSectionHeader(color: group.color)
                                            }
                                            GroupSectionHeader(heading: heading, belowBanner: group.banner != nil)
                                        }
                                        .listRowInsets(EdgeInsets())
                                    } else if !group.title.isEmpty {
                                        DayHeadingLine(full: group.title, short: group.shortTitle)
                                            .taskSectionHeader(color: group.color)
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
        .quickAddEntry(addContext, showsButton: selection != .completed && (!isSharedTasks || SharedTasksCenter.shared.isOn))
        .background(Theme.background)
        .navigationTitle(title)
        #if os(iOS)
        // Every list's name once, as the system large title (brief 61): a Group's too, with no header under it.
        .navigationBarTitleDisplayMode(.large)
        #endif
        // The filter-lines icon holds the view options and, under a divider, this screen's actions; Settings is
        // the control beside it (`screenChrome`).
        .screenChrome {
            ViewOptionsMenu {
                if selection != .completed {
                    Toggle(isOn: $showCompleted) { Label("Show completed", systemImage: "checkmark.circle") }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                if selection == .today {
                    SortPicker(selection: todaySortBinding, choices: ListSort.today)
                }
                if isSharedTasks {
                    // Who shares these tasks: invite, who is in, leave, the switch (brief 64).
                    Button { showSharing = true } label: { Label("Sharing…", systemImage: "person.2") }
                        .accessibilityIdentifier("sharingButton")
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
                    FilterQueryBadge(query: filter.query)
                }
            }
        }
        #endif
        .sheet(item: $editingProject) { ProjectEditorView(project: $0).slateSheet() }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0).slateSheet() }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0).slateSheet() }
        .sharingSheet(isPresented: $showSharing)
        .onReceive(clock) { now = $0 }
        .onReceive(CalendarChange.moments) { now = $0 } // brief 82: a new zone or day regroups Today and Overdue at once
        .onAppear {
            CompletionFeedback.shared.prepare()
            sharedRows.start()
            calendarEvents.start()
        }
        // Held rows belong to the list they were completed in.
        .onChange(of: selection) { _, _ in completions.cancelAll() }
    }

    // MARK: - Rows

    private func taskRow(_ task: TaskItem, in group: Group) -> some View {
        let phase = completions.phase(of: task.id)
        return TaskRow(task: task, now: now, showProject: showsProjectOnRows,
                       hidesDay: group.hidesDay, completionPhase: phase, onToggleCompletion: { toggleCompletion(task) })
            .opacity(phase == .animating ? 0 : 1)
            .tag(ListSelection.task(task))
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

    /// A shared task (briefs 62, 64): drawn as yours, the people where labels go and Shared Tasks where a Group sits;
    /// completing goes through the shared store; selecting it opens its editor.
    private func sharedRow(_ row: SharedRow, in group: Group) -> some View {
        let phase = completions.phase(of: row.id)
        return SharedTaskListRow(row: row, now: now, showGroup: showsProjectOnRows, hidesDay: group.hidesDay,
                                 completionPhase: phase, onToggleCompletion: { toggleCompletion(row) })
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
                        try? sharedRows.reschedule(row, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)))
                    } label: { Label("Tomorrow", systemImage: "sunrise") }
                    .tint(.orange)
                }
            }
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

    /// A shared row: completed in the shared store (stamped with who and when, so the others see it), with the same
    /// check, toast and Undo as yours (brief 62). A shared task has no repeat and no switch.
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
        if isListed(id) {
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
        case .project where isSharedTasks: return "No shared tasks yet"
        case .inbox: return "Inbox zero"
        case .completed: return "Nothing completed yet"
        default: return "No tasks"
        }
    }
    private var emptyDescription: String {
        if isSharedTasks { return "Tasks you add here show up in everyone's lists. Choose who sees them in Sharing…" }
        return selection == .completed ? "Completed tasks show up here." : "Try: Call mom tomorrow 5pm p2 #Family"
    }

    /// What a task added here defaults to: Today's date in Today, this project in a project, and so on.
    private var addContext: QuickAddContext {
        switch selection {
        case .inbox: return .inbox
        case .today: return .today
        case .upcoming: return .upcoming
        case .project:
            if isSharedTasks { return .sharedTasks } // into Shared Tasks (brief 64)
            return currentProject.map { .project(name: $0.name, id: $0.id) } ?? .plain
        case .label: return currentLabel.map { .label(name: $0.name) } ?? .plain
        case .filter, .completed: return .plain
        }
    }
}
