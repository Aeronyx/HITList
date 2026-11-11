import XCTest

/// Brief 100, item 4: on iPhone the companion on the "+" stood over the trailing end of a list's last row (Browse's
/// Settings chevron, a Group's count). Scrolled to its end, the last row of Browse, of the Inbox and of a Group sits
/// wholly above the companion as well as the "+": its bottom no lower than the "+"'s top less the companion's height
/// above it (Nod on Slate: 34 pt at its tallest, the umbrella up in the rain). Run on the iPhone 17 and the iPhone 16.
/// Run with `SIMULATOR=<your simulator> scripts/test.sh ui`; the screenshots land in the .xcresult.
final class CompanionListEndUITests: XCTestCase {
    private var app: XCUIApplication!
    /// How far Nod stands above the "+" at its tallest still (`CompanionPerch.clearance(.nod)`).
    private let companion: CGFloat = 34

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES", "-companionHour", "12"]
    }

    func testTheLastRowsComeClearOfTheCompanion() throws {
        app.launch()
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        XCTAssertTrue(app.descendants(matching: .any)["browseSearch"].firstMatch.waitForExistence(timeout: 5))
        scrollToEnd()
        let settings = app.buttons["browse-settings-row"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        snapshot("Browse at its end, clear of the companion")
        assertClearOfTheCompanion(settings, "Browse's Settings row")
        for name in ["Inbox", "Work"] {
            scrollToTop()
            let row = app.collectionViews.firstMatch.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), name)
            row.tap()
            scrollToEnd()
            snapshot("\(name) at its end, clear of the companion")
            assertClearOfTheCompanion(lastLine(), "\(name)'s last line")
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            (back.exists ? back : app.navigationBars.buttons.firstMatch).tap()
            XCTAssertTrue(app.descendants(matching: .any)["browseSearch"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    private func assertClearOfTheCompanion(_ element: XCUIElement, _ name: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let plus = app.buttons["quickAddButton"].firstMatch
        XCTAssertTrue(plus.exists, "the + is on show", file: file, line: line)
        let top = plus.frame.minY - companion
        XCTAssertLessThanOrEqual(element.frame.maxY, top + 0.5,
                                 "\(name) ends at \(element.frame.maxY), the companion's top is at \(top)",
                                 file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) is hittable", file: file, line: line)
    }

    private func scrollToEnd() {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "a list on screen")
        for _ in 0..<8 {
            let before = lastLine().frame
            list.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.8)
            if lastLine().frame == before { break }
        }
    }

    private func scrollToTop() {
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 { list.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// The bottom-most text in the list on screen.
    private func lastLine() -> XCUIElement {
        let texts = app.collectionViews.firstMatch.staticTexts.allElementsBoundByIndex.filter { !$0.frame.isEmpty }
        let last = texts.max { $0.frame.maxY < $1.frame.maxY }
        XCTAssertNotNil(last, "a line on screen")
        return last ?? app.collectionViews.firstMatch
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
