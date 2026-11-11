import Foundation
import CoreLocation
import WeatherKit

/// Apple's weather (brief 80): one current-conditions request per observation, nothing else (no forecast), and the
/// attribution Apple requires wherever its data is used. From it: the condition, how warm it feels and whether the
/// sun is up (round 19: a hot day is a sky of its own); none of it is shown, stored or logged as a number. Needs the WeatherKit capability on the
/// App ID; without it every request throws and the sky stays `unknown`.
@MainActor
final class WeatherKitSource: WeatherConditionSource {
    private let service = WeatherKit.WeatherService.shared

    func currentCondition(at location: CLLocation) async throws -> WeatherReading {
        let current = try await service.weather(for: location, including: .current)
        let feels: Double = current.apparentTemperature.converted(to: .celsius).value
        return WeatherReading(condition: current.condition.rawValue, date: current.date,
                              apparentCelsius: feels, isDaylight: current.isDaylight)
    }

    func credit() async throws -> WeatherCredit {
        let attribution = try await service.attribution
        return WeatherCredit(serviceName: attribution.serviceName, markURL: attribution.combinedMarkDarkURL,
                             legalURL: attribution.legalPageURL)
    }
}
