import XCTest

/// Brief 169: every screen a stranger meets in the first week, as pictures, for a person to read one by one. It walks;
/// it does not judge (a missing element is noted and the walk goes on). Skipped unless `HITLIST_SWEEP=1`; the pictures
/// go to `HITLIST_SHOTS_DIR` (a folder on the Mac) as `<walk>-<nn>-<screen>.png`. Both variables go in xcodebuild's
/// environment *before* the command:
///
///     TEST_RUNNER_HITLIST_SWEEP=1 TEST_RUNNER_HITLIST_SHOTS_DIR=/path/to/folder xcodebuild test-without-building \
///       -project HITList.xcodeproj -scheme HITListUITests -destination 'platform=iOS Simulator,id=<UDID>' \
///       -derivedDataPath build.noindex/169 -only-testing:HITListUITests/StrangerSweepUITests
///
/// Each walk launches a store of its own (sync off). The first-run walks ask the system's questions, so run each on
/// an app that was just installed (`xcrun simctl uninstall <UDID> com.trammells.hitlist` between them). Runs on an
/// iPhone (four tabs) and an iPad (a sidebar).
final class StrangerSweepUITests: XCTestCase {
    private var app: XCUIApplication!
    private var walk = "walk"
    private var number = 0

    static let longTitle = "Ask the landlord whether the radiator in the back bedroom can be bled before the cold weather arrives, and whether the window latch can be fixed in the same visit"
    static let longDescription = String(repeating: "The radiator knocks every morning around six and the valve on the left side drips onto the floorboards; the last visit tightened it but the drip came back within a week. ", count: 6)
    static let longGroup = "Household paperwork, insurance renewals and everything for the move"

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_SWEEP"] == "1",
                          "brief 169's sweep runs only on demand (TEST_RUNNER_HITLIST_SWEEP=1)")
        continueAfterFailure = true
        app = XCUIApplication()
        // `HITLIST_SWEEP_LANDSCAPE=1`: the device on its side (an iPad's full width with the sidebar).
        XCUIDevice.shared.orientation = ProcessInfo.processInfo.environment["HITLIST_SWEEP_LANDSCAPE"] == "1" ? .landscapeLeft : .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: 1. First launch

    /// A new person who says yes: the location question, the first screen, the + with its tip, a first task with a
    /// reminder (the notification question), and the tips that follow.
    func test01FirstRunYes() throws { try firstRun(yes: true) }

    /// The same, answering no to both questions.
    func test02FirstRunNo() throws { try firstRun(yes: false) }

    private func firstRun(yes: Bool) throws {
        walk = yes ? "firstrun-yes" : "firstrun-no"
        app.resetAuthorizationStatus(for: .location)
        launch(seed: false, tips: true, extra: ["-askLocationAtLaunch", "YES"], waitForTabs: false)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 15) {
            snap("location-question")
            let button = alert.buttons.matching(NSPredicate(format: yes ? "label CONTAINS 'While Using'" : "label BEGINSWITH 'Don'")).firstMatch
            if button.exists { button.tap() } else { note("no answer button on the location question") }
        } else { note("no location question at the first launch") }
        _ = app.buttons["tab-inbox"].waitForExistence(timeout: 10) || app.staticTexts["Inbox"].waitForExistence(timeout: 5)
        pause(4)
        snap("first-screen")
        let plus = app.buttons["quickAddButton"].firstMatch
        if plus.waitForExistence(timeout: 5) {
            plus.tap()
            pause(1.5)
            snap("quickadd-first-open")
            app.typeText("Call the dentist tomorrow 9am !15mb ")
            pause(1)
            snap("quickadd-first-typed")
            app.buttons["quickAddSave"].firstMatch.tap()
            pause(2)
            let notify = springboard.alerts.firstMatch
            if notify.waitForExistence(timeout: 6) {
                snap("notification-question")
                let button = notify.buttons[yes ? "Allow" : "Don’t Allow"].exists ? notify.buttons[yes ? "Allow" : "Don’t Allow"]
                                                                                  : notify.buttons.element(boundBy: yes ? 1 : 0)
                button.tap()
                pause(1)
            } else { note("no notification question after the first task with a reminder") }
            snap("after-first-task")
        } else { note("no + on the first screen") }
        for name in ["today", "upcoming", "flipboard", "inbox"] {
            go(name)
            pause(1.5)
            snap("tab-\(name)")
        }
        // Away and back, as a person does: a tip may wait for the second visit.
        XCUIDevice.shared.press(.home)
        pause(1)
        app.activate()
        pause(3)
        snap("back-in-the-app")
        openBrowse()
        snap("browse")
        openSettings()
        snap("settings")
        let extras = element("settings-page-extras")
        if extras.waitForExistence(timeout: 3) {
            extras.tap()
            pause()
            shotDown("settings-extras")
            sheetBack()
        }
        let reminders = element("settings-page-reminders")
        if reminders.waitForExistence(timeout: 3) {
            reminders.tap()
            pause()
            shotDown("settings-reminders")
            sheetBack()
        }
        closeSettings()
    }

    // MARK: 2. Every tab and list

    func test03Lists() throws {
        walk = "lists"
        launch(seed: true)
        let names = isPhoneShell ? ["inbox", "today", "upcoming", "flipboard"] : ["inbox", "today", "upcoming", "flipboard", "Completed"]
        for name in names {
            go(name)
            snap(name)
            toTheEnd(name)
        }
        go("upcoming")
        chooseLayout("Week")
        snap("upcoming-week")
        weekScroll("upcoming-week")
        chooseLayout(nil)
        snap("upcoming-list-again")
        if isPhoneShell {
            go("inbox")
            openBrowse()
            snap("browse")
            toTheEnd("browse")
            openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Work")).firstMatch, "group-work")
            openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "errands")).firstMatch, "label-errands")
            openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Focus")).firstMatch, "filter-focus")
            openFromBrowse(element("browse-shared-tasks"), "shared-tasks")
            openFromBrowse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch, "completed")
        } else {
            for name in ["Work", "errands", "Focus", "Shared Tasks"] {
                go(name)
                snap("sidebar-\(name.lowercased())")
                toTheEnd("sidebar-\(name.lowercased())")
            }
            showSidebar()
            snap("sidebar")
        }
        search("lease")
        snap("search-results")
        search("zebra")
        snap("search-no-results")
        search("#Work")
        snap("search-group-syntax")
    }

    // MARK: 3. Every card and picker

    func test04QuickAdd() throws {
        walk = "quickadd"
        launch(seed: true)
        go("inbox")
        guard tapIfExists(app.buttons["quickAddButton"].firstMatch, timeout: 5) else { return note("no +") }
        pause(1.2)
        snap("empty")
        let more = element("quickAddPlus")
        if more.waitForExistence(timeout: 2) {
            more.tap()
            pause()
            snap("plus-menu")
            dismissMenu()
        }
        // A tap outside the + menu can take the title's focus on an iPad: give it back.
        if element("quickAddTitle").exists { element("quickAddTitle").tap(); pause(0.4) }
        app.typeText("Haircut ")
        pause()
        snap("typed-plain")
        app.typeText("tomorrow 11am p1 !15mb #Home @errands every 2 weeks ")
        pause()
        snap("typed-every-chip")
        let row = element("quickAddOptionBar")
        if row.exists {
            row.swipeLeft()
            pause()
            snap("chips-scrolled")
            row.swipeRight()
            pause()
        }
        for (id, name) in [("quickAddDateChip", "date"), ("quickAddPriorityChip", "priority"), ("quickAddReminderChip", "reminder"),
                           ("quickAddGroupChip", "group"), ("quickAddRepeatChip", "repeat"), ("quickAddDeadlineChip", "deadline"),
                           ("quickAddLocation", "location"), ("quickAddSubtasks", "subtasks")] {
            pickerShot(id, "picker-\(name)")
        }
        // The keyboard down, to see the card on its own.
        tapIfExists(app.buttons["Close"].firstMatch)
        pause()
        snap("discard-question")
        tapIfExists(app.buttons["quickAddKeepEditing"].firstMatch)
        pause()
        snap("after-keep-editing")
        tapIfExists(app.buttons["Close"].firstMatch)
        tapIfExists(element("quickAddDiscard"))
        pause()
        // A long line in quick add.
        tapIfExists(app.buttons["quickAddButton"].firstMatch, timeout: 5)
        pause(1)
        app.typeText(Self.longTitle + " ")
        pause()
        snap("typed-long")
        tapIfExists(app.buttons["Close"].firstMatch)
        tapIfExists(element("quickAddDiscard"))
        pause()
    }

    func test05EditorAndCards() throws {
        walk = "cards"
        launch(seed: true)
        go("inbox")
        add("Frame the print tomorrow 5pm p1 #Work @errands every week !15mb")
        openTask("Frame the print")
        if let field = optional(element("editorDescription")) {
            field.tap()
            pause(0.5)
            app.typeText("Hang it above the desk, level with the shelf.")
            pause(0.5)
        }
        let addRow = element("addSubtask")
        if scrollTo(addRow) {
            addRow.tap()
            pause(0.5)
            app.typeText("Measure the wall\n")
            app.typeText("Buy hooks\n")
            pause(0.5)
        }
        tapIfExists(app.buttons["editorConfirm"].firstMatch)
        pause()
        // Confirm may close the card: open it again to see everything in it.
        if !element("editorTitle").exists { openTask("Frame the print") }
        snap("editor-everything")
        let pills = element("editorPills")
        if pills.exists {
            pills.swipeLeft()
            pause()
            snap("editor-pills-scrolled")
            pills.swipeRight()
            pause()
        }
        for (id, name) in [("popoutDateRow", "date"), ("popoutPriorityChip", "priority"), ("popoutReminderChip", "reminder"),
                           ("popoutLabelsChip", "labels"), ("popoutRepeatChip", "repeat"), ("popoutDeadlineChip", "deadline"),
                           ("popoutLocationChip", "location"), ("editorGroupRow", "group")] {
            pickerShot(id, "editor-picker-\(name)")
        }
        // The repeat picker's custom card.
        if scrollTo(element("popoutRepeatChip"), horizontal: true) {
            element("popoutRepeatChip").tap()
            pause()
            if tapIfExists(element("repeatCustom")) {
                pause()
                snap("editor-repeat-custom")
                tapIfExists(element("repeatCustomCancel"))
            }
            dismissPopover()
        }
        let more = element("popoutMore")
        if more.waitForExistence(timeout: 2) {
            more.tap()
            pause()
            snap("editor-more-menu")
            let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'")).firstMatch
            if delete.waitForExistence(timeout: 2) {
                delete.tap()
                pause()
                snap("editor-delete-question")
                let cancel = app.buttons["Cancel"].firstMatch
                if cancel.exists { cancel.tap() } else { dismissPopover() }
                pause()
            } else { dismissMenu() }
        }
        closeEditor()
        // A demo task's card as it comes.
        go("today")
        openTask("Reply to Sam")
        snap("editor-demo-task")
        closeEditor()
        // Completing: the toast.
        let check = app.buttons["Complete task"].firstMatch
        if check.waitForExistence(timeout: 3) {
            check.tap()
            pause(0.6)
            snap("completion-toast")
            pause(4)
        }
        // Review Inbox.
        go("inbox")
        if tapIfExists(app.buttons["viewOptions"].firstMatch, timeout: 3) {
            pause()
            snap("inbox-view-options")
            let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
            if review.waitForExistence(timeout: 3) {
                review.tap()
                pause(1.2)
                snap("review-inbox")
                if let pick = optional(app.buttons["reviewPickDate"].firstMatch) {
                    pick.tap()
                    pause()
                    snap("review-pick-date")
                    dismissPopover()
                }
                let card = element("reviewCard")
                if card.exists {
                    card.swipeLeft()
                    pause(0.8)
                    snap("review-after-swipe-left")
                    tapIfExists(app.buttons["reviewUndo"].firstMatch)
                }
                tapIfExists(app.buttons["reviewDone"].firstMatch)
                tapIfExists(app.buttons["Done"].firstMatch, timeout: 1)
                pause()
            } else { dismissMenu() }
        }
        if tapIfExists(app.buttons["screenMenu"].firstMatch, timeout: 2) {
            pause()
            snap("inbox-screen-menu")
            dismissMenu()
        }
        // The Flipboard's cards.
        go("flipboard")
        let tile = app.descendants(matching: .any)["flipSwitchTile"].firstMatch
        if tile.waitForExistence(timeout: 3) {
            tile.press(forDuration: 1.0)
            pause()
            snap("switch-context-menu")
            let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Edit switch'")).firstMatch
            if edit.waitForExistence(timeout: 2) {
                edit.tap()
                pause(1.2)
                snap("switch-card-existing")
                closeEditor()
                tapIfExists(app.buttons["switchClose"].firstMatch, timeout: 1)
                tapIfExists(app.buttons["switchDiscard"].firstMatch, timeout: 1)
                pause()
            } else { dismissMenu() }
        }
        let addTile = element("addSwitchTile")
        if scrollTo(addTile) {
            addTile.tap()
            pause(1.2)
            snap("switch-card-empty")
            app.typeText("Water the ferns every 3 days")
            pause()
            snap("switch-card-typed")
            tapIfExists(app.buttons["switchClose"].firstMatch)
            pause()
            snap("switch-discard-question")
            tapIfExists(app.buttons["switchDiscard"].firstMatch)
            pause()
        }
        let board = element("newSwitchboardRow")
        if scrollTo(board) {
            board.tap()
            pause(1.2)
            snap("switchboard-card")
            tapIfExists(app.buttons["switchboardClose"].firstMatch)
            tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
            pause()
        }
        let menu = element("switchBoardMenu")
        if scrollTo(menu) {
            menu.tap()
            pause()
            snap("switchboard-menu")
            dismissMenu()
        }
        // Browse's delete question for a Group, and the new-Group card.
        if isPhoneShell {
            go("inbox")
            openBrowse()
            let work = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Work")).firstMatch
            if scrollTo(work) {
                work.press(forDuration: 1.0)
                pause()
                snap("group-context-menu")
                let delete = app.buttons["Delete"].firstMatch
                if delete.waitForExistence(timeout: 2) {
                    delete.tap()
                    pause()
                    snap("group-delete-question")
                    tapIfExists(app.buttons["Cancel"].firstMatch)
                } else { dismissMenu() }
                pause()
            }
            if tapIfExists(app.buttons["browseNew"].firstMatch) {
                pause()
                snap("browse-new-menu")
                for (label, name) in [("New Group…", "new-group"), ("New Label…", "new-label"), ("New Filter…", "new-filter")] {
                    if !app.buttons[label].exists { _ = tapIfExists(app.buttons["browseNew"].firstMatch); pause() }
                    if tapIfExists(app.buttons[label].firstMatch) {
                        pause(1.2)
                        snap(name)
                        tapIfExists(app.buttons["Cancel"].firstMatch)
                        pause()
                    }
                }
            }
        }
    }

    // MARK: 4. Settings

    func test06Settings() throws {
        walk = "settings"
        launch(seed: true)
        openSettings()
        shotDown("first-screen")
        let rows = ["settings-profile"] + ["general", "calendar", "reminders", "extras", "iCloud", "claude", "about"].map { "settings-page-\($0)" }
        for id in rows {
            let row = element(id)
            guard scrollTo(row) else { note("no \(id)"); continue }
            row.tap()
            pause()
            let name = id.replacingOccurrences(of: "settings-page-", with: "").replacingOccurrences(of: "settings-", with: "")
            shotDown(name)
            if id == "settings-page-general", tapScrolling("settings-quick-add-guide") { shotDown("general-quick-add-guide"); sheetBack() }
            if id == "settings-page-iCloud", tapScrolling("settings-sync-log-row") { shotDown("icloud-sync-log"); sheetBack() }
            if id == "settings-page-about", tapScrolling("settings-whats-new") { shotDown("about-whats-new"); sheetBack() }
            if id == "settings-page-general", tapScrolling("settings-start-screen") { snap("general-start-screen-menu"); dismissMenu() }
            sheetBack()
        }
        // The theme rows on the first screen: open one.
        let theme = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'theme-companion-'")).firstMatch
        if scrollTo(theme) {
            snap("first-screen-themes")
        }
        closeSettings()
        // The profile menu.
        if isPhoneShell {
            go("inbox")
            openBrowse()
            if tapIfExists(app.buttons["browse-profile"].firstMatch) {
                pause()
                snap("profile-menu")
                dismissMenu()
            }
        }
    }

    /// The iCloud page in the engine's states (Debug's `-syncEngineDemo`), and the bolt's words on the list.
    func test07ICloudStates() throws {
        for state in ["synced", "waiting3", "checking", "purged", "update", "full12", "failed", "refused2", "signedout"] {
            walk = "icloud-\(state)"
            number = 0
            launch(seed: true, extra: ["-syncEngineDemo", state])
            snap("list-with-bolt")
            let bolt = app.buttons["syncBolt"].firstMatch
            if bolt.waitForExistence(timeout: 8) {
                bolt.tap()
                pause(1.2)
                shotDown("page")
            } else { note("no bolt in \(state)") }
            app.terminate()
        }
        // And the mirror's page as it is without iCloud (no demo state).
        walk = "icloud-mirror-off"
        number = 0
        launch(seed: true)
        snap("list")
        openSettings()
        if tapScrolling("settings-page-iCloud") { shotDown("page") }
        closeSettings()
    }

    // MARK: 5. States

    /// A new person's empty store, every list.
    func test08Empty() throws {
        walk = "empty"
        launch(seed: false)
        let screens = isPhoneShell ? ["inbox", "today", "upcoming", "flipboard"] : ["inbox", "today", "upcoming", "flipboard", "Completed"]
        for screen in screens {
            go(screen)
            snap(screen)
        }
        go("upcoming")
        chooseLayout("Week")
        snap("upcoming-week")
        chooseLayout(nil)
        if isPhoneShell {
            go("inbox")
            openBrowse()
            snap("browse")
            let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch
            if scrollTo(completed) { completed.tap(); pause(); snap("completed"); back() }
        }
        search("zebra")
        snap("search-no-results")
        // Nothing overdue: one task for today only.
        add("Water the plants today")
        go("today")
        snap("today-one-task-nothing-overdue")
    }

    /// Everything overdue: an empty store given only past tasks.
    func test09Overdue() throws {
        walk = "overdue"
        launch(seed: false)
        go("inbox")
        for line in ["Pay the plumber yesterday p1", "Return the library books 3 days ago", "Renew the parking permit last monday p2",
                     "Send the birthday card yesterday 9am", "Book the boiler service 2 weeks ago #Home"] {
            add(line)
        }
        for screen in ["inbox", "today", "upcoming"] {
            go(screen)
            snap(screen)
            toTheEnd(screen)
        }
        go("upcoming")
        chooseLayout("Week")
        snap("upcoming-week")
        let overdue = element("weekOverdue")
        if overdue.exists { overdue.tap(); pause(); snap("upcoming-week-overdue-open"); dismissPopover() }
        chooseLayout(nil)
    }

    /// A very long title and description, and a Group with a long name.
    func test10LongWords() throws {
        walk = "long"
        launch(seed: true)
        go("inbox")
        add(Self.longTitle + " today")
        openTask("Ask the landlord")
        if let field = optional(element("editorDescription")) {
            field.tap()
            pause(0.5)
            app.typeText(Self.longDescription)
            pause(0.5)
            tapIfExists(app.buttons["editorConfirm"].firstMatch)
        }
        snap("editor-long")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -400)))
        pause()
        snap("editor-long-scrolled")
        closeEditor()
        go("inbox")
        snap("inbox-long-row")
        go("today")
        snap("today-long-row")
        // A Group with a long name.
        if isPhoneShell {
            go("inbox")
            openBrowse()
            if tapIfExists(app.buttons["browseNew"].firstMatch), tapIfExists(app.buttons["New Group…"].firstMatch) {
                pause(1.2)
                app.typeText(Self.longGroup)
                pause()
                snap("new-group-long-name")
                let save = app.buttons.matching(NSPredicate(format: "label IN {'Save', 'Add', 'Done', 'Create'}")).firstMatch
                if save.exists { save.tap() } else { note("no Save on the new Group") }
                pause()
                snap("browse-with-long-group")
                let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Household")).firstMatch
                if scrollTo(group) { group.tap(); pause(); snap("group-long-name-empty"); back() }
            }
        }
        go("inbox")
        add("File the insurance letter tomorrow #Household")
        tapIfExists(app.buttons["quickAddButton"].firstMatch, timeout: 5)
        pause(1)
        app.typeText("Scan the deeds ")
        if tapIfExists(element("quickAddGroupChip")) {
            pause()
            snap("quickadd-group-picker-long")
            let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Household")).firstMatch
            if group.exists { group.tap(); pause() } else { dismissPopover() }
            snap("quickadd-group-chip-long")
        }
        tapIfExists(app.buttons["Close"].firstMatch)
        tapIfExists(element("quickAddDiscard"))
        pause()
    }

    /// Forty tasks on one day, three at one time in Week.
    func test11Crowded() throws {
        walk = "crowded"
        launch(seed: false, extra: ["-upcomingLayout", "list"])
        go("inbox")
        for i in 1...3 { add("Meeting part \(i) tomorrow 10am") }
        for i in 1...37 { add("Errand number \(i) tomorrow") }
        go("upcoming")
        snap("upcoming-list-forty")
        toTheEnd("upcoming-list-forty")
        chooseLayout("Week")
        snap("upcoming-week-forty")
        weekScroll("upcoming-week-forty")
        if tapIfExists(element("weekBandMore")) {
            pause()
            snap("upcoming-week-band-open")
        }
        chooseLayout(nil)
    }

    /// The largest and the smallest Dynamic Type sizes.
    func test12DynamicType() throws {
        for (size, name) in [("UICTContentSizeCategoryAccessibilityXXXL", "type-ax5"), ("UICTContentSizeCategoryXS", "type-xs"),
                             ("UICTContentSizeCategoryXXXL", "type-xxxl")] {
            walk = name
            number = 0
            launch(seed: true, extra: ["-UIPreferredContentSizeCategoryName", size])
            for screen in ["inbox", "today", "upcoming", "flipboard"] { go(screen); snap(screen) }
            go("today")
            openTask("Reply to Sam")
            snap("editor")
            closeEditor()
            go("inbox")
            if tapIfExists(app.buttons["quickAddButton"].firstMatch, timeout: 5) {
                pause(1)
                app.typeText("Haircut tomorrow 11am p1 #Home ")
                pause()
                snap("quickadd")
                tapIfExists(app.buttons["Close"].firstMatch)
                tapIfExists(element("quickAddDiscard"))
                pause()
            }
            if isPhoneShell { go("inbox"); openBrowse(); snap("browse") }
            openSettings()
            snap("settings")
            if tapScrolling("settings-page-general") { shotDown("settings-general"); sheetBack() }
            closeSettings()
            app.terminate()
        }
    }

    /// Other themes.
    func test13Themes() throws {
        for theme in ["rose", "nord", "moss"] {
            walk = "theme-\(theme)"
            number = 0
            launch(seed: true, extra: ["-pref.theme", theme])
            for screen in ["inbox", "today", "flipboard"] { go(screen); snap(screen) }
            go("today")
            openTask("Reply to Sam")
            snap("editor")
            closeEditor()
            openSettings()
            snap("settings")
            closeSettings()
            app.terminate()
        }
    }

    /// With the system's Reduce Motion on (set on the simulator before this walk): the lists and a card.
    func test14ReduceMotion() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_SWEEP_REDUCED"] == "1", "only with Reduce Motion set")
        walk = "reduce-motion"
        launch(seed: true)
        for screen in ["inbox", "today", "upcoming", "flipboard"] { go(screen); snap(screen) }
        go("inbox")
        if tapIfExists(app.buttons["quickAddButton"].firstMatch, timeout: 5) {
            pause(1)
            snap("quickadd")
            tapIfExists(app.buttons["Close"].firstMatch)
        }
        go("today")
        let check = app.buttons["Complete task"].firstMatch
        if check.waitForExistence(timeout: 3) { check.tap(); pause(0.4); snap("completion") }
    }

    // MARK: Walking

    private var isPhoneShell: Bool { app.buttons["tab-inbox"].exists }

    private func launch(seed: Bool, tips: Bool = false, extra: [String] = [], waitForTabs: Bool = true) {
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "r169-\(walk)-\(UUID().uuidString.prefix(6))"
        app.launchArguments = ["-disableCloudKit", "YES"]
        if !tips { app.launchArguments.append("-hideTips") }
        if seed { app.launchArguments += ["-seedDemoData", "YES", "-seedSharedTasksSample", "YES"] }
        app.launchArguments += extra
        app.launch()
        guard waitForTabs else { return }
        let ready = app.buttons["tab-inbox"].waitForExistence(timeout: 20) || app.staticTexts["Inbox"].waitForExistence(timeout: 5)
        if !ready { note("the app did not come up") }
        pause(1.5)
    }

    /// A tab on iPhone (`inbox`), a sidebar row elsewhere (`Inbox`, a Group's name).
    private func go(_ name: String) {
        let tab = app.buttons["tab-\(name)"]
        if tab.exists {
            tab.tap()
            _ = tab.wait(for: \.isSelected, toEqual: true, timeout: 5)
            if tab.isSelected { tab.tap() } // a second tap returns to the tab's first screen
            pause()
            return
        }
        showSidebar()
        let label = ["inbox": "Inbox", "today": "Today", "upcoming": "Upcoming", "flipboard": "Flipboard"][name] ?? name
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        let target = row.exists ? row : app.staticTexts[label].firstMatch
        if scrollTo(target) { target.tap() } else { note("no sidebar row \(label)") }
        pause()
    }

    private func showSidebar() {
        if app.staticTexts["Flipboard"].exists, app.staticTexts["Flipboard"].isHittable { return }
        let toggle = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@ OR identifier == %@", "Show Sidebar", "ToggleSidebar", "sidebarToggle")).firstMatch
        if toggle.exists { toggle.tap(); pause() }
    }

    /// Upcoming's layout from its menu (`nil`: the list).
    private func chooseLayout(_ name: String?) {
        let menu = element("upcomingLayout")
        guard menu.waitForExistence(timeout: 3) else { return note("no layout menu") }
        menu.tap()
        pause(0.6)
        let option: XCUIElement
        if let name {
            option = app.buttons[name].firstMatch
        } else {
            option = app.buttons.matching(NSPredicate(format: "label IN {'List', 'Board', 'Days'}")).firstMatch
        }
        if option.waitForExistence(timeout: 2) { option.tap() } else { snap("layout-menu-unknown"); dismissMenu() }
        pause(1.2)
    }

    /// Week: the hours a page down, then sideways.
    private func weekScroll(_ name: String) {
        guard element("upcomingWeek").exists else { return note("no Week") }
        // The grid opens at the present hour: drag towards the morning, where the day's timed tasks are.
        let grid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        for _ in 0..<2 { grid.press(forDuration: 0.05, thenDragTo: grid.withOffset(CGVector(dx: 0, dy: 300))); pause(0.5) }
        snap("\(name)-hours-earlier")
        grid.press(forDuration: 0.05, thenDragTo: grid.withOffset(CGVector(dx: -250, dy: 0)))
        pause()
        snap("\(name)-sideways")
    }

    private func openBrowse() {
        if tapIfExists(app.buttons["browseButton"].firstMatch, timeout: 5) { pause() }
    }

    private func openFromBrowse(_ target: XCUIElement, _ name: String) {
        guard scrollTo(target) else { return note("no \(name) in Browse") }
        target.tap()
        pause()
        snap(name)
        toTheEnd(name)
        back()
    }

    private func search(_ text: String) {
        if isPhoneShell {
            go("inbox")
            openBrowse()
        } else { showSidebar() }
        let ids = ["browseSearch", "sidebarSearch"]
        var field = app.textFields.firstMatch
        for id in ids where app.textFields[id].exists { field = app.textFields[id] }
        if !field.exists, app.searchFields.firstMatch.exists { field = app.searchFields.firstMatch }
        guard scrollTo(field) else { return note("no search field") }
        field.tap()
        if let value = field.value as? String, !value.isEmpty, !value.hasPrefix("Search") {
            if tapIfExists(app.buttons["Clear text"].firstMatch, timeout: 1) || tapIfExists(app.buttons["Clear"].firstMatch, timeout: 1) {}
            field.tap()
        }
        app.typeText(text)
        pause(1.2)
    }

    private func back() {
        let button = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if button.exists { button.tap() }
        pause()
    }

    /// Adds a task through the "+" card.
    private func add(_ line: String) {
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5), plus.isHittable else { return note("no + for \(line.prefix(20))") }
        plus.tap()
        let title = element("quickAddTitle")
        guard title.waitForExistence(timeout: 5) else { return note("no card for \(line.prefix(20))") }
        pause(0.4)
        app.typeText(line + " ")
        pause(0.4)
        app.buttons["quickAddSave"].firstMatch.tap()
        if title.waitForNonExistence(timeout: 4) { pause(0.3); return }
        // The iPad's panel stays open for the next one.
        tapIfExists(app.buttons["Close"].firstMatch, timeout: 1)
        tapIfExists(element("quickAddDiscard"), timeout: 1)
        _ = title.waitForNonExistence(timeout: 3)
        pause(0.3)
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
        if close.exists { close.tap() } else { app.typeText(XCUIKeyboardKey.escape.rawValue) }
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch, timeout: 1.5)
        _ = element("editorTitle").waitForNonExistence(timeout: 5)
        pause()
    }

    private func pickerShot(_ id: String, _ name: String) {
        let chip = element(id)
        guard scrollTo(chip, horizontal: true) else { return note("no \(id)") }
        chip.tap()
        pause(1.0)
        snap(name)
        dismissPopover()
    }

    private func dismissPopover() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.06)).tap()
        pause(0.8)
        if app.otherElements["PopoverDismissRegion"].firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            pause(0.8)
        }
    }

    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.06)).tap()
        pause(0.6)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.075)).tap()
        pause(0.4)
    }

    private func openSettings() {
        if isPhoneShell {
            go("inbox")
            openBrowse()
        } else { showSidebar() }
        let candidates = [app.buttons["settingsButton"].firstMatch, app.buttons["sidebar-settings"].firstMatch,
                          app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch]
        for button in candidates where button.waitForExistence(timeout: 2) {
            button.tap()
            if element("settings-profile").waitForExistence(timeout: 5) { pause(); return }
        }
        note("Settings did not open")
    }

    private func closeSettings() {
        tapIfExists(app.buttons["Done"].firstMatch)
        _ = element("settings-profile").waitForNonExistence(timeout: 5)
        pause()
    }

    private func sheetBack() {
        if tapIfExists(app.buttons["sheetBack"].firstMatch, timeout: 3) { pause() }
    }

    @discardableResult
    private func tapScrolling(_ id: String) -> Bool {
        let target = element(id)
        guard scrollTo(target) else { note("no \(id)"); return false }
        target.tap()
        pause()
        return true
    }

    /// Drags the screen (from its middle, never where XCUITest likes) until `target` is clear of the bars.
    @discardableResult
    private func scrollTo(_ target: XCUIElement, horizontal: Bool = false) -> Bool {
        _ = target.waitForExistence(timeout: 2)
        let top: CGFloat = 100
        let bottom = app.frame.height - 110
        for _ in 0..<8 {
            if target.exists, target.frame.minY > top, target.frame.maxY < bottom, target.isHittable { return true }
            if horizontal, target.exists, target.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let up = !target.exists || target.frame.maxY >= bottom
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -260 : 200)))
            pause(0.5)
        }
        return target.exists && target.isHittable
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func optional(_ element: XCUIElement) -> XCUIElement? {
        element.waitForExistence(timeout: 2) && element.isHittable ? element : nil
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        return true
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "note: \(walk): \(text)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("notes.txt")
        let line = "\(walk): \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Saves the screen as `<walk>-<nn>-<name>.png` in `HITLIST_SHOTS_DIR`, and attaches it.
    private func snap(_ name: String) {
        number += 1
        pause(0.4)
        let screenshot = XCUIScreen.main.screenshot()
        let file = String(format: "%@-%02d-%@", walk, number, name)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["HITLIST_SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file + ".png"))
    }

    /// Where the words on screen sit: a page that moved changes it, a companion that blinks does not.
    private func layout() -> Data {
        // The screen's left half below the bars: a page that moved changes it; the companion by the + and the bolt
        // (which blink and tick) are not in it.
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { return Data() }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: 0, y: h * 0.14, width: w * 0.55, height: h * 0.66).integral
        guard let part = cg.cropping(to: rect) else { return Data() }
        return UIImage(cgImage: part).pngData() ?? Data()
    }

    /// A list scrolled to its end (a picture only if it moved), then back to the top.
    private func toTheEnd(_ name: String) {
        var last = layout()
        var moved = false
        for _ in 0..<12 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -480)))
            pause(0.7)
            let now = layout()
            if now == last { break }
            last = now
            moved = true
        }
        if moved { snap("\(name)-end") }
        for _ in 0..<12 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 600)))
            pause(0.3)
            let now = layout()
            if now == last { break }
            last = now
        }
        pause(0.5)
    }

    /// The open page from its top to its end, a screen at a time.
    private func shotDown(_ name: String) {
        snap("\(name)-1")
        for part in 2...8 {
            let before = layout()
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -480)))
            pause(0.8)
            if layout() == before { break }
            snap("\(name)-\(part)")
        }
    }
}
