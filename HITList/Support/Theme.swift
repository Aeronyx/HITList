import SwiftUI
import Observation

/// One dark palette: the eight colours every list, form, sheet and control draws from. HITList is dark
/// only; a theme changes the greys' temperature and the accent, never the brightness. Due colours and
/// priority colours are the same in every palette.
struct ThemePalette: Identifiable, Equatable {
    /// Stored at `Preferences.theme`; keep these stable once shipped.
    let id: String
    let name: String
    let hex: Hexes

    let background: Color
    let surface: Color
    let elevated: Color
    let separator: Color
    let accent: Color
    let secondaryText: Color
    /// Primary text on any of the three surfaces.
    let text: Color
    /// Text and icons on an accent fill.
    let onAccent: Color

    struct Hexes: Equatable {
        var background, surface, elevated, separator, accent, secondaryText, text, onAccent: String

        /// In declaration order, for tests and swatches.
        var all: [String] { [background, surface, elevated, separator, accent, secondaryText, text, onAccent] }
    }

    init(id: String, name: String, hex: Hexes) {
        self.id = id
        self.name = name
        self.hex = hex
        background = Color(hex: hex.background)
        surface = Color(hex: hex.surface)
        elevated = Color(hex: hex.elevated)
        separator = Color(hex: hex.separator)
        accent = Color(hex: hex.accent)
        secondaryText = Color(hex: hex.secondaryText)
        text = Color(hex: hex.text)
        onAccent = Color(hex: hex.onAccent)
    }

    /// True when the accent is light enough that white on it disappears (Graphite's off-white): controls
    /// that put a white part on the accent (the toggle thumb) use `onAccent` instead.
    var hasLightAccent: Bool {
        let r = accent.resolve(in: EnvironmentValues())
        let luminance = 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722 * Double(r.linearBlue)
        return luminance > 0.6
    }

    /// The eight colours, in the order of `Hexes.all`.
    var colors: [Color] { [background, surface, elevated, separator, accent, secondaryText, text, onAccent] }

    static func == (a: ThemePalette, b: ThemePalette) -> Bool { a.id == b.id && a.hex == b.hex }

    /// The original: blue-grey slate with a soft blue accent. The default.
    static let slate = ThemePalette(id: "slate", name: "Slate", hex: Hexes(
        background: "#14181F", surface: "#1B2029", elevated: "#242B38", separator: "#303948",
        accent: "#6C9EFF", secondaryText: "#9AA4B8", text: "#E8ECF3", onAccent: "#0B0E14"))

    /// Neutral greys with a warm off-white accent (dark text on it).
    static let graphite = ThemePalette(id: "graphite", name: "Graphite", hex: Hexes(
        background: "#161616", surface: "#1D1D1E", elevated: "#262627", separator: "#343436",
        accent: "#E6E1D6", secondaryText: "#A3A3A6", text: "#EDEDED", onAccent: "#141414"))

    /// Blue-black with a cyan accent.
    static let midnight = ThemePalette(id: "midnight", name: "Midnight", hex: Hexes(
        background: "#0B0F1A", surface: "#111727", elevated: "#1A2236", separator: "#273149",
        accent: "#4FD1E8", secondaryText: "#93A0BC", text: "#E6ECF7", onAccent: "#04121A"))

    /// Green-black with a soft green accent.
    static let moss = ThemePalette(id: "moss", name: "Moss", hex: Hexes(
        background: "#111612", surface: "#171E19", elevated: "#202A22", separator: "#2D3A30",
        accent: "#8FD694", secondaryText: "#9CAE9F", text: "#E6EFE7", onAccent: "#0B140D"))

    /// Cool Scandinavian greys with an ice-blue accent (after the Nord palette).
    static let nord = ThemePalette(id: "nord", name: "Nord", hex: Hexes(
        background: "#232831", surface: "#2E3440", elevated: "#3B4252", separator: "#4C566A",
        accent: "#88C0D0", secondaryText: "#AEB8CA", text: "#ECEFF4", onAccent: "#1B222C"))

    /// Deep indigo night with a periwinkle accent (after Tokyo Night).
    static let tokyo = ThemePalette(id: "tokyo", name: "Tokyo Night", hex: Hexes(
        background: "#16161E", surface: "#1A1B26", elevated: "#24283B", separator: "#3B4261",
        accent: "#7AA2F7", secondaryText: "#9AA5CE", text: "#C0CAF5", onAccent: "#0F1018"))

    /// Warm violet-black with a mauve accent (after Catppuccin Mocha).
    static let mocha = ThemePalette(id: "mocha", name: "Mocha", hex: Hexes(
        background: "#181825", surface: "#1E1E2E", elevated: "#313244", separator: "#45475A",
        accent: "#CBA6F7", secondaryText: "#A6ADC8", text: "#CDD6F4", onAccent: "#11111B"))

    /// Dusky plum with a rose accent (after Rosé Pine).
    static let rose = ThemePalette(id: "rose", name: "Rosé", hex: Hexes(
        background: "#191724", surface: "#1F1D2E", elevated: "#26233A", separator: "#403D52",
        accent: "#EBBCBA", secondaryText: "#9A95B4", text: "#E0DEF4", onAccent: "#14121E"))

    static let all: [ThemePalette] = [.slate, .graphite, .midnight, .moss, .nord, .tokyo, .mocha, .rose]

    /// The palette stored under `id`; Slate for nil or anything unknown (a theme from a newer build).
    static func named(_ id: String?) -> ThemePalette {
        all.first { $0.id == id } ?? .slate
    }
}

/// The palette in use. `Theme`'s colours read `ThemeStore.shared.palette`, and because the store is
/// `@Observable`, every view whose body read a `Theme` colour redraws when it changes: switching applies
/// live in every window (the Mac Settings window included) without restarting or re-identifying the
/// root view. Persists to `Preferences.theme` in `AppGroup.defaults`.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var palette: ThemePalette
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        palette = ThemePalette.named(defaults.string(forKey: Preferences.theme))
    }

    /// Switches to `palette` and saves the choice (`persist: false` only switches, for tests and previews).
    func select(_ palette: ThemePalette, persist: Bool = true) {
        if persist { defaults.set(palette.id, forKey: Preferences.theme) }
        if palette != self.palette { self.palette = palette }
    }
}

/// The current dark palette's colours. The app is dark-only; every list, form and sheet draws from here.
/// Computed from `ThemeStore.shared`, so call sites never change when the theme does.
enum Theme {
    static var palette: ThemePalette { ThemeStore.shared.palette }

    static var background: Color { palette.background }
    static var surface: Color { palette.surface }
    static var elevated: Color { palette.elevated }
    static var separator: Color { palette.separator }
    static var accent: Color { palette.accent }
    static var secondaryText: Color { palette.secondaryText }
}

extension View {
    /// Replaces a List/Form's system background with the theme's background.
    func slateList() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background)
    }

    /// Theme row cards on iOS; macOS keeps its native inset/sidebar row rendering.
    @ViewBuilder
    func slateRow() -> some View {
        #if os(iOS)
        self.listRowBackground(Theme.elevated)
        #else
        self
        #endif
    }

    /// Dark themed chrome for sheets on both platforms.
    func slateSheet() -> some View {
        self.preferredColorScheme(.dark).tint(Theme.accent).presentationBackground(Theme.background)
    }
}
