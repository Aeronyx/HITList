import SwiftUI
import SwiftData
import HITListCore

/// Adding or editing a Switchboard (brief 72): a small card like the switch card, never a sheet. The name, Daily or
/// Weekly (`HITSegmented`), when it resets (the editor's time row; 04:00 for a new board), the reset day of a weekly
/// board, "Overdue becomes task" for every switch on it, and, editing, Delete Switchboard…, whose question (keep its
/// switches on the main board, or delete them too) sits inside the card. In the grid on the Mac and iPad, over the
/// board on iPhone (`FloatingSwitchCard`), exactly as the switch card is.
struct SwitchboardCard: View {
    /// The board being edited; nil adds one.
    let editing: Switchboard?
    var style: SwitchCard.Style
    /// Opened from a board's Delete…: the delete question shows at once.
    var asksToDelete = false
    var isConfirmingDiscard = false
    var isClosing = false
    var onClose: () -> Void
    var onSaved: (Switchboard) -> Void
    /// The board was deleted (its switches kept or deleted as asked).
    var onDeleted: () -> Void = {}
    var onDraftChange: (Bool) -> Void = { _ in }
    var onDiscard: () -> Void = {}
    var onKeepEditing: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: SwitchboardDraft
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init(editing: Switchboard?, style: SwitchCard.Style, asksToDelete: Bool = false, isConfirmingDiscard: Bool = false,
         isClosing: Bool = false, onClose: @escaping () -> Void, onSaved: @escaping (Switchboard) -> Void,
         onDeleted: @escaping () -> Void = {}, onDraftChange: @escaping (Bool) -> Void = { _ in },
         onDiscard: @escaping () -> Void = {}, onKeepEditing: @escaping () -> Void = {}) {
        self.editing = editing
        self.style = style
        self.asksToDelete = asksToDelete
        self.isConfirmingDiscard = isConfirmingDiscard
        self.isClosing = isClosing
        self.onClose = onClose
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onDraftChange = onDraftChange
        self.onDiscard = onDiscard
        self.onKeepEditing = onKeepEditing
        _draft = State(initialValue: editing.map(SwitchboardDraft.init) ?? SwitchboardDraft())
        _confirmingDelete = State(initialValue: asksToDelete && editing != nil)
    }

    private var padding: CGFloat { style == .floating ? QuickAddPopout.padding : CompactQuickAddCard.padding + 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HITSpacing.m) {
                nameField
                HITSegmented(selection: $draft.cadence, segments: [
                    HITSegment(SwitchboardSchedule.Cadence.daily, "Daily", systemImage: "sun.max"),
                    HITSegment(SwitchboardSchedule.Cadence.weekly, "Weekly", systemImage: "calendar"),
                ])
                .accessibilityIdentifier("switchboardCadence")
                resetRow
                overdueRow
                if let errorMessage {
                    Text(errorMessage).font(HITType.caption).foregroundStyle(HITColor.danger)
                }
                footer
            }
            .padding(padding)
            if confirmingDelete, let editing {
                SwitchboardDeleteRow(board: editing, padding: padding, onCancel: {
                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDelete = false }
                }, onDelete: delete(keepingSwitches:))
                .transition(.opacity)
            } else if isConfirmingDiscard {
                SwitchDiscardRow(question: editing == nil ? "Discard this Switchboard?" : "Discard changes?",
                                 padding: padding, onKeepEditing: onKeepEditing, onDiscard: onDiscard)
                    .transition(.opacity)
            }
        }
        .modifier(SwitchCardChrome(style: style))
        .contentShape(Rectangle())
        .onTapGesture { if isConfirmingDiscard { onKeepEditing() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("switchboardCard")
        .onAppear {
            if editing == nil { nameFocused = true }
            onDraftChange(draft.hasContent)
        }
        #if os(macOS)
        .onExitCommand(perform: onClose)
        #endif
        .onChange(of: draft) { _, new in
            onDraftChange(new.hasContent)
            if isConfirmingDiscard { onKeepEditing() }
        }
        .onChange(of: isClosing) { _, closing in if closing { SwitchCard.dropKeyboard() } }
    }

    // MARK: Parts

    private var nameField: some View {
        TextField(text: $draft.name) {
            Text("Switchboard name").foregroundStyle(Theme.secondaryText)
        }
        .textFieldStyle(.plain)
        .font(HITType.taskName)
        .foregroundStyle(HITColor.text)
        .focused($nameFocused)
        .onSubmit(save)
        .submitLabel(.done)
        .accessibilityIdentifier("switchboardName")
    }

    /// "Resets at ‹04:00›", and on a weekly board "on ‹Monday›".
    private var resetRow: some View {
        HStack(spacing: HITSpacing.s) {
            Text("Resets at")
                .font(HITType.body)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize()
            PickerTimeField(time: draft.resetTime, placeholder: "04:00") { time in
                // A board always has a day; no time is midnight.
                draft.resetTime = time ?? PickerTime(hour: 0, minute: 0)
            }
            .frame(maxWidth: 150)
            .accessibilityIdentifier("switchboardResetTime")
            if draft.cadence == .weekly { weekdayMenu }
            Spacer(minLength: 0)
        }
    }

    private var weekdayMenu: some View {
        let choices = SwitchboardDraft.weekdayChoices(weekStart: Preferences.weekStartWeekday())
        let title = choices.first { $0.value == draft.resetWeekday }.map { $0.value == 0 ? shortWeekStart : $0.title }
            ?? shortWeekStart
        return Menu {
            ForEach(choices, id: \.value) { choice in
                Button {
                    draft.resetWeekday = choice.value
                } label: {
                    if draft.resetWeekday == choice.value { Label(choice.title, systemImage: "checkmark") } else { Text(choice.title) }
                }
            }
        } label: {
            HITChipLabel("on \(title)", systemImage: "calendar")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("switchboardResetDay")
    }

    /// The week start's own name ("Monday"), for the menu's label.
    private var shortWeekStart: String {
        let weekday = SwitchboardSchedule.weekday(stored: 0, weekStart: Preferences.weekStartWeekday())
        return Calendar.current.standaloneWeekdaySymbols[weekday - 1]
    }

    private var overdueRow: some View {
        Toggle(isOn: $draft.overdueBecomesTask) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Overdue becomes task")
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                Text("Every switch on it waits in Today once it’s due")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .toggleStyle(.hit)
        .accessibilityIdentifier("switchboardOverdueToggle")
    }

    private var footer: some View {
        HStack(spacing: HITSpacing.s) {
            if editing != nil {
                Button("Delete Switchboard…", role: .destructive) {
                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDelete = true }
                }
                .buttonStyle(HITButtonStyle(.ghost, size: .small))
                .foregroundStyle(HITColor.danger)
                .accessibilityIdentifier("switchboardDelete")
            }
            Spacer(minLength: HITSpacing.s)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(HITButtonStyle(.ghost, size: .small, shape: .circle))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("switchboardClose")
                .help("Close (Esc)")
            ConfirmPill(kind: draft.canSave ? .primary : .secondary) { save() }
                .opacity(draft.canSave ? 1 : 0.55)
                .disabled(!draft.canSave)
                .accessibilityLabel(editing == nil ? "Add Switchboard" : "Save Switchboard")
                .accessibilityIdentifier("switchboardSave")
                .help(editing == nil ? "Add Switchboard (Return)" : "Save (Return)")
        }
    }

    // MARK: Actions

    private func save() {
        guard !isConfirmingDiscard, !confirmingDelete else { return }
        do {
            guard let board = try draft.save(editing: editing, in: context) else { return }
            errorMessage = nil
            #if os(iOS)
            if editing == nil { TapHaptic.play() }
            #endif
            AccessibilityNotification.Announcement(editing == nil ? "Added \(board.name)" : "Saved \(board.name)").post()
            Task { await NotificationScheduler.reschedule(context: context) }
            onSaved(board)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(keepingSwitches: Bool) {
        guard let editing else { return }
        withAnimation(.snappy) { Flipboard.deleteSwitchboard(editing, deletingSwitches: !keepingSwitches, in: context) }
        Task { await NotificationScheduler.reschedule(context: context) }
        onDeleted()
    }
}

/// "Delete ‘Before Bed’?" at the card's foot (the question sits inside the card it concerns): keep its switches on the
/// main board, delete them too, or not delete at all. A board with no switches just asks Delete.
struct SwitchboardDeleteRow: View {
    let board: Switchboard
    let padding: CGFloat
    var onCancel: () -> Void
    /// `keepingSwitches`: its switches stay, as loose switches.
    var onDelete: (_ keepingSwitches: Bool) -> Void

    private var count: Int { board.switches?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            VStack(alignment: .leading, spacing: HITSpacing.s) {
                Text("Delete ‘\(board.name)’?")
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                if count > 0 {
                    Text(count == 1 ? "Its switch can stay on the Flipboard, or go with it, from every device."
                         : "Its \(count) switches can stay on the Flipboard, or go with it, from every device.")
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: HITSpacing.s) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(HITButtonStyle(.ghost, size: .small))
                        .accessibilityIdentifier("switchboardDeleteCancel")
                    Spacer(minLength: 0)
                    if count > 0 {
                        Button("Keep Switches") { onDelete(true) }
                            .buttonStyle(HITButtonStyle(.secondary, size: .small))
                            .accessibilityIdentifier("switchboardDeleteKeep")
                    }
                    Button(count > 0 ? "Delete All" : "Delete", role: .destructive) { onDelete(false) }
                        .buttonStyle(HITButtonStyle(.destructive, size: .small))
                        .accessibilityIdentifier("switchboardDeleteAll")
                }
            }
            .padding(.horizontal, padding)
            .padding(.vertical, HITSpacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("switchboardDeleteRow")
    }
}
