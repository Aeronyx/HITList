import SwiftUI
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif

/// Adding or editing a switch (brief 69, George on 0.8.1: "Adding switches should have cute popouts that look
/// and feel like the 'Add task' card on the Upcoming page in the Mac app"). A small card: the name, focused at
/// once, read with the quick-add grammar so a typed "every 3 days" lights up and sets the interval and a typed
/// "9pm" the time; the quick choices; the interval's number and unit (on a Switchboard, "Daily, with Before Bed"
/// in their place); the time and the Switchboard as two chips side by side, and "Become a task when Overdue" (briefs 72
/// and 96); "Flip ‹1› time", × and the Confirm pill. One scale of type (`SwitchCardType`). The Switchboard chip's
/// New Switchboard… turns the card into the Switchboard card and back, the switch kept as it was typed.
///
/// On the Mac and iPad it opens in the grid, in place of the + tile (or of the switch it edits), as wide as
/// two tiles (`FlipboardGrid`). On iPhone it rises from the bottom over the dimmed board, above the keyboard,
/// like the quick-add card (`FloatingSwitchCard`). A tap away or × with a name typed (or, editing, with
/// something changed) asks "Discard?" at the card's foot first (George's rule; `BoardInlineAdd` holds it).
struct SwitchCard: View {
    enum Style {
        /// iPhone: the oval card over the board, in glass.
        case floating
        /// Mac and iPad: in the grid, the Upcoming board's Add task card look.
        case inline
    }

    /// The switch being edited; nil adds one.
    let editing: TaskItem?
    var style: Style
    /// Adding: the Switchboard whose "+" opened the card (brief 72); nil for a loose switch.
    var board: Switchboard?
    /// Duplicate (brief 96): the switch whose settings the new one starts with, its name left empty.
    var duplicating: TaskItem?
    /// The card asks "Discard?" at its foot (after ×, Escape or a tap away with something to lose).
    var isConfirmingDiscard = false
    /// iPhone: the card is going; the keyboard goes down with it.
    var isClosing = false
    /// The name has the keyboard when the card opens (adding; editing on the Mac).
    var focusesName = true
    /// The keyboard has stepped aside for the Discard question (brief 107): the name does not ask for it meanwhile.
    var keyboardSteppedAside = false
    /// Bumped by the host to give the name the keyboard again (it stepped aside for the Discard question; brief 107).
    var nameFocusRequest = 0
    /// × or Escape: the host decides (close, ask, or discard).
    var onClose: () -> Void
    /// Add or Save wrote this switch.
    var onSaved: (TaskItem) -> Void
    /// Whether the card has something to lose, whenever that changes.
    var onDraftChange: (Bool) -> Void = { _ in }
    var onDiscard: () -> Void = {}
    var onKeepEditing: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: SwitchDraft
    /// Every Switchboard, for the card's board menu.
    @Query private var allBoards: [Switchboard]
    @State private var nameFocused = false
    @State private var errorMessage: String?
    /// The Mac's card stays open after Add for the next switch; its empty name says what was added.
    @State private var added: String?
    @State private var addedGeneration = 0
    /// New Switchboard… from the Switchboard chip: the card shows the Switchboard card until it is saved or closed.
    @State private var makingBoard = false
    /// The Switchboard card's own "something to lose" while it shows (its name typed).
    @State private var boardHasContent = false

    /// The toggle's words (George's, exactly; brief 96). One line, nothing under it.
    static let overdueTitle = "Become a task when Overdue"

    /// The foot's count, around its dial: "Flip ‹1› time", "Flip ‹3› times": how many flips turn the switch green each
    /// time it is due (a charger takes more than one).
    static func flipsWords(_ count: Int) -> (before: String, after: String) {
        ("Flip", count == 1 ? "time" : "times")
    }

    init(editing: TaskItem?, style: Style, board: Switchboard? = nil, duplicating: TaskItem? = nil,
         isConfirmingDiscard: Bool = false, isClosing: Bool = false,
         focusesName: Bool = true, keyboardSteppedAside: Bool = false, nameFocusRequest: Int = 0,
         onClose: @escaping () -> Void,
         onSaved: @escaping (TaskItem) -> Void,
         onDraftChange: @escaping (Bool) -> Void = { _ in }, onDiscard: @escaping () -> Void = {},
         onKeepEditing: @escaping () -> Void = {}) {
        self.editing = editing
        self.style = style
        self.board = board
        self.duplicating = duplicating
        self.isConfirmingDiscard = isConfirmingDiscard
        self.isClosing = isClosing
        self.focusesName = focusesName
        self.keyboardSteppedAside = keyboardSteppedAside
        self.nameFocusRequest = nameFocusRequest
        self.onClose = onClose
        self.onSaved = onSaved
        self.onDraftChange = onDraftChange
        self.onDiscard = onDiscard
        self.onKeepEditing = onKeepEditing
        _draft = State(initialValue: editing.map { SwitchDraft($0) } ?? duplicating.map { SwitchDraft(duplicating: $0) }
                       ?? SwitchDraft(boardID: board?.id))
    }

    private var boards: [Switchboard] { Flipboard.ordered(allBoards) }

    /// The board the draft is on, if it still exists.
    private var chosenBoard: Switchboard? { draft.boardID.flatMap { id in allBoards.first { $0.id == id } } }

    /// Inside the card: the quick-add oval's 20 on iPhone, the board card's 12 in the grid.
    private var padding: CGFloat { style == .floating ? QuickAddPopout.padding : CompactQuickAddCard.padding + 2 }

    private var parser: QuickAddParser { QuickAddParser(weekStart: Preferences.weekStartWeekday()) }

    var body: some View {
        if makingBoard {
            // The Switchboard card, in this card's place: saved, it comes back with the new board chosen; × goes back.
            SwitchboardCard(editing: nil, style: style, isConfirmingDiscard: isConfirmingDiscard, isClosing: isClosing,
                            discardQuestion: editing == nil ? "Discard this switch?" : "Discard changes?",
                            onClose: { leaveBoardPage(chosen: nil) },
                            onSaved: { board in leaveBoardPage(chosen: board) },
                            onDraftChange: { has in
                                boardHasContent = has
                                onDraftChange(has || draft.hasContent(parser))
                            },
                            onDiscard: onDiscard, onKeepEditing: onKeepEditing)
                .transition(.opacity)
        } else {
            switchCard
                .transition(.opacity)
        }
    }

    /// Back from the Switchboard card: with the board just made chosen (and the name given the keyboard again).
    private func leaveBoardPage(chosen board: Switchboard?) {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
            if let board { draft.boardID = board.id }
            makingBoard = false
        }
        boardHasContent = false
        onDraftChange(draft.hasContent(parser))
        nameFocused = true
    }

    private var switchCard: some View {
        let parser = parser
        let read = draft.reading(parser)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HITSpacing.m) {
                nameField(read)
                if let chosenBoard {
                    boardRow(chosenBoard)
                } else {
                    IntervalChoiceStrip(selected: read.choice) { choice in
                        draft.choose(choice.interval, parser)
                    }
                    intervalRow(read, parser: parser)
                }
                timeAndBoardRow(read, parser: parser)
                overdueRow
                if let errorMessage {
                    Text(errorMessage).font(SwitchCardType.secondary).foregroundStyle(HITColor.danger)
                }
                footer(canSave: !read.title.isEmpty)
            }
            .padding(padding)
            if isConfirmingDiscard {
                SwitchDiscardRow(question: editing == nil ? "Discard this switch?" : "Discard changes?",
                                 padding: padding, onKeepEditing: onKeepEditing, onDiscard: onDiscard)
                    .transition(.opacity)
            }
        }
        .modifier(SwitchCardChrome(style: style))
        // A tap on the card while it asks means keep editing (the fields and buttons still take theirs).
        .contentShape(Rectangle())
        .onTapGesture { if isConfirmingDiscard { onKeepEditing() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("switchCard")
        .onAppear {
            if focusesName { nameFocused = true }
            onDraftChange(draft.hasContent(parser))
        }
        #if os(macOS)
        .task(claimNameFocus)
        .onExitCommand(perform: onClose)
        #endif
        .onChange(of: draft) { _, new in
            onDraftChange(new.hasContent(parser))
            // Typing (or a chip) while the card asks is keeping it.
            if isConfirmingDiscard { onKeepEditing() }
        }
        // The keyboard stays up while the card asks: the question is inside the card, above it. (Letting it go
        // from here, inside an update, hung the iPhone's cover: UIKit's keyboard tracking laid the cover out
        // again mid-update. The card's owner drops the keyboard from its action when the card goes:
        // `SwitchCard.dropKeyboard()`.)
        .onChange(of: isClosing) { _, closing in if closing { Self.dropKeyboard() } }
        .onChange(of: nameFocusRequest) { _, _ in if !makingBoard, !isClosing { nameFocused = true } }
    }

    /// Takes the keyboard from whatever has it, at once. Call it from an action (a tap, a button), never from
    /// inside a view update.
    static func dropKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    /// Nothing on iPhone and iPad, where the keyboard passes straight to the Switchboard card's name; on the Mac the
    /// name's text view lets go first so the next one can take it.
    static func dropKeyboardOnTheMac() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    #if os(macOS)
    /// The name has the keyboard the moment the card shows, with no click (as the board's Add task card,
    /// brief 39): the focus asked for on appear can be lost to the click that opened the card, so it is asked
    /// again over the next quarter second.
    private var claimNameFocus: @Sendable () async -> Void {
        let name = $nameFocused, wanted = focusesName
        return { @MainActor in
            guard wanted else { return }
            for delay in [0, 30, 80, 150, 250] {
                guard (try? await Task.sleep(for: .milliseconds(delay))) != nil else { return }
                if !name.wrappedValue { name.wrappedValue = true }
            }
        }
    }
    #endif

    // MARK: Parts

    private func nameField(_ read: SwitchDraft.Reading) -> some View {
        // The draft's own binding, as quick add's: typing fast lost a letter through a hand-made Binding.
        // After an Add on the Mac the empty name says what was added, until the next switch is typed or 3 s pass.
        TokenHighlightField(placeholder: added ?? "Switch name", text: $draft.text,
                            tokens: read.tokens, priority: .p4, focus: nameFocus, bordered: false,
                            onDisable: { token in
                                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.switchOff(token) }
                            },
                            onEnable: { token in
                                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.switchOn(token) }
                            },
                            onSubmit: save)
            .accessibilityIdentifier("switchName")
    }

    /// The name's focus, false while the keyboard has stepped aside for the Discard question.
    private var nameFocus: Binding<Bool> {
        Binding(get: { nameFocused && !keyboardSteppedAside }, set: { nameFocused = $0 })
    }

    /// "Every ‹3› days ⌄": the interval's number and unit.
    private func intervalRow(_ read: SwitchDraft.Reading, parser: QuickAddParser) -> some View {
        let interval = read.interval ?? FlipInterval(count: 1, unit: .weeks)
        return HStack(spacing: HITSpacing.s) {
            Text("Every")
                .font(SwitchCardType.label)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: SwitchCardType.leadWidth, alignment: .leading)
            FlipDial(value: interval.count, range: FlipInterval.range, accessibilityName: "Every") { delta in
                draft.step(delta, parser)
            }
            .accessibilityIdentifier("switchIntervalDial")
            unitMenu(interval, parser: parser)
            Spacer(minLength: 0)
        }
    }

    /// On a Switchboard, in place of the quick choices and the dial: "Daily, with Before Bed" (the board's cadence is
    /// the interval).
    private func boardRow(_ board: Switchboard) -> some View {
        HStack(spacing: HITSpacing.s) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text(SwitchDraft.boardLine(board))
                .font(SwitchCardType.label)
                .foregroundStyle(HITColor.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(minHeight: FlipDial.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("switchBoardLine")
    }

    /// The switch's time and its Switchboard: two chips of one size side by side (brief 96), the time typed into its
    /// chip ("9pm", "21:00", "noon", then Return).
    private func timeAndBoardRow(_ read: SwitchDraft.Reading, parser: QuickAddParser) -> some View {
        HStack(spacing: HITSpacing.s) {
            SwitchTimeChip(time: read.time) { time in
                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.setTime(time, parser) }
            } onStart: {
                nameFocused = false
            } onFinish: {
                nameFocused = true
            }
            boardMenu
            Spacer(minLength: 0)
        }
    }

    /// No Switchboard, the boards, and New Switchboard… (brief 96: the way to a first board from the card itself).
    private var boardMenu: some View {
        Menu {
            boardChoice("No Switchboard", id: nil)
            if !boards.isEmpty {
                Divider()
                ForEach(boards) { board in boardChoice(board.name, id: board.id) }
            }
            Divider()
            Button {
                SwitchCard.dropKeyboardOnTheMac()
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { makingBoard = true }
            } label: {
                Label("New Switchboard…", systemImage: "plus")
            }
        } label: {
            HITChipLabel(chosenBoard?.name ?? "No Switchboard", systemImage: "square.grid.2x2", isSelected: chosenBoard != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Switchboard: \(chosenBoard?.name ?? "none")")
        .accessibilityIdentifier("switchBoardMenu")
    }

    /// One of the board menu's choices, ticked when it is the draft's.
    @ViewBuilder
    private func boardChoice(_ title: String, id: UUID?) -> some View {
        Button {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { draft.boardID = id }
        } label: {
            if draft.boardID == id { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// "Become a task when Overdue" (briefs 72 and 96): off, the switch is never a task; on, it waits in Today once it
    /// is due. One line: a Switchboard with its own toggle on opts every switch on it in, and the row shows on and
    /// dimmed, saying why to VoiceOver and the pointer.
    private var overdueRow: some View {
        let boardOptIn = chosenBoard?.overdueBecomesTask ?? false
        let isOn = Binding(get: { draft.overdueBecomesTask || boardOptIn }, set: { draft.overdueBecomesTask = $0 })
        let why = "On for every switch on \(chosenBoard?.name ?? "its Switchboard")"
        return Toggle(isOn: isOn) {
            Text(Self.overdueTitle)
                .font(SwitchCardType.label)
                .foregroundStyle(HITColor.text)
                .lineLimit(1)
        }
        .toggleStyle(.hit)
        .disabled(boardOptIn)
        .help(boardOptIn ? why : "Waits in Today once it’s due")
        .accessibilityHint(boardOptIn ? why : "Waits in Today once it’s due")
        .accessibilityIdentifier("switchOverdueToggle")
    }

    /// "Flip ‹1› time": how many flips turn it green each time it is due, at the foot's leading side, its dial under
    /// the interval's (the leading words share a width).
    private var flipsControl: some View {
        let words = Self.flipsWords(draft.flips)
        return HStack(spacing: HITSpacing.s) {
            Text(words.before)
                .font(SwitchCardType.label)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: SwitchCardType.leadWidth, alignment: .leading)
            FlipDial(value: draft.flips, range: 1...Flipboard.maxFlipTarget, accessibilityName: "Flips each time") { delta in
                draft.setFlips(draft.flips + delta)
            }
            .accessibilityIdentifier("switchFlipsDial")
            Text(words.after)
                .font(SwitchCardType.label)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize()
        }
    }

    private func unitMenu(_ interval: FlipInterval, parser: QuickAddParser) -> some View {
        Menu {
            ForEach(FlipInterval.Unit.allCases) { unit in
                Button(unit.word(interval.count).capitalized) { draft.setUnit(unit, parser) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(interval.unit.word(interval.count))
                    .font(SwitchCardType.label)
                    .foregroundStyle(HITColor.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Unit: \(interval.unit.rawValue)")
        .accessibilityIdentifier("switchUnit")
    }

    private func footer(canSave: Bool) -> some View {
        HStack(spacing: HITSpacing.s) {
            flipsControl
            Spacer(minLength: HITSpacing.s)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(HITButtonStyle(.ghost, size: .small, shape: .circle))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("switchClose")
                .help("Close (Esc)")
            ConfirmPill(kind: canSave ? .primary : .secondary) { save() }
                .opacity(canSave ? 1 : 0.55)
                .animation(HITMotion.quick(reduceMotion: reduceMotion), value: canSave)
                .disabled(!canSave)
                .accessibilityLabel(editing == nil ? "Add switch" : "Save switch")
                .accessibilityIdentifier("switchSave")
                .help(editing == nil ? "Add switch (Return)" : "Save (Return)")
        }
    }

    // MARK: Saving

    private func save() {
        guard !isConfirmingDiscard else { return }
        let parser = parser
        guard draft.canSave(parser) else { return }
        do {
            guard let task = try draft.save(editing: editing, parser: parser, in: context) else { return }
            errorMessage = nil
            #if os(iOS)
            if editing == nil { TapHaptic.play() }
            #endif
            AccessibilityNotification.Announcement(editing == nil ? "Added \(task.title)" : "Saved \(task.title)").post()
            Task { await NotificationScheduler.reschedule(context: context) }
            if editing == nil, duplicating == nil, style == .inline {
                // The Mac and iPad card stays open, empty, for the next switch (as the board's Add task card); a
                // duplicate's closes once it is added.
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
                    draft = SwitchDraft()
                    added = "Added ‘\(task.title)’"
                }
                addedGeneration += 1
                let generation = addedGeneration
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if generation == addedGeneration { withAnimation { added = nil } }
                }
                nameFocused = true
            }
            onSaved(task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The card's look. iPhone: the quick-add oval's glass. Mac and iPad: the Upcoming board's Add task card
/// (`CompactQuickAddCard`), slate with a stronger hairline, in the tiles' grid.
struct SwitchCardChrome: ViewModifier {
    let style: SwitchCard.Style

    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content.ovalCardChrome()
        case .inline:
            let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
            content
                .background(shape.fill(Theme.surface))
                .overlay(shape.strokeBorder(Theme.secondaryText.opacity(0.45), lineWidth: 1).allowsHitTesting(false))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
    }
}

/// "Discard this switch?" with Keep editing and Discard, at the card's foot under a hairline: the question
/// sits inside the card it is about (HIG; the board card's `InlineDiscardRow`, worded for a switch).
struct SwitchDiscardRow: View {
    let question: String
    let padding: CGFloat
    var onKeepEditing: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: HITSpacing.s) {
                    questionText
                    Spacer(minLength: HITSpacing.s)
                    buttons
                }
                VStack(alignment: .leading, spacing: HITSpacing.s) {
                    questionText
                    HStack(spacing: HITSpacing.s) {
                        Spacer(minLength: 0)
                        buttons
                    }
                }
            }
            .padding(.horizontal, padding)
            .padding(.vertical, HITSpacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question)
        .accessibilityIdentifier("switchDiscardRow")
    }

    private var questionText: some View {
        Text(question)
            .font(SwitchCardType.label)
            .foregroundStyle(HITColor.text)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Keep editing", action: onKeepEditing)
            .buttonStyle(HITButtonStyle(.secondary, size: .small))
            .accessibilityIdentifier("switchKeepEditing")
        Button("Discard", role: .destructive, action: onDiscard)
            .buttonStyle(HITButtonStyle(.destructive, size: .small))
            .accessibilityIdentifier("switchDiscard")
    }
}

/// The cards' one scale of type (brief 96, George: "fonts are different sizes"): the name at the card title's size,
/// every label, value and chip at the chips' size, and a secondary line one size down. The switch card and the
/// Switchboard card share it.
///
/// | Text | iPhone and iPad | Mac |
/// |---|---|---|
/// | The name | Inter 19 bold | Inter 15 bold |
/// | Labels: "Every", "days", "Become a task when Overdue", "Flip … times", "Daily, with Before Bed", "Resets at" | Inter 15 | Inter 13 |
/// | Values: the dials' numbers | Inter 15 semibold | Inter 13 semibold |
/// | Chips and the quick choices (`HITType.control`) | Inter 15 semibold | Inter 13 medium |
/// | Secondary: an error, the delete question's explanation | Inter 12 | Inter 10 |
enum SwitchCardType {
    #if os(macOS)
    static let nameSize: CGFloat = 15
    static let labelSize: CGFloat = 13
    static let secondarySize: CGFloat = 10
    private static let scale: Font.TextStyle = .body
    #else
    static let nameSize: CGFloat = 19
    static let labelSize: CGFloat = 15
    static let secondarySize: CGFloat = 12
    private static let scale: Font.TextStyle = .subheadline
    #endif

    /// The switch's or the Switchboard's name: quick add's title (`HITType.taskName`).
    static let name = HITType.taskName
    static let label = HITFont.inter(labelSize, .regular, relativeTo: scale)
    static let value = HITFont.inter(labelSize, .semibold, relativeTo: scale).monospacedDigit()
    static let secondary = HITType.caption
    /// "Every" and "Flip" are one width, so the interval's dial and the flips' dial stand one above the other.
    #if os(macOS)
    static let leadWidth: CGFloat = 36
    #else
    static let leadWidth: CGFloat = 42
    #endif
}
