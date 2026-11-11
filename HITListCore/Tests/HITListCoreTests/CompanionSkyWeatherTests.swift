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
                          "windy", "frigid"] {
            XCTAssertEqual(sky(condition), .clouds, condition)
        }
    }

    func testAHotDayIsHeatAndWhateverFallsWins() {
        XCTAssertEqual(sky("hot"), .heat)
        func feels(_ condition: String, _ celsius: Double?, day: Bool? = true) -> CompanionSky {
            CompanionSky(weatherCondition: condition, apparentCelsius: celsius, isDaylight: day)
        }
        XCTAssertEqual(feels("clear", 30), .heat, "from 30 °C")
        XCTAssertEqual(feels("mostlyCloudy", 34.5), .heat)
        XCTAssertEqual(feels("clear", 29.9), .clear)
        XCTAssertEqual(feels("clear", nil), .clear, "no temperature, no heat")
        XCTAssertEqual(feels("clear", 33, day: false), .clear, "a warm night is not a hot day")
        XCTAssertEqual(feels("clear", 33, day: nil), .heat, "an unknown sun counts as up")
        XCTAssertEqual(feels("heavyRain", 35), .rain, "rain in a heatwave is rain")
        XCTAssertEqual(feels("thunderstorms", 35), .storm)
        XCTAssertEqual(feels("snow", 35), .snow)
        XCTAssertEqual(feels("hot", 12, day: false), .heat, "WeatherKit's own word stands")
    }

    func testAConditionWeatherKitAddsLaterIsClouds() {
        XCTAssertEqual(sky("volcanicAsh"), .clouds)
        XCTAssertEqual(sky(""), .clouds)
    }

    func testTheTableNamesEveryConditionOnceAndNeverUnknown() {
        let named = CompanionSky.weatherConditions
        XCTAssertEqual(named.count, 34)
        XCTAssertFalse(named.values.contains(.unknown), "an observation is never unknown")
        XCTAssertEqual(Set(named.values), [.clear, .clouds, .rain, .snow, .storm, .heat])
    }
}
