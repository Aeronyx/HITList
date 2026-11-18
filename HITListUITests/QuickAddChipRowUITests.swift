import XCTest

/// Brief 162 on iPhone: quick add's chips are one row that scrolls sideways (George, 2026-11-18: "a horizontally
/// scrolling bar, not one that wraps"). With three labels and a deadline the card is as tall as with none, the row
/// is one chip high, and the Group chip ("Inbox") can be brought whole into view and opened. Pictures of the card
/// at each step land in the .xcresult, and in `TEST_RUNNER_HITLIST_SHOTS_DIR` when it is set.
final class QuickAddChipRowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s162-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        XCUIDevice.shared.orientation = .portrait
    }

    func testRowScrollsInsteadOfWrapping() {
        app.launch()
        let inbox = app.buttons["tab-inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 30), "the app is up")
        inbox.tap()
        pause(1)
        app.buttons["quickAddButton"].firstMatch.tap()
        let card = element("quickAddCard")
        let bar = element("quickAddOptionBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the card is open")
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        pause(1)
        let emptyCard = card.frame, emptyBar = bar.frame, emptyTitle = element("quickAddTitle").frame
        let chipHeight = element("quickAddDateChip").frame.height
        shot("01 empty card")

        app.typeText("Pick up the parcel @errands @townhall @weekend ")
        pause(1)
        // "+" → Deadline, then Tomorrow.
        element("quickAddPlus").tap()
        let deadline = app.buttons["Deadline"].firstMatch
        XCTAssertTrue(deadline.waitForExistence(timeout: 3), "the + menu")
        deadline.tap()
        let tomorrow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tomorrow")).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 4), "the deadline card")
        tomorrow.tap()
        pause(1.5)
        XCTAssertTrue(element("quickAddDeadlineChip").exists, "the deadline chip")
        shot("02 three labels and a deadline")

        // The card is as tall as with no chips added, but for the title's own lines (a long title wraps by design).
        let titleGrowth = element("quickAddTitle").frame.height - emptyTitle.height
        let fullCard = card.frame, fullBar = bar.frame
        XCTAssertEqual(fullCard.height - titleGrowth, emptyCard.height, accuracy: 0.5, "the chips added no height")
        XCTAssertEqual(fullBar.height, emptyBar.height, accuracy: 0.5, "the row is still one line")
        XCTAssertLessThan(fullBar.height, chipHeight * 1.5, "one chip high")
        // The row stays inside the card's padding: its edges are in line with the title's.
        let title = element("quickAddTitle").frame
        XCTAssertEqual(fullBar.minX, title.minX, accuracy: 1, "the row starts in line with the title")
        XCTAssertLessThanOrEqual(fullBar.maxX, card.frame.maxX - 12, "the row ends inside the card's padding")

        // The Group chip, whole and tappable once the row is scrolled to it.
        let group = element("quickAddGroupChip")
        XCTAssertTrue(group.exists)
        for _ in 0..<3 where !(group.isHittable && fullBar.contains(group.frame)) {
            bar.swipeRight()
            pause(0.6)
        }
        XCTAssertTrue(group.isHittable, "Inbox can be reached")
        group.tap()
        XCTAssertTrue(app.buttons["Inbox"].firstMatch.waitForExistence(timeout: 3) || app.popovers.firstMatch.exists,
                      "the Group card opened")
        shot("03 the Group card from the scrolled row")
        pause(0.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        pause(1)

        // Scrolled to the end, the last chip ends at the card's padding, whole.
        bar.swipeLeft()
        bar.swipeLeft()
        pause(1)
        let last = element("quickAddDeadlineChip").frame
        XCTAssertLessThanOrEqual(last.maxX, bar.frame.maxX + 0.5, "the last chip is whole at the row's end")
        XCTAssertGreaterThanOrEqual(card.frame.maxX - last.maxX, 12 - 0.25, "the card's padding after the last chip")
        shot("04 scrolled to the end")
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

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
