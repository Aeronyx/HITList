import SwiftUI

/// "Completed ‘Title’ · Undo": the whole pill is the Undo button (George, build 13: "entirely
/// clickable"), 48 pt tall and only as wide as its text. Swiping it down or sideways puts it away without
/// undoing (`CompletionMotion.toastSwipe`). Callers place it: beside the iPhone's "+" (`PopoutHost`),
/// at the bottom-trailing corner of a Mac or iPad list (`completionToast`). Insert it with
/// `.transition(CompletionMotion.toastTransition(reduceMotion:))` so it enters with `HITMotion.enter` and
/// leaves with `exit`.
struct CompletionToast: View {
    /// Taller than build 13's 40 pt, so it reads as a button rather than a caption.
    static let height: CGFloat = 48
    /// Mac and iPad: content-sized up to this (about 60% of a typical list column); longer titles
    /// truncate in the middle. On the iPhone the space left of the "+" bounds it.
    static let panelMaxWidth: CGFloat = 360

    let message: String
    let onUndo: () -> Void
    /// A swipe put the toast away; the owner clears it without undoing.
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the finger has dragged the pill.
    @State private var drag: CGSize = .zero

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text(message)
                    .foregroundStyle(HITColor.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·").foregroundStyle(Theme.secondaryText)
                Text("Undo")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .layoutPriority(1)
            }
            .font(HITType.subheadline)
            .padding(.horizontal, 18)
            .frame(height: Self.height)
            .background(Theme.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator))
            .contentShape(Capsule())
        }
        .buttonStyle(ToastPressStyle())
        #if os(macOS)
        .keyboardShortcut("z", modifiers: .command)
        .help("Undo (⌘Z)")
        #endif
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .offset(drag)
        .opacity(1 - min(1, hypot(drag.width, drag.height) / 160) * 0.6)
        // High priority: a drag takes over from the button once it moves, a tap stays an Undo.
        .highPriorityGesture(swipe)
        .accessibilityLabel("\(message), Undo")
        .accessibilityHint("Undoes the completion")
        .accessibilityAction(named: "Dismiss", onDismiss)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Down and sideways follow the finger; up only gives a little.
                let t = value.translation
                drag = CGSize(width: t.width, height: t.height > 0 ? t.height : t.height / 4)
            }
            .onEnded { value in
                switch CompletionMotion.toastSwipe(translation: value.translation, predicted: value.predictedEndTranslation) {
                case .stay:
                    withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { drag = .zero }
                case .away(let fling):
                    withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) {
                        drag = fling
                        onDismiss()
                    }
                }
            }
    }
}

/// The pill darkens and gives a little while pressed, like the "+".
private struct ToastPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
