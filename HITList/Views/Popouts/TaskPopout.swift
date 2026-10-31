import SwiftUI
import SwiftData
import HITListCore

/// A task, popped out: a bottom sheet on iPhone, the top-centred panel on the Mac. Minimal until you
/// reach for more: checkbox and title (edit in place), a collapsed "Add description", and the chip row
/// (date, priority, project, labels, reminder, repeat); a repeating task also offers the Flipboard.
/// The `…` menu holds Duplicate, Move and Delete. Every change saves as it is made.
struct TaskPopout: View {
    @Bindable var task: TaskItem

    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var openChip: Chip?
    @State private var showsNotes = false
    @State private var confirmDelete = false
    /// The check fills for a moment before the popout closes with the toast.
    @State private var completing = false
    @State private var pops = 0
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    enum Chip: Hashable { case date, priority, project, labels, reminder, repeating }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            header
            description
            chipRow
            if task.recurrence != nil { flipboardRow }
            footer
        }
        .padding(HITSpacing.l)
        .onAppear { showsNotes = !task.notes.isEmpty }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("“\(task.title)” will be deleted on all your devices.")
        }
        #if os(macOS)
        .onExitCommand { popouts.closeTask() }
        #endif
    }

    // MARK: Header

    private var isChecked: Bool { task.isCompleted || completing }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: HITSpacing.m) {
            Button(action: toggleCompletion) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isChecked ? (task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color)
                                     : task.priorityValue == .p4 ? Theme.secondaryText : task.priorityValue.color)
                    .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                    .keyframeAnimator(initialValue: 1.0, trigger: pops) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.2, duration: 0.12, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.18, spring: .smooth)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")
            .accessibilityIdentifier("popoutCheckbox")

            TextField("Task name", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(HITType.title)
                .foregroundStyle(isChecked ? Theme.secondaryText : HITColor.text)
                .strikethrough(task.isCompleted, color: Theme.secondaryText)
                .lineLimit(1...5)
                .focused($titleFocused)
                .onChange(of: task.title) { _, title in
                    if title.contains(where: \.isNewline) {
                        // Return finishes editing instead of adding a line.
                        task.title = title.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
                        titleFocused = false
                    }
                    save(reschedule: false)
                }

            moreMenu
            Button { popouts.closeTask() } label: { Image(systemName: "xmark") }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 14, weight: .semibold)))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc)")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
            Menu("Move to…", systemImage: "arrow.right.square") {
                Button("Inbox", systemImage: "tray") { setProject(nil) }
                ForEach(projects) { project in
                    Button(project.name, systemImage: "number") { setProject(project) }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .help("Duplicate, move or delete")
    }

    // MARK: Description

    @ViewBuilder
    private var description: some View {
        if showsNotes {
            HITField("Description", text: $task.notes, axis: .vertical, lineLimit: 1...10)
                .focused($notesFocused)
                .onChange(of: task.notes) { _, _ in save(reschedule: false) }
                .transition(.opacity)
        } else {
            Button {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showsNotes = true }
                notesFocused = true
            } label: {
                Label("Add description", systemImage: "text.alignleft")
            }
            .buttonStyle(HITButtonStyle(.ghost, size: .small))
            .accessibilityIdentifier("addDescription")
        }
    }

    // MARK: Chips

    private func chipBinding(_ chip: Chip) -> Binding<Bool> {
        Binding(get: { openChip == chip }, set: { if !$0, openChip == chip { openChip = nil } })
    }

    private var timeParts: (hour: Int, minute: Int)? {
        guard task.hasDueTime, let due = task.dueDate else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
        return (parts.hour ?? 9, parts.minute ?? 0)
    }

    private var chipRow: some View {
        let now = Date()
        let due = task.dueDate
        return HITChipRow {
            HITChip(due.map { DueFormatter.text(for: $0, hasTime: false, now: now) } ?? "Date", systemImage: "calendar",
                    tint: due == nil ? Theme.secondaryText : PopoutTint.date(due, hasTime: task.hasDueTime, now: now),
                    isSelected: due != nil, action: { openChip = .date })
                .popover(isPresented: chipBinding(.date)) {
                    DateChipPopover(selected: due, now: now) { day in
                        openChip = nil
                        setDate(day)
                    }
                }
                .accessibilityIdentifier("popoutDateChip")

            HITChip(task.priorityValue == .p4 ? "Priority" : task.priorityValue.shortName, systemImage: task.priorityValue.symbol,
                    tint: task.priorityValue == .p4 ? Theme.secondaryText : task.priorityValue.color,
                    isSelected: task.priorityValue != .p4, action: { openChip = .priority })
                .popover(isPresented: chipBinding(.priority)) {
                    PriorityChipPopover(selection: task.priorityValue) { p in
                        openChip = nil
                        task.priorityValue = p
                        save()
                    }
                }

            HITChip(task.project?.name ?? "Inbox", systemImage: task.project == nil ? "tray" : "number",
                    tint: task.project.map { Color(hex: $0.colorHex) } ?? Theme.accent,
                    isSelected: task.project != nil, action: { openChip = .project })
                .popover(isPresented: chipBinding(.project)) {
                    ProjectChipPopover(projects: projects, selectedName: task.project?.name) { project in
                        openChip = nil
                        setProject(project)
                    }
                }

            HITChip(task.labelList.isEmpty ? "Labels" : task.labelList.map { "@" + $0.name }.joined(separator: " "),
                    systemImage: "tag", tint: task.labelList.isEmpty ? Theme.secondaryText : PopoutTint.label,
                    isSelected: !task.labelList.isEmpty, action: { openChip = .labels })
                .popover(isPresented: chipBinding(.labels)) {
                    LabelsChipPopover(labels: labels, selected: task.labelList.map(\.name), onToggle: toggleLabel)
                }

            HITChip(timeParts == nil ? "Reminder" : (due?.formatted(date: .omitted, time: .shortened) ?? "Reminder"),
                    systemImage: "alarm", tint: timeParts == nil ? Theme.secondaryText : Theme.accent,
                    isSelected: timeParts != nil, action: { openChip = .reminder })
                .popover(isPresented: chipBinding(.reminder)) {
                    ReminderChipPopover(hour: timeParts?.hour, minute: timeParts?.minute, onPick: { h, m in
                        openChip = nil
                        setTime(hour: h, minute: m)
                    }, onClear: {
                        openChip = nil
                        clearTime()
                    })
                }

            HITChip(task.recurrenceRule?.displayText ?? "Repeat", systemImage: "repeat",
                    tint: task.recurrence == nil ? Theme.secondaryText : PopoutTint.today,
                    isSelected: task.recurrence != nil, action: { openChip = .repeating })
                .popover(isPresented: chipBinding(.repeating)) {
                    RepeatChipPopover(rule: task.recurrenceRule) { rule in
                        openChip = nil
                        setRecurrence(rule)
                    }
                }
        }
    }

    // MARK: Flipboard

    private var flipboardRow: some View {
        let isMember = Flipboard.isMember(task)
        return HITGroup {
            HITMenuRow(isMember ? "Remove from Flipboard" : "Add to Flipboard",
                       subtitle: isMember ? "Shows as a switch that turns red when it’s due."
                                          : task.hasDueTime ? "A switch for this chore; drops its time of day." : "A switch for this chore that turns red when it’s due.",
                       systemImage: "switch.2", iconTint: isMember ? Theme.secondaryText : PopoutTint.today, accessory: .none) {
                if isMember {
                    Flipboard.remove(task, in: context)
                } else {
                    try? Flipboard.add(task, in: context)
                }
                rescheduleNotifications()
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: HITSpacing.s) {
            Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
            if let done = task.completedAt {
                Text("·")
                Text("Completed \(done.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(HITType.caption)
        .foregroundStyle(Theme.secondaryText.opacity(0.8))
    }

    // MARK: Changes

    private func save(reschedule: Bool = true) {
        task.touch()
        try? context.save()
        if reschedule { rescheduleNotifications() }
    }

    private func rescheduleNotifications() {
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    /// A new day keeps the time of day; nil removes the date (and with it the time).
    private func setDate(_ day: Date?) {
        TaskActions.reschedule(task, to: day, in: context)
        rescheduleNotifications()
    }

    private func setTime(hour: Int, minute: Int) {
        let calendar = Calendar.current
        let day = task.dueDate ?? calendar.startOfDay(for: Date())
        task.dueDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        task.hasDueTime = true
        save()
    }

    private func clearTime() {
        if let due = task.dueDate { task.dueDate = Calendar.current.startOfDay(for: due) }
        task.hasDueTime = false
        save()
    }

    private func setRecurrence(_ rule: RecurrenceRule?) {
        task.recurrenceRule = rule
        if rule != nil, task.dueDate == nil { task.dueDate = Calendar.current.startOfDay(for: Date()) }
        save()
    }

    private func setProject(_ project: Project?) {
        task.project = project
        save()
    }

    private func toggleLabel(_ name: String) {
        var current = task.labels ?? []
        if let i = current.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            current.remove(at: i)
        } else if let label = try? TaskActions.findOrCreateLabel(named: name, in: context) {
            current.append(label)
        }
        task.labels = current
        save()
    }

    private func duplicate() {
        let copy = TaskItem(title: task.title, notes: task.notes, priority: task.priority, dueDate: task.dueDate,
                            hasDueTime: task.hasDueTime, project: task.project, labels: task.labels ?? [],
                            recurrence: task.recurrenceRule)
        context.insert(copy)
        try? context.save()
        rescheduleNotifications()
        popouts.open(copy)
    }

    private func delete() {
        let doomed = task
        popouts.closeTask()
        // Delete once the popout has gone, so nothing draws a deleted task while it animates out.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            TaskActions.delete(doomed, in: context)
            rescheduleNotifications()
        }
    }

    /// Un-completing happens in place. Completing fills the check, plays the usual feedback, then
    /// closes the popout with the "Completed" toast (and its Undo).
    private func toggleCompletion() {
        if task.isCompleted {
            TaskActions.toggleCompletion(task, in: context)
            rescheduleNotifications()
            return
        }
        guard !completing else { return }
        if !reduceMotion { pops += 1 }
        withAnimation(.easeOut(duration: 0.15)) { completing = true }
        CompletionFeedback.shared.taskCompleted()
        let completed = task
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 380))
            popouts.complete(completed, in: context)
        }
    }
}
