import SwiftUI
import HITListCore

/// Upcoming's Week layout (brief 161): the week's tasks on a calendar. A header with the month and the week's number,
/// a red "Overdue" while anything is, and ‹ Today ›; the day headers; a band of all-day tasks (two rows, then "N more"
/// that opens it); and one scrolling grid of hours with each timed task drawn at its time in its day's column, and a
/// line across today at the present time. iPhone: three days, moved a day at a time by a swipe; iPad and the Mac: the
/// seven days of the week, from the app's first weekday.
///
/// It only draws: `UpcomingView` owns the tasks, the completion and its toast and Undo, and passes what a tap should
/// do, as it does for the board. What each day shows is `UpcomingWeekModel`'s, which is the list's.
struct UpcomingWeekView: View {
    typealias Entry = UpcomingView.Entry

    let entries: [Entry]
    let now: Date
    var calendar: Calendar = .current
    let strip: WeekStrip
    /// Seven days (iPad, the Mac); three otherwise.
    let wholeWeek: Bool
    /// Bumped by the screen's "Jump to today".
    var todayRequest = 0
    var phase: (UUID) -> CompletionPhase? = { _ in nil }
    var onToggleCompletion: (Entry) -> Void = { _ in }
    var onOpen: (Entry) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window: UpcomingWeekWindow
    @State private var bandOpen = false
    @State private var showingOverdue = false
    @State private var gridWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var hourHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .caption2) private var gutter: CGFloat = 56

    init(entries: [Entry], now: Date, calendar: Calendar = .current, strip: WeekStrip, wholeWeek: Bool,
         todayRequest: Int = 0, phase: @escaping (UUID) -> CompletionPhase? = { _ in nil },
         onToggleCompletion: @escaping (Entry) -> Void = { _ in }, onOpen: @escaping (Entry) -> Void = { _ in }) {
        self.entries = entries
        self.now = now
        self.calendar = calendar
        self.strip = strip
        self.wholeWeek = wholeWeek
        self.todayRequest = todayRequest
        self.phase = phase
        self.onToggleCompletion = onToggleCompletion
        self.onOpen = onOpen
        _window = State(initialValue: .startingToday(strip: strip, now: now))
    }

    static let bandRows = 2
    /// The grid's text stays this far from the screen's trailing edge and the chips' edges.
    private static let edge: CGFloat = HITSpacing.m
    private var dayCount: Int { wholeWeek ? 7 : 3 }
    private var today: Date { calendar.startOfDay(for: now) }
    private var shownDays: [Date] { window.days(count: dayCount, strip: strip, now: now) }
    private var columnWidth: CGFloat {
        max(0, (gridWidth - gutter - Self.edge) / CGFloat(dayCount))
    }

    var body: some View {
        let days = shownDays
        let model = UpcomingWeekModel(items: entries, days: days, now: now, calendar: calendar)
        VStack(spacing: 0) {
            header(days: days, overdue: model.overdue)
            dayHeaders(days)
            band(model.days)
            Rectangle().fill(Theme.separator).frame(height: 1)
            grid(model.days)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .background(Theme.background)
        .simultaneousGesture(swipe, including: wholeWeek ? .subviews : .all)
        .onChange(of: todayRequest) { _, _ in goToToday() }
        .accessibilityIdentifier("upcomingWeek")
    }

    private func move(by days: Int) {
        withAnimation(reduceMotion ? nil : .snappy) { window.move(by: days) }
    }

    private func goToToday() {
        withAnimation(reduceMotion ? nil : .snappy) { window = .startingToday(strip: strip, now: now) }
    }

    /// iPhone: a sideways swipe moves the days by as many whole days as it travelled (at least one) and settles there.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) > 40, abs(dx) > abs(dy) * 1.5 else { return }
            let width = max(columnWidth, 1)
            let days = max(1, Int((abs(dx) / width).rounded()))
            move(by: dx < 0 ? days : -days)
        }
    }

    // MARK: - Header

    private func header(days: [Date], overdue: [Entry]) -> some View {
        let isAtToday = UpcomingWeekWindow.startingToday(strip: strip, now: now)
            .days(count: dayCount, strip: strip, now: now) == days
        return HStack(alignment: .center, spacing: HITSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UpcomingWeekWindow.title(of: days, calendar: calendar))
                    .font(HITType.title3)
                    .foregroundStyle(HITColor.text)
                Text("Week \(UpcomingWeekWindow.weekNumber(of: days.first ?? today, strip: strip))")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            Spacer(minLength: HITSpacing.s)
            if !overdue.isEmpty {
                Button { showingOverdue = true } label: {
                    Text("Overdue")
                        .font(HITType.control)
                        .foregroundStyle(HITColor.dueOverdue)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overdue, \(overdue.count) tasks")
                .accessibilityIdentifier("weekOverdue")
                .modifier(OverdueList(isPresented: $showingOverdue, entries: overdue, now: now, phase: phase,
                                      onToggleCompletion: onToggleCompletion, onOpen: onOpen))
            }
            HStack(spacing: 2) {
                navButton("chevron.left", label: wholeWeek ? "Previous week" : "Previous days") {
                    move(by: -dayCount)
                }
                .disabled(window.offset == 0)
                Button("Today") { goToToday() }
                    .buttonStyle(.plain)
                    .font(HITType.control)
                    .foregroundStyle(isAtToday ? Theme.secondaryText : HITColor.text)
                    .padding(.horizontal, HITSpacing.s)
                    .frame(minHeight: 28)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous))
                    .disabled(isAtToday)
                navButton("chevron.right", label: wholeWeek ? "Next week" : "Next days") { move(by: dayCount) }
            }
        }
        .padding(.horizontal, HITSpacing.l)
        .padding(.top, HITSpacing.s)
        .padding(.bottom, HITSpacing.s)
    }

    private func navButton(_ symbol: String, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(HITType.captionBold)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(HITColor.text)
        .accessibilityLabel(label)
    }

    // MARK: - Day headers

    private func dayHeaders(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { day in
                dayHeader(day).frame(width: columnWidth)
            }
            Color.clear.frame(width: Self.edge, height: 1)
        }
        .padding(.bottom, HITSpacing.s)
    }

    private func dayHeader(_ day: Date) -> some View {
        let isToday = day == today
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        return HStack(spacing: HITSpacing.xs) {
            Text(day.formatted(style.weekday(.abbreviated)))
                .foregroundStyle(isToday ? Theme.accent : Theme.secondaryText)
            Text(day.formatted(style.day()))
                .font(HITType.subheadlineSemibold)
                .monospacedDigit()
                .foregroundStyle(isToday ? HITColor.onAccent : HITColor.text)
                .padding(.horizontal, 6)
                .frame(minWidth: 28, minHeight: 28)
                .background(Circle().fill(isToday ? Theme.accent : Color.clear))
        }
        .font(HITType.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(day.formatted(style.weekday(.wide).month(.wide).day()) + (isToday ? ", today" : ""))
    }

    // MARK: - All-day band

    @ViewBuilder
    private func band(_ days: [UpcomingWeekDay<Entry>]) -> some View {
        let tallest = days.map(\.allDay.count).max() ?? 0
        if tallest > 0 {
            let opens = tallest > Self.bandRows
            HStack(alignment: .top, spacing: 0) {
                SwiftUI.Group {
                    if opens {
                        Button { withAnimation(reduceMotion ? nil : .snappy) { bandOpen.toggle() } } label: {
                            Image(systemName: "chevron.down")
                                .font(HITType.captionBold)
                                .rotationEffect(.degrees(bandOpen ? 180 : 0))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(minWidth: 28, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(bandOpen ? "Show fewer all-day tasks" : "Show every all-day task")
                        .accessibilityIdentifier("weekBandToggle")
                    } else {
                        Text("all-day")
                            .font(HITType.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(minHeight: 28)
                    }
                }
                .frame(width: gutter)
                ForEach(days, id: \.date) { day in
                    bandColumn(day).frame(width: columnWidth, alignment: .top)
                }
                Color.clear.frame(width: Self.edge, height: 1)
            }
            .padding(.bottom, HITSpacing.s)
        }
    }

    private func bandColumn(_ day: UpcomingWeekDay<Entry>) -> some View {
        let shown = bandOpen ? day.allDay : Array(day.allDay.prefix(Self.bandRows))
        let hidden = day.allDay.count - shown.count
        return VStack(spacing: HITSpacing.xs) {
            ForEach(shown) { entry in
                WeekChip(entry: entry, now: now, height: hourHeight / 2, phase: phase(entry.id),
                         onToggle: { onToggleCompletion(entry) }, onOpen: { onOpen(entry) })
            }
            if hidden > 0 {
                Button { withAnimation(reduceMotion ? nil : .snappy) { bandOpen = true } } label: {
                    Text("\(hidden) more")
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekBandMore")
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Hours

    private func hourLabel(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        let date = calendar.date(byAdding: parts, to: today) ?? today
        return date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour())
    }

    private func grid(_ days: [UpcomingWeekDay<Entry>]) -> some View {
        let showsToday = days.contains { $0.date == today }
        let opening = showsToday ? calendar.component(.hour, from: now) : 8
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // The hours: a line at the top of each, its name in the gutter.
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 0) {
                                Text(hour == 0 ? "" : hourLabel(hour))
                                    .font(HITType.caption2)
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(width: gutter - HITSpacing.s, alignment: .trailing)
                                    .padding(.trailing, HITSpacing.s)
                                    .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                                Rectangle().fill(Theme.separator).frame(height: 1)
                                    .padding(.trailing, Self.edge)
                            }
                            .frame(height: hourHeight, alignment: .top)
                            .id(hour)
                        }
                    }
                    HStack(spacing: 0) {
                        Color.clear.frame(width: gutter, height: 1)
                        ForEach(days, id: \.date) { day in
                            dayColumn(day)
                                .frame(width: columnWidth, height: 24 * hourHeight, alignment: .topLeading)
                        }
                    }
                    if showsToday, let index = days.firstIndex(where: { $0.date == today }) {
                        NowLine(start: today, calendar: calendar, hourHeight: hourHeight, gutter: gutter,
                                x: gutter + CGFloat(index) * columnWidth, width: columnWidth)
                    }
                }
                .frame(height: 24 * hourHeight, alignment: .top)
                .padding(.top, HITSpacing.m)
            }
            .scrollIndicators(.never)
            .onAppear {
                // Opened at the present hour, or at 8 AM when today is not shown.
                proxy.scrollTo(max(0, opening), anchor: .top)
            }
        }
    }

    private func dayColumn(_ day: UpcomingWeekDay<Entry>) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.separator).frame(width: 1).frame(maxHeight: .infinity)
            ForEach(day.timed, id: \.item.id) { timed in
                let width = columnWidth / CGFloat(timed.columns)
                WeekChip(entry: timed.item, now: now, height: hourHeight / 2, phase: phase(timed.item.id),
                         onToggle: { onToggleCompletion(timed.item) }, onOpen: { onOpen(timed.item) })
                    .frame(width: max(0, width - 4), alignment: .leading)
                    .offset(x: CGFloat(timed.column) * width + 2,
                            y: CGFloat(timed.minute) / 60 * hourHeight)
            }
        }
    }
}

/// The present time: a line across today's column and the time at its left in the hours' gutter, drawn again each
/// minute by a timeline of its own, only while the Week layout is on screen.
private struct NowLine: View {
    let start: Date
    let calendar: Calendar
    let hourHeight: CGFloat
    let gutter: CGFloat
    let x: CGFloat
    let width: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let minutes = context.date.timeIntervalSince(start) / 60
            let y = CGFloat(max(0, min(minutes, 24 * 60))) / 60 * hourHeight
            ZStack(alignment: .topLeading) {
                Text(context.date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                    .hour().minute()))
                    .font(HITType.caption2Semibold)
                    .foregroundStyle(HITColor.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, HITSpacing.xs)
                    .background(HITColor.dueOverdue, in: Capsule())
                    .frame(width: gutter - 2, alignment: .trailing)
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                    .offset(y: y)
                Rectangle()
                    .fill(HITColor.dueOverdue)
                    .frame(width: width, height: 2)
                    .offset(x: x, y: y - 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A task on the Week layout: its priority's colour (`Priority.color`) and its title on one line, a ring that completes
/// it through the list's own completion (with its toast and Undo), a tap that opens it as a row's tap does.
/// VoiceOver reads it as the list reads the row (`TaskRowSpeech`).
struct WeekChip: View {
    let entry: UpcomingView.Entry
    let now: Date
    /// At least 28 pt: half an hour of the grid, which grows with the text.
    let height: CGFloat
    var phase: CompletionPhase?
    var onToggle: () -> Void
    var onOpen: () -> Void

    private var priority: Priority { Priority(clamping: entry.filterPriority) }
    private var isChecked: Bool { entry.filterIsCompleted || phase != nil }
    private var canToggle: Bool { entry.sharedTask?.canWrite ?? true }
    private var tint: Color { priority == .p4 ? Theme.accent : priority.color }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous)
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(HITType.captionBold)
                    .foregroundStyle(priority == .p4 ? Theme.secondaryText : priority.color)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggle)
            Text(entry.filterTitle)
                .font(HITType.caption)
                .foregroundStyle(HITColor.text)
                .strikethrough(isChecked, color: Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HITSpacing.s)
        .frame(maxWidth: .infinity, minHeight: max(28, height), maxHeight: max(28, height), alignment: .leading)
        .background(Theme.surface, in: shape)
        .overlay(shape.fill(tint.opacity(phase == .pending ? 0.28 : 0.14)).allowsHitTesting(false))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: HITRadius.chip, bottomLeadingRadius: HITRadius.chip)
                .fill(tint).frame(width: 3)
        }
        .clipShape(shape)
        .contentShape(shape)
        .opacity(phase == .animating ? 0 : 1)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.filterTitle)
        .accessibilityValue(TaskRowSpeech.value(speech))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("weekChip")
        .accessibilityAction(.default, onOpen)
        .accessibilityActions {
            if canToggle {
                Button(TaskRowSpeech.actionName(isChecked: isChecked, isSwitch: false), action: onToggle)
            }
        }
        .help(entry.filterTitle)
    }

    /// The row's facts as Upcoming's list reads them under a day's header: the time (no day), the repeat, the priority,
    /// the labels, the Group, the description's first line.
    private var speech: TaskRowSpeech.Parts {
        var parts = TaskRowSpeech.Parts(completed: entry.filterIsCompleted, priority: priority)
        if let due = entry.filterDueDate {
            if entry.filterHasDueTime { parts.due = DueFormatter.timeText(for: due) }
            parts.overdue = DueFormatter.isOverdue(due, hasTime: entry.filterHasDueTime,
                                                   isCompleted: entry.filterIsCompleted, now: now)
            parts.repeats = entry.filterIsRecurring
        }
        if let task = entry.ownTask {
            parts.reminder = TaskRow.reminderText(for: task, now: now)
            parts.checklist = task.subtaskProgress
        }
        parts.labels = entry.filterLabelNames
        parts.group = entry.filterProjectName
        let notes = entry.filterNotes
        parts.notes = notes.isEmpty ? nil : TaskLimits.firstLine(of: notes)
        return parts
    }
}

/// The overdue tasks in the list's own rows: a sheet on an iPhone, a popover on the iPad and the Mac. A tap on a row
/// opens it as in the list; its check completes it through the list's completion.
private struct OverdueList: ViewModifier {
    @Binding var isPresented: Bool
    let entries: [UpcomingView.Entry]
    let now: Date
    let phase: (UUID) -> CompletionPhase?
    let onToggleCompletion: (UpcomingView.Entry) -> Void
    let onOpen: (UpcomingView.Entry) -> Void
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        if sizeClass == .compact {
            content.sheet(isPresented: $isPresented) {
                list.presentationDetents([.medium, .large]).slateSheet()
            }
        } else {
            content.popover(isPresented: $isPresented, arrowEdge: .top) { list.frame(width: 380, height: 420) }
        }
        #else
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) { list.frame(width: 380, height: 420) }
        #endif
    }

    private var list: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    row(entry)
                        .contentShape(Rectangle())
                        .onTapGesture { open(entry) }
                        .listRowBackground(Theme.background)
                }
            }
            .listStyle(.plain)
            .slateList()
            .navigationTitle("Overdue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("weekOverdueList")
    }

    @ViewBuilder
    private func row(_ entry: UpcomingView.Entry) -> some View {
        let phase = phase(entry.id)
        switch entry.kind {
        case .own(let task):
            TaskRow(task: task, now: now, completionPhase: phase, onToggleCompletion: { onToggleCompletion(entry) })
                .opacity(phase == .animating ? 0 : 1)
        case .shared(let row):
            SharedTaskListRow(row: row, now: now, completionPhase: phase, onToggleCompletion: { onToggleCompletion(entry) })
                .opacity(phase == .animating ? 0 : 1)
        }
    }

    /// The list closes first, then the task opens, so its card is not drawn under a closing sheet.
    private func open(_ entry: UpcomingView.Entry) {
        isPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            onOpen(entry)
        }
    }
}
