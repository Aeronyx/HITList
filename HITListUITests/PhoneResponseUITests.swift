import XCTest

/// Brief 164 (round 33): the iPhone's everyday actions, each timed from the tap to the element that answers it,
/// with the app's own `ResponseProbe` (`-responseProbe YES`) writing, for every lifted finger, when the main thread
/// went to work and how long it worked. On demand only: skipped unless `HITLIST_PERF=1` reaches the runner
/// (`TEST_RUNNER_HITLIST_PERF=1 xcodebuild test … -only-testing:HITListUITests/PhoneResponseUITests`).
/// Each action's line is printed as `RESPONSE <name> <ms>`; the wall time includes XCUITest's own wait for the app to
/// settle and its polling, so it is for before and after, and the probe's numbers are the app's own.
final class PhoneResponseUITests: XCTestCase {
    private var app: XCUIApplication!
    private var lines: [String] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_PERF"] == "1", "on demand: HITLIST_PERF=1")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = ProcessInfo.processInfo.environment["HITLIST_PERF_SUFFIX"] ?? "r164"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-responseProbe", "YES"]
    }

    func testEverydayActions() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 30))
        pause(3)
        // The tabs three times: the first visit builds each screen's types, the later ones are what a day is.
        for pass in 1...3 {
            tab("inbox", shows: "Read the article Alex sent", pass)
            tab("upcoming", shows: "Finish the quarterly report", pass)
            tab("flipboard", shows: nil, pass)
            tab("today", shows: "Buy groceries", pass)
        }
        for round in 1...1 {

            timed("quick add open \(round)", tap: app.buttons["quickAddButton"].firstMatch) {
                self.element("quickAddTitle").exists
            }
            pause()
            app.typeText("Perf task \(round)")
            timed("quick add save \(round)", tap: app.buttons["quickAddSave"].firstMatch) {
                !self.element("quickAddTitle").exists
            }
            pause()

            let row = text("Buy groceries")
            timed("card open \(round)", tap: row) { self.element("editorTitle").exists }
            pause()
            timed("card close \(round)", tap: app.buttons["Close"].firstMatch) { !self.element("editorTitle").exists }
            pause()

            let checks = app.buttons.matching(NSPredicate(format: "label == %@", "Complete task"))
            let before = checks.count
            timed("check off \(round)", tap: checks.firstMatch) {
                checks.count < before || self.app.buttons["Undo"].exists
            }
            pause(4)

            timed("browse open \(round)", tap: app.buttons["browseButton"].firstMatch) {
                self.app.buttons["settingsButton"].exists
            }
            pause()
            timed("group open \(round)", tap: app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home")).firstMatch) {
                self.text("Call the dentist").exists
            }
            pause()
            app.navigationBars.buttons.firstMatch.tap()
            pause()
            timed("label open \(round)", tap: app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "errands")).firstMatch) {
                self.text("Buy groceries").exists || self.text("Perf task \(round)").exists
            }
            pause()
            app.navigationBars.buttons.firstMatch.tap()
            pause()
            app.navigationBars.buttons.firstMatch.tap()
            pause()
            tab("today", shows: "Gym", round)
            let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
            let start = Date()
            list.swipeDown()
            record("pull today \(round)", Date().timeIntervalSince(start))
            pause(2)
            app.buttons["browseButton"].firstMatch.tap()
            pause()
            timed("settings open \(round)", tap: app.buttons["settingsButton"].firstMatch) {
                self.element("settings-profile").exists
            }
            pause()
            let page = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings-page-")).firstMatch
            timed("settings page \(round)", tap: page) { self.app.buttons["sheetBack"].firstMatch.exists }
            pause()
            app.buttons["sheetBack"].firstMatch.tap()
            pause()
        }
        let report = lines.joined(separator: "\n")
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "response times"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Helpers

    private func tab(_ name: String, shows title: String?, _ round: Int) {
        let button = app.buttons["tab-\(name)"].firstMatch
        timed("tab \(name) \(round)", tap: button) {
            if let title { return self.text(title).exists }
            return button.isSelected
        }
        pause()
    }

    private func timed(_ name: String, tap target: XCUIElement, until done: @escaping () -> Bool) {
        guard target.waitForExistence(timeout: 5) else { return record(name, -1) }
        let start = Date()
        target.tap()
        let tapped = Date().timeIntervalSince(start)
        while !done() {
            if Date().timeIntervalSince(start) > 8 { return record(name, -1) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        record(name, Date().timeIntervalSince(start), tapReturned: tapped)
    }

    private func record(_ name: String, _ seconds: TimeInterval, tapReturned: TimeInterval? = nil) {
        let line = "RESPONSE \(name) \(Int(seconds * 1000)) ms" + (tapReturned.map { " (tap() returned at \(Int($0 * 1000)))" } ?? "")
        lines.append(line)
        print(line)
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func pause(_ seconds: TimeInterval = 1.0) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

/// Brief 168: after every kind of switch the iPhone's "+" adds to the list on show (`popouts.listContext`), read from the
/// Debug shell's one-point readout (`-debugShell YES`); and only the tab on show is within reach (one Browse control,
/// one bolt), which any shell that keeps tabs alive must still hold.
final class MobileTabsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-debugShell", "YES"]
    }

    func testThePlusFollowsTheTabOnShow() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 30))
        expect(context: "today")
        for _ in 1...3 {
            for (tab, context) in [("inbox", "inbox"), ("upcoming", "upcoming"), ("flipboard", "plain"), ("today", "today")] {
                app.buttons["tab-\(tab)"].firstMatch.tap()
                expect(context: context, "after a tap on \(tab)")
            }
        }

        // A screen pushed on a tab: Browse, then a Group from it, each sets the "+"; leaving the tab and coming back
        // shows its first screen again and gives the "+" back to it.
        app.buttons["browseButton"].firstMatch.tap()
        expect(context: "inbox", "on Browse") // Browse adds to the Inbox
        let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Call the dentist")).firstMatch
                          .waitForExistence(timeout: 5))
        let onGroup = readout()
        XCTAssertNotEqual(onGroup, "inbox", "a Group's own list once it is pushed")
        XCTAssertNotEqual(onGroup, "today")
        app.navigationBars.buttons.firstMatch.tap()
        expect(context: "inbox", "back on Browse")
        app.buttons["tab-upcoming"].firstMatch.tap()
        expect(context: "upcoming", "a tab left from a pushed screen")
        app.buttons["tab-today"].firstMatch.tap()
        expect(context: "today", "back on a tab whose pushed screens went")
        XCTAssertFalse(app.buttons["browse-settings-row"].exists, "Today came back on its first screen")

        // A tap on the tab on show takes it back to its first screen.
        app.buttons["browseButton"].firstMatch.tap()
        expect(context: "inbox", "on Browse again")
        app.buttons["tab-today"].firstMatch.tap()
        expect(context: "today", "after a tap on the tab on show")

        // The "+" itself: from Inbox, the card adds a task that the Inbox shows.
        app.buttons["tab-inbox"].firstMatch.tap()
        expect(context: "inbox")
        app.buttons["quickAddButton"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickAddTitle"].firstMatch.waitForExistence(timeout: 5))
        app.typeText("Kept tabs check")
        let save = app.buttons["quickAddSave"].firstMatch
        XCTAssertTrue(save.wait(for: \.isHittable, toEqual: true, timeout: 5))
        save.tap()
        let card = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        if !card.waitForNonExistence(timeout: 3), save.exists { save.tap() } // a tap the keyboard's arrival swallowed
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "the card closes on Add")
        // The newest task is at the Inbox's end: a long list builds its last rows once they scroll into sight.
        let added = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kept tabs check")).firstMatch
        for _ in 0..<4 where !added.exists {
            app.swipeUp()
        }
        XCTAssertTrue(added.waitForExistence(timeout: 5), "added to the Inbox on show")
    }

    /// A tab left is out of reach: its rows, its title and its toolbar are not there for VoiceOver or a test, at once and
    /// after the crossfade.
    func testAHiddenTabIsOutOfReach() throws {
        continueAfterFailure = true
        app.launch()
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 30))
        let inboxOnly = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Read the article Alex sent")).firstMatch
        app.buttons["tab-inbox"].firstMatch.tap()
        XCTAssertTrue(inboxOnly.waitForExistence(timeout: 5))
        app.buttons["tab-today"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Buy groceries")).firstMatch
                          .waitForExistence(timeout: 5))
        XCTAssertTrue(inboxOnly.waitForNonExistence(timeout: 0.5), "the Inbox's row, as the switch begins")
        XCTAssertEqual(app.buttons.matching(identifier: "browseButton").count, 1, "one Browse control: Today's")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(inboxOnly.exists, "the Inbox's row, after the fade")
        XCTAssertEqual(app.buttons.matching(identifier: "syncBolt").count, 1, "one bolt: Today's")
    }

    // MARK: Helpers

    private func readout() -> String {
        String(app.staticTexts["debug-shell"].firstMatch.label.dropFirst("context=".count))
    }

    private func expect(context: String, _ when: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while readout() != context, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        XCTAssertEqual(readout(), context, when, file: file, line: line)
    }
}
