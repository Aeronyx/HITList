import XCTest

/// Brief 175 on the iPhone (George, 2026-11-23, after Todoist's: "when the user types an exclamation point … it pops up
/// with recommendations"): "!" in quick add opens a list above the card, never under the keyboard or off the top of the
/// screen. "Call mom 9am !" offers At time of task first, and a tap writes "!At time of task " lit, the Reminder chip
/// says At time, and Add saves a reminder at 9:00. "Buy milk !1" narrows to In 15 minutes and In 1 hour; In 15 minutes
/// saves a reminder fifteen minutes on. Pictures land in the .xcresult, and in `TEST_RUNNER_HITLIST_SHOTS_DIR` when set.
/// Each launch has a store and settings of its own, sync off, no tips.
final class ReminderListUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "r36-175-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 30), "the app is up")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the phone's oval card")
    }

    func testATimedTaskOffersAtTimeOfTaskFirstAndSavesIt() {
        openQuickAdd()
        app.typeText("Call mom 9am !")
        let list = element("reminderSuggestions")
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the list opens on \"!\"")
        list.waitUntilStill()
        let first = row("before-0")
        XCTAssertTrue(first.exists, "At time of task")
        XCTAssertTrue(first.label.hasPrefix("At time of task"), first.label)
        XCTAssertTrue(first.label.contains("exclamation 0 m b"), "read with its code: \(first.label)")
        XCTAssertLessThan(first.frame.minY, row("before-10").frame.minY, "first, above 10 minutes before")
        assertPlaced(list)
        shot("01 timed list")

        first.tap()
        XCTAssertTrue(list.waitForNonExistence(timeout: 3), "a pick closes the list")
        XCTAssertEqual(title.value as? String, "Call mom 9am !At time of task ", "the words and a space, written in")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays")
        let chip = app.buttons["quickAddReminderChip"].firstMatch
        XCTAssertTrue(chip.label.contains("At time"), "the Reminder chip: \(chip.label)")
        XCTAssertTrue(chip.label.contains("9:00"), "and the time: \(chip.label)")
        shot("02 after the pick")

        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Add closes the card")
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", "Call mom")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "saved with the words out of its title")
        saved.tap()
        let pill = app.buttons["popoutReminderChip"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the editor")
        XCTAssertTrue(pill.label.contains("9:00"), "a reminder at 9:00: \(pill.label)")
        XCTAssertFalse(pill.label.contains("before"), "at the time, not before it: \(pill.label)")
        shot("03 saved, in its editor")
    }

    func testTypingNarrowsAndInFifteenMinutesSavesIt() {
        openQuickAdd()
        app.typeText("Buy milk !1")
        let list = element("reminderSuggestions")
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the list")
        list.waitUntilStill()
        XCTAssertTrue(row("in-15").exists, "In 15 minutes")
        XCTAssertTrue(row("in-60").exists, "In 1 hour")
        XCTAssertFalse(row("in-5").exists, "narrowed: In 5 minutes is gone")
        XCTAssertFalse(row("before-10").exists, "no time: no before rows")
        assertPlaced(list)
        shot("04 narrowed by 1")

        let picked = Date()
        row("in-15").tap()
        XCTAssertTrue(list.waitForNonExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Buy milk !In 15 minutes ")
        shot("05 In 15 minutes picked")

        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Add closes the card")
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", "Buy milk")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        let pill = app.buttons["popoutReminderChip"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the editor")
        // Fifteen minutes on from the pick (the minute may turn while the test runs).
        let times = (14...16).map { picked.addingTimeInterval(TimeInterval($0 * 60)).formatted(date: .omitted, time: .shortened) }
        XCTAssertTrue(times.contains { pill.label.contains($0) }, "a reminder fifteen minutes on (\(times)): \(pill.label)")
        shot("06 saved, in its editor")
    }

    func testAnUntimedTaskOffersFromNowAndLaterAndASpaceClosesIt() {
        openQuickAdd()
        app.typeText("Water the plants !")
        let list = element("reminderSuggestions")
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the list")
        list.waitUntilStill()
        for id in ["in-5", "in-15", "in-30", "in-60", "later"] { XCTAssertTrue(row(id).exists, id) }
        XCTAssertFalse(row("before-0").exists, "no time: no At time of task")
        assertPlaced(list)
        shot("07 untimed list")
        app.typeText("in")
        XCTAssertTrue(row("in-5").waitForExistence(timeout: 2))
        XCTAssertFalse(row("later").exists, "\"!in\": the In rows")
        app.typeText(" ")
        XCTAssertTrue(list.waitForNonExistence(timeout: 3), "a space closes it")
        app.typeText("!x")
        XCTAssertFalse(list.waitForExistence(timeout: 1.5), "nothing matches: no list")
    }

    /// The task editor's title is the same field: "!" there opens the same list, under the title, for the task's own
    /// time; a pick lights at once and the Reminder pill reads it before Confirm, and Confirm saves it.
    func testTheEditorsTitleOffersTheListToo() {
        openQuickAdd()
        app.typeText("Call the dentist 5pm")
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Add closes the card")
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", "Call the dentist")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let editorTitle = element("editorTitle")
        let pill = app.buttons["popoutReminderChip"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the editor")
        // A tap at the title's right end puts the caret after its last letter and brings the keyboard.
        editorTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard")
        editorTitle.typeText(" !1h")
        let list = element("reminderSuggestions")
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the list in the editor")
        list.waitUntilStill()
        let hour = self.row("before-60")
        XCTAssertTrue(hour.exists, "the task has a time: 1 hour before")
        XCTAssertLessThanOrEqual(list.frame.maxY, app.keyboards.firstMatch.frame.minY, "clear of the keyboard")
        XCTAssertGreaterThanOrEqual(list.frame.minY, editorTitle.frame.maxY, "under the title")
        shot("08 editor's list")
        hour.tap()
        XCTAssertTrue(list.waitForNonExistence(timeout: 3))
        XCTAssertEqual(editorTitle.value as? String, "Call the dentist !1 hour before ")
        XCTAssertTrue(pill.label.contains("1 hour before"), "the pill reads it before Confirm: \(pill.label)")
        shot("09 editor after the pick")
        app.buttons["editorConfirm"].firstMatch.tap()
        XCTAssertTrue(editorTitle.waitForNonExistence(timeout: 5), "Confirm closes the editor")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the title without the words")
        row.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(pill.label.contains("1 hour before"), "saved: \(pill.label)")
    }

    // MARK: Helpers

    private var title: XCUIElement { element("quickAddTitle") }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func row(_ id: String) -> XCUIElement { app.buttons["reminderSuggestion-\(id)"].firstMatch }

    /// The Inbox's quick-add card (no day of its own), the keyboard up.
    private func openQuickAdd() {
        app.buttons["tab-inbox"].firstMatch.tap()
        pause(1)
        app.buttons["quickAddButton"].firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard")
        pause(0.8)
    }

    /// Above the card, under the screen's top (its status bar), clear of the keyboard; its rows' words 12 pt from its
    /// edges at the least.
    private func assertPlaced(_ list: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let frame = list.frame, card = element("quickAddCard").frame, keyboard = app.keyboards.firstMatch.frame
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(frame.maxY, card.minY + 0.5, "above the card: \(frame) / \(card)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, keyboard.minY, "never under the keyboard", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY + 20, "never off the top: \(frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX + 8, "inside the screen", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX - 8, "inside the screen", file: file, line: line)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reminderSuggestion-"))
        XCTAssertGreaterThan(rows.count, 0, file: file, line: line)
        for index in 0..<rows.count {
            let r = rows.element(boundBy: index)
            guard r.frame.minY >= frame.minY, r.frame.maxY <= frame.maxY else { continue }
            for text in r.staticTexts.allElementsBoundByIndex where !text.label.isEmpty {
                XCTAssertGreaterThanOrEqual(text.frame.minX - frame.minX, 12, "\(text.label) clear of the edge", file: file, line: line)
                XCTAssertGreaterThanOrEqual(frame.maxX - text.frame.maxX, 12, "\(text.label) clear of the edge", file: file, line: line)
            }
        }
    }

    private func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
    }
}
