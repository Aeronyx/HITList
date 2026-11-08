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

    /// Brief 62: shared tasks are rows of your lists, not a screen of their own. With the sample shared lists
    /// (`-seedSharedTasksSample`: in memory, no CloudKit), "Oat milk" (Groceries, due today, P2) is a row in Today
    /// with its list's name and the people marker; completing it from the row shows the Undo toast and Undo brings it
    /// back; tapping it opens its editor; the Inbox sorted by Group gives Groceries a section of its own after the
    /// Groups and before "Ungrouped"; "Lemons" (tomorrow) is on Upcoming.
    func testSharedTasksAreRowsOfYourLists() throws {
        app.launchArguments += ["-seedDemoData", "YES", "-seedSharedTasksSample", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        tab("today")
        let oatMilk = app.cells.containing(NSPredicate(format: "label == %@", "Oat milk")).firstMatch
        XCTAssertTrue(oatMilk.waitForExistence(timeout: 10), "the shared task in Today")
        XCTAssertTrue(oatMilk.descendants(matching: .any)["Shared list Groceries"].exists, "its list's name with the marker")
        snapshot("1 Today with a shared task")

        oatMilk.buttons["Complete task"].tap()
        let undo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Undo")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the Undo toast")
        snapshot("2 Completed, with Undo")
        XCTAssertTrue(oatMilk.waitForNonExistence(timeout: 5), "the row leaves Today")
        undo.tap()
        XCTAssertTrue(oatMilk.waitForExistence(timeout: 5), "Undo brings it back")

        oatMilk.staticTexts["Oat milk"].firstMatch.tap()
        let delete = app.buttons["Delete Task"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the shared task's editor")
        snapshot("3 Its editor")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5), "Cancel closes it")

        tab("inbox")
        XCTAssertTrue(row("Shared list Groceries").waitForExistence(timeout: 5), "a dated shared task is in the Inbox")
        sort(by: "Group")
        app.swipeUp()
        let groceries = element(beginningWith: "Groceries, shared list")
        XCTAssertTrue(groceries.waitForExistence(timeout: 5), "the shared list's section")
        let ungrouped = element(beginningWith: "Ungrouped,")
        if ungrouped.exists { XCTAssertLessThan(groceries.frame.minY, ungrouped.frame.minY, "before Ungrouped") }
        let health = element(beginningWith: "Health,")
        if health.exists { XCTAssertLessThan(health.frame.minY, groceries.frame.minY, "after the Groups") }
        snapshot("4 Inbox by Group")
        app.swipeDown()
        sort(by: "Priority")

        tab("upcoming")
        XCTAssertTrue(row("Lemons").waitForExistence(timeout: 5), "tomorrow's shared task on Upcoming")
        snapshot("5 Upcoming")
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

    /// Brief 63: a tab left for another comes back on its first screen. Browse opened on the Inbox is gone after
    /// a visit to Today; re-tapping the tab on show still takes it back too.
    func testLeavingATabTakesItBackToItsFirstScreen() throws {
        app.launch()
        let inbox = app.buttons["tab-inbox"], today = app.buttons["tab-today"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15))
        inbox.tap()
        XCTAssertTrue(inbox.wait(for: \.isSelected, toEqual: true, timeout: 3))
        let browse = app.buttons["browseButton"].firstMatch
        let browseSearch = app.descendants(matching: .any)["browseSearch"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
        browse.tap()
        XCTAssertTrue(browseSearch.waitForExistence(timeout: 5), "Browse is pushed on the Inbox")
        snapshot("1 Browse on the Inbox")

        today.tap()
        XCTAssertTrue(today.wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertTrue(browseSearch.waitForNonExistence(timeout: 3))
        inbox.tap()
        XCTAssertTrue(inbox.wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertTrue(browse.waitForExistence(timeout: 5), "the Inbox is back at its root, the magnifying glass on show")
        XCTAssertFalse(browseSearch.exists, "Browse is gone")
        snapshot("2 Inbox at its root after Today")

        // Re-tapping the tab on show pops it as before.
        browse.tap()
        XCTAssertTrue(browseSearch.waitForExistence(timeout: 5))
        inbox.tap()
        XCTAssertTrue(browseSearch.waitForNonExistence(timeout: 5), "re-tapping the Inbox pops Browse")
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
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

    /// Brief 61: the Inbox sorts by Priority (flat, the default), Group or Date and Today by Priority or Group,
    /// from the view options' "Sort by"; the screen's name once, as its large title.
    func testSortByOnTheInboxAndToday() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        tab("inbox")
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5), "the large title")
        XCTAssertFalse(element(beginningWith: "Inbox ·").exists, "no \"Inbox · N\" under the title")
        XCTAssertFalse(element(beginningWith: "Work,").exists, "Priority is one flat list: no headers")
        snapshot("1 Inbox by Priority")

        sort(by: "Group")
        let home = element(beginningWith: "Home, 2 tasks"), work = element(beginningWith: "Work, 2 tasks")
        XCTAssertTrue(home.waitForExistence(timeout: 5), "Home's header")
        XCTAssertTrue(work.exists, "Work's header")
        XCTAssertLessThan(home.frame.minY, work.frame.minY, "the sidebar's order (the demo made Home first)")
        snapshot("2 Inbox by Group")
        app.swipeUp()
        let ungrouped = element(beginningWith: "Ungrouped,")
        XCTAssertTrue(ungrouped.waitForExistence(timeout: 5), "the tasks in no Group")
        let health = element(beginningWith: "Health,")
        if health.exists { XCTAssertLessThan(health.frame.minY, ungrouped.frame.minY, "Ungrouped last") }
        snapshot("2b Inbox by Group, the end")
        app.swipeDown()

        sort(by: "Date")
        XCTAssertTrue(element(beginningWith: "Today,").waitForExistence(timeout: 5), "the Today section")
        snapshot("3 Inbox by Date")
        app.swipeUp()
        XCTAssertTrue(element(beginningWith: "No date, 2 tasks").waitForExistence(timeout: 5), "the undated tasks last")
        snapshot("3b Inbox by Date, the end")
        app.swipeDown()

        tab("today")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5), "the large title")
        XCTAssertFalse(element(beginningWith: "Work,").exists, "Priority: no Group headers")
        snapshot("4 Today by Priority")
        sort(by: "Group")
        XCTAssertTrue(element(beginningWith: "Work, 1 task").waitForExistence(timeout: 5), "Work's header on Today")
        snapshot("5 Today by Group")
        app.buttons["viewOptions"].firstMatch.tap()
        app.buttons["Sort by"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Priority"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Date"].exists, "Today sorts by Priority or Group only")
    }

    /// View options → Sort by → `name`.
    private func sort(by name: String) {
        app.buttons["viewOptions"].firstMatch.tap()
        let sortBy = app.buttons["Sort by"].firstMatch
        XCTAssertTrue(sortBy.waitForExistence(timeout: 5), "Sort by in the view options")
        sortBy.tap()
        let choice = app.buttons[name].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), name)
        choice.tap()
        XCTAssertTrue(choice.waitForNonExistence(timeout: 5), "the menu closes")
    }

    /// The first element whose label starts with `prefix` (section headers read "Work, 2 tasks").
    private func element(beginningWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Brief 57: a Group's "+" adds the task to that Group. Brief 61: its name once, as the large title.
    func testPlusOnAGroupAddsToIt() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        let workRow = app.buttons["Work, 2"].firstMatch
        XCTAssertTrue(workRow.waitForExistence(timeout: 5))
        workRow.tap()
        XCTAssertTrue(app.navigationBars["Work"].waitForExistence(timeout: 5), "Work pushed, its name the title")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Work ·")).firstMatch.exists,
                       "no second \"Work\" under the title")
        snapshot("1 Work")

        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.wait(for: \.isHittable, toEqual: true, timeout: 5))
        plus.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickAddTitle"].firstMatch.waitForExistence(timeout: 5))
        app.typeText("Draft the agenda ")
        snapshot("2 Card on Work")
        app.buttons["quickAddSave"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Draft the agenda")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the new task is in Work (undated: a note in its Group)")
        snapshot("3 Work after the add")
    }

    /// Brief 61: Browse puts its Groups first, above Shared Tasks, and the saved filters as chips under the
    /// search field (no Filters section); the field takes a filter query: "#Work" lists Work's tasks, and "Save
    /// as filter…" names it as a new filter, which joins the chips.
    func testBrowseTakesFiltersInTheSearchField() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
        let focus = app.buttons["Focus filter"].firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5), "the default filters as chips under the field")
        XCTAssertTrue(app.buttons["newFilterChip"].exists, "the + chip")
        let work = app.buttons["Work, 2"].firstMatch
        let shared = app.descendants(matching: .any)["browse-shared-tasks"].firstMatch
        XCTAssertTrue(work.exists && shared.exists)
        XCTAssertLessThan(work.frame.minY, shared.frame.minY, "Groups above Shared Tasks")
        XCTAssertGreaterThan(work.frame.minY, focus.frame.minY, "the chips above the Groups")
        XCTAssertTrue(app.staticTexts["A task lives in one Group: Work, Home, a project."].exists)
        snapshot("1 Browse")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["A label is a tag any task can carry: @waiting, @errands."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Filters"].exists, "no Filters section")
        app.swipeDown()

        // A chip opens its filter's list.
        focus.tap()
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5), "the chip opens Focus")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))

        // A query in the search field filters by it.
        let field = app.textFields.firstMatch
        field.tap()
        app.typeText("#Work")
        let save = app.buttons["saveSearchAsFilter"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save as filter… under the field")
        XCTAssertTrue(row("Reply to Sam about the lease").waitForExistence(timeout: 5))
        XCTAssertTrue(row("Finish the quarterly report").exists)
        XCTAssertFalse(row("Buy groceries").exists, "only Work's tasks")
        snapshot("2 Search #Work")

        save.tap()
        XCTAssertTrue(app.navigationBars["New Filter"].waitForExistence(timeout: 5)
                      || app.staticTexts["New Filter"].waitForExistence(timeout: 1), "the filter editor, to name it")
        app.typeText("Work only")
        snapshot("3 Name the filter")
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["New Filter"].waitForNonExistence(timeout: 5), "the editor closes")

        // The new filter joins the chips; plain words still search titles and notes.
        app.buttons["Clear"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Work only filter"].waitForExistence(timeout: 5), "the saved filter's chip")
        snapshot("4 Browse with the new filter")
        field.tap()
        app.typeText("groceries")
        XCTAssertTrue(row("Buy groceries").waitForExistence(timeout: 5), "text searches titles")
        XCTAssertFalse(save.exists, "no Save as filter… for plain words")
    }

    /// A task row whose label contains `title`.
    private func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Brief 57: a Group dragged to a new place in Browse stays there (long-press, then drag).
    func testReorderGroupsInBrowse() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        let health = app.buttons["Health, 1"].firstMatch, home = app.buttons["Home, 2"].firstMatch
        XCTAssertTrue(health.waitForExistence(timeout: 5) && home.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(health.frame.minY, home.frame.minY, "Health starts below Home")
        snapshot("1 Browse before")
        health.press(forDuration: 1.0, thenDragTo: home, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertLessThan(health.frame.minY, home.frame.minY, "Health moved above Home")
        snapshot("2 Browse after")
    }

    /// Brief 57: deleting a Group with tasks asks first and says where its tasks go; Cancel keeps it.
    func testDeletingAGroupWithTasksAsks() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        let work = app.buttons["Work, 2"].firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.press(forDuration: 1.2)
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the Group's menu")
        delete.tap()
        let message = app.staticTexts["Its 2 open tasks move to the Inbox."]
        XCTAssertTrue(message.waitForExistence(timeout: 5), "the question says where the tasks go")
        snapshot("1 Delete Work?")
        // A popover on iPhone: tapping outside it is its Cancel.
        let outside = app.otherElements["PopoverDismissRegion"].firstMatch
        if outside.exists { outside.tap() } else { app.buttons["Cancel"].firstMatch.tap() }
        XCTAssertTrue(message.waitForNonExistence(timeout: 5))
        XCTAssertTrue(work.exists, "Cancel keeps the Group")
    }

    /// Keeps a screenshot in the test result.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
