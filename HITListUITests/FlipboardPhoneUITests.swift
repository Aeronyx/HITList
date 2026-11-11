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

    // MARK: Helpers

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
