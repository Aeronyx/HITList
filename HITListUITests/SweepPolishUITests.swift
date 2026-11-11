import XCTest

/// Brief 99 on iPhone, through the real app on whatever iPhone it runs on: a list's rows and headers on the large
/// title's edge (16 pt on most phones, 20 on the widest), no hairline between a large title and the first row, a day
/// written the one way ("Nov 11 · Today · Wednesday"), and Reminders → Summary time in our own time field. Each launch
/// has a store of its own, sync off, no tips, the demo week. Screenshots land in the .xcresult
/// (`xcrun xcresulttool export attachments`).
final class SweepPolishUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s99-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES"]
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Lists

    /// Today's day header starts where the large title does (the system's margin), and reads the one way.
    func testTodaysHeaderSharesTheLargeTitlesEdgeAndReadsTheOneWay() throws {
        try launchPhone()
        tab("today")
        let title = app.navigationBars.staticTexts["Today"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the large title")
        let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " · Today · ")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Today's header in the one form: \(app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label))")
        pause(1)
        try assertSharesTheTitlesEdge(header, title)
        shot("Today")
    }

    /// Upcoming's day headers read as every list's: "Nov 12 · Tomorrow · Thursday", on the title's edge.
    func testUpcomingsHeadersReadTheOneWay() throws {
        try launchPhone()
        tab("upcoming")
        let title = app.navigationBars.staticTexts["Upcoming"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let tomorrow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " · Tomorrow · ")).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5), "Tomorrow's header in the one form")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Wed · ", " · Today")).firstMatch.exists,
                       "not the old weekday-first form")
        pause(1)
        try assertSharesTheTitlesEdge(tomorrow, title)
        shot("Upcoming")
    }

    /// No hairline between the Inbox's large title and its first row (the Inbox and Completed drew one 1 pt under it).
    func testNoHairlineUnderTheInboxsLargeTitle() throws {
        try launchPhone()
        tab("inbox")
        let title = app.navigationBars.staticTexts["Inbox"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "the Inbox has rows")
        pause(1)
        let screenshot = XCUIScreen.main.screenshot()
        shot("Inbox")
        let lines = try hairlines(in: screenshot.image, from: title.frame.maxY + 2, to: firstRow.frame.minY + 4)
        XCTAssertTrue(lines.isEmpty, "no line across the screen between the title and the first row: \(lines)")
    }

    /// Today at the smallest text size, for the record: its meta lines stay at 13 pt and its captions at 12 (they fell to
    /// 10.7 and 9.7), so the rows' second lines keep their size while the titles shrink.
    func testTodayAtTheSmallestTextSize() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXS"]
        try launchPhone()
        tab("today")
        let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " · Today · ")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        pause(1)
        shot("Today, smallest text size")
    }

    // MARK: iPad

    /// The iPad sidebar's selected row is our own fill (the Mac's selection colour), with no accent outline round it.
    func testTheIPadSidebarsSelectionIsOurFill() throws {
        // On its side, where the split view keeps the sidebar beside the list (in portrait it slides away on a pick).
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let inbox = app.staticTexts["Inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 30), "the sidebar")
        try XCTSkipIf(app.buttons["tab-today"].exists, "the iPhone's tabs: no sidebar")
        pause(1)
        // The sidebar's row, read before the tap (after it, "Today" is also the list's large title): its cell when the
        // sidebar exposes one, else the band round its title across the sidebar's column.
        let today = app.staticTexts.matching(NSPredicate(format: "label == %@", "Today")).element(boundBy: 0)
        let title = today.frame
        let cell = app.cells.containing(NSPredicate(format: "label == %@", "Today")).firstMatch
        let row = cell.exists ? cell.frame : CGRect(x: 12, y: title.midY - 21, width: max(200, title.maxX + 80), height: 42)
        today.tap()
        pause(1.5)
        XCTAssertTrue(app.staticTexts["Inbox"].firstMatch.isHittable, "the sidebar is still beside the list")
        let image = XCUIScreen.main.screenshot().image
        shot("iPad sidebar, Today selected")
        let (ring, fill) = try accentPixels(in: image, onTheBorderOf: row)
        XCTAssertGreaterThan(fill, 500, "the selected fill inside the row (the scan is looking at the row): row \(row)")
        XCTAssertLessThan(ring, 20, "no accent outline round the selected row (\(ring) accent pixels on its border)")
    }

    // MARK: Settings

    /// Reminders → Summary time is our time field, never the system's picker: it shows the time and takes a typed one.
    func testTheSummaryTimeIsOurTimeField() throws {
        try launchPhone()
        // Switching the summary on asks for notifications once, on this simulator only.
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        openSettings()
        open("settings-page-reminders")
        let summary = element("settings-morning-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        if !app.textFields["pickerTimeField"].exists {
            summary.tap()
            pause(1)
            app.tap() // lets the interruption monitor answer the prompt, if one came
            pause(1)
        }
        let field = app.textFields["pickerTimeField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the summary's time is our field")
        XCTAssertEqual(app.datePickers.count, 0, "no system date picker on the page")
        shot("Reminders, summary time")
        field.tap()
        pause(0.5)
        // Everything in the field, then the new time over it (a tap can leave the cursor anywhere in "8:00 AM").
        field.typeKey("a", modifierFlags: .command)
        field.typeText("7:30\n")
        pause(0.8)
        let typed = (field.value as? String ?? "").replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(typed, "7:30 AM", "it took the typed time and wrote it back as the row writes times")
        shot("Reminders, summary time typed")
    }

    // MARK: Helpers

    private func launchPhone() throws {
        app.launch()
        try XCTSkipUnless(app.buttons["tab-today"].waitForExistence(timeout: 15), "the iPhone's tabs (this test is the phone shell's)")
    }

    private func tab(_ name: String) {
        app.buttons["tab-\(name)"].firstMatch.tap()
        pause()
    }

    private func openSettings() {
        tab("inbox")
        app.buttons["browseButton"].firstMatch.tap()
        let gear = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "Settings opened")
        pause()
    }

    private func open(_ id: String) {
        let row = element(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(id) on screen")
        row.tap()
        XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 5), "\(id) opened a page")
        pause()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first lit column of `element`'s band and of the large title's, on the screen's pixels, within 1.5 pt (the
    /// letters' own side bearings: "T", "N"). An element's frame is no help: a padded header's spans the row.
    private func assertSharesTheTitlesEdge(_ element: XCUIElement, _ title: XCUIElement,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let image = XCUIScreen.main.screenshot().image
        let header = try firstInk(in: image, band: element.frame)
        let large = try firstInk(in: image, band: title.frame)
        XCTAssertEqual(header, large, accuracy: 1.5, "the header's ink starts where the large title's does", file: file, line: line)
    }

    /// The leftmost x (points) in a horizontal band where a pixel stands clearly off the background (a letter's ink).
    private func firstInk(in image: UIImage, band: CGRect) throws -> CGFloat {
        let cg = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cg.width) / image.size.width
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let y0 = max(0, Int(band.minY * scale)), y1 = min(h - 1, Int(band.maxY * scale))
        let bg = (y0 * w + 1) * 4
        for x in 0..<w {
            for y in y0...y1 {
                let i = (y * w + x) * 4
                let d = max(abs(Int(pixels[i]) - Int(pixels[bg])), abs(Int(pixels[i + 1]) - Int(pixels[bg + 1])),
                            abs(Int(pixels[i + 2]) - Int(pixels[bg + 2])))
                if d > 60 { return CGFloat(x) / scale }
            }
        }
        return .infinity
    }

    /// How many pixels on a rectangle's border (a point inside and outside each edge) are the accent's light blue, the
    /// system focus outline's colour (the selected fill is darker: the Mac's selection colour).
    private func accentPixels(in image: UIImage, onTheBorderOf frame: CGRect) throws -> (ring: Int, fill: Int) {
        let cg = try XCTUnwrap(image.cgImage)
        // On its side the picture's pixels stay in the device's upright frame (the image only says it is turned).
        let sideways = (cg.width < cg.height) != (image.size.width < image.size.height)
        let scale = CGFloat(max(cg.width, cg.height)) / max(image.size.width, image.size.height)
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var turn = 0 // 0 upright, 1 and 2 the two quarter turns; the one that finds the fill is kept
        func rgb(_ ax: Int, _ ay: Int) -> (Int, Int, Int)? {
            let x = !sideways ? ax : turn == 1 ? w - 1 - ay : ay
            let y = !sideways ? ay : turn == 1 ? ax : h - 1 - ax
            guard x >= 0, y >= 0, x < w, y < h else { return nil }
            let i = (y * w + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        func isAccent(_ x: Int, _ y: Int) -> Bool {
            guard let (r, g, b) = rgb(x, y) else { return false }
            return b > 220 && g > 130 && r > 80 && r < 150 // #6C9EFF and its neighbours
        }
        func isFill(_ x: Int, _ y: Int) -> Bool {
            guard let (r, g, b) = rgb(x, y) else { return false }
            return b > 185 && b < 225 && g > 100 && g < 140 && r > 60 && r < 95 // the Mac's selection, #4D79D1
        }
        let px = frame.insetBy(dx: -2, dy: -2)
        let x0 = Int(px.minX * scale), x1 = Int(px.maxX * scale), y0 = Int(px.minY * scale), y1 = Int(px.maxY * scale)
        var best = (ring: 0, fill: 0)
        for candidate in (sideways ? [1, 2] : [0]) {
            turn = candidate
            var count = 0
            for band in 0..<Int(4 * scale) {
                for x in x0...x1 { if isAccent(x, y0 + band) { count += 1 }; if isAccent(x, y1 - band) { count += 1 } }
                for y in y0...y1 { if isAccent(x0 + band, y) { count += 1 }; if isAccent(x1 - band, y) { count += 1 } }
            }
            var fill = 0
            for y in stride(from: y0, through: y1, by: 2) { for x in stride(from: x0, through: x1, by: 2) where isFill(x, y) { fill += 1 } }
            if fill > best.fill { best = (count, fill) }
        }
        return best
    }

    /// The rows of pixels between two heights (points) where at least 60% of the screen's width differs from the
    /// background by a line's worth (a hairline is a faint colour drawn across the list), in points.
    private func hairlines(in image: UIImage, from top: CGFloat, to bottom: CGFloat) throws -> [CGFloat] {
        let cg = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cg.width) / image.size.width
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        let y0 = max(0, Int(top * scale)), y1 = min(h - 1, Int(bottom * scale))
        guard y0 < y1 else { return [] }
        let background = pixel(w / 2, y0)
        var found: [CGFloat] = []
        for y in y0...y1 {
            var differing = 0
            for x in stride(from: 0, to: w, by: 2) {
                let p = pixel(x, y)
                let d = max(abs(p.0 - background.0), abs(p.1 - background.1), abs(p.2 - background.2))
                if d >= 6 && d < 120 { differing += 1 }
            }
            if Double(differing) > 0.6 * Double(w / 2) { found.append(CGFloat(y) / scale) }
        }
        return found
    }
}
