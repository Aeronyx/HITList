import XCTest

/// Settings → Stream Ring on the iPhone (brief 176), against the relay the app keeps in its own process in Debug
/// (`-streamInboxDemo YES`: one capture waiting, "Call the dentist tomorrow at 9am p2."), so nothing reaches a
/// network: the page not connected, a link that isn't one, Connect, the capture made a task, a test capture, the
/// "starts with Task" rule, Reconnect Stream… near the end of Stream's connection, Disconnect, and the rows behind the
/// troubleshooting gesture. Each launch has a store and settings of its own, sync off, no tips. Pictures land in the
/// .xcresult (`xcrun xcresulttool export attachments`).
final class StreamRingUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The pretend relay's link (`StreamInboxFakeRelay.demoHost`, `.demoKey`).
    private static let demoLink = "https://demo-relay.example/#demo0000demo1111demo2222demo3333demo4444demo5555demo6666demo7777"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s176-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-streamInboxDemo", "YES"]
    }

    // MARK: The tests

    func testConnectingMakesTheWaitingCaptureATask() {
        app.launchArguments += ["-settingsAsFriend", "YES"]
        app.launch()
        openStreamRing()
        XCTAssertTrue(element("stream-ring-link").waitForExistence(timeout: 5), "not connected: the link's field")
        XCTAssertTrue(element("stream-ring-paste").exists, "Paste beside it")
        XCTAssertFalse(element("stream-ring-connect").isEnabled, "Connect waits for a link")
        XCTAssertFalse(element("stream-ring-troubleshooting").exists, "a friend's device: no troubleshooting rows")
        shot("01 Stream Ring, not connected")

        type(into: "stream-ring-link", "hello")
        element("stream-ring-connect").tap()
        let problem = element("stream-ring-connect-problem")
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertTrue(problem.label.contains("That isn't an inbox link"), problem.label)
        element("stream-ring-link").tap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "hello".count))

        connect()
        shot("02 Stream Ring, connected")
        XCTAssertTrue(waitForLabel(of: "stream-ring-status", containing: "added today"), "the waiting capture was added")
        closeSettings()
        tab("inbox")
        XCTAssertTrue(app.staticTexts["Call the dentist"].waitForExistence(timeout: 10), "the capture is a task in the Inbox")
        shot("03 Inbox with the capture")
    }

    func testATestCaptureArrivesWhateverTheRuleSays() {
        app.launchArguments += ["-settingsAsFriend", "YES"]
        app.launch()
        openStreamRing()
        connect()
        let rule = element("stream-ring-only-task")
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        rule.tap()
        pause()
        element("stream-ring-test").tap()
        XCTAssertTrue(waitForLabel(of: "stream-ring-status", containing: "2 added today"), "the test capture was added too")
        closeSettings()
        tab("inbox")
        XCTAssertTrue(app.staticTexts["Test capture from your Stream ring"].waitForExistence(timeout: 10))
    }

    func testReconnectingStreamShowsNearTheEndAndDisconnectAsks() {
        app.launchArguments += ["-settingsAsFriend", "YES", "-streamInboxDemoDaysLeft", "10"]
        app.launch()
        openStreamRing()
        connect()
        let reconnect = element("stream-ring-reconnect")
        XCTAssertTrue(reconnect.waitForExistence(timeout: 5), "ten days left: Reconnect Stream…")
        XCTAssertTrue(reconnect.label.contains("Reconnect Stream…"), reconnect.label)
        shot("04 Stream Ring, Stream's connection ending")

        scroll(to: element("stream-ring-disconnect"))
        element("stream-ring-disconnect").tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Disconnect asks first")
        alert.buttons["Disconnect"].tap()
        XCTAssertTrue(element("stream-ring-link").waitForExistence(timeout: 5), "not connected again")
    }

    func testTheTroubleshootingRowsShowWhatTheRelayHeard() {
        app.launch() // a Debug side store shows the rows, as a revealed device does
        openStreamRing()
        connect()
        let rows = element("stream-ring-troubleshooting")
        scroll(to: rows)
        XCTAssertTrue(rows.exists)
        XCTAssertTrue(app.staticTexts["Stream tool's arguments"].exists)
        XCTAssertTrue(app.staticTexts["limit, days"].exists, "what Stream's tool takes, as the relay heard it")
        shot("05 Stream Ring, revealed")
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
    }

    /// Browse's gear, then the Stream Ring row, below the first screen's fold.
    private func openStreamRing() {
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "Settings opened")
        let row = element("settings-page-streamRing")
        scroll(to: row)
        row.tap()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 5), "the page opened")
        pause()
    }

    private func connect() {
        type(into: "stream-ring-link", Self.demoLink)
        element("stream-ring-connect").tap()
        XCTAssertTrue(waitForLabel(of: "stream-ring-status", containing: "Connected"), "connected")
        pause()
    }

    private func type(into id: String, _ text: String) {
        let field = element(id)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        pause(0.4)
        app.typeText(text)
    }

    private func waitForLabel(of id: String, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let target = element(id)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // The status line keeps its short parts whole with no-break spaces.
            if target.exists, target.label.replacingOccurrences(of: "\u{00A0}", with: " ").contains(text) { return true }
            pause(0.3)
        }
        return false
    }

    private func closeSettings() {
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element("settings-profile").waitForNonExistence(timeout: 5), "Settings closed")
        pause(0.6)
    }

    /// Drags the sheet up until `target` is on screen, clear of the bar and the screen's foot.
    private func scroll(to target: XCUIElement) {
        let bottom = app.frame.height - 60
        for _ in 0..<8 {
            if target.exists, target.isHittable, target.frame.minY > 120, target.frame.maxY < bottom { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)))
            pause(0.5)
        }
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    private func shot(_ name: String) {
        pause(0.4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
