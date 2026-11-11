import XCTest

/// The iPhone profile menu (brief 53), through the real app: Browse's profile button opens the menu with
/// What's New, Send Beta Feedback… and the version; What's New opens as a sheet with this version's lines;
/// Send Beta Feedback… on a simulator (no Mail app) shows the card with the address and Copy.
/// In its own file beside `HITListUITests.swift` (session 56 owns that one this round).
final class ProfileMenuUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        // No first-run tips: on iPhone a tip takes the first tap outside it to close itself.
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Opens Browse, then the profile menu.
    private func openMenu() {
        let profile = element("browse-profile")
        if !profile.exists {
            let browse = element("browseButton")
            XCTAssertTrue(browse.waitForExistence(timeout: 15), "the magnifying glass that opens Browse")
            browse.tap()
        }
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "Browse's profile button")
        profile.tap()
        XCTAssertTrue(element("profile-menu-whatsnew").waitForExistence(timeout: 5), "the menu opened")
    }

    func testProfileMenuWhatsNewAndFeedback() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        openMenu()

        // The menu: Account settings…, What's New, Send Beta Feedback…, the version; no Settings… (the gear).
        XCTAssertTrue(element("profile-menu-account").exists)
        XCTAssertTrue(element("profile-menu-feedback").exists)
        XCTAssertFalse(element("profile-menu-settings").exists, "Browse's gear is the way to Settings")
        let version = element("profile-menu-version")
        XCTAssertTrue(version.exists)
        XCTAssertTrue(version.label.hasPrefix("HITList version "), version.label)
        snapshot("1 Profile menu")

        // What's New: a sheet with this version's lines only (brief 99: no earlier versions).
        element("profile-menu-whatsnew").tap()
        let done = element("whatsNewDone")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "What's New opened once the menu had gone")
        XCTAssertTrue(app.staticTexts["What's New"].exists)
        XCTAssertFalse(element("whatsNewEarlier").exists, "no Earlier versions")
        snapshot("2 What's New")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done closes it")

        // Send Beta Feedback…: the simulator has no Mail app, so the card shows the address and Copy.
        openMenu()
        element("profile-menu-feedback").tap()
        let address = element("betaFeedbackAddress")
        XCTAssertTrue(address.waitForExistence(timeout: 8), "the no-mail-app card")
        XCTAssertEqual(address.label, "george@trammells.com")
        let copy = element("betaFeedbackCopy")
        XCTAssertTrue(copy.exists)
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 3) || copy.label.contains("Copied"))
        snapshot("4 Feedback card")
        let feedbackDone = element("betaFeedbackDone")
        feedbackDone.tap()
        XCTAssertTrue(feedbackDone.waitForNonExistence(timeout: 5))

        // Account settings… still opens Settings.
        openMenu()
        element("profile-menu-account").tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5)
                      || app.navigationBars["Settings"].exists, "Settings opened")
        snapshot("5 Account settings")
    }

    /// Keeps a screenshot in the test result.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
