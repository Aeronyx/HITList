import XCTest

/// Brief 144: the bolt and Settings → iCloud & data on HITList's own engine, every state, from the Debug demo
/// (`-syncEngineDemo <state>`: a made-up engine status on a side store, no engine and no iCloud needed). Each test
/// launches a store of its own, reads the bolt's words, opens iCloud & data from the bolt and checks the rows that
/// state has. With `HITLIST_SHOTS_DIR` set (a folder on the Mac), it also saves the pictures for the hand-over sheet.
final class SyncEngineStatusUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ state: String) {
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-s144-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-syncEngineDemo", state]
        app.launch()
    }

    private var bolt: XCUIElement { app.buttons["syncBolt"].firstMatch }

    /// Opens iCloud & data from the bolt, as a person would.
    private func openICloudPage() {
        XCTAssertTrue(bolt.waitForExistence(timeout: 15))
        bolt.tap()
        XCTAssertTrue(element("settings-engine-sync-now").waitForExistence(timeout: 8), "the engine's Sync now row")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Saves the screen as `<state>-<what>.png` in `HITLIST_SHOTS_DIR` (on the Mac), and attaches it to the result.
    private func shot(_ state: String, _ what: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(state)-\(what)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(state)-\(what).png"))
    }

    private func check(_ state: String, words: String, holdButtons: [String] = [], extra: [String] = []) {
        launch(state)
        XCTAssertTrue(bolt.waitForExistence(timeout: 15))
        XCTAssertEqual(bolt.label, words, "the bolt's words in \(state)")
        shot(state, "bolt")
        openICloudPage()
        XCTAssertTrue(element("settings-engine-waiting").exists)
        // Check iCloud… is the mirror's audit: hidden on the engine.
        XCTAssertFalse(element("settings-check-icloud").exists, "Check iCloud… on the engine")
        shot(state, "icloud")
        for id in extra { XCTAssertTrue(element(id).waitForExistence(timeout: 3), "\(id) in \(state)") }
        guard !holdButtons.isEmpty else { return }
        let first = element(holdButtons[0])
        if !first.isHittable { app.swipeUp(velocity: .slow) }
        for id in holdButtons { XCTAssertTrue(element(id).waitForExistence(timeout: 3), "\(id) in \(state)") }
        shot(state, "hold")
    }

    func testSynced() { check("synced", words: "Synced just now") }
    func testWaiting() { check("waiting3", words: "3 changes waiting to go to iCloud") }
    func testChecking() { check("checking", words: "Checking with iCloud…") }
    func testMassDeletion() {
        check("mass248", words: "248 items are missing from this device. Nothing has been deleted in iCloud.",
              holdButtons: ["settings-engine-deleted-them", "settings-engine-keep"])
    }
    func testPurged() {
        check("purged", words: "HITList's data was removed from iCloud in Settings.",
              holdButtons: ["settings-engine-remove-here", "settings-engine-send-again"])
    }
    func testNeedsUpdate() {
        check("update", words: "Update HITList to sync: iCloud holds data from a newer version.", extra: ["settings-engine-hold"])
    }
    func testFull() {
        check("full12", words: "iCloud is full: 12 changes are waiting.", holdButtons: ["settings-engine-try-again"])
    }
    func testFailed() {
        check("failed", words: "Sync stopped: this device's sync records could not be read",
              holdButtons: ["settings-engine-try-again"])
    }
    func testRefused() {
        check("refused2", words: "2 items couldn't go to iCloud; Settings → iCloud names them",
              extra: ["settings-engine-refused", "settings-engine-refused-names"])
    }
    func testSignedOut() { check("signedout", words: "Not signed in to iCloud") }
}
