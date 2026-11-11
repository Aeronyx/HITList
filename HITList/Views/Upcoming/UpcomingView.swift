import SwiftUI
import SwiftData
import HITListCore

/// Todoist-style Upcoming. iPhone (and a narrow iPad): a swipeable week strip over a day-by-day list that
/// starts today, with overdue tasks in a collapsible section on top; the list covers 30 days and grows as
/// you scroll. Mac (and a full-width iPad): a board of seven day columns (`UpcomingBoard`). Shared tasks with a
/// date are rows, dots and cards among yours (brief 62).
struct UpcomingView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]

    @Environment(PopoutController.self) private var popouts
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appShell) private var shell
    /// iPhone: the island's "+" is the only way to add; lists show no "Add task" row.
    private var isCompact: Bool { sizeClass == .compact }
    /// iPad at full width and the iPhone Duo's inner display: the board (`showsBoard(idiom:sizeClass:shell:)`).
    private var showsBoard: Bool { Self.showsBoard(idiom: AppShell.currentIdiom, sizeClass: sizeClass, shell: shell) }
    #else
    private let isCompact = false
    private let showsBoard = true
    #endif

    /// The board or the week list. The Mac: the board. iPad: the board at full width. iPhone: the list, whose
    /// landscape Plus/Max sizes are regular too, except on the Duo's inner display (`AppShell.duo`, brief 50),
    /// which has the room for the board whatever size class it reports.
    static func showsBoard(idiom: AppShell.Idiom, sizeClass: UserInterfaceSizeClass?, shell: AppShell?) -> Bool {
        switch idiom {
        case .mac: true
        case .pad: sizeClass == .regular
        case .phone: shell == .duo
        }
    }
    @State private var now = Date()
    /// The board's seven days (Mac, iPad).
    @State private var window = UpcomingWindow()
    @State private var dayCount = UpcomingView.pageDays
    @State private var overdueExpanded = true
    /// The week strip's page, in weeks from the current one.
    @State private var visibleWeek: Int? = 0
    /// The day whose header is at the top of the list.
    @State private var focusedDay: Date?
    /// The toolbar's "Jump to today": bumped there, acted on inside the ScrollViewReader.
    @State private var jumpToTodayRequest = 0
    /// The day a dragged task is hovering over, in the strip or on a header.
    @State private var dropTarget: Date?
    /// The task whose Pick Date popover is open.
    @State private var pickingDateFor: UUID?
    @State private var headers = HeaderPositions()
    @State private var completions = CompletionAnimator<Date?>()
    @State private var toast = CompletionToastState()
    /// "You can see “Trip” but not change it.": a drop or a move a shared list refused, for a moment.
    @State private var refusal: String?
    private var sharedRows: SharedRows { SharedRows.shared }
    /// Each day's calendar events at the top of that day (brief 77); none while the setting is off.
    private var calendarEvents: CalendarEvents { CalendarEvents.shared }
    @AppStorage(Preferences.compactRows, store: AppGroup.defaults) private var compactRows = Preferences.compactRowsDefault

    private static let pageDays = 30
    /// The strip's pages: a month back, a year ahead.
    private static let weeks = -4...52
    private let strip = WeekStrip(weekStart: Preferences.weekStartWeekday())
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { strip.calendar }
    private var today: Date { calendar.startOfDay(for: now) }
    /// Enough days to reach the end of the strip's last week.
    private var maxDays: Int {
        let end = strip.week(Self.weeks.upperBound + 1, from: today)
        return calendar.dateComponents([.day], from: today, to: end).day ?? 365
    }

    /// Each task, yours or a shared one (brief 62), under the date the list shows it on: its own, or while its
    /// completion animates the one it had when tapped (a completed recurring task has already moved to its next
    /// date), and open while it animates.
    typealias Entry = TaskListRow

    private var entries: [Entry] {
        let anchors = completions.anchors
        let own = allTasks.map { task in
            if let anchor = anchors[task.id] {
                return Entry(task: task, filterDueDate: anchor, filterIsCompleted: false)
            }
            return Entry(task: task, filterDueDate: task.dueDate, filterIsCompleted: task.isCompleted)
        }
        let shared = sharedRows.rows.map { row in
            anchors[row.id].map { Entry(.shared(row), listedAt: $0, isCompleted: false) } ?? .shared(row)
        }
        return own + shared
    }

    var body: some View {
        let entries = entries
        VStack(spacing: 0) {
            SwiftUI.Group {
                if showsBoard {
                    board(entries)
                } else {
                    weekList(entries)
                }
            }
            // iPhone: drawn by PopoutHost above the island and the "+".
            .completionToast(toast.isVisible ? toast.message : nil, onUndo: undoToast,
                             onDismiss: { withAnimation(HITMotion.exit) { _ = toast.takeAll() } })
        }
        .overlay(alignment: .bottom) {
            if let refusal { RefusalNote(text: refusal).transition(.opacity) }
        }
        .quickAddEntry(.upcoming)
        .background(Theme.background)
        .navigationTitle("Upcoming")
        .screenChrome {
            ViewOptionsMenu {
                Toggle(isOn: $overdueExpanded) { Label("Show overdue", systemImage: "exclamationmark.circle") }
                // The board always shows seven days.
                if !showsBoard {
                    Picker(selection: $dayCount) {
                        Text("2 weeks").tag(14)
                        Text("1 month").tag(30)
                        Text("2 months").tag(60)
                    } label: {
                        Label("Days shown", systemImage: "calendar.day.timeline.leading")
                    }
                }
            }
        } menu: {
            Button { jumpToToday() } label: { Label("Jump to today", systemImage: "calendar") }
        }
        .onReceive(clock) { now = $0 }
        .onReceive(CalendarChange.moments) { now = $0 } // brief 82: a new zone or day moves the days (and the Mac board) at once
        .onAppear {
            CompletionFeedback.shared.prepare()
            sharedRows.start()
            calendarEvents.start()
            coverEvents()
        }
        // The events reach as far as the list or the board does.
        .onChange(of: dayCount) { _, _ in coverEvents() }
        .onChange(of: window) { _, _ in coverEvents() }
    }

    /// A day's events, in order (none while off): never tasks, so no count, dot or drop takes them.
    private func events(on day: Date) -> [DayEvent] { calendarEvents.events(on: day, calendar: calendar) }

    private func coverEvents() {
        let last = showsBoard ? window.days(now: now, calendar: calendar).last ?? today
            : calendar.date(byAdding: .day, value: dayCount, to: today) ?? today
        calendarEvents.cover(through: last)
    }

    private func jumpToToday() {
        if showsBoard {
            withAnimation(reduceMotion ? nil : .snappy) { window.goToToday() }
        } else {
            jumpToTodayRequest += 1
        }
    }

    // MARK: - Board

    private func board(_ entries: [Entry]) -> some View {
        let board = UpcomingBoardModel(items: entries, window: window, now: now, showOverdue: overdueExpanded, calendar: calendar)
        return UpcomingBoard(board: board, window: $window, now: now, calendar: calendar,
                             events: { events(on: $0) },
                             phase: { completions.phase(of: $0) },
                             onToggleCompletion: { toggleCompletion($0) },
                             onOpen: { open($0) },
                             onDrop: { drop($0, on: $1) },
                             // The floating quick add (a 270 pt column is too narrow for the inline card).
                             onAdd: { popouts.openQuickAdd(.day($0)) },
                             onRescheduleOverdue: { day in
                                 let held = completions.heldIDs
                                 let overdue = board.columns.first { $0.id == .overdue }?.items ?? []
                                 rescheduleAll(overdue.filter { !held.contains($0.id) }, to: day)
                             })
    }

    // MARK: - List

    private func weekList(_ entries: [Entry]) -> some View {
        let schedule = UpcomingSchedule(items: entries, now: now, dayCount: dayCount, calendar: calendar)
        return ScrollViewReader { proxy in
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
            .onChange(of: jumpToTodayRequest) { _, _ in jump(to: today, schedule: schedule, proxy: proxy) }
        }
    }

    private func list(_ schedule: UpcomingSchedule<Entry>) -> some View {
        List(selection: popouts.listSelection) {
            if !schedule.overdue.isEmpty {
                #if os(iOS)
                Section {
                    overdueHeader(schedule.overdue).headerRow()
                    if overdueExpanded {
                        ForEach(schedule.overdue) { row($0) }
                    }
                }
                #else
                Section {
                    if overdueExpanded {
                        ForEach(schedule.overdue) { row($0) }
                    }
                } header: {
                    // Outermost, like `headerRow()`: zero insets so the header text starts over the checkboxes.
                    overdueHeader(schedule.overdue).listRowInsets(EdgeInsets())
                }
                #endif
            }
            ForEach(schedule.days) { day in
                #if os(iOS)
                // iPhone: the header is the section's first row, not a pinned header. The week strip
                // already shows the day on top, and a jump lands exactly on the header (a pinned one
                // floats over the top of the rows it is scrolled to).
                Section {
                    dayHeader(day).headerRow()
                    eventRows(day.date)
                    ForEach(day.items) { row($0) }
                    addRow(day.date, isEmpty: day.items.isEmpty)
                }
                #else
                Section {
                    eventRows(day.date)
                    ForEach(day.items) { row($0) }
                    addRow(day.date, isEmpty: day.items.isEmpty)
                } header: {
                    dayHeader(day).listRowInsets(EdgeInsets())
                }
                #endif
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

    /// The day's calendar events above its tasks (brief 77): read-only rows, nothing to select, swipe or drag.
    private func eventRows(_ day: Date) -> some View {
        ForEach(events(on: day)) { event in
            CalendarEventRow(event: event, now: now, calendar: calendar)
                .calendarEventListRow(compact: compactRows)
                .id(EventRowID(day: day, event: event.id))
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry.kind {
        case .own(let task): row(task)
        case .shared(let shared): sharedRow(shared)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        let phase = completions.phase(of: task.id)
        return TaskRow(task: task, now: now, completionPhase: phase, onToggleCompletion: { toggleCompletion(task) })
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

    /// A shared task (brief 62): drawn as yours, its list's name where a Group's sits; the same swipes and menu,
    /// through the shared store; selecting it opens its editor.
    private func sharedRow(_ row: SharedRow) -> some View {
        let phase = completions.phase(of: row.id)
        return SharedTaskListRow(row: row, now: now, completionPhase: phase, onToggleCompletion: { toggleCompletion(row) })
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
                        move(row, to: calendar.date(byAdding: .day, value: 1, to: today)!)
                    } label: { Label("Tomorrow", systemImage: "sunrise") }
                    .tint(.orange)
                    Button { pickingDateFor = row.id } label: { Label("Pick Date", systemImage: "calendar") }
                        .tint(Theme.accent)
                }
            }
            // iPhone: a long press is the context menu, so rows don't drag there (swipe → Pick Date instead).
            #if os(macOS)
            .draggable(TaskRescheduling.dragPayload(for: row.id)) { DragPreview(title: row.filterTitle) }
            #endif
            .popover(isPresented: Binding(get: { pickingDateFor == row.id },
                                          set: { if !$0, pickingDateFor == row.id { pickingDateFor = nil } })) {
                PickDatePopover(initial: row.filterDueDate ?? today) { day in
                    pickingDateFor = nil
                    move(row, to: day)
                } onRemove: {
                    pickingDateFor = nil
                    move(row, to: nil)
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
            popouts.requestDelete(task) {
                if selectedTask?.id == task.id { selectedTask = nil }
                TaskActions.delete(task, in: context)
            }
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
                    Text("Overdue")
                    Text("\(overdue.count)").foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(HITColor.dueOverdue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Overdue, \(overdue.count) tasks")
            .accessibilityValue(overdueExpanded ? "Expanded" : "Collapsed")
            Spacer()
            Button("Reschedule all to today") {
                let held = completions.heldIDs
                rescheduleAll(overdue.filter { !held.contains($0.id) }, to: today)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .modifier(DayHeaderStyle())
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { headerMoved(.distantPast, to: $0) }
        .onDisappear { headerGone(.distantPast) }
        #if os(iOS)
        .id(HeaderID(day: .distantPast))
        #endif
    }

    private func dayHeader(_ day: UpcomingDay<Entry>) -> some View {
        let isToday = day.date == today
        return HStack(spacing: 6) {
            Text(UpcomingFormat.header(for: day.date, now: now, calendar: calendar))
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
        #if os(iOS)
        .id(HeaderID(day: day.date))
        #endif
    }

    @ViewBuilder
    private func addRow(_ day: Date, isEmpty: Bool) -> some View {
        if isCompact {
            // iPhone: the "+" adds; an empty day just says so.
            if isEmpty {
                Text("Nothing due")
                    .font(HITType.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .id(AddRowID(day: day))
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                    .listRowInsets(ListMetrics.rowInsets(compact: false))
                    .listRowBackground(Theme.background)
            }
        } else {
            InlineAddRow(context: .day(day), key: "day-\(day.timeIntervalSinceReferenceDate)", note: isEmpty ? "Nothing due" : nil)
                .id(AddRowID(day: day))
                .selectionDisabled()
                .slateRow()
        }
    }

    // MARK: - Week strip ↔ list

    private struct AddRowID: Hashable { let day: Date }
    /// A calendar event's row under its day (brief 77): on the Mac a jump lands on the day's first one.
    private struct EventRowID: Hashable { let day: Date; let event: String }
    /// A day header (`.distantPast` is Overdue's), the iPhone's jump target.
    private struct HeaderID: Hashable { let day: Date }

    /// Where a day's jump lands: iPhone, the day's header row; the Mac (pinned headers), the day's first
    /// calendar event, else its first task, or the add row of an empty day.
    private func scrollTarget(for day: Date, firstItem: UUID?) -> AnyHashable {
        #if os(iOS)
        AnyHashable(HeaderID(day: day))
        #else
        if let event = events(on: day).first { return AnyHashable(EventRowID(day: day, event: event.id)) }
        return firstItem.map { AnyHashable($0) } ?? AnyHashable(AddRowID(day: day))
        #endif
    }

    /// Scrolls the list to a day (see `scrollTarget`). Days before today go to the overdue section.
    private func jump(to day: Date, schedule: UpcomingSchedule<Entry>, proxy: ScrollViewProxy) {
        let animation: Animation? = reduceMotion ? nil : .snappy
        if day < today {
            guard !schedule.overdue.isEmpty else { return }
            overdueExpanded = true
            #if os(iOS)
            withAnimation(animation) { proxy.scrollTo(HeaderID(day: .distantPast), anchor: .top) }
            #else
            withAnimation(animation) { proxy.scrollTo(schedule.overdue[0].id, anchor: .top) }
            #endif
            return
        }
        let index = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if index >= dayCount {
            // Not loaded yet: grow the list, then scroll once it has laid out.
            dayCount = min(max(dayCount, index + Self.pageDays), maxDays)
            Task { @MainActor in
                await Task.yield()
                withAnimation(animation) { proxy.scrollTo(scrollTarget(for: day, firstItem: nil), anchor: .top) }
            }
            return
        }
        let target = scrollTarget(for: day, firstItem: schedule.days[index].items.first?.id)
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

    /// Reschedules dropped tasks onto `day`, keeping their times (`TaskRescheduling.drop`); a dropped shared task
    /// changes its date in the shared store, or stays put with a word when its list is view-only for you
    /// (`SharedRows.drop`, brief 62). Days before today don't take drops.
    private func drop(_ payload: [String], on day: Date) -> Bool {
        dropTarget = nil
        let moved = withAnimation(reduceMotion ? nil : .snappy) {
            TaskRescheduling.drop(payload, on: day, among: allTasks, now: now, calendar: calendar, in: context)
        }
        let shared = withAnimation(reduceMotion ? nil : .snappy) {
            sharedRows.drop(payload, on: day, now: now, calendar: calendar)
        }
        if let refused = shared.refusal { showRefusal(refused) }
        if !moved.isEmpty { rescheduleNotifications() }
        return !moved.isEmpty || !shared.moved.isEmpty
    }

    private func open(_ entry: Entry) {
        switch entry.kind {
        case .own(let task): selectedTask = task
        case .shared(let row): popouts.openShared(SharedTaskRef(row))
        }
    }

    /// A shared task to `day` (nil: no date), keeping its time; a word if its list won't take the change.
    private func move(_ row: SharedRow, to day: Date?) {
        do {
            try withAnimation(reduceMotion ? nil : .snappy) { try sharedRows.reschedule(row, to: day, calendar: calendar) }
        } catch let refusal as SharedRows.Refusal where refusal != .gone {
            showRefusal(refusal.localizedDescription)
        } catch {}
    }

    private func showRefusal(_ text: String) {
        withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { refusal = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) { if refusal == text { refusal = nil } }
        }
    }

    private func dropHover(_ hovering: Bool, on day: Date) {
        if hovering, day >= today { dropTarget = day } else if dropTarget == day { dropTarget = nil }
    }

    private func move(_ task: TaskItem, to day: Date) {
        withAnimation(reduceMotion ? nil : .snappy) { TaskActions.reschedule(task, to: day, in: context) }
        rescheduleNotifications()
    }

    /// "Reschedule all to today" and the board's Overdue Reschedule: yours, and the shared ones you may change.
    private func rescheduleAll(_ entries: [Entry], to day: Date) {
        let own = entries.compactMap(\.ownTask)
        let shared = entries.compactMap(\.sharedTask).filter(\.canWrite)
        withAnimation(reduceMotion ? nil : .snappy) {
            TaskRescheduling.reschedule(own, to: day, calendar: calendar, in: context)
            for row in shared { try? sharedRows.reschedule(row, to: day, calendar: calendar) }
        }
        rescheduleNotifications()
    }

    private func rescheduleNotifications() {
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    // MARK: - Completion (the same behaviour as TaskListView)

    private func toggleCompletion(_ entry: Entry) {
        switch entry.kind {
        case .own(let task): toggleCompletion(task)
        case .shared(let row): toggleCompletion(row)
        }
    }

    /// A shared row: completed in the shared store (who and when, so the others see it), with the same check, toast
    /// and Undo as yours. It has no repeat, so it always leaves the list.
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
        do {
            try sharedRows.setCompleted(true, row)
        } catch let refusal as SharedRows.Refusal where refusal != .gone {
            showRefusal(refusal.localizedDescription)
            return
        } catch {
            return
        }
        let token = withAnimation(HITMotion.quick) { completions.begin(row.id, anchor: row.filterDueDate) }
        CompletionFeedback.shared.taskCompleted()
        Task { await collapse(row.id, token: token) }
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

        let revert: CompletedTask.Revert = if task.recurrenceRule != nil, let due = task.dueDate {
            .restoreDueDate(due)
        } else {
            .uncomplete
        }
        let token = withAnimation(HITMotion.quick) { completions.begin(task.id, anchor: task.dueDate) }
        TaskActions.toggleCompletion(task, in: context)
        CompletionFeedback.shared.taskCompleted()
        Task { await finishCompletion(of: task, token: token) }
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
                if let shared = sharedRows.row(record.id) {
                    // Reopened in the shared store: the others see it back too.
                    if shared.task.isCompleted { try? sharedRows.setCompleted(false, shared) }
                    continue
                }
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
        try? await Task.sleep(for: CompletionMotion.hold)
        if !task.isCompleted, task.dueDate != nil {
            withAnimation(reduceMotion ? nil : .snappy) { _ = completions.remove(id, token: token) }
            return
        }
        await collapse(id, token: token, waited: true)
    }

    /// The row fades and the gap closes (`waited`: the check and flash have already had their moment).
    private func collapse(_ id: UUID, token: Int, waited: Bool = false) async {
        if !waited { try? await Task.sleep(for: CompletionMotion.hold) }
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
        // The same type and padding as every other list's headers (`taskSectionHeader`), plus the drop tint.
        content
            .font(HITType.listSectionHeader)
            .textCase(nil)
            .padding(.horizontal, ListMetrics.horizontalInset)
            .padding(.top, ListMetrics.headerTop)
            .padding(.bottom, ListMetrics.headerBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .background(Theme.accent.opacity(highlighted ? 0.18 : 0))
            // Only the drop target draws a line of its own (the list draws the header's separator).
            .overlay(alignment: .bottom) { Theme.accent.frame(height: highlighted ? 2 : 0) }
            .listRowInsets(EdgeInsets())
    }
}

#if os(iOS)
private extension View {
    /// A day header drawn as the first row of its section (iPhone): not selectable, no separator,
    /// on the slate background.
    func headerRow() -> some View {
        self
            .selectionDisabled()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background)
            // Set here, outermost: set only inside `DayHeaderStyle` the zero insets were lost on the way
            // out through the header's drop and geometry modifiers, and the header text sat 17 pt to the
            // right of the checkboxes under it.
            .listRowInsets(EdgeInsets())
    }
}
#endif

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

/// What a dragged row (or board card) looks like under the finger or pointer.
struct DragPreview: View {
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

extension ListRow where Own == TaskItem, Shared == SharedRow {
    /// A task of yours under the date Upcoming shows it on (`UpcomingView.Entry`).
    init(task: TaskItem, filterDueDate: Date?, filterIsCompleted: Bool) {
        self.init(.own(task), listedAt: filterDueDate, isCompleted: filterIsCompleted)
    }
}

/// A word for a change a shared list refused (brief 62): a capsule at the foot of Upcoming for a moment.
private struct RefusalNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HITType.footnote)
            .foregroundStyle(HITColor.text)
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, HITSpacing.s + 2)
            .background(Theme.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
            .padding(.bottom, HITSpacing.xl)
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}
