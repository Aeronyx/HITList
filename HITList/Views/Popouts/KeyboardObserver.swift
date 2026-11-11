#if os(iOS)
import SwiftUI
import UIKit
import Observation

/// The on-screen keyboard's height, from `keyboardWillChangeFrame`, for views that place themselves
/// above the keyboard by hand instead of through the keyboard safe area. `PopoutHost` uses it for the
/// iPhone quick-add card and `FloatingSwitchCard` for the Flipboard's: the card follows the keyboard up and
/// down on the keyboard's own curve (`Follow`), and when the card is put away it keeps the height it had, so
/// it fades in place while the keyboard drops instead of riding the shrinking safe area down (which stuttered).
@MainActor
@Observable
final class KeyboardObserver {
    static let shared = KeyboardObserver()

    /// The keyboard's height above the bottom of the screen; 0 when it is hidden.
    private(set) var height: CGFloat = 0
    /// The height the latest notification asked for, which `height` reaches a moment later.
    @ObservationIgnored private var target: CGFloat = 0

    /// The keyboard's own curve over `duration` (the notification's, 0.383 s on iOS 26 and 27).
    static func follow(duration: TimeInterval) -> Animation { Animation(Follow(duration: duration)) }

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
            MainActor.assumeIsolated { self?.update(endFrame: end, duration: duration) }
        }
    }

    private func update(endFrame: CGRect?, duration: Double?) {
        guard let endFrame else { return }
        let screen = UIScreen.main.bounds
        let visible = max(0, screen.maxY - endFrame.minY)
        // A hidden keyboard reports a frame at or below the screen's bottom.
        let newHeight = endFrame.minY >= screen.maxY ? 0 : visible
        guard newHeight != target else { return }
        target = newHeight
        let animation = Self.follow(duration: Follow.duration(fromNotification: duration))
        // The notification arrives inside UIKit's own keyboard animation, and a SwiftUI change made there was
        // drawn wrongly (brief 75): the card vanished for six frames, flew back up from below and only then came
        // down, or jumped up before coming down. Changed on the next turn of the run loop, outside that block, it
        // moves on its own animation, a few frames behind the keyboard and on its curve. (The spring this used until
        // round 17 arrived ~350 ms after the keyboard.)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.target == newHeight else { return }
            withAnimation(animation) { self.height = newHeight }
        }
    }

    /// Tests and previews: set the height without a notification.
    func set(height: CGFloat) {
        target = height
        self.height = height
    }

    /// The keyboard's motion, measured frame by frame on the iPhone 17 simulator (iOS 27.0) in round 17: it is no
    /// spring but a plain ease-out, `1 - e^(-t/τ)` with τ a fifth of the notification's duration (77 ms of its
    /// 383 ms; fitted within 0.08 over twelve frames, where a critically damped spring was four times further
    /// off). It starts at full speed, is 90% of the way there in about 170 ms and has settled when the
    /// duration ends.
    struct Follow: CustomAnimation {
        var duration: TimeInterval

        /// The fraction of the way at `time` into a `duration`-long move; exactly 1 at its end.
        static func fraction(at time: TimeInterval, duration: TimeInterval) -> Double {
            guard duration > 0 else { return 1 }
            let t = min(max(time / duration, 0), 1)
            return (1 - exp(-5 * t)) / (1 - exp(-5))
        }

        /// The notification's duration, or the keyboard's usual one when it gives none (or zero, as a keyboard
        /// that is only changing its input view does).
        static func duration(fromNotification value: Double?) -> TimeInterval {
            guard let value, value > 0 else { return 0.383 }
            return value
        }

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            guard time < duration else { return nil }
            return value.scaled(by: Self.fraction(at: time, duration: duration))
        }
    }
}
#endif
