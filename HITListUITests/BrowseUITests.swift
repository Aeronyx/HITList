import XCTest

/// Browse on iPhone (brief 73): its end clear of the tab island, and swiping a Group away.
/// Run with `SIMULATOR=<your simulator> scripts/test.sh ui`; the screenshots land in the .xcresult.
final class BrowseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        // No first-run tips: on iPhone a tip takes the first tap outside it to close itself.
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    // MARK: - The end of Browse

    /// George, 2026-11-10: "The Browse tab has hidden button at the bottom again behind the home bar." Scrolled to its
    /// end, Browse's last row (Settings) sits wholly above the island and the "+", and a tap reaches it. Runs on
    /// whichever phone the suite runs on (the iPhone 17 and the smallest one, brief 73).
    func testBrowsesLastRowEndsAboveTheIsland() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        openBrowse()
        // A long Browse builds its last rows only once they scroll into sight.
        scrollToEnd()
        let settings = app.buttons["browse-settings-row"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        snapshot("Browse at its end")
        assertClearOfTheChrome(settings, "Browse's Settings row")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5)
                          || app.staticTexts["Settings"].waitForExistence(timeout: 1),
                      "the tap reached the Settings row")
    }

    /// The same with labels and saved filters (the demo week has both), and without any: a fresh store has no labels,
    /// no filters and no Groups, so Browse is short and its last row must still be clear.
    func testBrowsesLastRowEndsAboveTheIslandOnAnEmptyStore() throws {
        app.launch()
        openBrowse()
        let settings = app.buttons["browse-settings-row"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        scrollToEnd()
        snapshot("Browse at its end, empty store")
        assertClearOfTheChrome(settings, "Browse's Settings row")
    }

    /// Every screen pushed inside Browse ends clear of the island too: the Inbox (the demo week's
    /// longest list) and a Group, scrolled to their ends, keep their last line above the chrome.
    func testScreensPushedFromBrowseEndAboveTheIsland() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        openBrowse()
        for name in ["Inbox", "Work"] {
            let row = app.collectionViews.firstMatch.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), name)
            row.tap()
            scrollToEnd()
            snapshot("\(name) at its end")
            assertClearOfTheChrome(lastLine(), "\(name)'s last line")
            goBack()
        }
    }

    // MARK: - Helpers

    private func openBrowse() {
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        XCTAssertTrue(app.textFields["browseSearch"].firstMatch.waitForExistence(timeout: 5)
                          || app.descendants(matching: .any)["browseSearch"].firstMatch.waitForExistence(timeout: 5))
    }

    private func goBack() {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        (back.exists ? back : app.navigationBars.buttons.firstMatch).tap()
        XCTAssertTrue(app.descendants(matching: .any)["browseSearch"].firstMatch.waitForExistence(timeout: 5), "back on Browse")
    }

    /// Swipes up until the list stops moving.
    private func scrollToEnd() {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "a list on screen")
        for _ in 0..<6 {
            let before = lastLine().frame
            list.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.8)  // let the bounce settle
            if lastLine().frame == before { break }
        }
    }

    /// The bottom-most text in the list on screen (a task row's title or meta line, a row's name).
    private func lastLine() -> XCUIElement {
        let texts = app.collectionViews.firstMatch.staticTexts.allElementsBoundByIndex.filter { !$0.frame.isEmpty }
        let last = texts.max { $0.frame.maxY < $1.frame.maxY }
        XCTAssertNotNil(last, "a line on screen")
        return last ?? app.collectionViews.firstMatch
    }

    /// `element` ends above the island's top and the "+"'s top, and is hittable.
    private func assertClearOfTheChrome(_ element: XCUIElement, _ name: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let tabs = ["inbox", "today", "upcoming", "flipboard"].map { app.buttons["tab-\($0)"].firstMatch }
        XCTAssertTrue(tabs[0].exists, "the island is on show", file: file, line: line)
        // The tab buttons are the island's pills, 6 pt inside its edge (`IslandMetrics.pillInset`).
        let islandTop = tabs.map(\.frame.minY).min()! - 6
        let plus = app.buttons["quickAddButton"].firstMatch
        let chromeTop = plus.exists ? min(islandTop, plus.frame.minY) : islandTop
        XCTAssertLessThanOrEqual(element.frame.maxY, chromeTop,
                                 "\(name) ends at \(element.frame.maxY), the chrome starts at \(chromeTop)",
                                 file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) is hittable", file: file, line: line)
    }

    /// Keeps a screenshot in the test result.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
