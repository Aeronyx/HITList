import SwiftUI
import HITListCore

/// Upcoming on the Mac (and a full-width iPad): Todoist's board. A header with the month, a calendar to
/// jump, and ‹ Today ›; then an Overdue column (when shown and not empty) and seven day columns side by
/// side, each about 270 pt wide and scrolling on its own, the row of columns scrolling sideways.
///
/// It only draws: `UpcomingView` owns the tasks, the window, the completion animation and its toast, and
/// passes what a click or a drop should do. Kept that way so a test can render it offscreen. The one thing
/// it opens itself is a day's inline add card (`CompactQuickAddCard`, brief 39), through the popouts.
struct UpcomingBoard: View {
    typealias Entry = UpcomingView.Entry

    let board: UpcomingBoardModel<Entry>
    @Binding var window: UpcomingWindow
    let now: Date
    var calendar: Calendar = .current
    /// The completion animation's phase for a task (`CompletionAnimator`), nil when it isn't animating.
    var phase: (UUID) -> CompletionPhase? = { _ in nil }
    var onToggleCompletion: (TaskItem) -> Void = { _ in }
    var onOpen: (TaskItem) -> Void = { _ in }
    /// Task ids dropped on a day; true if anything moved.
    var onDrop: ([String], Date) -> Bool = { _, _ in false }
    /// Not called since brief 39: a day's "+ Add task" opens the column's own inline card
    /// (`CompactQuickAddCard`) through the popouts. Kept so `UpcomingView`'s call compiles; it can go with it.
    var onAdd: (Date) -> Void = { _ in }
    /// The Overdue column's Reschedule: every overdue task to the picked day.
    var onRescheduleOverdue: (Date) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PopoutController.self) private var popouts
    @State private var dropTarget: Date?
    /// The open inline card has something typed (it says so through `onDraftChange`).
    @State private var inlineHasContent = false
    /// "Discard" is showing above the open inline card.
    @State private var confirmingDiscard = false
    @State private var pickingMonth = false
    @State private var reschedulingOverdue = false
    /// The board's trailing safe area: the system's vertical bar on the iPhone Duo's inner display on its
    /// side (brief 56); 0 on the Mac and iPad.
    @State private var trailingBar: CGFloat = 0

    static let columnWidth: CGFloat = 270
    static let columnSpacing: CGFloat = 14
    /// A card inside a column (a task, or the inline add card): the column less its 4 pt sides and the
    /// cards' 2 pt inset.
    static let cardWidth: CGFloat = columnWidth - 2 * 4 - 2 * 2

    private var today: Date { calendar.startOfDay(for: now) }

    var body: some View {
        VStack(spacing: 0) {
            header
            columns
                // A sideways scroll view runs under a trailing safe area (it only adds it as a content
                // inset), so the Duo's vertical bar floated over the last column on screen. The columns stop
                // at the bar instead; the background still runs under it.
                .padding(.trailing, trailingBar)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { trailingBar = $0 }
        .background(Theme.background)
        .onChange(of: openInlineKey) { _, _ in
            inlineHasContent = false
            confirmingDiscard = false
        }
        // Leaving Upcoming with an empty card open puts it away; one with typing stays (stored, as every
        // open card is) and is there again when the board comes back.
        .onDisappear {
            if openInlineKey != nil, !inlineHasContent { popouts.closeQuickAdd() }
        }
        // The month calendar and the Reschedule card are the popouts' picker cards (drawn inside the window
        // on the Mac, popovers on iPad).
        .pickerOverlay()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: HITSpacing.m) {
            Button { pickingMonth = true } label: {
                HStack(spacing: 6) {
                    Text(window.title(now: now, calendar: calendar))
                        .font(HITType.title3)
                        .foregroundStyle(HITColor.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(window.title(now: now, calendar: calendar)), pick a day")
            .help("Jump to a day")
            .pickerAnchor(.date, isPresented: $pickingMonth) {
                HITCalendar(selection: window.start(now: now, calendar: calendar), today: now,
                            weekStart: Preferences.weekStartWeekday(), calendar: calendar) { day in
                    pickingMonth = false
                    move { $0.jump(to: day, now: now, calendar: calendar) }
                }
                .padding(HITSpacing.m)
            }
            Spacer(minLength: HITSpacing.m)
            HStack(spacing: 2) {
                navButton("chevron.left", label: "Previous day", help: "One day back") {
                    $0.move(by: -1)
                }
                .disabled(window.isAtToday)
                Button("Today") { move { $0.goToToday() } }
                    .buttonStyle(.plain)
                    .font(HITType.control)
                    .foregroundStyle(window.isAtToday ? Theme.secondaryText : HITColor.text)
                    .padding(.horizontal, HITSpacing.s)
                    .frame(height: 26)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .disabled(window.isAtToday)
                    .help("Back to today")
                navButton("chevron.right", label: "Next day", help: "One day ahead") {
                    $0.move(by: 1)
                }
            }
        }
        .padding(.horizontal, HITSpacing.l)
        .padding(.top, HITSpacing.m)
        .padding(.bottom, HITSpacing.s)
    }

    private func navButton(_ symbol: String, label: String, help: String,
                           _ change: @escaping (inout UpcomingWindow) -> Void) -> some View {
        Button { move(change) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(HITColor.text)
        .accessibilityLabel(label)
        .help(help)
    }

    private func move(_ change: (inout UpcomingWindow) -> Void) {
        withAnimation(reduceMotion ? nil : .snappy) { change(&window) }
    }

    // MARK: - Columns

    private var columns: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Self.columnSpacing) {
                ForEach(board.columns) { column in
                    columnView(column)
                        .frame(width: Self.columnWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, HITSpacing.l)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
        // While an inline card is open, a click on the board outside every card and button is a click away.
        // The card, the task cards and the buttons take their own clicks first.
        .gesture(TapGesture().onEnded { clickAway() }, including: openInlineKey == nil ? .subviews : .all)
    }

    // MARK: - Inline add (brief 39)

    /// The board card that is open, if the open quick add is one of the board's.
    private var openInlineKey: String? { BoardInlineAdd.openKey(in: popouts.state) }

    /// A click somewhere else on the board while a card is open. An empty card closes and `then` runs;
    /// with typing, "Discard" shows and nothing else happens; with "Discard" showing, back to typing.
    private func clickAway(then action: (() -> Void)? = nil) {
        guard let key = openInlineKey else { action?(); return }
        switch BoardInlineAdd.clickAway(hasContent: inlineHasContent, confirmingDiscard: confirmingDiscard) {
        case .close:
            popouts.closeInline(key)
            action?()
        case .askDiscard:
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .keepEditing:
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
        }
    }

    /// × or Escape on the card: an empty card closes; with typing "Discard" shows first, and a second ×
    /// or Escape discards.
    private func requestClose(_ key: String) {
        switch BoardInlineAdd.close(hasContent: inlineHasContent, confirmingDiscard: confirmingDiscard) {
        case .close:
            popouts.closeInline(key)
        case .askDiscard:
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .discard:
            popouts.discardQuickAddDraft()
            popouts.closeInline(key)
        }
    }

    private func openInline(_ context: QuickAddContext, day: Date) {
        let key = BoardInlineAdd.key(for: day, calendar: calendar)
        guard openInlineKey != key else { return }
        clickAway { popouts.openQuickAdd(context, placement: .inline(key)) }
    }

    @ViewBuilder
    private func addSlot(_ context: QuickAddContext, day: Date) -> some View {
        let key = BoardInlineAdd.key(for: day, calendar: calendar)
        if popouts.state.isInlineOpen(key) {
            CompactQuickAddCard(context: context, isConfirmingDiscard: confirmingDiscard,
                                onClose: { requestClose(key) },
                                onSaved: { popouts.didSave() },
                                onDraftChange: { inlineHasContent = $0 },
                                onDiscard: {
                                    popouts.discardQuickAddDraft()
                                    popouts.closeInline(key)
                                },
                                onKeepEditing: {
                                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
                                })
                // One view per card, so a card opened again starts from its own (empty) draft.
                .id(popouts.state.quickAdd?.id)
                .transition(.opacity)
        } else {
            AddTaskCardRow { openInline(context, day: day) }
                // First-run tip (brief 52), on today's column only.
                .hitTip(calendar.isDate(day, inSameDayAs: today) ? HITTip(.boardAddTask) : nil)
        }
    }

    private func columnView(_ column: UpcomingBoardModel<Entry>.Column) -> some View {
        let targeted = column.day != nil && dropTarget == column.day
        return VStack(alignment: .leading, spacing: 0) {
            columnHeader(column)
            Rectangle().fill(targeted ? Theme.accent : Theme.separator).frame(height: targeted ? 2 : 1)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: HITSpacing.s) {
                        ForEach(column.items) { entry in
                            card(entry, inOverdue: column.day == nil)
                        }
                        if let day = column.day, let context = column.addContext {
                            addSlot(context, day: day)
                                .id(Self.addSlotID)
                        }
                    }
                    .padding(.vertical, HITSpacing.s)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                // The column scrolls so its card is in view when it opens and after each task it adds.
                .onChange(of: inlineCardRevision(for: column)) { _, revision in
                    guard revision != nil else { return }
                    Task { @MainActor in
                        withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(Self.addSlotID, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
                .fill(Theme.accent.opacity(targeted ? 0.10 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
                .strokeBorder(Theme.accent.opacity(targeted ? 0.55 : 0), lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .modifier(DayDropTarget(day: column.day, today: today, dropTarget: $dropTarget,
                                reduceMotion: reduceMotion, onDrop: onDrop))
    }

    /// The add slot's scroll id inside its column.
    private static let addSlotID = "boardAddSlot"

    /// Changes when this column's card opens and when it adds a task; nil while it has none.
    private func inlineCardRevision(for column: UpcomingBoardModel<Entry>.Column) -> Int? {
        guard let day = column.day, let quickAdd = popouts.state.quickAdd,
              quickAdd.placement == .inline(BoardInlineAdd.key(for: day, calendar: calendar)) else { return nil }
        return quickAdd.id.hashValue &+ quickAdd.savedCount
    }

    private func columnHeader(_ column: UpcomingBoardModel<Entry>.Column) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let day = column.day {
                Text(UpcomingFormat.boardHeader(for: day, now: now, calendar: calendar))
                    .foregroundStyle(day == today ? Theme.accent : HITColor.text)
                    .lineLimit(1)
            } else {
                Text("Overdue").foregroundStyle(HITColor.dueOverdue)
            }
            if column.count > 0 {
                Text("\(column.count)").foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: HITSpacing.s)
            if column.day == nil {
                Button("Reschedule") { reschedulingOverdue = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .help("Move every overdue task to another day")
                    .pickerAnchor(.date, isPresented: $reschedulingOverdue) {
                        DatePickerCard(selected: nil, now: now) { day in
                            reschedulingOverdue = false
                            if let day { onRescheduleOverdue(day) }
                        }
                    }
            }
        }
        .font(HITType.listSectionHeader)
        .padding(.horizontal, 6)
        .padding(.top, HITSpacing.s)
        .padding(.bottom, HITSpacing.s + 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cards

    private func card(_ entry: Entry, inOverdue: Bool) -> some View {
        let task = entry.task
        let phase = phase(task.id)
        // `TaskRow` itself, so the checkbox, its sound and motion, the meta line and the context menu are
        // the lists'. In a day column the day is in the header, so the card shows only the time (and the
        // repeat icon); Overdue shows the date.
        return BoardCard(flashing: phase == .pending) {
            TaskRow(task: task, now: now, hidesDay: !inOverdue, completionPhase: phase,
                    onToggleCompletion: { onToggleCompletion(task) })
                // A crowded card's meta line takes a second line rather than truncating (brief 56).
                .environment(\.taskMetaWraps, true)
        }
        .opacity(phase == .animating ? 0 : 1)
        // With a card open, a click on a task is a click away first.
        .onTapGesture { clickAway { onOpen(task) } }
        .draggable(TaskRescheduling.dragPayload(for: task.id)) { DragPreview(title: task.title) }
        .accessibilityAction(named: "Open") { onOpen(task) }
    }
}

/// One task on the board: `Theme.surface` in the design system's card radius with a hairline border; a
/// little lighter under the pointer, accent-tinted while its completion flashes.
private struct BoardCard<Content: View>: View {
    var flashing = false
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        content
            .padding(.horizontal, HITSpacing.m)
            .padding(.vertical, HITSpacing.s + 2)
            .background(hovering ? Theme.elevated : Theme.surface, in: shape)
            .overlay(shape.fill(Theme.accent.opacity(flashing ? 0.12 : 0)).allowsHitTesting(false))
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// "+ Add task" at the foot of a day column.
private struct AddTaskCardRow: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.s) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                Text("Add task")
                    .foregroundStyle(hovering ? Theme.accent : Theme.secondaryText)
                Spacer(minLength: 0)
            }
            .font(HITType.body)
            .padding(.horizontal, HITSpacing.m - 2)
            .padding(.vertical, HITSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityIdentifier("boardAddTask")
    }
}

/// A day column takes dropped tasks (their ids as strings) and says so while one hovers over it. Overdue
/// (no day) and days before today take nothing.
private struct DayDropTarget: ViewModifier {
    let day: Date?
    let today: Date
    @Binding var dropTarget: Date?
    let reduceMotion: Bool
    let onDrop: ([String], Date) -> Bool

    func body(content: Content) -> some View {
        if let day, day >= today {
            content.dropDestination(for: String.self) { items, _ in
                dropTarget = nil
                return onDrop(items, day)
            } isTargeted: { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    if hovering { dropTarget = day } else if dropTarget == day { dropTarget = nil }
                }
            }
        } else {
            content
        }
    }
}
