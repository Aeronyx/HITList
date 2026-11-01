import SwiftUI
import HITListCore
#if canImport(UIKit)
import UIKit
#endif

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

/// Inter, the app typeface: six static 18 pt cuts from `Resources/Fonts/Inter/static`, registered through
/// Info.plist (`UIAppFonts` on iOS, `ATSApplicationFontsPath` on macOS) and loaded by PostScript name, so
/// `inter(14, .bold)` is "Inter18pt-Bold" at 14 pt. (iOS resolves only a variable font's default instance
/// by name, which is why the variable files stay out of the bundle.) Pass `relativeTo:` for Dynamic Type.
/// SF Symbols keep `.font(.system(size:weight:))`; this is for text.
enum HITFont {
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle? = nil) -> Font {
        let name = postScriptName(weight)
        if let style { return .custom(name, size: size, relativeTo: style) }
        return .custom(name, fixedSize: size)
    }

    /// The bundled cut for a SwiftUI weight. Thin and ultra-light fall back to Light, black to ExtraBold.
    static func postScriptName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return "Inter18pt-Light"
        case .medium: return "Inter18pt-Medium"
        case .semibold: return "Inter18pt-SemiBold"
        case .bold: return "Inter18pt-Bold"
        case .heavy, .black: return "Inter18pt-ExtraBold"
        default: return "Inter18pt-Regular"
        }
    }

    /// iOS navigation bar titles (large and inline) in Inter; SwiftUI has no modifier for them.
    /// Call once at launch. A no-op on macOS, where the window title is the system's.
    static func installPlatformAppearance() {
        #if canImport(UIKit)
        let bars = UINavigationBar.appearance()
        if let large = UIFont(name: postScriptName(.bold), size: 34) { bars.largeTitleTextAttributes = [.font: large] }
        if let inline = UIFont(name: postScriptName(.semibold), size: 17) { bars.titleTextAttributes = [.font: inline] }
        #endif
    }
}

/// Type roles, all Inter. Sizes follow each platform's text styles (iOS Dynamic Type default / macOS),
/// except the fixed ones noted. Views use these instead of `.font(.subheadline)` and friends; the root
/// of each window sets `body`, so unstyled `Text` is Inter too.
enum HITType {
    #if os(macOS)
    static let largeTitle = HITFont.inter(26, .bold, relativeTo: .largeTitle)
    static let title1 = HITFont.inter(22, .bold, relativeTo: .title)
    static let title2 = HITFont.inter(17, .semibold, relativeTo: .title2)
    static let title2Bold = HITFont.inter(17, .bold, relativeTo: .title2)
    static let title3 = HITFont.inter(15, .semibold, relativeTo: .title3)
    static let headline = HITFont.inter(13, .bold, relativeTo: .headline)
    static let body = HITFont.inter(13, .regular, relativeTo: .body)
    static let callout = HITFont.inter(12, .regular, relativeTo: .callout)
    static let calloutMedium = HITFont.inter(12, .medium, relativeTo: .callout)
    static let calloutBold = HITFont.inter(12, .bold, relativeTo: .callout)
    static let subheadline = HITFont.inter(11, .regular, relativeTo: .subheadline)
    static let subheadlineMedium = HITFont.inter(11, .medium, relativeTo: .subheadline)
    static let subheadlineSemibold = HITFont.inter(11, .semibold, relativeTo: .subheadline)
    static let footnote = HITFont.inter(10, .regular, relativeTo: .footnote)
    static let caption = HITFont.inter(10, .regular, relativeTo: .caption)
    static let captionBold = HITFont.inter(10, .bold, relativeTo: .caption)
    static let caption2 = HITFont.inter(10, .medium, relativeTo: .caption2)
    static let caption2Semibold = HITFont.inter(10, .semibold, relativeTo: .caption2)
    /// Button and chip labels.
    static let control = HITFont.inter(13, .medium, relativeTo: .body)
    #else
    static let largeTitle = HITFont.inter(34, .bold, relativeTo: .largeTitle)
    static let title1 = HITFont.inter(28, .bold, relativeTo: .title)
    static let title2 = HITFont.inter(22, .semibold, relativeTo: .title2)
    static let title2Bold = HITFont.inter(22, .bold, relativeTo: .title2)
    static let title3 = HITFont.inter(20, .semibold, relativeTo: .title3)
    static let headline = HITFont.inter(17, .semibold, relativeTo: .headline)
    static let body = HITFont.inter(17, .regular, relativeTo: .body)
    static let callout = HITFont.inter(16, .regular, relativeTo: .callout)
    static let calloutMedium = HITFont.inter(16, .medium, relativeTo: .callout)
    static let calloutBold = HITFont.inter(16, .bold, relativeTo: .callout)
    static let subheadline = HITFont.inter(15, .regular, relativeTo: .subheadline)
    static let subheadlineMedium = HITFont.inter(15, .medium, relativeTo: .subheadline)
    static let subheadlineSemibold = HITFont.inter(15, .semibold, relativeTo: .subheadline)
    static let footnote = HITFont.inter(13, .regular, relativeTo: .footnote)
    static let caption = HITFont.inter(12, .regular, relativeTo: .caption)
    static let captionBold = HITFont.inter(12, .bold, relativeTo: .caption)
    static let caption2 = HITFont.inter(11, .regular, relativeTo: .caption2)
    static let caption2Semibold = HITFont.inter(11, .semibold, relativeTo: .caption2)
    /// Button and chip labels.
    static let control = HITFont.inter(15, .semibold, relativeTo: .subheadline)
    #endif
    /// Sheet and popout titles: fixed semibold 17.
    static let title = HITFont.inter(17, .semibold)
    /// Naming a task in the quick-add card: fixed bold 14 (George's spec).
    /// The quick-add card's title field: one step above `body` (the ratio of 14 pt to 12 pt), bold, so the
    /// task being typed reads larger than the tasks in the list behind it. Fixed size, like `title`.
    #if os(macOS)
    static let taskName = HITFont.inter(15, .bold)
    #else
    static let taskName = HITFont.inter(20, .bold)
    #endif
    /// Section headers above a group of rows or fields.
    static let sectionHeader = caption2Semibold
    /// Filter queries and other code-like text stay in the system mono; Inter has no mono cut.
    static let mono = Font.callout.monospaced()
    static let monoCaption = Font.caption.monospaced()
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

    // Due dates, the same everywhere (rows, chips, Upcoming): today green, tomorrow orange, later
    // purple, overdue red.
    static let dueToday = Color(hex: "#30A46C")
    static let dueTomorrow = Color(hex: "#F5A524")
    static let dueLater = Color(hex: "#B07CF5")
    static let dueOverdue = danger

    /// The colour for a due date; nil (no date) is the secondary text colour.
    static func due(_ date: Date?, hasTime: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> Color {
        guard let date else { return Theme.secondaryText }
        if DueFormatter.isOverdue(date, hasTime: hasTime, isCompleted: false, now: now, calendar: calendar) { return dueOverdue }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return dueToday
        case 1: return dueTomorrow
        default: return dueLater
        }
    }
}

/// Motion. Six named roles, each quick and deliberate; pick by what is happening, never by feel:
///
/// | Role | Curve | For |
/// |---|---|---|
/// | `quick` | 100 ms ease-out | hover and press feedback |
/// | `standard` | 150 ms ease-in-out | state changes (selection, focus, enabled, expanding a row) |
/// | `enter` | 200 ms ease-out | something appearing (a toast, a popout, a revealed field) |
/// | `exit` | 150 ms ease-in | something leaving (a completed row sliding away, a toast expiring) |
/// | `emphasis` | spring, response 0.28, damping 0.8 | the moving parts: toggle thumb, segment highlight |
/// | `celebrate` | the check pop (scale 1.2 in 90 ms, spring settle) | the completion check only |
///
/// Nothing outside `celebrate` bounces or takes longer than 250 ms to arrive (`Role.arrival`). Each role
/// has a `(reduceMotion:)` variant: `quick`/`standard` become instant, `enter`/`exit`/`emphasis` a 100 ms
/// ease with no overshoot, `celebrate` nil (the check just swaps). Pass
/// `@Environment(\.accessibilityReduceMotion)`, or `HITEffects.calmMotion` (which adds the app's Reduce
/// Effects switch) for the larger movements.
enum HITMotion {
    enum Role: String, CaseIterable {
        case quick, standard, enter, exit, emphasis, celebrate

        var animation: Animation {
            switch self {
            case .quick: .easeOut(duration: 0.1)
            case .standard: .easeInOut(duration: 0.15)
            case .enter: .easeOut(duration: 0.2)
            case .exit: .easeIn(duration: 0.15)
            case .emphasis: .spring(response: SpringSpec.emphasis.response, dampingFraction: SpringSpec.emphasis.damping)
            case .celebrate: .spring(response: SpringSpec.celebrate.response, dampingFraction: SpringSpec.celebrate.damping)
            }
        }

        /// The calm stand-in under Reduce Motion (or Reduce Effects, for the larger movements).
        var reducedAnimation: Animation? {
            switch self {
            case .quick, .standard, .celebrate: nil
            case .enter, .exit, .emphasis: .easeOut(duration: 0.1)
            }
        }

        func animation(reduceMotion: Bool) -> Animation? { reduceMotion ? reducedAnimation : animation }

        /// Seconds until the animated value first reaches its target: the curve's duration, or for a
        /// spring the time to its first peak (emphasis arrives at ~233 ms and overshoots 1.5%, under half
        /// a point on a 30 pt move, so it reads as a firm stop rather than a bounce).
        var arrival: TimeInterval {
            switch self {
            case .quick: 0.1
            case .standard: 0.15
            case .enter: 0.2
            case .exit: 0.15
            case .emphasis: SpringSpec.emphasis.timeToPeak
            case .celebrate: Celebrate.totalDuration
            }
        }

        /// What the gallery and the README call it.
        var usage: String {
            switch self {
            case .quick: "100 ms · hover, press"
            case .standard: "150 ms · state changes"
            case .enter: "200 ms ease-out · appearing"
            case .exit: "150 ms ease-in · leaving"
            case .emphasis: "spring 0.28 / 0.8 · thumbs, highlights"
            case .celebrate: "the completion check"
            }
        }
    }

    /// Spring parameters, kept as numbers so tests can check them.
    struct SpringSpec {
        let response: Double
        let damping: Double

        static let emphasis = SpringSpec(response: 0.28, damping: 0.8)
        /// The check's settle after its pop: a little life, still under 15% overshoot.
        static let celebrate = SpringSpec(response: 0.3, damping: 0.62)

        /// Time to the first peak of an underdamped spring: π / ω_d, with ω_0 = 2π / response.
        var timeToPeak: TimeInterval {
            let omega0 = 2 * Double.pi / response
            let omegaD = omega0 * (1 - damping * damping).squareRoot()
            return Double.pi / omegaD
        }

        /// The fraction it overshoots its target by: e^(-ζπ / √(1-ζ²)).
        var overshoot: Double { exp(-damping * Double.pi / (1 - damping * damping).squareRoot()) }
    }

    /// The completion check's pop (`TaskRow`, `TaskPopout`): up to `peakScale` fast, then a spring settle.
    /// Crisper than build 5's (1.15 over 100 ms, then 150 ms back), and a touch bigger.
    enum Celebrate {
        static let peakScale: CGFloat = 1.2
        static let popDuration: TimeInterval = 0.09
        static let settleDuration: TimeInterval = 0.24
        static var totalDuration: TimeInterval { popDuration + settleDuration }
    }

    static let quick = Role.quick.animation
    static let standard = Role.standard.animation
    static let enter = Role.enter.animation
    static let exit = Role.exit.animation
    static let emphasis = Role.emphasis.animation
    static let celebrate = Role.celebrate.animation

    static func quick(reduceMotion: Bool) -> Animation? { Role.quick.animation(reduceMotion: reduceMotion) }
    static func standard(reduceMotion: Bool) -> Animation? { Role.standard.animation(reduceMotion: reduceMotion) }
    static func enter(reduceMotion: Bool) -> Animation? { Role.enter.animation(reduceMotion: reduceMotion) }
    static func exit(reduceMotion: Bool) -> Animation? { Role.exit.animation(reduceMotion: reduceMotion) }
    static func emphasis(reduceMotion: Bool) -> Animation? { Role.emphasis.animation(reduceMotion: reduceMotion) }
    static func celebrate(reduceMotion: Bool) -> Animation? { Role.celebrate.animation(reduceMotion: reduceMotion) }

    /// Build 5's name for `emphasis`, kept so code written against it still compiles.
    @available(*, deprecated, renamed: "emphasis")
    static var spring: Animation { emphasis }
    @available(*, deprecated, renamed: "emphasis(reduceMotion:)")
    static func spring(reduceMotion: Bool) -> Animation? { emphasis(reduceMotion: reduceMotion) }
}

extension Color {
    /// This colour with each sRGB channel scaled by `1 - fraction` (0.08 = 8% darker). Opacity is kept.
    func darkened(by fraction: Double) -> Color {
        let r = resolve(in: EnvironmentValues())
        let k = Float(max(0, 1 - fraction))
        return Color(Color.Resolved(colorSpace: .sRGB, red: r.red * k, green: r.green * k, blue: r.blue * k, opacity: r.opacity))
    }
}
