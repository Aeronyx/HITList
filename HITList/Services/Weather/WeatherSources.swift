import Foundation
import CoreLocation

// Brief 80: the sky for the companions. Where the person is (approximately) and what the sky is doing there, each
// behind a protocol so the tests use fakes and a Debug run can use the demo (`-seedDemoSky rain`). The location goes
// from one source straight into the other and is never stored, synced, logged or sent anywhere but to Apple's
// WeatherKit request.

/// Whether HITList may know roughly where the device is, while it is in use.
enum WeatherAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case allowed

    /// The person (or a device profile) has said no, so asking again shows nothing: only the system's settings
    /// change it.
    var isRefused: Bool { self == .denied || self == .restricted }
}

/// Where the device is, as roughly as a town.
@MainActor
protocol WeatherLocationSource: AnyObject {
    /// The current permission, without asking.
    func access() -> WeatherAccess
    /// Asks for location while the app is in use (the system's prompt, once); the permission afterwards.
    func requestAccess() async -> WeatherAccess
    /// One reduced-accuracy fix. Throws when none arrives.
    func approximateLocation() async throws -> CLLocation
}

/// What the sky is doing: Apple's WeatherKit on a device, the demo under `-seedDemoSky`, a fake in tests.
@MainActor
protocol WeatherConditionSource: AnyObject {
    /// The current condition at `location`.
    func currentCondition(at location: CLLocation) async throws -> WeatherReading
    /// Apple's attribution for the data (the Apple Weather mark and the link to its data sources).
    func credit() async throws -> WeatherCredit
}

/// One current-conditions answer.
struct WeatherReading: Equatable, Sendable {
    /// WeatherKit's `WeatherCondition` raw value ("heavyRain"); core's table turns it into a `CompanionSky`.
    let condition: String
    /// When the conditions were observed.
    let date: Date
}

/// Apple's required attribution, as WeatherKit's `WeatherAttribution` gives it.
struct WeatherCredit: Equatable, Sendable {
    /// " Weather".
    let serviceName: String
    /// The combined mark for a dark background (the app is dark only).
    let markURL: URL?
    /// The page listing the data sources.
    let legalURL: URL

    /// What the setting shows before (or without) Apple's answer: the service's name and its legal page.
    static let fallback = WeatherCredit(serviceName: "\u{F8FF} Weather", markURL: nil,
                                        legalURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
}
