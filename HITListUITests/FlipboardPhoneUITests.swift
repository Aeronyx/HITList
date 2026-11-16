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
        XCTAssertTrue(element("switchBoardLine").waitForExistence(timeout: 3), "a new switch takes the board's Daily: with Before Bed")
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
        XCTAssertTrue(lights("2 of 4 on").exists)

        // Held still: the menu, as before.
        water.press(forDuration: 1.0)
        let menu = app.buttons["Remove from Flipboard"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3), "the menu")
        snapshot("1 Held still: the menu")
        // A tap on the dimmed board beside the menu closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 3), "the menu closed")

        // Held until it lifts, then moved at once onto Before Bed's panel (moving while the menu shows, a finger that
        // crosses the menu picks an item instead), and held there a moment before letting go.
        drag(water, onto: bed)
        XCTAssertTrue(lights("2 of 5 on").waitForExistence(timeout: 5), "on Before Bed now")
        snapshot("2 Dropped on Before Bed")

        // Back off it: from near the top of its tile, now on Before Bed's row, onto the lower part of the loose switches'
        // Add outline, which stands just above the panel: both held clear of the screen's edges, where a held drag
        // scrolls the board (brief 126: the panel's header between them made the old centre-to-centre drag too long).
        let addTile = app.buttons["addSwitchTile"]
        let moved = tile("Water the plants")
        XCTAssertTrue(moved.waitForExistence(timeout: 3))
        let height = app.frame.height
        for _ in 0..<6 {
            let drop = addTile.frame.minY + addTile.frame.height * 0.85, lift = moved.frame.minY + moved.frame.height * 0.15
            if drop < height * 0.3 {
                scroll(by: -0.06)
            } else if lift > height * 0.7 {
                scroll(by: 0.06)
            } else {
                break
            }
        }
        moved.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.6, thenDragTo: addTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)),
                   withVelocity: .default, thenHoldForDuration: 1.0)
        XCTAssertTrue(lights("2 of 4 on").waitForExistence(timeout: 5), "off Before Bed again")
        snapshot("3 Dragged back onto the loose switches")

        // Brief 126: with the loose switches folded away, their header takes the drop.
        drag(switchTile("Water the plants"), onto: bed)
        XCTAssertTrue(lights("2 of 5 on").waitForExistence(timeout: 5), "on Before Bed again")
        // Back at the top of the board (where a held drag can't scroll it further), folded, and onto the header.
        app.swipeDown()
        app.swipeDown()
        let ungrouped = element("ungroupedHeader")
        XCTAssertTrue(ungrouped.waitForExistence(timeout: 3))
        ungrouped.tap()
        XCTAssertTrue(addTile.waitForNonExistence(timeout: 3), "folded")
        let onBoard = tile("Water the plants")
        XCTAssertTrue(onBoard.waitForExistence(timeout: 3))
        onBoard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: ungrouped.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
                   withVelocity: .default, thenHoldForDuration: 1.2)
        XCTAssertTrue(lights("2 of 4 on").waitForExistence(timeout: 5), "dropped on the folded header: off Before Bed")
        snapshot("4 Dropped on the folded Ungrouped header")
    }

    /// George, 2026-11-16: "when you group switches that already exist … they maintain their old timing", so one group
    /// can hold "one that resets once a week and one that resets every other day". The demo week's loose switch on
    /// every 3 days, dragged onto Before Bed (daily, 04:00): it reads "every 3 days" there as it did, beside the
    /// board's own daily switches; its card on the board has the interval's dial (it was hidden on a board before),
    /// and only the board's own cadence, Daily, makes it reset "with Before Bed".
    func testASwitchGroupedOntoABoardKeepsItsOwnTiming() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        let water = switchTile("Water the plants")
        XCTAssertTrue(water.waitForExistence(timeout: 10))
        let bed = boardHeader("Before Bed")
        XCTAssertTrue(bed.waitForExistence(timeout: 5))
        XCTAssertTrue(detail("every 3 days", on: "Water the plants").exists, "loose: every 3 days")

        drag(water, onto: bed)
        XCTAssertTrue(lights("2 of 5 on").waitForExistence(timeout: 5), "on Before Bed now")
        XCTAssertTrue(detail("every 3 days", on: "Water the plants").waitForExistence(timeout: 3),
                      "and still every 3 days, not the board's every day")
        settle()
        snapshot("1 Grouped on Before Bed, still every 3 days")

        // Its card: the dial with its 3 days, and nothing that says it resets with the board.
        let moved = tile("Water the plants")
        if !switchTile("Water the plants").isHittable { scroll(by: 0.1) }
        switchTile("Water the plants").press(forDuration: 1.0)
        let edit = app.buttons["Edit switch…"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "the menu")
        edit.tap()
        XCTAssertTrue(element("switchName").waitForExistence(timeout: 5), "the card")
        let dial = element("switchIntervalDial")
        XCTAssertTrue(dial.waitForExistence(timeout: 3), "the interval's dial, on a board too")
        XCTAssertEqual(dial.value as? String, "3")
        XCTAssertFalse(element("switchBoardLine").exists, "on its own days: no ‘with Before Bed’")
        settle()
        snapshot("2 Its card on the board: every 3 days")

        // Daily is the board's own cadence: chosen, the switch resets with the board, and the card says so.
        app.buttons["Daily"].firstMatch.tap()
        let with = element("switchBoardLine")
        XCTAssertTrue(with.waitForExistence(timeout: 3), "with Before Bed")
        XCTAssertEqual(with.label, "Resets with Before Bed")
        settle()
        snapshot("3 Daily on a daily board: with Before Bed")
        // And back: any other interval is its own again.
        app.buttons["3 days"].firstMatch.tap()
        XCTAssertTrue(with.waitForNonExistence(timeout: 3))
        app.buttons["switchClose"].tap()
        XCTAssertTrue(element("switchName").waitForNonExistence(timeout: 5))
        XCTAssertTrue(moved.exists)
        XCTAssertTrue(detail("every 3 days", on: "Water the plants").exists, "nothing was saved")
    }

    /// A loose switch held until it lifts and moved onto a board's panel (its header, at the panel's top). The board is
    /// first scrolled so the header stands clear of the foot of the screen, where a held drag scrolls the board on
    /// (brief 126: the panel sets the header 44 pt lower than the old section did, into that zone), with the switch
    /// still clear of the bars; the press starts low on the tile, under its rocker.
    private func drag(_ rocker: XCUIElement, onto header: XCUIElement) {
        // The whole tile, pressed by its caption, well under the rocker: the tile and the panel's header are farther
        // apart than the screen's middle holds otherwise.
        let whole = tile(rocker.label)
        let press = { whole.frame.minY + whole.frame.height * 0.92 }
        for _ in 0..<10 where header.frame.minY > app.frame.height * 0.6 && press() > 200 {
            scroll(by: 0.05)
        }
        whole.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
            .press(forDuration: 0.6, thenDragTo: header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
                   withVelocity: .default, thenHoldForDuration: 1.2)
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
        XCTAssertTrue(lights("2 of 5 on").exists, "both on Before Bed")
        snapshot("2 The copy beside the original")
    }

    // MARK: Switchboards in rows (brief 126)

    /// The demo week: a switch added to Before Bed from the Add switch outline at the end of its row, with a time and a
    /// name that wraps, appears once, in the row's order, and the row scrolls to show it; every tile on the row is one
    /// size, and the board's lights count it. (Item 5, the jitter, is pinned by `FlipboardAddTests`; this is its film.)
    func testASwitchAddedToABoardAppearsInItsRow() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        XCTAssertTrue(switchTile("Water the plants").waitForExistence(timeout: 10))
        XCTAssertTrue(lights("2 of 4 on").waitForExistence(timeout: 5), "Before Bed's lights")
        let add = app.buttons.matching(NSPredicate(format: "identifier == 'switchboardAdd' AND label == 'Add a switch to Before Bed'")).firstMatch
        XCTAssertTrue(add.exists, "the Add switch outline at the end of Before Bed's row")
        add.tap()
        XCTAssertTrue(element("switchName").waitForExistence(timeout: 5), "the card")
        XCTAssertTrue(element("switchBoardLine").waitForExistence(timeout: 3), "on Before Bed")
        settle()
        app.typeText("Lay out tomorrow's clothes and pack the bag")
        setTime("10pm")
        app.buttons["switchSave"].tap()
        let added = switchTile("Lay out tomorrow's clothes and pack the bag")
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", added.label)).count, 1, "once")
        XCTAssertTrue(added.isHittable, "the row scrolled to show it")
        XCTAssertTrue(lights("2 of 5 on").exists, "the lights count it")
        // After Take meds (21:00), before the untimed ones.
        XCTAssertLessThan(switchTile("Take meds").frame.minX, added.frame.minX)
        XCTAssertLessThan(added.frame.minX, switchTile("Brush teeth").frame.minX)
        let row = ["Take meds", "Lay out tomorrow's clothes and pack the bag", "Brush teeth", "Floss", "Read 20 minutes"]
        let size = tile("Take meds").frame.size
        for title in row {
            XCTAssertEqual(tile(title).frame.width, size.width, accuracy: 0.5, title)
            XCTAssertEqual(tile(title).frame.height, size.height, accuracy: 0.5, title)
        }
        snapshot("1 Added to Before Bed, the row scrolled to it")
    }

    /// The demo week: "Ungrouped" over the loose switches folds them away to its one line and back; the boards stay.
    func testUngroupedFoldsAwayAndBack() throws {
        app.launchArguments += ["-seedDemoData"]
        app.launch()
        openFlipboard()
        let water = switchTile("Water the plants")
        XCTAssertTrue(water.waitForExistence(timeout: 10))
        let header = element("ungroupedHeader")
        XCTAssertTrue(header.exists, "a header over the loose switches once there is a board")
        XCTAssertTrue(lights("0 of 2 on").exists, "their lights")
        snapshot("1 Ungrouped, open")
        header.tap()
        XCTAssertTrue(water.waitForNonExistence(timeout: 3), "folded away")
        XCTAssertTrue(boardHeader("Before Bed").exists, "the boards stay")
        XCTAssertTrue(lights("0 of 2 on").exists, "its lights stay in view")
        snapshot("2 Ungrouped, folded")
        header.tap()
        XCTAssertTrue(water.waitForExistence(timeout: 3), "back")
    }

    // MARK: Helpers

    private func boardHeader(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'switchboardHeader' AND label == %@", name)).firstMatch
    }

    /// A board's lights (or the loose switches'), read as one element: "2 of 4 on. Off: …".
    private func lights(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'boardLights' AND label BEGINSWITH %@", prefix)).firstMatch
    }

    /// A switch's whole tile.
    private func tile(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "flipSwitchTile")
            .containing(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// The line under a switch's title on its tile ("every 3 days", "9:00 PM").
    private func detail(_ text: String, on title: String) -> XCUIElement {
        tile(title).staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
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
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        // A session's pictures: `TEST_RUNNER_PICTURES_DIR=<folder> xcodebuild test …` writes each one there too.
        if let folder = ProcessInfo.processInfo.environment["PICTURES_DIR"] {
            let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "simulator"
            let file = "\(device)-\(name.replacingOccurrences(of: " ", with: "-")).png"
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(file))
        }
    }
}
