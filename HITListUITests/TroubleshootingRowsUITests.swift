import XCTest

/// Round 35, brief 174: Settings → iCloud & data as a friend sees it, and the rows behind the gesture. A friend's
/// device is played by a Debug side store launched with `-settingsAsFriend YES` (without it a side store shows the
/// troubleshooting rows, as UI tests need). Seven taps on About's Version row bring the "For troubleshooting" group;
/// About's "Troubleshooting rows: Showing" row hides it again. Send sync log… opens the share sheet with no viewer in
/// between. With `HITLIST_SHOTS_DIR` set (a folder on the Mac), `testPictures` saves the hand-over pictures.
final class TroubleshootingRowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(demo: String? = nil, friend: Bool = true) {
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-s174-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        if friend { app.launchArguments += ["-settingsAsFriend", "YES"] }
        if let demo { app.launchArguments += ["-syncEngineDemo", demo] }
        app.launch()
    }

    // MARK: The gesture

    func testSevenTapsOnTheVersionShowTheGroupAndAboutHidesItAgain() {
        launch(demo: "synced")
        openICloudFromTheBolt()
        XCTAssertFalse(element("settings-troubleshooting").exists, "a friend's page has no troubleshooting group")
        XCTAssertFalse(element("settings-sync-environment").exists, "nor the environment row")
        XCTAssertFalse(element("settings-engine-switch").exists, "nor the sync engine's rows")
        XCTAssertTrue(element("settings-send-sync-log").exists, "Send sync log… is everyone's")
        back()

        open("settings-page-about")
        XCTAssertFalse(element("settings-troubleshooting-hide").exists, "nothing about it before the taps")
        let version = element("settings-version")
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        for _ in 0..<7 { version.tap() }
        let hide = element("settings-troubleshooting-hide")
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "About says the rows are showing")
        back()

        open("settings-page-iCloud")
        let group = element("settings-troubleshooting")
        scroll(to: group)
        XCTAssertTrue(group.exists, "the group arrived in iCloud & data")
        XCTAssertTrue(element("settings-engine-switch").exists, "with the sync engine's rows")
        back()

        open("settings-page-about")
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        XCTAssertTrue(hide.waitForNonExistence(timeout: 5), "pressed, the row goes with them")
        back()

        open("settings-page-iCloud")
        scroll(to: element("settings-reset-cache"))
        XCTAssertFalse(element("settings-troubleshooting").exists, "hidden again")
        XCTAssertFalse(element("settings-engine-switch").exists)
    }

    // MARK: Send sync log…

    func testSendSyncLogOpensTheShareSheet() {
        launch()
        openICloudFromTheBolt()
        let send = element("settings-send-sync-log")
        scroll(to: send)
        XCTAssertTrue(send.isHittable, "Send sync log… on screen")
        send.tap()
        // The system's share sheet, straight away: no viewer in between.
        let sheet = app.otherElements["ActivityListView"].firstMatch
        let shareSheet = sheet.waitForExistence(timeout: 10) ? sheet : app.navigationBars["UIActivityContentView"].firstMatch
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5), "the share sheet")
        XCTAssertFalse(element("settings-sync-log").exists, "no viewer in between")
    }

    // MARK: The words a friend reads

    /// Every text on the iCloud & data page of a friend's device, on the earlier sync and the new one, read from the
    /// screen while scrolling to its foot: none says CloudKit, environment, Production, Development, engine, zone,
    /// mirror, ledger or transport.
    func testAFriendsPageSaysNoDeveloperWords() {
        for demo in [nil, "synced", "waiting3", "refused2"] as [String?] {
            launch(demo: demo)
            openICloudFromTheBolt()
            var seen: Set<String> = []
            for _ in 0..<10 {
                for text in app.staticTexts.allElementsBoundByIndex where text.exists { seen.insert(text.label) }
                for button in app.buttons.allElementsBoundByIndex where button.exists { seen.insert(button.label) }
                let before = app.screenshot().pngRepresentation
                dragUp()
                if app.screenshot().pngRepresentation == before { break }
            }
            XCTAssertTrue(seen.contains { $0.contains("Send sync log") }, "the walk reached the page's rows: \(seen)")
            let forbidden = ["cloudkit", "environment", "production", "development", "engine", "zone", "mirror",
                             "ledger", "transport"]
            for label in seen {
                let lower = label.lowercased()
                for word in forbidden {
                    XCTAssertFalse(lower.contains(word), "“\(label)” says \(word) (\(demo ?? "earlier sync"))")
                }
            }
            app.terminate()
        }
    }

    // MARK: Pictures

    /// The hand-over pictures: iCloud & data on the earlier sync, on the new sync and with something waiting, as a
    /// friend sees it and once revealed; About before and after the seven taps.
    func testPictures() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] != nil, "pictures on demand")
        for (demo, name) in [(nil, "earlier"), ("synced", "new"), ("waiting3", "new-waiting")] as [(String?, String)] {
            launch(demo: demo)
            openICloudFromTheBolt()
            shotDown("icloud \(name), unrevealed")
            back()
            open("settings-page-about")
            if demo == nil { shot("about, before the taps") }
            let version = element("settings-version")
            XCTAssertTrue(version.waitForExistence(timeout: 5))
            for _ in 0..<7 { version.tap() }
            pause()
            if demo == nil { shot("about, after the taps") }
            back()
            open("settings-page-iCloud")
            shotDown("icloud \(name), revealed")
            app.terminate()
        }
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func openICloudFromTheBolt() {
        let bolt = app.buttons["syncBolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 15))
        bolt.tap()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 8), "iCloud & data opened")
        pause()
    }

    private func open(_ id: String) {
        let row = element(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(id) on screen")
        row.tap()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 5), "\(id) opened a page")
        pause()
    }

    private func back() {
        let back = app.buttons["sheetBack"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        pause()
    }

    private func dragUp() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -520)))
        pause(0.8)
    }

    /// Drags the open page up until `target` is on screen and clear of the sheet's bar and the screen's foot.
    private func scroll(to target: XCUIElement) {
        let top: CGFloat = 140
        let bottom = app.frame.height - 60
        for _ in 0..<12 {
            if target.exists, target.frame.minY > top, target.frame.maxY < bottom { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let up = !target.exists || target.frame.maxY >= bottom
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -320 : 220)))
            pause(0.5)
        }
    }

    private func shotDown(_ name: String) {
        shot("\(name) 1")
        for part in 2...6 {
            let before = app.screenshot().pngRepresentation
            dragUp()
            if app.screenshot().pngRepresentation == before { break }
            shot("\(name) \(part)")
        }
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("iphone \(name).png"))
    }
}
