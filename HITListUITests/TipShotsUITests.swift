import XCTest

/// Brief 162 on iPhone: a picture of every tip in its real place, with `-showAllTips`, and each tip's frame read
/// as it appears and again a second later (a tip must not change its size once it is up). Pictures land in the
/// .xcresult and, when `TEST_RUNNER_HITLIST_SHOTS_DIR` is set, in that folder as "<label> <name>.png"
/// (`TEST_RUNNER_HITLIST_SHOTS_LABEL`, "before" or "after"). Frames go into an attachment "tip frames".
final class TipShotsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var frames: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s162t-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-showAllTips", "-seedDemoData", "YES"]
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: frames.joined(separator: "\n"))
        attachment.name = "tip frames"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = shotsDir {
            try? frames.joined(separator: "\n").write(toFile: dir + "/\(label) tip frames.txt",
                                                      atomically: true, encoding: .utf8)
        }
    }

    private var shotsDir: String? { ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] }
    private var label: String { ProcessInfo.processInfo.environment["HITLIST_SHOTS_LABEL"] ?? "run" }

    func testEveryTip() {
        app.launch()
        let inbox = app.buttons["tab-inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 30), "the app is up")

        // Today first: the calendar tip over the list.
        tab("today")
        watchTip("calendar tip over Today")
        shot("1 Today, calendar tip")
        dismissTip()

        // The Inbox: Browse's tip on the magnifying glass.
        tab("inbox")
        watchTip("browse tip")
        shot("2 Inbox, browse tip")
        dismissTip()

        // Quick add's floating tips: the syntax, then keep-as-text once something lights up.
        app.buttons["quickAddButton"].firstMatch.tap()
        _ = element("quickAddTitle").waitForExistence(timeout: 5)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        watchTip("quick add syntax tip")
        shot("3 Quick add, syntax tip")
        app.typeText("Call mom tomorrow ")
        pause(1)
        watchTip("quick add after typing")
        shot("4 Quick add, after typing")
        // Add it: the iPhone's card closes after a save.
        let save = element("quickAddSave")
        if save.exists { save.tap() }
        pause(1.5)

        // The Flipboard: its first switch's tip.
        let flip = app.buttons["tab-flipboard"].firstMatch
        if flip.waitForExistence(timeout: 3) {
            flip.tap()
            pause(1.5)
            watchTip("flipboard tip")
            shot("5 Flipboard, switch tip")
            dismissTip()
        }

        // Review Inbox: its swipe tip, inline on the card.
        tab("inbox")
        let options = app.buttons["viewOptions"].firstMatch
        if options.waitForExistence(timeout: 5) {
            options.tap()
            pause(0.8)
            let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
            if review.waitForExistence(timeout: 3) {
                review.tap()
                pause(1.5)
                watchTip("review tip")
                shot("6 Review Inbox, swipe tip")
            }
        }
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tab(_ name: String) {
        let tab = app.buttons["tab-\(name)"].firstMatch
        guard tab.waitForExistence(timeout: 5) else { return }
        tab.tap()
        pause(0.3)
    }

    /// The tip's × as soon as it is there, then after a second: the two must agree (a popover tip's own identifier
    /// does not reach the accessibility tree; its × sits in its top trailing corner, so it moves if the tip changes
    /// its width or place).
    private func watchTip(_ name: String) {
        let tip = app.buttons["Dismiss tip"].firstMatch
        guard tip.waitForExistence(timeout: 4) else { frames.append("\(name): no tip"); return }
        let first = tip.frame
        pause(1.2)
        let later = tip.exists ? tip.frame : .zero
        let screen = app.frame
        frames.append(String(format: "%@: first %.0f×%.0f at (%.0f,%.0f); later %.0f×%.0f at (%.0f,%.0f); screen %.0f",
                             name, first.width, first.height, first.minX, first.minY,
                             later.width, later.height, later.minX, later.minY, screen.width))
        XCTAssertEqual(first.size.width, later.size.width, accuracy: 0.5, "\(name): the width holds")
        XCTAssertEqual(first.size.height, later.size.height, accuracy: 0.5, "\(name): the height holds")
        XCTAssertGreaterThanOrEqual(later.minX, 0, "\(name): on screen")
        XCTAssertLessThanOrEqual(later.maxX, screen.maxX, "\(name): on screen")
    }

    private func dismissTip() {
        let close = app.buttons["Dismiss tip"].firstMatch
        if close.exists, close.isHittable { close.tap() }
        pause(0.8)
    }

    private func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = shotsDir {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(label) \(name).png"))
        }
    }
}
