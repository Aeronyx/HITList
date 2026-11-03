import SwiftUI

/// The completion sequence's timing in one place, each step on its `HITMotion` role:
///
/// 1. the check pops (`celebrate`, `hitCelebratePop`) and swaps to a filled check;
/// 2. the strike sweeps across the title left to right while the title dims (200 ms ease-out);
/// 3. the row flashes the accent (`completionRowBackground`), then slides a little to the trailing edge
///    as the list fades it (`exit`, 150 ms ease-in);
/// 4. the undo toast rises in with `enter` and leaves with `exit`, or is swiped away (`toastSwipe`).
///
/// Reduce Motion (and Reduce Effects, for the pop and the slide) keeps the swap, the strike as a fade and
/// the toast as a fade, and drops the pop and the slide.
enum CompletionMotion {
    /// The strike sweep and the title dimming with it. Stays at 200 ms: long enough to read as a stroke.
    static let strikeDuration: TimeInterval = 0.2
    static let strike = Animation.easeOut(duration: strikeDuration)

    /// How long a checked row stays before it leaves: long enough for the check's pop (`hitCelebratePop`,
    /// 330 ms) and the strike (200 ms) to land, no longer (George, build 11: "snappier"; it was 600 ms).
    static let hold: Duration = .milliseconds(380)
    /// After the row starts collapsing, how long until the list drops it.
    static let collapseSettle: Duration = .milliseconds(150)

    /// How far a completed row slides toward the trailing edge while it fades out.
    static let slideDistance: CGFloat = 24
    static func slideAway(calmMotion: Bool) -> Animation? { HITMotion.exit(reduceMotion: calmMotion) }

    /// The undo toast: rises from the bottom edge with `enter`, fades down with `exit`; a plain fade under
    /// Reduce Motion. The animations ride on the transition, so it looks the same whatever animation the
    /// caller wraps the change in.
    ///
    ///     if toast.isVisible {
    ///         CompletionToast(message: toast.message, onUndo: undo)
    ///             .transition(CompletionMotion.toastTransition(reduceMotion: reduceMotion))
    ///     }
    static func toastTransition(reduceMotion: Bool) -> AnyTransition {
        let insertion: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        let removal: AnyTransition = reduceMotion ? .opacity : .offset(y: 12).combined(with: .opacity)
        return .asymmetric(insertion: insertion.animation(HITMotion.enter(reduceMotion: reduceMotion)),
                           removal: removal.animation(HITMotion.exit(reduceMotion: reduceMotion)))
    }

    /// What a drag on the undo toast ends in: back in place, or away (no undo) to `fling`, the offset it
    /// leaves toward on `exit`.
    enum ToastSwipe: Equatable {
        case stay
        case away(fling: CGSize)
    }

    /// Down past `swipeDistance`, or sideways past twice that, puts the toast away; so does a short
    /// flick whose predicted end gets there. Up never does (the toast has nowhere to go but the list).
    static let swipeDistance: CGFloat = 28
    static let flingDistance: CGFloat = 120

    static func toastSwipe(translation t: CGSize, predicted p: CGSize) -> ToastSwipe {
        let side = max(abs(t.width), abs(p.width))
        let down = max(t.height, p.height)
        if side >= swipeDistance * 2, side >= down {
            let sign: CGFloat = (abs(p.width) >= abs(t.width) ? p.width : t.width) < 0 ? -1 : 1
            return .away(fling: CGSize(width: sign * max(flingDistance * 2, side), height: max(0, t.height)))
        }
        if down >= swipeDistance {
            return .away(fling: CGSize(width: t.width, height: max(flingDistance, down)))
        }
        return .stay
    }
}
