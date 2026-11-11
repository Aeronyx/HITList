import Foundation

/// What the sky is doing where the person is, as far as a companion cares (round 18). The weather service decides it
/// (`HITList/Services/Weather`, brief 80); the companions draw for it (brief 79). `unknown` whenever weather is off,
/// not permitted, stale or not yet fetched: a companion then behaves as on a clear day.
public enum CompanionSky: String, Sendable, CaseIterable, Codable {
    case unknown
    case clear
    case clouds
    case rain
    case snow
    case storm
}
