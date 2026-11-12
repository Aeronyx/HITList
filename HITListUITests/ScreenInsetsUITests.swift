import XCTest

/// Brief 115: the screens' own spacing, read from the frames XCUITest reports, on whatever iPhone it runs on (the iPhone
/// Duo's outer display first, an iPhone 16 second). Text against its tile's or card's border is measured in pixels by the
/// inset meter over the screenshots (`115-screen-insets/tool/measure.swift` in the round's notes folder); these pin what
/// frames can show: a screen's tiles on its title's left edge, and Browse's title-row controls at one gap.
///
///     xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:HITListUITests/ScreenInsetsUITests
final class ScreenInsetsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s115-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES",
                               "-seedSharedTasksSample", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 20), "the app is up")
        pause(1.5)
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the phone's tabs")
    }

    /// The Flipboard's tiles start on the large title's left edge, as every list's rows do: 16 pt on an iPhone 16, 20 on
    /// the Duo's outer display (where a fixed 16 put them 4 pt left of "Flipboard").
    func testTheFlipboardStartsOnItsTitlesEdge() {
        go("flipboard")
        let title = app.navigationBars.staticTexts["Flipboard"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the large title")
        let tile = app.descendants(matching: .any)["flipSwitchTile"].firstMatch
        let first = tile.exists ? tile : app.descendants(matching: .any)["addSwitchTile"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "a tile")
        XCTAssertEqual(first.frame.minX, title.frame.minX, accuracy: 2.5,
                       "the first tile (\(first.frame.minX)) on the title's edge (\(title.frame.minX))")
        attachTree("Flipboard")
    }

    /// The Duo's outer display: Browse's picture, the bolt and the pill stand in the title's row at one gap, the bolt's
    /// from the pill (the picture had been an item of its own, 23 pt from the bolt against the bolt's 7 from the pill).
    func testBrowsesTitleRowKeepsOneGap() throws {
        let inbox = app.buttons["tab-inbox"].frame, today = app.buttons["tab-today"].frame
        try XCTSkipUnless(today.minY >= inbox.maxY - 1, "the controls stand in the title's row only on the Duo's outer display")
        go("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        XCTAssertTrue(app.textFields["browseSearch"].waitForExistence(timeout: 8), "Browse opened")
        pause()
        let profile = app.buttons["browse-profile"].firstMatch
        let bolt = app.descendants(matching: .any)["syncBolt"].firstMatch
        let new = app.buttons["browseNew"].firstMatch
        XCTAssertTrue(profile.exists && bolt.exists && new.exists, "the picture, the bolt and the pill")
        attachTree("Browse")
        // As drawn: the picture is a 28 pt circle in the middle of its menu's frame, and the pill's capsule starts
        // `TitleRowControlMetrics.pillPadding` (4) before its first 44 pt target.
        let circleEnd = profile.frame.midX + 14
        let pillStart = new.frame.minX - 4
        let before = bolt.frame.minX - circleEnd
        let after = pillStart - bolt.frame.maxX
        XCTAssertEqual(profile.frame.midY, bolt.frame.midY, accuracy: 4, "the picture in the bolt's row")
        XCTAssertEqual(before, after, accuracy: 1.5, "one gap either side of the bolt (\(before), \(after))")
        XCTAssertGreaterThanOrEqual(before, 4, "the picture clear of the bolt")
    }

    /// Pictures of the four tabs and a Group, at the top and a page down, from the seeded tasks alone (brief 93's walk adds
    /// three through quick add first, which on a busy Duo simulator sometimes leaves its card open and stops the walk).
    /// On demand: `TEST_RUNNER_HITLIST_QA=1`.
    func testPhotographTheLists() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_QA"] == "1", "pictures on demand (TEST_RUNNER_HITLIST_QA=1)")
        for tab in ["inbox", "today", "upcoming", "flipboard"] {
            go(tab)
            snap("list \(tab)")
            snapScrolled("list \(tab)")
        }
        go("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let work = app.staticTexts["Work"].firstMatch
        if work.waitForExistence(timeout: 8) {
            work.tap()
            pause()
            snap("a Group, Work")
        }
    }

    /// Review Inbox and its three tiles, from the Inbox's view options (on demand, as above).
    func testPhotographReviewInbox() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_QA"] == "1", "pictures on demand (TEST_RUNNER_HITLIST_QA=1)")
        go("inbox")
        let options = app.buttons["viewOptions"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5), "the view options")
        options.tap()
        pause()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5), "Review Inbox in the view options")
        review.tap()
        pause(1.2)
        snap("Review Inbox")
        let group = app.buttons["reviewMoveToGroup"].firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5), "the tiles")
        let date = app.buttons["reviewPickDate"].firstMatch, later = app.buttons["reviewLater"].firstMatch
        XCTAssertEqual(date.frame.height, group.frame.height, accuracy: 0.5, "the tiles stand as tall as each other")
        XCTAssertEqual(later.frame.height, group.frame.height, accuracy: 0.5)
    }

    // MARK: Helpers

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func snapScrolled(_ name: String) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.75))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -380)))
        pause(0.8)
        snap("\(name), scrolled")
        let back = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35))
        back.press(forDuration: 0.05, thenDragTo: back.withOffset(CGVector(dx: 0, dy: 600)))
        pause(0.6)
    }

    private func go(_ tab: String) {
        let button = app.buttons["tab-\(tab)"]
        button.tap()
        if button.isSelected { pause(0.3) }
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
        pause()
    }

    private func attachTree(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree: \(name)"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
