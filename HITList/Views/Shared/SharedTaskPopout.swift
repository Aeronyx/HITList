import SwiftUI
import HITListCore

/// What the shared task's editor holds until Confirm (brief 64): the typing, as `TaskEditorDraft` holds it for a task
/// of yours. Everything picked rather than typed (the date, the priority, the set of people) lands at once.
struct SharedTaskDraft: Equatable {
    var title: String
    var notes: String

    init(task: SharedTask) {
        title = task.title.value
        notes = task.notes.value
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// One line, capped, as a task of yours; nil keeps the stored title (left blank, or unchanged).
    private func titleToSave(for task: SharedTask) -> String? {
        TaskEditorDraft.titleToSave(title, current: task.title.value)
    }

    private func notesToSave(for task: SharedTask) -> String? {
        let notes = Self.trimmed(notes)
        return notes == Self.trimmed(task.notes.value) ? nil : notes
    }

    /// Whether Confirm would save anything.
    func hasPendingChanges(for task: SharedTask) -> Bool {
        titleToSave(for: task) != nil || notesToSave(for: task) != nil
    }

    /// × (and Esc, a click on the panel's backdrop, a swipe down on the iPhone's sheet): with typing, Discard first; ×
    /// again while asking is the Discard. With none it closes. As yours (brief 41).
    func closeStep(for task: SharedTask, asking: Bool) -> TaskEditorDraft.CloseStep {
        !asking && hasPendingChanges(for: task) ? .askDiscard : .close
    }

    /// Confirm: what was typed, into the shared store (stamped, sent to the others). True if anything changed.
    @MainActor
    @discardableResult
    mutating func commit(to row: SharedRow, in rows: SharedRows) throws -> Bool {
        var changed = false
        if let title = titleToSave(for: row.task) {
            try rows.setTitle(title, row)
            changed = true
        }
        if let notes = notesToSave(for: row.task) {
            try rows.setNotes(notes, row)
            changed = true
        }
        if changed { title = TaskEditorDraft.titleToSave(title, current: "") ?? title }
        return changed
    }
}

/// A shared task, popped out (brief 64, George: "there's no point in shared tasks if they don't appear to users in
/// the app like regular tasks"): the editor of a task of yours, built from its own components (`EditorCard`,
/// `EditorRow`, the pill row, `ConfirmPill`, × and "…"), drawn where yours is (`PopoutHost`: the panel over a dimmed
/// window on the Mac and iPad, the sheet on the iPhone), with the same Discard rules. The Group row reads Shared Tasks
/// with its dot; the people row shows who it is shared with and moves it to another set of people. Only what the
/// shared model has: the title, the description, the priority and the date with its time.
struct SharedTaskPopout: View {
    let ref: SharedTaskRef

    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var draft: SharedTaskDraft?
    @State private var showsNotes = false
    @State private var openChip: Chip?
    @State private var confirmingDiscard = false
    @State private var discardOfferedAt = Date.distantPast
    @State private var isClosing = false
    @State private var completing = false
    @State private var pops = 0
    @State private var bodyHeight: CGFloat = 0
    @State private var confirmDelete = false
    /// "You can see “…” but not change it.", for a moment.
    @State private var refusal: String?
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    enum Chip: Hashable { case date, priority, people }

    private var rows: SharedRows { popouts.sharedRows }
    /// The task as it is now: another member's change shows at once; nil once it went (deleted or left elsewhere).
    private var row: SharedRow? { rows.row(ref.taskID) }

    private var isPanel: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        SwiftUI.Group {
            if let row {
                editor(row)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        // Deleted, or its set of people left, on another device while it was open: nothing to edit.
        .onChange(of: row == nil, initial: true) { _, gone in
            if gone { popouts.closeSharedTask() }
        }
    }

    private func editor(_ row: SharedRow) -> some View {
        let draft = Binding(get: { self.draft ?? SharedTaskDraft(task: row.task) }, set: { self.draft = $0 })
        let asks = !isClosing && draft.wrappedValue.hasPendingChanges(for: row.task)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar(row)
                ScrollView {
                    VStack(alignment: .leading, spacing: HITSpacing.l) {
                        titleCard(row, draft: draft)
                        pillRow(row)
                        if let refusal {
                            Text(refusal).font(HITType.footnote).foregroundStyle(HITColor.dueTomorrow).transition(.opacity)
                        }
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
            footer(row)
        }
        .background(Theme.background)
        .onAppear {
            if self.draft == nil {
                self.draft = SharedTaskDraft(task: row.task)
                showsNotes = !row.task.notes.value.isEmpty
            }
        }
        .onChange(of: self.draft) { _, new in
            if confirmingDiscard, let new, !new.hasPendingChanges(for: row.task) { confirmingDiscard = false }
        }
        #if os(iOS)
        .sheetSwipeGuard(isActive: !isPanel && asks) {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        }
        #endif
        .panelDismissGuard(isActive: isPanel && asks) {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        }
        .pickerOverlay()
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete(row) }
        } message: {
            Text("“\(row.filterTitle)” will be deleted for everyone it is shared with.")
        }
        #if os(macOS)
        .onExitCommand { requestClose(row) }
        #endif
        .accessibilityIdentifier("sharedEditor")
    }

    // MARK: Top bar

    private func topBar(_ row: SharedRow) -> some View {
        HStack(spacing: HITSpacing.s) {
            Button { requestClose(row) } label: { Image(systemName: "xmark").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 16, weight: .semibold)))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc); asks before dropping typing")
            Spacer()
            moreMenu(row)
        }
        .padding(.horizontal, HITSpacing.s)
        .padding(.top, isPanel ? HITSpacing.s : HITSpacing.l)
        .padding(.bottom, HITSpacing.xs)
    }

    private func moreMenu(_ row: SharedRow) -> some View {
        Menu {
            if row.canWrite {
                Button("A day earlier", systemImage: "arrow.left.circle") { shiftDay(row, by: -1) }
                    .disabled(row.task.isCompleted)
                Button("A day later", systemImage: "arrow.right.circle") { shiftDay(row, by: 1) }
                    .disabled(row.task.isCompleted)
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
            Section {
                ForEach(dateLines(row), id: \.self) { line in
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
        .help("Move a day or delete")
    }

    /// Who added it and when; who completed it.
    private func dateLines(_ row: SharedRow) -> [String] {
        let list = rows.list(row.listID)
        let me = rows.me
        var by = ""
        if let creator = row.task.createdBy, let list {
            by = " by " + SharedPeople.name(of: creator, in: list, me: me, fallback: row.task.createdByName)
        }
        var lines = ["Added\(by) \(row.task.createdAt.formatted(date: .abbreviated, time: .shortened))"]
        if let list, let done = SharedPeople.completedBy(row.task, in: list, me: me) { lines.append(done) }
        return lines
    }

    // MARK: Title card

    private func titleCard(_ row: SharedRow, draft: Binding<SharedTaskDraft>) -> some View {
        let priority = Priority(clamping: row.task.priority.value)
        let checked = row.task.isCompleted || completing
        let now = Date()
        return EditorCard {
            HStack(alignment: .top, spacing: EditorMetrics.gap) {
                Button { toggleCompletion(row) } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: EditorMetrics.checkSize, weight: .light))
                        .frame(width: EditorMetrics.iconColumn, height: EditorMetrics.titleLine)
                        .foregroundStyle(checked ? (priority == .p4 ? Theme.accent : priority.color)
                                         : priority == .p4 ? Theme.secondaryText : priority.color)
                        .contentTransition(checked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                        .hitCelebratePop(trigger: pops)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!row.canWrite)
                .accessibilityLabel(row.task.isCompleted ? "Mark incomplete" : "Complete task")
                .accessibilityIdentifier("popoutCheckbox")

                VStack(alignment: .leading, spacing: HITSpacing.xs) {
                    TextField("Task name", text: draft.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(HITType.title2Bold)
                        .foregroundStyle(checked ? Theme.secondaryText : HITColor.text)
                        .strikethrough(row.task.isCompleted, color: Theme.secondaryText)
                        .lineLimit(1...6)
                        .frame(minHeight: EditorMetrics.titleLine, alignment: .leading)
                        .focused($titleFocused)
                        .disabled(!row.canWrite)
                        #if os(macOS)
                        .onSubmit { confirm(row) }
                        #else
                        .submitLabel(.return)
                        #endif
                        .onChange(of: draft.wrappedValue.title) { old, title in
                            // Return never adds a line: the Mac confirms, the iPhone drops it (`TitleReturn`).
                            guard let outcome = TitleReturn.resolve(old: old, new: title) else { return }
                            draft.wrappedValue.title = outcome.text
                            if outcome.submits { confirm(row) }
                        }
                        .accessibilityIdentifier("editorTitle")
                    if showsNotes {
                        TextField("Description", text: draft.notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(HITType.callout)
                            .foregroundStyle(HITColor.text.opacity(0.85))
                            .lineLimit(1...12)
                            .focused($notesFocused)
                            .disabled(!row.canWrite)
                            .transition(.opacity)
                            .accessibilityIdentifier("editorDescription")
                    }
                }
            }
            .padding(.horizontal, EditorMetrics.inset)
            .padding(.top, EditorMetrics.inset)
            .padding(.bottom, HITSpacing.m)

            SharedEditorGroupRow()
            EditorHairline()
            peopleRow(row)
            EditorHairline()
            dateRow(row, now: now)
        }
    }

    /// Who it is shared with: their faces and first names. It opens the sets of people, to move it to another.
    private func peopleRow(_ row: SharedRow) -> some View {
        let people = row.people
        return Button { openChip = .people } label: {
            HStack(spacing: EditorMetrics.gap) {
                Image(systemName: "person.2")
                    .font(.system(size: EditorMetrics.iconSize, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: EditorMetrics.iconColumn)
                Text(people.isEmpty ? "Not shared yet" : SharedSets.names(people))
                    .font(HITType.body)
                    .foregroundStyle(people.isEmpty ? Theme.secondaryText : HITColor.text)
                    .lineLimit(1)
                Spacer(minLength: HITSpacing.s)
                SharedAvatarStack(people: people, size: EditorMetrics.iconSize + 8, ring: Theme.surface)
            }
            .padding(.horizontal, EditorMetrics.inset)
            .frame(minHeight: EditorMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(EditorRowStyle())
        .disabled(!row.canWrite)
        .pickerAnchor(.group, isPresented: chipBinding(.people)) {
            SharedSetPicker(current: row.listID) { listID in
                openChip = nil
                move(row, to: listID)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(people.isEmpty ? "Not shared yet" : SharedAvatarStack.accessibilityLabel(people))
        .accessibilityIdentifier("editorPeopleRow")
    }

    private func dateRow(_ row: SharedRow, now: Date) -> some View {
        let due = row.task.due.value
        return EditorRow(due.map { DueFormatter.text(for: $0.date, hasTime: $0.hasTime, now: now) } ?? "No date",
                         systemImage: "calendar",
                         tint: due == nil ? Theme.secondaryText : PopoutTint.date(due?.date, hasTime: due?.hasTime ?? false, now: now),
                         isPlaceholder: due == nil, action: { openChip = .date })
            .disabled(!row.canWrite)
            .pickerAnchor(.date, isPresented: chipBinding(.date)) {
                DatePickerCard(selected: due?.date, now: now, onPick: { day in
                    openChip = nil
                    perform { try rows.reschedule(row, to: day) }
                }, time: timeParts(due).map { PickerTime(hour: $0.hour, minute: $0.minute) }, onTime: { time in
                    if let time {
                        openChip = nil
                        perform { try rows.setTime(row, hour: time.hour, minute: time.minute) }
                    } else {
                        perform { try rows.clearTime(row) }
                    }
                })
            }
            .accessibilityIdentifier("popoutDateRow")
    }

    private func timeParts(_ due: SharedDue?) -> (hour: Int, minute: Int)? {
        guard let due, due.hasTime else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: due.date)
        return (parts.hour ?? 9, parts.minute ?? 0)
    }

    // MARK: Pills

    private func chipBinding(_ chip: Chip) -> Binding<Bool> {
        Binding(get: { openChip == chip }, set: { if !$0, openChip == chip { openChip = nil } })
    }

    /// Description and Priority: what a shared task has of the pills.
    private func pillRow(_ row: SharedRow) -> some View {
        let priority = Priority(clamping: row.task.priority.value)
        let hasNotes = !(draft?.notes ?? row.task.notes.value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: HITSpacing.s) {
            HITChip("Description", systemImage: "text.alignleft", tint: hasNotes ? Theme.accent : Theme.secondaryText,
                    isSelected: hasNotes, size: .compact) {
                withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { showsNotes = true }
                Task { @MainActor in notesFocused = true }
            }
            .accessibilityIdentifier("editorDescriptionPill")
            HITChip(priority == .p4 ? "Priority" : priority.shortName, systemImage: priority.symbol,
                    tint: priority == .p4 ? Theme.secondaryText : priority.color,
                    isSelected: priority != .p4, size: .compact, action: { openChip = .priority })
                .pickerAnchor(.priority, isPresented: chipBinding(.priority)) {
                    PriorityChipPopover(selection: priority) { p in
                        openChip = nil
                        perform { try rows.setPriority(p.rawValue, row) }
                    }
                }
            Spacer(minLength: 0)
        }
        .disabled(!row.canWrite)
        .frame(height: HITChip.Size.compact.height + 2)
        .accessibilityIdentifier("editorPills")
    }

    // MARK: Footer and Discard

    private func footer(_ row: SharedRow) -> some View {
        HStack(spacing: HITSpacing.m) {
            Spacer(minLength: HITSpacing.s)
            ConfirmPill { confirm(row) }
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Confirm")
                .accessibilityIdentifier("editorConfirm")
                .help("Save and close (⌘Return)")
        }
        .padding(.horizontal, HITSpacing.l)
        .padding(.vertical, HITSpacing.m)
    }

    private var discardLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Keep editing")
            DiscardBubble { close() }
                .padding(.bottom, HITSpacing.m)
        }
        .transition(.opacity)
    }

    // MARK: Actions

    private func confirm(_ row: SharedRow) {
        guard !isClosing else { return }
        isClosing = true
        commit(row)
        popouts.closeSharedTask()
    }

    private func commit(_ row: SharedRow) {
        guard row.canWrite, var draft else { return }
        perform { try draft.commit(to: row, in: rows) }
        self.draft = draft
    }

    private func requestClose(_ row: SharedRow) {
        let draft = self.draft ?? SharedTaskDraft(task: row.task)
        switch draft.closeStep(for: row.task, asking: confirmingDiscard) {
        case .askDiscard:
            discardOfferedAt = .now
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .close:
            if confirmingDiscard, Date.now.timeIntervalSince(discardOfferedAt) < 0.3 { return }
            close()
        }
    }

    /// Closes without saving typing (picked values have landed already).
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        confirmingDiscard = false
        popouts.closeSharedTask()
    }

    /// Reopening happens in place; completing fills the check, plays the usual feedback, then closes with the toast.
    private func toggleCompletion(_ row: SharedRow) {
        if row.task.isCompleted {
            perform { try rows.setCompleted(false, row) }
            return
        }
        guard !completing else { return }
        commit(row)
        isClosing = true
        if !reduceMotion { pops += 1 }
        withAnimation(.easeOut(duration: 0.15)) { completing = true }
        CompletionFeedback.shared.taskCompleted()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 380))
            guard let current = rows.row(row.id) else { popouts.closeSharedTask(); return }
            do { try popouts.completeShared(current) } catch { popouts.closeSharedTask() }
        }
    }

    private func shiftDay(_ row: SharedRow, by offset: Int) {
        let day = TaskRescheduling.day(offset, from: row.task.due.value?.date, now: Date())
        perform { try rows.reschedule(row, to: day) }
    }

    private func move(_ row: SharedRow, to listID: UUID) {
        commit(row)
        guard let current = rows.row(row.id) else { return }
        do {
            let moved = try rows.move(current, to: listID)
            // The task has a new id in its new set: the editor follows it.
            isClosing = true
            popouts.openShared(SharedTaskRef(moved))
        } catch {
            show(error)
        }
    }

    private func delete(_ row: SharedRow) {
        popouts.requestDelete(title: row.filterTitle) {
            isClosing = true
            popouts.closeSharedTask()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                try? rows.delete(row)
            }
        }
    }

    private func perform(_ change: () throws -> Void) {
        do { try change() } catch { show(error) }
    }

    private func show(_ error: Error) {
        let text = (error as? SharedRows.Refusal)?.localizedDescription ?? error.localizedDescription
        withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { refusal = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) { if refusal == text { refusal = nil } }
        }
    }
}

/// The editor's Group row for a shared task: Shared Tasks with its dot. It can't change: a shared task's Group is
/// always Shared Tasks (its people row moves it between sets of people).
struct SharedEditorGroupRow: View {
    var body: some View {
        EditorRow(SharedTasksGroup.name, systemImage: GroupDot.symbol, tint: Color(hex: SharedTasksGroup.colorHex), action: {})
            .allowsHitTesting(false)
            .accessibilityLabel("Group: \(SharedTasksGroup.name)")
            .accessibilityIdentifier("editorGroupRow")
    }
}

/// The people row's card: each set of people the task can be shared with, the current one checked.
struct SharedSetPicker: View {
    let current: UUID
    let onPick: (UUID) -> Void
    private var rows: SharedRows { .shared }

    var body: some View {
        let me = rows.me
        let lists = SharedSets.ordered(rows.lists, me: me).filter { SharedTasksPermissions.allows(.addTask, in: $0) }
        VStack(alignment: .leading, spacing: 0) {
            Text("Shared with")
                .font(HITType.sectionHeader)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, HITSpacing.l)
                .padding(.top, HITSpacing.m)
                .padding(.bottom, HITSpacing.xs)
            ForEach(lists) { list in
                let people = SharedPeople.others(in: list, me: me)
                Button { onPick(list.id) } label: {
                    HStack(spacing: HITSpacing.m) {
                        Text(people.isEmpty ? "Only you" : SharedSets.names(people))
                            .font(HITType.body)
                            .foregroundStyle(HITColor.text)
                            .lineLimit(1)
                        Spacer(minLength: HITSpacing.s)
                        SharedAvatarStack(people: people, size: 20, ring: Theme.surface)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .opacity(list.id == current ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HITRowButtonStyle())
            }
            Text("Add people in Sharing…, in Shared Tasks' view options.")
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HITSpacing.l)
                .padding(.vertical, HITSpacing.s)
        }
    }
}
