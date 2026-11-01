import SwiftUI

/// Keys for user preferences in `AppGroup.defaults`, so Settings (which writes them) and the views that
/// read them agree on the name and the default. Read with `@AppStorage(Preferences.startTab, store:
/// AppGroup.defaults)` or `Preferences.value(_:)`. Each feature adds its keys in an `extension Preferences`
/// in its own file; keep the names stable once a build has shipped them.
enum Preferences {
    /// iPhone: the tab shown at launch (`MobileTab.rawValue`); default "today".
    static let startTab = "pref.startTab"
    static let startTabDefault = "today"

    /// Minutes before a timed task's due time that its reminder fires when the task has no `!` offset
    /// of its own; 0 = at the due time.
    static let defaultReminderOffsetMinutes = "pref.defaultReminderOffsetMinutes"
    static let defaultReminderOffsetDefault = 0

    /// The dark palette in use (`Theme` reads it); "slate" is the original.
    static let theme = "pref.theme"
    static let themeDefault = "slate"

    /// True turns off blur, glass and the larger motion effects everywhere (also implied by the system's
    /// Reduce Transparency / Reduce Motion).
    static let reduceEffects = "pref.reduceEffects"

    static func value<T>(_ key: String, default fallback: T) -> T {
        AppGroup.defaults.object(forKey: key) as? T ?? fallback
    }
}
