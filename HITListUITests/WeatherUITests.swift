import XCTest

/// Briefs 80 and 83 on iPhone: Settings → Extras → Weather, the sky for the companions. On by default, though a Debug
/// build never asks by itself (brief 83's first-launch question is `LocationQuestionUITests`); on with the demo sky
/// (`-seedDemoSky rain`, no location or network) it shows Apple's attribution; the real location prompt on this
/// simulator, refused and allowed. Each launch has a store of its own, sync off, no tips. Screenshots land in the
/// .xcresult.
final class WeatherUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-weather-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    func testOnByDefaultButNotAskedInADebugBuild() {
        app.launch()
        openExtras()
        XCTAssertEqual(weatherToggle.value as? String, "1", "a switch nobody touched is on")
        XCTAssertTrue(subtitle("dresses for the weather").exists)
        XCTAssertFalse(attribution.exists, "no attribution before the question is answered")
        XCTAssertFalse(openSystemSettingsRow.exists)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "a Debug build never asks by itself")
        snapshot("1 Extras, Weather on, not yet asked")
    }

    func testOnWithTheDemoSkyShowsTheAttribution() {
        app.launchArguments += ["-seedDemoSky", "rain"]
        app.launch()
        openExtras()
        XCTAssertTrue(attribution.waitForExistence(timeout: 5), "on: Apple's attribution under the switch")
        XCTAssertTrue(app.buttons["settings-weather-sources"].exists, "the link to the data sources")
        XCTAssertFalse(openSystemSettingsRow.exists)
        snapshot("2 Extras, Weather on, with the attribution")
    }

    func testCompanionsOffDisablesWeather() {
        app.launchArguments += ["-seedDemoSky", "rain"]
        app.launch()
        openExtras()
        let companions = app.descendants(matching: .any)["companionsToggle"].firstMatch
        XCTAssertTrue(companions.exists)
        companions.tap()
        XCTAssertFalse(attribution.waitForExistence(timeout: 1), "Companions off: nothing from Apple Weather")
        XCTAssertFalse(weatherToggle.isEnabled, "the Weather row is disabled while Companions is off")
        snapshot("3 Extras, Companions off")
        companions.tap()
        XCTAssertTrue(attribution.waitForExistence(timeout: 5))
    }

    /// The real prompt: switching on (a Debug build has not asked, so off and on again) asks for location while in use, approximate, with the purpose string; Don't
    /// Allow leaves the switch off, says why and offers the system's settings.
    func testThePromptAndRefusing() {
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        openExtras()
        switchOffThenOn()
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the system's prompt")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "on local time and dressed for the weather")).firstMatch.exists,
                      "the purpose string")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "4 The location prompt"
        shot.lifetime = .keepAlways
        add(shot)
        alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch.tap()
        XCTAssertTrue(openSystemSettingsRow.waitForExistence(timeout: 5), "refused: a way to the system's settings")
        XCTAssertTrue(subtitle("isn't allowed to use your location").exists)
        XCTAssertFalse(attribution.exists)
        snapshot("5 Extras, Weather refused")
    }

    /// Allowed while in use: the switch stays on and the attribution shows (whatever WeatherKit answers here).
    func testAllowing() {
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        openExtras()
        switchOffThenOn()
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the system's prompt")
        alert.buttons.matching(NSPredicate(format: "label CONTAINS %@", "While Using")).firstMatch.tap()
        XCTAssertTrue(attribution.waitForExistence(timeout: 10), "allowed: on, with the attribution")
        XCTAssertFalse(openSystemSettingsRow.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(4)) // the mark loads from Apple
        snapshot("6 Extras, Weather allowed")
    }

    // MARK: Helpers

    /// The switch reads on but a Debug build never asked: off, then on, asks.
    private func switchOffThenOn() {
        weatherToggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(weatherToggle.value as? String, "0")
        weatherToggle.tap()
    }

    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    private var weatherToggle: XCUIElement { app.descendants(matching: .any)["settings-weather"].firstMatch }
    private var attribution: XCUIElement { app.descendants(matching: .any)["settings-weather-attribution"].firstMatch }
    private var openSystemSettingsRow: XCUIElement {
        app.descendants(matching: .any)["settings-weather-open-settings"].firstMatch
    }

    private func subtitle(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openExtras() {
        let inbox = app.buttons["tab-inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15))
        inbox.tap()
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        // Brief 86: Extras is a page of Settings' first screen.
        let extras = app.descendants(matching: .any)["settings-page-extras"].firstMatch
        XCTAssertTrue(extras.waitForExistence(timeout: 5))
        extras.tap()
        for _ in 0..<10 where !(weatherToggle.exists && weatherToggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(weatherToggle.exists, "Extras has a Weather switch")
        // Bring the switch to the middle of the screen, so the rows under it show and nothing covers it.
        let middle = app.frame.height * 0.45
        for _ in 0..<6 where abs(weatherToggle.frame.midY - middle) > 120 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance = max(-300, min(300, middle - weatherToggle.frame.midY))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: distance)))
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        XCTAssertTrue(weatherToggle.isHittable)
    }

    private func snapshot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
