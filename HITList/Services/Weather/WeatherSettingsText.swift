import Foundation

/// The Weather row's words (Settings → Extras), apart from the row so tests can read them and so the row's layout
/// and its words can change separately (round 19: brief 83 owns the words, brief 86 the layout).
enum WeatherSettingsText {
    static let about = "Your companion dresses for the weather where you are."

    static func subtitle(for access: WeatherAccess) -> String {
        switch access {
        case .denied: "HITList isn't allowed to use your location. Allow it below."
        case .restricted: "Location is restricted on this device."
        case .notDetermined, .allowed: about
        }
    }

    /// Where the switch is, under the system's settings (the row above it opens them).
    static let settingsPath = "Privacy & Security → Location Services → HITList"
}
