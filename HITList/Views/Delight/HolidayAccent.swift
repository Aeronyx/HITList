import SwiftUI
import HITListCore

/// The quiet theme touch during a holiday's window (brief 44): a tiny seasonal glyph tucked against a
/// control — a snowflake at Christmas, an orange moon at Halloween. Off with Settings → Delight →
/// Holiday touches; nothing at all on an ordinary day.
///
///     plus.holidayAccent(size: 8, outside: false)     // inside the "+" oval's top-trailing corner
///     Text("Today").holidayAccent(size: 11)          // just past the title's top-trailing corner
enum HolidayAccent {
    /// The SF Symbol for each holiday's accent.
    static func symbol(for holiday: Holiday) -> String {
        switch holiday {
        case .christmas: "snowflake"
        case .newYear: "sparkle"
        case .valentines: "heart.fill"
        case .stPatricks: "leaf.fill"
        case .independenceDay: "star.fill"
        case .halloween: "moon.fill"
        case .thanksgiving, .autumnEquinox: "leaf.fill"
        case .springEquinox: "camera.macro"
        case .summerSolstice: "sun.max.fill"
        }
    }

    /// Its colour: the burst's first colour, so the accent and the completions agree.
    static func tint(for holiday: Holiday) -> Color {
        switch holiday {
        case .stPatricks: Color(hex: "#3FB56B")
        case .halloween: Color(hex: "#F28C28")
        case .christmas: Color(hex: "#DDEBFF")
        default: holiday.burst.palette[0]
        }
    }

    /// The holiday whose accent shows now, if Holiday touches is on.
    static func current(at date: Date = .now, defaults: UserDefaults = AppGroup.defaults,
                        launch: DelightLaunchOptions = .current) -> Holiday? {
        guard HolidayDelight.holidayTouchesEnabled(in: defaults) else { return nil }
        return HolidayDelight.holiday(at: date, launch: launch)
    }
}

extension View {
    /// Overlays the current holiday's tiny glyph at `alignment`: just past the view's edge in the holiday's
    /// colour (`outside`), or tucked inside its corner in the accent's text colour, for a control filled with
    /// the accent such as the "+" oval (the holiday colours wash out on it).
    func holidayAccent(alignment: Alignment = .topTrailing, size: CGFloat = 9, outside: Bool = true) -> some View {
        modifier(HolidayAccentModifier(alignment: alignment, size: size, outside: outside))
    }
}

private struct HolidayAccentModifier: ViewModifier {
    let alignment: Alignment
    let size: CGFloat
    let outside: Bool
    @AppStorage(Preferences.holidayTouches, store: AppGroup.defaults) private var touches = true

    func body(content: Content) -> some View {
        // Re-read when the toggle changes; the day itself changes rarely enough to catch on the next render.
        let holiday = touches ? HolidayAccent.current() : nil
        content.overlay(alignment: alignment) {
            if let holiday {
                Image(systemName: HolidayAccent.symbol(for: holiday))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(outside ? HolidayAccent.tint(for: holiday) : HITColor.onAccent.opacity(0.75))
                    .offset(offset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Outside: most of the glyph past the corner. Inside: a little in from it.
    private var offset: CGSize {
        // Inside, clear of a capsule's rounded end.
        let dx = outside ? size * 0.9 : -size * 1.9, dy = outside ? size * 0.55 : -size * 1.0
        let x: CGFloat = alignment.horizontal == .trailing ? dx : alignment.horizontal == .leading ? -dx : 0
        let y: CGFloat = alignment.vertical == .top ? -dy : alignment.vertical == .bottom ? dy : 0
        return CGSize(width: x, height: y)
    }
}
