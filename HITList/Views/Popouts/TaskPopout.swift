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
///   which open the Group and date cards. The title reads quick-add phrases typed in it (brief 65): they
///   light up as in the quick-add card, the rows and pills below show what they set (`EditorFields`), and
///   Confirm saves them (`TitlePhrases`). Picking a value replaces a typed phrase of its kind.
/// - A sideways row of pills: Description, Priority, Reminder, Labels, Repeat, Deadline, Location,
///   outlined until set, filled with their value once set.
/// - The Flipboard row for a repeating task, then the "Sub-tasks" checklist (`SubtaskChecklist`).
/// - A footer with **Confirm** (`ConfirmPill`, the quick-add card's pill; when it was created is in "…"): one tap saves
///   everything typed (title, description, the sub-task field, a rename) and closes. × and Esc close
///   without saving typing, asking Discard first when there is any (brief 41); what was picked (date,
///   Group, chips, ticks) has already landed. On the Mac Return in the title and ⌘Return confirm; on the
///   iPhone only the pill does (brief 36), and a swipe down with typing asks Discard first too.
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
    /// × (or, on the iPhone, a swipe down) met typing Confirm would save; "Discard" shows above the footer
    /// (briefs 36 and 41).
    @State private var confirmingDiscard = false
    /// When "Discard" was offered: one Esc can reach both the ×'s shortcut and the exit command, and must
    /// not ask and discard in the same press.
    @State private var discardOfferedAt = Date.distantPast
    /// The scrolling middle's height, so the panel is as tall as its content (up to a cap).
    @State private var bodyHeight: CGFloat = 0
    /// The task's id, read once while it certainly exists: the popout may close because the task was
    /// deleted elsewhere, and then nothing may be written to it.
    @State private var taskID: UUID?
    /// Not `@FocusState`: the title is a native text view whose own bridge moves its keyboard
    /// (`TokenHighlightField.focus`).
    @State private var titleFocused = false
    @FocusState private var notesFocused: Bool
    #if os(iOS)
    /// Where the keyboard was when a card opened, to give it back when the card closes.
    @State private var keyboardBeforeCard: KeyboardPlace?
    enum KeyboardPlace { case title, notes }
    #endif

    enum Chip: Hashable { case date, priority, project, labels, reminder, repeating, deadline, location }

    /// The iPhone Duo's fold (brief 50): the editor moves between the outer display's sheet and the inner
    /// display's column as a new view; this one writes its typing to `carryOver` as it changes, and starts from
    /// what an earlier one left there.
    private let carryOver: EditorCarryOver?

    init(task: TaskItem, carryOver: EditorCarryOver? = nil) {
        self.task = task
        self.carryOver = carryOver
        let start = EditorCarryOver.start(for: task, from: carryOver)
        _draft = State(initialValue: start.draft)
        _showsNotes = State(initialValue: start.showsNotes)
    }

    /// The panel (Mac, iPad) sizes to its content; the iPhone sheet fills its detent.
    private var isPanel: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    /// Reads the title's phrases the way the quick-add card does: the person's Groups and labels known.
    private func parser(now: Date = Date()) -> QuickAddParser {
        QuickAddParser(now: now, knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                       weekStart: Preferences.weekStartWeekday())
    }

    var body: some View {
        // The title is read once per keystroke: its highlights, and every row and pill below, come from it.
        let parser = parser()
        let parsed = draft.parsed(parser, for: task)
        let phrases = TitlePhrases(text: draft.title, result: parsed, dueDate: task.dueDate, hasDueTime: task.hasDueTime,
                                   calendar: parser.dateParser.calendar)
        let shown = EditorFields(task: task).applying(phrases)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: HITSpacing.l) {
                        titleCard(parsed: parsed, typedGroup: phrases.projectName, shown: shown)
                        pillRow(shown)
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
            }
            .overlay(alignment: .bottom) { if confirmingDiscard { discardLayer } }
            footer
        }
        .background(Theme.background)
        #if os(iOS)
        // A swipe down (or a tap above the sheet) with typing asks Discard; with none it just closes.
        .sheetSwipeGuard(isActive: !isPanel && !isClosing && draft.asksBeforeSwipeClose(for: task)) {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        }
        #endif
        .onChange(of: draft) { _, _ in
            if confirmingDiscard, !draft.hasPendingChanges(for: task) { confirmingDiscard = false }
            keepTyping()
        }
        .onChange(of: showsNotes) { _, _ in keepTyping() }
        #if os(iOS)
        // iPhone and iPad: the keyboard steps aside while a card is open, as in the quick-add card; with it up, the
        // date card was squeezed between its row and the keyboard, its presets and time cut off (brief 65).
        .onChange(of: openChip) { _, chip in keyboardMoves(forCard: chip != nil) }
        #endif
        // The chips' picker cards (inside the window on the Mac).
        .pickerOverlay()
        .onAppear {
            if taskID == nil { taskID = task.id }
        }
        // Mac and iPad: a click on the dimmed backdrop with typing asks Discard too (`PopoutHost`).
        .panelDismissGuard(isActive: isPanel && !isClosing && draft.asksBeforeSwipeClose(for: task)) {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("“\(task.title)” will be deleted on all your devices.")
        }
        #if os(macOS)
        .onExitCommand(perform: requestClose)
        #endif
    }

    #if os(iOS)
    /// A card opening takes the keyboard from the title or the description; closing gives it back there.
    private func keyboardMoves(forCard isOpen: Bool) {
        if isOpen {
            if keyboardBeforeCard == nil { keyboardBeforeCard = titleFocused ? .title : notesFocused ? .notes : nil }
            titleFocused = false
            notesFocused = false
        } else if let place = keyboardBeforeCard {
            keyboardBeforeCard = nil
            guard !isClosing else { return }
            switch place {
            case .title: titleFocused = true
            case .notes: notesFocused = true
            }
        }
    }
    #endif

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: HITSpacing.s) {
            Button(action: requestClose) { Image(systemName: "xmark").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 16, weight: .semibold)))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc); asks before dropping typing")
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
                    Button(project.name, systemImage: GroupDot.symbol) { setProject(project) }
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
            // When it was made (and done): the footer's old line, here since brief 36.
            Section {
                ForEach(Self.dateLines(for: task), id: \.self) { line in
                    Button(line) {}.disabled(true)
                }
            }
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

    /// The "…" menu's last lines: when the task was created, and completed if it is.
    static func dateLines(for task: TaskItem) -> [String] {
        var lines = ["Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))"]
        if let done = task.completedAt {
            lines.append("Completed \(done.formatted(date: .abbreviated, time: .shortened))")
        }
        return lines
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

    /// `parsed`: the title's phrases; `typedGroup`: a Group typed in it; `shown`: the fields as Confirm saves them.
    private func titleCard(parsed: QuickAddResult, typedGroup: String?, shown: EditorFields) -> some View {
        let now = Date()
        let priority = shown.priority
        let look = HighlightTextStyle.editorTitle(isChecked: isChecked, isCompleted: task.isCompleted)
        return EditorCard {
            HStack(alignment: .top, spacing: EditorMetrics.gap) {
                Button(action: toggleCompletion) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: EditorMetrics.checkSize, weight: .light))
                        .frame(width: EditorMetrics.iconColumn, height: EditorMetrics.titleLine)
                        .foregroundStyle(isChecked ? (priority == .p4 ? Theme.accent : priority.color)
                                         : priority == .p4 ? Theme.secondaryText : priority.color)
                        .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                        .hitCelebratePop(trigger: pops)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")
                .accessibilityIdentifier("popoutCheckbox")

                VStack(alignment: .leading, spacing: HITSpacing.xs) {
                    // The quick-add card's field (brief 65): phrases light up as typed; a click, a tap or Backspace
                    // right after one keeps it as text. Return never adds a line: the Mac confirms, the iPhone's
                    // plain "return" key does nothing (brief 36, `TitleReturn`).
                    TokenHighlightField(placeholder: "Task name", text: $draft.title, tokens: parsed.tokens,
                                        priority: parsed.priority, focus: $titleFocused, bordered: false,
                                        onDisable: { token in
                                            withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.disable(token) }
                                        },
                                        onEnable: { token in
                                            withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.switchBackOn(token) }
                                        },
                                        look: look, onSubmit: confirm)
                        // The first line centred on the check circle, as the old field's was.
                        .padding(.top, max(0, (EditorMetrics.titleLine - look.lineHeight) / 2))
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

            // While a Group is typed ("#Work"), the row shows it as it will be saved; otherwise the task's own.
            if let typedGroup { typedGroupRow(typedGroup) } else { groupRow }
            EditorHairline()
            dateRow(now: now, shown: shown)
        }
    }

    /// The Group row while a Group is typed in the title (brief 65): its name and colour (a new Group's in the
    /// default colour), opening the same Group card; a pick there replaces the typed Group.
    private func typedGroupRow(_ name: String) -> some View {
        let project = projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return EditorRow(project?.name ?? name, systemImage: GroupDot.symbol,
                         tint: project.map { Color(hex: $0.colorHex) } ?? PopoutTint.project,
                         action: { openChip = .project })
            .pickerAnchor(.group, isPresented: chipBinding(.project)) {
                ProjectChipPopover(projects: projects, selectedName: project?.name ?? name) { project in
                    openChip = nil
                    setProject(project)
                }
            }
            .accessibilityLabel("Group: \(project?.name ?? name)")
            .accessibilityIdentifier("editorGroupRow")
    }

    private var groupRow: some View {
        // A Group's dot, never "#" (brief 64).
        EditorRow(task.project?.name ?? "Inbox", systemImage: task.project == nil ? "tray" : GroupDot.symbol,
                  tint: task.project.map { Color(hex: $0.colorHex) } ?? Theme.accent,
                  action: { openChip = .project })
            .pickerAnchor(.group, isPresented: chipBinding(.project)) {
                ProjectChipPopover(projects: projects, selectedName: task.project?.name, onPickShared: {
                    // Into Shared Tasks (brief 64): the task moves to the shared store and its editor opens there.
                    openChip = nil
                    commitDraft()
                    guard let row = try? TaskActions.sharedCopy(of: task) else { return }
                    isClosing = true
                    let moved = task
                    popouts.openShared(SharedTaskRef(row))
                    // Yours goes once this editor has stopped drawing it, as Delete does.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        TaskActions.delete(moved, in: context)
                        rescheduleNotifications()
                    }
                }) { project in
                    openChip = nil
                    setProject(project)
                }
            }
            .accessibilityLabel("Group: \(task.project?.name ?? "Inbox")")
            .accessibilityIdentifier("editorGroupRow")
    }

    private func dateRow(now: Date, shown: EditorFields) -> some View {
        let due = shown.dueDate
        return EditorRow(due.map { DueFormatter.text(for: $0, hasTime: shown.hasDueTime, now: now) } ?? "No date",
                         systemImage: "calendar",
                         tint: due == nil ? Theme.secondaryText : PopoutTint.date(due, hasTime: shown.hasDueTime, now: now),
                         isPlaceholder: due == nil, action: { openChip = .date }) {
            if let rule = shown.recurrence {
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
            }, time: shown.timeParts.map { PickerTime(hour: $0.hour, minute: $0.minute) }, onTime: { time in
                if let time {
                    openChip = nil
                    setTime(hour: time.hour, minute: time.minute)
                } else {
                    clearTime()
                }
            }, recurrence: shown.recurrence, onRepeat: { rule in
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

    /// One sideways-scrolling row, edge to edge: outlined until set, filled with the value once set (typed in the
    /// title or stored: `shown`).
    private func pillRow(_ shown: EditorFields) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HITSpacing.s) {
                descriptionPill
                priorityPill(shown.priority)
                reminderPill(shown)
                labelsPill(shown.labelNames)
                repeatPill(shown.recurrence)
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

    private func priorityPill(_ priority: Priority) -> some View {
        HITChip(priority == .p4 ? "Priority" : priority.shortName, systemImage: priority.symbol,
                tint: priority == .p4 ? Theme.secondaryText : priority.color,
                isSelected: priority != .p4, size: .compact, action: { openChip = .priority })
            .pickerAnchor(.priority, isPresented: chipBinding(.priority)) {
                PriorityChipPopover(selection: priority) { p in
                    openChip = nil
                    removeTyped([.priority])
                    task.priorityValue = p
                    save()
                }
            }
            .accessibilityIdentifier("popoutPriorityChip")
    }

    /// The task's time and its reminders, its own reminder moment included while it is still to come
    /// ("Remind 3:47 PM", brief 48); the card sets, moves or removes it.
    private func reminderPill(_ shown: EditorFields) -> some View {
        let due = shown.dueDate
        let now = Date()
        let timeParts = shown.timeParts
        let moment = shown.reminderDate.flatMap { $0 > now ? $0 : nil }
        let set = timeParts != nil || moment != nil
        let title = ReminderChipText.title(time: timeParts == nil ? nil : due, offsetMinutes: shown.reminderOffsetMinutes,
                                           reminderDate: moment, now: now)
        return HITChip(title, systemImage: (shown.reminderOffsetMinutes ?? 0) > 0 || moment != nil ? "bell.badge" : "alarm",
                       tint: set ? Theme.accent : Theme.secondaryText,
                       isSelected: set, size: .compact, action: { openChip = .reminder })
            .pickerAnchor(.reminder, isPresented: chipBinding(.reminder)) {
                ReminderPickerCard(day: due, time: timeParts.map { PickerTime(hour: $0.hour, minute: $0.minute) },
                                   offsetMinutes: shown.reminderOffsetMinutes, now: now, onTime: { time in
                    if let time {
                        openChip = nil
                        setTime(hour: time.hour, minute: time.minute)
                    } else {
                        clearTime()
                    }
                }, onClear: {
                    openChip = nil
                    clearTime()
                    setReminderMoment(nil)
                }, onOffset: setReminderOffset, reminderDate: moment, onMoment: { pick in
                    if pick != nil { openChip = nil }
                    setReminderMoment(pick)
                })
            }
            .accessibilityLabel("Reminder: \(title)")
            .accessibilityIdentifier("popoutReminderChip")
    }

    /// The task's own reminder moment: that long from now, a picked time, or none.
    private func setReminderMoment(_ pick: ReminderMomentPick?) {
        removeTypedReminders(beforeDue: false)
        let date: Date? = switch pick {
        case .span(let span)?: span.date(from: Date())
        case .at(let at)?: at
        case nil: nil
        }
        TaskActions.setReminderDate(date, of: task, in: context)
        rescheduleNotifications()
    }

    private func labelsPill(_ names: [String]) -> some View {
        HITChip(names.isEmpty ? "Labels" : names.map { "@" + $0 }.joined(separator: " "),
                systemImage: "tag", tint: names.isEmpty ? Theme.secondaryText : PopoutTint.label,
                isSelected: !names.isEmpty, size: .compact, action: { openChip = .labels })
            .pickerAnchor(.labels, isPresented: chipBinding(.labels)) {
                LabelsChipPopover(labels: labels, selected: names, onToggle: toggleLabel)
            }
            .accessibilityIdentifier("popoutLabelsChip")
    }

    private func repeatPill(_ rule: RecurrenceRule?) -> some View {
        HITChip(rule?.displayText ?? "Repeat", systemImage: "repeat",
                tint: rule == nil ? Theme.secondaryText : PopoutTint.today,
                isSelected: rule != nil, size: .compact, action: { openChip = .repeating })
            .pickerAnchor(.repeating, isPresented: chipBinding(.repeating)) {
                RepeatChipPopover(rule: rule) { rule in
                    openChip = nil
                    setRecurrence(rule)
                }
            }
            .accessibilityIdentifier("popoutRepeatChip")
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
                                          : "A switch for this chore that turns red when it’s due.",
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

    /// Just Confirm, on the editor's ground: no divider and no "Created" line (brief 36; the dates are in
    /// the "…" menu).
    private var footer: some View {
        HStack(spacing: HITSpacing.m) {
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
    }

    // MARK: Discard (×, Esc, or on the iPhone a swipe down, with typing)

    /// Over the editor above the footer: a dimmed layer that means "keep editing" when tapped, and the
    /// quick-add card's Discard bubble pointing at the footer, whose Confirm still saves.
    private var discardLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture(perform: keepEditing)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Keep editing")
            DiscardBubble(action: discardTyping)
                .padding(.bottom, HITSpacing.m)
        }
        .transition(.opacity)
    }

    private func keepEditing() {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
    }

    /// Drops the typing and closes, as × does.
    private func discardTyping() {
        confirmingDiscard = false
        close()
    }

    // MARK: Confirm and close

    /// Saves everything typed and closes, in one tap.
    private func confirm() {
        guard !isClosing else { return }
        isClosing = true
        commitDraft()
        popouts.closeTask()
    }

    /// × and Esc: with typing, "Discard" first (brief 41); × again (or Discard) closes. Nothing typed: closes.
    private func requestClose() {
        switch draft.closeStep(for: task, asking: confirmingDiscard) {
        case .askDiscard:
            discardOfferedAt = .now
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .close:
            if confirmingDiscard, Date.now.timeIntervalSince(discardOfferedAt) < 0.3 { return }
            discardTyping()
        }
    }

    /// Hands the typing to the next editor of this task, should a fold replace this one (brief 50). Not while
    /// closing: Confirm and Discard are done with it.
    private func keepTyping() {
        guard let carryOver, taskID != nil, !isClosing else { return }
        carryOver.keep(draft, showsNotes: showsNotes, for: task)
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
        if (try? draft.commit(to: task, in: context, parser: parser())) == true { rescheduleNotifications() }
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

    // MARK: Picks replace typed phrases (brief 65)

    /// A value picked in the editor wins over a phrase of its kind typed in the title: the phrase leaves it.
    private func removeTyped(_ kinds: Set<QuickAddToken.Kind>, where include: (QuickAddToken) -> Bool = { _ in true }) {
        draft.removeTyped(kinds, parser(), for: task, where: include)
    }

    /// The title's reminder phrases of one sort: before the due time ("!15mb", "!at") or from now ("!15m").
    private func removeTypedReminders(beforeDue: Bool) {
        removeTyped([.reminder]) { ReminderPhrase(token: $0.text)?.isBeforeDue == beforeDue }
    }

    /// A new day keeps the time of day; nil removes the date (and with it the time).
    private func setDate(_ day: Date?) {
        if day == nil {
            removeTyped([.date, .time, .recurrence])
            removeTypedReminders(beforeDue: true)
        } else {
            removeTyped([.date])
        }
        TaskActions.reschedule(task, to: day, in: context)
        rescheduleNotifications()
    }

    private func setTime(hour: Int, minute: Int) {
        removeTyped([.time])
        let calendar = Calendar.current
        let day = task.dueDate ?? calendar.startOfDay(for: Date())
        task.dueDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        task.hasDueTime = true
        TaskActions.syncRepeatTime(of: task)
        save()
    }

    private func clearTime() {
        removeTyped([.time])
        removeTypedReminders(beforeDue: true)
        if let due = task.dueDate { task.dueDate = Calendar.current.startOfDay(for: due) }
        task.hasDueTime = false
        task.reminderOffsetMinutes = nil
        TaskActions.syncRepeatTime(of: task)
        save()
    }

    /// Nil or 0 reminds at the due time.
    private func setReminderOffset(_ minutes: Int?) {
        removeTypedReminders(beforeDue: true)
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
        removeTyped([.recurrence])
        TaskActions.setRecurrence(rule, on: task, in: context)
        rescheduleNotifications()
    }

    /// The checklist moves with the task (`TaskActions.setProject`).
    private func setProject(_ project: Project?) {
        removeTyped([.project])
        TaskActions.setProject(project, of: task, in: context)
        rescheduleNotifications()
    }

    /// The labels card: a label typed in the title or on the task is taken off (both), any other is added.
    private func toggleLabel(_ name: String) {
        let lowered = name.lowercased()
        let typed = draft.parsed(parser(), for: task, .final).tokens
            .contains { $0.kind == .label && QuickAddDraft.name(of: $0) == lowered }
        if typed { removeTyped([.label]) { QuickAddDraft.name(of: $0) == lowered } }
        var current = task.labels ?? []
        if let i = current.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            current.remove(at: i)
        } else if typed {
            return
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
