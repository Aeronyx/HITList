import XCTest

/// Brief 77 on iPhone: calendar events beside the tasks, with the demo day (`-seedDemoEvents YES`, fake events that
/// never touch the system calendar) and the demo week of tasks (`-seedDemoData`). Each launch has a store of its own
/// (`HITLIST_STORE_SUFFIX`), sync off, no tips. Screenshots land in the .xcresult.
final class CalendarEventsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-cal-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
    }

    func testOffByDefaultTodayHasNoEvents() {
        app.launch()
        tab("today")
        XCTAssertTrue(text("Buy groceries").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Calendar"].exists, "no events header while the setting is off")
        XCTAssertEqual(events.count, 0)
        snapshot("1 Today, calendar events off")
    }

    func testTodayShowsTheDayEventsAboveItsTasks() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("today")
        let birthday = event(containing: "Sam's birthday")
        XCTAssertTrue(birthday.waitForExistence(timeout: 10), "the demo day's all-day event")
        XCTAssertTrue(app.staticTexts["Calendar"].exists, "under a quiet header of their own")
        let standup = event(containing: "Standup")
        let yoga = event(containing: "Yoga")
        XCTAssertLessThan(birthday.frame.minY, standup.frame.minY, "all-day first")
        XCTAssertLessThan(standup.frame.minY, yoga.frame.minY, "then by time")
        let task = text("Buy groceries")
        XCTAssertTrue(task.exists)
        XCTAssertLessThan(yoga.frame.maxY, task.frame.minY, "events above the day's tasks")
        XCTAssertFalse(event(containing: "Quarterly planning").exists, "tomorrow's events stay in Upcoming")
        snapshot("2 Today with events")

        // A tap on an event does nothing: no editor opens.
        yoga.tap()
        XCTAssertFalse(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 1.5))
    }

    func testUpcomingShowsEachDaysEventsAtTheTopOfTheDay() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("upcoming")
        XCTAssertTrue(event(containing: "Sam's birthday").waitForExistence(timeout: 10), "today's events")
        snapshot("3 Upcoming with events, today")
        // Tomorrow is below today's events and tasks.
        let planning = event(containing: "Quarterly planning")
        for _ in 0..<6 where !(planning.exists && planning.isHittable) { app.swipeUp() }
        XCTAssertTrue(planning.exists, "tomorrow's event")
        let tomorrowsTask = text("Call the dentist")
        if tomorrowsTask.exists {
            XCTAssertLessThan(planning.frame.minY, tomorrowsTask.frame.minY, "events at the top of the day")
        }
        snapshot("3b Upcoming with events, tomorrow")
    }

    func testSettingsStatesAndTheCalendarCard() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("today")
        XCTAssertTrue(event(containing: "Coffee with Alex").waitForExistence(timeout: 10))
        openSettings()
        let toggle = app.descendants(matching: .any)["settings-calendar-events"].firstMatch
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(toggle.exists)
        let choice = app.descendants(matching: .any)["settings-calendar-choice"].firstMatch
        XCTAssertTrue(choice.exists, "on: the calendars row")
        XCTAssertTrue(choice.label.contains("All"), choice.label)
        snapshot("4 Settings, calendar events on")
        choice.tap()
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3), "the card lists the calendars")
        XCTAssertTrue(app.buttons["Work"].exists)
        XCTAssertTrue(app.buttons["Family"].exists)
        snapshot("5 Settings, the calendar card")
        home.tap()
        XCTAssertTrue(choice.label.contains("2 of 3"), choice.label)
        snapshot("6 Settings, Home hidden")

        // Off: the calendars row goes, and Today has no events.
        toggle.tap()
        XCTAssertFalse(choice.waitForExistence(timeout: 1))
        snapshot("7 Settings, calendar events off")
        closeSettings()
        tab("today")
        XCTAssertTrue(text("Buy groceries").waitForExistence(timeout: 5))
        XCTAssertEqual(events.count, 0)
    }

    /// The real permission, on the simulator's own (empty) calendar: switching on shows the system's prompt with the
    /// purpose string; Don't Allow leaves the switch off, says why and offers the system's settings.
    func testRefusingAccessSaysWhyAndOffersSettings() {
        app.resetAuthorizationStatus(for: .calendar)
        app.launch()
        openSettings()
        let toggle = app.descendants(matching: .any)["settings-calendar-events"].firstMatch
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        snapshot("8 Settings, calendar events off (not asked yet)")
        toggle.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the system's prompt")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "only reads them")).firstMatch.exists,
                      "the purpose string says read-only")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "9 The permission prompt"
        shot.lifetime = .keepAlways
        add(shot)
        alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch.tap()
        let openSettingsRow = app.descendants(matching: .any)["settings-calendar-open-settings"].firstMatch
        XCTAssertTrue(openSettingsRow.waitForExistence(timeout: 5), "refused: a way to the system's settings")
        XCTAssertFalse(app.descendants(matching: .any)["settings-calendar-choice"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "isn't allowed")).firstMatch.exists)
        snapshot("10 Settings, calendar access refused")
    }

    // MARK: Helpers

    private var events: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "calendarEvent") }

    private func event(containing title: String) -> XCUIElement {
        events.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func text(_ prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
    }

    private func openSettings() {
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
    }

    private func closeSettings() {
        let done = app.buttons["Done"].firstMatch
        if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable { back.tap() }
    }

    private func snapshot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
