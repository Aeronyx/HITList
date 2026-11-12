import CoreGraphics

/// Where a picker card goes, relative to the chip that opened it. Pure, so tests can pin it.
///
/// The card's leading edge lines up with the chip's, a few points below it; if the card would run past
/// the bottom of `bounds` it goes above the chip instead. A card too tall for either goes beside the chip,
/// after it or else before it, level with it and slid up only as far as it must (brief 65: the editor's
/// Reminder card in a 721 pt window was slid over the pill that opened it). Only with no room on any side
/// does it take the roomier of above and below and slide back inside `bounds` (covering part of the chip
/// rather than leaving the window). Horizontally it is clamped so it never crosses either side of `bounds`.
enum PickerPlacement {
    /// Which side of the chip the card ended up on.
    enum Edge: Equatable { case below, above, trailing, leading, overlapping }

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

        var x = clamp(anchor.minX, inner.minX, inner.maxX - width)

        let below = anchor.maxY + gap
        let above = anchor.minY - gap - height
        let after = anchor.maxX + gap
        let before = anchor.minX - gap - width
        let y: CGFloat
        let edge: Edge
        if below + height <= inner.maxY {
            y = below
            edge = .below
        } else if above >= inner.minY {
            y = above
            edge = .above
        } else if after >= inner.minX, after + width <= inner.maxX {
            x = after
            y = anchor.minY
            edge = .trailing
        } else if before >= inner.minX, before + width <= inner.maxX {
            x = before
            y = anchor.minY
            edge = .leading
        } else {
            // Neither side fits: use the roomier one and slide inside.
            let roomBelow = inner.maxY - anchor.maxY
            let roomAbove = anchor.minY - inner.minY
            y = roomBelow >= roomAbove ? inner.maxY - height : inner.minY
            edge = .overlapping
        }
        return (CGRect(x: clamp(x, inner.minX, inner.maxX - width), y: clamp(y, inner.minY, inner.maxY - height),
                       width: width, height: height), edge)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, max(low, high)))
    }
}

/// iPhone and iPad: which side of its chip a picker card opens on, and how tall it may be there (brief 107). Keyed on
/// the room there is, never on the device: pure, so tests pin it against the phones' screens, the iPhone Duo's short
/// outer display (376 × 678 pt of content beside the system's bar column) and its inner display held on its side
/// (951 × 669, regular width) among them.
///
/// The card is a system popover. Left to itself the system took the roomier side of the chip, as this does, but put a
/// card too tall for either side beside its chip, past the screen's edge (the editor's Reminder card on the Duo started
/// 12 pt left of the display), and chose the side before a chip moved (quick add's Date card: chosen with the keyboard
/// up, it stayed below the chip after the card dropped with the keyboard, 102 pt tall, its calendar off the display).
/// So the side is ours: the roomier of above and below for where the chip will be (`settle`), never beside (a phone is
/// not wide enough for a 280–360 pt card beside a chip). `room` is the height the card has there; a taller card takes
/// its short layout and scrolls inside rather than being cut (`pickerRoom`).
enum PhonePickerPlacement {
    enum Edge: Equatable { case below, above }

    struct Result: Equatable {
        var edge: Edge
        /// The card's tallest on that side, its arrow and margins taken off.
        var room: CGFloat
        /// The card's widest: the screen's width inside its safe area, `margin` off each side (brief 114: on the iPhone
        /// Duo's outer display, 376 pt beside the bar column, the 360 pt Reminder card ran 6 pt into the column).
        var width: CGFloat? = nil
    }

    /// What the system's popover takes between the chip and the card: its arrow (13 pt on iOS 27) and a hairline.
    static let arrow: CGFloat = 14
    /// The popover keeps this far from the screen's safe area.
    static let margin: CGFloat = 10
    /// And this far (plus `margin`) from a screen edge with no safe area: on the iPhone Duo's outer display, which has
    /// none above or below, the system kept its popovers 25 pt from the top and the foot (measured).
    static let screenEdge: CGFloat = 15

    /// Where a card may go: the screen inside its safe area, and never nearer its top or foot than `screenEdge`.
    static func area(in screen: CGRect, top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) -> CGRect {
        let top = max(top, screenEdge)
        let bottom = max(bottom, screenEdge)
        return CGRect(x: screen.minX + leading, y: screen.minY + top,
                      width: max(0, screen.width - leading - trailing),
                      height: max(0, screen.height - top - bottom))
    }

    /// `anchor`: the chip; `settle`: how far it will move down before the card is up (quick add's card drops with the
    /// keyboard); `area`: the screen inside its safe area (on the Duo's outer display, without the bar column), in the
    /// same coordinates.
    static func place(anchor: CGRect, area: CGRect, settle: CGFloat = 0) -> Result {
        let chip = anchor.offsetBy(dx: 0, dy: settle)
        let below = max(0, area.maxY - chip.maxY - arrow - margin)
        let above = max(0, chip.minY - area.minY - arrow - margin)
        let width = max(0, area.width - 2 * margin)
        return below >= above ? Result(edge: .below, room: below, width: width)
                              : Result(edge: .above, room: above, width: width)
    }
}
