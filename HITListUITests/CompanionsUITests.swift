import XCTest

/// The companions on iPhone (brief 76): Nod on Browse's search field, which keeps every tap meant for it.
/// Run with `SIMULATOR=<your simulator> scripts/test.sh ui`; the screenshots land in the .xcresult.
final class CompanionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
    }

    /// A tap on the field right under Nod's dangling feet focuses the field and takes typing, as anywhere else on it.
    func testATapUnderNodsFeetReachesTheField() throws {
        app.launch()
        openBrowse()
        let field = searchField()
        snapshot("Browse with Nod on the field")
        // Nod sits 14 pt from the field's trailing edge, its feet 4 to 6 pt down into it.
        let feet = field.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: field.frame.width - 14 - 12, dy: 4))
        feet.tap()
        app.typeText("gym")
        XCTAssertEqual(field.value as? String, "gym", "the tap reached the field and it took the typing")
        snapshot("Typed under Nod's feet")
    }

    // MARK: - Helpers

    private func searchField() -> XCUIElement {
        let field = app.textFields["browseSearch"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func openBrowse() {
        let browse = app.buttons["browseButton"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        browse.tap()
        XCTAssertTrue(app.textFields["browseSearch"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
