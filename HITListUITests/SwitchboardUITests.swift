import XCTest

/// Brief 72 on iPhone: Switchboards. The demo week's "Before Bed" (daily, 04:00, four switches, one at 21:00, two
/// flipped) and "Deep Clean" (weekly, three) on panels under the loose switches, each one row (brief 126) with its
/// lights ("2 of 4 on"); the board's clock either side of
/// its reset (`-flipboardNow`); a new Switchboard from the Flipboard's menu and a switch added to it with a time and
/// "Overdue becomes task"; a board's card from its name, and Delete keeping its switches. Each launch has a store of
/// its own (`HITLIST_STORE_SUFFIX`), sync off, no tips. Screenshots land in the .xcresult.
final class SwitchboardUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    // MARK: The board's sections

    func testTheBoardShowsLooseSwitchesThenEachSwitchboard() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        XCTAssertTrue(switchTile("Water the plants").waitForExistence(timeout: 10), "loose switches first")
        let bed = header("Before Bed"), clean = header("Deep Clean")
        XCTAssertTrue(bed.waitForExistence(timeout: 5))
        XCTAssertTrue(bed.frame.minY > switchTile("Water the plants").frame.maxY, "the boards come after the loose switches")
        XCTAssertTrue(line(containing: "Daily · resets").exists)
        XCTAssertTrue(lights("2 of 4 on. Off: Take meds, Read 20 minutes.").exists, "Before Bed's lights, in its order")
        snapshot("1 Flipboard, loose switches first")
        // Before Bed's order, along its row: the timed switch first, then the rest in the order they were added.
        XCTAssertLessThan(switchTile("Take meds").frame.minX, switchTile("Read 20 minutes").frame.minX)
        XCTAssertEqual(switchTile("Take meds").frame.midY, switchTile("Read 20 minutes").frame.midY, accuracy: 1, "one row")
        // "Due 9:00 PM" (with the narrow space iOS puts before PM), or "Due 21:00" on a 24-hour clock.
        let caption = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Due' AND (label CONTAINS '9:00' OR label CONTAINS '21:00')"))
        XCTAssertTrue(caption.firstMatch.exists, "the timed switch's caption")
        scrollToBeforeBed()
        snapshot("2 Before Bed")
        app.swipeUp()
        XCTAssertTrue(clean.waitForExistence(timeout: 5))
        XCTAssertTrue(line(containing: "Weekly · resets").exists)
        XCTAssertTrue(lights("1 of 3 on").exists)
        snapshot("3 Deep Clean")

        // Every switch tile on the screen is one height; the loose ones one width, and a row's tiles another (sized so
        // whole tiles show and a fifth of the next, brief 126).
        let tiles = app.descendants(matching: .any).matching(identifier: "flipSwitchTile").allElementsBoundByIndex
        XCTAssertEqual(tiles.count, 9)
        let size = try XCTUnwrap(tiles.first).frame.size
        for tile in tiles {
            XCTAssertEqual(tile.frame.height, size.height, accuracy: 0.5)
        }
        let rowWidth = switchTileFrame("Take meds").width
        for title in ["Brush teeth", "Floss", "Read 20 minutes", "Vacuum", "Clean the bathroom", "Change the sheets"] {
            XCTAssertEqual(switchTileFrame(title).width, rowWidth, accuracy: 0.5, title)
        }
        XCTAssertEqual(switchTileFrame("Water the plants").width, switchTileFrame("Take out the recycling").width, accuracy: 0.5)
    }

    /// The same board just before Before Bed's 04:00 reset and just after it: before, the two flipped last evening are
    /// still green ("2 of 4"); after, every switch of the daily board is red again together ("0 of 4").
    func testTheBoardBeforeAndAfterItsReset() throws {
        let suffix = "uitest-reset-\(UUID().uuidString.prefix(8))"
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = suffix
        app.launchArguments += ["-seedDemoData"]
        // The board day the demo's flips counted for (it began at 04:00 today, or yesterday before 04:00), and the
        // next reset.
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let boardDay = cal.component(.hour, from: now) < 4 ? cal.date(byAdding: .day, value: -1, to: today)! : today
        let nextDay = cal.date(byAdding: .day, value: 1, to: boardDay)!
        let before = cal.date(bySettingHour: 3, minute: 30, second: 0, of: nextDay)!
        let after = cal.date(bySettingHour: 4, minute: 30, second: 0, of: nextDay)!

        app.launchArguments += ["-flipboardNow", Self.argument(before)]
        app.launch()
        openFlipboard()
        XCTAssertTrue(header("Before Bed").waitForExistence(timeout: 10))
        XCTAssertTrue(lights("2 of 4 on").waitForExistence(timeout: 5), "03:30: still yesterday evening's board day")
        scrollToBeforeBed()
        snapshot("1 Before the reset, 03:30")
        app.terminate()

        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = suffix
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-flipboardNow", Self.argument(after)]
        app.launch()
        openFlipboard()
        XCTAssertTrue(header("Before Bed").waitForExistence(timeout: 10))
        XCTAssertTrue(lights("0 of 4 on").waitForExistence(timeout: 5), "04:30: every switch red again")
        scrollToBeforeBed()
        snapshot("2 After the reset, 04:30")
    }

    // MARK: Making a Switchboard and a switch on it

    func testANewSwitchboardAndASwitchOnItWithATime() throws {
        app.launch()
        openFlipboard()
        // The empty board offers a switch alone (brief 96); once there is one, a Switchboard at the board's foot.
        XCTAssertFalse(app.buttons["New Switchboard"].exists, "no Switchboard before a switch")
        app.buttons["addSwitchTile"].tap()
        let first = app.descendants(matching: .any)["switchName"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the switch card")
        app.typeText("Stretch")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5))
        let newBoard = app.buttons["New Switchboard"]
        XCTAssertTrue(newBoard.waitForExistence(timeout: 5))
        newBoard.tap()
        let name = app.descendants(matching: .any)["switchboardName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the Switchboard card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the name has the keyboard")
        app.typeText("Before Bed")
        snapshot("1 The Switchboard card")
        app.buttons["switchboardSave"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(header("Before Bed").waitForExistence(timeout: 5))
        XCTAssertTrue(line(containing: "Daily · resets").exists)

        // The Add switch outline at the end of its row (brief 126; it was a "+" by the name): the switch card on the
        // board, a time typed into the name, Overdue becomes task on.
        let add = app.buttons["switchboardAdd"].firstMatch
        XCTAssertEqual(add.label, "Add a switch to Before Bed")
        add.tap()
        let switchName = app.descendants(matching: .any)["switchName"].firstMatch
        XCTAssertTrue(switchName.waitForExistence(timeout: 5), "the switch card")
        XCTAssertTrue(app.descendants(matching: .any)["switchBoardLine"].waitForExistence(timeout: 3),
                      "Daily, with Before Bed in place of the dial")
        app.typeText("Take meds 9pm")
        let optIn = app.descendants(matching: .any)["switchOverdueToggle"].firstMatch
        optIn.tap()
        snapshot("2 The switch card with a time and the toggle")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(switchName.waitForNonExistence(timeout: 5))
        XCTAssertTrue(switchTile("Take meds").waitForExistence(timeout: 5), "on the board")
        XCTAssertTrue(lights("0 of 1 on").exists)
        snapshot("3 The new switch on Before Bed")

        // A loose switch opted in, with a time already past today: it is in Today as today's task.
        app.buttons["addSwitchTile"].tap()
        XCTAssertTrue(switchName.waitForExistence(timeout: 5))
        app.typeText("Take vitamins 12:05am")
        optIn.tap()
        app.buttons["switchSave"].tap()
        XCTAssertTrue(switchName.waitForNonExistence(timeout: 5))
        let today = app.buttons["tab-today"]
        today.tap()
        XCTAssertTrue(text("Take vitamins").waitForExistence(timeout: 5), "opted in, past its time: today's task")
        // The board's day starts at its 04:00 reset: between midnight and 04:00 it is still yesterday's board day,
        // whose 21:00 has passed, so the switch is rightly in Today then (this ran at 00:30 once and failed).
        if (4..<21).contains(Calendar.current.component(.hour, from: Date())) {
            XCTAssertFalse(text("Take meds").exists, "opted in too, but its 21:00 hasn't come")
        }
        snapshot("4 Today with an opted-in switch after its time")
    }

    // MARK: A board's card

    func testABoardsCardFromItsNameAndDeleteKeepingItsSwitches() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        let bed = header("Before Bed")
        XCTAssertTrue(bed.waitForExistence(timeout: 10))
        bed.tap()
        let name = app.descendants(matching: .any)["switchboardName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the board's card")
        XCTAssertEqual(name.value as? String, "Before Bed")
        snapshot("1 Before Bed's card")
        app.buttons["switchboardDelete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["switchboardDeleteRow"].waitForExistence(timeout: 3),
                      "the question sits inside the card")
        snapshot("2 Delete: keep its switches or not")
        app.buttons["switchboardDeleteKeep"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(bed.waitForNonExistence(timeout: 5), "the board is gone")
        XCTAssertTrue(switchTile("Take meds").exists, "its switches stay, loose")
        snapshot("3 Before Bed deleted, its switches kept")
    }

    // MARK: Helpers

    private static func argument(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }

    /// Scrolls until Before Bed's header sits near the top, its switches in view.
    private func scrollToBeforeBed() {
        let bed = header("Before Bed")
        for _ in 0..<4 where bed.frame.minY > app.frame.height * 0.3 {
            app.swipeUp(velocity: .slow)
        }
    }

    private func openFlipboard() {
        let tab = app.buttons["tab-flipboard"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    private func header(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'switchboardHeader' AND label == %@", name)).firstMatch
    }

    /// A board's lights, read as one element: "2 of 4 on. Off: …".
    private func lights(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'boardLights' AND label BEGINSWITH %@", prefix)).firstMatch
    }

    /// A switch's whole tile.
    private func switchTileFrame(_ title: String) -> CGRect {
        app.descendants(matching: .any).matching(identifier: "flipSwitchTile")
            .containing(NSPredicate(format: "label == %@", title)).firstMatch.frame
    }

    private func line(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'switchboardLine' AND label CONTAINS %@", text)).firstMatch
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A tile's rocker (its accessibility label is the switch's title).
    private func switchTile(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
