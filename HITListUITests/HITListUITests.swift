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

    /// Review Inbox (brief 60): three tasks added on the Inbox with no date or Group are offered as "Review 3
    /// unsorted…"; the first is swiped right (Today), the second left (deleted) and brought back from the toast,
    /// then put off with Later; the third is deleted. The review ends on "Inbox reviewed", the menu then offers
    /// the one left, and the first is on Today.
    func testReviewInboxSwipes() throws {
        app.launch()
        let inbox = app.buttons["tab-inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15))
        inbox.tap()
        let plus = app.buttons["quickAddButton"].firstMatch
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        for name in ["Alpha idea", "Beta idea", "Gamma idea"] {
            XCTAssertTrue(plus.wait(for: \.isHittable, toEqual: true, timeout: 5), "the + before \(name)")
            plus.tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            app.typeText(name)
            app.buttons["quickAddSave"].tap()
            XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the card closes after \(name)")
        }

        app.buttons["viewOptions"].firstMatch.tap()
        let item = app.buttons["Review 3 unsorted…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the menu item counts the unsorted tasks")
        snapshot("1 Menu")
        item.tap()

        let card = app.descendants(matching: .any)["reviewCard"].firstMatch
        let cardTitle = app.buttons["reviewTitle"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the review's card")
        XCTAssertTrue(app.staticTexts["3 tasks with no date or Group"].exists)
        XCTAssertEqual(cardTitle.label, "Alpha idea", "oldest first")
        snapshot("2 Card")

        card.swipeRight()
        XCTAssertTrue(cardTitle.wait(for: \.label, toEqual: "Beta idea", timeout: 5), "swiped right: the next card")

        card.swipeLeft()
        let undo = app.buttons["reviewUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "deleting offers Undo")
        XCTAssertTrue(cardTitle.wait(for: \.label, toEqual: "Gamma idea", timeout: 5))
        snapshot("3 Deleted, undo")
        undo.tap()
        XCTAssertTrue(cardTitle.wait(for: \.label, toEqual: "Beta idea", timeout: 5), "Undo brings the card back")

        app.buttons["reviewLater"].tap()
        XCTAssertTrue(cardTitle.wait(for: \.label, toEqual: "Gamma idea", timeout: 5), "Later moves on")
        card.swipeLeft()
        XCTAssertTrue(app.staticTexts["Inbox reviewed"].waitForExistence(timeout: 5), "the empty state")
        XCTAssertTrue(app.staticTexts["1 task waits in the Inbox for later."].exists)
        snapshot("4 Reviewed")
        app.buttons["reviewDone"].tap()
        XCTAssertTrue(app.staticTexts["Inbox reviewed"].waitForNonExistence(timeout: 5), "the sheet closes")

        app.buttons["viewOptions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Review 1 unsorted…"].waitForExistence(timeout: 5), "Beta is still unsorted")
        snapshot("5 Menu after")
        app.buttons["Review 1 unsorted…"].tap()
        XCTAssertTrue(cardTitle.wait(for: \.label, toEqual: "Beta idea", timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))

        let today = app.buttons["tab-today"]
        today.tap()
        XCTAssertTrue(today.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let alpha = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Alpha idea")).firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5), "the task swiped right is on Today")
        let gamma = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Gamma idea")).firstMatch
        XCTAssertFalse(gamma.exists)
        snapshot("6 Today")
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
