import SwiftUI

/// The completion sequence's timing in one place, each step on its `HITMotion` role:
///
/// 1. the check pops (`celebrate`, `hitCelebratePop`) and swaps to a filled check;
/// 2. the strike sweeps across the title left to right while the title dims (200 ms ease-out);
/// 3. the row flashes the accent (`completionRowBackground`), then slides a little to the trailing edge
///    as the list fades it (`exit`, 150 ms ease-in);
/// 4. the undo toast rises in with `enter` and leaves with `exit`.
///
/// Reduce Motion (and Reduce Effects, for the pop and the slide) keeps the swap, the strike as a fade and
/// the toast as a fade, and drops the pop and the slide.
enum CompletionMotion {
    /// The strike sweep and the title dimming with it. Stays at 200 ms: long enough to read as a stroke.
    static let strikeDuration: TimeInterval = 0.2
    static let strike = Animation.easeOut(duration: strikeDuration)

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
}
