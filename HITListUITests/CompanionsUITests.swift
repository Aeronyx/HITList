import XCTest

/// The companions on iPhone (briefs 76 and 79): one at a time, the theme's, on the top right of the "+" on every
/// screen that shows it, and nowhere else. It never takes a tap meant for the "+", goes away with the "+" when a
/// card opens and comes back with it, and a theme change is the other companion at once. `testEveryLookOnThePlus`
/// keeps a screenshot of each companion by day, asleep, in rain and in snow; `testCompanionsDemo` holds the screen
/// while the gestures and the flourish play (`-companionPlay all`) for a `simctl io recordVideo`.
/// Run with `SIMULATOR=<your simulator> scripts/test.sh ui`; the screenshots land in the .xcresult.
final class CompanionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        // Midday, whatever the simulator's clock says, unless a test asks for the night.
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-companionHour", "12"]
    }

    /// A tap on the "+" right under the companion's feet opens the card, and the companion goes with the "+";
    /// closing the card brings both back.
    func testATapUnderItsFeetIsTheCards() throws {
        app.launch()
        let plus = plusButton()
        snapshot("Today with the companion on the +")
        // The companion sits 8 pt in from the "+"'s right edge, its feet 2 to 6 pt down into it.
        plus.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: plus.frame.width - 22, dy: 3)).tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the tap under its feet opened the card")
        snapshot("The card open: the + and the companion are away")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "× closes the empty card")
        XCTAssertTrue(plusButton().waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        snapshot("The card closed: both back")
    }

    /// A tap on the companion itself, above the "+", is the companion's: no card opens.
    func testATapOnTheCompanionIsNotTheCards() throws {
        app.launch()
        let plus = plusButton()
        plus.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: plus.frame.width - 24, dy: -14)).tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertFalse(title.waitForExistence(timeout: 2), "a tap on the companion opened no card")
        snapshot("A tap on the companion")
    }

    /// Browse has no companion of its own any more: not on its field, not at its foot.
    func testBrowseHasNoneOfItsOwn() throws {
        app.launch()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        XCTAssertTrue(app.textFields["browseSearch"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        snapshot("Browse: the field alone, the companion on the + only")
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 { list.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 0.8)
        snapshot("Browse's end: nobody asleep in the corner")
    }

    /// Choosing Midnight in Settings is Quill on the "+" at once; Slate is Nod again.
    func testAThemeChangeIsTheOtherCompanion() throws {
        app.launch()
        _ = plusButton()
        snapshot("Slate: Nod")
        chooseTheme("Midnight")
        XCTAssertTrue(plusButton().waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        snapshot("Midnight: Quill")
        chooseTheme("Slate")
        Thread.sleep(forTimeInterval: 0.8)
        snapshot("Slate again: Nod")
    }

    /// Each companion by day, asleep, in the rain and in the snow, on its own theme's "+" (Debug arguments pick the
    /// companion, the hour and the sky).
    func testEveryLookOnThePlus() throws {
        let looks: [(String, [String])] = [
            ("day", ["-companionHour", "12"]),
            ("asleep", ["-companionHour", "23"]),
            ("rain", ["-companionHour", "12", "-companionSky", "rain"]),
            ("snow", ["-companionHour", "12", "-companionSky", "snow"]),
        ]
        let base = app.launchArguments.filter { $0 != "-companionHour" && $0 != "12" }
        for companion in Self.companions {
            for (name, arguments) in looks {
                app.terminate()
                app.launchArguments = base + ["-companion", companion] + arguments
                app.launch()
                _ = plusButton()
                Thread.sleep(forTimeInterval: 0.8)
                snapshot("\(companion) \(name)")
            }
        }
    }

    /// Every gesture, the reply and the flourish in turn, a few seconds apart, held long enough to record.
    func testCompanionsDemo() throws {
        let companion = ProcessInfo.processInfo.environment["HITLIST_COMPANION"] ?? "nod"
        app.launchArguments += ["-companion", companion, "-companionPlay", "all"]
        app.launch()
        _ = plusButton()
        for second in 1...30 {
            Thread.sleep(forTimeInterval: 1)
            if second % 5 == 0 { snapshot("\(companion) at \(second) s") }
        }
    }

    // MARK: - Helpers

    static let companions = ["nod", "quill", "hush"]

    private func plusButton() -> XCUIElement {
        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15), "the +")
        return plus
    }

    private func chooseTheme(_ name: String) {
        let browse = app.buttons["browseButton"].firstMatch
        if browse.waitForExistence(timeout: 5) { browse.tap() }
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
        // Back to the tab's first screen, where the "+" stands alone.
        app.buttons["tab-today"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
