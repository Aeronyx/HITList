import XCTest

/// Brief 127 on the iPhone (a friend of George's, 0.9.8: "PNHP Working Group tonight !30mb" set no reminder on a task
/// due today at 8 PM): a reminder phrase typed into the title of a task that already has a time. The demo week's "Buy
/// groceries" is due today at 6 PM; " !30mb" goes at the end of its title. The Reminder pill must say "30 min before"
/// before Confirm (what Confirm will save), and the task must keep it after.
final class EditorReminderPhraseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s127-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 20), "the app is up")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the phone's tabs")
    }

    /// The friend's case exactly: the phrase at the very end, no space after it, then Confirm.
    func testThePhraseAtTheEndShowsAndSavesBeforeConfirm() {
        let title = openGroceries()
        title.typeText(" !30mb")
        snapshot("1 Typed, no space")
        let pill = reminderPill
        XCTAssertTrue(pill.label.contains("30 min before"), "the pill previews what Confirm saves: \(pill.label)")

        app.buttons["editorConfirm"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Confirm closes the editor")
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: 5), "the title without the phrase")

        _ = openGroceries()
        snapshot("2 Reopened")
        XCTAssertTrue(reminderPill.label.contains("30 min before"), "saved: \(reminderPill.label)")
    }

    /// A space after it: it lights up as typed, the pill says so, and Confirm saves it.
    func testThePhraseWithASpaceAfterItIsSaved() {
        let title = openGroceries()
        title.typeText(" !1hb ")
        snapshot("1 Typed, a space after")
        XCTAssertTrue(reminderPill.label.contains("1 hour before"), "the pill previews it: \(reminderPill.label)")
        app.buttons["editorConfirm"].firstMatch.tap()
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: 5), "the title without the phrase")
        _ = openGroceries()
        XCTAssertTrue(reminderPill.label.contains("1 hour before"), "saved: \(reminderPill.label)")
    }

    /// The friend's own sequence: "PNHP Working Group tonight !30mb" typed in quick add on Today ("tonight" is today,
    /// a day only), so "!30mb" stays in the title as text; the task given 8 PM by hand in the Reminder card. The stored
    /// phrase wakes at once; opened again it is lit and the pill previews it, × closes without asking, and Confirm
    /// sets the reminder and takes the phrase out of the title.
    func testAReminderTypedBeforeTheTaskHadATimeWakes() {
        let today = app.buttons["tab-today"]
        today.tap()
        _ = today.wait(for: \.isSelected, toEqual: true, timeout: 5)
        app.buttons["quickAddButton"].firstMatch.tap()
        let field = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the quick-add card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("PNHP Working Group tonight !30mb")
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the card closes after Add")

        let stored = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@",
                                                          "PNHP Working Group", "!30mb")).firstMatch
        XCTAssertTrue(stored.waitForExistence(timeout: 5), "no time: \"!30mb\" is kept in the title as text")
        stored.tap()
        XCTAssertTrue(reminderPill.waitForExistence(timeout: 5), "the editor")
        XCTAssertFalse(reminderPill.label.contains("before"), "no time yet: \(reminderPill.label)")
        reminderPill.tap()
        let eight = app.buttons["8 PM"].firstMatch
        XCTAssertTrue(eight.waitForExistence(timeout: 5), "the Reminder card's times")
        eight.tap()
        let woken = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "30 min before"),
                                              object: reminderPill)
        XCTAssertEqual(XCTWaiter().wait(for: [woken], timeout: 5), .completed,
                       "8 PM by hand wakes the stored phrase: \(reminderPill.label)")

        app.buttons["Close"].firstMatch.tap()
        let title = app.descendants(matching: .any)["editorTitle"].firstMatch
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "× closes at once: a woken phrase is not typing")

        XCTAssertTrue(stored.waitForExistence(timeout: 5), "nothing saved without Confirm")
        stored.tap()
        XCTAssertTrue(reminderPill.waitForExistence(timeout: 5))
        snapshot("1 Opened: the stored phrase lit, the pill previewing it")
        XCTAssertTrue(reminderPill.label.contains("30 min before"), "previewed on opening: \(reminderPill.label)")

        app.buttons["editorConfirm"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", "PNHP Working Group")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the phrase left the title")
        saved.tap()
        XCTAssertTrue(reminderPill.waitForExistence(timeout: 5))
        XCTAssertTrue(reminderPill.label.contains("30 min before"), "saved: \(reminderPill.label)")
        snapshot("2 After Confirm")
    }

    // MARK: Helpers

    private var groceriesRow: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Buy groceries")).firstMatch
    }

    private var reminderPill: XCUIElement { app.buttons["popoutReminderChip"].firstMatch }

    /// Today, then "Buy groceries": its editor, the caret at the end of the title.
    @discardableResult
    private func openGroceries() -> XCUIElement {
        let today = app.buttons["tab-today"]
        today.tap()
        _ = today.wait(for: \.isSelected, toEqual: true, timeout: 5)
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: 10), "the demo week's timed task")
        groceriesRow.tap()
        let title = app.descendants(matching: .any)["editorTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the editor")
        XCTAssertTrue(reminderPill.waitForExistence(timeout: 5), "the Reminder pill")
        // A tap at the title's right end puts the caret after its last letter and brings the keyboard.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard")
        return title
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
