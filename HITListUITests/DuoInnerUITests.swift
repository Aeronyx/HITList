import XCTest

/// Brief 108's look at the iPhone Duo's inner display where brief 93's walk (`QASweepUITests`) does not reach: the
/// editor column with typing and the keyboard, sub-tasks, quick add over the sidebar layout, Settings from the
/// sidebar, half open (the crease), across a fold with something open, and the larger text sizes. It runs on the
/// stand-in, an iPad mini drawn at the inner display's size (`-duoStandIn YES -duoStandInSize inner`, `DuoDebug`),
/// because the simulator's own fold needs Device Hub (the shared notes' `108-duo-inner/README.md`). It looks and
/// keeps pictures; it judges little. Skipped unless asked for, and on anything but an iPad:
///
///     TEST_RUNNER_HITLIST_DUO_INNER=1 xcodebuild test-without-building -project HITList.xcodeproj \
///       -scheme HITListUITests -destination 'platform=iOS Simulator,id=<iPad mini UDID>' \
///       -derivedDataPath build.noindex/sim -only-testing:HITListUITests/DuoInnerUITests \
///       -resultBundlePath build.noindex/duo.xcresult
///
/// `TEST_RUNNER_HITLIST_DUO_INNER_SIDE=1` turns it on its side first; `TEST_RUNNER_HITLIST_DUO_INNER_TAG=after`
/// names the pictures (`before` by default).
final class DuoInnerUITests: XCTestCase {
    private var app: XCUIApplication!
    private var number = 0
    private var onSide = false
    private var tag = "before"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["HITLIST_DUO_INNER"] == "1", "brief 108's look runs only on demand (TEST_RUNNER_HITLIST_DUO_INNER=1)")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the stand-in is an iPad")
        continueAfterFailure = true
        onSide = env["HITLIST_DUO_INNER_SIDE"] == "1"
        tag = env["HITLIST_DUO_INNER_TAG"] ?? "before"
        XCUIDevice.shared.orientation = onSide ? .landscapeLeft : .portrait
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// The first screen, the sidebar's header, Upcoming's board, the Flipboard, a Group.
    func test1Screens() throws {
        launch()
        snap("today")
        for name in ["Inbox", "Upcoming", "Flipboard", "Work", "Completed"] {
            go(name)
            snap(name.lowercased())
            if name == "Upcoming" {
                // A swipe along the board: it settles on whole columns.
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: onSide ? 0.75 : 0.8, dy: 0.45))
                from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -170, dy: 0)))
                pause(1.2)
                snap("upcoming, swiped")
            }
        }
    }

    /// The sidebar's search: words, then a filter query, then a result opened beside the results.
    func test8Search() throws {
        launch()
        let field = app.textFields["sidebarSearch"].firstMatch
        guard field.waitForExistence(timeout: 5) else { return note("no sidebarSearch") }
        snap("search field")
        field.tap()
        pause(0.8)
        app.typeText("lease")
        pause(1.2)
        snap("search lease, keyboard")
        app.typeText(XCUIKeyboardKey.return.rawValue)
        pause(0.8)
        openTask("Reply to Sam")
        snap("search result in the editor")
        closeEditor()
        let clear = app.buttons["Clear search"].firstMatch
        if clear.waitForExistence(timeout: 2) { clear.tap() }
        pause(0.8)
        field.tap()
        app.typeText("#Work")
        pause(1.2)
        snap("search #Work")
        tapIfExists(app.buttons["Clear search"].firstMatch)
        pause(1)
        snap("search cleared, back")
    }

    /// The editor column: open, a long title, sub-tasks, the keyboard in its title, one of its cards.
    func test2Editor() throws {
        launch()
        go("Inbox")
        addTask(QASweepTitles.longTitle)
        openTask("Reply to Sam")
        snap("editor open")
        let title = element("editorTitle")
        if title.waitForExistence(timeout: 3) {
            title.tap()
            pause(1.2)
            app.typeText(" today")
            pause(0.6)
            snap("editor typing, keyboard")
        }
        tapIfExists(element("popoutPriorityChip"))
        pause(1)
        snap("editor priority card")
        dismissPopover()
        closeEditor()
        openTask("Ask the landlord")
        snap("editor long title")
        let add = element("addSubtask")
        if scrollTo(add) {
            add.tap()
            pause(0.8)
            app.typeText("Find the radiator key\n")
            pause(0.4)
            app.typeText("Buy a bleed tray\n")
            pause(0.8)
            snap("editor sub-tasks, keyboard")
        } else { note("no addSubtask") }
        closeEditor()
    }

    /// Quick add over the sidebar layout, with the keyboard; its date card.
    func test3QuickAdd() throws {
        launch()
        go("Today")
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5) else { return note("no quickAddButton") }
        plus.tap()
        pause(1.2)
        snap("quick add empty")
        app.typeText("Call the plumber tomorrow 9am p2 #Home")
        pause(0.8)
        snap("quick add typed")
        tapIfExists(element("quickAddDateChip"))
        pause(1)
        snap("quick add date card")
    }

    /// Settings from the sidebar, its first page; the profile menu.
    func test4SettingsAndProfile() throws {
        launch()
        let gear = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            pause(1.2)
            snap("settings")
            tapIfExists(element("settings-page-general"))
            pause(0.8)
            snap("settings general")
            tapIfExists(app.buttons["Done"].firstMatch)
            pause(0.8)
        } else { note("no Settings button") }
        let profile = app.buttons["profile-badge"].firstMatch.exists ? app.buttons["profile-badge"].firstMatch
                                                                     : app.buttons["profile-menu"].firstMatch
        if profile.waitForExistence(timeout: 3) {
            profile.tap()
            pause(0.8)
            snap("profile menu")
            dismissPopover()
        } else { note("no profile button") }
    }

    /// Half open, held like a book: the crease top to bottom down the middle (`-duoCrease 475`, the display's middle).
    /// Upright the crease runs across the display and the columns cross it (brief 50), so there is nothing to see.
    func test5HalfOpen() throws {
        try XCTSkipUnless(onSide, "upright the crease runs across the display")
        launch(extra: ["-duoCrease", "475"])
        snap("half open today")
        go("Upcoming")
        snap("half open upcoming")
        go("Flipboard")
        snap("half open flipboard")
        go("Inbox")
        openTask("Reply to Sam")
        snap("half open editor")
        closeEditor()
    }

    /// Folding and unfolding (`-duoFoldDemo 6`: the stand-in swaps every 6 s) with the editor open and typed in.
    func test6AcrossAFold() throws {
        launch(extra: ["-duoFoldDemo", "6"])
        go("Inbox")
        openTask("Reply to Sam")
        let title = element("editorTitle")
        guard title.waitForExistence(timeout: 5) else { return note("no editor") }
        title.tap()
        pause(0.6)
        app.typeText(" before Friday")
        pause(0.4)
        for step in 1...3 {
            pause(6.2)
            snap("fold \(step), editor typed")
        }
    }

    /// XL type (and one size up): the sidebar, Today and the editor.
    func test7LargerText() throws {
        for size in ["UICTContentSizeCategoryXL", "UICTContentSizeCategoryXXXL"] {
            launch(extra: ["-UIPreferredContentSizeCategoryName", size])
            let name = size.replacingOccurrences(of: "UICTContentSizeCategory", with: "")
            snap("\(name) today")
            go("Upcoming")
            snap("\(name) upcoming")
            go("Inbox")
            openTask("Reply to Sam")
            snap("\(name) editor")
            closeEditor()
            app.terminate()
        }
    }

    // MARK: Helpers

    private func launch(extra: [String] = []) {
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s108-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips", "-duoStandIn", "YES", "-duoStandInSize", "inner",
                               "-seedDemoData", "YES", "-seedSharedTasksSample", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Inbox"].waitForExistence(timeout: 20), "the app is up")
        pause(1.5)
    }

    private func go(_ name: String) {
        let row = app.cells.containing(.staticText, identifier: name).firstMatch
        let target = row.exists ? row : app.staticTexts[name].firstMatch
        if target.waitForExistence(timeout: 3), target.isHittable { target.tap() } else { note("no sidebar row \(name)") }
        pause()
    }

    private func addTask(_ title: String) {
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5) else { return note("no quickAddButton") }
        plus.tap()
        pause(0.8)
        app.typeText(title)
        let save = app.buttons["quickAddSave"].firstMatch
        if save.waitForExistence(timeout: 2) { save.tap() }
        pause(0.8)
        app.typeText(XCUIKeyboardKey.escape.rawValue)
        pause(0.8)
    }

    private func openTask(_ prefix: String) {
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard scrollTo(row) else { return note("no row \(prefix)") }
        row.tap()
        if !element("editorTitle").waitForExistence(timeout: 5) { note("no editor for \(prefix)") }
        pause()
    }

    private func closeEditor() {
        guard element("editorTitle").exists else { return }
        let close = app.buttons["Close"].firstMatch
        if close.exists, close.isHittable { close.tap() } else { app.typeText(XCUIKeyboardKey.escape.rawValue) }
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch, timeout: 1.5)
        _ = element("editorTitle").waitForNonExistence(timeout: 5)
        pause()
    }

    private func dismissPopover() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.97)).tap()
        pause(0.8)
    }

    @discardableResult
    private func scrollTo(_ target: XCUIElement) -> Bool {
        for _ in 0..<6 {
            if target.waitForExistence(timeout: 1), target.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            pause(0.5)
        }
        return target.exists && target.isHittable
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 2) {
        if element.waitForExistence(timeout: timeout), element.isHittable { element.tap() }
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "note: \(text)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// "standin up before 003 editor open": which display, which way up, before or after, the order, the screen.
    private func snap(_ name: String) {
        number += 1
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "standin %@ %@ %03d %@", onSide ? "side" : "up", tag, number, name)
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// The walk's long title, so both looks wrap the same words.
private enum QASweepTitles {
    static let longTitle = "Ask the landlord whether the radiator in the back bedroom can be bled before the cold weather arrives"
}
