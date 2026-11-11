import XCTest

/// Brief 74: the real widgets on the iPhone's Home Screen, put there through SpringBoard's widget gallery the way a
/// person does it, one screenshot each, kept in the .xcresult. It needs a build whose extension reads this run's side
/// store (`HITLIST_WIDGET_SUFFIX`, a Debug-only build setting), so it is skipped in ordinary runs:
///
///     TEST_RUNNER_HITLIST_WIDGETS=1 xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,name=HITList-74' -only-testing:HITListUITests/WidgetsUITests \
///       HITLIST_WIDGET_SUFFIX=widgets -resultBundlePath build.noindex/widgets.xcresult
///     xcrun xcresulttool export attachments --path build.noindex/widgets.xcresult --output-path build.noindex/widgets
///
/// It changes the simulator's Home Screen, so run it on a simulator of your own. Brief 81 adds the tap to checked to gone
/// (`testCheckingATaskOnTheTodayWidget`, same build setting, `-only-testing:` it alone).
final class WidgetsUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_WIDGETS"] == "1",
                          "the widgets tour runs only when asked (TEST_RUNNER_HITLIST_WIDGETS=1)")
        continueAfterFailure = true
    }

    /// Opens the app once on the side store the extension reads, so the snapshot exists, then goes home.
    private func writeTheSnapshot() {
        let app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "widgets"
        app.launchArguments = ["-disableCloudKit", "YES", "-seedDemoData", "YES", "-hideTips"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        sleep(3) // the writer's debounce, then its write
        XCUIDevice.shared.press(.home)
        sleep(1)
    }

    /// Every page of HITList's widget gallery (each widget in each size), added to the Home Screen one at a time, with a
    /// screenshot of the gallery's page and of the Home Screen after each. Each new widget lands at the top of the page.
    func testTheWidgetsOnTheHomeScreen() throws {
        writeTheSnapshot()
        var page = 0
        var pages = 1
        while page < pages {
            openGallery()
            let indicator = springboard.pageIndicators.matching(NSPredicate(format: "value BEGINSWITH 'page'")).firstMatch
            XCTAssertTrue(indicator.waitForExistence(timeout: 5), "the gallery's sizes")
            if let total = (indicator.value as? String)?.split(separator: " ").last.flatMap({ Int($0) }) { pages = total }
            for _ in 0..<page {
                springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'HITList,'")).firstMatch.swipeLeft()
                usleep(700_000)
            }
            let widget = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'HITList,'"))
                .allElementsBoundByIndex.first { $0.isHittable }
            let name = [widget?.label, widget?.value as? String].compactMap { $0 }.joined(separator: " ")
            attach("\(page + 1) gallery · \(name)")
            springboard.buttons[" Add Widget"].firstMatch.tap()
            sleep(2)
            springboard.buttons["Done"].firstMatch.tap()
            sleep(3)
            attach("\(page + 1) home · \(name)")
            page += 1
        }
        dump("home, every widget")
    }

    // MARK: - Brief 81: a tap to checked to gone

    /// The Today widget's check, tapped on the Home Screen with the app not running: the row goes checked at once, and
    /// leaves once its (pretend, `-widgetExportDelay 4`) export has finished, the next task taking its place. A frame
    /// every half second is kept in the .xcresult; the simulator's log says which process ran the intent ("recorded
    /// by", category widgets). The build needs `HITLIST_WIDGET_SUFFIX=widgets` (the app the system launches for the tap
    /// gets no arguments and opens that side store with sync off, `WidgetDebug`).
    func testCheckingATaskOnTheTodayWidget() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "widgets"
        app.launchArguments = ["-disableCloudKit", "YES", "-seedDemoData", "YES", "-hideTips", "-widgetExportDelay", "4"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        sleep(3) // the writer's debounce, then its write
        app.terminate() // not running when the widget is tapped
        XCUIDevice.shared.press(.home)
        sleep(1)

        addWidget(page: 1) // Today, medium
        // A widget's check is a toggle: a switch to accessibility, a button on some systems.
        let checks = springboard.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Complete '"))
        guard checks.firstMatch.waitForExistence(timeout: 10) else {
            dump("no check found")
            return XCTFail("the Today widget's checks are buttons on the Home Screen")
        }
        let check = checks.firstMatch
        let title = String(check.label.dropFirst("Complete ".count))
        attach("0 before · \(title)")
        check.tap()
        let tapped = Date()

        var sawChecked = false, gone = false
        for step in 1...40 {
            usleep(500_000)
            let seconds = String(format: "%.1f", Date().timeIntervalSince(tapped))
            let checked = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "\(title), checked")).firstMatch.exists
            let toggle = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Complete \(title)")).firstMatch
            let stillThere = toggle.exists
            // The toggle drawn on at once (value 1), before the app has run; then the row drawn as a tap on its way.
            let turned = stillThere && "\(toggle.value ?? "")" == "1"
            if checked { sawChecked = true }
            attach("\(step) +\(seconds) s · \(checked ? "checked" : turned ? "check turned" : stillThere ? "open" : "gone")")
            if sawChecked, !checked, !stillThere { gone = true; break }
        }
        dump("after the tap")
        XCTAssertTrue(sawChecked, "the row went checked")
        XCTAssertTrue(gone, "and left once the export had finished")
    }

    /// Adds the widget on gallery page `page` (0 Today small, 1 Today medium, 2 Today large, …) to the Home Screen.
    private func addWidget(page: Int) {
        openGallery()
        for _ in 0..<page {
            springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'HITList,'")).firstMatch.swipeLeft()
            usleep(700_000)
        }
        springboard.buttons[" Add Widget"].firstMatch.tap()
        sleep(2)
        springboard.buttons["Done"].firstMatch.tap()
        sleep(3)
    }

    /// Edit mode, Edit → Add Widget, search for HITList, its page.
    private func openGallery() {
        // The dock's empty end: free on every page, however full the page gets.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.93)).press(forDuration: 2)
        sleep(1)
        springboard.buttons["Edit"].tap()
        let add = springboard.buttons["Add Widget"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3), "Edit → Add Widget")
        add.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the gallery's search")
        search.tap()
        search.typeText("HITList")
        let cell = springboard.cells["HITList"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "HITList in the gallery")
        cell.tap()
        sleep(2)
    }

    private func dump(_ name: String) {
        attach(name)
        let tree = XCTAttachment(string: springboard.debugDescription)
        tree.name = name + " tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
