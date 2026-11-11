import Foundation

/// The Weather row's words (Settings → Extras), apart from the row so tests can read them and so the row's layout
/// and its words can change separately (round 19: brief 83 owns the words, brief 86 the layout).
enum WeatherSettingsText {
    static let about = "Your companion dresses for the weather and keeps the hours of where you are."

    static func subtitle(for access: WeatherAccess) -> String {
        switch access {
        case .denied:
            "HITList isn't allowed to use your location, so your companion keeps this device's hours, without weather. Allow it below."
        case .restricted:
            "Location is restricted on this device, so your companion keeps its hours, without weather."
        case .notDetermined, .allowed: about
        }
    }

    /// Where the switch is, under the system's settings (the row above it opens them).
    static let settingsPath = "Privacy & Security → Location Services → HITList"

    /// The system question's words (`NSLocationWhenInUseUsageDescription` in `project.yml`, both platforms): what the
    /// location is for, and nothing it is not used for. A test holds the Info.plist to this.
    static let purpose = "HITList uses your approximate location to keep your companion on local time and dressed for the weather where you are. It is never stored or shared."
}
