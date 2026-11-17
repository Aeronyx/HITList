import XCTest

/// Round 32, brief 157: what the task editor must never drop or hide, seen on the iPhone.
///
/// - Typing in an open editor lands when the app goes to the background, so iOS ending the app there loses nothing
///   (the data review's B9). The editor stays open and asks nothing.
/// - The delete question names the sub-tasks that go with the task (C13).
/// - A move to Shared Tasks names what a shared task can't hold, first (B7).
///
/// Every launch uses a store and settings of its own (`HITLIST_STORE_SUFFIX`), as `HITListUITests` does.
final class EditorSafetyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "uitest-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips"]
    }

    func testTypingInTheEditorSurvivesTheAppBeingEndedInTheBackground() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        app.buttons["tab-inbox"].tap()
        addFromTheCard("Kept on quit")
        openEditor("Kept on quit")

        app.buttons["editorDescriptionPill"].firstMatch.tap()
        let notes = app.descendants(matching: .any)["editorDescription"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "the description field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard in the description")
        app.typeText("Typed, never confirmed")
        snapshot("1 Typed, not confirmed")

        // Home: the app goes to the background with the editor open; then iOS ends it.
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.terminate()

        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        app.buttons["tab-inbox"].tap()
        openEditor("Kept on quit")
        let kept = app.descendants(matching: .any)["editorDescription"].firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "the description shows: it was saved")
        XCTAssertEqual(kept.value as? String, "Typed, never confirmed")
        snapshot("2 After the app was ended")
    }

    func testTheDeleteQuestionNamesTheSubtasks() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        app.buttons["tab-inbox"].tap()
        addFromTheCard("Pack for the trip")
        openEditor("Pack for the trip")
        for item in ["Socks", "Charger"] {
            let add = app.buttons["addSubtask"].firstMatch
            if add.waitForExistence(timeout: 2) { add.tap() }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the sub-task field")
            app.typeText(item + "\n")
        }
        app.buttons["editorConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForNonExistence(timeout: 5))

        openEditor("Pack for the trip")
        app.buttons["popoutMore"].firstMatch.tap()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let words = "“Pack for the trip” and its 2 sub-tasks will be deleted on all your devices."
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "the question names the sub-tasks")
        snapshot("3 Delete question with sub-tasks")
    }

    func testAMoveToSharedTasksNamesWhatStaysBehind() throws {
        app.launchArguments += ["-seedSharedTasksSample", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 15))
        app.buttons["tab-inbox"].tap()
        addFromTheCard("Water plants every day @home")
        openEditor("Water plants")
        app.buttons["editorGroupRow"].firstMatch.tap()
        let shared = app.descendants(matching: .any)["groupCardSharedTasks"].firstMatch
        XCTAssertTrue(shared.waitForExistence(timeout: 5), "Shared Tasks in the Group card")
        shared.tap()
        let words = "Shared tasks can’t keep its label and repeat. They’ll be dropped."
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 5), "the move names what stays behind")
        snapshot("4 Move to Shared Tasks question")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 5), "Cancel keeps the task")
    }

    // MARK: Helpers

    private func addFromTheCard(_ title: String) {
        app.buttons["quickAddButton"].firstMatch.tap()
        let field = app.descendants(matching: .any)["quickAddTitle"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card's title field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(title)
        app.buttons["quickAddSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the card closes after Add")
    }

    private func openEditor(_ title: String) {
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), title)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTitle"].waitForExistence(timeout: 5), "the editor")
    }

    private func snapshot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
