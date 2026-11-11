import XCTest

/// Brief 96 on iPhone: the Flipboard on the phone. The empty board (the Add a Switch tile alone, no paragraphs, no New
/// Switchboard), the Add a Switch card empty, typed, and with a time and a Switchboard, a switch dragged onto a
/// Switchboard and back off it, and Duplicate. Each launch has a store of its own (`HITLIST_STORE_SUFFIX`), sync off,
/// no tips. Screenshots land in the .xcresult.
final class FlipboardPhoneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    // MARK: Pictures of the board and the card

    /// A fresh store: the empty board, then the card it opens, empty and typed.
    func testTheEmptyBoardAndTheCard() throws {
        app.launch()
        openFlipboard()
        let tile = app.buttons["addSwitchTile"], old = app.buttons["Add a Switch"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5) || old.exists, "a way to add a switch")
        snapshot("1 The empty Flipboard")
        (tile.exists ? tile : old).tap()
        let name = element("switchName")
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the name has the keyboard")
        settle()
        snapshot("2 The card, empty")
        app.typeText("Water the plants")
        settle()
        snapshot("3 The card, typed")
    }

    /// The demo week: the card from the + tile with a name, a time from the time control and Before Bed from the
    /// Switchboard picker.
    func testTheCardWithATimeAndASwitchboard() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        XCTAssertTrue(switchTile("Water the plants").waitForExistence(timeout: 10))
        snapshot("1 The demo board")
        app.buttons["addSwitchTile"].tap()
        let name = element("switchName")
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the card")
        app.typeText("Stretch")
        setTime("7am")
        settle()
        snapshot("2 The card with a time")
        let boards = element("switchBoardMenu")
        XCTAssertTrue(boards.waitForExistence(timeout: 3), "the Switchboard picker")
        boards.tap()
        let bed = app.buttons["Before Bed"].firstMatch
        XCTAssertTrue(bed.waitForExistence(timeout: 3), "Before Bed in the picker")
        bed.tap()
        XCTAssertTrue(element("switchBoardLine").waitForExistence(timeout: 3), "Daily, with Before Bed")
        settle()
        snapshot("3 The card with a time and a Switchboard")
    }

    /// A fresh store: no Switchboard anywhere until the card's own picker offers one. New Switchboard… turns the card
    /// into the Switchboard card; saved, the switch card comes back as it was typed, on the new board.
    func testANewSwitchboardFromTheCardsPicker() throws {
        app.launch()
        openFlipboard()
        let tile = app.buttons["addSwitchTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["New Switchboard"].exists, "not a starting option")
        tile.tap()
        let name = element("switchName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.typeText("Take meds")
        element("switchBoardMenu").tap()
        let make = app.buttons["New Switchboard…"].firstMatch
        XCTAssertTrue(make.waitForExistence(timeout: 3), "New Switchboard… in the picker")
        make.tap()
        let boardName = element("switchboardName")
        XCTAssertTrue(boardName.waitForExistence(timeout: 5), "the Switchboard card in the switch card's place")
        settle()
        app.typeText("Before Bed")
        snapshot("1 New Switchboard from the card")
        app.buttons["switchboardSave"].tap()
        XCTAssertTrue(element("switchBoardLine").waitForExistence(timeout: 5), "back, on the new board")
        XCTAssertTrue((name.value as? String ?? "").contains("Take meds"), "the switch as it was typed")
        settle()
        snapshot("2 Back on the switch card, Before Bed chosen")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        let header = app.buttons.matching(NSPredicate(format: "identifier == 'switchboardHeader' AND label == 'Before Bed'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "the new board")
        XCTAssertTrue(switchTile("Take meds").exists, "its switch")
        snapshot("3 The board with its switch")
    }

    // MARK: Dragging a switch onto a Switchboard (item 3)

    /// The demo week: a loose switch pressed, held and moved onto Before Bed lands on it ("2 of 5"); dragged back onto
    /// the loose switches it leaves it ("2 of 4"). A long press held still still opens the menu, and a tap still flips.
    func testDraggingASwitchOntoASwitchboardAndOff() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        let water = switchTile("Water the plants")
        XCTAssertTrue(water.waitForExistence(timeout: 10))
        let bed = boardHeader("Before Bed")
        XCTAssertTrue(bed.waitForExistence(timeout: 5))
        XCTAssertTrue(boardLine(containing: "2 of 4").exists)

        // Held still: the menu, as before.
        water.press(forDuration: 1.0)
        let menu = app.buttons["Remove from Flipboard"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3), "the menu")
        snapshot("1 Held still: the menu")
        // A tap on the dimmed board beside the menu closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 3), "the menu closed")

        // The loose switches' first row and Before Bed's together on the screen.
        scroll(by: 0.2)
        // Held until it lifts, then moved at once onto Before Bed (moving while the menu shows, a finger that crosses
        // the menu picks an item instead), and held there a moment before letting go.
        water.press(forDuration: 0.6, thenDragTo: bed, withVelocity: .default, thenHoldForDuration: 2)
        XCTAssertTrue(boardLine(containing: "2 of 5").waitForExistence(timeout: 5), "on Before Bed now")
        snapshot("2 Dropped on Before Bed")

        // Back off it: dragged onto the loose switches' + tile, which stands just above Before Bed, once both are clear
        // of the bars (the board has centred the switch where it landed).
        let addTile = app.buttons["addSwitchTile"]
        let moved = switchTile("Water the plants")
        XCTAssertTrue(moved.waitForExistence(timeout: 3))
        for _ in 0..<4 {
            if addTile.frame.minY < 120 {
                scroll(by: -0.12)
            } else if moved.frame.maxY > app.frame.height - 110 {
                scroll(by: 0.1)
            } else {
                break
            }
        }
        moved.press(forDuration: 0.6, thenDragTo: addTile, withVelocity: .default, thenHoldForDuration: 1.0)
        XCTAssertTrue(boardLine(containing: "2 of 4").waitForExistence(timeout: 5), "off Before Bed again")
        snapshot("3 Dragged back onto the loose switches")
    }

    /// Scrolls the board by `fraction` of the screen's height (positive: further down the board), from the screen's
    /// right edge, where no tile's long press can start.
    private func scroll(by fraction: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.55))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.55 - fraction))
        // Held at the end, so the board stops where the finger does (no momentum: the same distance every run).
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        Thread.sleep(forTimeInterval: 0.6)
    }

    // MARK: Duplicate (item 4)

    /// Duplicate in a switch's menu: the card with its settings (Before Bed, 9:00 PM) and an empty name, the keyboard up;
    /// × leaves nothing behind; a name and Add make a second switch beside the first.
    func testDuplicateOpensTheCardWithTheSwitchsSettings() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        let meds = switchTile("Take meds")
        XCTAssertTrue(meds.waitForExistence(timeout: 10))
        if !meds.isHittable { app.swipeUp(velocity: .slow) }
        meds.press(forDuration: 1.0)
        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 3))
        duplicate.tap()
        let name = element("switchName")
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard up")
        XCTAssertTrue(element("switchBoardLine").exists, "on Before Bed, as the original")
        let time = element("switchTime")
        XCTAssertTrue(time.exists && (time.label.contains("9:00") || time.label.contains("21:00")), "its time: \(time.label)")
        XCTAssertTrue((name.value as? String ?? "").isEmpty || (name.value as? String) == "Switch name", "an empty name")
        settle()
        snapshot("1 Duplicate: the card filled in, the name empty")

        // × with nothing typed: gone, nothing added.
        app.buttons["switchClose"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Take meds'")).count, 1)

        meds.press(forDuration: 1.0)
        XCTAssertTrue(duplicate.waitForExistence(timeout: 3))
        duplicate.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.typeText("Take vitamins")
        app.buttons["switchSave"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(switchTile("Take vitamins").waitForExistence(timeout: 5), "the copy")
        XCTAssertTrue(switchTile("Take meds").exists, "the original")
        XCTAssertTrue(boardLine(containing: "2 of 5").exists, "both on Before Bed")
        snapshot("2 The copy beside the original")
    }

    // MARK: Helpers

    private func boardHeader(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'switchboardHeader' AND label == %@", name)).firstMatch
    }

    private func boardLine(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'switchboardLine' AND label CONTAINS %@", text)).firstMatch
    }

    /// The time: the compact time control, whose tap opens a field in its place.
    private func setTime(_ typed: String) {
        let control = element("switchTime")
        XCTAssertTrue(control.waitForExistence(timeout: 3), "the time control")
        control.tap()
        let field = app.textFields["switchTimeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3) || app.textFields["switchTime"].exists, "a field for the time")
        app.typeText(typed + "\n")
    }

    /// Lets a card finish arriving (the keyboard and the card's own entrance) before a picture.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func openFlipboard() {
        let tab = app.buttons["tab-flipboard"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
