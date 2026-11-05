import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// The Upcoming board's inline add card (brief 39): one card per day column, one open across the board,
/// Confirm keeps it open for the next task, a click away closes an empty card and asks before losing
/// typing; and (Mac) every quick-add card has the keyboard the moment it appears.
@MainActor
final class CompactQuickAddTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int, hour: Int = 0) -> Date {
        cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: today)!)!
    }

    // MARK: - One card per day, one at a time

    func testEachDayHasItsOwnCardKey() {
        XCTAssertEqual(BoardInlineAdd.key(for: day(2), calendar: cal), BoardInlineAdd.key(for: day(2, hour: 15), calendar: cal),
                       "the time of day doesn't matter")
        XCTAssertNotEqual(BoardInlineAdd.key(for: day(2), calendar: cal), BoardInlineAdd.key(for: day(3), calendar: cal))
        XCTAssertTrue(BoardInlineAdd.isBoardKey(BoardInlineAdd.key(for: day(0), calendar: cal)))
        XCTAssertFalse(BoardInlineAdd.isBoardKey("upcoming-day"), "a list's Add task row is not the board's")
    }

    func testOneInlineCardAtATimeAcrossTheBoard() {
        var state = PopoutState()
        let monday = BoardInlineAdd.key(for: day(1), calendar: cal)
        let tuesday = BoardInlineAdd.key(for: day(2), calendar: cal)
        state.openQuickAdd(.day(day(1)), placement: .inline(monday))
        XCTAssertEqual(BoardInlineAdd.openKey(in: state), monday)
        state.openQuickAdd(.day(day(2)), placement: .inline(tuesday))
        XCTAssertFalse(state.isInlineOpen(monday), "opening another day's card closes the first")
        XCTAssertEqual(BoardInlineAdd.openKey(in: state), tuesday)
        state.openQuickAdd(.upcoming)
        XCTAssertNil(BoardInlineAdd.openKey(in: state), "the floating card (⌘N, the toolbar +) is not a board card")
        state.openQuickAdd(.inbox, placement: .inline("inbox"))
        XCTAssertNil(BoardInlineAdd.openKey(in: state), "nor is a list's inline row")
    }

    func testConfirmKeepsTheCardOpenForTheNextTask() {
        var state = PopoutState()
        let key = BoardInlineAdd.key(for: day(3), calendar: cal)
        state.openQuickAdd(.day(day(3)), placement: .inline(key))
        let card = state.quickAdd?.id
        state.didSave()
        state.didSave()
        XCTAssertTrue(state.isInlineOpen(key))
        XCTAssertEqual(state.quickAdd?.id, card, "the same card, emptied for the next task")
        XCTAssertEqual(state.quickAdd?.savedCount, 2)
        state.closeInline(key)
        XCTAssertNil(state.quickAdd, "Escape or × closes it")
    }

    // MARK: - Click away

    func testAClickAwayClosesAnEmptyCardAndAsksBeforeLosingTyping() {
        XCTAssertEqual(BoardInlineAdd.clickAway(hasContent: false, confirmingDiscard: false), .close)
        XCTAssertEqual(BoardInlineAdd.clickAway(hasContent: true, confirmingDiscard: false), .askDiscard)
        XCTAssertEqual(BoardInlineAdd.clickAway(hasContent: true, confirmingDiscard: true), .keepEditing,
                       "with Discard showing, a click elsewhere goes back to typing (only Discard throws it away)")
    }

    /// × and Escape (supervisor, from session 41): an empty card closes at once; with typing they ask Discard
    /// first, like the iPhone card, and a second × or Escape while Discard shows throws the typing away.
    func testCloseAsksBeforeLosingTyping() {
        XCTAssertEqual(BoardInlineAdd.close(hasContent: false, confirmingDiscard: false), .close)
        XCTAssertEqual(BoardInlineAdd.close(hasContent: true, confirmingDiscard: false), .askDiscard)
        XCTAssertEqual(BoardInlineAdd.close(hasContent: true, confirmingDiscard: true), .discard)
    }

    // MARK: - The day chip's ×

    func testTheDayChipsCrossLeavesTheTaskUndated() {
        let parser = QuickAddParser(now: Date(), calendar: cal)
        var draft = QuickAddDraft(context: .day(day(4)), text: "Call Sam 3pm")
        XCTAssertEqual(draft.result(parser).dueDate, cal.date(bySettingHour: 15, minute: 0, second: 0, of: day(4)))
        draft.setDate(nil, parser)
        let result = draft.result(parser)
        XCTAssertNil(result.dueDate, "× on the day chip: no date, not the column's day")
        XCTAssertEqual(result.title, "Call Sam")
    }

    // MARK: - Layout

    /// The card fits its column: as wide as the column inside its padding, the chips wrapping onto more
    /// lines rather than running off the side.
    func testTheCardFitsTheColumn() {
        XCTAssertLessThan(CompactQuickAddCard.padding, QuickAddPopout.padding)
        let width = UpcomingBoard.cardWidth
        XCTAssertEqual(width, UpcomingBoard.columnWidth - 2 * 4 - 2 * 2, "the column's padding and the cards' inset")
        // Five chips at their compact sizes (about +, Today ×, Priority, Reminders, Inbox) don't fit one line.
        let chips = [CGSize(width: 30, height: 26), CGSize(width: 82, height: 26), CGSize(width: 76, height: 26),
                     CGSize(width: 96, height: 26), CGSize(width: 66, height: 26)]
        let laid = HITFlowLayout.arrange(chips, maxWidth: width - 2 * CompactQuickAddCard.padding, spacing: 6, lineSpacing: 6)
        XCTAssertEqual(Set(laid.frames.map(\.minY)).count, 2, "two lines")
        XCTAssertLessThanOrEqual(laid.size.width, width - 2 * CompactQuickAddCard.padding)
    }

    // MARK: - Discard inside the card (brief 49)

    private func renderedHeight<V: View>(_ view: V, container: ModelContainer) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: UpcomingBoard.cardWidth)
            .environment(PopoutController(draftDefaults: UserDefaults(suiteName: "CompactQuickAddRender-\(UUID().uuidString)")!))
            .modelContainer(container).preferredColorScheme(.dark))
        renderer.scale = 1
        return CGFloat(renderer.cgImage?.height ?? 0)
    }

    /// The question is the card's own foot: the card grows by exactly the row (nothing floats above it).
    func testTheCardAsksInsideItselfAndGrowsToFit() {
        let container = ModelContainerFactory.preview()
        let plain = renderedHeight(CompactQuickAddCard(context: .day(today), onClose: {}), container: container)
        let asking = renderedHeight(CompactQuickAddCard(context: .day(today), isConfirmingDiscard: true, onClose: {}), container: container)
        let row = renderedHeight(InlineDiscardRow(padding: CompactQuickAddCard.padding, onKeepEditing: {}, onDiscard: {}), container: container)
        XCTAssertGreaterThan(plain, 0)
        XCTAssertGreaterThan(row, 40, "the question over its two buttons in the 270 pt column")
        XCTAssertEqual(asking, plain + row, accuracy: 1, "the card grows by the row and by nothing else")
        XCTAssertEqual(InlineDiscardRow.question, "Discard this task?")
    }

    // MARK: - Focus at once (Mac)

    #if os(macOS)
    /// A window with `root` in it, key, on screen but out of sight; the run loop turns for `seconds`.
    private func keyWindow<V: View>(_ root: V, size: CGSize = CGSize(width: 900, height: 600)) -> (NSWindow, NSHostingView<V>) {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        spin(0.3)
        return (window, host)
    }

    /// Takes the SwiftUI views down while their model container is still alive (a hosted `@Query` left behind
    /// trapped in a later test's save), then closes the window.
    private func tearDown(_ window: NSWindow) {
        window.contentView = nil
        spin(0.05)
        window.orderOut(nil)
        window.close()
    }

    private func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// A left click at `point` (top-left origin, in `host`), as the mouse sends it.
    private func click(_ window: NSWindow, _ host: NSView, at point: CGPoint) {
        let local = host.isFlipped ? point : CGPoint(x: point.x, y: host.bounds.height - point.y)
        let location = host.convert(local, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                           pressure: type == .leftMouseDown ? 1 : 0)!
            window.sendEvent(event)
            spin(0.05)
        }
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for sub in view.subviews { if let found = textView(in: sub) { return found } }
        return nil
    }

    /// The window's own text view (the title) is first responder: typing goes into the card.
    private func assertTitleHasKeyboard(_ window: NSWindow, _ host: NSView, _ what: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        guard let field = textView(in: host) else { return XCTFail("\(what): no title field", file: file, line: line) }
        XCTAssertTrue(window.firstResponder === field, "\(what): the title has the keyboard without a click "
                      + "(first responder: \(String(describing: window.firstResponder)))", file: file, line: line)
    }

    /// A day's "+ Add task" clicked on a board already on screen: the card that replaces the row has the
    /// keyboard, with no click in it.
    func testTheBoardCardHasTheKeyboardAtOnce() throws {
        let container = ModelContainerFactory.preview()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CompactQuickAddFocus-\(UUID().uuidString)"))
        let popouts = PopoutController(draftDefaults: defaults)
        let board = UpcomingBoardModel<UpcomingView.Entry>(items: [], window: UpcomingWindow(), now: Date(), showOverdue: false, calendar: cal)
        let (window, host) = keyWindow(UpcomingBoard(board: board, window: .constant(UpcomingWindow()), now: Date())
            .environment(popouts).modelContainer(container).preferredColorScheme(.dark))
        defer { tearDown(window) }
        XCTAssertNil(textView(in: host), "no card yet")
        // A real click on today's "+ Add task" (the first column's foot: the board is empty).
        click(window, host, at: CGPoint(x: 70, y: 103))
        spin(0.6)
        XCTAssertEqual(BoardInlineAdd.openKey(in: popouts.state), BoardInlineAdd.key(for: today, calendar: cal),
                       "the click opened today's card")
        assertTitleHasKeyboard(window, host, "board card")
    }

    /// A card that is already open when its view comes to the screen (a board column scrolled back into view, a
    /// window opened with a card up, the card reopened at launch) asks for the keyboard as it appears; the Mac
    /// dropped that request (eight times out of eight here) until the card asked again once it was in place.
    func testACardAppearingWithItsWindowHasTheKeyboardEveryTime() throws {
        let container = ModelContainerFactory.preview()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CompactQuickAddFocus-\(UUID().uuidString)"))
        var missed: [Int] = []
        for attempt in 0..<8 {
            let popouts = PopoutController(draftDefaults: defaults)
            popouts.openQuickAdd(.day(today), placement: .inline(BoardInlineAdd.key(for: today, calendar: cal)))
            let root = CompactQuickAddCard(context: .day(today), onClose: {})
                .frame(width: UpcomingBoard.cardWidth)
                .environment(popouts).modelContainer(container).preferredColorScheme(.dark)
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 260), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.makeKeyAndOrderFront(nil)
            spin(0.6)
            if let field = textView(in: window.contentView!), window.firstResponder === field {} else { missed.append(attempt) }
            popouts.closeAll()
            tearDown(window)
        }
        XCTAssertEqual(missed, [], "the title had the keyboard every time")
    }

    /// Escape on the board's card, as the keyboard sends it: with typing it asks Discard and the card stays;
    /// Escape again discards; an empty card closes at once.
    func testEscapeAsksDiscardOverTypingOnTheBoard() throws {
        let container = ModelContainerFactory.preview()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CompactQuickAddFocus-\(UUID().uuidString)"))
        let popouts = PopoutController(draftDefaults: defaults)
        let key = BoardInlineAdd.key(for: today, calendar: cal)
        popouts.openQuickAdd(.day(today), placement: .inline(key))
        let card = try XCTUnwrap(popouts.state.quickAdd?.id)
        QuickAddDraftStore.save(QuickAddDraft(context: .day(today), text: "Call Sam"), card: card, to: defaults)
        let board = UpcomingBoardModel<UpcomingView.Entry>(items: [], window: UpcomingWindow(), now: Date(), showOverdue: false, calendar: cal)
        let (window, host) = keyWindow(UpcomingBoard(board: board, window: .constant(UpcomingWindow()), now: Date())
            .environment(popouts).modelContainer(container).preferredColorScheme(.dark))
        defer { popouts.closeAll(); tearDown(window) }
        spin(0.4)
        XCTAssertEqual(textView(in: host)?.string, "Call Sam")

        escape(window)
        XCTAssertTrue(popouts.state.isInlineOpen(key), "typing: Escape asks first, the card stays")
        XCTAssertEqual(QuickAddDraftStore.draft(for: card, from: defaults)?.text, "Call Sam", "and so does the typing")
        escape(window)
        XCTAssertNil(popouts.state.quickAdd, "Escape again discards")
        XCTAssertNil(QuickAddDraftStore.draft(for: card, from: defaults))

        popouts.openQuickAdd(.day(today), placement: .inline(key))
        spin(0.4)
        escape(window)
        XCTAssertNil(popouts.state.quickAdd, "an empty card closes at once")
    }

    /// A list's inline "Add task" card (round 10's open item): × and Escape now ask before losing typing, inside
    /// the card, and again discard; an empty card still closes at once.
    func testEscapeAsksDiscardOverTypingInAListsAddRow() throws {
        let container = ModelContainerFactory.preview()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CompactQuickAddFocus-\(UUID().uuidString)"))
        let popouts = PopoutController(draftDefaults: defaults)
        let key = "list-row-test"
        popouts.openQuickAdd(.today, placement: .inline(key))
        let card = try XCTUnwrap(popouts.state.quickAdd?.id)
        QuickAddDraftStore.save(QuickAddDraft(context: .today, text: "Call Sam"), card: card, to: defaults)
        let (window, host) = keyWindow(List { InlineAddRow(context: .today, key: key) }
            .environment(popouts).modelContainer(container).preferredColorScheme(.dark))
        defer { popouts.closeAll(); tearDown(window) }
        spin(0.4)
        XCTAssertEqual(textView(in: host)?.string, "Call Sam")

        escape(window)
        XCTAssertTrue(popouts.state.isInlineOpen(key), "typing: Escape asks first, the card stays")
        XCTAssertEqual(QuickAddDraftStore.draft(for: card, from: defaults)?.text, "Call Sam", "and so does the typing")
        escape(window)
        XCTAssertNil(popouts.state.quickAdd, "Escape again discards")
        XCTAssertNil(QuickAddDraftStore.draft(for: card, from: defaults))

        popouts.openQuickAdd(.today, placement: .inline(key))
        spin(0.4)
        escape(window)
        XCTAssertNil(popouts.state.quickAdd, "an empty card closes at once")
    }

    private func escape(_ window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            if type == .keyDown, !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
            else if type == .keyUp { window.sendEvent(event) }
        }
        spin(0.4)
    }

    /// The toolbar "+" and ⌘N: the panel (`PopoutHost`) over the window as the app has it, a split view with
    /// the sidebar's list holding the keyboard (it does after a click on a sidebar row).
    func testThePanelHasTheKeyboardAtOnce() throws {
        let container = ModelContainerFactory.preview()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CompactQuickAddFocus-\(UUID().uuidString)"))
        let popouts = PopoutController(draftDefaults: defaults)
        let split = FocusSplit()
        let (window, host) = keyWindow(split.popoutHost(popouts).environment(popouts).modelContainer(container)
            .preferredColorScheme(.dark))
        defer { popouts.closeAll(); tearDown(window) }
        func table(in view: NSView) -> NSTableView? {
            if let t = view as? NSTableView { return t }
            for sub in view.subviews { if let found = table(in: sub) { return found } }
            return nil
        }
        let sidebar = try XCTUnwrap(table(in: host))
        window.makeFirstResponder(sidebar)
        spin(0.2)
        XCTAssertTrue(window.firstResponder === sidebar)
        popouts.openQuickAdd(.today)
        spin(0.6)
        assertTitleHasKeyboard(window, host, "panel")
    }
    #endif
}

#if os(macOS)
/// The app window's shape for the focus test: a sidebar list with a selection beside a detail list.
private struct FocusSplit: View {
    @State private var item: String? = "Today"
    @State private var row: String?
    var body: some View {
        NavigationSplitView {
            List(["Inbox", "Today", "Upcoming"], id: \.self, selection: $item) { Text($0) }
        } detail: {
            List(["A task", "Another"], id: \.self, selection: $row) { Text($0) }
        }
    }
}
#endif
