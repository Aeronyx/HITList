import SwiftUI

/// The board's inline add (brief 39, George on 0.5.0: "adding a task in-line should make a smaller 'Add task'
/// popout centered only on that day"). A day column's "+ Add task" turns into this card at the column's foot,
/// as wide as the column, in place of the row. It is the quick add itself (`QuickAddPopout` in its `.compact`
/// style: the same draft, parser, highlights, chips and sticky draft), laid out for 270 pt: the title, the
/// chips wrapping onto as many lines as they need, then × and the Confirm pill.
///
/// Confirm adds the task on the column's day and leaves the card open and empty for the next one. Escape, ×
/// or a click elsewhere on the board closes an empty card; with something typed, "Discard" is offered above
/// the card first (the iPhone card's rule): Escape or × again discards, a click on the card goes back to typing.
/// One inline card at a time: the board's cards are `PopoutState.Placement.inline` cards keyed by day
/// (`BoardInlineAdd.key`), and the controller holds at most one quick add.
struct CompactQuickAddCard: View {
    let context: QuickAddContext
    /// "Discard" is showing above the card (the board asks after a click elsewhere with something typed).
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
        VStack(spacing: HITSpacing.s) {
            if isConfirmingDiscard {
                DiscardBubble(action: onDiscard)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
            QuickAddPopout(context: context, style: .compact, isPaused: isConfirmingDiscard,
                           onClose: onClose, onSaved: onSaved, onDraftChange: onDraftChange)
                .background(shape.fill(Theme.surface))
                // A touch stronger than a task card's hairline: this one is being edited.
                .overlay(shape.strokeBorder(Theme.secondaryText.opacity(0.45), lineWidth: 1).allowsHitTesting(false))
                .clipShape(shape)
                .accessibilityIdentifier("boardQuickAdd")
        }
        // A click anywhere on the card is a click on the card, never a click away (the board listens for
        // those above it, and a child's tap comes first; the fields, chips and buttons still take theirs).
        // While "Discard" shows it means keep editing.
        .contentShape(Rectangle())
        .onTapGesture { if isConfirmingDiscard { onKeepEditing() } }
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
        /// Something typed: "Discard" shows above the card and the click does nothing else.
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
        /// Something typed: "Discard" shows above the card first (the iPhone card's rule).
        case askDiscard
        /// "Discard" is already showing: × or Escape again throws the typing away.
        case discard
    }

    static func close(hasContent: Bool, confirmingDiscard: Bool) -> Close {
        if confirmingDiscard { return .discard }
        return hasContent ? .askDiscard : .close
    }
}
