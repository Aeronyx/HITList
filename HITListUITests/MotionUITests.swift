import XCTest

/// Brief 75 (round 17): walks every iPhone transition slowly enough to film, one family per test, so a session can
/// record each with `xcrun simctl io <udid> recordVideo` and read the frames. Skipped in ordinary runs; a recording
/// run sets `TEST_RUNNER_HITLIST_MOTION=1`:
///
///     TEST_RUNNER_HITLIST_MOTION=1 xcodebuild test-without-building -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,name=HITList-75' -only-testing:HITListUITests/MotionUITests/testQuickAddCard
///
/// Each step prints "MOTION <step> <unix time>" to the test log, to find the step in the film. The walks look; they do
/// not judge.
final class MotionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_MOTION"] == "1",
                          "the motion walk runs only when filming (TEST_RUNNER_HITLIST_MOTION=1)")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "motion-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 20))
        pause(2)
    }

    func testTabsAndBrowse() {
        for name in ["inbox", "today", "upcoming", "flipboard", "today"] {
            mark("tab \(name)")
            app.buttons["tab-\(name)"].tap()
            pause(1.2)
        }
        mark("push browse")
        app.buttons["tab-inbox"].tap()
        pause(1)
        element("browseButton").tap()
        pause(1.5)
        mark("back from browse")
        app.navigationBars.buttons.firstMatch.tap()
        pause(1.5)
        mark("push browse again")
        element("browseButton").tap()
        pause(1.2)
        let work = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Work")).firstMatch
        if work.waitForExistence(timeout: 3) {
            mark("push group")
            work.tap()
            pause(1.5)
        }
        mark("tab today from a pushed screen")
        app.buttons["tab-today"].tap()
        pause(1.2)
        mark("tab inbox returns to its first screen")
        app.buttons["tab-inbox"].tap()
        pause(1.5)
    }

    func testQuickAddCard() {
        mark("open card")
        element("quickAddButton").tap()
        waitForKeyboard()
        pause(1.5)
        mark("type with highlights")
        for word in ["Call ", "Sam ", "tom ", "5pm ", "p1 "] {
            app.typeText(word)
            pause(0.5)
        }
        pause(1)
        mark("ask discard")
        app.buttons["Close"].firstMatch.tap()
        pause(1.5)
        mark("keep editing")
        element("quickAddTitle").tap()
        pause(1.5)
        mark("ask discard again")
        app.buttons["Close"].firstMatch.tap()
        pause(1.2)
        mark("discard")
        element("quickAddDiscard").tap()
        pause(2)

        mark("open card to save")
        element("quickAddButton").tap()
        waitForKeyboard()
        pause(1.2)
        app.typeText("Motion test")
        pause(0.8)
        mark("save")
        element("quickAddSave").tap()
        pause(2)

        mark("open card, close empty")
        element("quickAddButton").tap()
        pause(1.5)
        app.buttons["Close"].firstMatch.tap()
        pause(1.5)
    }

    func testQuickAddChipsAndCards() {
        element("quickAddButton").tap()
        waitForKeyboard()
        app.typeText("Chip walk")
        pause(1)
        for chip in ["quickAddDateChip", "quickAddPriorityChip", "quickAddReminderChip", "quickAddGroupChip"] {
            mark("open \(chip)")
            element(chip).tap()
            pause(1.4)
            mark("close \(chip)")
            // A tap on the card's title closes the card and gives the keyboard back.
            element("quickAddTitle").tap()
            pause(1.4)
        }
        mark("plus menu")
        element("quickAddPlus").tap()
        pause(1.4)
        let labels = app.buttons["Labels"].firstMatch
        if labels.waitForExistence(timeout: 2) {
            mark("reveal labels")
            labels.tap()
            pause(1.6)
            element("quickAddTitle").tap()
            pause(1.2)
        }
        mark("pick priority")
        element("quickAddPriorityChip").tap()
        pause(1.2)
        let p2 = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Priority 2")).firstMatch
        if p2.waitForExistence(timeout: 2) { p2.tap() }
        pause(1.5)
        app.buttons["Close"].firstMatch.tap()
        pause(1)
        let discard = element("quickAddDiscard")
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        pause(1.5)
    }

    func testEditor() {
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", "Buy groceries")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        mark("open editor")
        row.tap()
        pause(2)
        for chip in ["popoutDateRow", "popoutPriorityChip", "popoutReminderChip", "popoutLabelsChip", "popoutRepeatChip"] {
            let button = element(chip)
            guard button.waitForExistence(timeout: 2) else { mark("missing \(chip)"); continue }
            mark("open \(chip)")
            button.tap()
            pause(1.4)
            mark("close \(chip)")
            // Outside the card: the editor's title card.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            pause(1.4)
        }
        mark("description pill")
        let description = element("editorDescriptionPill")
        if description.exists { description.tap(); pause(1.5) }
        mark("editor title keyboard")
        element("editorTitle").tap()
        pause(1.5)
        mark("close editor")
        app.buttons["Close"].firstMatch.tap()
        pause(1)
        let discard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch
        if discard.waitForExistence(timeout: 1.5) { discard.tap() }
        pause(2)
        mark("open editor and swipe down")
        row.tap()
        pause(2)
        app.swipeDown(velocity: .fast)
        pause(2)
    }

    func testCompletion() {
        let check = app.buttons.matching(NSPredicate(format: "label == %@", "Complete task")).firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        mark("complete")
        check.tap()
        pause(1.2)
        mark("undo")
        let undo = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Undo")).firstMatch
        if undo.waitForExistence(timeout: 2) { undo.tap() }
        pause(2)
        mark("complete and let the toast expire")
        check.tap()
        pause(7)
        mark("complete two")
        check.tap()
        pause(0.5)
        app.buttons.matching(NSPredicate(format: "label == %@", "Complete task")).firstMatch.tap()
        pause(1.5)
        mark("swipe toast away")
        let toast = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Undo")).firstMatch
        if toast.waitForExistence(timeout: 2) { toast.swipeDown() }
        pause(2)
        mark("editor check")
        let row = app.staticTexts.firstMatch
        _ = row
        let gym = app.staticTexts.matching(NSPredicate(format: "label == %@", "Reply to Sam about the lease")).firstMatch
        if gym.waitForExistence(timeout: 2) {
            gym.tap()
            pause(1.5)
            element("popoutCheckbox").tap()
            pause(2.5)
        }
    }

    func testProfileWhatsNewSettings() {
        element("browseButton").tap()
        pause(1.2)
        mark("profile menu")
        element("browse-profile").tap()
        pause(1.5)
        mark("whats new")
        element("profile-menu-whatsnew").tap()
        pause(2)
        mark("earlier versions")
        element("whatsNewEarlier").tap()
        pause(1.5)
        mark("whats new done")
        element("whatsNewDone").tap()
        pause(1.5)
        mark("settings")
        let gear = element("browse-settings-row")
        if gear.waitForExistence(timeout: 2) { gear.tap() } else { element("settingsButton").tap() }
        pause(2)
        mark("settings done")
        let done = app.buttons["Done"].firstMatch
        if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
        pause(1.5)
        mark("view options menu")
        app.buttons["tab-today"].tap()
        pause(1)
        element("viewOptions").tap()
        pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause(1.2)
    }

    func testFlipboard() {
        app.buttons["tab-flipboard"].tap()
        pause(1.5)
        let tile = app.descendants(matching: .any).matching(identifier: "flipSwitchTile").firstMatch
        if tile.waitForExistence(timeout: 3) {
            mark("flip")
            tile.tap()
            pause(1.5)
            mark("flip back")
            tile.tap()
            pause(1.5)
        }
        let add = element("addSwitchTile")
        if add.waitForExistence(timeout: 3) {
            mark("switch card")
            add.tap()
            waitForKeyboard()
            pause(1.5)
            app.typeText("Water the ferns")
            pause(0.8)
            mark("save switch")
            element("switchSave").tap()
            pause(2.5)
            mark("switch card close")
            add.tap()
            pause(1.5)
            element("switchClose").tap()
            pause(1.5)
        }
        if tile.exists {
            mark("switch menu")
            tile.press(forDuration: 1.0)
            pause(1.5)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            pause(1.2)
        }
    }

    /// The screens at rest, for overlays against another build (brief 75: nothing may move at rest). Pin the status
    /// bar first (`xcrun simctl status_bar <udid> override --time 9:41`).
    func testRestScreens() {
        for name in ["today", "inbox", "upcoming", "flipboard"] {
            app.buttons["tab-\(name)"].tap()
            pause(2)
            still(name)
        }
        app.buttons["tab-today"].tap()
        pause(1.5)
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", "Buy groceries")).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            pause(2.5)
            still("editor")
            app.buttons["Close"].firstMatch.tap()
            pause(2)
        }
        element("quickAddButton").tap()
        waitForKeyboard()
        pause(2.5)
        still("quick-add")
    }

    private func still(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// A fresh simulator's keyboard shows Apple's one-time "slide to type" tip over itself; it is not ours.
    private func waitForKeyboard() {
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        let tip = app.buttons["Continue"].firstMatch
        if tip.waitForExistence(timeout: 1.5) { tip.tap(); pause(1) }
    }

    private func mark(_ step: String) {
        print(String(format: "MOTION %@ %.3f", step, Date().timeIntervalSince1970))
    }

    private func pause(_ seconds: TimeInterval = 1) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
