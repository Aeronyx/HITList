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
