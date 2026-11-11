import XCTest

/// The supervisor's screenshot pass (SUPERVISOR §4 step 8): every main iPhone screen with a believable week
/// (`-seedDemoData`) and the sample shared lists (`-seedSharedTasksSample`, in memory), one screenshot each, kept in
/// the .xcresult. Skipped in ordinary runs; the pass runs it on its own:
///
///     TEST_RUNNER_HITLIST_TOUR=1 xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:HITListUITests/ScreenTourUITests \
///       -resultBundlePath build.noindex/tour.xcresult
///     xcrun xcresulttool export attachments --path build.noindex/tour.xcresult --output-path build.noindex/tour
///
/// It looks; it does not judge. A missing element is noted and the tour goes on.
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_TOUR"] == "1",
                          "the screenshot tour runs only in the supervisor's pass (TEST_RUNNER_HITLIST_TOUR=1)")
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func testEveryMainScreen() throws {
        launch(tips: false)
        for (index, name) in ["inbox", "today", "upcoming", "flipboard"].enumerated() {
            tab(name)
            pause()
            snapshot("\(index + 1) \(name.capitalized)")
        }

        // Adding a switch: the card over the board.
        let addTile = app.descendants(matching: .any)["addSwitchTile"].firstMatch
        if addTile.waitForExistence(timeout: 3) {
            addTile.tap()
            pause(1.2)
            snapshot("5 Flipboard, adding a switch")
            app.typeText("Water the ferns every 3 days")
            pause()
            snapshot("6 Flipboard, a typed switch")
            let close = app.buttons["Close"].firstMatch
            if close.exists { close.tap() }
            let discard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch
            if discard.waitForExistence(timeout: 2) { discard.tap() }
            pause()
        }

        // Browse, a Group of yours, then Shared Tasks.
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        pause()
        snapshot("7 Browse")
        let work = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Work")).firstMatch
        if work.waitForExistence(timeout: 3) {
            work.tap()
            pause()
            snapshot("8 A Group: Work")
            app.navigationBars.buttons.firstMatch.tap()
            pause()
        }
        let shared = app.buttons["browse-shared-tasks"].firstMatch
        if shared.waitForExistence(timeout: 3) {
            shared.tap()
            pause()
            snapshot("9 The Shared Tasks Group")
            app.navigationBars.buttons.firstMatch.tap()
            pause()
        }
        // Completed (brief 93), at Browse's foot.
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch
        for _ in 0..<4 where !(completed.exists && completed.isHittable) { app.swipeUp() }
        if completed.waitForExistence(timeout: 3), completed.isHittable {
            completed.tap()
            pause()
            snapshot("9b Completed")
            app.navigationBars.buttons.firstMatch.tap()
            pause()
        }
        for _ in 0..<4 { app.swipeDown() }
        // Search with a query (brief 93): Browse's field.
        let field = app.textFields["browseSearch"].exists ? app.textFields["browseSearch"] : app.textFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            app.typeText("lease")
            pause()
            snapshot("9c Search, a query")
            let clear = app.buttons["Clear"].firstMatch
            if clear.exists { clear.tap() }
            pause()
        }

        // Settings' first screen, then its Extras page (brief 86: pages push inside the sheet).
        let gear = app.buttons["settingsButton"].firstMatch
        if gear.waitForExistence(timeout: 3) {
            gear.tap()
            pause()
            snapshot("10 Settings")
            let extras = app.descendants(matching: .any)["settings-page-extras"].firstMatch
            if extras.waitForExistence(timeout: 3) { extras.tap() }
            pause()
            snapshot("11 Settings, Extras")
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
            pause()
        }

        // The editor with quick-add phrases typed into its title.
        tab("today")
        let task = app.staticTexts.matching(NSPredicate(format: "label == %@", "Reply to Sam about the lease")).firstMatch
        if task.waitForExistence(timeout: 5) {
            task.tap()
            let title = app.descendants(matching: .any)["editorTitle"].firstMatch
            if title.waitForExistence(timeout: 5) {
                pause()
                snapshot("12 The editor")
                title.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
                    app.typeText(" tomorrow p1 ")
                    pause()
                    snapshot("13 The editor, tomorrow p1 typed")
                }
                app.buttons["Close"].firstMatch.tap()
                let discard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch
                if discard.waitForExistence(timeout: 2) { discard.tap() }
                pause()
            }
        }

        // A first-run tip floats above the quick-add card, which keeps its place.
        app.terminate()
        launch(tips: true)
        tab("inbox")
        app.buttons["quickAddButton"].firstMatch.tap()
        pause(1.5)
        snapshot("14 Quick add with its first tip")
    }

    // MARK: Helpers

    private func launch(tips: Bool) {
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "tour-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-seedDemoData", "YES", "-seedSharedTasksSample", "YES"]
        if !tips { app.launchArguments.append("-hideTips") }
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15), "the tabs")
    }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        if button.waitForExistence(timeout: 5) { button.tap() }
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
    }

    /// Lets a transition settle before a screenshot.
    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
