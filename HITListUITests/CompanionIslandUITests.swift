import XCTest

/// Brief 104, item 7: each companion on the crown of the upright island on the iPhone Duo's outer display, on a tab's
/// first screen and on a pushed one (Browse, under the system's Back), with and without `-duoStatusPad 60` (a call
/// widening the camera island, which the simulator can't place). On a pushed screen during a call the column leaves
/// 36 pt: only a companion that fits there shows. Saves each screen as a PNG in the runner's temporary folder
/// (`CompanionIsland/`) and as an attachment, for the brief's contact sheet (the companion is hidden from VoiceOver,
/// so it is looked at, not queried). `COMPANION_ISLAND_ONLY=flint,hush` in the runner's environment narrows the cast.
///
/// Runs only where the island stands upright (an `iPhone Duo` simulator, folded onto its outer display):
///
///     xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,id=<Duo UDID>' -only-testing:HITListUITests/CompanionIslandUITests
final class CompanionIslandUITests: XCTestCase {
    /// Each companion and its own theme.
    static let cast = [("nod", "slate"), ("quill", "midnight"), ("hush", "nord"), ("tuck", "moss"), ("glim", "tokyo"),
                       ("phase", "mocha"), ("button", "rose"), ("flint", "graphite")]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testEachCompanionOnTheIslandOnFirstAndPushedScreens() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CompanionIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["COMPANION_ISLAND_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        for (id, theme) in Self.cast where only?.contains(id) ?? true {
            for pad in ["0", "60"] {
                let app = XCUIApplication()
                app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s104d"
                app.launchArguments = ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-companionHour", "12",
                                       "-companion", id, "-pref.theme", theme, "-duoStatusPad", pad]
                app.launch()
                XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 20), "\(id): the app is up")
                let inbox = app.buttons["tab-inbox"].frame, today = app.buttons["tab-today"].frame
                try XCTSkipUnless(today.minY >= inbox.maxY - 1, "the island stands upright only on the Duo's outer display")
                Thread.sleep(forTimeInterval: 2.5)
                save(folder, "\(id)-first-pad\(pad)")
                let browse = app.buttons["browseButton"].firstMatch
                XCTAssertTrue(browse.waitForExistence(timeout: 5), "\(id): the magnifying glass")
                browse.tap()
                XCTAssertTrue(app.textFields["browseSearch"].waitForExistence(timeout: 8), "\(id): Browse opened")
                Thread.sleep(forTimeInterval: 2)
                save(folder, "\(id)-pushed-pad\(pad)")
                app.terminate()
            }
        }
        print("Companion island screens: \(folder.path)")
    }

    private func save(_ folder: URL, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
