import XCTest
import WeatherKit
import HITListCore
@testable import HITList

/// Brief 80: core's sky table names every condition this SDK's WeatherKit has, so none falls to `clouds` by accident.
/// When an SDK adds one, this fails: give it a place in `CompanionSky.weatherConditions`.
final class WeatherConditionTableTests: XCTestCase {
    func testCoreNamesEveryWeatherKitCondition() {
        let sdk = Set(WeatherCondition.allCases.map(\.rawValue))
        let core = Set(CompanionSky.weatherConditions.keys)
        XCTAssertEqual(sdk.subtracting(core), [], "conditions core's table does not name")
        XCTAssertEqual(core.subtracting(sdk), [], "names core's table has that WeatherKit does not")
    }

    func testARainyReadingIsRain() {
        XCTAssertEqual(CompanionSky(weatherCondition: WeatherCondition.heavyRain.rawValue), .rain)
        XCTAssertEqual(CompanionSky(weatherCondition: WeatherCondition.isolatedThunderstorms.rawValue), .storm)
        XCTAssertEqual(CompanionSky(weatherCondition: WeatherCondition.mostlyClear.rawValue), .clear)
    }
}
