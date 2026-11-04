import SwiftUI
import SwiftData
import HITListCore

/// A task, popped out: a bottom sheet on iPhone, the top-centred panel on the Mac (and iPad). Laid out
/// like Todoist's task view in HITList's slate (brief 32, George: "please make a better task editing
/// system"), on the darker ground with `Theme.surface` cards:
///
/// - × (close) and "…" (duplicate, move, a day earlier / later, delete) at the top.
/// - The title card: the check circle and the title, the description under it once it has one (or the
///   Description pill is tapped), then the Group row and the date row (with the time and the repeat),
///   which open the Group and date cards.
/// - A sideways row of pills: Description, Priority, Reminder, Labels, Repeat, Deadline, Location,
///   outlined until set, filled with their value once set.
/// - The Flipboard row for a repeating task, then the "Sub-tasks" checklist (`SubtaskChecklist`).
/// - A footer with when it was created and **Confirm**, the quick-add card's filled pill: one tap saves
///   everything typed (title, description, the sub-task field, a rename) and closes. × and Esc close
///   without saving typing; what was picked (date, Group, chips, ticks) has already landed. Return in the
///   title confirms; ⌘Return confirms on the Mac.
struct TaskPopout: View {
    @Bindable var task: TaskItem

    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var draft: TaskEditorDraft
    @State private var openChip: Chip?
    @State private var showsNotes: Bool
    @State private var confirmDelete = false
    /// The check fills for a moment before the popout closes with the toast.
    @State private var completing = false
    @State private var pops = 0
    /// Confirm (or Return) ran: a second one in the same instant does nothing.
    @State private var isClosing = false
    /// The scrolling middle's height, so the panel is as tall as its content (up to a cap).
    @State private var bodyHeight: CGFloat = 0
    /// The task's id, read once while it certainly exists: the popout may close because the task was
    /// deleted elsewhere, and then nothing may be written to it.
    @State private var taskID: UUID?
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    enum Chip: Hashable { case date, priority, project, labels, reminder, repeating, deadline, location }

    init(task: TaskItem) {
        self.task = task
        _draft = State(initialValue: TaskEditorDraft(task: task))
        _showsNotes = State(initialValue: !task.notes.isEmpty)
    }

    /// The panel (Mac, iPad) sizes to its content; the iPhone sheet fills its detent.
    private var isPanel: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: HITSpacing.l) {
                    titleCard
                    pillRow
                    if task.recurrence != nil, !task.isSubtask { flipboardRow }
                    if !task.isSubtask { SubtaskChecklist(task: task, draft: $draft) }
                }
                .padding(.horizontal, HITSpacing.l)
                .padding(.top, HITSpacing.xs)
                .padding(.bottom, HITSpacing.l)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .frame(idealHeight: bodyHeight)
            .frame(maxHeight: isPanel ? EditorMetrics.panelBodyMaxHeight : .infinity)
            footer
        }
        .background(Theme.background)
        // The chips' picker cards (inside the window on the Mac).
        .pickerOverlay()
        .onAppear {
            if taskID == nil { taskID = task.id }
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("“\(task.title)” will be deleted on all your devices.")
        }
        #if os(macOS)
        .onExitCommand(perform: close)
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: HITSpacing.s) {
            Button(action: close) { Image(systemName: "xmark").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 16, weight: .semibold)))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close without saving typing (Esc)")
            Spacer()
            moreMenu
        }
        .padding(.horizontal, HITSpacing.s)
        .padding(.top, isPanel ? HITSpacing.s : HITSpacing.l)
        .padding(.bottom, HITSpacing.xs)
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .accessibilityIdentifier("popoutMore")
        .help("Duplicate, move or delete")
    }

    /// Menu titles carry their Mac shortcut, since `PopoutHost` handles the keys rather than the menu.
    private static func menuTitle(_ title: String, key: String) -> String {
        #if os(macOS)
        return title + "   " + key
        #else
        return title
        #endif
    }

    // MARK: Title card

    private var isChecked: Bool { task.isCompleted || completing }

    private var titleCard: some View {
        let now = Date()
        return EditorCard {
            HStack(alignment: .top, spacing: EditorMetrics.gap) {
                Button(action: toggleCompletion) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: EditorMetrics.checkSize, weight: .light))
                        .frame(width: EditorMetrics.iconColumn, height: EditorMetrics.titleLine)
                        .foregroundStyle(isChecked ? (task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color)
                                         : task.priorityValue == .p4 ? Theme.secondaryText : task.priorityValue.color)
                        .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                        .hitCelebratePop(trigger: pops)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")
                .accessibilityIdentifier("popoutCheckbox")

                VStack(alignment: .leading, spacing: HITSpacing.xs) {
                    TextField("Task name", text: $draft.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(HITType.title2Bold)
                        .foregroundStyle(isChecked ? Theme.secondaryText : HITColor.text)
                        .strikethrough(task.isCompleted, color: Theme.secondaryText)
                        .lineLimit(1...6)
                        .frame(minHeight: EditorMetrics.titleLine, alignment: .leading)
                        .focused($titleFocused)
                        .onSubmit(confirm)
                        .onChange(of: draft.title) { _, title in
                            // Return confirms (George: one tap, or one key) instead of adding a line.
                            if title.contains(where: \.isNewline) {
                                draft.title = TaskLimits.singleLine(title)
                                confirm()
                            }
                        }
                        .accessibilityIdentifier("editorTitle")
                    if showsNotes {
                        TextField("Description", text: $draft.notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(HITType.callout)
                            .foregroundStyle(HITColor.text.opacity(0.85))
                            .lineLimit(1...12)
                            .focused($notesFocused)
                            .transition(.opacity)
                            .accessibilityIdentifier("editorDescription")
                    }
                }
            }
            .padding(.horizontal, EditorMetrics.inset)
            .padding(.top, EditorMetrics.inset)
            .padding(.bottom, HITSpacing.m)

            groupRow
            EditorHairline()
            dateRow(now: now)
        }
    }

    private var groupRow: some View {
        EditorRow(task.project?.name ?? "Inbox", systemImage: task.project == nil ? "tray" : "number",
                  tint: task.project.map { Color(hex: $0.colorHex) } ?? Theme.accent,
                  action: { openChip = .project })
            .pickerAnchor(.group, isPresented: chipBinding(.project)) {
                ProjectChipPopover(projects: projects, selectedName: task.project?.name) { project in
                    openChip = nil
                    setProject(project)
                }
            }
            .accessibilityLabel("Group: \(task.project?.name ?? "Inbox")")
            .accessibilityIdentifier("editorGroupRow")
    }

    private func dateRow(now: Date) -> some View {
        let due = task.dueDate
        return EditorRow(due.map { DueFormatter.text(for: $0, hasTime: task.hasDueTime, now: now) } ?? "No date",
                         systemImage: "calendar",
                         tint: due == nil ? Theme.secondaryText : PopoutTint.date(due, hasTime: task.hasDueTime, now: now),
                         isPlaceholder: due == nil, action: { openChip = .date }) {
            if let rule = task.recurrenceRule {
                HStack(spacing: 4) {
                    Image(systemName: "repeat").font(.system(size: 11, weight: .semibold))
                    Text(rule.displayText).font(HITType.caption).lineLimit(1)
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
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
        .accessibilityIdentifier("popoutDateRow")
    }

    // MARK: Pills

    private func chipBinding(_ chip: Chip) -> Binding<Bool> {
        Binding(get: { openChip == chip }, set: { if !$0, openChip == chip { openChip = nil } })
    }

    private var timeParts: (hour: Int, minute: Int)? {
        guard task.hasDueTime, let due = task.dueDate else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
        return (parts.hour ?? 9, parts.minute ?? 0)
    }

    /// One sideways-scrolling row, edge to edge: outlined until set, filled with the value once set.
    private var pillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HITSpacing.s) {
                descriptionPill
                priorityPill
                reminderPill
                labelsPill
                repeatPill
                deadlinePill
                locationPill
            }
            .padding(.horizontal, HITSpacing.l)
            .padding(.vertical, 1)
        }
        .padding(.horizontal, -HITSpacing.l)
        .frame(height: HITChip.Size.compact.height + 2)
        .accessibilityIdentifier("editorPills")
    }

    private var descriptionPill: some View {
        let hasNotes = !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HITChip("Description", systemImage: "text.alignleft", tint: hasNotes ? Theme.accent : Theme.secondaryText,
                       isSelected: hasNotes,
                       size: .compact) {
            withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { showsNotes = true }
            Task { @MainActor in notesFocused = true }
        }
        .accessibilityIdentifier("editorDescriptionPill")
    }

    private var priorityPill: some View {
        HITChip(task.priorityValue == .p4 ? "Priority" : task.priorityValue.shortName, systemImage: task.priorityValue.symbol,
                tint: task.priorityValue == .p4 ? Theme.secondaryText : task.priorityValue.color,
                isSelected: task.priorityValue != .p4, size: .compact, action: { openChip = .priority })
            .pickerAnchor(.priority, isPresented: chipBinding(.priority)) {
                PriorityChipPopover(selection: task.priorityValue) { p in
                    openChip = nil
                    task.priorityValue = p
                    save()
                }
            }
    }

    private var reminderPill: some View {
        let due = task.dueDate
        return HITChip(ReminderChipText.title(time: timeParts == nil ? nil : due, offsetMinutes: task.reminderOffsetMinutes),
                       systemImage: (task.reminderOffsetMinutes ?? 0) > 0 ? "bell.badge" : "alarm",
                       tint: timeParts == nil ? Theme.secondaryText : Theme.accent,
                       isSelected: timeParts != nil, size: .compact, action: { openChip = .reminder })
            .pickerAnchor(.reminder, isPresented: chipBinding(.reminder)) {
                ReminderPickerCard(day: due, time: timeParts.map { PickerTime(hour: $0.hour, minute: $0.minute) },
                                   offsetMinutes: task.reminderOffsetMinutes, now: Date(), onTime: { time in
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
    }

    private var labelsPill: some View {
        HITChip(task.labelList.isEmpty ? "Labels" : task.labelList.map { "@" + $0.name }.joined(separator: " "),
                systemImage: "tag", tint: task.labelList.isEmpty ? Theme.secondaryText : PopoutTint.label,
                isSelected: !task.labelList.isEmpty, size: .compact, action: { openChip = .labels })
            .pickerAnchor(.labels, isPresented: chipBinding(.labels)) {
                LabelsChipPopover(labels: labels, selected: task.labelList.map(\.name), onToggle: toggleLabel)
            }
    }

    private var repeatPill: some View {
        HITChip(task.recurrenceRule?.displayText ?? "Repeat", systemImage: "repeat",
                tint: task.recurrence == nil ? Theme.secondaryText : PopoutTint.today,
                isSelected: task.recurrence != nil, size: .compact, action: { openChip = .repeating })
            .pickerAnchor(.repeating, isPresented: chipBinding(.repeating)) {
                RepeatChipPopover(rule: task.recurrenceRule) { rule in
                    openChip = nil
                    setRecurrence(rule)
                }
            }
    }

    private var deadlinePill: some View {
        let deadline = task.deadline
        let now = Date()
        return HITChip(deadline.map { "Deadline · " + DueFormatter.text(for: $0, hasTime: false, now: now) } ?? "Deadline",
                       systemImage: "scope",
                       tint: deadline == nil ? Theme.secondaryText : PopoutTint.date(deadline, now: now),
                       isSelected: deadline != nil, size: .compact,
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

    private var locationPill: some View {
        let name = task.locationName
        return HITChip(name ?? "Location", systemImage: "mappin.and.ellipse",
                       tint: name == nil ? Theme.secondaryText : Theme.accent, isSelected: name != nil, size: .compact,
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
        HStack(spacing: HITSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
                if let done = task.completedAt {
                    Text("Completed \(done.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(HITType.caption)
            .foregroundStyle(Theme.secondaryText.opacity(0.8))
            .lineLimit(1)
            Spacer(minLength: HITSpacing.s)
            // The quick-add card's send pill (George: "ideally the same as the Confirm add task button").
            ConfirmPill(action: confirm)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Confirm")
            .accessibilityIdentifier("editorConfirm")
            .help("Save and close (⌘Return)")
        }
        .padding(.horizontal, HITSpacing.l)
        .padding(.vertical, HITSpacing.m)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator.opacity(0.6)).frame(height: 1) }
    }

    // MARK: Confirm and close

    /// Saves everything typed and closes, in one tap.
    private func confirm() {
        guard !isClosing else { return }
        isClosing = true
        commitDraft()
        popouts.closeTask()
    }

    /// Closes without saving typing (picked values have landed already).
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        draft.renaming = nil
        popouts.closeTask()
    }

    private func commitDraft() {
        // Closed because the task was deleted elsewhere: leave it alone (a write would bring it back).
        guard let taskID, PopoutController.taskExists(taskID, in: context) else { return }
        if (try? draft.commit(to: task, in: context)) == true { rescheduleNotifications() }
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
        TaskActions.syncRepeatTime(of: task)
        save()
    }

    private func clearTime() {
        if let due = task.dueDate { task.dueDate = Calendar.current.startOfDay(for: due) }
        task.hasDueTime = false
        task.reminderOffsetMinutes = nil
        TaskActions.syncRepeatTime(of: task)
        save()
    }

    /// Nil or 0 reminds at the due time.
    private func setReminderOffset(_ minutes: Int?) {
        let value = (minutes ?? 0) > 0 ? minutes : nil
        guard task.reminderOffsetMinutes != value else { return }
        task.reminderOffsetMinutes = value
        save()
    }

    /// The deadline's day; nil removes it.
    private func setDeadline(_ day: Date?) {
        task.deadline = day.map { Calendar.current.startOfDay(for: $0) }
        save(reschedule: false)
    }

    /// Trimmed; nil or blank removes it.
    private func setLocation(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard task.locationName != value else { return }
        task.locationName = value
        save(reschedule: false)
    }

    private func setRecurrence(_ rule: RecurrenceRule?) {
        TaskActions.setRecurrence(rule, on: task, in: context)
        rescheduleNotifications()
    }

    /// The checklist moves with the task (`TaskActions.setProject`).
    private func setProject(_ project: Project?) {
        TaskActions.setProject(project, of: task, in: context)
        rescheduleNotifications()
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

    /// A copy with what was typed so far, its checklist open again, opened in place of this one.
    private func duplicate() {
        commitDraft()
        let copy = TaskItem(title: task.title, notes: task.notes, priority: task.priority, dueDate: task.dueDate,
                            hasDueTime: task.hasDueTime, project: task.project, labels: task.labels ?? [],
                            recurrence: task.recurrenceRule)
        copy.reminderOffsetMinutes = task.reminderOffsetMinutes
        copy.deadline = task.deadline
        copy.locationName = task.locationName
        context.insert(copy)
        for (i, subtask) in task.orderedSubtasks.enumerated() {
            let item = TaskItem(title: subtask.title, project: task.project)
            item.sortOrder = i
            context.insert(item)
            item.parent = copy
        }
        try? context.save()
        rescheduleNotifications()
        isClosing = true
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
        // Typing lands with it: completing is as deliberate as Confirm.
        commitDraft()
        isClosing = true
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
