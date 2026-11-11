import XCTest

/// Brief 101: Phase on Mocha's "+" in every look, photographed from the real app: by day, asleep, in rain, in snow
/// (and the snow piled deep), on a hot day, and risen out of the "+" (its popUp routine). The screenshots land in the
/// .xcresult. The store is `HITLIST_STORE_SUFFIX` from the runner's environment when set (so a session can leave
/// Mocha chosen in its own side store for recordings), a fresh one otherwise.
final class CompanionPhaseUITests: XCTestCase {
    private var app: XCUIApplication!
    private var store = "uitest-\(UUID().uuidString.prefix(8))"

    override func setUp() {
        continueAfterFailure = false
        if let suffix = ProcessInfo.processInfo.environment["HITLIST_PHASE_STORE"], !suffix.isEmpty { store = suffix }
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = store
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-companion", "phase"]
        app.launchArguments += extra
        app.launch()
    }

    func testPhaseInEveryLookOnMocha() throws {
        launch(["-companionHour", "12"])
        chooseTheme("Mocha")
        snapshot("Phase by day on Mocha")
        let looks: [(String, [String])] = [
            ("asleep", ["-companionHour", "23"]),
            ("rain", ["-companionHour", "12", "-companionSky", "rain"]),
            ("snow", ["-companionHour", "12", "-companionSky", "snow"]),
            ("snow piled deep", ["-companionHour", "12", "-companionSky", "snow", "-companionSnowDepth", "2"]),
            ("heat", ["-companionHour", "12", "-companionSky", "heat"]),
            ("asleep in snow", ["-companionHour", "23", "-companionSky", "snow"]),
        ]
        for (name, arguments) in looks {
            app.terminate()
            launch(arguments)
            XCTAssertTrue(app.buttons["quickAddButton"].firstMatch.waitForExistence(timeout: 15), "the +")
            Thread.sleep(forTimeInterval: 1.2)
            snapshot("Phase \(name)")
        }
        // Risen right out of the "+", its wavy hem showing (the popUp routine, played again and again).
        app.terminate()
        launch(["-companionHour", "12", "-companionPlay", "routine:popUp"])
        XCTAssertTrue(app.buttons["quickAddButton"].firstMatch.waitForExistence(timeout: 15))
        for k in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            snapshot("Phase popUp \(k)")
        }
    }

    // MARK: - Helpers

    private func chooseTheme(_ name: String) {
        let browse = app.buttons["browseButton"].firstMatch
        if browse.waitForExistence(timeout: 15) { browse.tap() }
        let list = app.collectionViews.firstMatch
        let settings = app.buttons["browse-settings-row"].firstMatch
        for _ in 0..<6 where !(settings.exists && settings.isHittable) { list.swipeUp(velocity: .fast) }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let swatch = app.buttons["\(name) theme"].firstMatch
        for _ in 0..<8 where !(swatch.exists && swatch.isHittable) { app.swipeUp() }
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the \(name) swatch")
        swatch.tap()
        app.buttons["Done"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["tab-today"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
