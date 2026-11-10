import XCTest
import SwiftUI
import SwiftData
@testable import HITList

/// Brief 66: the Mac toolbar's trailing pill keeps its width whatever its first control's glyph.
@MainActor
final class MacChromeTests: XCTestCase {
    #if os(macOS)
    /// Every glyph that sits in the trailing pill: the filter lines (task lists, Upcoming), the flip sound on and
    /// off (the Flipboard) and the "…". The speaker is the widest, and before brief 66 it pushed the pill out.
    static let pillGlyphs = ["line.3.horizontal.decrease", "speaker.wave.2", "speaker.slash", "ellipsis.circle"]

    func testEveryControlInTheTrailingPillTakesTheSameFrame() {
        let size = CGSize(width: ScreenControlMetrics.width, height: ScreenControlMetrics.height)
        for glyph in Self.pillGlyphs {
            let label = Label(glyph, systemImage: glyph).labelStyle(.iconOnly).screenControlFrame()
            XCTAssertEqual(NSHostingView(rootView: label).fittingSize, size, glyph)
            let menu = Menu { Button("x") {} } label: { Image(systemName: glyph) }.screenControlFrame()
            XCTAssertEqual(NSHostingView(rootView: menu).fittingSize, size, "\(glyph) as a menu")
        }
    }

    func testTheFrameHoldsTheWidestGlyphWithRoomToSpare() {
        // The speaker, the widest, at the toolbar's size, with at least 4 pt either side.
        let speaker = NSHostingView(rootView: Image(systemName: "speaker.wave.2").font(.body)).fittingSize
        XCTAssertLessThanOrEqual(speaker.width + 8, ScreenControlMetrics.width)
        XCTAssertLessThanOrEqual(speaker.height, ScreenControlMetrics.height)
    }

    /// The toolbar shrinks an item taller than its own controls (a 32 pt square came out about 25 pt), which made the
    /// width follow the glyph again; the frame stays within the toolbar's height.
    func testTheFrameIsNoTallerThanTheToolbarsControls() {
        XCTAssertLessThanOrEqual(ScreenControlMetrics.height, 24)
    }

    // MARK: - A filter's query (brief 66)

    func testAFiltersQueryReadsSearchWithRoomInsideItsCapsule() {
        let query = "(p1 | p2) & (overdue | today)"
        XCTAssertEqual(FilterQueryBadge.prefix, "Search:")
        let badge = NSHostingView(rootView: FilterQueryBadge(query: query)).fittingSize
        let bare = NSHostingView(rootView: Text(query).font(HITType.monoCaption)).fittingSize
        let prefix = NSHostingView(rootView: Text(FilterQueryBadge.prefix).font(HITType.callout)).fittingSize
        // The prefix, the query and even room either side: nothing touches the capsule's edges.
        XCTAssertGreaterThanOrEqual(badge.width, bare.width + prefix.width + 2 * FilterQueryBadge.horizontalPadding)
        XCTAssertGreaterThanOrEqual(FilterQueryBadge.horizontalPadding, 8)
    }

    // MARK: - The sidebar's top (brief 66)

    /// About 8 pt more above the profile button and between it and the search field than 0.8 had above it and
    /// between it and Inbox, with the profile's left edge still on the Settings gear's line.
    func testTheSidebarsTopHasRoomAboveAndBelowTheProfile() {
        XCTAssertEqual(ProfileButtonMetrics.top, 12)
        XCTAssertEqual(ProfileButtonMetrics.bottom, 20)
        XCTAssertEqual(SidebarView.searchBottom, 8)
        XCTAssertEqual(SidebarView.profileInset, HITSpacing.s + 2)
    }

    // MARK: - The sidebar's rows and selection are ours (brief 70, item 2)

    /// ↑ and ↓ walk the rows in the order they are drawn, and stop at either end, as the list did.
    func testArrowKeysWalkTheRowsInOrderAndStopAtTheEnds() {
        let work = SidebarItem.project(UUID()), focus = SidebarItem.filter(UUID()), bills = SidebarItem.label(UUID())
        let order: [SidebarItem] = [.inbox, .today, .upcoming, .flipboard, .completed, work, .sharedTasks, focus, bills]
        XCTAssertEqual(SidebarNavigation.item(after: .today, in: order, offset: 1), .upcoming)
        XCTAssertEqual(SidebarNavigation.item(after: .completed, in: order, offset: 1), work, "into the Groups")
        XCTAssertEqual(SidebarNavigation.item(after: work, in: order, offset: -1), .completed)
        XCTAssertEqual(SidebarNavigation.item(after: .sharedTasks, in: order, offset: 1), focus, "past the Groups' header")
        XCTAssertNil(SidebarNavigation.item(after: .inbox, in: order, offset: -1), "the first row stays")
        XCTAssertNil(SidebarNavigation.item(after: bills, in: order, offset: 1), "the last row stays")
        XCTAssertEqual(SidebarNavigation.item(after: nil, in: order, offset: 1), .inbox)
        XCTAssertEqual(SidebarNavigation.item(after: .search, in: order, offset: -1), .inbox, "from the results, the top")
    }

    /// Dropping a dragged Group or Filter above or below a row: the move `Array.move(fromOffsets:toOffset:)` makes,
    /// as `.onMove` gave it, or nothing where the row would land where it is.
    func testDroppingARowAboveOrBelowAnotherMovesItThere() {
        XCTAssertEqual(SidebarReorder.move(from: 0, onto: 2, below: true)?.to, 3, "first to below the third")
        XCTAssertEqual(SidebarReorder.move(from: 3, onto: 1, below: false)?.to, 1, "fourth to above the second")
        XCTAssertEqual(SidebarReorder.move(from: 3, onto: 1, below: false)?.from, IndexSet(integer: 3))
        XCTAssertNil(SidebarReorder.move(from: 2, onto: 2, below: true), "onto itself")
        XCTAssertNil(SidebarReorder.move(from: 2, onto: 1, below: true), "just below the row above it is where it is")
        XCTAssertNil(SidebarReorder.move(from: 2, onto: 3, below: false), "just above the row below it too")
        var names = ["Home", "Work", "Finance", "Personal"]
        guard let move = SidebarReorder.move(from: 0, onto: 2, below: true) else { return XCTFail("no move") }
        names.move(fromOffsets: move.from, toOffset: move.to)
        XCTAssertEqual(names, ["Work", "Finance", "Home", "Personal"])
    }

    /// The selected row's fill: the accent the way macOS 26.7.1 drew a focused sidebar's selection from it (Slate's
    /// #6C9EFF came out #4D79D1 in sRGB), now ours and the same whatever holds the keyboard. White text on it, or the
    /// theme's dark `onAccent` where white would not read (Graphite's off-white accent).
    func testTheSelectionFillIsTheAccentAsTheFocusedListDrewIt() {
        let fill = MacSidebarStyle.selectionFillHex(accent: "#6C9EFF")
        let rgb = { (hex: String) -> [Int] in
            let v = Int(hex.dropFirst(), radix: 16)!
            return [(v >> 16) & 255, (v >> 8) & 255, v & 255]
        }
        for (got, want) in zip(rgb(fill), rgb("#4D79D1")) { XCTAssertEqual(got, want, accuracy: 1, fill) }
        XCTAssertFalse(MacSidebarStyle.selectedTextIsDark(accent: ThemePalette.slate.hex.accent), "white on Slate's")
        XCTAssertTrue(MacSidebarStyle.selectedTextIsDark(accent: ThemePalette.graphite.hex.accent), "dark on Graphite's")
        for palette in ThemePalette.all {
            let fillHex = MacSidebarStyle.selectionFillHex(accent: palette.hex.accent)
            let text = MacSidebarStyle.selectedTextIsDark(accent: palette.hex.accent) ? palette.hex.onAccent : "#FFFFFF"
            XCTAssertGreaterThanOrEqual(Self.contrast(fillHex, text), 3, "\(palette.name): the selected title reads")
        }
    }

    /// 26.7.1's sidebar, measured: 32 pt rows whose fill sits 10 pt in from the column's edges, 13 pt symbols.
    func testTheRowsKeepTheMeasurementsOf26() {
        XCTAssertEqual(MacSidebarMetrics.rowHeight, 32)
        XCTAssertEqual(MacSidebarMetrics.rowInset, 10)
        XCTAssertEqual(MacSidebarMetrics.iconPointSize, 13)
        let row = MacSidebarRow(title: "Inbox", isSelected: true) { Image(systemName: "tray") } trailing: { MacSidebarCount(12) }
            .frame(width: 240)
        XCTAssertEqual(NSHostingView(rootView: row).fittingSize.height, 32)
    }

    /// The selected row looks the same in a key window, a background window and with the keyboard elsewhere: nothing
    /// in it reads the window's state (macOS drew a focused list's selection in accent, any other grey, bold on 27).
    func testASelectedRowIsDrawnTheSameInAKeyAndABackgroundWindow() throws {
        func render(_ state: ControlActiveState) throws -> Data {
            let row = MacSidebarRow(title: "Today", isSelected: true) {
                Image(systemName: "calendar").foregroundStyle(.red)
            } trailing: { MacSidebarCount(6) }
                .frame(width: 240)
                .background(Theme.surface)
                .environment(\.controlActiveState, state)
                .preferredColorScheme(.dark)
            let host = NSHostingView(rootView: row)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        let key = try render(.key)
        XCTAssertEqual(key, try render(.inactive), "a background window")
        XCTAssertEqual(key, try render(.active), "a key window whose keyboard is elsewhere")
    }

    private static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let v = Int(hex.dropFirst(), radix: 16)!
            return [(v >> 16) & 255, (v >> 8) & 255, v & 255].map { c -> Double in
                let s = Double(c) / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }.enumerated().map { [0.2126, 0.7152, 0.0722][$0.offset] * $0.element }.reduce(0, +)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: - Nothing takes the keyboard at launch (brief 70, item 1)

    /// On macOS 27.2 the sidebar's search field held the keyboard when the window opened (the friend's screenshot:
    /// an accent ring, the sidebar's selection drawn grey). The guard's rule, every case.
    func testTheGuardTakesBackOnlyATextViewTheSystemHandedTheKeyboard() {
        func release(_ text: Bool, guarding: Bool = true, heldAtResign: Bool = false, allowed: Bool = false) -> Bool {
            WindowFocusGuard.releases(responderIsText: text, guarding: guarding, heldAtResign: heldAtResign, allowed: allowed)
        }
        XCTAssertTrue(release(true), "a text view that takes the keyboard as the window opens or becomes key")
        XCTAssertFalse(release(false), "the sidebar, a list or the window itself may hold it")
        XCTAssertFalse(release(true, guarding: false), "after the window settles, a focus is the person's own")
        XCTAssertFalse(release(true, heldAtResign: true), "coming back to the field the person was typing in")
        XCTAssertFalse(release(true, allowed: true), "a card or editor the app opened focuses its own field")
    }

    /// The bad case as 27 draws it: the system hands the search field the keyboard as the window becomes key. The
    /// window's first responder is not a text view once the content has appeared.
    func testNoTextFieldHasTheKeyboardOnceTheWindowAppears() throws {
        let (window, host, focusGuard, _) = try sidebarWindow()
        defer { tearDown(window) }
        let field = try XCTUnwrap(textField(in: host), "the sidebar's search field")
        focusGuard.windowDidBecomeKey()
        window.makeFirstResponder(field) // what macOS 27 does by itself
        spin(0.3)
        XCTAssertFalse(window.firstResponder is NSText, "first responder: \(String(describing: window.firstResponder))")
        XCTAssertGreaterThanOrEqual(focusGuard.releases, 1)
    }

    /// The window coming back (a Dock click, ⌘Tab) or becoming key again does the same.
    func testBecomingKeyAgainDoesNotHandTheFieldTheKeyboard() throws {
        let (window, host, focusGuard, _) = try sidebarWindow()
        defer { tearDown(window) }
        let field = try XCTUnwrap(textField(in: host))
        spin(WindowFocusGuard.settleTime + 0.1)
        focusGuard.windowDidResignKey()
        focusGuard.windowDidBecomeKey()
        window.makeFirstResponder(field)
        spin(0.3)
        XCTAssertFalse(window.firstResponder is NSText)
    }

    /// ⌘F, a click and Tab still focus Search: a focus after the window has settled is kept, and so is the field the
    /// person was typing in when they left the window.
    func testADeliberateFocusKeepsTheSearchField() throws {
        let (window, host, focusGuard, search) = try sidebarWindow()
        defer { tearDown(window) }
        spin(WindowFocusGuard.settleTime + 0.1)
        search.focus() // ⌘F
        spin(0.3)
        let field = try XCTUnwrap(textField(in: host))
        XCTAssertTrue(window.firstResponder is NSText, "⌘F focuses Search (first responder: \(String(describing: window.firstResponder)))")
        XCTAssertTrue((window.firstResponder as? NSText)?.delegate === field)
        // Away and back while typing there: the field keeps the keyboard.
        focusGuard.windowDidResignKey()
        focusGuard.windowDidBecomeKey()
        spin(0.3)
        XCTAssertTrue(window.firstResponder is NSText, "coming back keeps the field the person was typing in")
        XCTAssertEqual(focusGuard.releases, 0)
    }

    /// A key pressed while the window settles (⌘F, Tab) is the person's: the guard stands aside.
    func testAKeyWhileTheWindowSettlesEndsTheGuard() throws {
        let (window, host, focusGuard, _) = try sidebarWindow()
        defer { tearDown(window) }
        focusGuard.windowDidBecomeKey()
        let tab = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, characters: "\t",
                                                 charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        focusGuard.userEvent(tab)
        window.makeFirstResponder(try XCTUnwrap(textField(in: host)))
        spin(0.3)
        XCTAssertTrue(window.firstResponder is NSText)
    }

    /// The click that brings the window forward: one outside the field the system focused takes the keyboard back
    /// before the click is handled; one in the field is the person choosing it.
    func testAClickOutsideTheFieldTakesItBackAndAClickInItKeepsIt() throws {
        let (window, host, focusGuard, _) = try sidebarWindow()
        defer { tearDown(window) }
        let field = try XCTUnwrap(textField(in: host))
        func click(at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let inField = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        let below = NSPoint(x: inField.x, y: 40)

        focusGuard.windowDidBecomeKey()
        window.makeFirstResponder(field)
        focusGuard.userEvent(try click(at: inField))
        spin(0.3)
        XCTAssertTrue(window.firstResponder is NSText, "a click in the field keeps it")

        window.makeFirstResponder(nil)
        spin(WindowFocusGuard.settleTime + 0.1)
        focusGuard.windowDidResignKey()
        focusGuard.windowDidBecomeKey()
        // As the system would, with the guard looking away: the field takes the keyboard, then a click lands below it.
        focusGuard.isDisabled = true
        window.makeFirstResponder(field)
        spin(0.1)
        focusGuard.isDisabled = false
        focusGuard.userEvent(try click(at: below))
        XCTAssertFalse(window.firstResponder is NSText, "a click elsewhere takes the field's keyboard back first")
    }

    /// A window holding the real `SidebarView` with its search field, and the window's focus guard attached the way
    /// `SplitContent` attaches it.
    private func sidebarWindow() throws -> (NSWindow, NSView, WindowFocusGuard, SidebarSearch) {
        let container = ModelContainerFactory.preview()
        let focusGuard = WindowFocusGuard()
        let search = SidebarSearch()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MacChromeFocus-\(UUID().uuidString)"))
        let root = SidebarView(selection: .constant(.today))
            .environment(\.sidebarSearch, search)
            .environment(SettingsRouter(defaults: defaults))
            .environment(PopoutController(draftDefaults: defaults))
            .environment(focusGuard)
            .windowFocusGuard(focusGuard)
            .modelContainer(container)
            .frame(width: 260, height: 500)
            .preferredColorScheme(.dark)
        let size = CGSize(width: 260, height: 500)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        spin(0.3)
        retained = container
        return (window, host, focusGuard, search)
    }

    /// The preview container outlives the window's views (a hosted `@Query` traps on a container that is gone).
    private var retained: ModelContainer?

    private func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let found = textField(in: sub) { return found } }
        return nil
    }

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
    #endif
}
