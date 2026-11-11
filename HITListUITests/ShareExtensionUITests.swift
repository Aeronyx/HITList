import XCTest

/// Brief 90: "Add to HITList" from Safari's share sheet, the way a person does it, then the task in HITList's Inbox with
/// its link. Screenshots of each step are kept in the .xcresult. It needs a build whose extension writes this run's side
/// store (`HITLIST_WIDGET_SUFFIX`, a Debug-only build setting) and a page to share, so it is skipped in ordinary runs:
///
///     python3 -m http.server 8790 --directory <folder with article.html> &
///     TEST_RUNNER_HITLIST_SHARE=1 TEST_RUNNER_HITLIST_SHARE_PAGE=http://localhost:8790/article.html \
///       xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
///       -destination 'platform=iOS Simulator,name=HITList-90' -only-testing:HITListUITests/ShareExtensionUITests \
///       HITLIST_WIDGET_SUFFIX=s90 -resultBundlePath build.noindex/share.xcresult
///     xcrun xcresulttool export attachments --path build.noindex/share.xcresult --output-path build.noindex/share
///
/// The page's title is "A page worth reading". Run it on a simulator of your own: it adds a task to that side store.
final class ShareExtensionUITests: XCTestCase {
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let suffix = "s90"

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_SHARE"] == "1",
                          "the share sheet tour runs only when asked (TEST_RUNNER_HITLIST_SHARE=1)")
        continueAfterFailure = false
    }

    private var page: URL {
        URL(string: ProcessInfo.processInfo.environment["HITLIST_SHARE_PAGE"] ?? "http://localhost:8790/article.html")!
    }

    private func hitlist(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = suffix
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips"] + arguments
        return app
    }

    func testSharingASafariPageAddsItToTheInboxWithItsLink() throws {
        // The app once, so the sheet's context (theme, Groups) is written, then closed: it isn't running when the share
        // is made, as on most phones most of the time.
        let app = hitlist(["-seedDemoData", "YES"])
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "HITList's first screen")
        sleep(3)
        sleep(2)
        app.terminate()

        safari.launch()
        safari.open(page)
        XCTAssertTrue(safari.webViews.staticTexts["A page worth reading"].firstMatch.waitForExistence(timeout: 20)
                      || safari.webViews.firstMatch.waitForExistence(timeout: 5), "the page loaded")
        sleep(2)
        attach("1 Safari, the page")

        openShareSheet()
        attach("2 the share sheet")
        let row = shareRow()
        XCTAssertNotNil(row, "HITList is offered in the share sheet")
        row?.tap()

        let title = safari.descendants(matching: .any)["shareTitle"].firstMatch
        // The extension's first launch on a busy simulator can take half a minute.
        let found = title.waitForExistence(timeout: 90)
        attach("3 the card, prefilled")
        if !found { dump("3 no card") }
        XCTAssertTrue(found, "HITList's card")
        sleep(1)
        // A simulator that behaves as if a hardware keyboard is attached shows no software keyboard; say which this is.
        let keyboard = XCTAttachment(string: "software keyboard on screen: \(safari.keyboards.firstMatch.exists); title has focus: \((title.value(forKey: "hasKeyboardFocus") as? Bool) ?? false)")
        keyboard.name = "3a keyboard"
        keyboard.lifetime = .keepAlways
        add(keyboard)
        title.typeText(" tomorrow p1")
        sleep(1)
        attach("4 the card, typed")
        safari.descendants(matching: .any)["shareAdd"].firstMatch.tap()
        let done = safari.descendants(matching: .any)["shareDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the sheet's last line")
        attach("5 saved: \(done.label)")
        sleep(4)
        attach("6 the sheet closed")

        // HITList opens and makes the task.
        let opened = hitlist()
        opened.launch()
        let inboxButton = try XCTUnwrap(inbox(in: opened), "HITList's Inbox")
        inboxButton.tap()
        let made = opened.staticTexts["A page worth reading"].firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 10), "the task is in the Inbox")
        sleep(1)
        attach("7 HITList's Inbox")
        made.tap()
        sleep(2)
        attach("8 the task, with its link")
        let link = opened.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                                                                             page.absoluteString, page.absoluteString)).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "its notes hold the address")
    }

    /// The Inbox: the iPhone's tab, or the iPad's sidebar row (the sidebar opened first when it is hidden, as in
    /// portrait), once the app shows one (up to 20 s).
    private func inbox(in app: XCUIApplication) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier == 'tab-inbox' OR label == 'Inbox' OR label BEGINSWITH 'Inbox,'")
        let sidebar = NSPredicate(format: "label CONTAINS[c] 'sidebar' OR identifier CONTAINS[c] 'sidebar'")
        var openedSidebar = false
        for _ in 0..<40 {
            if app.buttons["tab-inbox"].exists { return app.buttons["tab-inbox"] }
            if let row = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.first(where: { $0.isHittable }) {
                return row
            }
            if !openedSidebar, let toggle = app.buttons.matching(sidebar).allElementsBoundByIndex.first(where: { $0.isHittable }) {
                toggle.tap()
                openedSidebar = true
            }
            usleep(500_000)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "no Inbox tree"
        tree.lifetime = .keepAlways
        add(tree)
        return nil
    }

    // MARK: - Driving Safari's share sheet

    /// Safari's Share: in the toolbar on iPad (`ShareButton`), in the Page Menu on iPhone from iOS 26 (`MoreMenuButton`).
    private func openShareSheet() {
        let direct = safari.buttons["ShareButton"].firstMatch
        let pageMenu = safari.buttons["MoreMenuButton"].firstMatch
        _ = pageMenu.waitForExistence(timeout: 5)
        if direct.exists, direct.isHittable {
            // The first tap may only end the address field's editing (its keyboard is up after `open`): tap until the
            // sheet is up.
            for _ in 0..<3 {
                direct.tap()
                if shareSheetIsUp() { break }
            }
        } else if pageMenu.exists, pageMenu.isHittable {
            pageMenu.tap()
            sleep(2)
            attach("2a the Page Menu")
            let share = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'Share' OR identifier == 'Share' OR identifier == 'ShareButton'"))
                .allElementsBoundByIndex.first { $0.isHittable }
            if let share { share.tap() } else { dump("2a no Share in the Page Menu") }
        }
        // A busy simulator draws the sheet blank for a while before its rows arrive.
        _ = shareSheetIsUp(timeout: 30)
        sleep(2)
    }

    private func shareSheetIsUp(timeout: TimeInterval = 5) -> Bool {
        let marker = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Copy' OR label == 'AirDrop' OR label == 'HITList' OR label == 'Messages'")).firstMatch
        return marker.waitForExistence(timeout: timeout)
    }

    /// HITList's icon in the share sheet's app row (scrolled to, or behind "More").
    private func shareRow() -> XCUIElement? {
        let predicate = NSPredicate(format: "label == 'HITList'")
        _ = safari.descendants(matching: .any).matching(predicate).firstMatch.waitForExistence(timeout: 20)
        for _ in 0..<4 {
            let candidates = safari.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
            if let hittable = candidates.first(where: { $0.isHittable }) { return hittable }
            // The app row scrolls sideways.
            let row = safari.collectionViews.firstMatch
            if row.exists { row.swipeLeft() } else { break }
            sleep(1)
        }
        dump("2 no HITList in the sheet")
        return nil
    }

    private func dump(_ name: String) {
        let tree = XCTAttachment(string: safari.debugDescription)
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
