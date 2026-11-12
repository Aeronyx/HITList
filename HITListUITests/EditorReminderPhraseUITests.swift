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
