import XCTest
@testable import HITListCore

/// Brief 80: WeatherKit's conditions as the companions' six skies. The names are WeatherKit's `WeatherCondition` raw
/// values (Xcode 27.2 SDK, all 34 of them); the app's `WeatherConditionTableTests` checks the SDK still has no others.
final class CompanionSkyWeatherTests: XCTestCase {
    private func sky(_ condition: String) -> CompanionSky { CompanionSky(weatherCondition: condition) }

    func testThunderAndSevereWeatherAreStorm() {
        for condition in ["thunderstorms", "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms",
                          "tropicalStorm", "hurricane", "hail"] {
            XCTAssertEqual(sky(condition), .storm, condition)
        }
    }

    func testDrizzleRainShowersAndFreezingRainAreRain() {
        for condition in ["drizzle", "rain", "heavyRain", "sunShowers", "freezingDrizzle", "freezingRain"] {
            XCTAssertEqual(sky(condition), .rain, condition)
        }
    }

    func testSnowSleetFlurriesAndBlizzardsAreSnow() {
        for condition in ["snow", "heavySnow", "sleet", "flurries", "sunFlurries", "blizzard", "blowingSnow", "wintryMix"] {
            XCTAssertEqual(sky(condition), .snow, condition)
        }
    }

    func testClearAndMostlyClearAreClear() {
        XCTAssertEqual(sky("clear"), .clear)
        XCTAssertEqual(sky("mostlyClear"), .clear)
    }

    func testEverythingElseIsClouds() {
        for condition in ["cloudy", "mostlyCloudy", "partlyCloudy", "foggy", "haze", "smoky", "blowingDust", "breezy",
                          "windy", "hot", "frigid"] {
            XCTAssertEqual(sky(condition), .clouds, condition)
        }
    }

    func testAConditionWeatherKitAddsLaterIsClouds() {
        XCTAssertEqual(sky("volcanicAsh"), .clouds)
        XCTAssertEqual(sky(""), .clouds)
    }

    func testTheTableNamesEveryConditionOnceAndNeverUnknown() {
        let named = CompanionSky.weatherConditions
        XCTAssertEqual(named.count, 34)
        XCTAssertFalse(named.values.contains(.unknown), "an observation is never unknown")
        XCTAssertEqual(Set(named.values), [.clear, .clouds, .rain, .snow, .storm])
    }
}
