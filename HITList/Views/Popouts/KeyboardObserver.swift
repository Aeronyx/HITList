#if os(iOS)
import SwiftUI
import UIKit
import Observation

/// The on-screen keyboard's height, from `keyboardWillChangeFrame`, for views that place themselves
/// above the keyboard by hand instead of through the keyboard safe area. `PopoutHost` uses it for the
/// iPhone quick-add card: the card follows the keyboard up with the keyboard's own motion, and when the
/// card is put away it keeps the height it had, so it fades in place while the keyboard drops instead
/// of riding the shrinking safe area down (which stuttered).
@MainActor
@Observable
final class KeyboardObserver {
    static let shared = KeyboardObserver()

    /// The keyboard's height above the bottom of the screen; 0 when it is hidden.
    private(set) var height: CGFloat = 0

    /// Close to UIKit's keyboard curve, for moving along with it.
    static let motion: Animation = .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            MainActor.assumeIsolated { self?.update(endFrame: end) }
        }
    }

    private func update(endFrame: CGRect?) {
        guard let endFrame else { return }
        let screen = UIScreen.main.bounds
        let visible = max(0, screen.maxY - endFrame.minY)
        // A hidden keyboard reports a frame at or below the screen's bottom.
        let newHeight = endFrame.minY >= screen.maxY ? 0 : visible
        guard newHeight != height else { return }
        withAnimation(Self.motion) { height = newHeight }
    }

    /// Tests and previews: set the height without a notification.
    func set(height: CGFloat) { self.height = height }
}
#endif
