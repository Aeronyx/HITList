import CoreGraphics

/// Where a picker card goes, relative to the chip that opened it. Pure, so tests can pin it.
///
/// The card's leading edge lines up with the chip's, a few points below it; if the card would run past
/// the bottom of `bounds` it goes above the chip instead; if neither side has room, it takes the side
/// with more room and slides back inside `bounds` (covering part of the chip rather than leaving the
/// window). Horizontally it is clamped so it never crosses either side of `bounds`.
enum PickerPlacement {
    /// Which side of the chip the card ended up on.
    enum Edge: Equatable { case below, above, overlapping }

    /// Space between the chip and the card.
    static let gap: CGFloat = 6
    /// The card keeps at least this far from the edges of `bounds`.
    static let margin: CGFloat = 8

    /// The card's frame, in the same coordinate space as `anchor` and `bounds` (y grows downwards).
    static func frame(anchor: CGRect, cardSize: CGSize, bounds: CGRect,
                      gap: CGFloat = gap, margin: CGFloat = margin) -> CGRect {
        place(anchor: anchor, cardSize: cardSize, bounds: bounds, gap: gap, margin: margin).frame
    }

    /// The frame and which side it is on.
    static func place(anchor: CGRect, cardSize: CGSize, bounds: CGRect,
                      gap: CGFloat = gap, margin: CGFloat = margin) -> (frame: CGRect, edge: Edge) {
        let inner = bounds.insetBy(dx: min(margin, bounds.width / 2), dy: min(margin, bounds.height / 2))
        let width = min(cardSize.width, inner.width)
        let height = min(cardSize.height, inner.height)

        let x = clamp(anchor.minX, inner.minX, inner.maxX - width)

        let below = anchor.maxY + gap
        let above = anchor.minY - gap - height
        let y: CGFloat
        let edge: Edge
        if below + height <= inner.maxY {
            y = below
            edge = .below
        } else if above >= inner.minY {
            y = above
            edge = .above
        } else {
            // Neither side fits: use the roomier one and slide inside.
            let roomBelow = inner.maxY - anchor.maxY
            let roomAbove = anchor.minY - inner.minY
            y = roomBelow >= roomAbove ? inner.maxY - height : inner.minY
            edge = .overlapping
        }
        return (CGRect(x: x, y: clamp(y, inner.minY, inner.maxY - height), width: width, height: height), edge)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, max(low, high)))
    }
}
