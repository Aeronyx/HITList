import XCTest
import HITListCore
@testable import HITList

/// Round 19: a hot day is a sky of its own, read from how warm it feels and whether the sun is up.
@MainActor
final class WeatherHeatTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    func testAReadingThatOnlyNamesAConditionIsWhatTheTableSays() {
        XCTAssertEqual(WeatherReading(condition: "clear", date: at).sky, .clear)
        XCTAssertEqual(WeatherReading(condition: "heavyRain", date: at).sky, .rain)
    }

    func testAWarmDryDayIsHeatAndANightOrRainIsNot() {
        XCTAssertEqual(WeatherReading(condition: "clear", date: at, apparentCelsius: 31, isDaylight: true).sky, .heat)
        XCTAssertEqual(WeatherReading(condition: "partlyCloudy", date: at, apparentCelsius: 31, isDaylight: true).sky, .heat)
        XCTAssertEqual(WeatherReading(condition: "clear", date: at, apparentCelsius: 31, isDaylight: false).sky, .clear)
        XCTAssertEqual(WeatherReading(condition: "rain", date: at, apparentCelsius: 31, isDaylight: true).sky, .rain)
        XCTAssertEqual(WeatherReading(condition: "clear", date: at, apparentCelsius: 24, isDaylight: true).sky, .clear)
    }

    func testTheDemoCanAskForAHotDay() {
        XCTAssertEqual(DemoWeatherSource.condition(for: .heat).map(CompanionSky.init(weatherCondition:)), .heat)
    }
}
