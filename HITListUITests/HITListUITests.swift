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

    /// Brief 59 on iPhone, from the demo week's two switches (both red: never flipped). Flipping one from its
    /// Today row turns it green and it leaves Today, the Inbox and Upcoming; a long press on a tile opens the
    /// switch's menu and every item works; Delete takes a switch off the board and Today at once, with Undo.
    func testFlipboardSwitchesStayOffTheListsUntilDue() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        let water = "Water the plants", recycling = "Take out the recycling"

        // Today: both red switches, as today's tasks.
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        app.buttons["tab-today"].tap()
        XCTAssertTrue(text(water).waitForExistence(timeout: 10))
        XCTAssertTrue(text(recycling).exists)
        XCTAssertFalse(text("Overdue").exists)
        snapshot("1 Today: two red switches")

        // Completing a red switch's row flips it: the toast says so, the row leaves Today.
        let row = app.cells.containing(NSPredicate(format: "label == %@", recycling)).firstMatch
        row.buttons["Flip switch"].tap()
        XCTAssertTrue(text("Flipped ‘\(recycling)’").waitForExistence(timeout: 3), "the toast says Flipped")
        snapshot("2 Flipped from its Today row")
        XCTAssertTrue(text(recycling).waitForNonExistence(timeout: 8), "green: gone from Today")

        // Green is on the Flipboard only; red is in the Inbox as a today task; Upcoming shows neither.
        tab("inbox")
        XCTAssertTrue(text(water).waitForExistence(timeout: 5))
        XCTAssertFalse(text(recycling).exists)
        snapshot("3 Inbox: the red switch only")
        tab("upcoming")
        sleep(1)
        XCTAssertFalse(text(water).exists)
        XCTAssertFalse(text(recycling).exists)
        snapshot("4 Upcoming: no switches")

        // The board: a long press opens the menu (red: Flip first; nothing to flip back).
        tab("flipboard")
        openMenu(water)
        for item in ["Flip", "Edit task…", "Edit interval…", "Flips per interval…", "Remove from Flipboard", "Delete"] {
            XCTAssertTrue(app.buttons[item].exists, item)
        }
        XCTAssertFalse(app.buttons["Flip back to red"].isEnabled, "a red switch with no flip has nothing to undo")
        snapshot("5 Long press on a red switch")
        app.buttons["Edit task…"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 5), "the task editor")
        snapshot("6 Edit task…")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForNonExistence(timeout: 5))

        openMenu(water)
        app.buttons["Edit interval…"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5), "the interval editor")
        XCTAssertTrue(text("Turns red").exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForNonExistence(timeout: 5))

        openMenu(water)
        app.buttons["Flips per interval…"].tap()
        XCTAssertTrue(text("Flips per Interval").waitForExistence(timeout: 5), "the flips editor")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForNonExistence(timeout: 5))

        // Green: Mark done is there; Flip back to red turns it red again.
        openMenu(recycling)
        XCTAssertTrue(app.buttons["Mark done"].exists)
        snapshot("7 Long press on a green switch")
        app.buttons["Flip back to red"].tap()
        // And the red one flips from its menu.
        openMenu(water)
        app.buttons["Flip"].tap()
        sleep(1)
        tab("today")
        XCTAssertTrue(text(recycling).waitForExistence(timeout: 5), "flipped back to red: in Today again")
        XCTAssertFalse(text(water).exists, "flipped from its menu: green, gone from Today")
        snapshot("8 Today after the menu's flips")

        // Delete: off the board at once, with Undo; then for good, and gone from Today.
        tab("flipboard")
        openMenu(recycling)
        app.buttons["Delete"].tap()
        XCTAssertTrue(text("Deleted ‘\(recycling)’").waitForExistence(timeout: 3), "the undo toast")
        XCTAssertTrue(switchTile(recycling).waitForNonExistence(timeout: 3), "the tile goes at once")
        snapshot("9 Deleted, with Undo")
        app.buttons["Deleted ‘\(recycling)’, Undo"].tap()
        XCTAssertTrue(switchTile(recycling).waitForExistence(timeout: 3), "Undo brings it back")
        openMenu(recycling)
        app.buttons["Delete"].tap()
        XCTAssertTrue(switchTile(recycling).waitForNonExistence(timeout: 3))
        tab("today")
        sleep(1)
        XCTAssertFalse(text(recycling).exists, "deleted: gone from Today")
        snapshot("10 Today after Delete")

        // Remove from Flipboard: the last tile goes; the board shows its empty state.
        tab("flipboard")
        openMenu(water)
        app.buttons["Remove from Flipboard"].tap()
        XCTAssertTrue(switchTile(water).waitForNonExistence(timeout: 3))
        snapshot("11 Board after Remove")
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A tile's rocker (its accessibility label is the switch's title).
    private func switchTile(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        button.tap()
        XCTAssertTrue(button.wait(for: \.isSelected, toEqual: true, timeout: 5), "\(name) selected")
    }

    /// Long-presses a tile and waits for its menu.
    private func openMenu(_ title: String) {
        let tile = switchTile(title)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), title)
        tile.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Remove from Flipboard"].waitForExistence(timeout: 3), "the menu opened on \(title)")
    }

    /// Keeps a screenshot in the test result.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
