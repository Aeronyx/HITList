import XCTest

/// Brief 93's look at every screen, the way George looks after a build: every main screen, every card and picker,
/// Settings' first screen and each page, the empty states, a title that wraps, a task with every kind of meta, and
/// Dynamic Type a step either side, on whatever simulator it runs on (an iPhone's four tabs, or the iPad's and the
/// Duo's sidebar). It looks; it does not judge: a missing element is noted and the walk goes on. Skipped in ordinary
/// runs; run it on its own:
///
///     TEST_RUNNER_HITLIST_QA=1 xcodebuild test-without-building -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath build.noindex/sim \
///       -only-testing:HITListUITests/QASweepUITests -resultBundlePath build.noindex/qa.xcresult
///     xcrun xcresulttool export attachments --path build.noindex/qa.xcresult --output-path build.noindex/qa
///
/// `TEST_RUNNER_HITLIST_QA_LANDSCAPE=1` turns the device on its side first.
final class QASweepUITests: XCTestCase {
    private var app: XCUIApplication!
    private var number = 0

    /// Wraps on every iPhone and in the iPad's list.
    static let longTitle = "Ask the landlord whether the radiator in the back bedroom can be bled before the cold weather arrives"
    /// Date, time, repeat, reminder, label, Group; sub-tasks are added in the editor.
    static let metaLine = "Frame the print tomorrow 5pm p1 #Work @errands every week !15mb"
    static let metaTitle = "Frame the print"

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_QA"] == "1",
                          "brief 93's look runs only on demand (TEST_RUNNER_HITLIST_QA=1)")
        continueAfterFailure = true
        app = XCUIApplication()
        if ProcessInfo.processInfo.environment["HITLIST_QA_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        } else {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: The walks (each launches on its own store, so one that stalls leaves the others their pictures)

    /// Inbox, Today, Upcoming and the Flipboard, with a title that wraps and a task with every kind of meta.
    func test1Lists() throws {
        launch(seed: true)
        addTheTwoTasks()
        let names = isPhoneShell ? ["inbox", "today", "upcoming", "flipboard"]
                                 : ["inbox", "today", "upcoming", "flipboard", "Completed", "Work", "Shared Tasks", "errands"]
        for name in names {
            go(name)
            snap("list \(name)")
            snapScrolled("list \(name)")
        }
    }

    /// Quick add empty and typed, each of its cards, its + menu and its Discard question; the Inbox's view options
    /// and Review Inbox.
    func test2QuickAddAndReview() throws {
        launch(seed: true)
        quickAddWalk()
        go("inbox")
        let options = app.buttons["viewOptions"].firstMatch
        guard options.waitForExistence(timeout: 3) else { return note("no view options") }
        options.tap()
        pause()
        snap("Inbox view options")
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
        if review.waitForExistence(timeout: 3) {
            review.tap()
            pause(1.2)
            snap("Review Inbox")
            let card = element("reviewCard")
            if card.exists {
                card.swipeLeft()
                pause(0.8)
                snap("Review Inbox, deleted toast")
                tapIfExists(app.buttons["reviewUndo"].firstMatch)
                pause()
            }
            let pick = app.buttons["reviewPickDate"].firstMatch
            if pick.waitForExistence(timeout: 2) {
                pick.tap()
                pause(1.0)
                snap("Review Inbox, Pick a date")
                dismissPopover()
            }
            tapIfExists(app.buttons["Done"].firstMatch)
            pause()
        } else { dismissMenu(); note("no Review item") }
        let more = app.buttons["screenMenu"].firstMatch
        if more.exists, more.isHittable {
            more.tap()
            pause()
            snap("Inbox … menu")
            dismissMenu()
        }
    }

    /// The editor, each of its cards and its … menu; a task with every kind of meta; a title that wraps.
    func test3Editor() throws {
        launch(seed: true)
        addTheTwoTasks()
        editorWalk()
    }

    /// Browse and what it opens, the profile menu, search with a query; Completed after a completion.
    func test4BrowseAndSearch() throws {
        launch(seed: true)
        go("today")
        openTask("Buy groceries")
        let check = element("popoutCheckbox")
        if check.waitForExistence(timeout: 3) {
            check.tap()
            pause(0.6)
            snap("Completion toast")
        }
        pause(4)
        guard isPhoneShell else {
            go("Completed")
            snap("Completed")
            let profile = app.buttons["profile-badge"].firstMatch.exists ? app.buttons["profile-badge"].firstMatch : app.buttons["profile-menu"].firstMatch
            if profile.exists { profile.tap(); pause(); snap("Profile menu"); dismissMenu() }
            return
        }
        go("inbox")
        openBrowse()
        snap("Browse")
        snapScrolled("Browse")
        let profile = app.buttons["browse-profile"].firstMatch
        if profile.waitForExistence(timeout: 3) {
            profile.tap()
            pause()
            snap("Profile menu")
            dismissMenu()
        }
        openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Work")).firstMatch, "A Group, Work")
        openFromBrowse(element("browse-shared-tasks"), "The Shared Tasks Group")
        openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch, "Completed")
        openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "errands")).firstMatch, "A label, errands")
        openFromBrowse(app.buttons["Focus filter"].firstMatch, "A filter, Focus")
        search("lease")
        snap("Search, lease")
        search("#Work")
        snap("Search, #Work")
    }

    /// Settings' first screen and every page, top to bottom.
    func test5Settings() throws {
        launch(seed: true)
        settingsWalk()
    }

    /// The Flipboard's cards: adding a switch, a new Switchboard, a Switchboard's menu.
    func test6FlipboardCards() throws {
        launch(seed: true)
        go("flipboard")
        let addTile = element("addSwitchTile")
        if scrollTo(addTile) {
            addTile.tap()
            pause(1.2)
            snap("Switch card, empty")
            app.typeText("Water the ferns every 3 days")
            pause()
            snap("Switch card, typed")
            tapIfExists(app.buttons["switchClose"].firstMatch)
            pause()
            snap("Switch card, discard question")
            tapIfExists(app.buttons["switchDiscard"].firstMatch)
            pause()
        } else { note("no add tile") }
        let board = element("newSwitchboardRow")
        if scrollTo(board) {
            board.tap()
            pause(1.2)
            snap("Switchboard card")
            tapIfExists(app.buttons["switchboardClose"].firstMatch)
            pause()
            tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
            pause()
        } else { note("no New Switchboard row") }
    }

    /// A fresh store: the empty states.
    func test7EmptyStates() throws {
        launch(seed: false)
        let screens = isPhoneShell ? ["inbox", "today", "upcoming", "flipboard"] : ["inbox", "today", "upcoming", "flipboard", "Completed"]
        for screen in screens {
            go(screen)
            snap("empty \(screen)")
        }
        guard isPhoneShell else {
            XCTAssertTrue(app.staticTexts["Nothing completed yet"].exists, "an empty Completed says so")
            return
        }
        go("inbox")
        openBrowse()
        snap("empty Browse")
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch
        if scrollTo(completed) {
            completed.tap()
            pause()
            snap("empty Completed")
            XCTAssertTrue(app.staticTexts["Nothing completed yet"].exists, "an empty Completed says so")
            back()
        }
        search("zebra")
        snap("empty Search, no match")
    }

    /// Dynamic Type one step up (XL) and one down (M) from the default (L).
    func test8DynamicType() throws {
        for (size, name) in [("UICTContentSizeCategoryXL", "type XL"), ("UICTContentSizeCategoryM", "type M")] {
            launch(seed: true, extra: ["-UIPreferredContentSizeCategoryName", size])
            go("today")
            snap("\(name) Today")
            go("inbox")
            snap("\(name) Inbox")
            openTask("Reply to Sam about the lease")
            snap("\(name) editor")
            closeEditor()
            openSettings()
            snap("\(name) Settings")
            closeSettings()
            app.terminate()
        }
    }

    // MARK: iPhone

    private func addTheTwoTasks() {
        go("inbox")
        for line in [Self.longTitle, Self.metaLine, "Return the library books yesterday p2 #Personal"] { add(line) }
        // Sub-tasks, from the editor.
        go("inbox")
        openTask(Self.metaTitle)
        let addRow = element("addSubtask")
        if scrollTo(addRow) {
            addRow.tap()
            pause(0.5)
            app.typeText("Measure the wall\n")
            app.typeText("Buy hooks\n")
            pause(0.5)
            tapIfExists(app.buttons["editorConfirm"].firstMatch)
            pause()
        } else { note("no Add Sub-task") }
        closeEditor()
        // One of the two done.
        openTask(Self.metaTitle)
        let sub = element("subtaskRow")
        if scrollTo(sub), sub.isHittable {
            sub.tap()
            pause(0.4)
        }
        tapIfExists(app.buttons["editorConfirm"].firstMatch)
        closeEditor()
    }

    /// Adds a task through the "+" card. The iPhone's card closes after the add; the iPad's panel stays open,
    /// empty, for the next one, and is closed here.
    private func add(_ line: String) {
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5), plus.isHittable else { return note("no + for \(line.prefix(20))") }
        plus.tap()
        let title = element("quickAddTitle")
        guard title.waitForExistence(timeout: 5) else { return note("no card for \(line.prefix(20))") }
        pause(0.6)
        app.typeText(line + " ")
        pause(0.8)
        app.buttons["quickAddSave"].firstMatch.tap()
        if title.waitForNonExistence(timeout: 4) { pause(0.6); return }
        let value = (title.value as? String) ?? ""
        if !value.isEmpty, value != "Task Name" {
            // Still holding the text: the add did not happen. Keep the evidence.
            snap("Save left the card open: \(line.prefix(24))")
            app.typeText("\n")
            pause(1.5)
        }
        if title.exists {
            tapIfExists(app.buttons["Close"].firstMatch)
            tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch, timeout: 1.5)
            _ = title.waitForNonExistence(timeout: 4)
        }
        pause(0.6)
    }

    private func quickAddWalk() {
        go("inbox")
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5) else { return note("no +") }
        plus.tap()
        pause(1.2)
        snap("Quick add, empty")
        app.typeText("Haircut tom 11am p1 !15mb #Home @errands ")
        pause()
        snap("Quick add, typed")
        for (id, name) in [("quickAddDateChip", "date"), ("quickAddPriorityChip", "priority"),
                           ("quickAddReminderChip", "reminder"), ("quickAddGroupChip", "Group")] {
            pickerShot(id, "Quick add, \(name) card")
        }
        let more = element("quickAddPlus")
        if more.waitForExistence(timeout: 2) {
            more.tap()
            pause()
            snap("Quick add, + menu")
            dismissMenu()
        }
        tapIfExists(app.buttons["Close"].firstMatch)
        pause()
        snap("Quick add, discard question")
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
        pause()
    }

    private func editorWalk() {
        go("today")
        openTask("Reply to Sam about the lease")
        snap("Editor")
        for (id, name) in [("popoutDateRow", "date"), ("popoutPriorityChip", "priority"), ("popoutReminderChip", "reminder"),
                           ("popoutLabelsChip", "labels"), ("popoutRepeatChip", "repeat"), ("editorGroupRow", "Group")] {
            pickerShot(id, "Editor, \(name) card")
        }
        let more = element("popoutMore")
        if more.waitForExistence(timeout: 2) {
            more.tap()
            pause()
            snap("Editor, … menu")
            dismissMenu()
        }
        closeEditor()
        go("inbox")
        openTask(Self.metaTitle)
        snap("Editor, every meta")
        let pills = element("editorPills")
        if pills.exists {
            pills.swipeLeft()
            pause()
            snap("Editor, every meta, pills scrolled")
        }
        closeEditor()
        go("inbox")
        openTask("Ask the landlord")
        snap("Editor, long title")
        closeEditor()
    }

    private func settingsWalk() {
        openSettings()
        snap("Settings")
        let rows = ["settings-profile", "settings-page-general", "settings-page-reminders", "settings-page-extras",
                    "settings-page-iCloud", "settings-page-claude", "settings-page-about"]
        for id in rows {
            let row = element(id)
            guard row.waitForExistence(timeout: 3) else { note("no \(id)"); continue }
            row.tap()
            pause()
            shotDown("Settings, \(id.replacingOccurrences(of: "settings-page-", with: "").replacingOccurrences(of: "settings-", with: ""))")
            if id == "settings-page-iCloud", tapScrolling("settings-sync-log-row") {
                snap("Settings, Sync log")
                sheetBack()
            }
            if id == "settings-page-about", tapScrolling("settings-whats-new") {
                shotDown("Settings, What's New")
                sheetBack()
            }
            sheetBack()
        }
        closeSettings()
    }

    // MARK: Helpers

    private var isPhoneShell: Bool { app.buttons["tab-inbox"].exists }

    private func launch(seed: Bool, extra: [String] = []) {
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s93-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips"]
        if seed { app.launchArguments += ["-seedDemoData", "YES", "-seedSharedTasksSample", "YES"] }
        app.launchArguments += extra
        app.launch()
        let ready = app.buttons["tab-inbox"].waitForExistence(timeout: 20) || app.staticTexts["Inbox"].waitForExistence(timeout: 5)
        XCTAssertTrue(ready, "the app is up")
        pause(1.5)
    }

    /// A tab on iPhone (`inbox`), a sidebar row elsewhere (`Inbox`, a Group's name).
    private func go(_ name: String) {
        let tab = app.buttons["tab-\(name)"]
        if tab.exists {
            // Back to the tab's first screen: re-tapping a selected tab pops it.
            tab.tap()
            if tab.isSelected { pause(0.3) }
            _ = tab.wait(for: \.isSelected, toEqual: true, timeout: 5)
            pause()
            return
        }
        showSidebar()
        let name = ["inbox": "Inbox", "today": "Today", "upcoming": "Upcoming", "flipboard": "Flipboard"][name] ?? name
        let row = app.cells.containing(.staticText, identifier: name).firstMatch
        let target = row.exists ? row : app.staticTexts[name].firstMatch
        if scrollTo(target) {
            target.tap()
        } else {
            note("no sidebar row \(name)")
        }
        pause()
    }

    /// The iPad in portrait hides the sidebar: bring it back.
    private func showSidebar() {
        if app.staticTexts["Flipboard"].exists, app.staticTexts["Flipboard"].isHittable { return }
        let toggle = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Show Sidebar", "ToggleSidebar")).firstMatch
        if toggle.exists { toggle.tap(); pause() }
    }

    private func openBrowse() {
        let browse = app.buttons["browseButton"].firstMatch
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        pause()
    }

    private func openFromBrowse(_ element: XCUIElement, _ name: String) {
        guard scrollTo(element) else { return note("no \(name) in Browse") }
        element.tap()
        pause()
        snap(name)
        snapScrolled(name)
        back()
    }

    private func search(_ text: String) {
        let field = app.textFields["browseSearch"].exists ? app.textFields["browseSearch"] : app.textFields.firstMatch
        guard scrollTo(field) else { return note("no search field") }
        field.tap()
        if let value = field.value as? String, !value.isEmpty, value != "Search" {
            tapIfExists(app.buttons["Clear"].firstMatch)
            field.tap()
        }
        app.typeText(text)
        pause()
    }

    private func back() {
        let bar = app.navigationBars.firstMatch
        let button = bar.buttons.element(boundBy: 0)
        if button.exists { button.tap() }
        pause()
    }

    private func openTask(_ prefix: String) {
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard scrollTo(row) else { return note("no row \(prefix)") }
        row.tap()
        if !element("editorTitle").waitForExistence(timeout: 5) { note("no editor for \(prefix)") }
        pause()
    }

    private func closeEditor() {
        guard element("editorTitle").exists else { return }
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() } else { app.typeText(XCUIKeyboardKey.escape.rawValue) }
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch, timeout: 1.5)
        _ = element("editorTitle").waitForNonExistence(timeout: 5)
        pause()
    }

    /// Opens the card a chip or row opens, takes its picture, and closes it with a tap outside.
    private func pickerShot(_ id: String, _ name: String) {
        let chip = element(id)
        guard scrollTo(chip, horizontal: true) else { return note("no \(id)") }
        chip.tap()
        pause(1.0)
        snap(name)
        dismissPopover()
    }

    private func dismissPopover() {
        // A tap in the top corner lands on the popover's dismissal layer, not on the card underneath.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.06)).tap()
        pause(0.8)
        // On an iPhone with a Dynamic Island that corner is inside the status bar and the system keeps the tap (on an
        // iPhone 16 every card stayed open and the walk lost its way, round 21): while the popover's own dismissal
        // layer is still up, tap it under the status bar instead.
        if app.otherElements["PopoverDismissRegion"].firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            pause(0.8)
        }
    }

    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.06)).tap()
        pause(0.6)
        // On an iPhone with a Dynamic Island that corner is inside the status bar and the system may keep the tap (on
        // an iPhone 16 quick add's + menu stayed open and the walk never reached Review Inbox, round 22): a second
        // tap just under the status bar, in the screen's empty leading margin, closes a menu that is still open and
        // lands on nothing when it is not.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.075)).tap()
        pause(0.4)
    }

    private func openSettings() {
        let candidates = [app.buttons["settingsButton"].firstMatch,
                          app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch,
                          app.buttons["gearshape"].firstMatch]
        if isPhoneShell {
            go("inbox")
            openBrowse()
        } else {
            showSidebar()
        }
        for button in candidates where button.waitForExistence(timeout: 2) {
            button.tap()
            if element("settings-profile").waitForExistence(timeout: 5) { pause(); return }
        }
        note("Settings did not open")
    }

    private func closeSettings() {
        tapIfExists(app.buttons["Done"].firstMatch)
        _ = element("settings-profile").waitForNonExistence(timeout: 5)
        pause()
    }

    private func sheetBack() {
        let back = app.buttons["sheetBack"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        pause()
    }

    @discardableResult
    private func tapScrolling(_ id: String) -> Bool {
        let target = element(id)
        guard scrollTo(target) else { note("no \(id)"); return false }
        target.tap()
        pause()
        return true
    }

    /// Drags the screen until `target` is on screen, clear of the bars at the top and foot.
    @discardableResult
    private func scrollTo(_ target: XCUIElement, horizontal: Bool = false) -> Bool {
        if !target.waitForExistence(timeout: 3) && !horizontal {
            // Not built yet: it may be further down a lazy list.
        }
        let top: CGFloat = 100
        let bottom = app.frame.height - 110
        for _ in 0..<8 {
            if target.exists, target.frame.minY > top, target.frame.maxY < bottom, target.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let up = !target.exists || target.frame.maxY >= bottom
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -260 : 200)))
            pause(0.5)
        }
        return target.exists && target.isHittable
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 2) {
        if element.waitForExistence(timeout: timeout), element.isHittable { element.tap() }
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "note: \(text)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func snap(_ name: String) {
        number += 1
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%03d %@", number, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The screen a page further down, if it scrolls; then back to the top.
    private func snapScrolled(_ name: String) {
        let before = XCUIScreen.main.screenshot().pngRepresentation
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -420)))
        pause(0.8)
        if XCUIScreen.main.screenshot().pngRepresentation != before { snap("\(name), scrolled") }
        let back = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        back.press(forDuration: 0.05, thenDragTo: back.withOffset(CGVector(dx: 0, dy: 600)))
        pause(0.6)
    }

    /// The open Settings page from its top to its end, a screen at a time.
    private func shotDown(_ name: String) {
        snap("\(name) 1")
        for part in 2...5 {
            let before = XCUIScreen.main.screenshot().pngRepresentation
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -480)))
            pause(0.8)
            if XCUIScreen.main.screenshot().pngRepresentation == before { break }
            snap("\(name) \(part)")
        }
    }
}
