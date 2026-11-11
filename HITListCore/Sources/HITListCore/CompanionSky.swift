import Foundation

/// What the sky is doing where the person is, as far as a companion cares (round 18). The weather service decides it
/// (`HITList/Services/Weather`, brief 80); the companions draw for it (brief 79). `unknown` whenever weather is off,
/// not permitted, stale or not yet fetched: a companion then behaves as on a clear day.
///
/// `heat` (round 19, George: "have some of them get tired in the heat/try to hide in the shade") is a hot day with
/// nothing falling: by day, when it feels like `heatFrom` degrees or more. Rain, snow and storms win over it.
public enum CompanionSky: String, Sendable, CaseIterable, Codable {
    case unknown
    case clear
    case clouds
    case rain
    case snow
    case storm
    case heat

    /// From this apparent temperature (°C) a dry day is `heat`: 30 °C, 86 °F.
    public static let heatFrom: Double = 30
}
