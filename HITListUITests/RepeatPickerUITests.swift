import XCTest

/// Brief 97 on the iPhone: the Repeat menu worded for the task's day, Custom… for each frequency, the date card's
/// Repeat button, and our date card in Review Inbox and Upcoming's Pick Date. Every screen is kept as an attachment
/// (`xcrun xcresulttool export attachments`). Nothing here reads the clock to check words: the words that depend on
/// the day are checked on a typed day ("dec 31"), the rest by the rows that are there.
final class RepeatPickerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "YES"]
    }

    // MARK: Quick add: the date card's Repeat button, the menu, Custom…

    func test1DateCardRepeatAndCustom() throws {
        app.launch()
        openQuickAdd(in: "inbox")
        app.typeText("Water plants")
        let dateChip = element("quickAddDateChip")
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5))
        dateChip.tap()
        let repeatButton = element("datePickerRepeat")
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5), "the date card's Repeat button")
        snapshot("01 Date card with its Repeat button")

        repeatButton.tap()
        XCTAssertTrue(element("repeatChoice-weekly").waitForExistence(timeout: 5), "the Repeat menu in the card's place")
        for kind in ["everyDay", "weekdays", "weekly", "everyTwoWeeks", "monthly", "everyThreeMonths", "yearly"] {
            XCTAssertTrue(element("repeatChoice-\(kind)").exists, kind)
        }
        XCTAssertTrue(element("repeatCustom").exists)
        XCTAssertFalse(element("repeatNone").exists, "Don't repeat only once a repeat is set")
        snapshot("02 Date card, Repeat menu")

        element("repeatCustom").tap()
        let card = element("repeatCustomCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Custom in the card's place")
        let summary = element("repeatCustomSummary")
        XCTAssertTrue(summary.label.hasPrefix("Every "), summary.label)
        snapshot("03 Custom, weekly")

        segment("Daily").tap()
        pause()
        XCTAssertEqual(element("repeatCustomSummary").label, "Every day")
        snapshot("04 Custom, daily")

        segment("Monthly").tap()
        pause()
        XCTAssertTrue(element("repeatCustomSummary").label.hasPrefix("Every month on the "), element("repeatCustomSummary").label)
        snapshot("05 Custom, monthly on a day")
        element("repeatCustomDay31").tap()
        pause()
        XCTAssertEqual(element("repeatCustomSummary").label, "Every month on the 31st")
        segment("Last day").tap()
        pause()
        XCTAssertEqual(element("repeatCustomSummary").label, "Every month on the last day")
        snapshot("06 Custom, monthly on the last day")
        segment("Weekday").tap()
        pause()
        segment("Last").tap()
        element("repeatCustomWeekday6").tap()
        pause()
        XCTAssertEqual(element("repeatCustomSummary").label, "Every month on the last Friday")
        snapshot("07 Custom, monthly on a weekday")

        segment("Yearly").tap()
        pause()
        element("repeatCustomMonth2").tap()
        element("repeatCustomDay29").tap()
        pause()
        XCTAssertEqual(element("repeatCustomSummary").label, "Every year on Feb 29")
        snapshot("08 Custom, yearly")

        segment("Weekly").tap()
        element("repeatCustomIntervalUp").tap()
        pause()
        XCTAssertTrue(element("repeatCustomSummary").label.hasPrefix("Every 2 weeks on "), element("repeatCustomSummary").label)
        // Tuesday, Thursday and Saturday: whichever day today is, two days or more stay on, a rule none of the seven.
        for weekday in [3, 5, 7] { element("repeatCustomWeekday\(weekday)").tap() }
        pause()
        XCTAssertTrue(element("repeatCustomSummary").label.contains(" and "), element("repeatCustomSummary").label)
        snapshot("09 Custom, every 2 weeks on several days")
        element("repeatCustomDone").tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "Done closes the card")

        let repeatChip = app.buttons["quickAddRepeatChip"].firstMatch
        XCTAssertTrue(repeatChip.waitForExistence(timeout: 5), "the Repeat chip shows the rule")
        XCTAssertTrue(repeatChip.label.contains("Every 2 weeks on"), repeatChip.label)
        snapshot("10 Quick add with the custom repeat")

        repeatChip.tap()
        XCTAssertTrue(element("repeatCurrent").waitForExistence(timeout: 5), "a rule none of the seven: its own ticked line")
        XCTAssertTrue(element("repeatNone").exists)
        snapshot("11 Repeat chip's menu, the rule in force at the top")
    }

    // MARK: The menu on a task due on the 31st, and with no date

    func test2MenuOnThe31stAndWithNoDate() throws {
        app.launch()
        openQuickAdd(in: "inbox")
        app.typeText("Pay the bills dec 31 ")
        openRepeatFromPlus()
        XCTAssertTrue(element("repeatChoice-monthly").waitForExistence(timeout: 5))
        XCTAssertEqual(element("repeatChoice-monthly").label, "Every month on the 31st")
        XCTAssertEqual(element("repeatChoice-everyThreeMonths").label, "Every 3 months on the 31st")
        XCTAssertEqual(element("repeatChoice-yearly").label, "Every year on December 31")
        XCTAssertEqual(element("repeatChoice-weekdays").label, "Every weekday (Mon – Fri)")
        snapshot("12 Repeat menu, due on the 31st")
        element("repeatChoice-yearly").tap()
        let chip = app.buttons["quickAddRepeatChip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.label.contains("Every year on Dec 31"), chip.label)
        XCTAssertTrue(field.value.map { "\($0)".contains("every year on dec 31") } ?? false, "the card writes the words")
        snapshot("13 Quick add, every year on Dec 31")

        // A fresh card with no date: worded for today, the rows all there.
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Add closes the card")
        openQuickAdd(in: "inbox")
        app.typeText("Stretch")
        openRepeatFromPlus()
        XCTAssertTrue(element("repeatChoice-weekly").waitForExistence(timeout: 5))
        XCTAssertTrue(element("repeatChoice-weekly").label.hasPrefix("Every week on "))
        XCTAssertTrue(element("repeatChoice-monthly").label.hasPrefix("Every month on the "))
        snapshot("14 Repeat menu, no date")
    }

    // MARK: The editor's Repeat pill

    func test3EditorRepeatPill() throws {
        app.launch()
        openQuickAdd(in: "inbox")
        app.typeText("Water the ferns dec 11 ")
        app.buttons["quickAddSave"].tap()
        dismissQuickAdd()
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", "Water the ferns")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let pill = app.buttons["popoutRepeatChip"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the editor's Repeat pill")
        pill.tap()
        XCTAssertTrue(element("repeatChoice-monthly").waitForExistence(timeout: 5))
        XCTAssertEqual(element("repeatChoice-monthly").label, "Every month on the 11th")
        snapshot("15 Editor, Repeat menu for the 11th")
        element("repeatChoice-monthly").tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let words = app.staticTexts.matching(NSPredicate(format: "label == %@", "Every month on the 11th")).firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 5), "the date row says the rule")
        pill.tap()
        XCTAssertTrue(element("repeatChoice-monthly").waitForExistence(timeout: 5))
        XCTAssertTrue(element("repeatChoice-monthly").isSelected, "the rule in force is ticked")
        XCTAssertTrue(element("repeatNone").exists)
        snapshot("16 Editor, the rule ticked")
        element("repeatCustom").tap()
        XCTAssertTrue(element("repeatCustomCard").waitForExistence(timeout: 5))
        XCTAssertEqual(element("repeatCustomSummary").label, "Every month on the 11th", "Custom opens on the rule")
        snapshot("17 Editor, Custom on the rule")
    }

    // MARK: No system date picker: Review Inbox and Upcoming

    func test4ReviewInboxAndUpcomingPickDate() throws {
        app.launchArguments += ["-seedDemoData", "YES"]
        app.launch()
        go("inbox")
        let options = app.buttons["viewOptions"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        options.tap()
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5), "Review Inbox in the view options")
        review.tap()
        let pick = app.buttons["reviewPickDate"].firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        XCTAssertTrue(element("pickDateCard").waitForExistence(timeout: 5), "our date card")
        XCTAssertFalse(app.datePickers.firstMatch.exists, "no system date picker")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tomorrow")).firstMatch.exists, "its presets")
        snapshot("18 Review Inbox, Pick a date")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tomorrow")).firstMatch.tap()
        XCTAssertTrue(element("pickDateCard").waitForNonExistence(timeout: 5), "a day applies at once")
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) { done.tap() }
        pause()

        go("upcoming")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10))
        // A task's row, not a day's header (the headers are the short cells).
        let taskRow = app.cells.allElementsBoundByIndex.first { $0.frame.height > 56 && $0.isHittable }
        let row = try XCTUnwrap(taskRow, "a task in Upcoming")
        row.swipeRight()
        let pickDate = app.buttons["Pick Date"].firstMatch
        XCTAssertTrue(pickDate.waitForExistence(timeout: 5), "the swipe's Pick Date")
        pickDate.tap()
        XCTAssertTrue(element("pickDateCard").waitForExistence(timeout: 5), "our date card")
        XCTAssertFalse(app.datePickers.firstMatch.exists, "no system date picker")
        snapshot("19 Upcoming, Pick Date")
    }

    // MARK: Helpers

    private var field: XCUIElement { app.descendants(matching: .any)["quickAddTitle"].firstMatch }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// A segment of one of Custom's segmented controls, by its words.
    private func segment(_ title: String) -> XCUIElement {
        let button = element("repeatCustomCard").buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), title)
        return button
    }

    private func go(_ tab: String) {
        let button = app.buttons["tab-\(tab)"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
    }

    private func openQuickAdd(in tab: String) {
        go(tab)
        app.buttons["quickAddButton"].firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card's title field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    /// "+" → Repeat: the Repeat chip appears and opens its menu.
    private func openRepeatFromPlus() {
        let plus = element("quickAddPlus")
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        let item = app.buttons.matching(NSPredicate(format: "label == %@", "Repeat")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "+ → Repeat")
        item.tap()
        pause(0.8)
        if !element("repeatChoice-weekly").waitForExistence(timeout: 2) {
            let chip = app.buttons["quickAddRepeatChip"].firstMatch
            if chip.waitForExistence(timeout: 3) { chip.tap() }
        }
    }

    private func dismissQuickAdd() {
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
        if field.exists, close.waitForExistence(timeout: 2) { close.tap() }
        _ = field.waitForNonExistence(timeout: 5)
    }

    private func pause(_ seconds: TimeInterval = 0.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snapshot(_ name: String) {
        pause(0.4)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
