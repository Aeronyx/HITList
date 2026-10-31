import SwiftUI
import SwiftData
import HITListCore

/// Todoist-style Upcoming: a swipeable week strip over a day-by-day list that starts today, with
/// overdue tasks in a collapsible section on top. The list covers 30 days and grows as you scroll.
struct UpcomingView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]

    @State private var now = Date()
    @State private var dayCount = UpcomingView.pageDays
    @State private var overdueExpanded = true
    /// The week strip's page, in weeks from the current one.
    @State private var visibleWeek: Int? = 0
    /// The day whose header is at the top of the list.
    @State private var focusedDay: Date?
    /// The day a dragged task is hovering over, in the strip or on a header.
    @State private var dropTarget: Date?
    /// The task whose Pick Date popover is open.
    @State private var pickingDateFor: UUID?
    @State private var headers = HeaderPositions()
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()

    private static let pageDays = 30
    /// The strip's pages: a month back, a year ahead.
    private static let weeks = -4...52
    private let strip = WeekStrip()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { strip.calendar }
    private var today: Date { calendar.startOfDay(for: now) }
    /// Enough days to reach the end of the strip's last week.
    private var maxDays: Int {
        let end = strip.week(Self.weeks.upperBound + 1, from: today)
        return calendar.dateComponents([.day], from: today, to: end).day ?? 365
    }

    /// Each open task under the date the list shows it on: its own, or while its completion animates,
    /// the one it had when tapped (a completed recurring task has already moved to its next date).
    struct Entry: FilterableTask, Identifiable {
        let task: TaskItem
        let filterDueDate: Date?
        let filterIsCompleted: Bool
        var id: UUID { task.id }
        var filterTitle: String { task.filterTitle }
        var filterNotes: String { task.filterNotes }
        var filterPriority: Int { task.filterPriority }
        var filterHasDueTime: Bool { task.filterHasDueTime }
        var filterProjectName: String? { task.filterProjectName }
        var filterLabelNames: [String] { task.filterLabelNames }
        var filterIsRecurring: Bool { task.filterIsRecurring }
    }

    private var entries: [Entry] {
        let anchors = completions.anchors
        return allTasks.map { task in
            if let anchor = anchors[task.id] {
                return Entry(task: task, filterDueDate: anchor, filterIsCompleted: false)
            }
            return Entry(task: task, filterDueDate: task.dueDate, filterIsCompleted: task.isCompleted)
        }
    }

    var body: some View {
        let entries = entries
        let schedule = UpcomingSchedule(items: entries, now: now, dayCount: dayCount, calendar: calendar)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    WeekStripView(strip: strip, today: today, focusedDay: focusedDay,
                                  counts: UpcomingSchedule.counts(of: entries, calendar: calendar),
                                  weeks: Self.weeks, visibleWeek: $visibleWeek, dropTarget: $dropTarget,
                                  onDrop: { drop($0, on: $1) }) { day in
                        jump(to: day, schedule: schedule, proxy: proxy)
                    }
                    Divider()
                    list(schedule)
                }
            }
            .overlay(alignment: .bottom) {
                if toast.isVisible {
                    CompletionToast(message: toast.message, onUndo: undoToast)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .quickAddEntry(.upcoming)
        .background(Theme.background)
        .navigationTitle("Upcoming")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(clock) { now = $0 }
        .onAppear { CompletionFeedback.shared.prepare() }
    }

    // MARK: - List

    private func list(_ schedule: UpcomingSchedule<Entry>) -> some View {
        List(selection: $selectedTask) {
            if !schedule.overdue.isEmpty {
                Section {
                    if overdueExpanded {
                        ForEach(schedule.overdue) { row($0) }
                    }
                } header: {
                    overdueHeader(schedule.overdue)
                }
            }
            ForEach(schedule.days) { day in
                Section {
                    ForEach(day.items) { row($0) }
                    addRow(day.date, isEmpty: day.items.isEmpty)
                } header: {
                    dayHeader(day)
                }
            }
            if dayCount < maxDays {
                // Reaching the end loads the next month of days.
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
                    .onAppear { dayCount = min(dayCount + Self.pageDays, maxDays) }
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

    private func row(_ entry: Entry) -> some View {
        let task = entry.task
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
                    move(task, to: calendar.date(byAdding: .day, value: 1, to: today)!)
                } label: { Label("Tomorrow", systemImage: "sunrise") }
                .tint(.orange)
                Button { pickingDateFor = task.id } label: { Label("Pick Date", systemImage: "calendar") }
                    .tint(Theme.accent)
            }
            // iPhone: a long press is the context menu, so rows don't drag there (swipe → Pick Date instead).
            #if os(macOS)
            .draggable(TaskRescheduling.dragPayload(for: task.id)) { DragPreview(title: task.title) }
            #endif
            .contextMenu { rowMenu(task) }
            .popover(isPresented: Binding(get: { pickingDateFor == task.id },
                                          set: { if !$0, pickingDateFor == task.id { pickingDateFor = nil } })) {
                PickDatePopover(initial: task.dueDate ?? today) { day in
                    pickingDateFor = nil
                    move(task, to: day)
                } onRemove: {
                    pickingDateFor = nil
                    withAnimation(reduceMotion ? nil : .snappy) { TaskActions.reschedule(task, to: nil, in: context) }
                    rescheduleNotifications()
                }
            }
    }

    @ViewBuilder
    private func rowMenu(_ task: TaskItem) -> some View {
        ForEach(TaskRescheduling.QuickDate.allCases, id: \.self) { quick in
            Button(quick.title, systemImage: quick.symbol) { move(task, to: quick.date(now: now, calendar: calendar)) }
        }
        Button("Pick Date…", systemImage: "calendar") {
            // Let the menu finish closing before the popover anchors to the row.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                pickingDateFor = task.id
            }
        }
        if task.dueDate != nil {
            Button("Remove Date", systemImage: "calendar.badge.minus") {
                withAnimation(reduceMotion ? nil : .snappy) { TaskActions.reschedule(task, to: nil, in: context) }
                rescheduleNotifications()
            }
        }
        Divider()
        Menu("Priority") {
            ForEach(Priority.allCases, id: \.self) { p in
                Button { task.priorityValue = p; task.touch(); try? context.save() } label: { Label(p.displayName, systemImage: p.symbol) }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            if selectedTask?.id == task.id { selectedTask = nil }
            TaskActions.delete(task, in: context)
        }
    }

    private func overdueHeader(_ overdue: [Entry]) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { overdueExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(HITType.captionBold)
                        .rotationEffect(.degrees(overdueExpanded ? 90 : 0))
                    Text("Overdue").fontWeight(.semibold)
                    Text("\(overdue.count)").foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Overdue, \(overdue.count) tasks")
            .accessibilityValue(overdueExpanded ? "Expanded" : "Collapsed")
            Spacer()
            Button("Reschedule all to today") {
                let held = completions.heldIDs
                rescheduleAll(overdue.map(\.task).filter { !held.contains($0.id) })
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .modifier(DayHeaderStyle())
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { headerMoved(.distantPast, to: $0) }
        .onDisappear { headerGone(.distantPast) }
    }

    private func dayHeader(_ day: UpcomingDay<Entry>) -> some View {
        let isToday = day.date == today
        return HStack(spacing: 6) {
            Text(UpcomingFormat.header(for: day.date, now: now, calendar: calendar))
                .fontWeight(.semibold)
                .foregroundStyle(isToday ? Theme.accent : .primary)
            if !day.items.isEmpty {
                Text("\(day.items.count)").foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if dropTarget == day.date {
                Label("Move here", systemImage: "arrow.down.to.line").labelStyle(.titleAndIcon).foregroundStyle(Theme.accent)
            }
        }
        .modifier(DayHeaderStyle(highlighted: dropTarget == day.date))
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: day.date)
        } isTargeted: { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { dropHover(hovering, on: day.date) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { headerMoved(day.date, to: $0) }
        .onDisappear { headerGone(day.date) }
    }

    private func addRow(_ day: Date, isEmpty: Bool) -> some View {
        InlineAddRow(context: .day(day), key: "day-\(day.timeIntervalSinceReferenceDate)", note: isEmpty ? "Nothing due" : nil)
        .id(AddRowID(day: day))
        .selectionDisabled()
        .slateRow()
    }

    // MARK: - Week strip ↔ list

    private struct AddRowID: Hashable { let day: Date }

    /// Scrolls the list to a day: its first task, or its add row when it has none. Days before today
    /// go to the overdue section.
    private func jump(to day: Date, schedule: UpcomingSchedule<Entry>, proxy: ScrollViewProxy) {
        let animation: Animation? = reduceMotion ? nil : .snappy
        if day < today {
            guard let first = schedule.overdue.first else { return }
            overdueExpanded = true
            withAnimation(animation) { proxy.scrollTo(first.id, anchor: .top) }
            return
        }
        let index = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if index >= dayCount {
            // Not loaded yet: grow the list, then scroll once it has laid out.
            dayCount = min(max(dayCount, index + Self.pageDays), maxDays)
            Task { @MainActor in
                await Task.yield()
                withAnimation(animation) { proxy.scrollTo(AddRowID(day: day), anchor: .top) }
            }
            return
        }
        let target: AnyHashable = schedule.days[index].items.first.map { AnyHashable($0.id) } ?? AnyHashable(AddRowID(day: day))
        withAnimation(animation) { proxy.scrollTo(target, anchor: .top) }
    }

    /// The pinned header is the topmost one on screen; when that changes, the strip follows.
    private func headerMoved(_ day: Date, to minY: CGFloat) {
        headers.minY[day] = minY
        updateFocusedDay()
    }

    private func headerGone(_ day: Date) {
        headers.minY[day] = nil
        updateFocusedDay()
    }

    private func updateFocusedDay() {
        guard let top = headers.minY.min(by: { $0.value < $1.value })?.key else { return }
        let day: Date? = top == .distantPast ? nil : top
        guard day != focusedDay else { return }
        focusedDay = day
        let week = strip.weekOffset(of: day ?? today, from: today)
        if week != visibleWeek, Self.weeks.contains(week) {
            withAnimation(reduceMotion ? nil : .snappy) { visibleWeek = week }
        }
    }

    // MARK: - Actions

    /// Reschedules dropped tasks onto `day`, keeping their times. Days before today don't take drops.
    private func drop(_ payload: [String], on day: Date) -> Bool {
        dropTarget = nil
        guard day >= today else { return false }
        let ids = Set(TaskRescheduling.taskIDs(in: payload))
        let tasks = allTasks.filter { ids.contains($0.id) && !$0.isCompleted }
        guard !tasks.isEmpty else { return false }
        withAnimation(reduceMotion ? nil : .snappy) {
            for task in tasks { TaskActions.reschedule(task, to: day, in: context) }
        }
        rescheduleNotifications()
        return true
    }

    private func dropHover(_ hovering: Bool, on day: Date) {
        if hovering, day >= today { dropTarget = day } else if dropTarget == day { dropTarget = nil }
    }

    private func move(_ task: TaskItem, to day: Date) {
        withAnimation(reduceMotion ? nil : .snappy) { TaskActions.reschedule(task, to: day, in: context) }
        rescheduleNotifications()
    }

    private func rescheduleAll(_ tasks: [TaskItem]) {
        withAnimation(reduceMotion ? nil : .snappy) {
            for task in tasks { TaskActions.reschedule(task, to: today, in: context) }
        }
        rescheduleNotifications()
    }

    private func rescheduleNotifications() {
        Task { await NotificationScheduler.reschedule(context: context) }
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
        Task { await finishCompletion(of: task, token: token) }
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

    /// Check, strike and flash, then the row fades and the gap closes. A recurring task, which is still
    /// open on its next date, just moves to that day instead.
    private func finishCompletion(of task: TaskItem, token: Int) async {
        let id = task.id
        try? await Task.sleep(for: .milliseconds(600))
        if !task.isCompleted, task.dueDate != nil {
            withAnimation(reduceMotion ? nil : .snappy) { _ = completions.remove(id, token: token) }
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

/// Where each visible section header sits, written on every scroll frame. A plain class so writing it
/// doesn't redraw the view; only a change of the top day does.
private final class HeaderPositions {
    var minY: [Date: CGFloat] = [:]
}

/// Slate background for pinned section headers, so rows don't show through them. Tinted while a
/// dragged task hovers over it.
private struct DayHeaderStyle: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .font(HITType.subheadline)
            .textCase(nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .background(Theme.accent.opacity(highlighted ? 0.18 : 0))
            .overlay(alignment: .bottom) { (highlighted ? Theme.accent : Theme.separator).frame(height: highlighted ? 2 : 0.5) }
            .listRowInsets(EdgeInsets())
    }
}

extension QuickAddResult {
    /// The result due on `day` (all day) when the text named no date of its own.
    func dueDefaulting(to day: Date) -> QuickAddResult {
        guard dueDate == nil else { return self }
        var result = self
        result.dueDate = day
        result.hasDueTime = false
        return result
    }
}

/// What a dragged row looks like under the finger or pointer.
private struct DragPreview: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "circle")
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6)))
            .foregroundStyle(.primary)
            .preferredColorScheme(.dark)
    }
}
