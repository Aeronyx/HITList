import SwiftUI
import SwiftData
import HITListCore

/// A task, popped out: a bottom sheet on iPhone, the top-centred panel on the Mac. Minimal until you
/// reach for more: checkbox and title (edit in place), a collapsed "Add description", and the chip row
/// (date, priority, group, labels, reminder with its offset, repeat, then deadline and location when
/// set); a repeating task also offers the Flipboard. The `…` menu holds Location, Deadline, Duplicate,
/// Move and Delete. Every change saves as it is made.
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
    /// Deadline / Location picked from the `…` menu: their chips show before they have a value.
    @State private var revealsDeadline = false
    @State private var revealsLocation = false
    /// The title when the popout opened, put back if it is left blank (`restoreTitleIfBlank`).
    @State private var openingTitle: String?
    /// The task's id, read once while it certainly exists: the popout may close because the task was
    /// deleted elsewhere, and then nothing may be written to it.
    @State private var taskID: UUID?
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    enum Chip: Hashable { case date, priority, project, labels, reminder, repeating, deadline, location }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            header
            description
            chipRow
            if task.recurrence != nil { flipboardRow }
            footer
        }
        .padding(HITSpacing.l)
        // The chips' picker cards (inside the window on the Mac).
        .pickerOverlay()
        .onAppear {
            showsNotes = !task.notes.isEmpty
            if openingTitle == nil { openingTitle = task.title }
            if taskID == nil { taskID = task.id }
        }
        .onDisappear(perform: restoreTitleIfBlank)
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

    /// One title line; the checkbox and the header buttons centre on it (a long title wraps below).
    private let headerLine: CGFloat = 26

    private var header: some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            Button(action: toggleCompletion) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .frame(width: 24, height: headerLine)
                    .foregroundStyle(isChecked ? (task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color)
                                     : task.priorityValue == .p4 ? Theme.secondaryText : task.priorityValue.color)
                    .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                    .hitCelebratePop(trigger: pops)
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
                .frame(minHeight: headerLine, alignment: .leading)
                .focused($titleFocused)
                .onChange(of: task.title) { _, title in
                    if title.contains(where: \.isNewline) {
                        // Return finishes editing instead of adding a line.
                        task.title = title.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
                        titleFocused = false
                    }
                    if task.title.count > TaskLimits.titleCharacters {
                        task.title = String(task.title.prefix(TaskLimits.titleCharacters))
                    }
                    save(reschedule: false)
                }

            moreMenu
                .frame(height: headerLine)
            Button { popouts.closeTask() } label: { Image(systemName: "xmark") }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 14, weight: .semibold)))
                .frame(height: headerLine)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc)")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Location", systemImage: "mappin.and.ellipse") { reveal(.location) }
            Button("Deadline", systemImage: "scope") { reveal(.deadline) }
            Divider()
            Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
            Menu("Move to…", systemImage: "arrow.right.square") {
                Button("Inbox", systemImage: "tray") { setProject(nil) }
                ForEach(projects) { project in
                    Button(project.name, systemImage: "number") { setProject(project) }
                }
            }
            Divider()
            Button(Self.menuTitle("A day earlier", key: "⌘←"), systemImage: "arrow.left.circle") {
                popouts.shiftDay(task, by: -1, in: context)
            }
            .disabled(task.isCompleted)
            Button(Self.menuTitle("A day later", key: "⌘→"), systemImage: "arrow.right.circle") {
                popouts.shiftDay(task, by: 1, in: context)
            }
            .disabled(task.isCompleted)
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
        .accessibilityIdentifier("popoutMore")
        .help("Location, deadline, duplicate, move or delete")
    }

    /// Shows the Deadline or Location chip and opens its popover once the menu has gone.
    private func reveal(_ chip: Chip) {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
            if chip == .deadline { revealsDeadline = true }
            if chip == .location { revealsLocation = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            openChip = chip
        }
    }

    /// Menu titles carry their Mac shortcut, since `PopoutHost` handles the keys rather than the menu.
    private static func menuTitle(_ title: String, key: String) -> String {
        #if os(macOS)
        return title + "   " + key
        #else
        return title
        #endif
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
                .pickerAnchor(.date, isPresented: chipBinding(.date)) {
                    DatePickerCard(selected: due, now: now, onPick: { day in
                        openChip = nil
                        setDate(day)
                    }, time: timeParts.map { PickerTime(hour: $0.hour, minute: $0.minute) }, onTime: { time in
                        if let time {
                            openChip = nil
                            setTime(hour: time.hour, minute: time.minute)
                        } else {
                            clearTime()
                        }
                    }, recurrence: task.recurrenceRule, onRepeat: { rule in
                        openChip = nil
                        setRecurrence(rule)
                    })
                }
                .accessibilityIdentifier("popoutDateChip")

            HITChip(task.priorityValue == .p4 ? "Priority" : task.priorityValue.shortName, systemImage: task.priorityValue.symbol,
                    tint: task.priorityValue == .p4 ? Theme.secondaryText : task.priorityValue.color,
                    isSelected: task.priorityValue != .p4, action: { openChip = .priority })
                .pickerAnchor(.priority, isPresented: chipBinding(.priority)) {
                    PriorityChipPopover(selection: task.priorityValue) { p in
                        openChip = nil
                        task.priorityValue = p
                        save()
                    }
                }

            HITChip(task.project?.name ?? "Inbox", systemImage: task.project == nil ? "tray" : "number",
                    tint: task.project.map { Color(hex: $0.colorHex) } ?? Theme.accent,
                    isSelected: task.project != nil, action: { openChip = .project })
                .pickerAnchor(.group, isPresented: chipBinding(.project)) {
                    ProjectChipPopover(projects: projects, selectedName: task.project?.name) { project in
                        openChip = nil
                        setProject(project)
                    }
                }

            HITChip(task.labelList.isEmpty ? "Labels" : task.labelList.map { "@" + $0.name }.joined(separator: " "),
                    systemImage: "tag", tint: task.labelList.isEmpty ? Theme.secondaryText : PopoutTint.label,
                    isSelected: !task.labelList.isEmpty, action: { openChip = .labels })
                .pickerAnchor(.labels, isPresented: chipBinding(.labels)) {
                    LabelsChipPopover(labels: labels, selected: task.labelList.map(\.name), onToggle: toggleLabel)
                }

            HITChip(ReminderChipText.title(time: timeParts == nil ? nil : due, offsetMinutes: task.reminderOffsetMinutes),
                    systemImage: (task.reminderOffsetMinutes ?? 0) > 0 ? "bell.badge" : "alarm",
                    tint: timeParts == nil ? Theme.secondaryText : Theme.accent,
                    isSelected: timeParts != nil, action: { openChip = .reminder })
                .pickerAnchor(.reminder, isPresented: chipBinding(.reminder)) {
                    ReminderPickerCard(day: due, time: timeParts.map { PickerTime(hour: $0.hour, minute: $0.minute) },
                                       offsetMinutes: task.reminderOffsetMinutes, now: now, onTime: { time in
                        if let time {
                            openChip = nil
                            setTime(hour: time.hour, minute: time.minute)
                        } else {
                            clearTime()
                        }
                    }, onClear: {
                        openChip = nil
                        clearTime()
                    }, onOffset: setReminderOffset)
                }
                .accessibilityIdentifier("popoutReminderChip")

            HITChip(task.recurrenceRule?.displayText ?? "Repeat", systemImage: "repeat",
                    tint: task.recurrence == nil ? Theme.secondaryText : PopoutTint.today,
                    isSelected: task.recurrence != nil, action: { openChip = .repeating })
                .pickerAnchor(.repeating, isPresented: chipBinding(.repeating)) {
                    RepeatChipPopover(rule: task.recurrenceRule) { rule in
                        openChip = nil
                        setRecurrence(rule)
                    }
                }

            if task.deadline != nil || revealsDeadline { deadlineChip(now: now) }
            if task.locationName != nil || revealsLocation { locationChip }
        }
    }

    private func deadlineChip(now: Date) -> some View {
        let deadline = task.deadline
        return HITChip(deadline.map { "Deadline · " + DueFormatter.text(for: $0, hasTime: false, now: now) } ?? "Deadline",
                       systemImage: "scope",
                       tint: deadline == nil ? Theme.secondaryText : PopoutTint.date(deadline, now: now),
                       isSelected: deadline != nil,
                       onDismiss: deadline == nil ? nil : { setDeadline(nil) },
                       action: { openChip = .deadline })
            .pickerAnchor(.deadline, isPresented: chipBinding(.deadline)) {
                DatePickerCard(selected: deadline, now: now, title: "Deadline", clearTitle: "No deadline") { day in
                    openChip = nil
                    setDeadline(day)
                }
            }
            .accessibilityIdentifier("popoutDeadlineChip")
    }

    private var locationChip: some View {
        let name = task.locationName
        return HITChip(name ?? "Location", systemImage: "mappin.and.ellipse",
                       tint: name == nil ? Theme.secondaryText : Theme.accent, isSelected: name != nil,
                       onDismiss: name == nil ? nil : { setLocation(nil) },
                       action: { openChip = .location })
            .pickerAnchor(.location, isPresented: chipBinding(.location)) {
                LocationChipPopover(name: name) { value in
                    openChip = nil
                    setLocation(value)
                }
            }
            .accessibilityIdentifier("popoutLocationChip")
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

    /// The title to put back when the popout closes: the one it opened with, if the edit left the title
    /// blank (a task needs a title; quick add refuses an empty one). Nil keeps the title as it is.
    static func titleToKeep(_ edited: String, opening: String?) -> String? {
        guard edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let opening, !opening.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return opening
    }

    /// On close: a title left blank gets its opening title back (`titleToKeep`).
    private func restoreTitleIfBlank() {
        // Closed because the task was deleted elsewhere: leave it alone (a write would bring it back).
        guard let taskID, PopoutController.taskExists(taskID, in: context) else { return }
        guard let kept = Self.titleToKeep(task.title, opening: openingTitle) else { return }
        task.title = kept
        save(reschedule: false)
    }

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
        task.reminderOffsetMinutes = nil
        save()
    }

    /// Nil or 0 reminds at the due time.
    private func setReminderOffset(_ minutes: Int?) {
        let value = (minutes ?? 0) > 0 ? minutes : nil
        guard task.reminderOffsetMinutes != value else { return }
        task.reminderOffsetMinutes = value
        save()
    }

    /// The deadline's day; nil removes it and its chip.
    private func setDeadline(_ day: Date?) {
        task.deadline = day.map { Calendar.current.startOfDay(for: $0) }
        if day == nil { revealsDeadline = false }
        save(reschedule: false)
    }

    /// Trimmed; nil or blank removes it and its chip.
    private func setLocation(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if value == nil { revealsLocation = false }
        guard task.locationName != value else { return }
        task.locationName = value
        save(reschedule: false)
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
        copy.reminderOffsetMinutes = task.reminderOffsetMinutes
        copy.deadline = task.deadline
        copy.locationName = task.locationName
        context.insert(copy)
        try? context.save()
        rescheduleNotifications()
        popouts.open(copy)
    }

    private func delete() {
        let doomed = task
        popouts.requestDelete(doomed) {
            popouts.closeTask()
            // Delete once the popout has gone, so nothing draws a deleted task while it animates out.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                TaskActions.delete(doomed, in: context)
                rescheduleNotifications()
            }
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
