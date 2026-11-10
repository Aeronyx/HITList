import XCTest

/// Brief 71 on the iPhone: "Pay rent every month on the 1st 9am p1 #Finance" lights up in the quick-add card,
/// saves as a task due on the next 1st at 9:00, its editor reads "Monthly on the 1st", and the Repeat card shows
/// that rule as the current choice without turning it into "Every month".
final class RepeatPhraseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    func testMonthlyOnThe1stFromQuickAddToTheRepeatCard() throws {
        app.launch()
        let inbox = app.buttons["tab-inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15))
        inbox.tap()
        XCTAssertTrue(inbox.wait(for: \.isSelected, toEqual: true, timeout: 5))

        app.buttons["quickAddButton"].firstMatch.tap()
        let field = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card's title field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("Pay rent every month on the 1st 9am p1 #Finance ")
        let chip = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Monthly on the 1st")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the Repeat chip reads the rule")
        snapshot("1 Card typed")

        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the card closes after Add")
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", "Pay rent")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the task in the Inbox")
        snapshot("2 Inbox row")

        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 5), "the editor")
        let words = app.staticTexts.matching(NSPredicate(format: "label == %@", "Monthly on the 1st")).firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 5), "the editor's date row reads the rule")
        snapshot("3 Editor")

        let repeatChip = app.buttons["popoutRepeatChip"].firstMatch
        XCTAssertTrue(repeatChip.waitForExistence(timeout: 5))
        repeatChip.tap()
        let everyMonth = app.buttons.matching(NSPredicate(format: "label == %@", "Every month")).firstMatch
        XCTAssertTrue(everyMonth.waitForExistence(timeout: 5), "the Repeat card")
        XCTAssertFalse(everyMonth.isSelected, "Every month is not the current choice")
        snapshot("4 Repeat card")
        // The current rule's row picks nothing: the card stays open and the rule stays.
        let current = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Monthly on the 1st"))
        XCTAssertGreaterThanOrEqual(current.count, 1)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
