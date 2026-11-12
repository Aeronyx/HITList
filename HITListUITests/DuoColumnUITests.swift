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

    // MARK: The walk

    /// Every tab's first screen, then Browse, a Group and Completed pushed from it.
    private func walk(suffix: String = "") {
        for tab in ["inbox", "today", "upcoming", "flipboard"] {
            go(tab)
            check("\(tab)\(suffix)", pushed: false)
        }
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

