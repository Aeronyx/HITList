import XCTest

/// Brief 86 on iPhone: Settings as one short first screen (the profile, Appearance with the eight themes, a row per
/// page) and pages pushed inside the sheet. The tour keeps a screenshot of the first screen and of every page, top
/// to bottom; the other tests walk each way into Settings and back out of a page (the back control and the edge
/// swipe). Each launch has a store and settings of its own, sync off, no tips, the demo week. Screenshots land in the
/// .xcresult (`xcrun xcresulttool export attachments`).
final class SettingsTidyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s86-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
    }

    /// The pages in the first screen's order, by the identifier of their row.
    private static let pages = ["general", "reminders", "extras", "iCloud", "claude", "about"]

    // MARK: The tour

    func testTourOfEveryPage() {
        app.launch()
        openFromBrowseGear()
        XCTAssertTrue(element("settings-profile").isHittable, "the profile, first")
        let swatch = app.buttons["Slate theme"].firstMatch
        XCTAssertTrue(swatch.isHittable, "the themes, second, without scrolling")
        for page in Self.pages {
            XCTAssertTrue(element("settings-page-\(page)").isHittable, "\(page) is on the first screen without scrolling")
        }
        shot("01 First screen")

        open("settings-profile")
        shotDown("02 Account")
        back()
        var number = 3
        for page in Self.pages {
            open("settings-page-\(page)")
            shotDown(String(format: "%02d %@", number, page))
            number += 1
            if page == "iCloud" {
                tapScrolling(to: "settings-sync-log-row")
                XCTAssertTrue(app.staticTexts["Sync log"].waitForExistence(timeout: 5), "the sync log, pushed")
                pause()
                shot(String(format: "%02d %@", number, "iCloud, Sync log"))
                number += 1
                back()
            }
            if page == "about" {
                tapScrolling(to: "settings-whats-new")
                XCTAssertTrue(element("settings-whats-new-inline").waitForExistence(timeout: 5), "What's New, pushed")
                pause()
                shot(String(format: "%02d %@", number, "About, What's New"))
                number += 1
                back()
            }
            back()
        }
        XCTAssertTrue(element("settings-profile").isHittable, "back on the first screen")
    }

    // MARK: Moving between pages

    func testBackAndTheEdgeSwipeReturnToTheFirstScreen() {
        app.launch()
        openFromBrowseGear()
        open("settings-page-general")
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.isHittable, "a back control in the sheet's bar")
        XCTAssertFalse(element("settings-profile").isHittable, "the first screen is covered")
        back()
        XCTAssertTrue(element("settings-profile").isHittable, "the back control")

        open("settings-page-reminders")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 6, dy: 0))
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 300, dy: 0)))
        XCTAssertTrue(element("settings-profile").waitForHittable(timeout: 3), "the edge swipe")

        // A short drag settles back on the page.
        open("settings-page-extras")
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 40, dy: 0)))
        pause()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.isHittable, "still on Extras")
        back()

        // Done closes Settings from a page too.
        open("settings-page-about")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element("settings-profile").waitForNonExistence(timeout: 5), "Done closes the sheet")
    }

    // MARK: The ways in

    func testEveryWayInArrives() {
        app.launch()
        // Browse's gear.
        openFromBrowseGear()
        close()

        // Browse's last row, Settings.
        let row = app.buttons["browse-settings-row"].firstMatch
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where !(row.exists && row.isHittable) { list.swipeUp(velocity: .fast) }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "Browse's Settings row")
        close()

        // The profile menu's Account settings….
        app.buttons["browse-profile"].firstMatch.tap()
        let account = element("profile-menu-account")
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        // Straight on the Account page (the supervisor's follow-up to brief 86); Back leads to the first screen.
        XCTAssertTrue(element("settings-account-name").waitForExistence(timeout: 5), "Account settings… opens Account")
        back()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "and Back is Settings' first screen")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element("settings-profile").waitForNonExistence(timeout: 5))
        pause(0.6)

        // The sync bolt, on a tab's own screen: Settings, straight on iCloud & data.
        tab("today")
        let bolt = app.buttons["syncBolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 5))
        bolt.tap()
        XCTAssertTrue(element("settings-check-icloud").waitForExistence(timeout: 5), "the bolt opens iCloud & data")
        back()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "and Back is Settings' first screen")
        app.buttons["Done"].firstMatch.tap()
    }

    /// The paths 0.9.2's What's New names ("Settings → Extras → Weather") still lead to their rows.
    func testWhatsNewPathsArrive() {
        app.launch()
        openFromBrowseGear()
        let paths: [(page: String, row: String)] = [
            ("extras", "settings-weather"), ("extras", "companionsToggle"), ("extras", "boltStyle"),
            ("general", "settings-calendar-events"), ("about", "settings-show-tips"),
        ]
        for path in paths {
            open("settings-page-\(path.page)")
            let target = element(path.row)
            scroll(to: target)
            XCTAssertTrue(target.exists && target.isHittable, "\(path.page) → \(path.row)")
            back()
        }
        // Show tips again answers in place.
        open("settings-page-about")
        tapScrolling(to: "settings-show-tips")
        let tips = element("settings-show-tips")
        let deadline = Date().addingTimeInterval(3)
        while !tips.label.contains("Done"), Date() < deadline { pause(0.2) }
        XCTAssertTrue(tips.label.contains("Done"), "Show tips again says Done: \(tips.label)")
    }

    /// Picking a theme on the first screen applies it at once and keeps the sheet open.
    func testAThemeIsPickedOnTheFirstScreen() {
        app.launch()
        openFromBrowseGear()
        let midnight = app.buttons["Midnight theme"].firstMatch
        XCTAssertTrue(midnight.isHittable)
        midnight.tap()
        pause()
        XCTAssertTrue(midnight.isSelected, "Midnight is the theme")
        shot("Midnight picked")
        let slate = app.buttons["Slate theme"].firstMatch
        slate.tap()
        pause()
        XCTAssertTrue(slate.isSelected)
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
    }

    private func openFromBrowseGear() {
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "Settings opened")
        pause()
    }

    private func close() {
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element("settings-profile").waitForNonExistence(timeout: 5), "Settings closed")
        pause(0.6)
    }

    private func open(_ id: String) {
        let row = element(id)
        XCTAssertTrue(row.waitForHittable(timeout: 5), "\(id) on screen")
        row.tap()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 5), "\(id) opened a page")
        pause()
    }

    private func back() {
        let back = app.buttons["sheetBack"].firstMatch
        XCTAssertTrue(back.waitForHittable(timeout: 5))
        back.tap()
        pause()
    }

    /// Drags the open page up until `target` is on screen and clear of the sheet's bar and the screen's foot.
    private func scroll(to target: XCUIElement) {
        let top: CGFloat = 140
        let bottom = app.frame.height - 60
        for _ in 0..<12 {
            if target.exists, target.frame.minY > top, target.frame.maxY < bottom { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let up = !target.exists || target.frame.maxY >= bottom
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -320 : 220)))
            pause(0.5)
        }
    }

    private func tapScrolling(to id: String) {
        let target = element(id)
        scroll(to: target)
        XCTAssertTrue(target.isHittable, "\(id) reachable")
        target.tap()
        pause()
    }

    /// Screenshots of the open page from its top down to its end, a screen at a time.
    private func shotDown(_ name: String) {
        shot("\(name) 1")
        for part in 2...6 {
            let before = app.screenshot().pngRepresentation
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -520)))
            pause(0.8)
            if app.screenshot().pngRepresentation == before { break }
            shot("\(name) \(part)")
        }
        // No drag back down: at a page's top a downward drag would pull the sheet away. The bar stays put anyway.
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return exists && isHittable
    }
}
