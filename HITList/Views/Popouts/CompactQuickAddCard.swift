import SwiftUI

/// The board's inline add (brief 39, George on 0.5.0: "adding a task in-line should make a smaller 'Add task'
/// popout centered only on that day"). A day column's "+ Add task" turns into this card at the column's foot,
/// as wide as the column, in place of the row. It is the quick add itself (`QuickAddPopout` in its `.compact`
/// style: the same draft, parser, highlights, chips and sticky draft), laid out for 270 pt: the title, the
/// chips wrapping onto as many lines as they need, then × and the Confirm pill.
///
/// Confirm adds the task on the column's day and leaves the card open and empty for the next one. Escape, ×
/// or a click elsewhere on the board closes an empty card; with something typed, the card first asks inside
/// itself, at its foot ("Discard this task?" · Keep editing · Discard; brief 49, George: "contained within
/// the 'Add task' card ... instead of popping out above it"): Escape or × again discards, a click on the card
/// goes back to typing.
/// One inline card at a time: the board's cards are `PopoutState.Placement.inline` cards keyed by day
/// (`BoardInlineAdd.key`), and the controller holds at most one quick add.
struct CompactQuickAddCard: View {
    let context: QuickAddContext
    /// The card is asking "Discard this task?" at its foot (after ×, Escape or a click elsewhere with typing).
    var isConfirmingDiscard = false
    var onClose: () -> Void
    var onSaved: () -> Void = {}
    /// Whether the draft has something in it, whenever that changes (the board decides how a click away behaves).
    var onDraftChange: (Bool) -> Void = { _ in }
    var onDiscard: () -> Void = {}
    /// A click on the card while "Discard" is showing: back to typing.
    var onKeepEditing: () -> Void = {}

    /// Inside the card, every side: smaller than the panel's 20 so the chips have the column's width.
    static let padding: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        VStack(spacing: 0) {
            QuickAddPopout(context: context, style: .compact, isPaused: isConfirmingDiscard,
                           onClose: onClose, onSaved: onSaved, onDraftChange: onDraftChange)
                .accessibilityIdentifier("boardQuickAdd")
            if isConfirmingDiscard {
                InlineDiscardRow(padding: Self.padding, onKeepEditing: onKeepEditing, onDiscard: onDiscard)
                    .transition(.opacity)
            }
        }
        // The card grows to fit the question; the board's column scrolls if it has to.
        .background(shape.fill(Theme.surface))
        // A touch stronger than a task card's hairline: this one is being edited.
        .overlay(shape.strokeBorder(Theme.secondaryText.opacity(0.45), lineWidth: 1).allowsHitTesting(false))
        .clipShape(shape)
        // A click anywhere on the card is a click on the card, never a click away (the board listens for
        // those above it, and a child's tap comes first; the fields, chips and buttons still take theirs).
        // While the card asks, it means keep editing.
        .contentShape(Rectangle())
        .onTapGesture { if isConfirmingDiscard { onKeepEditing() } }
    }
}

/// "Discard this task?" with Keep editing and Discard, as the foot of a Mac or iPad quick-add card (the
/// board's `CompactQuickAddCard`, a list's `InlineAddRow`), under a hairline, so the question sits inside the
/// card it is about (HIG: a popover is not for warnings). The iPhone's docked card keeps `DiscardBubble`.
/// Escape or × on the card again also discards; Keep editing or a click on the card goes back to typing.
struct InlineDiscardRow: View {
    /// The card's own inner padding, so the row's edges line up with the title's and the footer's.
    let padding: CGFloat
    var onKeepEditing: () -> Void
    var onDiscard: () -> Void

    static let question = "Discard this task?"

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            // Side by side when the card is wide enough (a list's card), the question over the buttons in the
            // board's 270 pt column.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: HITSpacing.s) {
                    question
                    Spacer(minLength: HITSpacing.s)
                    buttons
                }
                VStack(alignment: .leading, spacing: HITSpacing.s) {
                    question
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
        .accessibilityLabel(Self.question)
        .accessibilityIdentifier("quickAddDiscardRow")
    }

    private var question: some View {
        Text(Self.question)
            .font(HITType.body)
            .foregroundStyle(HITColor.text)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Keep editing", action: onKeepEditing)
            .buttonStyle(HITButtonStyle(.secondary, size: .small))
            .accessibilityIdentifier("quickAddKeepEditing")
        Button("Discard", role: .destructive, action: onDiscard)
            .buttonStyle(HITButtonStyle(.destructive, size: .small))
            .accessibilityLabel("Discard draft")
            .accessibilityIdentifier("quickAddDiscard")
    }
}

/// The board's inline cards as plain values, so tests can drive them.
enum BoardInlineAdd {
    /// The inline card key (`PopoutState.Placement.inline`) of a board day column: one per day, whatever the
    /// time of `day`.
    static func key(for day: Date, calendar: Calendar = .current) -> String {
        "board-\(Int(calendar.startOfDay(for: day).timeIntervalSinceReferenceDate))"
    }

    /// Whether an inline card is one of the board's (and not a list's "Add task" row).
    static func isBoardKey(_ key: String) -> Bool { key.hasPrefix("board-") }

    /// The board card that is open, if the open quick add is one.
    static func openKey(in state: PopoutState) -> String? {
        guard case .inline(let key)? = state.quickAdd?.placement, isBoardKey(key) else { return nil }
        return key
    }

    /// What a click elsewhere on the board (another task, another day's "Add task", the empty board) does
    /// while a card is open.
    enum ClickAway: Equatable {
        /// Nothing typed: the card closes and the click does what it would have done.
        case close
        /// Something typed: the card asks "Discard this task?" at its foot and the click does nothing else.
        case askDiscard
        /// "Discard" is already showing: the click is taken as "keep editing" (as on iPhone).
        case keepEditing
    }

    static func clickAway(hasContent: Bool, confirmingDiscard: Bool) -> ClickAway {
        if confirmingDiscard { return .keepEditing }
        return hasContent ? .askDiscard : .close
    }

    /// What × or Escape does on an open card.
    enum Close: Equatable {
        /// Nothing typed: the card closes.
        case close
        /// Something typed: the card asks "Discard this task?" first (the iPhone card's rule).
        case askDiscard
        /// "Discard" is already showing: × or Escape again throws the typing away.
        case discard
    }

    static func close(hasContent: Bool, confirmingDiscard: Bool) -> Close {
        if confirmingDiscard { return .discard }
        return hasContent ? .askDiscard : .close
    }
}
