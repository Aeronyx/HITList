import XCTest

/// Brief 114: the room inside every card that opens over a list (quick add, the editor, every picker). For an open card
/// it lists each text and control with its distance to the card's border and to its nearest neighbours, and fails
/// under the floors: text or a control 12 pt from the card's border, 6 pt between two controls, nothing cut by the
/// border. A chip row that scrolls is measured by its own frame (its fade is looked at by eye).
///
/// It runs on whatever simulator the suite runs on (the iPhone Duo's outer display and the iPhone 16 by hand). With
/// `TEST_RUNNER_HITLIST_INSETS_OUT=<folder>` it also writes each card's table and a picture of it there, named with
/// `TEST_RUNNER_HITLIST_INSETS_LABEL` ("duo-after"), and `TEST_RUNNER_HITLIST_INSETS_TEXT_SIZE` runs it at another text size:
///
///     TEST_RUNNER_HITLIST_INSETS_OUT=… TEST_RUNNER_HITLIST_INSETS_LABEL=duo-after xcodebuild test-without-building \
///       -xctestrun <the .xctestrun> -destination 'platform=iOS Simulator,id=<UDID>' \
///       -only-testing:HITListUITests/CardInsetsUITests
final class CardInsetsUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Text or a control to the card's border.
    static let borderFloor: CGFloat = 12
    /// Two neighbouring controls.
    static let neighbourFloor: CGFloat = 6
    /// Frames come back in fractions of a point: a quarter point under a floor is the floor.
    static let slack: CGFloat = 0.25

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    private var outFolder: String? { ProcessInfo.processInfo.environment["HITLIST_INSETS_OUT"] }
    private var label: String { ProcessInfo.processInfo.environment["HITLIST_INSETS_LABEL"] ?? "run" }

    // MARK: The cards

    func testQuickAddCards() throws {
        launch()
        go("inbox")
        openQuickAdd()
        app.typeText("Haircut tom 11am p1 !15mb #Home @errands ")
        pause()
        measure("quick-add", card: element("quickAddCard"))
        for (id, name) in [("quickAddDateChip", "quick-add-date"), ("quickAddPriorityChip", "quick-add-priority"),
                           ("quickAddReminderChip", "quick-add-reminder"), ("quickAddGroupChip", "quick-add-group")] {
            measureCard(opening: id, name)
        }
        // "+" → Repeat, then the repeat card and its Custom….
        let plus = element("quickAddPlus")
        if reveal(plus) {
            plus.tap()
            pause()
            let item = app.buttons["Repeat"].firstMatch
            if item.waitForExistence(timeout: 2) {
                item.tap()
                pause()
                measureCard(opening: "quickAddRepeatChip", "quick-add-repeat", keepOpen: true)
                let custom = element("repeatCustom")
                if custom.waitForExistence(timeout: 2), custom.isHittable {
                    custom.tap()
                    pause(1)
                    measure("quick-add-repeat-custom", card: openCard)
                }
                dismissPopover()
            } else {
                dismissPopover()
            }
        }
        tapIfExists(app.buttons["Close"].firstMatch)
        pause()
        if element("quickAddDiscard").exists || element("quickAddDiscardRow").exists {
            measure("quick-add-discard", card: element("quickAddCard"))
        }
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
        pause()
    }

    func testEditorCards() throws {
        launch()
        go("today")
        openTask("Reply to Sam about the lease")
        measure("editor", card: element("editorCard"))
        for (id, name) in [("popoutDateRow", "editor-date"), ("popoutPriorityChip", "editor-priority"),
                           ("popoutReminderChip", "editor-reminder"), ("popoutLabelsChip", "editor-labels"),
                           ("editorGroupRow", "editor-group")] {
            measureCard(opening: id, name)
        }
        measureCard(opening: "popoutRepeatChip", "editor-repeat", keepOpen: true)
        let custom = element("repeatCustom")
        if app.popovers.firstMatch.exists, custom.waitForExistence(timeout: 2), custom.isHittable {
            custom.tap()
            pause(1)
            measure("editor-repeat-custom", card: openCard)
        }
        dismissPopover()
        // A sub-task row, then the Discard question.
        let add = element("addSubtask")
        if reveal(add) {
            add.tap()
            pause()
            app.typeText("Find the lease\n")
            pause()
            app.typeText("Write the reply")
            pause()
            measure("editor-subtasks", card: element("editorCard"))
        }
        tapIfExists(app.buttons["Close"].firstMatch)
        pause()
        measure("editor-discard", card: element("editorCard"))
        tapIfExists(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discard")).firstMatch)
        pause()
    }

    // MARK: Measuring

    private struct Item {
        var kind: String
        var name: String
        var frame: CGRect
        /// The part of it on screen (inside every scroll view it is in).
        var visible: CGRect
        /// Inside a sideways-scrolling row: its own edges are the row's business.
        var inRow: Bool
        var isControl: Bool { kind != "text" }
    }

    /// Opens `id`'s card, measures it and closes it.
    private func measureCard(opening id: String, _ name: String, keepOpen: Bool = false) {
        let chip = element(id)
        guard reveal(chip) else {
            note("\(name): no \(id) to tap")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree \(name)"
            tree.lifetime = .keepAlways
            add(tree)
            if let outFolder {
                try? app.debugDescription.write(toFile: outFolder + "/\(label)-\(name)-tree.txt", atomically: true, encoding: .utf8)
            }
            return
        }
        chip.tap()
        pause(1.2)
        guard app.popovers.firstMatch.waitForExistence(timeout: 3) else { return note("\(name): no card opened") }
        measure(name, card: openCard)
        if !keepOpen { dismissPopover() }
    }

    /// The open picker card itself (inside its popover, whose frame takes in the arrow).
    private var openCard: XCUIElement {
        let card = element("pickerCard")
        return card.exists ? card : app.popovers.firstMatch
    }

    /// Lists every text and control in `card` with its distance to the card's four borders and its nearest neighbour,
    /// writes the table (and a picture of the card), and fails each one under the floors.
    private func measure(_ name: String, card: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard card.waitForExistence(timeout: 3), let root = try? card.snapshot() else {
            return XCTFail("\(name): no card to measure", file: file, line: line)
        }
        let bounds = root.frame
        var items: [Item] = []
        collect(root, clip: bounds, inRow: false, into: &items)
        var lines = [String(format: "%@ — card %.0f × %.0f at (%.0f, %.0f); floors %.0f to the border, %.0f between controls",
                            name, bounds.width, bounds.height, bounds.minX, bounds.minY,
                            Self.borderFloor, Self.neighbourFloor)]
        var failures: [String] = []
        // A layer over the whole card (the Discard question's "Keep editing") is not a control in it.
        // (On the Duo's outer display the editor's sheet takes in the bar column: its layer is 83% of the sheet's width.)
        items.removeAll { $0.visible.width >= bounds.width * 0.75 && $0.visible.height >= bounds.height * 0.5 }
        // A grid's cell (the calendar's day) draws its mark as the square in its middle: measured by that.
        let cells = gridCells(items)
        for item in items where item.visible.width > 0.5 && item.visible.height > 0.5 {
            let f = item.visible
            // A square icon button without a border (the editor's ×) is measured by its glyph, about 16 pt across in
            // the middle of its hit area.
            let icon = item.kind == "button" && abs(f.width - f.height) < 1 && f.width <= 36
            let side = min(f.width, f.height)
            // A list's row without a box of its own (the Group card's): its line of text, about 20 pt, in its middle.
            let listRow = item.kind == "button" && abs((f.minX - bounds.minX) - (bounds.maxX - f.maxX)) < 1
                && f.width >= bounds.width * 0.8 && f.height > 20
            let glyph = icon ? f.insetBy(dx: (f.width - 16) / 2, dy: (f.height - 16) / 2)
                : cells.contains(f) ? f.insetBy(dx: (f.width - side) / 2, dy: (f.height - side) / 2)
                : listRow ? f.insetBy(dx: 0, dy: (f.height - 20) / 2) : f
            let left = glyph.minX - bounds.minX, right = bounds.maxX - glyph.maxX
            let top = glyph.minY - bounds.minY, bottom = bounds.maxY - glyph.maxY
            var problems: [String] = []
            // A row of the card's full width on purpose (a menu's rows) keeps its text in by its own padding.
            let fullWidth = left < 1 && right < 1
            if !item.inRow && !fullWidth {
                if left < Self.borderFloor - Self.slack { problems.append(String(format: "L %.1f", left)) }
                if right < Self.borderFloor - Self.slack { problems.append(String(format: "R %.1f", right)) }
            }
            // A row the card's own list has scrolled part-way out of sight: its edge is the list's, not the card's.
            let scrolled = item.visible.height + Self.slack < item.frame.height
            if !fullWidth && !scrolled {
                if top < Self.borderFloor - Self.slack { problems.append(String(format: "T %.1f", top)) }
                if bottom < Self.borderFloor - Self.slack { problems.append(String(format: "B %.1f", bottom)) }
            }
            // A grid's cell is its mark, inside it (the calendar's first column reaches past the card's padding).
            if !item.inRow, !cells.contains(item.visible), item.visible.width + 0.5 < item.frame.width {
                problems.append("cut sideways")
            }
            var near = ""
            if item.isControl, !fullWidth, !icon, whole(item), let gap = nearestGap(item, among: items) {
                near = String(format: "  next %.1f (%@)", gap.0, gap.1)
                if gap.0 < Self.neighbourFloor - Self.slack { problems.append(String(format: "next %.1f to %@", gap.0, gap.1)) }
            }
            let row = String(format: "%@ %-6@ %-34@ L %5.1f  R %5.1f  T %5.1f  B %5.1f%@%@",
                             problems.isEmpty ? "  " : "✘ ", item.kind, "\"\(item.name.prefix(32))\"",
                             left, right, top, bottom, near, item.inRow ? "  (in a scrolling row)" : "")
            lines.append(row)
            if !problems.isEmpty { failures.append("\(item.kind) \"\(item.name)\": " + problems.joined(separator: ", ")) }
        }
        lines.append(failures.isEmpty ? "✔ every text and control is at or over the floors"
                                      : "✘ \(failures.count) under the floors")
        let table = lines.joined(separator: "\n")
        let attachment = XCTAttachment(string: table)
        attachment.name = "insets \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        write(table, picture: bounds, name: name)
        for failure in failures {
            XCTFail("\(name): \(failure)", file: file, line: line)
        }
    }

    /// Texts and controls, leaves first: a button, field or switch is one item (its label is its own business).
    private func collect(_ node: XCUIElementSnapshot, clip: CGRect, inRow: Bool, into items: inout [Item]) {
        for child in node.children {
            let frame = child.frame
            switch child.elementType {
            case .button, .textField, .secureTextField, .textView, .switch, .toggle, .slider, .stepper, .menuButton,
                 .popUpButton, .segmentedControl, .link:
                items.append(Item(kind: kind(child.elementType), name: title(child), frame: frame,
                                  visible: frame.intersection(clip), inRow: inRow))
            case .staticText:
                items.append(Item(kind: "text", name: title(child), frame: frame, visible: frame.intersection(clip),
                                  inRow: inRow))
            case .scrollView:
                // A short scroll view is a sideways row of chips: measured by its own frame.
                let sideways = frame.height < 64
                if sideways {
                    items.append(Item(kind: "row", name: title(child), frame: frame, visible: frame.intersection(clip),
                                      inRow: false))
                }
                collect(child, clip: clip.intersection(frame), inRow: inRow || sideways, into: &items)
            default:
                collect(child, clip: clip, inRow: inRow, into: &items)
            }
        }
    }

    /// All of it on screen (to a quarter point).
    private func whole(_ item: Item) -> Bool {
        item.visible.width + Self.slack >= item.frame.width && item.visible.height + Self.slack >= item.frame.height
    }

    /// Frames of seven or more same-sized buttons side by side in one row: a grid's cells.
    private func gridCells(_ items: [Item]) -> [CGRect] {
        var cells: [CGRect] = []
        let buttons = items.filter { $0.kind == "button" }
        for rowY in Set(buttons.map { $0.frame.minY.rounded() }) {
            let row = buttons.filter { $0.frame.minY.rounded() == rowY }
            guard row.count >= 7, let first = row.first,
                  row.allSatisfy({ abs($0.frame.width - first.frame.width) < 0.5 && abs($0.frame.height - first.frame.height) < 0.5 })
            else { continue }
            cells += row.map(\.visible)
        }
        return cells
    }

    /// The nearest other control beside it in its row or above or below it in its column.
    private func nearestGap(_ item: Item, among items: [Item]) -> (CGFloat, String)? {
        var best: (CGFloat, String)?
        let a = item.visible
        for other in items where other.isControl && other.kind != "row" && item.kind != "row" && whole(other) {
            let b = other.visible
            guard b != a, b.width > 0.5, b.height > 0.5, !b.contains(a), !a.contains(b) else { continue }
            // A grid's cells (the calendar's days) abut by design: each draws its mark inside its own cell.
            if abs(a.width - b.width) < 0.5, abs(a.height - b.height) < 0.5,
               abs(a.minY - b.minY) < 0.5 || abs(a.minX - b.minX) < 0.5,
               abs(max(b.minX - a.maxX, a.minX - b.maxX)) < 0.5 || abs(max(b.minY - a.maxY, a.minY - b.maxY)) < 0.5 {
                continue
            }
            let rowOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
            let columnOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
            var gap: CGFloat?
            if rowOverlap > 4 { gap = max(b.minX - a.maxX, a.minX - b.maxX) }
            else if columnOverlap > 4 {
                // Rows of one list (the editor's Group and date rows) are one control, a hairline apart.
                if abs(a.minX - b.minX) < 0.5, abs(a.width - b.width) < 0.5 { continue }
                gap = max(b.minY - a.maxY, a.minY - b.maxY)
            }
            // Parts of one control (a segmented control's segments, a stepper's − field +) touch: one control, not two.
            // Overlaps are a layer above another (the Discard bubble over a field).
            guard let gap, gap > 2.5, best == nil || gap < best!.0 else { continue }
            best = (gap, String(other.name.prefix(24)))
        }
        return best
    }

    private func kind(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button, .menuButton, .popUpButton, .link: "button"
        case .textField, .secureTextField, .textView: "field"
        case .switch, .toggle: "switch"
        default: "control"
        }
    }

    private func title(_ node: XCUIElementSnapshot) -> String {
        let text = node.label.isEmpty ? (node.value as? String ?? "") : node.label
        return text.isEmpty ? node.identifier : text
    }

    /// The table and a picture of the card with 24 pt around it, at the screen's own scale.
    private func write(_ table: String, picture rect: CGRect, name: String) {
        guard let outFolder else { return }
        let folder = URL(fileURLWithPath: outFolder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? table.write(to: folder.appendingPathComponent("\(label)-\(name).txt"), atomically: true, encoding: .utf8)
        let shot = XCUIScreen.main.screenshot()
        let image = shot.image
        guard let cg = image.cgImage else { return }
        let scale = image.scale
        let around = rect.insetBy(dx: -24, dy: -24)
        let pixels = CGRect(x: around.minX * scale, y: around.minY * scale,
                            width: around.width * scale, height: around.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        if let crop = cg.cropping(to: pixels), let png = UIImage(cgImage: crop, scale: scale, orientation: .up).pngData() {
            try? png.write(to: folder.appendingPathComponent("\(label)-\(name).png"))
        }
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(label)-\(name)-screen.png"))
    }

    // MARK: Helpers

    private func launch() {
        app.launchEnvironment["HITLIST_STORE_SUFFIX"] = "s114-\(UUID().uuidString.prefix(8))"
        app.launchArguments = ["-disableCloudKit", "YES", "-hideTips", "-seedDemoData", "YES",
                               "-seedSharedTasksSample", "YES"]
        // A larger text size, where a tight chip gets worse first: TEST_RUNNER_HITLIST_INSETS_TEXT_SIZE=
        // UICTContentSizeCategoryXL.
        if let size = ProcessInfo.processInfo.environment["HITLIST_INSETS_TEXT_SIZE"] {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        XCTAssertTrue(app.buttons["tab-inbox"].waitForExistence(timeout: 30), "the app is up")
        pause(1.5)
    }

    private func go(_ name: String) {
        let tab = app.buttons["tab-\(name)"]
        guard tab.waitForExistence(timeout: 5) else { return note("no tab \(name)") }
        tab.tap()
        _ = tab.wait(for: \.isSelected, toEqual: true, timeout: 5)
        pause()
    }

    private func openQuickAdd() {
        let plus = app.buttons["quickAddButton"].firstMatch
        guard plus.waitForExistence(timeout: 5) else { return note("no +") }
        plus.tap()
        let title = element("quickAddTitle")
        _ = title.waitForExistence(timeout: 5)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 4), title.exists { title.tap() }
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        pause(0.8)
    }

    private func openTask(_ prefix: String) {
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard row.waitForExistence(timeout: 5) else { return note("no row \(prefix)") }
        for _ in 0..<6 where !row.isHittable { app.swipeUp(); pause(0.5) }
        row.tap()
        if !element("editorTitle").waitForExistence(timeout: 5) { note("no editor for \(prefix)") }
        pause()
    }

    /// The chip on screen and tappable: a chip at the far end of a scrolling row is brought in first.
    @discardableResult
    private func reveal(_ chip: XCUIElement) -> Bool {
        guard chip.waitForExistence(timeout: 3) else { return false }
        if !chip.isHittable {
            for row in ["editorPills", "quickAddOptionBar"] where element(row).exists {
                element(row).swipeLeft()
                pause(0.5)
            }
        }
        if !chip.isHittable { app.swipeUp(); pause(0.5) }
        return chip.isHittable
    }

    /// A tap just outside the open card, which its dismissal layer takes.
    private func dismissPopover() {
        let popover = app.popovers.firstMatch
        if popover.exists {
            let card = popover.frame
            let y = card.minY > 90 ? card.minY - 30 : min(card.maxY + 30, app.frame.height - 40)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: card.midX, dy: y)).tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
        }
        pause(0.8)
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
}
