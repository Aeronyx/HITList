import XCTest

/// A friend's first run (brief 56), recorded: a fresh store with the first-run tips on, exactly as a friend
/// installing from TestFlight gets it (only iCloud is off). Launch, add "Call mom tomorrow 5pm p1",
/// complete a task and see the Undo toast, open Browse, Settings and Account, with a screenshot at each
/// step for George (`xcrun xcresulttool export attachments …`).
///
/// It also proves a tip never takes a tap: the very first tap goes to the "+" and opens the card, Add adds
/// with the quick-add tip showing, and Browse's tip waits until the person comes back to the app.
final class FirstRunUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "firstrun-\(UUID().uuidString.prefix(8))"
        // Tips on (no -hideTips): this is the run a friend gets.
        app.launchArguments += ["-disableCloudKit", "YES"]
    }

    func testAFriendsFirstRun() throws {
        app.launch()
        let today = app.buttons["tab-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 15), "the tabs")
        // Give TipKit a moment: a tip that was going to show on the first screen would be up by now.
        XCTAssertFalse(tip.waitForExistence(timeout: 2), "no tip on the very first screen")
        snapshot("01 First screen")

        // The first tap of all: the "+" opens the card with the keyboard in its title.
        app.buttons["quickAddButton"].firstMatch.tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the first tap opened the card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "with the keyboard in the title")
        XCTAssertTrue(tip.waitForExistence(timeout: 3), "the quick-add tip, inside the card")
        snapshot("02 Card open")

        app.typeText("Call mom tomorrow 5pm p1 ")
        XCTAssertTrue(title.value.map { "\($0)".contains("Call mom tomorrow 5pm p1") } ?? false,
                      "every keystroke reached the title")
        snapshot("03 Card typed")

        let save = app.buttons["quickAddSave"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the card closes after Add")
        XCTAssertFalse(tip.waitForExistence(timeout: 2), "no tip pops up as the first task lands")
        snapshot("04 Added")

        // A task for today to complete: the first one is tomorrow's.
        // One tap is enough (the swallowed first tap after an Add was fixed in 0.7.1; see
        // `HITListUITests.testPlusOpensTheNextCardRightAfterAnAdd`).
        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.wait(for: \.isHittable, toEqual: true, timeout: 3), "the + is back")
        plus.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the card again")
        app.typeText("Water the plants today ")
        save.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the card closes after Add")

        today.tap()
        XCTAssertTrue(today.wait(for: \.isSelected, toEqual: true, timeout: 5), "Today selected")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Water the plants")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "today's task on Today")
        snapshot("05 Today")

        app.buttons["Complete task"].firstMatch.tap()
        let undo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Undo")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the Undo toast")
        snapshot("06 Completed, Undo toast")

        let upcoming = app.buttons["tab-upcoming"]
        upcoming.tap()
        XCTAssertTrue(upcoming.wait(for: \.isSelected, toEqual: true, timeout: 5), "Upcoming selected")
        let call = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Call mom")).firstMatch
        XCTAssertTrue(call.waitForExistence(timeout: 5), "tomorrow's call on Upcoming")
        snapshot("07 Upcoming")

        // Away and back: now the person has settled in, and Browse's tip explains the magnifying glass.
        XCTAssertFalse(tip.exists, "still no tip in the first session")
        XCUIDevice.shared.press(.home)
        app.activate()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10), "the magnifying glass")
        XCTAssertTrue(tip.waitForExistence(timeout: 5), "Browse's tip, back in the app after the first task")
        snapshot("08 Back in the app, Browse tip")
        dismissTipIfShown()
        XCTAssertFalse(tip.exists, "its × closed it")
        browse.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "Browse opened, with Settings' gear")
        snapshot("09 Browse")

        gear.tap()
        // Brief 86: Settings opens on one short screen, the profile first; Account and About are pages in it.
        let profile = app.descendants(matching: .any)["settings-profile"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "Settings opened, the profile first")
        snapshot("10 Settings")

        profile.tap()
        let name = app.descendants(matching: .any)["settings-account-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Account")
        snapshot("11 Settings, Account")
        app.buttons["sheetBack"].firstMatch.tap()

        let about = app.descendants(matching: .any)["settings-page-about"].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        let version = app.descendants(matching: .any)["settings-version"].firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5) && version.isHittable, "About, with the version")
        snapshot("12 Settings, About")
    }

    // MARK: Helpers

    /// Any first-run tip on screen: its × ("Dismiss tip") or its title. (A popover tip's own identifier does
    /// not reach the accessibility tree; its contents do.)
    private var tip: XCUIElement {
        let titles = ["Type it all in one line", "Keep the words as text", "Find anything",
                      "Flip a switch when it’s done", "Add straight to a day"]
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Dismiss tip' OR label IN %@", titles)).firstMatch
    }

    /// Closes a tip with its own × (never by a tap elsewhere, which a popover tip swallows).
    private func dismissTipIfShown() {
        guard tip.exists else { return }
        let close = app.buttons["Dismiss tip"].firstMatch
        if close.exists { close.tap() }
        _ = tip.waitForNonExistence(timeout: 3)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
