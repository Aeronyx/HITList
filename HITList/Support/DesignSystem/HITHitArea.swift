import SwiftUI

extension View {
    /// Grows what takes a press, and VoiceOver's frame, by `horizontal` and `vertical` points on each side, into
    /// empty space around a small control (brief 94: the audit's targets too small). Put it on the control's label and
    /// `hitOutsetLayout` with the same values on the control: the layout, and so everything on screen, stays where it
    /// was. Never grow into a neighbour that takes presses itself.
    ///
    ///     Button(action: back) { Image(systemName: "chevron.left").hitOutset(horizontal: 12, vertical: 6) }
    ///         .hitOutsetLayout(horizontal: 12, vertical: 6)
    func hitOutset(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .contentShape(Rectangle())
    }

    /// Takes `hitOutset`'s room back out of the layout; on the control, outside its label.
    func hitOutsetLayout(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
    }
}

/// How large a control's hit frame must be, and the `hitOutset` that gets a small one there.
enum HITHitTarget {
    /// A Mac control's hit frame is at least this on each side (brief 94's audit; brief 99: the editor's check circle
    /// was 22 × 24).
    static let macMinimum: CGFloat = 24

    /// The outset on each side that grows `length` to at least `minimum`; 0 when it is there already.
    static func outset(for length: CGFloat, minimum: CGFloat = macMinimum) -> CGFloat { max(0, (minimum - length) / 2) }
}
