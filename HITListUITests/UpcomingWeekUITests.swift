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
        for _ in 0..<3 { app.swipeDown() }
        #endif
        XCTAssertEqual(a.frame.minY, b.frame.minY, accuracy: 1, "at one time")
        XCTAssertTrue(a.frame.maxX <= b.frame.minX + 1 || b.frame.maxX <= a.frame.minX + 1, "side by side")
        shot("week-two-at-nine")
        let overdue = element("weekOverdue")
        XCTAssertTrue(overdue.waitForExistence(timeout: 5), "Overdue in the header")
        hit(overdue)
        XCTAssertTrue(app.staticTexts["Pay the plumber"].waitForExistence(timeout: 5), "the overdue task in the list's row")
        shot("week-overdue")
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
