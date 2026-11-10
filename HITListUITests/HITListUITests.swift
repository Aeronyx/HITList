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

    /// Brief 65 (George, 0.8.1: clicking "No date" in the editor did nothing, and the title did not "respect
    /// quickadd"). The date row is the editor's way to a date: an undated task's "No date" opens the date card at
    /// once, Tomorrow closes it and the row reads Tomorrow. The title reads quick-add phrases: "Call mom" with
    /// " tomorrow 5pm p1" typed at its end shows tomorrow 5 PM and P1 in the rows below, and Confirm saves them
    /// with "Call mom" as the title.
    func testTheEditorsDateRowAndQuickAddTitle() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        tab("inbox")
        addFromTheCard("Pay rent")
        addFromTheCard("Call mom")

        // The date row: "No date" → the date card → Tomorrow.
        openEditor("Pay rent")
        let dateRow = app.buttons["popoutDateRow"].firstMatch
        XCTAssertTrue(dateRow.waitForExistence(timeout: 5), "the editor's date row")
        XCTAssertTrue(dateRow.label.contains("No date"), dateRow.label)
        snapshot("1 Editor with no date")
        dateRow.tap()
        let tomorrow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tomorrow, ")).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3), "the date card, at once")
        snapshot("2 The date card")
        tomorrow.tap()
        XCTAssertTrue(tomorrow.waitForNonExistence(timeout: 5), "picking a day closes the card")
        XCTAssertTrue(dateRow.label.hasPrefix("Tomorrow"), "the row shows the day: \(dateRow.label)")
        snapshot("3 The row reads Tomorrow")
        closeEditor()

        // The title: phrases typed at its end light up and fill the rows; Confirm saves them.
        openEditor("Call mom")
        let title = app.descendants(matching: .any)["editorTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard in the title")
        app.typeText(" tomorrow 5pm p1 ")
        XCTAssertTrue(dateRow.label.hasPrefix("Tomorrow"), "the date row reads the typed day: \(dateRow.label)")
        XCTAssertTrue(dateRow.label.contains("5"), "and the typed time: \(dateRow.label)")
        let priority = app.buttons["popoutPriorityChip"].firstMatch
        XCTAssertTrue(priority.label.contains("P1"), "the priority pill fills: \(priority.label)")
        snapshot("4 Typed tomorrow 5pm p1")
        app.buttons["editorConfirm"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Confirm closes the editor")
        snapshot("5 Saved")

        openEditor("Call mom")
        XCTAssertEqual(title.value as? String, "Call mom", "the phrases left the title")
        XCTAssertTrue(dateRow.label.hasPrefix("Tomorrow"), dateRow.label)
        XCTAssertTrue(app.buttons["popoutPriorityChip"].firstMatch.label.contains("P1"))
        snapshot("6 Reopened")
        closeEditor()

        // With the keyboard in the title, the date row still opens its card at once, and a day picked there
        // replaces the day typed in the title.
        openEditor("Pay rent")
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(" in 3 days p2 ")
        XCTAssertFalse(dateRow.label.hasPrefix("Tomorrow"), "the typed day shows: \(dateRow.label)")
        snapshot("7 Typed in 3 days p2")
        dateRow.tap()
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today, ")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 3), "the date card, with the keyboard up")
        snapshot("8 The date card over the keyboard")
        today.tap()
        XCTAssertTrue(today.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dateRow.label.hasPrefix("Today"), "the picked day: \(dateRow.label)")
        XCTAssertFalse((title.value as? String ?? "").contains("in 3 days"), "the typed day left the title: \(title.value ?? "")")
        snapshot("9 Picked Today")
        app.buttons["editorConfirm"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        openEditor("Pay rent")
        XCTAssertEqual(title.value as? String, "Pay rent")
        XCTAssertTrue(dateRow.label.hasPrefix("Today"), dateRow.label)
        XCTAssertTrue(app.buttons["popoutPriorityChip"].firstMatch.label.contains("P2"))
        closeEditor()
    }

    /// Adds an undated task from the current list's card and waits for the card to go.
    private func addFromTheCard(_ title: String) {
        app.buttons["quickAddButton"].firstMatch.tap()
        let field = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card's title field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(title)
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the card closes after Add")
    }

    private func openEditor(_ title: String) {
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), title)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 5), "the editor")
        XCTAssertTrue(app.buttons["popoutDateRow"].firstMatch.waitForExistence(timeout: 5))
    }

    private func closeEditor() {
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForNonExistence(timeout: 5), "the editor closes")
    }

    /// Briefs 62 and 64: shared tasks are tasks of yours in one forced Group, Shared Tasks. With the sample shared lists
    /// (`-seedSharedTasksSample`: in memory, no CloudKit), "Oat milk" (Sam and Alex's, due today, P2) is a row in Today
    /// with their faces where labels go and "Shared Tasks" where a Group sits; completing it shows Undo and Undo brings
    /// it back; it opens in the editor you know. The Inbox sorted by Group gives Shared Tasks one section after your
    /// Groups. Browse lists it last under Groups; its screen has a section per set of people and Sharing… in its view
    /// options. `#Shared` in quick add puts a task there.
    func testSharedTasksAreOneGroup() throws {
        app.launchArguments += ["-seedDemoData", "YES", "-seedSharedTasksSample", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        tab("today")
        let oatMilk = app.cells.containing(NSPredicate(format: "label == %@", "Oat milk")).firstMatch
        XCTAssertTrue(oatMilk.waitForExistence(timeout: 10), "the shared task in Today")
        XCTAssertTrue(oatMilk.staticTexts["Shared Tasks"].exists, "Shared Tasks where a Group sits")
        XCTAssertTrue(oatMilk.descendants(matching: .any)["Shared with Sam and Alex"].exists, "their faces where labels go")
        snapshot("1 Today with a shared task")

        oatMilk.buttons["Complete task"].tap()
        let undo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Undo")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the Undo toast")
        XCTAssertTrue(oatMilk.waitForNonExistence(timeout: 5), "the row leaves Today")
        undo.tap()
        XCTAssertTrue(oatMilk.waitForExistence(timeout: 5), "Undo brings it back")

        oatMilk.staticTexts["Oat milk"].firstMatch.tap()
        let editor = app.descendants(matching: .any)["sharedEditor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "the shared task's editor")
        XCTAssertTrue(app.buttons["Group: Shared Tasks"].exists || element(beginningWith: "Group: Shared Tasks").exists,
                      "its Group row reads Shared Tasks")
        snapshot("2 Its editor")
        XCTAssertTrue(app.descendants(matching: .any)["editorPeopleRow"].exists, "the people row")
        XCTAssertTrue(app.descendants(matching: .any)["editorConfirm"].firstMatch.waitForExistence(timeout: 3), "Confirm, as yours")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "× closes it")

        tab("inbox")
        sort(by: "Group")
        app.swipeUp()
        let shared = element(beginningWith: "Shared Tasks, ")
        XCTAssertTrue(shared.waitForExistence(timeout: 5), "Shared Tasks' one section")
        let ungrouped = element(beginningWith: "Ungrouped,")
        if ungrouped.exists { XCTAssertLessThan(shared.frame.minY, ungrouped.frame.minY, "before Ungrouped") }
        let health = element(beginningWith: "Health,")
        if health.exists { XCTAssertLessThan(health.frame.minY, shared.frame.minY, "after your Groups") }
        snapshot("3 Inbox by Group")
        app.swipeDown()
        sort(by: "Priority")

        // Browse: Shared Tasks last under Groups; no Shared Tasks section and no shared lists of their own.
        app.buttons["browseButton"].firstMatch.tap()
        let group = app.buttons["browse-shared-tasks"].firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5), "Shared Tasks under Groups")
        let last = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Health")).firstMatch
        if last.exists { XCTAssertLessThan(last.frame.minY, group.frame.minY, "after the last Group of yours") }
        XCTAssertFalse(app.buttons["browse-shared-list"].exists, "no shared lists of their own")
        snapshot("4 Browse")
        group.tap()
        XCTAssertTrue(app.navigationBars["Shared Tasks"].waitForExistence(timeout: 5), "the Group's screen, its name once")
        XCTAssertTrue(element(beginningWith: "Shared with Sam and Alex").waitForExistence(timeout: 5), "Sam and Alex's set")
        XCTAssertTrue(element(beginningWith: "Only you").exists, "the set nobody joined yet")
        snapshot("5 The Shared Tasks Group")

        app.buttons["viewOptions"].firstMatch.tap()
        let sharing = app.buttons["sharingButton"].firstMatch
        XCTAssertTrue(sharing.waitForExistence(timeout: 5), "Sharing… in the view options")
        sharing.tap()
        XCTAssertTrue(app.staticTexts["Sharing"].waitForExistence(timeout: 5), "the Sharing sheet")
        XCTAssertTrue(app.descendants(matching: .any)["sharedTasksSwitch"].exists, "the switch")
        snapshot("6 Sharing")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sharing"].waitForNonExistence(timeout: 5))

        // Quick add's #Shared, from the Group's own "+": the task lands here.
        app.buttons["quickAddButton"].firstMatch.tap()
        let title = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("Bring snacks tomorrow #Shared ")
        XCTAssertTrue(app.buttons["Group: Shared Tasks"].firstMatch.waitForExistence(timeout: 5), "the chip names Shared Tasks")
        snapshot("7 Quick add #Shared")
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row("Bring snacks").waitForExistence(timeout: 5), "in Shared Tasks")
        snapshot("8 Added")
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

    /// Briefs 59 and 72 on iPhone, from the demo week's two loose switches (both red: never flipped). A switch is
    /// never a task by default: neither is in Today, the Inbox or Upcoming. "Overdue becomes task" on one (from its
    /// card) brings it to Today as today's task; flipping it from its Today row turns it green and it leaves. A long
    /// press on a tile opens the switch's menu and every item works; Delete takes a switch off the board at once,
    /// with Undo.
    func testFlipboardSwitchesStayOnTheBoardUnlessTheyOptIn() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        let water = "Water the plants", recycling = "Take out the recycling"

        // Today, the Inbox and Upcoming: no switch, red or green, loose or on a board.
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        app.buttons["tab-today"].tap()
        XCTAssertTrue(text("Buy groceries").waitForExistence(timeout: 10))
        for title in [water, recycling, "Take meds", "Read 20 minutes", "Clean the bathroom"] {
            XCTAssertFalse(text(title).exists, "\(title) stays on the Flipboard")
        }
        snapshot("1 Today: no switches")
        tab("inbox")
        sleep(1)
        XCTAssertFalse(text(water).exists)
        XCTAssertFalse(text(recycling).exists)
        tab("upcoming")
        sleep(1)
        XCTAssertFalse(text(water).exists)
        XCTAssertFalse(text(recycling).exists)

        // The board: a long press opens the menu (red: Flip first; nothing to flip back).
        tab("flipboard")
        openMenu(water)
        for item in ["Flip", "Edit task…", "Edit switch…", "Remove from Flipboard", "Delete"] {
            XCTAssertTrue(app.buttons[item].exists, item)
        }
        XCTAssertFalse(app.buttons["Flip back to red"].isEnabled, "a red switch with no flip has nothing to undo")
        snapshot("2 Long press on a red switch")
        app.buttons["Edit task…"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 5), "the task editor")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForNonExistence(timeout: 5))

        // Edit switch…: the switch card, filled in; Overdue becomes task on.
        openMenu(water)
        app.buttons["Edit switch…"].tap()
        let switchName = app.descendants(matching: .any)["switchName"].firstMatch
        XCTAssertTrue(switchName.waitForExistence(timeout: 5), "the switch card")
        let optIn = app.switches["switchOverdueToggle"].exists ? app.switches["switchOverdueToggle"]
            : app.descendants(matching: .any)["switchOverdueToggle"].firstMatch
        XCTAssertTrue(optIn.waitForExistence(timeout: 3), "Overdue becomes task")
        optIn.tap()
        snapshot("3 The switch card, Overdue becomes task on")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(switchName.waitForNonExistence(timeout: 5))

        // Opted in, it is today's task, never overdue; the other switch still isn't.
        tab("today")
        XCTAssertTrue(text(water).waitForExistence(timeout: 5), "opted in: in Today")
        XCTAssertFalse(text(recycling).exists, "not opted in: on the Flipboard only")
        XCTAssertFalse(text("Overdue").exists)
        snapshot("4 Today: the opted-in switch")
        let row = app.cells.containing(NSPredicate(format: "label == %@", water)).firstMatch
        row.buttons["Flip switch"].tap()
        XCTAssertTrue(text("Flipped ‘\(water)’").waitForExistence(timeout: 3), "the toast says Flipped")
        XCTAssertTrue(text(water).waitForNonExistence(timeout: 8), "green: gone from Today")
        snapshot("5 Flipped from its Today row")

        // Green: Mark done is there; Flip back to red brings it back to Today (it opted in).
        tab("flipboard")
        openMenu(water)
        XCTAssertTrue(app.buttons["Mark done"].exists)
        app.buttons["Flip back to red"].tap()
        // And the other flips from its menu.
        openMenu(recycling)
        app.buttons["Flip"].tap()
        sleep(1)
        tab("today")
        XCTAssertTrue(text(water).waitForExistence(timeout: 5), "flipped back to red: in Today again")
        XCTAssertFalse(text(recycling).exists)

        // Delete: off the board at once, with Undo; then for good.
        tab("flipboard")
        openMenu(recycling)
        app.buttons["Delete"].tap()
        XCTAssertTrue(text("Deleted ‘\(recycling)’").waitForExistence(timeout: 3), "the undo toast")
        XCTAssertTrue(switchTile(recycling).waitForNonExistence(timeout: 3), "the tile goes at once")
        app.buttons["Deleted ‘\(recycling)’, Undo"].tap()
        XCTAssertTrue(switchTile(recycling).waitForExistence(timeout: 3), "Undo brings it back")
        openMenu(recycling)
        app.buttons["Delete"].tap()
        XCTAssertTrue(switchTile(recycling).waitForNonExistence(timeout: 3))

        // Remove from Flipboard: the tile goes, and Today with it.
        openMenu(water)
        app.buttons["Remove from Flipboard"].tap()
        XCTAssertTrue(switchTile(water).waitForNonExistence(timeout: 3))
        snapshot("6 Board after Remove: the Switchboards stay")
        XCTAssertTrue(app.buttons["Before Bed"].exists || text("Before Bed").exists)
    }

    /// Brief 69 on iPhone: a switch added from the small card in a few seconds, its interval typed and then
    /// picked from the quick choices; the new tile on the board; its interval changed from the tile's menu with
    /// the same card; and a tap away with a name typed asking Discard inside the card.
    func testAddingAndEditingASwitchFromTheCard() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-flipboard"].waitForExistence(timeout: 15))
        tab("flipboard")
        let empty = app.buttons["Add a Switch"], tile = app.buttons["addSwitchTile"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5) || tile.exists, "a way to add a switch")
        (empty.exists ? empty : tile).tap()

        let name = app.descendants(matching: .any)["switchName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the name has the keyboard at once")
        snapshot("1 Card empty")
        app.typeText("Water the plants every 3 days ")
        let threeDays = choice("3 days"), weekly = choice("Weekly")
        XCTAssertTrue(threeDays.wait(for: \.isSelected, toEqual: true, timeout: 3), "the typed repeat lights 3 days")
        snapshot("2 Card typed")
        weekly.tap()
        XCTAssertTrue(weekly.wait(for: \.isSelected, toEqual: true, timeout: 3), "a quick choice")
        XCTAssertTrue((name.value as? String ?? "").contains("every week"), "the typed phrase follows the choice")
        threeDays.tap()
        XCTAssertTrue(threeDays.wait(for: \.isSelected, toEqual: true, timeout: 3))
        snapshot("3 Card with a chosen interval")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "the card goes after Add")
        XCTAssertTrue(switchTile("Water the plants").waitForExistence(timeout: 5), "the new switch on the board")
        XCTAssertTrue(text("every 3 days").exists)
        snapshot("4 The new tile")

        // Its tile's menu: the same card, filled in; 2 weeks, saved.
        openMenu("Water the plants")
        app.buttons["Edit switch…"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the card, editing")
        XCTAssertTrue(choice("3 days").isSelected, "filled in")
        choice("2 weeks").tap()
        snapshot("5 Editing its interval")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(text("every 2 weeks").waitForExistence(timeout: 5), "the interval changed from its tile")

        // A tap away with a name typed asks inside the card; Discard throws it away.
        app.buttons["addSwitchTile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.typeText("Floss")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["switchDiscardRow"].waitForExistence(timeout: 3), "Discard, in the card")
        snapshot("6 Discard inside the card")
        app.buttons["switchDiscard"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertFalse(switchTile("Floss").exists)
    }

    private func choice(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)["switchChoice-\(title)"].firstMatch
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

    /// George, 2026-11-08: the lights on the Flipboard's switches "slowly float in from the left side of the screen"
    /// whenever a friend taps the Flipboard tab on his iPhone, and "all switches should be the same width and height".
    /// With a switch of every look on the board (`-seedFlipboardStates`: overdue, chargers, green, a long title):
    /// Today → Flipboard, with a burst of screenshots through the first second and a half (the lights sit on their
    /// switches from the first frame; an overdue one used to drift in across its title), and every tile, the + tile
    /// included, is one size.
    func testFlipboardLightsStayOnTheirSwitches() throws {
        app.launchArguments += ["-seedDemoData", "-seedFlipboardStates"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-flipboard"].waitForExistence(timeout: 15))
        // The first visit seeds a switch of every look (overdue, chargers, green, a long title).
        tab("flipboard")
        XCTAssertTrue(switchTile("Clean the litter box").waitForExistence(timeout: 10))
        sleep(1)
        tab("today")
        XCTAssertTrue(text("Buy groceries").waitForExistence(timeout: 10))
        sleep(1)
        let start = Date()
        app.buttons["tab-flipboard"].tap()
        var shots = 0
        while Date().timeIntervalSince(start) < 1.6 {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = String(format: "tab switch +%04.0f ms", Date().timeIntervalSince(start) * 1000)
            shot.lifetime = .keepAlways
            add(shot)
            shots += 1
        }
        XCTAssertGreaterThan(shots, 3)

        // Every switch and the + tile: one width, one height.
        let tiles = app.descendants(matching: .any).matching(identifier: "flipSwitchTile").allElementsBoundByIndex
        XCTAssertEqual(tiles.count, 15, "the demo's two loose switches, its seven on two Switchboards, and the six seeded")
        let size = try XCTUnwrap(tiles.first).frame.size
        for tile in tiles {
            XCTAssertEqual(tile.frame.width, size.width, accuracy: 0.5, "every switch is as wide as the first")
            XCTAssertEqual(tile.frame.height, size.height, accuracy: 0.5, "every switch is as tall as the first")
        }
        let add = app.buttons["addSwitchTile"]
        XCTAssertEqual(add.frame.width, size.width, accuracy: 0.5, "the + tile too")
        XCTAssertEqual(add.frame.height, size.height, accuracy: 0.5, "the + tile too")
        snapshot("Every tile one size")
    }
}
