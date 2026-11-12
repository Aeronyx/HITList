import XCTest

/// Brief 106: the iPhone Duo's outer display, where the system's bars stand in a column down the trailing edge and the
/// tab island stands upright at its foot with the "+" under it. Nothing in that column may touch anything else, and the
/// screen's own controls (the bolt, the view options or the screen's control, the magnifying glass or gear) stand in the
/// large title's row, out of the column, in the same place on every screen. Each check reads the frames XCUITest
/// reports, on a tab's first screen and on pushed ones, at the default and the largest text size, and with the
/// column 60 pt shorter (`-duoStatusPad 60`: a call widening the camera island, which the simulator can't place).
///
/// Runs only where the island stands upright (an `iPhone Duo` simulator, folded onto its outer display); skipped
/// everywhere else. On its own:
///
///     xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,id=<Duo UDID>' -only-testing:HITListUITests/DuoColumnUITests
final class DuoColumnUITests: XCTestCase {
    private var app: XCUIApplication!
    private var number = 0

    /// The least room between two parts of the column, or two controls in the title's row.
    static let minimumGap: CGFloat = 8
    /// The seeded Groups, as a row's meta line names them.
    static let groups = ["Work", "Home", "Finance", "Personal", "Health", "Shared Tasks"]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: The column and the title's row

    func testNothingInTheColumnTouchesOnFirstAndPushedScreens() throws {
        try launch()
        walk()
    }

    func testNothingTouchesDuringACall() throws {
        try launch(["-duoStatusPad", "60"])
        walk(suffix: ", call")
    }

    func testNothingTouchesAtTheLargestTextSize() throws {
        try launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        walk(suffix: ", AX5")
    }

    /// The title row's controls take a tap on the outer display: the view options open, the magnifying glass pushes
    /// Browse. (Drawn by us over the title's row they took none: the navigation bar in front of the screen kept them.)
    func testTheTitleRowsControlsTakeATap() throws {
        try launch()
        go("inbox")
        tap(app.buttons["viewOptions"].firstMatch)
        XCTAssertTrue(app.buttons["Show completed"].firstMatch.waitForExistence(timeout: 5)
                      || app.switches["Show completed"].firstMatch.waitForExistence(timeout: 1), "the view options opened")
        snap("view options")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.9)).tap()
        pause()
        tap(app.buttons["browseButton"].firstMatch)
        XCTAssertTrue(app.textFields["browseSearch"].waitForExistence(timeout: 8), "Browse opened")
        snap("Browse")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree: Browse"
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// While the keyboard is up the upright island and its "+" are out of the way (item 5): nothing of them peeks out
    /// between the quick-add card and the keys.
    func testTheIslandStepsAsideForTheKeyboard() throws {
        try launch()
        go("inbox")
        tap(app.buttons["quickAddButton"].firstMatch)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "quick add's keyboard")
        pause(1)
        snap("keyboard, quick add")
        let tab = app.buttons["tab-inbox"].firstMatch
        XCTAssertFalse(tab.exists && tab.isHittable, "the island stepped aside")
    }

    // MARK: The walk

    /// Every tab's first screen, then Browse, a Group and Completed pushed from it.
    private func walk(suffix: String = "") {
        for tab in ["inbox", "today", "upcoming", "flipboard"] {
            go(tab)
            check("\(tab)\(suffix)", pushed: false)
        }
        // Scrolled, the title's row and its controls stay (a List and the Flipboard's ScrollView alike).
        go("flipboard")
        scrollDown()
        check("flipboard, scrolled\(suffix)", pushed: false)
        go("inbox")
        scrollDown()
        check("inbox, scrolled\(suffix)", pushed: false)
        tap(app.buttons["browseButton"].firstMatch)
        XCTAssertTrue(app.textFields["browseSearch"].waitForExistence(timeout: 8), "the magnifying glass opened Browse")
        check("Browse\(suffix)", pushed: true)
        for row in ["Work", "Shared Tasks", "Completed"] {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch
            guard scrollTo(link) else {
                XCTFail("no \(row) row in Browse")
                continue
            }
            link.tap()
            pause()
            check("\(row)\(suffix)", pushed: true)
            back()
        }
    }

    /// The column's parts and the title row's controls on the screen on show: none touches another, the controls stand
    /// left of the column, Back (on a pushed screen) above the island.
    private func check(_ screen: String, pushed: Bool) {
        snap(screen)
        let window = app.windows.firstMatch.frame
        let island = islandFrame()
        let plus = app.buttons["quickAddButton"].firstMatch
        var column: [(String, CGRect)] = [("island", island)]
        if plus.exists { column.append(("+", plus.frame)) }
        if pushed {
            let back = backButton()
            if back.exists {
                column.append(("Back", back.frame))
                XCTAssertGreaterThanOrEqual(island.minY - back.frame.maxY, Self.minimumGap,
                                            "\(screen): Back \(back.frame) on the island \(island)")
            } else {
                XCTFail("\(screen): no Back")
            }
        }
        // The title row's controls: the bolt, the screen's control and the magnifying glass or gear.
        let ids = ["syncBolt", "viewOptions", "flipSound", "browseNew", "browseButton", "settingsButton"]
        var row: [(String, CGRect)] = []
        for id in ids {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            if element.exists, !element.frame.isEmpty { row.append((id, element.frame)) }
        }
        XCTAssertEqual(row.count, 3, "\(screen): the bolt and two controls, found \(row.map(\.0))")
        for (id, frame) in row {
            XCTAssertLessThanOrEqual(frame.maxX, island.minX, "\(screen): \(id) \(frame) in the column")
            XCTAssertLessThan(frame.maxY, window.height / 4, "\(screen): \(id) \(frame) not in the title's row")
        }
        // A row's Group is never cut to a letter (item 3): each Group's name on screen is wider than "W…".
        for name in Self.groups {
            let texts = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex
            for text in texts where text.frame.minY > 80 && text.frame.maxX <= island.minX && text.frame.height < 60 {
                XCTAssertGreaterThanOrEqual(text.frame.width, 28, "\(screen): \(name) cut to \(text.frame.width) pt")
            }
        }
        let parts = column + row
        for (i, a) in parts.enumerated() {
            for b in parts[(i + 1)...] where a.1.intersects(b.1) {
                XCTFail("\(screen): \(a.0) \(a.1) touches \(b.0) \(b.1)")
            }
        }
        record(screen, parts)
    }

    /// The upright island: its four tabs and the pill's inset around them.
    private func islandFrame() -> CGRect {
        let tabs = ["inbox", "today", "upcoming", "flipboard"].map { app.buttons["tab-\($0)"].firstMatch.frame }
        return tabs.dropFirst().reduce(tabs[0]) { $0.union($1) }.insetBy(dx: 0, dy: -6)
    }

    /// The system's Back, in the column on a pushed screen.
    private func backButton() -> XCUIElement {
        app.buttons["BackButton"].firstMatch
    }

    // MARK: Helpers

    private func launch(_ extra: [String] = []) throws {
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s106-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES",
                               "-seedSharedTasksSample", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 20), "the app is up")
        pause(1.5)
        let inbox = app.buttons["tab-inbox"].frame, today = app.buttons["tab-today"].frame
        try XCTSkipUnless(today.minY >= inbox.maxY - 1, "the island stands upright only on the Duo's outer display")
    }

    private func go(_ tab: String) {
        let button = app.buttons["tab-\(tab)"]
        button.tap()
        if button.isSelected { pause(0.3) }
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
        // A re-tap goes back to the tab's first screen.
        if backButton().exists, backButton().isHittable { button.tap() }
        pause()
    }

    private func tap(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 5) { element.tap() } else { XCTFail("no \(element)") }
        pause()
    }

    private func back() {
        let button = backButton()
        if button.exists { button.tap() }
        pause()
    }

    /// Scrolls down until `element` is on screen and clear of the island: a list's rows below the fold don't exist yet.
    private func scrollTo(_ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 2)
        var tries = 0
        while !(element.exists && element.isHittable && element.frame.maxY < islandFrame().maxY) && tries < 8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)))
            pause(0.5)
            tries += 1
        }
        return element.exists && element.isHittable
    }

    /// A page further down the list.
    private func scrollDown() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.75))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)))
        pause()
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snap(_ name: String) {
        number += 1
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%03d %@", number, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Each part's frame, for the report.
    private func record(_ screen: String, _ parts: [(String, CGRect)]) {
        let lines = parts.map { "\($0.0): x \(Int($0.1.minX))–\(Int($0.1.maxX)), y \(Int($0.1.minY))–\(Int($0.1.maxY))" }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "frames: \(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


/// Brief 106's sweep: every list screen on the Duo's outer display photographed, for the findings table. It looks; it
/// does not judge. Skipped unless asked for (`TEST_RUNNER_HITLIST_DUO_SWEEP=1`); `TEST_RUNNER_HITLIST_DUO_SWEEP_XL=1` at
/// the XL text size, `TEST_RUNNER_HITLIST_DUO_SWEEP_LANDSCAPE=1` on its side.
final class DuoSweepUITests: XCTestCase {
    private var app: XCUIApplication!
    private var number = 0
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var suffix: String {
        (environment["HITLIST_DUO_SWEEP_XL"] == "1" ? " XL" : "") + (environment["HITLIST_DUO_SWEEP_LANDSCAPE"] == "1" ? " side" : "")
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(environment["HITLIST_DUO_SWEEP"] == "1", "brief 106's sweep runs only on demand")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = environment["HITLIST_DUO_SWEEP_LANDSCAPE"] == "1" ? .landscapeLeft : .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func test1Lists() throws {
        launch(seed: true)
        go("inbox")
        // The supervisor's crowded row: a repeat, a date and time, a checklist (in the editor) and a label.
        let plus = app.buttons["quickAddButton"].firstMatch
        if plus.waitForExistence(timeout: 5), plus.isHittable {
            plus.tap()
            if app.descendants(matching: .any)["quickAddTitle"].firstMatch.waitForExistence(timeout: 5) {
                pause(0.6)
                app.typeText("Frame the print tomorrow 5pm p1 #Work @errands @waiting every week ")
                pause(0.8)
                snap("quick add, keyboard")
                app.buttons["quickAddSave"].firstMatch.tap()
                pause(1.2)
            }
        }
        go("inbox")
        snap("inbox")
        scrolled("inbox")
        for tab in ["today", "upcoming", "flipboard"] {
            go(tab)
            snap(tab)
            scrolled(tab)
        }
        go("flipboard")
        let tile = app.descendants(matching: .any)["flipSwitchTile"].firstMatch
        if tile.waitForExistence(timeout: 3) {
            tile.press(forDuration: 1.0)
            pause()
            snap("flipboard, a tile's menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.95)).tap()
            pause()
        }
        go("today")
        let check = app.buttons.matching(NSPredicate(format: "label == %@", "Complete task")).firstMatch
        if check.waitForExistence(timeout: 3) {
            check.tap()
            pause(0.7)
            snap("completion toast")
            pause(4)
        }
    }

    func test2Browse() throws {
        launch(seed: true)
        go("inbox")
        tap(app.buttons["browseButton"].firstMatch)
        snap("Browse")
        scrolled("Browse")
        for (label, name) in [("Work", "a Group, Work"), ("Shared Tasks", "Shared Tasks"), ("errands", "a label, errands"),
                              ("Focus filter", "a filter, Focus"), ("Completed", "Completed")] {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            guard scrollTo(link) else { continue }
            link.tap()
            pause()
            snap(name)
            back()
            scrollToTop()
        }
        let field = app.textFields["browseSearch"].firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            app.typeText("lease")
            pause()
            snap("search, lease, keyboard")
            app.typeText("\n")
            pause()
            snap("search, lease")
        }
    }

    func test3EmptyAndTips() throws {
        launch(seed: false, tips: true)
        for tab in ["inbox", "today", "upcoming", "flipboard"] {
            go(tab)
            snap("empty \(tab)")
        }
        go("inbox")
        tap(app.buttons["browseButton"].firstMatch)
        snap("empty Browse")
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch
        if scrollTo(completed) {
            completed.tap()
            pause()
            snap("empty Completed")
        }
    }

    // MARK: Helpers

    private func launch(seed: Bool, tips: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s106w-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES"]
        if !tips { app.launchArguments += ["-hideTips"] }
        if seed { app.launchArguments += ["-seedDemoData", "YES", "-seedSharedTasksSample", "YES"] }
        if environment["HITLIST_DUO_SWEEP_XL"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"]
        }
        app.launch()
        _ = app.buttons["tab-inbox"].waitForExistence(timeout: 30)
        pause(1.5)
    }

    private func go(_ tab: String) {
        let button = app.buttons["tab-\(tab)"]
        guard button.waitForExistence(timeout: 5) else { return }
        button.tap()
        pause(0.4)
        if app.buttons["BackButton"].exists { button.tap() }
        pause()
    }

    private func tap(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 5) { element.tap() }
        pause()
    }

    private func back() {
        let button = app.buttons["BackButton"].firstMatch
        if button.exists { button.tap() }
        pause()
    }

    private func scrollTo(_ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 2)
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)))
            pause(0.5)
            tries += 1
        }
        return element.exists && element.isHittable
    }

    private func scrollToTop() {
        for _ in 0..<3 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 400)))
        }
        pause(0.5)
    }

    private func scrolled(_ name: String) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.75))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)))
        pause()
        snap("\(name), scrolled")
        scrollToTop()
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snap(_ name: String) {
        number += 1
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%03d %@%@", number, name, suffix)
        shot.lifetime = .keepAlways
        add(shot)
    }
}
