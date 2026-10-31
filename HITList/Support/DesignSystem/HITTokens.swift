import SwiftUI
import HITListCore

// The design system's shared numbers. Components in this folder read these instead of inventing their
// own; views outside it should too. Colours stay in `Theme` and `Priority.color`; this file only adds
// the few the controls need. See README.md in this folder for which component to use where.

/// Spacing scale. Use these for padding and stack spacing; anything else is a one-off that needs a reason.
enum HITSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Corner radii. `pill` is large enough to round any control into a capsule.
enum HITRadius {
    static let chip: CGFloat = 6
    static let field: CGFloat = 10
    static let card: CGFloat = 14
    static let pill: CGFloat = 999
}

/// Type roles. Sizes follow the platform (Dynamic Type on iOS) except `title`, fixed at semibold 17.
enum HITType {
    /// Sheet and popout titles.
    static let title = Font.system(size: 17, weight: .semibold)
    /// Field text, row titles.
    static let body = Font.body
    /// Button and chip labels.
    #if os(macOS)
    static let control = Font.system(size: 13, weight: .medium)
    #else
    static let control = Font.subheadline.weight(.semibold)
    #endif
    /// Row values, section headers, helper text.
    static let caption = Font.caption
    /// Section headers above a group of rows or fields.
    static let sectionHeader = Font.caption.weight(.semibold)
    /// Filter queries and other code-like text.
    static let mono = Font.callout.monospaced()
}

/// Colours the controls need beyond `Theme`.
enum HITColor {
    /// Text and icons on an accent fill: near-black, so the blue reads as a light surface.
    static let onAccent = Color(hex: "#0B0E14")
    /// Primary text on slate.
    static let text = Color(hex: "#E8ECF3")
    /// Toggle track when off (the same slate as `Theme.separator`).
    static let trackOff = Color(hex: "#303948")
    /// Toggle thumb.
    static let thumb = Color(hex: "#F4F6FA")
    /// Destructive actions and invalid input: the P1 red.
    static let danger = Priority.p1.color
}

/// Motion. Every control animates state changes with `standard` (150 ms ease) and moving parts
/// (toggle thumb, segment highlight) with `spring`; both collapse to nil under Reduce Motion.
enum HITMotion {
    static let standard = Animation.easeInOut(duration: 0.15)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.72)

    static func standard(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : standard }
    /// Reduce Motion keeps a quick fade instead of sliding.
    static func spring(reduceMotion: Bool) -> Animation? { reduceMotion ? .linear(duration: 0.1) : spring }
}

extension Color {
    /// This colour with each sRGB channel scaled by `1 - fraction` (0.08 = 8% darker). Opacity is kept.
    func darkened(by fraction: Double) -> Color {
        let r = resolve(in: EnvironmentValues())
        let k = Float(max(0, 1 - fraction))
        return Color(Color.Resolved(colorSpace: .sRGB, red: r.red * k, green: r.green * k, blue: r.blue * k, opacity: r.opacity))
    }
}
