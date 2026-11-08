import SwiftUI

/// What the switch card is open for.
enum SwitchCardRequest: Identifiable, Equatable {
    case add
    case edit(TaskItem)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let task): "edit-\(task.id.uuidString)"
        }
    }

    var task: TaskItem? {
        if case .edit(let task) = self { return task }
        return nil
    }
}

/// The switch card's "something to lose", kept where reading and writing it redraws nothing: the hosts only
/// read it when the card is tapped away from or closed.
final class SwitchCardContent {
    var hasContent = false
}

#if os(iOS)
/// The iPhone's switch card (brief 69): it rises from the bottom over the dimmed board and floats 12 pt above
/// the keyboard, the quick-add card's oval and motion (`PopoutHost`), never a full-height sheet. A tap on the
/// dimmed board is a tap away: an empty card closes, one with a name typed asks Discard at its foot.
///
/// It is presented as a clear full-screen cover so the dimming reaches over the navigation bar and the tab
/// island the way the quick-add card's does; the cover itself appears and goes without animation, and the
/// card brings its own (`HITMotion.enter` / `exit`).
struct FloatingSwitchCard: View {
    let request: SwitchCardRequest
    /// The card has gone; the switch it added or saved, if any.
    var onFinished: (TaskItem?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var keyboard: KeyboardObserver { .shared }
    @State private var shown = false
    @State private var closing = false
    @State private var heldKeyboardHeight: CGFloat = 0
    /// Whether the card has something to lose: read when it is tapped away from, never drawn, so a box that
    /// re-renders nothing (the first letter typed re-laid out the whole cover and the next letter was lost).
    @State private var content = SwitchCardContent()
    @State private var confirmingDiscard = false

    /// The oval's distance from the screen's edges and from the top of the keyboard (`PopoutHost.ovalInset`).
    private static let inset: CGFloat = 12
    /// How long the card takes to go before the cover is removed.
    static let retractDuration: TimeInterval = 0.2

    var body: some View {
        // Built here, outside the geometry reader, as `PopoutHost` builds the quick-add card: the keyboard moving
        // re-runs only the reader's closure, never the card. A keyboard change arrives in the middle of a
        // keystroke (UIKit lays the view out there and then); a card rebuilt at that moment handed its name
        // field the text from before the keystroke, and the letter was lost (the UI test's "Wter the plants").
        let card = SwitchCard(editing: request.task, style: .floating, isConfirmingDiscard: confirmingDiscard,
                              isClosing: closing, focusesName: request == .add,
                              onClose: requestClose, onSaved: { finish(saved: $0) },
                              onDraftChange: { content.hasContent = $0 },
                              onDiscard: { finish(saved: nil) },
                              onKeepEditing: keepEditing)
        GeometryReader { geo in
            let keyboardHeight = closing ? heldKeyboardHeight : keyboard.height
            let aboveKeyboard = max(0, keyboardHeight - geo.safeAreaInsets.bottom)
            ZStack(alignment: .bottom) {
                Color.black.opacity(shown && !closing ? 0.5 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: tapAway)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(confirmingDiscard ? "Keep editing" : "Close")
                if shown {
                    card
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, Self.inset + aboveKeyboard)
                        .opacity(closing ? 0 : 1)
                        .offset(y: closing && !reduceMotion ? 10 : 0)
                        .allowsHitTesting(!closing)
                        .transition(entrance)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .animation(HITMotion.exit(reduceMotion: reduceMotion), value: closing)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            // A turn later: the cover arrives in a transaction without animation, and a change made inside it
            // popped the card in at once instead of letting it rise.
            Task { @MainActor in
                withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) { shown = true }
            }
        }
    }

    /// Rises from the bottom as it fades in (the quick-add card's `cardTransition`).
    private var entrance: AnyTransition {
        let rise: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        return .asymmetric(insertion: rise.animation(HITMotion.enter(reduceMotion: reduceMotion)),
                           removal: .opacity.animation(HITMotion.exit(reduceMotion: reduceMotion)))
    }

    private func tapAway() {
        switch BoardInlineAdd.clickAway(hasContent: content.hasContent, confirmingDiscard: confirmingDiscard) {
        case .close: finish(saved: nil)
        case .askDiscard: withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .keepEditing: keepEditing()
        }
    }

    private func requestClose() {
        switch BoardInlineAdd.close(hasContent: content.hasContent, confirmingDiscard: confirmingDiscard) {
        case .close, .discard: finish(saved: nil)
        case .askDiscard: withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        }
    }

    private func keepEditing() {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
    }

    /// The card holds where it is (the keyboard height it had), drops the keyboard and fades with a small
    /// settle downward; the cover goes once it has.
    private func finish(saved: TaskItem?) {
        guard !closing else { return }
        heldKeyboardHeight = keyboard.height
        // From the action itself, outside any view update (see `SwitchCard.dropKeyboard`).
        SwitchCard.dropKeyboard()
        closing = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.retractDuration + 0.05))
            onFinished(saved)
        }
    }
}
#endif
