import Foundation

// What the design system's shared files (Theme, HITTokens, Formatting, HITCalendar; see project.yml) expect from the
// app, in the form a widget extension has it. The extension reads the widget snapshot and nothing else.

/// The App Group, as the app's `AppGroup` (HITList/Support/AppGroup.swift) names it. The id comes from the
/// extension's Info.plist (`HITListAppGroup`, set per platform in project.yml), and `WidgetAppGroupTests` checks it
/// is the app's own on each platform.
enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "HITListAppGroup") as? String ?? ""

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// The shared files read settings through this (`ThemeStore`, `Preferences.value`). A widget takes its settings
    /// from the snapshot (its theme, the week's first day), so here it is the extension's own empty defaults, never
    /// the app's: nothing in the extension reads or writes George's settings.
    static let defaults = UserDefaults.standard
}

/// HITTokens' row type asks where the iPhone's island stands; a widget has no island.
enum IslandPlacement: Equatable {
    case bottom
    var isSide: Bool { false }
}
