import XCTest

/// Brief 94: the system's accessibility audit (`XCUIApplication.performAccessibilityAudit`) on every main iPhone
/// screen, card, picker and Settings page, with the demo week. Each screen's findings fail the test unless an
/// exclusion below names them with its reason (`exclusions`). Every audited screen keeps a screenshot in the
/// .xcresult, and the findings, excluded ones marked, are one text attachment per test.
///
/// The screens are audited as VoiceOver reads them (`-voiceOverRows YES`: each task row one element, as with VoiceOver
/// on; `TaskRowSpeech`). Without it the audit also measures every word inside a row as a target of its own, and a row's
/// target is the whole row.
///
/// Explore mode (`TEST_RUNNER_HITLIST_AUDIT_EXPLORE=1`) records every finding, excluded or not, in one text
/// attachment and fails nothing, for working through a screen.
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var findings: [String] = []
    private var explore: Bool { ProcessInfo.processInfo.environment["HITLIST_AUDIT_EXPLORE"] == "1" }

    /// On demand (`TEST_RUNNER_HITLIST_AUDIT=1`, or explore mode), like the screen tour: the audit's findings depend on
    /// the simulator's size and what the demo week shows that hour, and its exclusions were still being settled when
    /// round 19 was merged, so an ordinary UI run skips it rather than going red on a finding nobody has judged yet.
    ///
    ///     TEST_RUNNER_HITLIST_AUDIT=1 xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
    ///       -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:HITListUITests/AccessibilityAuditUITests
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_AUDIT"] == "1" || explore,
                          "the accessibility audit runs on demand (TEST_RUNNER_HITLIST_AUDIT=1)")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s94-\(UUID().uuidString.prefix(8))"
        app.launchArguments += ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES",
                                "-seedSharedTasksSample", "YES", "-voiceOverRows", "YES"]
    }

    override func tearDown() {
        let report = XCTAttachment(string: findings.isEmpty ? "No findings." : findings.joined(separator: "\n"))
        report.name = "Audit findings"
        report.lifetime = .keepAlways
        add(report)
        super.tearDown()
    }

    // MARK: The screens

    func testTabsBrowseAndLists() throws {
        app.launch()
        for name in ["inbox", "today", "upcoming", "flipboard"] {
            tab(name)
            audit("Tab \(name)")
        }
        tab("inbox")
        tapElement("browseButton")
        pause()
        audit("Browse")
        let work = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Work")).firstMatch
        if work.waitForExistence(timeout: 3) {
            work.tap()
            pause()
            audit("A Group: Work")
            app.navigationBars.buttons.firstMatch.tap()
            pause()
        }
        let shared = element("browse-shared-tasks")
        if shared.waitForExistence(timeout: 3) {
            shared.tap()
            pause()
            audit("Shared Tasks")
            app.navigationBars.buttons.firstMatch.tap()
            pause()
        }
    }

    func testQuickAddAndItsPickers() throws {
        app.launch()
        tab("inbox")
        tapElement("quickAddButton")
        XCTAssertTrue(element("quickAddTitle").waitForExistence(timeout: 5), "the card")
        pause(1)
        audit("Quick add, empty")
        app.typeText("Call Sam tomorrow 9am p2 ")
        pause()
        audit("Quick add, typed with highlights")
        for chip in ["quickAddDateChip", "quickAddPriorityChip", "quickAddReminderChip", "quickAddGroupChip"] {
            let button = element(chip)
            guard button.waitForExistence(timeout: 3) else { record("\(chip): missing"); continue }
            button.tap()
            pause(1)
            audit("Quick add picker: \(chip)")
            closePicker()
        }
    }

    func testEditorAndItsCards() throws {
        app.launch()
        tab("today")
        let task = app.staticTexts.matching(NSPredicate(format: "label == %@", "Reply to Sam about the lease")).firstMatch
        guard task.waitForExistence(timeout: 8) else { return record("editor: no demo task") }
        task.tap()
        XCTAssertTrue(element("editorTitle").waitForExistence(timeout: 5), "the editor")
        pause(1)
        audit("Editor")
        for chip in ["popoutDateRow", "popoutPriorityChip", "popoutReminderChip", "popoutLabelsChip", "popoutRepeatChip"] {
            let button = element(chip)
            guard button.waitForExistence(timeout: 3), button.isHittable else { record("\(chip): not on screen"); continue }
            button.tap()
            pause(1)
            audit("Editor card: \(chip)")
            closePicker()
        }
    }

    func testFlipboardCards() throws {
        app.launch()
        tab("flipboard")
        let add = element("addSwitchTile")
        if add.waitForExistence(timeout: 5) {
            add.tap()
            pause(1.2)
            audit("Flipboard: adding a switch")
            tapIfThere("switchClose")
            tapIfThere("switchDiscard")
            pause()
        }
        let tile = element("flipSwitchTile")
        if tile.waitForExistence(timeout: 3) {
            tile.press(forDuration: 0.8)
            pause()
            audit("Flipboard: a switch's menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            pause()
        }
    }

    func testCompletionToast() throws {
        app.launch()
        tab("today")
        let check = app.buttons.matching(NSPredicate(format: "label == %@", "Complete task")).firstMatch
        guard check.waitForExistence(timeout: 8) else { return record("toast: no checkbox") }
        check.tap()
        pause(0.8)
        audit("Undo toast")
    }

    func testSettingsPages() throws {
        app.launch()
        tab("inbox")
        tapElement("browseButton")
        tapElement("settingsButton")
        XCTAssertTrue(element("settings-profile").waitForExistence(timeout: 5), "Settings")
        pause()
        audit("Settings, first screen")
        for page in ["profile", "page-general", "page-reminders", "page-extras", "page-iCloud", "page-claude", "page-about"] {
            let row = element("settings-\(page)")
            guard row.waitForExistence(timeout: 5) else { record("settings-\(page): missing"); continue }
            row.tap()
            XCTAssertTrue(app.buttons["sheetBack"].firstMatch.waitForExistence(timeout: 5), "\(page) opened")
            pause()
            audit("Settings: \(page)")
            scrollPage()
            audit("Settings: \(page), scrolled")
            app.buttons["sheetBack"].firstMatch.tap()
            pause()
        }
    }

    /// Larger Text, one size up from the default (xLarge): every main screen and the quick-add card, screenshots kept
    /// for the eye (brief 94: text clipped at one size up is a fault; the audit's own clipping check guesses at the
    /// largest sizes).
    func testLargerTextOneSizeUp() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"]
        app.launch()
        for name in ["inbox", "today", "upcoming", "flipboard"] {
            tab(name)
            shot("xLarge: \(name)")
        }
        tab("inbox")
        tapElement("quickAddButton")
        XCTAssertTrue(element("quickAddTitle").waitForExistence(timeout: 5), "the card")
        app.typeText("Call Sam tomorrow 9am p2 ")
        pause()
        shot("xLarge: quick add")
        tapElement("quickAddDateChip")
        pause(1)
        shot("xLarge: date card")
    }

    // MARK: Pressing and hearing

    /// The bolt takes a tap anywhere on its glyph (brief 94: drawn `SyncBolt.nudge` outside its toolbar slot, it took
    /// clicks on the Mac only on the strip still inside the slot).
    func testSyncBoltTakesATapAcrossItsGlyph() throws {
        app.launch()
        tab("today")
        let bolt = app.buttons["syncBolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 5))
        let frame = bolt.frame
        var misses: [CGFloat] = []
        var log: [String] = ["bolt frame \(frame)"]
        for x in stride(from: frame.minX + 1, through: frame.maxX - 1, by: 2) {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: frame.midY)).tap()
            // The bolt opens Settings at iCloud & data.
            let opened = element("settings-check-icloud").waitForExistence(timeout: 2.5)
            log.append("x \(x): \(opened ? "opens Settings" : "nothing")")
            if opened {
                app.buttons["Done"].firstMatch.tap()
                _ = element("settings-check-icloud").waitForNonExistence(timeout: 5)
                pause(0.6)
            } else {
                misses.append(x)
            }
        }
        record(log.joined(separator: "; "))
        XCTAssertTrue(misses.isEmpty, "taps on the bolt that did nothing, at x = \(misses)")
    }

    /// For the eye, not a check: with `-dumpAccessibility YES` the app logs what VoiceOver can reach every 4 s
    /// (`AccessibilityDump`); this holds Today, then the quick-add card, then a Settings page, long enough for a pass each.
    /// Skipped unless `TEST_RUNNER_HITLIST_AUDIT_EXPLORE=1`.
    func testDumpWhatVoiceOverReaches() throws {
        try XCTSkipUnless(explore, "a look for the eye, run with TEST_RUNNER_HITLIST_AUDIT_EXPLORE=1")
        app.launchArguments += ["-dumpAccessibility", "YES"]
        app.launch()
        tab("today")
        pause(9)
        // The editor (a sheet), then the undo toast after completing from the list.
        let task = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Buy groceries")).firstMatch
        if task.waitForExistence(timeout: 5) {
            task.tap()
            pause(9)
            app.swipeDown(velocity: .fast)
            pause(2)
        }
        tab("flipboard")
        pause(9)
        tab("upcoming")
        pause(9)
        tab("inbox")
        tapElement("quickAddButton")
        pause(9)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        pause(2)
        tapElement("browseButton")
        pause(9)
        tapElement("settingsButton")
        pause(9)
        element("settings-page-extras").tap()
        pause(9)
    }

    /// With VoiceOver a task row is one stop: its title, then what its second line says, and completing is an action.
    func testRowsReadAsOneStop() throws {
        app.launchArguments += ["-voiceOverRows", "YES"]
        app.launch()
        tab("today")
        let gym = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'taskRow' AND label == 'Gym'")).firstMatch
        XCTAssertTrue(gym.waitForExistence(timeout: 8), "the Gym row")
        record("Gym row: label \(gym.label), value \(String(describing: gym.value))")
        // "7:00 AM, repeats, Health", or after seven "7:00 AM, overdue, repeats, Health" (the demo's Gym is at 7:00 today).
        // Times are written with a narrow no-break space before AM.
        let value = (gym.value as? String ?? "").replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertTrue(value.hasPrefix("7:00 AM, ") && value.hasSuffix("repeats, Health"), value)
        audit("Today, rows as VoiceOver reads them")
    }

    // MARK: The audit

    /// Runs the audit on what is on screen now and records each finding (with a screenshot of the screen).
    private func audit(_ screen: String) {
        shot(screen)
        if explore {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Tree: \(screen)"
            tree.lifetime = .keepAlways
            add(tree)
        }
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let finding = Finding(issue, screen: screen)
                if let rule = Self.exclusions.first(where: { $0.matches(finding) }) {
                    self.findings.append("EXCLUDED (\(rule.reason)) \(finding.line)")
                    return true
                }
                self.findings.append(finding.line)
                return self.explore
            }
        } catch {
            record("\(screen): the audit did not run: \(error)")
        }
    }

    /// One finding, read once: its element's type, label, identifier and frame (nil where the audit names none).
    private struct Finding {
        let screen: String
        let type: XCUIAccessibilityAuditType
        let summary: String
        let detail: String
        let elementType: XCUIElement.ElementType?
        let label: String
        let identifier: String
        let frame: CGRect

        init(_ issue: XCUIAccessibilityAuditIssue, screen: String) {
            self.screen = screen
            type = issue.auditType
            summary = issue.compactDescription
            detail = issue.detailedDescription
            // An element that has gone since (the undo toast leaves after a few seconds) is read as none: asking a
            // gone element for its label fails the test.
            let element = issue.element.flatMap { $0.exists ? $0 : nil }
            elementType = element?.elementType
            label = element?.label ?? ""
            identifier = element?.identifier ?? ""
            frame = element?.frame ?? .null
        }

        var line: String {
            var parts = ["[\(screen)] \(AccessibilityAuditUITests.typeName(type)): \(summary)"]
            if let elementType {
                let id = identifier.isEmpty ? "" : " id=\(identifier)"
                parts.append("element: \(elementType.rawValue)\(id) label=\"\(label)\" frame=\(frame)")
            }
            parts.append(detail)
            return parts.joined(separator: " | ")
        }

        /// In the island at the foot of the screen (the tab bar).
        var inTabBar: Bool { !frame.isNull && frame.minY > 760 }
        var isControl: Bool { elementType == .button || elementType == .textField || elementType == .switch }
    }

    /// A finding left as it is, and why (brief 94: "exclude a finding only with a written reason").
    private struct Exclusion {
        let reason: String
        let matches: (Finding) -> Bool
    }

    private static let themeNames: Set<String> = ["Slate", "Graphite", "Midnight", "Moss", "Nord", "Tokyo", "Mocha", "Rosé"]
    /// Rows shown dimmed because they can't be used here (sync is off in the test, there is no profile to delete).
    private static let disabledRows: Set<String> = ["Delete profile…", "Reset local cache…",
                                                    "Downloads it all again; unsynced changes are lost"]

    private static let exclusions: [Exclusion] = [
        // Larger Text.
        Exclusion(reason: "Inter is set with Font.custom(_:size:relativeTo:), which follows Dynamic Type "
                  + "(testLargerTextOneSizeUp); the audit counts a custom font as only partly scaling. The tab island's "
                  + "names stop growing at xLarge, by design: the island has fixed room") {
            $0.type == .dynamicType && $0.summary.contains("partially")
        },
        Exclusion(reason: "fixed sizes in the design system (README): the sheet bars' titles (HITType.title), the card's "
                  + "and the editor's title (HITType.taskName) and the Today tab's day number in its 23 pt page glyph") {
            $0.type == .dynamicType && ($0.identifier == "editorTitle" || $0.frame.minY < 125 || $0.inTabBar)
        },
        Exclusion(reason: "the audit's guess at the largest accessibility sizes, where one-line labels (chips, a row's "
                  + "second line, the island's names) truncate by design; at one size up, brief 94's bar, none is cut "
                  + "(testLargerTextOneSizeUp's screenshots)") {
            $0.type == .textClipped
        },
        // Contrast: every text/surface pair of every theme passes WCAG AA on its own surface (ThemeTests; Slate's
        // secondary text is 6.5:1 on surface, 5.7:1 on elevated). These are not that.
        Exclusion(reason: "in or under the tab island: Theme.secondaryText (and whatever scrolls beneath) over the "
                  + "island's glass, which a list under it lightens. The token is at fault over glass; not repainted") {
            $0.type == .contrast && !$0.frame.isNull && $0.frame.minY > 740
        },
        Exclusion(reason: "scrolled up under the sheet bar's soft edge, which fades what passes beneath it") {
            $0.type == .contrast && $0.screen.hasSuffix("scrolled") && !$0.frame.isNull && $0.frame.minY < 170
        },
        Exclusion(reason: "the sheet bar's back control and the page title over the bar's glass") {
            $0.type == .contrast && !$0.frame.isNull && $0.frame.minY < 120 && $0.screen.hasPrefix("Settings")
        },
        Exclusion(reason: "a control dimmed because it can't be used here; WCAG leaves inactive controls out") {
            $0.type == .contrast && disabledRows.contains($0.label)
        },
        Exclusion(reason: "the week strip's days before today, dimmed on purpose") {
            $0.type == .contrast && $0.screen == "Tab upcoming" && !$0.frame.isNull && (195...260).contains($0.frame.minY)
        },
        Exclusion(reason: "a theme's name measured against its own swatch, a picture of that theme") {
            $0.type == .contrast && themeNames.contains($0.label)
        },
        Exclusion(reason: "HITSegmented's chosen segment over its moving Liquid Glass highlight; the token is at fault "
                  + "over glass (Theme.secondaryText's 5.7:1 is on Theme.elevated); not repainted") {
            $0.type == .contrast && ["Slam", "Strike"].contains($0.label)
        },
        Exclusion(reason: "the screen behind the quick-add card's dimmed backdrop: hidden from VoiceOver while the card "
                  + "is up (AccessibilityDump finds the card's nine stops alone); the audit still measures what it sees") {
            $0.type == .contrast && $0.elementType == nil && $0.screen.hasPrefix("Quick add")
        },
        Exclusion(reason: "a word inside a task row, which VoiceOver reads as one stop, so the audit names no element. "
                  + "Every colour a row draws its words in passes AA on Theme.background (due green 5.6:1, orange 8.7, "
                  + "purple 6.0, P1 red 6.4, a label's default grey 6.3, secondary text 7.1); a Group's or a label's own "
                  + "colour is the person's choice") {
            $0.type == .contrast && $0.elementType == nil
                && ["Tab inbox", "Tab today", "Tab upcoming", "Browse", "A Group: Work", "Shared Tasks",
                    "Undo toast"].contains($0.screen)
        },
        Exclusion(reason: "the date card's small Today preset in the due-today green: 5.2:1 on Theme.surface by its "
                  + "token; the audit's reading of the small anti-aliased text comes out just under") {
            $0.type == .contrast && $0.summary.contains("nearly") && $0.label == "Today" && $0.screen.contains("Date")
        },
        Exclusion(reason: "the undo toast fades out a few seconds after it appears, sooner than the audit finishes; "
                  + "its words are HITColor.text (12:1) and the accent (5.4:1) on Theme.elevated") {
            $0.type == .contrast && $0.screen == "Undo toast" && !$0.frame.isNull && $0.frame.minY > 650
        },
        Exclusion(reason: "a chip scrolled partly out of the card's chip bar, under its fade") {
            $0.type == .contrast && !$0.frame.isNull && $0.frame.maxX > 390
        },
        // Targets.
        Exclusion(reason: "iPhone: the bolt is drawn 16 x 23 pt in a 44 pt toolbar slot that takes the tap across all "
                  + "of the glyph (testSyncBoltTakesATapAcrossItsGlyph)") {
            $0.type == .hitRegion && $0.identifier == "syncBolt"
        },
        Exclusion(reason: "the calendar's this-month dot: 18 pt wide between ‹ and ›, which take presses themselves; "
                  + "it now takes presses 36 pt tall") {
            $0.type == .hitRegion && $0.label == "This month"
        },
        Exclusion(reason: "not a control: a word, a light or a face inside a row or a tile, whose whole row or tile "
                  + "takes the press") {
            $0.type == .hitRegion && $0.elementType != nil && !$0.isControl
        },
        // Elements.
        Exclusion(reason: "the list's words dimmed behind the editor's sheet or the quick-add card, which hide them "
                  + "from VoiceOver as a card should (brief 94 hid them behind the quick-add card)") {
            $0.type == .elementDetection && $0.elementType == nil
                && ($0.screen.hasPrefix("Editor") || $0.screen.hasPrefix("Quick add"))
        },
    ]

    static func typeName(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "type \(type.rawValue)"
        }
    }

    private func record(_ line: String) { findings.append("NOTE \(line)") }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tab(_ name: String) {
        let button = app.buttons["tab-\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "tab \(name)")
        button.tap()
        _ = button.wait(for: \.isSelected, toEqual: true, timeout: 5)
        pause()
    }

    private func tapElement(_ id: String) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(id) on screen")
        target.tap()
        pause()
    }

    private func tapIfThere(_ id: String) {
        let target = element(id)
        if target.waitForExistence(timeout: 2), target.isHittable { target.tap() }
    }

    /// Closes an open picker card: a tap high on the screen, outside the card.
    private func closePicker() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        pause()
        if !element("quickAddTitle").exists && !element("editorTitle").exists {
            record("closing a picker closed its popout too")
        }
    }

    private func scrollPage() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -400)))
        pause()
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
