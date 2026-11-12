import XCTest

/// Brief 107: what opens over a list on a short phone (the iPhone Duo's outer display, 376 × 678 pt of content beside
/// the system's bar column) fits it whole. The checks run on whatever simulator the suite runs on; the picture walk
/// runs only on demand:
///
///     TEST_RUNNER_HITLIST_DUO_WALK=1 xcodebuild test-without-building -xctestrun <the .xctestrun> \
///       -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:HITListUITests/DuoCardsUITests/testWalk \
///       -resultBundlePath build.noindex/duo.xcresult
final class DuoCardsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var number = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    private var walks: Bool { ProcessInfo.processInfo.environment["HITLIST_DUO_WALK"] == "1" }

    // MARK: Always: the cards fit the screen they open on

    /// Quick add's and the editor's Date and Reminder cards open whole on any phone: their first and last controls on
    /// screen, tappable, inside the window (on the iPhone Duo's outer display in 0.9.4 the date card's grid and the
    /// Reminder card's left side were off the display).
    func testDateAndReminderCardsOpenWhole() throws {
        launch()
        go("inbox")
        openQuickAdd()
        app.typeText("Haircut tom 11am ")
        pause()
        openCard("quickAddDateChip")
        assertWhole(presetToday, "quick add's date card: its presets")
        assertWhole(element("datePickerRepeat"), "quick add's date card: its Repeat button, under the calendar")
        dismissPopover()
        openCard("quickAddReminderChip")
        assertWhole(element("reminderOffset1440"), "quick add's reminder card: its offsets")
        assertWhole(element("reminderLaterToday"), "quick add's reminder card: its first section")
        dismissPopover()
        tapIfExists(app.buttons["Close"].firstMatch)
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
        pause()

        go("today")
        openTask("Reply to Sam about the lease")
        openCard("popoutDateRow")
        assertWhole(presetToday, "the editor's date card: its presets")
        assertWhole(element("datePickerRepeat"), "the editor's date card: its Repeat button")
        dismissPopover()
        openCard("popoutReminderChip")
        assertWhole(element("reminderOffset1440"), "the editor's reminder card: its offsets")
        assertWhole(element("reminderLaterToday"), "the editor's reminder card: its first section")
        dismissPopover()
        closeEditor()
    }

    private var presetToday: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today, ")).firstMatch
    }

    private func openCard(_ id: String) {
        let chip = element(id)
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(id) is there")
        chip.tap()
        pause(1.2)
    }

    /// On screen, tappable, and inside the window on every side.
    private func assertWhole(_ control: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard control.waitForExistence(timeout: 3) else {
            return XCTFail("\(what): not there", file: file, line: line)
        }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(control.isHittable, "\(what): tappable", file: file, line: line)
        XCTAssertTrue(window.contains(control.frame), "\(what): \(control.frame) inside \(window)", file: file, line: line)
    }

    // MARK: The walk (pictures and frames, on demand)

    func testWalk1QuickAdd() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        launch()
        go("inbox")
        // A title of three lines, first, on a fresh card.
        openQuickAdd()
        app.typeText("Ask the landlord whether the radiator in the back bedroom can be bled before the cold weather arrives tom")
        pause()
        snap("Quick add, three lines, keyboard up")
        pickerShot("quickAddDateChip", "Quick add, three lines, date card")
        tapIfExists(app.buttons["Close"].firstMatch)
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
        pause(1.5)
        openQuickAdd()
        snap("Quick add, empty, keyboard up")
        app.typeText("Haircut tom 11am p1 !15mb #Home @errands ")
        pause()
        snap("Quick add, typed, keyboard up")
        dump("quick add typed")
        for (id, name) in [("quickAddDateChip", "date"), ("quickAddPriorityChip", "priority"),
                           ("quickAddReminderChip", "reminder"), ("quickAddGroupChip", "Group")] {
            pickerShot(id, "Quick add, \(name) card")
        }
        let more = element("quickAddPlus")
        if more.waitForExistence(timeout: 2) {
            more.tap()
            pause()
            snap("Quick add, + menu")
            let repeatItem = app.buttons["Repeat"].firstMatch
            if repeatItem.waitForExistence(timeout: 2) {
                repeatItem.tap()
                pause()
                pickerShot("quickAddRepeatChip", "Quick add, repeat card")
            } else { dismissPopover() }
        }
        tapIfExists(app.buttons["Close"].firstMatch)
        pause()
        snap("Quick add, discard question")
        dump("quick add discard")
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
        pause()
    }

    func testWalk2Editor() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        launch()
        go("today")
        openTask("Reply to Sam about the lease")
        snap("Editor")
        dump("editor")
        for (id, name) in [("popoutDateRow", "date"), ("popoutPriorityChip", "priority"), ("popoutReminderChip", "reminder"),
                           ("popoutLabelsChip", "labels"), ("popoutRepeatChip", "repeat"), ("editorGroupRow", "Group")] {
            pickerShot(id, "Editor, \(name) card")
        }
        let repeatPill = element("popoutRepeatChip")
        if repeatPill.exists {
            if !repeatPill.isHittable, element("editorPills").exists { element("editorPills").swipeLeft(); pause(0.5) }
            repeatPill.tap()
            pause()
            let custom = element("repeatCustom")
            if custom.waitForExistence(timeout: 2) {
                custom.tap()
                pause()
                snap("Editor, repeat card, Custom")
            }
            dismissPopover()
        }
        let dateRow = element("popoutDateRow")
        if dateRow.waitForExistence(timeout: 2) {
            dateRow.tap()
            pause()
            let repeatButton = element("datePickerRepeat")
            if repeatButton.waitForExistence(timeout: 2) {
                repeatButton.tap()
                pause()
                snap("Editor, date card, Repeat menu")
            }
            dismissPopover()
        }
        let more = element("popoutMore")
        if more.waitForExistence(timeout: 2) {
            more.tap()
            pause()
            snap("Editor, … menu")
            dismissPopover()
        }
        // A change, then ×: the Discard question.
        let title = element("editorTitle")
        if title.waitForExistence(timeout: 2) {
            title.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
            pause(0.5)
            app.typeText(" soon")
            pause(0.5)
            snap("Editor, typing, keyboard up")
            tapIfExists(app.buttons["Close"].firstMatch)
            pause()
            snap("Editor, discard question")
            tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
            pause()
        }
        closeEditor()
        go("inbox")
        add("Ask the landlord whether the radiator in the back bedroom can be bled before the cold weather arrives")
        openTask("Ask the landlord")
        snap("Editor, long title")
        closeEditor()
    }

    func testWalk3Review() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        launch()
        go("inbox")
        let options = app.buttons["viewOptions"].firstMatch
        guard options.waitForExistence(timeout: 3) else { return note("no view options") }
        options.tap()
        pause()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
        guard review.waitForExistence(timeout: 3) else { return note("no Review item") }
        review.tap()
        pause(1.2)
        snap("Review Inbox")
        dump("review")
        let pick = app.buttons["reviewPickDate"].firstMatch
        if pick.waitForExistence(timeout: 2) {
            pick.tap()
            pause(1.0)
            snap("Review Inbox, Pick a date")
            dump("review pick a date")
            dismissPopover()
        }
        let group = app.buttons["reviewMoveToGroup"].firstMatch
        if group.waitForExistence(timeout: 2) {
            group.tap()
            pause(1.0)
            snap("Review Inbox, Move to a Group")
            dismissPopover()
        }
        let card = element("reviewCard")
        if card.exists {
            card.swipeLeft()
            pause(0.8)
            snap("Review Inbox, deleted toast")
        }
    }

    func testWalk4Flipboard() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        launch()
        go("flipboard")
        let addTile = element("addSwitchTile")
        if scrollTo(addTile) {
            addTile.tap()
            pause(1.2)
            snap("Switch card, empty")
            app.typeText("Water the ferns every 3 days")
            pause()
            snap("Switch card, typed")
            dump("switch typed")
            tapIfExists(app.buttons["switchClose"].firstMatch)
            pause()
            snap("Switch card, discard question")
            dump("switch discard")
            tapIfExists(app.buttons["switchKeepEditing"].firstMatch)
            pause()
            snap("Switch card, kept editing")
            tapIfExists(app.buttons["switchClose"].firstMatch)
            pause()
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

    func testWalk5Settings() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        for (size, name) in [("UICTContentSizeCategoryL", "default"), ("UICTContentSizeCategoryXL", "XL")] {
            launch(extra: ["-UIPreferredContentSizeCategoryName", size])
            openSettings()
            shotDown("Settings \(name)")
            closeSettings()
            // Each page from a fresh sheet: dragging a sheet back to its top closes it.
            for id in ["settings-profile", "settings-page-general", "settings-page-reminders", "settings-page-extras",
                       "settings-page-iCloud", "settings-page-about"] {
                openSettings()
                let row = element(id)
                guard scrollTo(row) else { note("no \(id)"); closeSettings(); continue }
                row.tap()
                pause()
                shotDown("Settings \(name), \(id.replacingOccurrences(of: "settings-page-", with: ""))")
                closeSettings()
            }
            app.terminate()
        }
    }

    func testWalk8SettingsPages() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        let pages: [(page: String, row: String, name: String)] = [
            ("settings-page-iCloud", "settings-sync-log-row", "Sync log"),
            ("settings-page-iCloud", "settings-check-icloud", "Check iCloud"),
            ("settings-page-general", "settings-quick-add-guide", "Quick add guide"),
            ("settings-page-about", "settings-whats-new", "What's New"),
            ("settings-page-about", "settings-privacy-policy", "Privacy policy"),
            ("settings-page-about", "settings-feedback", "Feedback"),
        ]
        for (size, name) in [("UICTContentSizeCategoryL", "default"), ("UICTContentSizeCategoryXL", "XL")] {
            launch(extra: ["-UIPreferredContentSizeCategoryName", size])
            for entry in pages {
                openSettings()
                let page = element(entry.page)
                guard scrollTo(page) else { note("no \(entry.page)"); closeSettings(); continue }
                page.tap()
                pause()
                let row = element(entry.row)
                guard scrollTo(row) else { note("no \(entry.row)"); closeSettings(); continue }
                row.tap()
                pause(entry.name == "Check iCloud" ? 4 : 1.2)
                shotDown("\(entry.name) \(name)")
                closeSettings()
                // A card or sheet over Settings (the feedback card) closes with its own Cancel or a tap above it.
                tapIfExists(app.buttons["Cancel"].firstMatch, timeout: 1)
                if element("settings-profile").exists { closeSettings() }
            }
            app.terminate()
        }
    }

    func testWalk6Sheets() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        launch()
        go("inbox")
        let browse = app.buttons["browseButton"].firstMatch
        guard browse.waitForExistence(timeout: 5) else { return note("no Browse") }
        browse.tap()
        pause()
        for item in ["New Group…", "New Label…", "New Filter…"] {
            let new = app.buttons["browseNew"].firstMatch
            guard new.waitForExistence(timeout: 3) else { note("no New menu"); break }
            new.tap()
            pause()
            let button = app.buttons[item].firstMatch
            guard button.waitForExistence(timeout: 2) else { note("no \(item)"); dismissPopover(); continue }
            button.tap()
            pause(1.2)
            snap("Sheet, \(item), keyboard up")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.2)).tap()
            pause()
            snap("Sheet, \(item)")
            let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Cancel", "sheetCancel")).firstMatch
            if cancel.waitForExistence(timeout: 2) { cancel.tap() } else { app.swipeDown() }
            pause()
        }
        let shared = element("browse-shared-tasks")
        if scrollTo(shared) {
            shared.tap()
            pause()
            snap("Shared Tasks")
            let options = app.buttons["viewOptions"].firstMatch
            if options.waitForExistence(timeout: 2) {
                options.tap()
                pause()
                snap("Shared Tasks, view options")
                let sharing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sharing")).firstMatch
                if sharing.waitForExistence(timeout: 2) {
                    sharing.tap()
                    pause(1.2)
                    snap("Sharing")
                } else { dismissPopover() }
            }
        }
    }

    func testWalk7Tips() throws {
        try XCTSkipUnless(walks, "brief 107's walk runs only on demand (TEST_RUNNER_HITLIST_DUO_WALK=1)")
        launch(tips: true)
        pause(2)
        snap("Tips, Inbox")
        go("today")
        snap("Tips, Today")
        go("flipboard")
        pause()
        snap("Tips, Flipboard")
        go("inbox")
        openQuickAdd()
        pause()
        snap("Tips, quick add")
        app.typeText("Call mom tom ")
        pause()
        snap("Tips, quick add with a highlight")
    }

    // MARK: Helpers

    private func launch(extra: [String] = [], tips: Bool = false) {
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s107-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", tips ? "-showAllTips" : "-hideTips",
                               "-seedDemoData", "YES", "-seedSharedTasksSample", "YES"]
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 30), "the app is up")
        pause(1.5)
    }

    private func go(_ name: String) {
        let tab = app.buttons["tab-\(name)"]
        guard tab.waitForExistence(timeout: 5) else { return note("no tab \(name)") }
        tab.tap()
        _ = tab.wait(for: \.isSelected, toEqual: true, timeout: 5)
        pause()
    }

    private func openQuickAdd() {
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5) else { return note("no +") }
        plus.tap()
        let title = element("quickAddTitle")
        _ = title.waitForExistence(timeout: 5)
        // The keyboard comes with the card; on a busy simulator it can be late, and typing before it lands nowhere.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 4), title.exists { title.tap() }
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        pause(0.8)
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
        tapIfExists(app.buttons["Close"].firstMatch)
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch, timeout: 1.5)
        _ = element("editorTitle").waitForNonExistence(timeout: 5)
        pause()
    }

    private func add(_ line: String) {
        openQuickAdd()
        app.typeText(line)
        pause(0.6)
        tapIfExists(app.buttons["quickAddSave"].firstMatch)
        _ = element("quickAddTitle").waitForNonExistence(timeout: 4)
        pause(0.6)
    }

    private func openSettings() {
        go("inbox")
        let browse = app.buttons["browseButton"].firstMatch
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        pause()
        for button in [app.buttons["settingsButton"].firstMatch,
                       app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch]
            where button.waitForExistence(timeout: 2) {
            button.tap()
            if element("settings-profile").waitForExistence(timeout: 5) { pause(); return }
        }
        note("Settings did not open")
    }

    /// Drags the screen until `target` is on screen and can be tapped.
    @discardableResult
    private func scrollTo(_ target: XCUIElement) -> Bool {
        _ = target.waitForExistence(timeout: 3)
        for _ in 0..<8 {
            if target.exists, target.isHittable, target.frame.minY > 60, target.frame.maxY < app.frame.height - 80 { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.6))
            let up = !target.exists || target.frame.maxY >= app.frame.height - 80
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -220 : 200)))
            pause(0.5)
        }
        return target.exists && target.isHittable
    }

    /// The open page from its top to its end, a screen at a time.
    private func shotDown(_ name: String) {
        snap("\(name) 1")
        for part in 2...5 {
            let before = XCUIScreen.main.screenshot().pngRepresentation
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -420)))
            pause(0.8)
            if XCUIScreen.main.screenshot().pngRepresentation == before { break }
            snap("\(name) \(part)")
        }
    }

    private func closeSettings() {
        tapIfExists(app.buttons["Done"].firstMatch)
        _ = element("settings-profile").waitForNonExistence(timeout: 5)
        pause()
    }

    private func pickerShot(_ id: String, _ name: String) {
        let chip = element(id)
        guard chip.waitForExistence(timeout: 3) else { return note("no \(id)") }
        if !chip.isHittable, element("editorPills").exists { element("editorPills").swipeLeft(); pause(0.5) }
        guard chip.isHittable else { return note("\(id) not hittable") }
        chip.tap()
        pause(1.2)
        snap(name)
        dump(name)
        dismissPopover()
    }

    /// A tap just outside the open card (above it, or below where it reaches the top), which the card's dismissal layer
    /// takes; a corner of the screen is the status bar on an iPhone, where a tap closes nothing.
    private func dismissPopover() {
        let popover = app.popovers.firstMatch
        if popover.exists {
            let card = popover.frame
            let y = card.minY > 90 ? card.minY - 30 : min(card.maxY + 30, app.frame.height - 40)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: card.midX, dy: y)).tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
        }
        pause(0.8)
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

    private func dump(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = String(format: "%03d tree %@", number, name)
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
}
