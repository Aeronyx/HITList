import XCTest

/// Brief 83 on iPhone: the location question at the first launch. A Debug build asks only with
/// `-askLocationAtLaunch YES`, which these tests pass; the permission is reset first, so the system's question shows
/// on this simulator. Allowed: the weather starts and Extras shows Apple's attribution. Refused: Extras says why,
/// with the way to the system's settings. The second launch asks nothing. Each test has a store (and so an "asked"
/// flag) of its own, sync off, no tips. Screenshots land in the .xcresult.
final class LocationQuestionUITests: XCTestCase {
    private var app: XCUIApplication!
    private let store = "uitest-locq-\(UUID().uuidString.prefix(8))"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = store
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-askLocationAtLaunch", "YES"]
    }

    func testTheFirstLaunchAsksAndAllowingStartsTheWeather() {
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        let alert = question()
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
                                                             "keep your companion on local time and dressed for the weather")).firstMatch.exists,
                      "the purpose string")
        keep(XCUIScreen.main.screenshot(), "1 The question at the first launch")
        alert.buttons.matching(NSPredicate(format: "label CONTAINS %@", "While Using")).firstMatch.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(8)) // one fix, one WeatherKit request, one geocode
        keep(app.screenshot(), "2 Allowed, the first screen with the companion")
        openExtras()
        XCTAssertEqual(weatherToggle.value as? String, "1")
        XCTAssertTrue(attribution.waitForExistence(timeout: 10), "allowed: on, with Apple's attribution")
        XCTAssertFalse(openSystemSettingsRow.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(3)) // the mark loads from Apple
        keep(app.screenshot(), "3 Extras, Weather allowed")
    }

    func testRefusingLeavesTheScreenAndExtrasSaysWhy() {
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        let alert = question()
        alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch.tap()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 5), "nothing else changes on screen")
        keep(app.screenshot(), "4 Refused, the first screen")
        openExtras()
        XCTAssertEqual(weatherToggle.value as? String, "0", "refused: Weather is off")
        XCTAssertTrue(openSystemSettingsRow.waitForExistence(timeout: 5), "the way to the system's settings")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "isn't allowed to use your location")).firstMatch.exists)
        XCTAssertFalse(attribution.exists)
        keep(app.screenshot(), "5 Extras, Weather refused")
    }

    func testTheSecondLaunchAsksNothing() {
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        question().buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch.tap()
        app.terminate()
        // Asked and answered: even with the permission back to "not determined" (as Allow Once leaves it), the next
        // launch of the same store never asks by itself.
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 8), "the second launch asks nothing")
        keep(app.screenshot(), "6 The second launch, no question")
    }

    func testADebugLaunchWithoutTheArgumentNeverAsks() {
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips"]
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 8), "a Debug build never asks by itself")
    }

    // MARK: Helpers

    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    private var weatherToggle: XCUIElement { app.descendants(matching: .any)["settings-weather"].firstMatch }
    private var attribution: XCUIElement { app.descendants(matching: .any)["settings-weather-attribution"].firstMatch }
    private var openSystemSettingsRow: XCUIElement {
        app.descendants(matching: .any)["settings-weather-open-settings"].firstMatch
    }

    /// The system's question, shortly after the first screen shows (not during launch).
    private func question() -> XCUIElement {
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15), "the first screen first")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "the system's question")
        return alert
    }

    /// Settings → Extras → Weather, the switch in the middle of the screen (Extras is a page of Settings' first
    /// screen since brief 86).
    private func openExtras() {
        app.buttons["tab-inbox"].tap()
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        let extras = app.descendants(matching: .any)["settings-page-extras"].firstMatch
        XCTAssertTrue(extras.waitForExistence(timeout: 5))
        extras.tap()
        for _ in 0..<10 where !(weatherToggle.exists && weatherToggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(weatherToggle.exists, "Extras has a Weather switch")
        let middle = app.frame.height * 0.45
        for _ in 0..<6 where abs(weatherToggle.frame.midY - middle) > 120 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance = max(-300, min(300, middle - weatherToggle.frame.midY))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: distance)))
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
    }

    private func keep(_ screenshot: XCUIScreenshot, _ name: String) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
