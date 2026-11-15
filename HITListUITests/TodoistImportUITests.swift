import XCTest

/// Brief 137 on iPhone: Settings → iCloud & data with `-todoistImportFixture` opens the import's preview on the bundled
/// Todoist backup (a file picker cannot be driven). The test imports it, finds the tasks in the lists, launches again
/// on the same store (the preview finds all seven already there and has nothing to import), and undoes the import.
/// Screenshots land in the .xcresult (`xcrun xcresulttool export attachments`).
final class TodoistImportUITests: XCTestCase {
    private var app: XCUIApplication!
    private let store = "s137-\(UUID().uuidString.prefix(8))"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = store
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", TodoistFixtureArgument.name]
    }

    func testImportReimportAndUndo() {
        app.launch()
        openICloudAndData()
        let confirm = element("todoist-import-confirm")
        scroll(to: confirm)
        shot("Preview")
        XCTAssertTrue(element("todoist-preview-tasks").exists)
        XCTAssertTrue(confirm.label.contains("Import 7 tasks"), confirm.label)
        let unread = element("todoist-preview-unread")
        scroll(to: unread)
        unread.tap()
        pause()
        shot("Preview, dates not understood")
        scroll(to: confirm)
        confirm.tap()

        let undo = element("todoist-undo-row")
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "the import finished and offers its undo")
        scroll(to: element("todoist-message"))
        XCTAssertTrue(element("todoist-message").label.contains("Imported 7 tasks"), element("todoist-message").label)
        shot("Imported")
        close()

        // The lists: the Inbox has Todoist's Inbox; Browse has the new Group.
        tab("inbox")
        XCTAssertTrue(app.staticTexts["Call the dentist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Read the lease"].exists)
        shot("Inbox")

        // Again: the same backup finds everything already here.
        app.terminate()
        app.launch()
        openICloudAndData()
        let skipped = element("todoist-preview-skipped")
        scroll(to: skipped)
        XCTAssertTrue(skipped.exists, "the second preview counts what is already here")
        XCTAssertTrue(element("todoist-import-confirm").label.contains("Nothing new"), element("todoist-import-confirm").label)
        XCTAssertFalse(element("todoist-import-confirm").isEnabled)
        shot("Second run")

        // Undo last import, after the question.
        let undoAgain = element("todoist-undo-row")
        scroll(to: undoAgain)
        undoAgain.tap()
        let remove = app.buttons["Remove 7 tasks"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "the question names the count")
        shot("Undo question")
        remove.tap()
        XCTAssertTrue(undoAgain.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("todoist-message").label.contains("Removed 7 tasks"), element("todoist-message").label)
        shot("Undone")
        close()
        tab("inbox")
        XCTAssertTrue(app.staticTexts["Call the dentist"].waitForNonExistence(timeout: 5))
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
        pause()
    }

    private func openICloudAndData() {
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        let row = element("settings-page-iCloud")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Settings opened")
        row.tap()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 5), "iCloud & data opened")
        pause()
    }

    private func close() {
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element("settings-profile").waitForNonExistence(timeout: 5), "Settings closed")
        pause(0.6)
    }

    /// Drags the open page until `target` is on screen and clear of the sheet's bar and the screen's foot.
    private func scroll(to target: XCUIElement) {
        let top: CGFloat = 125
        let bottom = app.frame.height - 60
        for _ in 0..<14 {
            if target.exists, target.frame.minY > top, target.frame.maxY < bottom { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let up = !target.exists || target.frame.maxY >= bottom
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -320 : 220)))
            pause(0.5)
        }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

/// The app's `TodoistFixture.launchArgument`, spelled here because the UI test target does not link the app.
private enum TodoistFixtureArgument {
    static let name = "-todoistImportFixture"
}
