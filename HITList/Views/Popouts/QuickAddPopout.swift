import SwiftUI
import SwiftData
import HITListCore

/// The quick-add card, the same everywhere: on iPhone a detached oval floating just above the keyboard
/// over a dimmed screen (`PopoutHost`), on the Mac the 560 pt panel near the top of the window, or
/// expanded in place of a list's "Add task" row.
///
/// "Task Name" in `HITType.taskName` (Inter bold, a step above `body`: 19 pt on iPhone), then one slim horizontally scrolling bar of
/// compact chips: "+" (Description, Labels, Location, Deadline, Repeat, Subtasks), Date, Priority, Reminder,
/// Group, then Labels, Deadline and Repeat once they are set or picked from "+". Type naturally
/// ("Haircut tom 11am p1 !15mb"); tokens light up and the chips follow. Picking a chip writes its token
/// into the text. Return adds the task and keeps the card open, empty, for the next one; Escape, ×, or
/// a tap on the dimmed backdrop closes it.
struct QuickAddPopout: View {
    /// `compact`: the Upcoming board's card inside a 270 pt day column (`CompactQuickAddCard`, brief 39):
    /// less padding, the chips wrapping instead of scrolling, and a × on the day chip.
    enum Style { case floating, inline, compact }

    /// The iPhone oval's corner radius.
    static let cardRadius: CGFloat = 28
    /// Inside the card: generous, on every side.
    static let padding: CGFloat = 20

    let context: QuickAddContext
    var style: Style = .floating
    /// iPhone: the host is putting the card away; drop the keyboard so it goes down with the card.
    var isClosing = false
    /// iPhone: the host closes the card after a save, so the card leaves its contents as they are while it
    /// fades (clearing them re-laid the card out mid-fade). The Mac panel stays open and resets for the next task.
    var closesAfterSave = false
    /// iPhone: the host is asking "Discard?" above the card; the keyboard steps down and comes back when
    /// the question is dismissed.
    var isPaused = false
    var onClose: () -> Void
    var onSaved: () -> Void = {}
    /// Whether the draft has a title, whenever that changes (the host decides how closing behaves).
    var onDraftChange: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Says which card this is (`PopoutState.QuickAdd.id`), for the "don't lose it" store.
    @Environment(PopoutController.self) private var popouts: PopoutController?
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var draft: QuickAddDraft
    @State private var openChip: Chip?
    @State private var errorMessage: String?
    @State private var added: String?
    @State private var addedGeneration = 0
    /// iPhone: the card has added its task and is on its way out; a second submit in that instant (Return
    /// delivered twice, a tap on the pill during the fade) must not add it again. The draft is left as it
    /// is while the card fades (`closesAfterSave`), so this flag is what makes the save idempotent.
    @State private var hasSavedForClose = false
    /// This card's id while it is on screen; its draft is stored under it (`QuickAddDraftStore`).
    @State private var cardID: UUID?
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool
    @FocusState private var locationFocused: Bool
    /// The sub-task line with the cursor (`SubtaskLineField` keeps its own focus; this asks for it).
    @State private var focusedLine: Int?

    enum Chip: Hashable { case date, priority, reminder, project, labels, deadline, repeating }

    init(context: QuickAddContext, style: Style = .floating, isClosing: Bool = false, closesAfterSave: Bool = false,
         isPaused: Bool = false, onClose: @escaping () -> Void, onSaved: @escaping () -> Void = {},
         onDraftChange: @escaping (Bool) -> Void = { _ in }) {
        self.isClosing = isClosing
        self.closesAfterSave = closesAfterSave
        self.isPaused = isPaused
        self.context = context
        self.style = style
        self.onClose = onClose
        self.onSaved = onSaved
        self.onDraftChange = onDraftChange
        // Empty: a fresh card never gets a stored draft. Only the card that was open when the app was
        // killed (same card id) reads its own back, on appear.
        _draft = State(initialValue: QuickAddDraft(context: context))
    }

    private var parser: QuickAddParser {
        QuickAddParser(knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                       weekStart: Preferences.weekStartWeekday())
    }

    var body: some View {
        // The text is read once per keystroke: the highlights, the chips and the add button all come from
        // this one parse (they used to make four, each repeated for every switched-off token).
        let parser = parser
        let parsed = draft.parsed(parser)
        let result = draft.result(parser, parsed: parsed)
        let chips = draft.chips(parser, parsed: parsed, result: result)
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            TokenHighlightField(placeholder: "Task Name", text: $draft.text, tokens: parsed.tokens,
                                priority: parsed.priority, focus: $titleFocused, bordered: false,
                                onDisable: { token in
                                    withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.disable(token) }
                                },
                                onEnable: { token in
                                    withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.switchBackOn(token) }
                                },
                                onSubmit: save)
                .accessibilityIdentifier("quickAddTitle")
                // First-run tips (brief 52): the syntax, then, once something lights up, how to undo a highlight.
                .quickAddTips(hasHighlight: parsed.tokens.contains { !$0.isSuperseded })
            if draft.shows(.description) {
                HITField("Description", text: $draft.notes, systemImage: "text.alignleft", axis: .vertical, lineLimit: 1...5)
                    .focused($notesFocused)
                    .transition(.opacity)
            }
            if draft.shows(.subtasks) {
                subtaskLines
                    .transition(.opacity)
            }
            if draft.shows(.location) {
                HITField("Location", text: $draft.locationName, systemImage: "mappin.and.ellipse", clearable: true)
                    .focused($locationFocused)
                    // Only the pill adds on the iPhone (brief 36): Return goes back to the title.
                    #if os(macOS)
                    .onSubmit(save)
                    #else
                    .onSubmit { titleFocused = true }
                    #endif
                    .transition(.opacity)
                    .accessibilityIdentifier("quickAddLocation")
            }
            optionBar(chips, parser: parser)
            if let errorMessage {
                Text(errorMessage).font(HITType.caption).foregroundStyle(HITColor.danger)
            }
            footer(canAdd: !result.title.isEmpty)
        }
        .padding(style == .compact ? CompactQuickAddCard.padding : Self.padding)
        // The chips' picker cards (inside the window on the Mac).
        .pickerOverlay()
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: draft.extras)
        .onAppear {
            // The card's own draft, if it had one when the app was last alive (or this view was rebuilt).
            cardID = popouts?.state.quickAdd?.id
            if let cardID, let popouts,
               let stored = QuickAddDraftStore.restoredDraft(for: cardID, from: popouts.draftDefaults, projects: projects) {
                draft = stored
            }
            titleFocused = true
            onDraftChange(draft.hasContent)
        }
        #if os(macOS)
        .task(claimTitleFocus)
        #endif
        .onChange(of: isClosing) { _, closing in
            if closing { titleFocused = false; notesFocused = false; locationFocused = false; endLineEditing() }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                titleFocused = false; notesFocused = false; locationFocused = false; endLineEditing()
            } else if !isClosing {
                titleFocused = true
            }
        }
        .onChange(of: draft.hasContent) { _, has in onDraftChange(has) }
        .onChange(of: draft) { _, _ in storeDraft() }
        .onChange(of: titleFocused) { _, focused in if focused { focusedLine = nil } }
        .onChange(of: openChip) { _, chip in
            // iPhone: the keyboard steps aside while a chip's popover needs the room, then comes back.
            #if os(iOS)
            if chip != nil {
                titleFocused = false; notesFocused = false; locationFocused = false; endLineEditing()
            } else {
                titleFocused = true
            }
            #endif
        }
        #if os(macOS)
        .onExitCommand(perform: onClose)
        #endif
    }

    #if os(macOS)
    /// The Mac: the title has the keyboard the moment the card shows, with no click in it (George, 0.5.0),
    /// whether the toolbar "+", ⌘N or a board day's "Add task" opened it. The focus asked for in `onAppear`
    /// is dropped when the card appears in the same pass as the view that holds it (a window opening with a
    /// card up, a board column coming back into view) and can be lost to the click that opened it, so the
    /// card asks again over the next half second until the title has it, unless something else in the card
    /// was picked meanwhile.
    ///
    /// The task holds only the focus and state bindings, never the card itself: a card holding its own
    /// queries past its model container (a render that never disappears, in tests) trapped in a later save.
    private var claimTitleFocus: @Sendable () async -> Void {
        let title = $titleFocused, notes = $notesFocused, location = $locationFocused
        let chip = $openChip, line = $focusedLine
        return { @MainActor in
            for delay in [0, 30, 80, 150, 250] {
                guard (try? await Task.sleep(for: .milliseconds(delay))) != nil else { return }
                guard chip.wrappedValue == nil, !notes.wrappedValue, !location.wrappedValue, line.wrappedValue == nil else { return }
                if !title.wrappedValue { title.wrappedValue = true }
            }
        }
    }
    #endif

    // MARK: The option bar

    private func chipBinding(_ chip: Chip) -> Binding<Bool> {
        Binding(get: { openChip == chip }, set: { if !$0, openChip == chip { openChip = nil } })
    }

    /// Closes the open popover and puts the cursor back in the title.
    private func done() {
        openChip = nil
        titleFocused = true
    }

    /// One slim row that scrolls sideways, edge to edge inside the card; in the board's compact card the
    /// chips wrap onto as many lines as the column needs instead.
    @ViewBuilder
    private func optionBar(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        if style == .compact {
            HITFlowLayout(spacing: 6) { optionChips(chips, parser: parser) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("quickAddOptionBar")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { optionChips(chips, parser: parser) }
                    .padding(.horizontal, Self.padding)
                    .padding(.vertical, 1)
            }
            .padding(.horizontal, -Self.padding)
            .frame(height: HITChip.Size.compact.height + 2)
            .accessibilityIdentifier("quickAddOptionBar")
        }
    }

    @ViewBuilder
    private func optionChips(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        plusMenu
        dateChip(chips, parser: parser)
        priorityChip(chips, parser: parser)
        reminderChip(chips, parser: parser)
        groupChip(chips, parser: parser)
        if !chips.labelNames.isEmpty || draft.shows(.labels) { labelsChip(chips, parser: parser) }
        if chips.deadline != nil || draft.shows(.deadline) { deadlineChip(chips) }
        if chips.recurrence != nil || draft.shows(.repeating) { repeatChip(chips, parser: parser) }
    }

    /// "+": the options that have no chip until you ask for them.
    private var plusMenu: some View {
        Menu {
            Button("Description", systemImage: "text.alignleft") { reveal(.description) }
            Button("Labels", systemImage: "tag") { reveal(.labels) }
            Button("Location", systemImage: "mappin.and.ellipse") { reveal(.location) }
            Button("Deadline", systemImage: "scope") { reveal(.deadline) }
            Button("Repeat", systemImage: "repeat") { reveal(.repeating) }
            Button("Subtasks", systemImage: "checklist") { reveal(.subtasks) }
        } label: {
            HITChipLabel("", systemImage: "plus", tint: Theme.accent, size: .compact)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More options")
        .accessibilityIdentifier("quickAddPlus")
        .help("Description, labels, location, deadline, repeat, subtasks")
    }

    /// Shows the picked option's control: a field gets the cursor, a chip opens its popover once the
    /// menu has gone (presenting while the menu is still dismissing would be dropped).
    private func reveal(_ extra: QuickAddDraft.Extra) {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { draft.reveal(extra) }
        let chip: Chip? = switch extra {
        case .labels: .labels
        case .deadline: .deadline
        case .repeating: .repeating
        case .description, .location, .subtasks: nil
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if let chip {
                openChip = chip
            } else if extra == .description {
                notesFocused = true
            } else if extra == .subtasks {
                // Let SwiftUI finish resigning the title's field first: asking for the line's cursor in
                // the same turn lost it to that resignation (seen in the iPhone 17 simulator, 0.4.1).
                titleFocused = false
                try? await Task.sleep(for: .milliseconds(80))
                focusedLine = draft.subtaskLines.indices.last
            } else {
                locationFocused = true
            }
        }
    }

    private func dateChip(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        let now = parser.dateParser.now
        return HITChip(chips.dueDate.map { DueFormatter.text(for: $0, hasTime: false, now: now) } ?? "Date",
                       systemImage: chips.recurrence == nil ? "calendar" : "repeat",
                       tint: chips.dueDate == nil ? Theme.secondaryText : PopoutTint.date(chips.dueDate, now: now),
                       isSelected: chips.dueDate != nil, size: .compact,
                       // The board's card shows its day with a × (no date: the task goes undated).
                       onDismiss: style == .compact && chips.dueDate != nil ? { draft.setDate(nil, parser) } : nil,
                       action: { openChip = .date })
            .pickerAnchor(.date, isPresented: chipBinding(.date)) {
                DatePickerCard(selected: chips.dueDate, now: now, onPick: { day in
                    draft.setDate(day, parser)
                    done()
                }, time: chips.hasDueTime ? chips.dueDate.map { PickerTime($0) } : nil, onTime: { time in
                    if let time {
                        draft.setTime(hour: time.hour, minute: time.minute, parser)
                        done()
                    } else {
                        draft.clearTime(parser)
                        draft.setReminderOffset(nil, parser)
                    }
                }, recurrence: chips.recurrence, onRepeat: { rule in
                    draft.setRecurrence(rule, parser)
                    done()
                })
            }
            .accessibilityIdentifier("quickAddDateChip")
    }

    private func priorityChip(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        HITChip(chips.priority == .p4 ? "Priority" : chips.priority.shortName, systemImage: chips.priority.symbol,
                tint: chips.priority == .p4 ? Theme.secondaryText : chips.priority.color,
                isSelected: chips.priority != .p4, size: .compact, action: { openChip = .priority })
            .pickerAnchor(.priority, isPresented: chipBinding(.priority)) {
                PriorityChipPopover(selection: chips.priority) { p in
                    draft.setPriority(p, parser)
                    done()
                }
            }
            .accessibilityIdentifier("quickAddPriorityChip")
    }

    /// The task's time and its reminders: "5:00 PM · 15 min before", "In 15 min · 3:47 PM" (brief 48: "!15m",
    /// a reminder of its own, dated or not).
    private func reminderChip(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        let set = chips.hasDueTime || chips.reminderDate != nil
        let title = ReminderChipText.title(time: chips.hasDueTime ? chips.dueDate : nil, offsetMinutes: chips.reminderOffsetMinutes,
                                           reminderDate: chips.reminderDate, fromNow: chips.reminderFromNow,
                                           now: parser.dateParser.now)
        return HITChip(title, systemImage: (chips.reminderOffsetMinutes ?? 0) > 0 || chips.reminderDate != nil ? "bell.badge" : "alarm",
                       tint: set ? Theme.accent : Theme.secondaryText,
                       isSelected: set, size: .compact, action: { openChip = .reminder })
            .pickerAnchor(.reminder, isPresented: chipBinding(.reminder)) {
                ReminderPickerCard(day: chips.dueDate, time: chips.hasDueTime ? chips.dueDate.map { PickerTime($0) } : nil,
                                   offsetMinutes: chips.reminderOffsetMinutes, now: parser.dateParser.now,
                                   onTime: { time in
                                       if let time {
                                           draft.setTime(hour: time.hour, minute: time.minute, parser)
                                           done()
                                       } else {
                                           draft.clearTime(parser)
                                           draft.setReminderOffset(nil, parser)
                                       }
                                   }, onClear: {
                                       draft.clearTime(parser)
                                       draft.setReminderOffset(nil, parser)
                                       draft.setReminderMoment(nil, parser)
                                       done()
                                   }, onOffset: { minutes in
                                       draft.setReminderOffset(minutes, parser)
                                   }, reminderDate: chips.reminderDate, fromNow: chips.reminderFromNow,
                                   onMoment: { pick in
                                       draft.setReminderMoment(pick, parser)
                                       if pick != nil { done() }
                                   })
            }
            .accessibilityLabel("Reminder: \(title)")
            .accessibilityIdentifier("quickAddReminderChip")
    }

    private func groupChip(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        HITChip(chips.projectName ?? "Inbox", systemImage: chips.projectName == nil ? "tray" : "number",
                tint: projectTint(chips.projectName), isSelected: chips.projectName != nil, size: .compact,
                action: { openChip = .project })
            .pickerAnchor(.group, isPresented: chipBinding(.project)) {
                ProjectChipPopover(projects: projects, selectedName: chips.projectName) { project in
                    draft.setProject(project?.name, parser)
                    done()
                }
            }
            .accessibilityLabel("Group: \(chips.projectName ?? "Inbox")")
            .accessibilityIdentifier("quickAddGroupChip")
    }

    private func labelsChip(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        HITChip(chips.labelNames.isEmpty ? "Labels" : chips.labelNames.map { "@" + $0 }.joined(separator: " "),
                systemImage: "tag", tint: chips.labelNames.isEmpty ? Theme.secondaryText : PopoutTint.label,
                isSelected: !chips.labelNames.isEmpty, size: .compact, action: { openChip = .labels })
            .pickerAnchor(.labels, isPresented: chipBinding(.labels)) {
                LabelsChipPopover(labels: labels, selected: chips.labelNames) { name in
                    draft.toggleLabel(name, parser)
                }
            }
    }

    private func deadlineChip(_ chips: QuickAddChips) -> some View {
        let now = Date()
        return HITChip(chips.deadline.map { "Deadline · " + DueFormatter.text(for: $0, hasTime: false, now: now) } ?? "Deadline",
                       systemImage: "scope",
                       tint: chips.deadline == nil ? Theme.secondaryText : PopoutTint.date(chips.deadline, now: now),
                       isSelected: chips.deadline != nil, size: .compact,
                       onDismiss: chips.deadline == nil ? nil : { draft.setDeadline(nil) },
                       action: { openChip = .deadline })
            .pickerAnchor(.deadline, isPresented: chipBinding(.deadline)) {
                DatePickerCard(selected: chips.deadline, now: now, title: "Deadline", clearTitle: "No deadline") { day in
                    draft.setDeadline(day)
                    done()
                }
            }
            .accessibilityIdentifier("quickAddDeadlineChip")
    }

    private func repeatChip(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        HITChip(chips.recurrence?.displayText ?? "Repeat", systemImage: "repeat",
                tint: chips.recurrence == nil ? Theme.secondaryText : PopoutTint.today,
                isSelected: chips.recurrence != nil, size: .compact,
                onDismiss: chips.recurrence == nil ? nil : { draft.setRecurrence(nil, parser) },
                action: { openChip = .repeating })
            .pickerAnchor(.repeating, isPresented: chipBinding(.repeating)) {
                RepeatChipPopover(rule: chips.recurrence) { rule in
                    draft.setRecurrence(rule, parser)
                    if rule == nil { draft.extras.remove(.repeating) }
                    done()
                }
            }
    }

    private func projectTint(_ name: String?) -> Color {
        guard let name else { return Theme.accent }
        return projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { Color(hex: $0.colorHex) } ?? PopoutTint.project
    }

    // MARK: Footer

    /// `canAdd`: the text makes a title (the body's one parse says so).
    private func footer(canAdd: Bool) -> some View {
        HStack(spacing: HITSpacing.s) {
            if let added {
                Label(added, systemImage: "checkmark.circle.fill")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            }
            Spacer(minLength: HITSpacing.s)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(HITButtonStyle(.ghost, size: .small, shape: .circle))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc)")
            // Hollow and faded while there is nothing to add; filled with the accent from the first
            // character (George, build 11). A pill, so it never reads as a second "+".
            // The same pill as the editor's Confirm (`ConfirmPill`, brief 36).
            ConfirmPill(kind: canAdd ? .primary : .secondary) { TapHaptic.play(); save() }
            .opacity(canAdd ? 1 : 0.55)
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: canAdd)
            .disabled(!canAdd)
            .accessibilityLabel("Add task")
            .accessibilityIdentifier("quickAddSave")
            .help("Add task (Return)")
        }
    }

    // MARK: Subtask lines (brief 32)

    /// "+" → Subtasks: a line per sub-task under the description. Return adds the next line (on an empty
    /// line it finishes the list and goes back to the title); Backspace on an empty line removes it.
    private var subtaskLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(draft.subtaskLines.indices, id: \.self) { index in
                HStack(spacing: HITSpacing.s) {
                    Image(systemName: "circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                        .frame(width: 18)
                    SubtaskLineField(placeholder: "Sub-task", text: lineBinding(index), isFocused: focusedLine == index,
                                     onFocus: { focusedLine = index },
                                     onReturn: { lineReturn(index) },
                                     onDeleteEmpty: { lineDelete(index) })
                        .accessibilityLabel("Sub-task \(index + 1)")
                }
            }
        }
        .accessibilityIdentifier("quickAddSubtasks")
    }

    private func lineBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft.subtaskLines.indices.contains(index) ? draft.subtaskLines[index] : "" },
                set: { if draft.subtaskLines.indices.contains(index) { draft.subtaskLines[index] = $0 } })
    }

    private func lineReturn(_ index: Int) {
        guard draft.subtaskLines.indices.contains(index) else { return }
        if draft.subtaskLines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { _ = draft.removeSubtaskLine(at: index) }
            backToTitle()
        } else {
            focusedLine = draft.insertSubtaskLine(after: index)
        }
    }

    private func lineDelete(_ index: Int) {
        let next = withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { draft.removeSubtaskLine(at: index) }
        if let next { focusedLine = next } else { backToTitle() }
    }

    private func backToTitle() {
        focusedLine = nil
        titleFocused = true
    }

    /// Takes the cursor out of a sub-task line (they are UIKit / AppKit fields, outside `FocusState`).
    private func endLineEditing() {
        guard focusedLine != nil else { return }
        focusedLine = nil
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #else
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    // MARK: Saving

    /// Keeps what is in the card, under its id, so a kill in the background loses nothing. Not once the
    /// iPhone card has added its task and is fading (the controller clears it as the card goes).
    private func storeDraft() {
        guard let cardID, let popouts, !hasSavedForClose else { return }
        QuickAddDraftStore.save(draft, card: cardID, to: popouts.draftDefaults)
    }

    private func save() {
        let result = draft.result(parser)
        guard !result.title.isEmpty, !hasSavedForClose else { return }
        do {
            let task = try TaskActions.create(from: result, defaultProject: nil, defaultLabel: nil, in: modelContext)
            let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                task.notes = notes
                try? modelContext.save()
            }
            try TaskActions.addSubtasks(draft.subtaskTitles, to: task, in: modelContext)
            errorMessage = nil
            if closesAfterSave { hasSavedForClose = true }
            if let cardID, let popouts { QuickAddDraftStore.clear(card: cardID, from: popouts.draftDefaults) }
            if !closesAfterSave {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
                    draft.reset()
                    added = "Added ‘\(result.title)’"
                }
                addedGeneration += 1
                let generation = addedGeneration
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if generation == addedGeneration { withAnimation { added = nil } }
                }
                focusedLine = nil
                titleFocused = true
            }
            onSaved()
            AccessibilityNotification.Announcement("Added \(result.title)").post()
            Task { await NotificationScheduler.reschedule(context: modelContext) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
