import XCTest

/// Brief 77 on iPhone: calendar events beside the tasks, with the demo day (`-seedDemoEvents YES`, fake events that
/// never touch the system calendar) and the demo week of tasks (`-seedDemoData`). Brief 136: Settings → Calendar,
/// calendars by account, Google Calendar's words, an event's card, Add to Calendar into the demo's writable fake. Each launch has a store of its own
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
        // The demo's standups are weekdays only; coffee is every day.
        let coffee = event(containing: "Coffee with Alex")
        let yoga = event(containing: "Yoga")
        XCTAssertLessThan(birthday.frame.minY, coffee.frame.minY, "all-day first")
        XCTAssertLessThan(coffee.frame.minY, yoga.frame.minY, "then by time")
        let task = text("Buy groceries")
        XCTAssertTrue(task.exists)
        XCTAssertLessThan(yoga.frame.maxY, task.frame.minY, "events above the day's tasks")
        XCTAssertFalse(event(containing: "Quarterly planning").exists, "tomorrow's events stay in Upcoming")
        snapshot("2 Today with events")

        // A tap on an event opens its card, never the editor (brief 136).
        yoga.tap()
        XCTAssertTrue(app.descendants(matching: .any)["calendarEventCard"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["editorTitle"].exists)
    }

    /// Brief 136 item 3: the card's facts, read as one element; a tap outside closes it.
    func testAnEventsCardInToday() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("today")
        let review = event(containing: "Design review")
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        let card = app.descendants(matching: .any)["calendarEventCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        for fact in ["Design review", "Work", "Room 4B", "Agenda", "https://meet.example.com/design-review"] {
            XCTAssertTrue(card.label.contains(fact), "\(fact) in \(card.label)")
        }
        snapshot("11 Today, an event's card")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "a tap outside closes it")
        // An event made in another zone says its own time too.
        event(containing: "1:1 with Priya").tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.contains("Pacific Time"), card.label)
        snapshot("12 Today, an event in its own time zone")
    }

    /// Brief 136 item 3 on the Upcoming list.
    func testAnEventsCardInUpcoming() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("upcoming")
        let birthday = event(containing: "Sam's birthday")
        XCTAssertTrue(birthday.waitForExistence(timeout: 10))
        birthday.tap()
        let card = app.descendants(matching: .any)["calendarEventCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.contains("All day"), card.label)
        XCTAssertTrue(card.label.contains("Family"), card.label)
        snapshot("13 Upcoming, an event's card")
    }

    /// Brief 136 item 4: a dated task goes on the calendar once, with Undo; a second time says it is already there.
    func testAddToCalendarFromATasksMenu() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("today")
        let task = text("Buy groceries")
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1.0)
        let item = app.buttons["Add to Calendar"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "the task's menu offers it")
        snapshot("14 A task's menu with Add to Calendar")
        item.tap()
        let toast = app.descendants(matching: .any)["calendarNotice"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.hasPrefix("Added to Work"), toast.label)
        XCTAssertTrue(toast.label.hasSuffix("Undo"), toast.label)
        snapshot("15 Added to Work, with Undo")
        XCTAssertTrue(event(containing: "Buy groceries").waitForExistence(timeout: 5), "the copy shows among today's events")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 8), "the toast goes by itself")

        task.press(forDuration: 1.0)
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Already on your calendar")
        snapshot("16 Already on your calendar")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 8))
    }

    /// Brief 136 item 4: Undo removes the one event it added.
    func testAddToCalendarUndo() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("today")
        let task = text("Buy groceries")
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1.0)
        app.buttons["Add to Calendar"].firstMatch.tap()
        let toast = app.descendants(matching: .any)["calendarNotice"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(event(containing: "Buy groceries").waitForExistence(timeout: 5))
        toast.tap()
        XCTAssertTrue(event(containing: "Buy groceries").waitForNonExistence(timeout: 5), "Undo removed it")
        XCTAssertTrue(toast.label.hasPrefix("Removed"), toast.label)
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

    /// Brief 136 items 1 and 2: Settings → Calendar, the calendars by account, Google connected.
    func testTheCalendarPageListsCalendarsByAccount() {
        app.launchArguments += ["-seedDemoEvents", "YES"]
        app.launch()
        tab("today")
        XCTAssertTrue(event(containing: "Coffee with Alex").waitForExistence(timeout: 10))
        openSettings()
        let toggle = element("settings-calendar-events")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings-calendar-account-iCloud").exists, "the iCloud account")
        XCTAssertTrue(element("settings-calendar-account-Gmail").exists, "the Google account")
        XCTAssertTrue(app.buttons["Work"].exists)
        XCTAssertTrue(app.buttons["Climbing club"].exists)
        snapshot("4 Settings → Calendar, on")
        app.buttons["Home"].firstMatch.tap()
        XCTAssertEqual(app.buttons["Home"].firstMatch.value as? String, "Hidden")
        let google = element("settings-calendar-google")
        for _ in 0..<6 where !(google.exists && google.isHittable) { app.swipeUp() }
        XCTAssertTrue(google.label.contains("connected through this iPhone"), google.label)
        XCTAssertTrue(element("settings-calendar-add-target").exists)
        snapshot("5 Settings → Calendar, Add to Calendar and Google connected")

        // Off: the accounts go, the words say how Google Calendar comes in, and Today has no events.
        for _ in 0..<6 where !toggle.isHittable { app.swipeDown() }
        toggle.tap()
        XCTAssertTrue(element("settings-calendar-account-iCloud").waitForNonExistence(timeout: 2))
        XCTAssertTrue(google.label.contains("Add Account…"), google.label)
        snapshot("6 Settings → Calendar, off")
        closeSettings()
        tab("today")
        XCTAssertTrue(text("Buy groceries").waitForExistence(timeout: 5))
        XCTAssertEqual(events.count, 0)
    }

    /// Brief 136 item 2: no Google account on the device: the page says the device's own path.
    func testGoogleWordsWithoutAGoogleAccount() {
        app.launchArguments += ["-seedDemoEvents", "YES", "-demoGoogle", "NO"]
        app.launch()
        openSettings()
        XCTAssertTrue(element("settings-calendar-account-iCloud").waitForExistence(timeout: 5))
        XCTAssertFalse(element("settings-calendar-account-Gmail").exists)
        let google = element("settings-calendar-google")
        for _ in 0..<6 where !(google.exists && google.isHittable) { app.swipeUp() }
        XCTAssertTrue(google.label.contains("Settings → Apps → Calendar → Add Account…"), google.label)
        snapshot("7 Settings → Calendar, no Google account")
    }

    /// Brief 136: refused access, with the demo (no system dialog).
    func testTheDeniedState() {
        app.launchArguments += ["-seedDemoEvents", "YES", "-demoCalendarAccess", "denied"]
        app.launch()
        openSettings()
        XCTAssertTrue(element("settings-calendar-open-settings").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "isn't allowed")).firstMatch.exists)
        XCTAssertFalse(element("settings-calendar-account-iCloud").exists)
        snapshot("7b Settings → Calendar, access refused")
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
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "reads them to show them")).firstMatch.exists,
                      "the purpose string says what reading is for")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "9 The permission prompt"
        shot.lifetime = .keepAlways
        add(shot)
        alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch.tap()
        let openSettingsRow = app.descendants(matching: .any)["settings-calendar-open-settings"].firstMatch
        XCTAssertTrue(openSettingsRow.waitForExistence(timeout: 5), "refused: a way to the system's settings")
        XCTAssertFalse(element("settings-calendar-account-iCloud").exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "isn't allowed")).firstMatch.exists)
        snapshot("10 Settings, calendar access refused")
    }

    /// Brief 136 item 4 on the real EventKit (the simulator's own calendar): with events off, Add to Calendar asks for
    /// write-only access with its own purpose string, then saves one event; asking again says it is already there.
    func testAddToCalendarAsksForWriteOnlyAccess() {
        app.resetAuthorizationStatus(for: .calendar)
        app.launch()
        tab("today")
        let task = text("Buy groceries")
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1.0)
        let item = app.buttons["Add to Calendar"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the system's prompt")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "puts the task you chose")).firstMatch.exists,
                      "the write-only purpose string")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "17 The write-only prompt"
        shot.lifetime = .keepAlways
        add(shot)
        let allow = alert.buttons.matching(NSPredicate(format: "NOT (label BEGINSWITH %@)", "Don")).firstMatch
        allow.tap()
        let toast = app.descendants(matching: .any)["calendarNotice"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 8))
        XCTAssertTrue(toast.label.hasPrefix("Added to"), toast.label)
        snapshot("18 Added with write-only access")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 8))
        task.press(forDuration: 1.0)
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Already on your calendar", "remembered for the run")
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

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

    /// Settings → Calendar, where Calendar events lives (brief 136: a page of Settings' first screen, after General).
    private func openSettings() {
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        let page = app.descendants(matching: .any)["settings-page-calendar"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
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
