import XCTest

/// Round 34: a move between the engines that waits for the next start is finished by the app itself
/// (`SyncEngineMoveFinish`): an iPhone ends its own process once it is left, and never while something a person may
/// be typing in is open over it. This is the whole road on a simulator, with no iCloud: the move made by hand from
/// the group in Settings → iCloud & data (shown on a Debug side store), HITList left with Settings still open (it
/// stays alive), then left from its main screen (the process ends, as the system ends a background app every day).
/// A store of its own each run, so the preference the move writes is never read again.
final class MoveFinishUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testAWaitingMoveEndsTheAppOnceItIsLeftAndNeverUnderSettings() throws {
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-finish-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        app.launch()

        // Settings → iCloud & data, from the bolt, as a person would; the group that moves this store is at its foot.
        let bolt = app.buttons["syncBolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 15))
        bolt.tap()
        let move = element("settings-engine-move")
        XCTAssertTrue(move.waitForExistence(timeout: 8), "the group that moves this store (a Debug side store shows it)")
        for _ in 0..<10 where !move.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(move.isHittable)
        move.tap()

        // The question's own button (the row carries the same words, under its identifier).
        let ask = NSPredicate(format: "label == %@ AND identifier != %@", "Move to the new sync", "settings-engine-move")
        let confirm = app.buttons.matching(ask).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the question before the move")
        confirm.tap()

        // Moved: a backup, the preference, and the words that say the app finishes it.
        let message = element("settings-engine-move-message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), "the move's message")
        XCTAssertTrue(message.label.contains("the next time you leave it"), message.label)

        // Left with Settings open over it: something a person may be in the middle of. The app stays.
        XCUIDevice.shared.press(.home)
        wait(4)
        XCTAssertNotEqual(app.state, .notRunning, "HITList ended itself under an open sheet")
        app.activate()
        XCTAssertTrue(message.waitForExistence(timeout: 8), "back where it was, Settings still open")

        // Settings closed, HITList left from its main screen: the process ends, so the next opening is on the
        // other sync.
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(bolt.waitForExistence(timeout: 8))
        wait(1)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "the move was not finished when HITList was left")
    }
}
