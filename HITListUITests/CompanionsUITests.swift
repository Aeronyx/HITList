import XCTest

/// The companions on iPhone (brief 76): Nod on Browse's search field, Quill asleep on Browse's last card. Neither
/// takes a tap meant for the field or a row. `testCompanionsDemo` holds each screen while their flourishes play
/// (`-companionDemo all`), for a `simctl io recordVideo` of them at real size.
/// Run with `SIMULATOR=<your simulator> scripts/test.sh ui`; the screenshots land in the .xcresult.
final class CompanionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
    }

    /// A tap on the field right under Nod's dangling feet focuses the field and takes typing, as anywhere else on it.
    func testATapUnderNodsFeetReachesTheField() throws {
        app.launch()
        openBrowse()
        let field = searchField()
        snapshot("Browse with Nod on the field")
        // Nod sits 14 pt from the field's trailing edge, its feet 4 to 6 pt down into it.
        let feet = field.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: field.frame.width - 14 - 12, dy: 4))
        feet.tap()
        app.typeText("gym")
        XCTAssertEqual(field.value as? String, "gym", "the tap reached the field and it took the typing")
        snapshot("Typed under Nod's feet")
    }

    /// Quill lies on Browse's last card; the card's rows still take their taps.
    func testQuillSleepsOnBrowsesLastCard() throws {
        app.launch()
        openBrowse()
        scrollToEnd()
        let settings = app.buttons["browse-settings-row"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        snapshot("Browse's end with Quill")
        // The Completed row, right under where Quill sleeps, opens Completed.
        let completed = app.collectionViews.firstMatch.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        completed.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertTrue(app.navigationBars["Completed"].waitForExistence(timeout: 5)
                          || app.staticTexts["Completed"].waitForExistence(timeout: 2), "the row under Quill opened")
    }

    /// Both flourishes, on demand: Nod's a few seconds after Browse opens, Quill's after scrolling to the end. Long on
    /// purpose, so a recording catches them; the screenshots are the frames around each.
    func testCompanionsDemo() throws {
        app.launchArguments += ["-companionDemo", "all"]
        app.launch()
        openBrowse()
        for second in 1...12 {
            Thread.sleep(forTimeInterval: 1)
            if (3...6).contains(second) { snapshot("Nod at \(second) s") }
        }
        scrollToEnd()
        for second in 1...14 {
            Thread.sleep(forTimeInterval: 1)
            if (7...10).contains(second) { snapshot("Quill at \(second) s") }
        }
    }

    /// Settings → Extras has the Companions switch, on, beside Rare surprises; off, they're gone from Browse.
    func testTheExtrasSwitch() throws {
        app.launch()
        openBrowse()
        scrollToEnd()
        let settings = app.buttons["browse-settings-row"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let toggle = app.descendants(matching: .any)["companionsToggle"].firstMatch
        for _ in 0..<10 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Extras has a Companions switch")
        XCTAssertTrue(app.staticTexts["Rare surprises"].exists)
        snapshot("Extras with Companions")
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.5)
        snapshot("Companions off")
        app.buttons["Done"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        snapshot("Browse's end without Quill")
    }

    // MARK: - Helpers

    private func searchField() -> XCUIElement {
        let field = app.textFields["browseSearch"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func openBrowse() {
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        XCTAssertTrue(app.textFields["browseSearch"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// Swipes up until the list stops moving.
    private func scrollToEnd() {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "a list on screen")
        for _ in 0..<6 {
            let settings = app.buttons["browse-settings-row"].firstMatch
            let before = settings.exists ? settings.frame : .zero
            list.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.8)
            if settings.exists, settings.frame == before { break }
        }
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
