#if DEBUG
import XCTest
import HITListCore
@testable import HITList

/// Brief 80: `-seedDemoSky rain` reports that sky without location or network, with the setting shown on for the run
/// (not saved); `-seedDemoWeatherAccess denied` shows the refused setting.
@MainActor
final class WeatherDemoTests: XCTestCase {
    private func sky() -> CompanionSkySource {
        CompanionSkySource(arguments: UserDefaults(suiteName: "WeatherDemoTests.noArguments")!)
    }

    func testTheArgumentsChooseTheDemo() {
        XCTAssertNil(DemoWeatherSource.requested(arguments: ["HITList"]))
        XCTAssertEqual(DemoWeatherSource.requested(arguments: ["HITList", "-seedDemoSky", "snow"])?.sky, .snow)
        XCTAssertEqual(DemoWeatherSource.requested(arguments: ["HITList", "-seedDemoSky", "storm"])?.permission, .allowed)
        XCTAssertNil(DemoWeatherSource.requested(arguments: ["HITList", "-seedDemoSky", "hail"]), "not a CompanionSky")
        XCTAssertEqual(DemoWeatherSource.requested(arguments: ["HITList", "-seedDemoWeatherAccess", "denied"])?.permission, .denied)
    }

    func testEverySkyComesBackThroughCoresTable() {
        for sky in CompanionSky.allCases where sky != .unknown {
            let condition = DemoWeatherSource.condition(for: sky)
            XCTAssertEqual(condition.map(CompanionSky.init(weatherCondition:)), sky, "\(sky)")
        }
        XCTAssertNil(DemoWeatherSource.condition(for: .unknown))
    }

    func testTheDemoReportsItsSkyOnForTheRunWithoutSavingTheSetting() async {
        let suite = "WeatherDemoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = sky()
        let weather = CompanionWeather.makeShared(arguments: ["HITList", "-seedDemoSky", "rain"], sky: source, defaults: defaults)
        XCTAssertTrue(weather.isOn)
        await weather.cameForward()
        XCTAssertEqual(source.sky, .rain)
        XCTAssertTrue(weather.isShowing)
        await weather.loadCredit()
        XCTAssertEqual(weather.credit, .fallback, "no network: the name and the legal page")
        XCTAssertNil(defaults.object(forKey: Preferences.companionWeather), "on for the run only")
    }

    func testTheRefusedDemo() async {
        let suite = "WeatherDemoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = sky()
        let weather = CompanionWeather.makeShared(arguments: ["HITList", "-seedDemoWeatherAccess", "denied"], sky: source, defaults: defaults)
        XCTAssertFalse(weather.isOn)
        weather.refreshAccess()
        XCTAssertEqual(weather.access, .denied)
        await weather.cameForward()
        XCTAssertEqual(source.sky, .unknown)
    }
}
#endif
