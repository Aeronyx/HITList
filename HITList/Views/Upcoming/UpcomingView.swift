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
    /// The day whose "+ Add task" row is an open text field.
    @State private var addingDay: Date?
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
                                  weeks: Self.weeks, visibleWeek: $visibleWeek) { day in
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

            Divider()
            QuickAddBar(defaultProject: nil, defaultLabel: nil)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Theme.surface)
        }
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
            }
    }

    private func overdueHeader(_ overdue: [Entry]) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { overdueExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
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
        }
        .modifier(DayHeaderStyle())
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { headerMoved(day.date, to: $0) }
        .onDisappear { headerGone(day.date) }
    }

    private func addRow(_ day: Date, isEmpty: Bool) -> some View {
        SwiftUI.Group {
            if addingDay == day {
                InlineAddField(day: day) { if addingDay == day { addingDay = nil } }
            } else {
                HStack {
                    Button { addingDay = day } label: {
                        Label("Add task", systemImage: "plus").foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if isEmpty {
                        Text("Nothing due").foregroundStyle(Theme.secondaryText.opacity(0.7))
                    }
                }
                .font(.subheadline)
            }
        }
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

/// Slate background for pinned section headers, so rows don't show through them.
private struct DayHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .textCase(nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .overlay(alignment: .bottom) { Theme.separator.frame(height: 0.5) }
            .listRowInsets(EdgeInsets())
    }
}

/// The "+ Add task" row once tapped: quick-add syntax, due on the row's day unless the text names
/// another date. Stays open for the next task; closes when submitted empty, on Escape, or on losing
/// focus while empty.
private struct InlineAddField: View {
    let day: Date
    var onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                TextField("Task for \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
                    #if os(iOS)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    #endif
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in
            if !isFocused, text.trimmingCharacters(in: .whitespaces).isEmpty { onClose() }
        }
        #if os(macOS)
        .onExitCommand(perform: onClose)
        #endif
    }

    private func add() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { onClose(); return }
        let parser = QuickAddParser(knownProjects: projects.map(\.name), knownLabels: labels.map(\.name))
        do {
            try TaskActions.create(from: parser.parse(text).dueDefaulting(to: day), defaultProject: nil, defaultLabel: nil, in: context)
            text = ""
            errorMessage = nil
            focused = true
            Task { await NotificationScheduler.reschedule(context: context) }
        } catch {
            errorMessage = error.localizedDescription
        }
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
