import SwiftUI
import SwiftData
import HITListCore

/// Adding or editing a switch (brief 69, George on 0.8.1: "Adding switches should have cute popouts that look
/// and feel like the 'Add task' card on the Upcoming page in the Mac app"). A small card: the name, focused at
/// once, read with the quick-add grammar so a typed "every 3 days" lights up and sets the interval; the quick
/// choices; the interval's number and unit and the flips per interval; × and the Confirm pill.
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
    /// The card asks "Discard?" at its foot (after ×, Escape or a tap away with something to lose).
    var isConfirmingDiscard = false
    /// iPhone: the card is going; the keyboard goes down with it.
    var isClosing = false
    /// The name has the keyboard when the card opens (adding; editing on the Mac).
    var focusesName = true
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
    @State private var nameFocused = false
    @State private var errorMessage: String?
    /// The Mac's card stays open after Add for the next switch; this says what was added.
    @State private var added: String?
    @State private var addedGeneration = 0

    init(editing: TaskItem?, style: Style, isConfirmingDiscard: Bool = false, isClosing: Bool = false,
         focusesName: Bool = true, onClose: @escaping () -> Void, onSaved: @escaping (TaskItem) -> Void,
         onDraftChange: @escaping (Bool) -> Void = { _ in }, onDiscard: @escaping () -> Void = {},
         onKeepEditing: @escaping () -> Void = {}) {
        self.editing = editing
        self.style = style
        self.isConfirmingDiscard = isConfirmingDiscard
        self.isClosing = isClosing
        self.focusesName = focusesName
        self.onClose = onClose
        self.onSaved = onSaved
        self.onDraftChange = onDraftChange
        self.onDiscard = onDiscard
        self.onKeepEditing = onKeepEditing
        _draft = State(initialValue: editing.map(SwitchDraft.init) ?? SwitchDraft())
    }

    /// Inside the card: the quick-add oval's 20 on iPhone, the board card's 12 in the grid.
    private var padding: CGFloat { style == .floating ? QuickAddPopout.padding : CompactQuickAddCard.padding + 2 }

    private var parser: QuickAddParser { QuickAddParser(weekStart: Preferences.weekStartWeekday()) }

    var body: some View {
        let parser = parser
        let read = draft.reading(parser)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HITSpacing.m) {
                nameField(read)
                IntervalChoiceStrip(selected: read.choice) { choice in
                    draft.choose(choice.interval, parser)
                }
                intervalRow(read, parser: parser)
                if let errorMessage {
                    Text(errorMessage).font(HITType.caption).foregroundStyle(HITColor.danger)
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
    }

    /// Takes the keyboard from whatever has it, at once. Call it from an action (a tap, a button), never from
    /// inside a view update.
    static func dropKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        TokenHighlightField(placeholder: "Switch name", text: Binding(get: { draft.text }, set: { draft.setText($0) }),
                            tokens: read.tokens, priority: .p4, focus: $nameFocused, bordered: false,
                            onDisable: { token in
                                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.switchOff(token) }
                            },
                            onEnable: { token in
                                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { draft.switchOn(token) }
                            },
                            onSubmit: save)
            .accessibilityIdentifier("switchName")
    }

    /// "Every ‹3› days ⌄": the interval's number and unit.
    private func intervalRow(_ read: SwitchDraft.Reading, parser: QuickAddParser) -> some View {
        let interval = read.interval ?? FlipInterval(count: 1, unit: .weeks)
        return HStack(spacing: HITSpacing.s) {
            Text("Every")
                .font(HITType.body)
                .foregroundStyle(Theme.secondaryText)
            FlipDial(value: interval.count, range: FlipInterval.range, accessibilityName: "Every") { delta in
                draft.step(delta, parser)
            }
            .accessibilityIdentifier("switchIntervalDial")
            unitMenu(interval, parser: parser)
            Spacer(minLength: HITSpacing.s)
            // How it will look: tap it to try the flip.
            SwitchPreviewRocker(flips: draft.flips)
        }
    }

    /// "‹1› flip": flips per interval, at the foot's leading side.
    private var flipsControl: some View {
        HStack(spacing: HITSpacing.s) {
            FlipDial(value: draft.flips, range: 1...Flipboard.maxFlipTarget, accessibilityName: "Flips per interval") { delta in
                draft.setFlips(draft.flips + delta)
            }
            .accessibilityIdentifier("switchFlipsDial")
            Text(draft.flips == 1 ? "flip" : "flips")
                .font(HITType.body)
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
                    .font(HITType.body)
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
            if editing == nil, style == .inline {
                // The Mac and iPad card stays open, empty, for the next switch (as the board's Add task card).
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
private struct SwitchCardChrome: ViewModifier {
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
            .font(HITType.body)
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
