import XCTest

/// Brief 161: Upcoming's Week layout through the real app. Each test has a store (and so settings) of its own, sync off,
/// no tips, the demo week. With `HITLIST_SHOTS_DIR` set (a folder on the Mac) the pictures are saved there too.
final class UpcomingWeekUITests: XCTestCase {
    private var app: XCUIApplication!
    private var suffix = ""

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        suffix = "r161-\(UUID().uuidString.prefix(8))"
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = suffix
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #else
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    /// Open Upcoming, choose Week: a demo task's chip is there and a tap opens its card; the choice outlives a relaunch;
    /// choose the list again, and that outlives a relaunch too.
    func testChooseWeekOpenAChipAndKeepTheChoice() throws {
        try launch()
        openUpcoming()
        XCTAssertFalse(element("upcomingWeek").exists, "today's layout by default")
        choose("Week")
        XCTAssertTrue(element("upcomingWeek").waitForExistence(timeout: 5), "the Week layout")
        let chip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'weekChip' AND label == %@",
                                                                        "Buy groceries")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "today's demo task as a chip")
        shot("week-demo")
        hit(chip)
        XCTAssertTrue(element("editorTitle").waitForExistence(timeout: 5), "the chip opened its card")
        closeCard()

        relaunch()
        openUpcoming()
        XCTAssertTrue(element("upcomingWeek").waitForExistence(timeout: 5), "Week kept across a relaunch")

        choose(listName)
        XCTAssertTrue(element("upcomingWeek").waitForNonExistence(timeout: 5), "today's layout again")
        relaunch()
        openUpcoming()
        pause(1.5)
        XCTAssertFalse(element("upcomingWeek").exists, "today's layout kept across a relaunch")
    }

    /// The pictures: the band closed and open, two tasks at one time, Overdue's list.
    func testWeekPictures() throws {
        app.launchArguments += ["-upcomingLayout", "week"]
        try launch()
        for line in ["Pick up the parcel tomorrow", "Call the bank tomorrow p2", "Order printer ink tomorrow",
                     "Dentist forms tomorrow 9am p3", "Water filter tomorrow 9am p1", "Pay the plumber yesterday p1"] {
            addTask(line)
        }
        openUpcoming()
        XCTAssertTrue(element("upcomingWeek").waitForExistence(timeout: 5))
        let more = bandMore
        if !more.waitForExistence(timeout: 5) { shot("week-no-more") }
        XCTAssertTrue(more.exists, "the band's \"N more\"")
        shot("week-band-closed")
        hit(more)
        pause()
        XCTAssertFalse(bandMore.exists, "the band opened")
        shot("week-band-open")
        hit(app.buttons["Show fewer all-day tasks"].firstMatch)
        pause()
        XCTAssertTrue(bandMore.waitForExistence(timeout: 5), "and closed again")
        // Two tasks at 9 AM tomorrow, side by side.
        let a = chip("Dentist forms"), b = chip("Water filter")
        XCTAssertTrue(a.waitForExistence(timeout: 5) && b.exists)
        #if os(iOS)
        // Nine o'clock brought into view by a finger in the hours themselves. (XCUITest's own `swipeDown()` on the
        // app begins above the grid on this screen and moved nothing: round 33.)
        let screen = app.frame
        for _ in 0..<8 {
            let y = a.frame.midY
            if y > screen.height * 0.5, y < screen.height * 0.75 { break }
            let pullsDown = y < screen.height * 0.5
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: pullsDown ? 0.55 : 0.75))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: pullsDown ? 0.75 : 0.55))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.3)
            pause(0.4)
        }
        XCTAssertTrue(a.isHittable && b.isHittable, "nine o'clock is on screen")
        #endif
        XCTAssertEqual(a.frame.minY, b.frame.minY, accuracy: 1, "at one time")
        XCTAssertTrue(a.frame.maxX <= b.frame.minX + 1 || b.frame.maxX <= a.frame.minX + 1, "side by side")
        shot("week-two-at-nine")
        let overdue = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Overdue")).firstMatch
        XCTAssertTrue(overdue.waitForExistence(timeout: 5), "Overdue in the header")
        hit(overdue)
        XCTAssertTrue(app.staticTexts["Pay the plumber"].waitForExistence(timeout: 5), "the overdue task in the list's row")
        shot("week-overdue")
    }

    /// The hours scroll under a finger (round 33: the sideways swipe is a gesture on the same view, and the first
    /// pictures showed the grid where it had opened after three swipes).
    func testTheHoursScrollAndASidewaysSwipeMovesTheDays() throws {
        app.launchArguments += ["-upcomingLayout", "week"]
        try launch()
        openUpcoming()
        let week = element("upcomingWeek")
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        let chip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'weekChip' AND label == %@",
                                                                        "Buy groceries")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "today's demo task as a chip")
        let before = chip.frame.minY
        // In the morning the grid opens near its top, so the finger goes up (later hours); later in the day, down.
        let up = Calendar.current.component(.hour, from: Date()) < 12
        // The screen's own coordinates: the Week layout's identifier is on each of its parts, so "the first match"
        // is its header, not the grid.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: up ? 0.75 : 0.55))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: up ? 0.55 : 0.75))
        shot("week-before-scroll")
        from.press(forDuration: 0.05, thenDragTo: to)
        pause()
        let moved = chip.frame.minY - before
        shot("week-scrolled")
        XCTAssertGreaterThan(abs(moved), 60, "the hours moved with the finger (moved \(moved) pt)")
        XCTAssertEqual(moved > 0, !up, "and the way the finger went")
        // A quick flick the other way moves them back the other way.
        let afterDrag = chip.frame.minY
        if up { app.swipeDown() } else { app.swipeUp() }
        pause()
        let flicked = chip.frame.minY - afterDrag
        shot("week-flicked")
        XCTAssertGreaterThan(abs(flicked), 60, "a flick moves the hours too (moved \(flicked) pt)")
        // And a sideways swipe still moves the days: the layout's own Today button (not the tab's) sleeps while the
        // days start today and wakes once they have moved on.
        func sleepingTodayButtons() -> Int {
            app.buttons.matching(NSPredicate(format: "label == 'Today'")).allElementsBoundByIndex.filter { !$0.isEnabled }.count
        }
        XCTAssertEqual(sleepingTodayButtons(), 1, "the days start today")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.65)))
        pause()
        XCTAssertEqual(sleepingTodayButtons(), 0, "the days moved with a sideways swipe")
        shot("week-swiped")
    }

    /// The largest ordinary text size, and another theme.
    func testWeekAtTheLargestTextSize() throws {
        app.launchArguments += ["-upcomingLayout", "week", "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryXXXL"]
        try launch()
        openUpcoming()
        XCTAssertTrue(element("upcomingWeek").waitForExistence(timeout: 5))
        XCTAssertTrue(element("weekChip").waitForExistence(timeout: 5))
        shot("week-largest-text")
    }

    func testWeekInAnotherTheme() throws {
        app.launchArguments += ["-upcomingLayout", "week", "-pref.theme", "midnight"]
        try launch()
        openUpcoming()
        XCTAssertTrue(element("upcomingWeek").waitForExistence(timeout: 5))
        shot("week-midnight")
    }

    // MARK: Helpers

    #if os(macOS)
    private let listName = "Board"
    #else
    private var listName: String { app.buttons["tab-today"].exists ? "List" : "Board" }
    #endif

    private func launch() throws {
        app.launch()
        #if os(iOS)
        try XCTSkipUnless(app.buttons["tab-today"].waitForExistence(timeout: 20), "the iPhone's tabs")
        #endif
    }

    private func relaunch() {
        app.terminate()
        app.launch()
        #if os(iOS)
        _ = app.buttons["tab-today"].waitForExistence(timeout: 20)
        #endif
    }

    private func openUpcoming() {
        #if os(iOS)
        hit(app.buttons["tab-upcoming"].firstMatch)
        #else
        app.outlines.staticTexts["Upcoming"].firstMatch.click()
        #endif
        pause()
    }

    private func choose(_ layout: String) {
        let menu = element("upcomingLayout")
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "the layout button")
        hit(menu)
        let item = app.buttons[layout].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(layout) in the menu")
        hit(item)
        pause()
    }

    private func addTask(_ line: String) {
        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "the +")
        hit(plus)
        let title = element("quickAddTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText(line + " ")
        hit(app.buttons["quickAddSave"])
        _ = title.waitForNonExistence(timeout: 5)
        pause(0.5)
    }

    private func closeCard() {
        let back = app.buttons["sheetBack"].firstMatch
        #if os(iOS)
        if back.waitForExistence(timeout: 2) { hit(back) } else { app.swipeDown() }
        #else
        app.typeKey(.escape, modifierFlags: [])
        #endif
        _ = element("editorTitle").waitForNonExistence(timeout: 5)
        pause()
    }

    private func chip(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'weekChip' AND label BEGINSWITH %@",
                                                             title)).firstMatch
    }

    private func hit(_ element: XCUIElement) {
        #if os(iOS)
        element.tap()
        #else
        element.click()
        #endif
    }

    /// "N more" under a day's all-day chips.
    private var bandMore: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", " more")).firstMatch
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func shot(_ name: String) {
        pause()
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
