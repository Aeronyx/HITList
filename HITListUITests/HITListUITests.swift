import XCTest

/// UI tests on the iPhone simulator (supervisor, round 11): they tap and type through the real app with
/// XCUITest, so a session can check a screen without the simulator panel's "Let Claude use it" permission.
/// Run them with `SIMULATOR=<your simulator> scripts/test.sh ui`; the screenshots they attach land in the
/// .xcresult (`xcrun xcresulttool export attachments --path <result> --output-path <folder>`).
///
/// Every launch uses a store and settings of its own (`HITLIST_STORE_SUFFIX=uitest`, see
/// `AppGroup.suiteName(suffix:)`), so nothing here touches the simulator's Debug store or its settings.
final class HITListUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        // No first-run tips: on iPhone a tip takes the first tap outside it to close itself.
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    /// The four tabs, then quick add end to end: the card opens with the keyboard in the title, the typed
    /// phrases light up as chips, Add saves, and the task shows on Upcoming.
    func testTabsAndQuickAdd() throws {
        app.launch()
        for tab in ["inbox", "today", "upcoming", "flipboard"] {
            XCTAssertTrue(app.buttons["tab-\(tab)"].waitForExistence(timeout: 15), "tab \(tab)")
        }
        snapshot("1 Today")

        app.buttons["quickAddButton"].firstMatch.tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the card's title field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the card opens with the keyboard in the title")
        app.typeText("UI smoke test tom 5pm p1 ")
        snapshot("2 Card typed")

        let save = app.buttons["quickAddSave"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        // A tap while the card slides away is swallowed: wait until it has gone.
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the card closes after Add")

        let upcoming = app.buttons["tab-upcoming"]
        upcoming.tap()
        XCTAssertTrue(upcoming.wait(for: \.isSelected, toEqual: true, timeout: 5), "Upcoming selected")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "UI smoke test")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the new task on Upcoming")
        snapshot("3 Upcoming")
    }

    /// The island's motion (brief 58): every tab change leaves exactly one tab selected, and after the screens
    /// crossfade the "+" adds to the list on show (the incoming list's onAppear sets the card's context while
    /// the outgoing one is still fading). Inbox then Today: a stale Inbox context would add an undated task,
    /// which Today does not show.
    ///
    /// A believable week (`-seedDemoData`) so the crossfade has lists to fade, and a second between taps so a
    /// screen recording of this test (`xcrun simctl io <udid> recordVideo`) shows each change on its own.
    func testTabSwitchCrossfadesAndThePlusFollowsTheScreen() throws {
        app.launchArguments.append("-seedDemoData")
        app.launch()
        let tabs = ["inbox", "today", "upcoming", "flipboard"].map { app.buttons["tab-\($0)"] }
        XCTAssertTrue(tabs[1].waitForExistence(timeout: 15))
        for index in [0, 1, 2, 3, 1, 0, 1] {
            let tab = tabs[index]
            tab.tap()
            XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 3), "tab \(index) selected")
            XCTAssertEqual(tabs.filter(\.isSelected).count, 1, "never two tabs selected")
            Thread.sleep(forTimeInterval: 1)
        }
        snapshot("Today after switching")

        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.wait(for: \.isHittable, toEqual: true, timeout: 3))
        plus.tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Crossfade context check")
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the card closes after Add")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Crossfade context check")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "added to Today, the list on show, not to the Inbox it left")
        snapshot("Added on Today")
    }

    /// One tap on "+" right after an Add opens the next card. Brief 56 found the first tap swallowed (a friend
    /// adding a second task had to tap twice).
    func testPlusOpensTheNextCardRightAfterAnAdd() throws {
        app.launch()
        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("First task ")
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the card closes after Add")
        XCTAssertTrue(plus.wait(for: \.isHittable, toEqual: true, timeout: 3), "the + is back")

        plus.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3), "one tap opens the next card")
        snapshot("Second card")
    }

    /// Keeps a screenshot in the test result.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
