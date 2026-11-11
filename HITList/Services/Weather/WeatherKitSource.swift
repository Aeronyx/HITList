import Foundation
import CoreLocation
import WeatherKit

/// Apple's weather (brief 80): one current-conditions request per observation, nothing else (no forecast, no
/// temperature), and the attribution Apple requires wherever its data is used. Needs the WeatherKit capability on the
/// App ID; without it every request throws and the sky stays `unknown`.
@MainActor
final class WeatherKitSource: WeatherConditionSource {
    private let service = WeatherKit.WeatherService.shared

    func currentCondition(at location: CLLocation) async throws -> WeatherReading {
        let current = try await service.weather(for: location, including: .current)
        return WeatherReading(condition: current.condition.rawValue, date: current.date)
    }

    func credit() async throws -> WeatherCredit {
        let attribution = try await service.attribution
        return WeatherCredit(serviceName: attribution.serviceName, markURL: attribution.combinedMarkDarkURL,
                             legalURL: attribution.legalPageURL)
    }
}
