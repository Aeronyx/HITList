import SwiftUI
import SwiftData
import HITListCore

/// Process mode: the inbox one task at a time, oldest first. Each action (a date, a Group, a label,
/// delete, skip) moves on to the next task; the last one gives way to the empty state.
///
/// Keys on macOS (and iPad with a keyboard): T today, M tomorrow, D pick date, P Group, L label,
/// ⌫ delete (undo with ⌘Z), → skip, Return edit the title, Esc close. They are off while the title is
/// being edited or a picker is open, so typing never triggers them.
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
    /// A deleted task stays in the store until its undo toast expires, the next delete, or closing.
    @State private var pendingDelete: PendingDelete?
    @State private var deleteGeneration = 0

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum Popover { case date, project, label }

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

    private var shortcutsEnabled: Bool { !editingTitle && popover == nil && current != nil }

    private var parser: QuickAddParser {
        QuickAddParser(knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                       weekStart: Preferences.weekStartWeekday())
    }

    private var stepAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.3) }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if let task = current {
                    card(task)
                        .id(task.id)
                        .transition(cardTransition)
                } else if started {
                    finished
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            if let pendingDelete {
                DeletedToast(title: pendingDelete.title, undoShortcut: !editingTitle, onUndo: undoDelete)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 600, idealHeight: 660)
        #endif
        .slateSheet()
        .onAppear(perform: start)
        .onChange(of: unsortedIDs) { _, _ in withAnimation(stepAnimation) { queue.retainReview(of: allTasks) } }
        .onChange(of: queue.current) { _, _ in endEditing(save: false) }
        .onChange(of: titleFocused) { _, focused in
            // Clicking away from the title keeps the edit.
            if !focused, editingTitle, let task = current { applyTitleEdit(to: task) }
        }
        .onReceive(clock) { now = $0 }
        .onDisappear(perform: commitDelete)
    }

    // MARK: - Layout

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                if !queue.isFinished {
                    Text(queue.progressText)
                        .font(HITType.subheadlineSemibold.monospacedDigit())
                        .contentTransition(.numericText())
                        .accessibilityLabel("Task \(queue.position) of \(queue.total)")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(HITButtonStyle(.secondary, size: .small))
                    .keyboardShortcut(editingTitle ? nil : .cancelAction)
                    .help("Close (Esc)")
            }
            ProgressView(value: Double(queue.finished), total: Double(max(queue.total, 1)))
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .opacity(queue.isFinished ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func card(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    title(task)
                    meta(task)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(HITType.callout)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(12)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator))

                actions(task)
            }
            .padding(20)
            // Room for the undo toast.
            .padding(.bottom, 48)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func title(_ task: TaskItem) -> some View {
        if editingTitle {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Task name", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(HITType.title2)
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(HITType.title2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .font(HITType.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(shortcutsEnabled ? .defaultAction : nil)
            .help("Edit the title (Return)")
            .accessibilityHint("Edits the title")
        }
    }

    /// Due date, priority, labels and age, so the decision has its context.
    private func meta(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            if let due = task.dueDate {
                let overdue = DueFormatter.isOverdue(due, hasTime: task.hasDueTime, isCompleted: false, now: now)
                Label(DueFormatter.text(for: due, hasTime: task.hasDueTime, now: now),
                      systemImage: task.recurrence == nil ? "calendar" : "repeat")
                    .foregroundStyle(overdue ? .red : Theme.secondaryText)
            } else {
                Label("No date", systemImage: "calendar").foregroundStyle(Theme.secondaryText)
            }
            if task.priorityValue != .p4 {
                Label(task.priorityValue.shortName, systemImage: "flag.fill").foregroundStyle(task.priorityValue.color)
            }
            ForEach(task.labelList) { label in
                Text("@" + label.name).foregroundStyle(Color(hex: label.colorHex))
            }
            Spacer(minLength: 0)
            Text("Added \(task.createdAt.formatted(.relative(presentation: .named)))")
                .foregroundStyle(Theme.secondaryText.opacity(0.8))
        }
        .font(HITType.caption)
        .lineLimit(1)
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

    private func actions(_ task: TaskItem) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            action("Today", "star", key: "T", shortcut: KeyboardShortcut("t", modifiers: [])) {
                schedule(task, to: TaskRescheduling.QuickDate.today.date(now: now))
            }
            action("Tomorrow", "sunrise", key: "M", tint: .orange, shortcut: KeyboardShortcut("m", modifiers: [])) {
                schedule(task, to: TaskRescheduling.QuickDate.tomorrow.date(now: now))
            }
            action("Pick date…", "calendar", key: "D", shortcut: KeyboardShortcut("d", modifiers: [])) {
                open(.date)
            }
            .popover(isPresented: isOpen(.date)) {
                PickDatePopover(initial: task.dueDate ?? TaskRescheduling.QuickDate.tomorrow.date(now: now)) { day in
                    popover = nil
                    schedule(task, to: day)
                }
            }
            action("Move to Group", "number", key: "P", tint: .purple, shortcut: KeyboardShortcut("p", modifiers: [])) {
                open(.project)
            }
            .popover(isPresented: isOpen(.project)) {
                InboxPicker(title: "Move to Group", noun: "Group", symbol: "circle.fill",
                            options: projects.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex) }) { choice in
                    popover = nil
                    move(task, to: choice)
                }
            }
            action("Add label", "tag", key: "L", tint: .teal, shortcut: KeyboardShortcut("l", modifiers: [])) {
                open(.label)
            }
            .popover(isPresented: isOpen(.label)) {
                let applied = Set((task.labels ?? []).map(\.id))
                InboxPicker(title: "Add label", noun: "label", symbol: "tag.fill",
                            options: labels.filter { !applied.contains($0.id) }
                                .map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex) }) { choice in
                    popover = nil
                    addLabel(to: task, choice)
                }
            }
            action("Skip", "arrow.right", key: "→", tint: Theme.secondaryText,
                   shortcut: KeyboardShortcut(.rightArrow, modifiers: [])) {
                endEditing(save: true)
                withAnimation(stepAnimation) { queue.skip() }
            }
            action("Delete", "trash", key: "⌫", tint: .red, shortcut: KeyboardShortcut(.delete, modifiers: [])) {
                delete(task)
            }
        }
    }

    private func action(_ title: String, _ symbol: String, key: String, tint: Color = Theme.accent,
                        shortcut: KeyboardShortcut, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(HITType.subheadlineMedium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                #if os(macOS)
                Text(key)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                #endif
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ProcessButtonStyle())
        .keyboardShortcut(shortcutsEnabled ? shortcut : nil)
        .help("\(title) (\(key))")
    }

    private var finished: some View {
        let left = unsortedTasks.filter { $0.id != pendingDelete?.id }.count
        return VStack(spacing: 0) {
            if left == 0 {
                InboxZeroView()
            } else {
                InboxZeroView(title: "All done",
                              message: "You've been through the inbox. \(left) \(left == 1 ? "task stays" : "tasks stay") there with \(left == 1 ? "its" : "their") new dates and labels.")
            }
            Button("Done") { dismiss() }
                .buttonStyle(.hitPrimary)
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    private func start() {
        guard !started else { return }
        queue = InboxProcessQueue(reviewOf: allTasks)
        started = true
        CompletionFeedback.shared.prepare()
    }

    private func isOpen(_ which: Popover) -> Binding<Bool> {
        Binding(get: { popover == which }, set: { if !$0, popover == which { popover = nil } })
    }

    private func open(_ which: Popover) {
        endEditing(save: true)
        popover = which
    }

    private func advance() {
        withAnimation(stepAnimation) { queue.advance() }
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

    private func addLabel(to task: TaskItem, _ choice: InboxPicker.Choice) {
        let label: TaskLabel? = switch choice {
        case .existing(let id): labels.first { $0.id == id }
        case .new(let name): try? TaskActions.findOrCreateLabel(named: name, in: context)
        }
        guard let label else { return }
        if !(task.labels ?? []).contains(where: { $0.id == label.id }) {
            task.labels = (task.labels ?? []) + [label]
        }
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
        withAnimation(.snappy) { pendingDelete = pending }
        advance()
        AccessibilityNotification.Announcement("Deleted \(task.title)").post()
        Task {
            try? await Task.sleep(for: CompletionToastState.lifetime)
            guard pendingDelete?.generation == pending.generation else { return }
            withAnimation(.easeOut(duration: 0.25)) { commitDelete() }
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
    /// task or moved it out of the inbox, which counts as handling it.
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

/// The Inbox menu's "Review 3 unsorted…", hidden when nothing needs review (`InboxReview`).
struct InboxReviewMenuItem: View {
    let tasks: [TaskItem]
    let open: () -> Void

    var body: some View {
        if let title = InboxText.reviewMenuItem(count: InboxReview.count(tasks)) {
            Button(action: open) { Label(title, systemImage: "tray.and.arrow.down") }
        }
    }
}

/// Big slate tiles for Process mode's actions.
private struct ProcessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.separator : Theme.elevated,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.separator))
    }
}

/// "Deleted ‘Title’ · Undo", styled like the completion toast.
private struct DeletedToast: View {
    let title: String
    var undoShortcut: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash").foregroundStyle(.red)
            Text("Deleted ‘\(title)’")
                .lineLimit(1)
                .truncationMode(.middle)
            Text("·").foregroundStyle(Theme.secondaryText)
            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
                .keyboardShortcut(undoShortcut ? KeyboardShortcut("z", modifiers: .command) : nil)
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
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", onUndo)
    }
}
