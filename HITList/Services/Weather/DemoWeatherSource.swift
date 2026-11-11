#if DEBUG
import Foundation
import CoreLocation
import HITListCore

/// A sky without location or network, for screenshots and UI tests (brief 80): `HITList -seedDemoSky rain` (any
/// `CompanionSky`). The weather service then reports that sky through `CompanionSkySource`, as a real observation
/// would, with Settings → Extras → Weather shown on for the run (not saved). Core Location and WeatherKit are never
/// touched. `-seedDemoWeatherAccess denied` (or `restricted`) shows the refused setting instead, for the Mac, where no
/// session may answer the system's prompt. Debug builds only.
///
/// (`-companionSky rain` is the companions' own override in `CompanionSkySource`; it holds the sky whatever this
/// service says.)
@MainActor
final class DemoWeatherSource: WeatherLocationSource, WeatherConditionSource, WeatherZoneSource {
    static let skyArgument = "-seedDemoSky"
    static let accessArgument = "-seedDemoWeatherAccess"

    let sky: CompanionSky
    let permission: WeatherAccess

    init(sky: CompanionSky, permission: WeatherAccess = .allowed) {
        self.sky = sky
        self.permission = permission
    }

    /// The demo the launch arguments ask for, if any.
    static func requested(arguments: [String] = CommandLine.arguments) -> DemoWeatherSource? {
        let sky = value(after: skyArgument, in: arguments).flatMap(CompanionSky.init(rawValue:))
        let access: WeatherAccess? = switch value(after: accessArgument, in: arguments) {
        case "denied": .denied
        case "restricted": .restricted
        default: nil
        }
        guard sky != nil || access != nil else { return nil }
        return DemoWeatherSource(sky: sky ?? .rain, permission: access ?? .allowed)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }

    /// A WeatherKit condition core's table turns into `sky`.
    static func condition(for sky: CompanionSky) -> String? {
        switch sky {
        case .unknown: nil
        case .clear: "clear"
        case .clouds: "cloudy"
        case .rain: "rain"
        case .snow: "snow"
        case .storm: "thunderstorms"
        case .heat: "hot"
        }
    }

    struct NoSky: Error {}

    func access() -> WeatherAccess { permission }
    func requestAccess() async -> WeatherAccess { permission }
    func approximateLocation() async throws -> CLLocation { CLLocation(latitude: 0, longitude: 0) }

    func currentCondition(at location: CLLocation) async throws -> WeatherReading {
        guard let condition = Self.condition(for: sky) else { throw NoSky() }
        return WeatherReading(condition: condition, date: Date())
    }

    func credit() async throws -> WeatherCredit { .fallback }

    /// No place, so no zone of its own: the device's (`-companionZone` holds one for screenshots).
    func timeZone(at location: CLLocation) async throws -> TimeZone? { nil }
}
#endif
