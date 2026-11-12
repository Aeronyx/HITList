import SwiftUI
import SwiftData
import HITListCore
import TipKit

/// Review Inbox (brief 60): the unsorted tasks (no date, no Group; `InboxReview`) one card at a time, oldest
/// first. On iPhone, swipe the card right for Today or left to delete (Undo in the toast); under it, Pick a
/// date, Move to a Group and Later (it stays in the Inbox as it is). Edit… opens the task editor for
/// everything else (labels, priority, tomorrow, notes). The last card gives way to the empty state.
///
/// Keys on macOS (and iPad with a keyboard): T today, D pick a date, P Group, ⌫ delete (undo with ⌘Z),
/// → later, Return edit the title, Esc close. They are off while the title is being edited or a picker is
/// open, so typing never triggers them. The Mac has no swipes: its card lists the keys and each is clickable.
struct InboxProcessView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var queue = InboxProcessQueue(tasks: [])
    @State private var started = false
    @State private var now = Date()
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var popover: Popover?
    /// Where the open card hangs (brief 107): over the actions, or from the line under the task's title.
    @State private var popoverPlace = ReviewPopoverPlace.actions
    /// The title's foot and the actions' top, measured as they move and read only as a card opens.
    @State private var frames = ReviewFrames()
    /// The task editor, opened by Edit… in a sheet over the review (its own presenter, so closing it comes
    /// back here rather than to the list underneath).
    @State private var editor: PopoutController?
    /// A deleted task stays in the store until its undo toast expires, the next delete, or closing.
    @State private var pendingDelete: PendingDelete?
    @State private var deleteGeneration = 0

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum Popover { case date, project }

    private struct PendingDelete {
        let id: UUID
        let title: String
        let generation: Int
    }

    private var unsortedTasks: [TaskItem] { allTasks.filter(\.needsReview) }
    private var unsortedIDs: Set<UUID> { Set(unsortedTasks.map(\.id)) }

    private var current: TaskItem? {
        guard let id = queue.current else { return nil }
        return allTasks.first { $0.id == id }
    }

    private var shortcutsEnabled: Bool { !editingTitle && popover == nil && editor == nil && current != nil }

    private var swipes: Bool {
        #if os(iOS)
        !editingTitle && popover == nil
        #else
        false
        #endif
    }

    private var parser: QuickAddParser {
        QuickAddParser(knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                       weekStart: Preferences.weekStartWeekday())
    }

    private var stepAnimation: Animation? { HITMotion.enter(reduceMotion: reduceMotion) }

    /// The next card rises from behind the one that left; a card sent on by a button fades back as it goes.
    /// (A swiped card has already flown off or faded by then.)
    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                                              removal: .scale(scale: 0.96).combined(with: .opacity))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let task = current {
                review(task)
            } else if started {
                finished
                    .transition(.opacity)
            } else {
                Spacer()
            }
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            if let pendingDelete {
                DeletedToast(title: pendingDelete.title, undoShortcut: !editingTitle && editor == nil, onUndo: undoDelete)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 600, idealHeight: 660)
        #endif
        .slateSheet()
        .sheet(isPresented: editorShown) { editorSheet }
        .onAppear(perform: start)
        .onChange(of: unsortedIDs) { _, _ in withAnimation(stepAnimation) { queue.retainReview(of: allTasks) } }
        .onChange(of: queue.current) { _, _ in endEditing(save: false) }
        .onChange(of: titleFocused) { _, focused in
            // Clicking away from the title keeps the edit.
            if !focused, editingTitle, let task = current { applyTitleEdit(to: task) }
        }
        .onReceive(clock) { now = $0 }
        .onReceive(CalendarChange.moments) { now = $0 } // brief 82's follow-up: a new zone or day shows at once, not at the next minute
        .onDisappear(perform: commitDelete)
    }

    // MARK: - Layout

    /// "Review Inbox", what it goes through, and a dot per task.
    private var topBar: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Inbox")
                        .font(HITType.title2Bold)
                        .accessibilityAddTraits(.isHeader)
                    if !queue.isFinished {
                        Text(InboxText.reviewSubtitle(count: queue.total))
                            .font(HITType.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .contentTransition(.numericText())
                    }
                }
                Spacer()
                // The accent pill, as every sheet's Done (brief 99: it was an outlined capsule here).
                Button("Done") { dismiss() }
                    .buttonStyle(.hitPrimary)
                    .keyboardShortcut(editingTitle ? nil : .cancelAction)
                    .help("Close (Esc)")
            }
            if !queue.isFinished {
                ReviewDots(done: queue.finished, total: queue.total)
                    .accessibilityElement()
                    .accessibilityLabel("Task \(queue.position) of \(queue.total)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func review(_ task: TaskItem) -> some View {
        VStack(spacing: HITSpacing.l) {
            ZStack {
                ReviewSwipeCard(enabled: swipes, onCommit: { act($0, on: task) }) {
                    cardContent(task)
                }
                .frame(maxHeight: 460)
                .id(task.id)
                .transition(cardTransition)
            }
            .frame(maxHeight: .infinity)
            actions(task)
        }
        .padding(20)
        // Room for the undo toast.
        .padding(.bottom, 40)
        .background(keyOnlyShortcuts(task))
    }

    private func cardContent(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            title(task)
            Text(InboxText.added(task.createdAt, now: now))
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { frames.titleBottom = $0 }
                // A short screen (the iPhone Duo's outer display): the card hangs from here, under the title, rather
                // than rising over it from the actions (its arrow on its top edge).
                .popover(isPresented: isOpen(.date, at: .underTitle), arrowEdge: .top) { dateCard(task) }
                .popover(isPresented: isOpen(.project, at: .underTitle), arrowEdge: .top) { groupCard(task) }
            if !task.notes.isEmpty, !editingTitle {
                Text(task.notes)
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(8)
                    .padding(.top, HITSpacing.xs)
            }
            Spacer(minLength: HITSpacing.l)
            #if os(iOS)
            if !editingTitle {
                TipView(HITTip(.reviewSwipe))
                    .tipViewStyle(HITTipStyle())
                    .tipBackground(Theme.elevated)
            }
            #endif
            HStack(alignment: .bottom) {
                #if os(macOS)
                keyHints(task)
                #endif
                Spacer(minLength: 0)
                Button("Edit…") { edit(task) }
                    .buttonStyle(.plain)
                    .font(HITType.subheadlineMedium)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("reviewEdit")
                    .help("Labels, priority, notes and more")
            }
        }
        .padding(HITSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func title(_ task: TaskItem) -> some View {
        if editingTitle {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Task name", text: $titleDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(HITType.title1)
                    .focused($titleFocused)
                    .onSubmit { submitTitle(task) }
                    .onAppear { titleFocused = true }
                    #if os(macOS)
                    .onExitCommand { endEditing(save: false) }
                    #else
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    #endif
                tokenChips
                Text("Return saves. Dates, #group, @label and p1–p4 work as in quick add.")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            Button {
                titleDraft = task.title
                editingTitle = true
            } label: {
                Text(task.title)
                    .font(HITType.title1)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(shortcutsEnabled ? .defaultAction : nil)
            .help("Edit the title (Return)")
            .accessibilityHint("Edits the title")
            .accessibilityIdentifier("reviewTitle")
        }
    }

    /// What Return will apply, like quick add's chips.
    @ViewBuilder
    private var tokenChips: some View {
        let p = parser.parse(titleDraft)
        HStack(spacing: 6) {
            if let due = p.dueDate { chip(DueFormatter.text(for: due, hasTime: p.hasDueTime, now: now), "calendar", .blue) }
            if let r = p.recurrence { chip(r.displayText, "repeat", .teal) }
            if p.priority != .p4 { chip(p.priority.shortName, "flag.fill", p.priority.color) }
            if let name = p.projectName {
                let known = projects.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                chip(known ? "#\(name)" : "#\(name) (new)", "number", known ? .purple : .orange)
            }
            ForEach(p.labelNames, id: \.self) { chip("@\($0)", "tag", .gray) }
        }
    }

    private func chip(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(HITType.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// The three big buttons under the card.
    private func actions(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            action("Pick a date", "calendar", key: "D", tint: HITColor.dueTomorrow,
                   shortcut: KeyboardShortcut("d", modifiers: []), id: "reviewPickDate") {
                open(.date)
            }
            .popover(isPresented: isOpen(.date, at: .actions)) { dateCard(task) }
            // "Pick a Group" (was "Move to a Group", which was shrunk to fit its button on every iPhone; brief 107): the
            // card it opens still says "Move to a Group".
            action("Pick a Group", "number", key: "P", tint: HITColor.dueLater,
                   shortcut: KeyboardShortcut("p", modifiers: []), id: "reviewMoveToGroup") {
                open(.project)
            }
            .popover(isPresented: isOpen(.project, at: .actions)) { groupCard(task) }
            action("Later", "clock", key: "→", tint: Theme.secondaryText,
                   shortcut: KeyboardShortcut(.rightArrow, modifiers: []), id: "reviewLater") {
                endEditing(save: true)
                withAnimation(stepAnimation) { queue.later() }
            }
        }
        // Every tile as tall as the tallest (a name on two lines makes its tile a line taller).
        .fixedSize(horizontal: false, vertical: true)
    }

    /// From a tile's sides to its name (brief 115: "Pick a Group" came 6 pt from its tile's sides on the Duo's outer
    /// display): a name wider than that wraps onto a second line at the same size rather than nearing the border.
    /// 8 pt, the floor for a label inside a button: at 10 "Pick a Group" wrapped on an iPhone 16 as well, between two
    /// names on one line; at 8 it wraps only on the Duo's narrower tiles.
    static let tileLabelInset: CGFloat = 8
    static let tileIconHeight: CGFloat = 30

    private func action(_ title: String, _ symbol: String, key: String, tint: Color,
                        shortcut: KeyboardShortcut, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    #if os(iOS)
                    // One height for the three symbols (the clock is taller than the calendar), so the names below
                    // them start on one line.
                    .frame(height: Self.tileIconHeight)
                    #endif
                Text(title)
                    .font(HITType.subheadlineMedium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(macOS)
                KeyCap(key)
                #endif
            }
            .padding(.horizontal, Self.tileLabelInset)
            #if os(iOS)
            // The icons on one line and the names' first lines on one line, across the three tiles.
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: .infinity, alignment: .top)
            #else
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: .infinity)
            #endif
            .contentShape(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous))
        }
        .buttonStyle(ReviewButtonStyle())
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { frames.actionsTop = $0 }
        .keyboardShortcut(shortcutsEnabled ? shortcut : nil)
        .help("\(title) (\(key))")
        .accessibilityIdentifier(id)
    }

    #if os(macOS)
    /// The Mac card's keys line: Today and Delete have no swipe on the Mac, so they are here, clickable.
    private func keyHints(_ task: TaskItem) -> some View {
        HStack(spacing: HITSpacing.m) {
            KeyHint(key: "T", title: "Today", shortcut: shortcutsEnabled ? KeyboardShortcut("t", modifiers: []) : nil) {
                act(.today, on: task)
            }
            KeyHint(key: "⌫", title: "Delete", tint: HITColor.danger,
                    shortcut: shortcutsEnabled ? KeyboardShortcut(.delete, modifiers: []) : nil) {
                act(.delete, on: task)
            }
        }
    }
    #endif

    /// T and ⌫ for a keyboard on iPad (on the Mac the keys line carries them); invisible.
    @ViewBuilder
    private func keyOnlyShortcuts(_ task: TaskItem) -> some View {
        #if os(iOS)
        ZStack {
            Button("Today") { act(.today, on: task) }
                .keyboardShortcut(shortcutsEnabled ? KeyboardShortcut("t", modifiers: []) : nil)
            Button("Delete") { act(.delete, on: task) }
                .keyboardShortcut(shortcutsEnabled ? KeyboardShortcut(.delete, modifiers: []) : nil)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        #endif
    }

    /// "Inbox reviewed" with the checkmark; tasks put off with Later are counted under it.
    private var finished: some View {
        let left = unsortedTasks.filter { $0.id != pendingDelete?.id }.count
        return VStack(spacing: 0) {
            InboxZeroView(title: InboxText.reviewedTitle, message: InboxText.reviewedMessage(left: left))
            Button("Done") { dismiss() }
                .buttonStyle(.hitPrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("reviewDone")
        }
        // Clear of the undo toast.
        .padding(.bottom, 96)
    }

    // MARK: - Editor

    private var editorShown: Binding<Bool> {
        Binding(get: { editor?.task != nil },
                set: { if !$0 { editor?.closeTask(); editor = nil } })
    }

    @ViewBuilder
    private var editorSheet: some View {
        if let editor, let task = editor.task {
            TaskPopout(task: task)
                .environment(editor)
                .presentationDetents(PopoutHost.editorDetents)
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
                .presentationCornerRadius(HITRadius.card + 10)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 460, idealWidth: 500, minHeight: 520)
                #endif
                .confirmationDialog(editor.pendingDelete.map { "Delete “\($0.title)”?" } ?? "Delete?",
                                    isPresented: Binding(get: { editor.pendingDelete != nil },
                                                         set: { if !$0 { editor.cancelPendingDelete() } }),
                                    titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { editor.confirmPendingDelete() }
                    Button("Cancel", role: .cancel) { editor.cancelPendingDelete() }
                } message: {
                    Text("This can't be undone.")
                }
                .onDisappear { self.editor = nil }
        }
    }

    private func edit(_ task: TaskItem) {
        endEditing(save: true)
        let controller = PopoutController()
        controller.open(task)
        editor = controller
    }

    // MARK: - Actions

    private func start() {
        guard !started else { return }
        queue = InboxProcessQueue(reviewOf: allTasks)
        started = true
        CompletionFeedback.shared.prepare()
    }

    private func isOpen(_ which: Popover, at place: ReviewPopoverPlace) -> Binding<Bool> {
        Binding(get: { popover == which && popoverPlace == place },
                set: { if !$0, popover == which, popoverPlace == place { popover = nil } })
    }

    private func open(_ which: Popover) {
        endEditing(save: true)
        #if os(iOS)
        let height = which == .date ? DatePickerCardLayout.regularHeight(hasFoot: false) : InboxPicker.height(options: projects.count)
        popoverPlace = ReviewPopoverPlace.place(cardHeight: height, titleBottom: frames.titleBottom, actionsTop: frames.actionsTop)
        #endif
        popover = which
    }

    private func dateCard(_ task: TaskItem) -> some View {
        PickDatePopover(selected: task.dueDate, now: now) { day in
            popover = nil
            schedule(task, to: day)
        }
    }

    private func groupCard(_ task: TaskItem) -> some View {
        InboxPicker(options: projects.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex) }) { choice in
            popover = nil
            move(task, to: choice)
        }
    }

    private func advance() {
        withAnimation(stepAnimation) { queue.advance() }
    }

    /// A swipe (or T / ⌫) on `task`, the card on screen.
    private func act(_ direction: InboxReviewSwipe.Direction, on task: TaskItem) {
        guard task.id == queue.current else { return }
        // They know the swipe (or the key) now.
        HITTip(.reviewSwipe).invalidate(reason: .actionPerformed)
        switch direction {
        case .today: schedule(task, to: TaskRescheduling.QuickDate.today.date(now: now))
        case .delete: delete(task)
        }
    }

    private func schedule(_ task: TaskItem, to day: Date) {
        endEditing(save: true)
        TaskActions.reschedule(task, to: day, in: context)
        rescheduleNotifications()
        advance()
    }

    private func move(_ task: TaskItem, to choice: InboxPicker.Choice) {
        let project: Project? = switch choice {
        case .existing(let id): projects.first { $0.id == id }
        case .new(let name): try? TaskActions.findOrCreateProject(named: name, in: context)
        }
        guard let project else { return }
        task.project = project
        task.touch()
        try? context.save()
        advance()
    }

    /// Hides the task and offers Undo; the delete itself (which syncs to every device) waits until
    /// the toast goes away.
    private func delete(_ task: TaskItem) {
        endEditing(save: false)
        commitDelete()
        if selectedTask?.id == task.id { selectedTask = nil }
        deleteGeneration += 1
        let pending = PendingDelete(id: task.id, title: task.title, generation: deleteGeneration)
        withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { pendingDelete = pending }
        advance()
        AccessibilityNotification.Announcement("Deleted \(task.title)").post()
        Task {
            try? await Task.sleep(for: CompletionToastState.lifetime)
            guard pendingDelete?.generation == pending.generation else { return }
            withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) { commitDelete() }
        }
    }

    private func commitDelete() {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        guard let task = allTasks.first(where: { $0.id == pending.id }) else { return }
        TaskActions.delete(task, in: context)
        rescheduleNotifications()
    }

    private func undoDelete() {
        guard let pending = pendingDelete else { return }
        withAnimation(stepAnimation) {
            pendingDelete = nil
            queue.restore(pending.id)
        }
    }

    // MARK: - Title editing

    private func submitTitle(_ task: TaskItem) {
        if applyTitleEdit(to: task) { advance() }
    }

    private func endEditing(save: Bool) {
        guard editingTitle else { return }
        if save, let task = current {
            applyTitleEdit(to: task)
        } else {
            editingTitle = false
            titleFocused = false
        }
    }

    /// Applies the edited title the way quick add reads text: a date, priority, #project and @labels
    /// are taken out and set on the task, the rest is the title. Returns whether that scheduled the
    /// task or moved it to a Group, which counts as handling it.
    @discardableResult
    private func applyTitleEdit(to task: TaskItem) -> Bool {
        editingTitle = false
        titleFocused = false
        let text = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != task.title else { return false }
        let parsed = parser.parse(text)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { task.title = title }
        var handled = false
        if let due = parsed.dueDate {
            task.dueDate = due
            task.hasDueTime = parsed.hasDueTime
            if let rule = parsed.recurrence { task.recurrenceRule = rule }
            handled = true
        }
        if parsed.priority != .p4 { task.priorityValue = parsed.priority }
        if let name = parsed.projectName, let project = try? TaskActions.findOrCreateProject(named: name, in: context) {
            task.project = project
            handled = true
        }
        for name in parsed.labelNames {
            guard let label = try? TaskActions.findOrCreateLabel(named: name, in: context),
                  !(task.labels ?? []).contains(where: { $0.id == label.id }) else { continue }
            task.labels = (task.labels ?? []) + [label]
        }
        task.touch()
        try? context.save()
        if parsed.dueDate != nil { rescheduleNotifications() }
        return handled
    }

    private func rescheduleNotifications() {
        Task { await NotificationScheduler.reschedule(context: context) }
    }
}

/// The card's moving shell: it follows a horizontal drag (`InboxReviewSwipe`), glows green towards Today or
/// red towards Delete, shows its stamp past the threshold, and on a commit flies off that side (under
/// Reduce Motion it fades where it is) before `onCommit` runs. Its state is its own, so a card that left
/// stays gone while the next one arrives.
private struct ReviewSwipeCard<Content: View>: View {
    let enabled: Bool
    let onCommit: (InboxReviewSwipe.Direction) -> Void
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipe = InboxReviewSwipe()
    /// Decided by the first movement: a mostly vertical drag is left to the sheet.
    @State private var horizontal: Bool?
    @State private var gone = false
    @State private var width: CGFloat = 400

    private var armed: InboxReviewSwipe.Direction? {
        if case .armed(let d) = swipe.phase { return d }
        if case .committed(let d) = swipe.phase { return d }
        return nil
    }

    private var glow: Color {
        swipe.direction == .delete ? HITColor.danger : HITColor.dueToday
    }

    private var offset: CGFloat {
        guard gone, !reduceMotion, let direction = swipe.direction else { return swipe.offset }
        return (direction == .today ? 1 : -1) * (width + 160)
    }

    var body: some View {
        content
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.separator))
            .overlay(shape.strokeBorder(glow.opacity(swipe.progress), lineWidth: 2))
            // In the card's middle, clear of the title.
            .overlay { stamp("Today", color: HITColor.dueToday, angle: -12, shown: armed == .today) }
            .overlay { stamp("Delete", color: HITColor.danger, angle: 12, shown: armed == .delete) }
            .shadow(color: glow.opacity(0.45 * swipe.progress), radius: 24 * swipe.progress)
            .offset(x: offset)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset) / 24), anchor: .bottom)
            .opacity(gone && reduceMotion ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(drag, including: enabled ? .all : .subviews)
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new != nil }
            #endif
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Today") { commit(.today) }
            .accessibilityAction(named: "Delete") { commit(.delete) }
            .accessibilityIdentifier("reviewCard")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: HITRadius.card + 6, style: .continuous) }

    private func stamp(_ text: String, color: Color, angle: Double, shown: Bool) -> some View {
        Text(text)
            .font(HITType.largeTitle)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, HITSpacing.s)
            .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous).strokeBorder(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
            .opacity(shown ? 1 : 0)
            .animation(HITMotion.standard(reduceMotion: reduceMotion) ?? .linear(duration: 0), value: shown)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !swipe.isCommitted else { return }
                if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) }
                guard horizontal == true else { return }
                swipe.drag(to: value.translation.width)
            }
            .onEnded { value in
                defer { horizontal = nil }
                guard horizontal == true, !swipe.isCommitted else { return }
                var next = swipe
                if case .committed(let direction) = next.release(velocity: value.velocity.width) {
                    swipe = next
                    leave(direction)
                } else {
                    withAnimation(HITMotion.emphasis(reduceMotion: reduceMotion)) { swipe = next }
                }
            }
    }

    /// VoiceOver's actions: arm the card fully that way, then leave as a swipe would.
    private func commit(_ direction: InboxReviewSwipe.Direction) {
        guard !swipe.isCommitted else { return }
        swipe.drag(to: (direction == .today ? 1 : -1) * InboxReviewSwipe.threshold)
        swipe.release(velocity: 0)
        leave(direction)
    }

    private func leave(_ direction: InboxReviewSwipe.Direction) {
        withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) { gone = true }
        let delay = reduceMotion ? 0.1 : HITMotion.Role.exit.arrival
        Task {
            try? await Task.sleep(for: .seconds(delay))
            onCommit(direction)
        }
    }
}

/// A dot per task in the review: reviewed ones filled, the current one wider, the rest hollow. A long
/// review (more dots than fit) is a bar instead.
private struct ReviewDots: View {
    let done: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let maxDots = 16

    var body: some View {
        SwiftUI.Group {
            if total <= Self.maxDots {
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { index in
                        Capsule()
                            .fill(index < done ? Theme.accent : index == done ? Theme.accent : Theme.separator)
                            .opacity(index < done ? 0.55 : 1)
                            .frame(width: index == done ? 18 : 7, height: 7)
                    }
                }
            } else {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }
        }
        .animation(HITMotion.emphasis(reduceMotion: reduceMotion), value: done)
    }
}

/// Big slate tiles for the review's buttons.
private struct ReviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.separator : Theme.elevated,
                        in: RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous).strokeBorder(Theme.separator))
    }
}

#if os(macOS)
/// "T", "⌫": a key as the Mac shows it.
private struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.caption2.weight(.semibold).monospaced())
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// "T Today" on the Mac card: the key and what it does, clickable.
private struct KeyHint: View {
    let key: String
    let title: String
    var tint: Color = HITColor.dueToday
    let shortcut: KeyboardShortcut?
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                KeyCap(key)
                Text(title)
                    .font(HITType.subheadlineMedium)
                    .foregroundStyle(tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .help("\(title) (\(key))")
    }
}
#endif

/// Where Review Inbox's date and Group cards open (brief 107). Over the actions, as they always have, when the card fits
/// between them and the task's title; otherwise (the iPhone Duo's outer display: 295 pt between them for a 309 pt
/// calendar, which covered the title) hanging from the line under the title, so the task it is about stays in sight.
/// Pure, so tests pin it.
enum ReviewPopoverPlace: Equatable {
    case actions, underTitle

    static func place(cardHeight: CGFloat, titleBottom: CGFloat, actionsTop: CGFloat) -> Self {
        let needs = cardHeight + PhonePickerPlacement.arrow + PhonePickerPlacement.margin
        return actionsTop - titleBottom >= needs ? .actions : .underTitle
    }
}

/// The title's foot and the actions' top, in the window; a reference, so measuring redraws nothing.
final class ReviewFrames {
    var titleBottom: CGFloat = 0
    var actionsTop: CGFloat = .greatestFiniteMagnitude
}

/// "Deleted ‘Title’ · Undo", styled like the completion toast.
private struct DeletedToast: View {
    let title: String
    var undoShortcut: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash").foregroundStyle(HITColor.danger)
            // The title cut at its end, the quotes and "Deleted" whole (brief 107: cut in the middle it read
            // "Read t…rticle Alex sent" on a phone).
            HStack(spacing: 0) {
                Text("Deleted ‘").fixedSize()
                Text(title).lineLimit(1).truncationMode(.tail)
                Text("’").fixedSize()
            }
            .accessibilityElement(children: .combine)
            Text("·").foregroundStyle(Theme.secondaryText)
            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
                .keyboardShortcut(undoShortcut ? KeyboardShortcut("z", modifiers: .command) : nil)
                .accessibilityIdentifier("reviewUndo")
                #if os(macOS)
                .help("Undo (⌘Z)")
                #endif
        }
        .font(HITType.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .frame(maxWidth: 480)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        // The text and a real Undo button, each reachable (a merged element took taps on its middle).
        .accessibilityElement(children: .contain)
    }
}
