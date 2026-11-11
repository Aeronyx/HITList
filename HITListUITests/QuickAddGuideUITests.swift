import XCTest

/// Brief 98 on iPhone: the quick add guide's two ways in, Browse's "Quick add guide" row under Settings and Settings →
/// General → Quick add guide, each opening the guide as a page of the Settings sheet. Screenshots of Browse, of the
/// General page's row and of the whole guide land in the .xcresult (`xcrun xcresulttool export attachments`). Each
/// launch has a store and settings of its own, sync off, no tips.
final class QuickAddGuideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s98-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
    }

    func testBrowsesRowOpensTheGuide() {
        app.launch()
        openBrowse()
        shot("00 Browse's top bar, unchanged")
        let row = element("browse-quick-add-guide")
        scroll(to: row)
        XCTAssertTrue(row.isHittable, "the row under Settings")
        shot("01 Browse with the row")
        row.tap()
        XCTAssertTrue(element("guide-example").waitForExistence(timeout: 5), "the guide opened")
        XCTAssertTrue(app.staticTexts["Quick add"].firstMatch.exists, "its title")
        pause()
        shotDown("02 Guide from Browse")
        back()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "back leads to Settings")
    }

    func testSettingsGeneralHasTheGuideRow() {
        app.launch()
        openBrowse()
        app.buttons["settingsButton"].firstMatch.tap()
        XCTAssertTrue(element("settings-page-general").waitForExistence(timeout: 5), "Settings opened")
        pause()
        element("settings-page-general").tap()
        let row = element("settings-quick-add-guide")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the row on General")
        scroll(to: row)
        shot("03 General with the row")
        row.tap()
        XCTAssertTrue(element("guide-example").waitForExistence(timeout: 5), "the guide opened as a page")
        pause()
        shot("04 Guide from General")
        back()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "back on General")
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func openBrowse() {
        let inbox = app.buttons["tab-inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.tap()
        app.buttons["browseButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settingsButton"].firstMatch.waitForExistence(timeout: 5), "Browse opened")
        pause()
    }

    private func back() {
        let back = app.buttons["sheetBack"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        pause()
    }

    /// Drags the page up until `target` is on screen and clear of the sheet's bar and the screen's foot.
    private func scroll(to target: XCUIElement) {
        let top: CGFloat = 140
        let bottom = app.frame.height - 60
        for _ in 0..<8 {
            if target.exists, target.frame.minY > top, target.frame.maxY < bottom { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -320)))
            pause(0.5)
        }
    }

    /// Screenshots of the open page from its top down to its end, a screen at a time.
    private func shotDown(_ name: String) {
        shot("\(name) 1")
        for part in 2...5 {
            let before = app.screenshot().pngRepresentation
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -560)))
            pause(0.8)
            if app.screenshot().pngRepresentation == before { break }
            shot("\(name) \(part)")
        }
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
