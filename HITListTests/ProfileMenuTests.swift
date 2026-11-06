import XCTest
import SwiftUI
import SwiftData
@testable import HITList
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The account button at the top of the Mac and iPad sidebar (brief 40): its words, the dropdown's rows,
/// the iCloud line, and opening the Mac Settings page at Account through `SettingsRouter`. On the Mac,
/// the real sidebar is rendered offscreen to PNGs (no session can see the Mac's screen), and mouse-downs and
/// Escape are sent through the app to check the card closes. (A synthetic click can't press a SwiftUI
/// button here: the test app is never the active app, so its windows never become key.)
@MainActor
final class ProfileMenuTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "ProfileMenuTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Words

    func testButtonShowsTheNameOrAddYourName() {
        XCTAssertEqual(ProfileMenuModel.title(forName: "George Trammell"), "George Trammell")
        XCTAssertEqual(ProfileMenuModel.title(forName: "  George  "), "George", "trimmed")
        XCTAssertEqual(ProfileMenuModel.title(forName: nil), "Add your name", "no profile yet")
        XCTAssertEqual(ProfileMenuModel.title(forName: ""), "Add your name")
        XCTAssertEqual(ProfileMenuModel.title(forName: " \n "), "Add your name")
        XCTAssertNil(ProfileMenuModel.displayName("   "))
    }

    func testAvatarIsTodoistSized() {
        XCTAssertEqual(ProfileMenuModel.avatarSize, 24)
    }

    func testMenuRowsInOrder() {
        XCTAssertEqual(ProfileMenuModel.items(for: .sidebar),
                       [.accountSettings, .settings, .divider, .whatsNew, .feedback, .divider, .iCloud, .version])
        XCTAssertEqual(ProfileMenuModel.accountSettingsTitle, "Account settings…")
        XCTAssertEqual(ProfileMenuModel.settingsTitle, "Settings…")
        XCTAssertEqual(ProfileMenuModel.whatsNewTitle, "What's New")
        XCTAssertEqual(ProfileMenuModel.feedbackTitle, "Send Beta Feedback…")
    }

    /// iPhone Browse's menu leaves out Settings…: Browse's own gear sits beside the button.
    func testBrowseMenuHasNoSettingsRow() {
        XCTAssertEqual(ProfileMenuModel.items(for: .browse),
                       [.accountSettings, .divider, .whatsNew, .feedback, .divider, .iCloud, .version])
    }

    func testMenuPlacementPerPlatform() {
        #if os(macOS)
        XCTAssertEqual(ProfileMenuModel.Placement.current, .sidebar)
        #else
        let expected: ProfileMenuModel.Placement = UIDevice.current.userInterfaceIdiom == .phone ? .browse : .sidebar
        XCTAssertEqual(ProfileMenuModel.Placement.current, expected)
        #endif
    }

    func testEveryMenuEndsWithTheVersion() {
        for placement in [ProfileMenuModel.Placement.sidebar, .browse] {
            let items = ProfileMenuModel.items(for: placement)
            XCTAssertEqual(items.last, .version, "the quiet version line at the foot")
            XCTAssertEqual(items.first, .accountSettings)
            XCTAssertEqual(items.filter { $0 == .whatsNew }.count, 1)
            XCTAssertEqual(items.filter { $0 == .feedback }.count, 1)
            XCTAssertEqual(items[items.count - 2], .iCloud, "the iCloud line just above it")
        }
    }

    func testVersionLine() {
        XCTAssertEqual(ProfileMenuModel.versionLine("0.7.0 (17)"), "HITList 0.7.0 (17)")
        XCTAssertEqual(ProfileMenuModel.versionLine(), "HITList \(AppInfo.versionLabel)")
        XCTAssertEqual(ProfileMenuModel.versionAccessibilityLabel(version: "0.7.0", build: "17"),
                       "HITList version 0.7.0, build 17")
    }

    // MARK: What's New

    private let sampleEntries = [
        WhatsNew.Entry(version: "0.7.0", items: ["New one", "New two"]),
        WhatsNew.Entry(version: "0.6.0", items: ["Older"]),
        WhatsNew.Entry(version: "0.5.0", items: ["Oldest"]),
    ]

    func testWhatsNewShowsTheNewestThenEarlierVersions() {
        XCTAssertEqual(WhatsNewPopoutModel.current(sampleEntries)?.version, "0.7.0")
        XCTAssertEqual(WhatsNewPopoutModel.earlier(sampleEntries).map(\.version), ["0.6.0", "0.5.0"])
        XCTAssertNil(WhatsNewPopoutModel.current([]))
        XCTAssertEqual(WhatsNewPopoutModel.earlier([]), [])
        XCTAssertEqual(WhatsNewPopoutModel.versionTitle(sampleEntries[0]), "Version 0.7.0")
        XCTAssertEqual(WhatsNewPopoutModel.title, "What's New")
        XCTAssertEqual(WhatsNewPopoutModel.earlierTitle, "Earlier versions")
    }

    /// The popout reads the supervisor's list as it is: the newest entry is the one Settings → About shows.
    func testWhatsNewReadsTheRealList() {
        XCTAssertEqual(WhatsNewPopoutModel.current(WhatsNew.entries), WhatsNew.current)
        XCTAssertEqual(WhatsNewPopoutModel.earlier(WhatsNew.entries).count, WhatsNew.entries.count - 1)
    }

    func testWhatsNewRendersCollapsedAndExpanded() {
        for expanded in [false, true] {
            let view = WhatsNewPopout(showsEarlier: expanded, onDone: {})
                .frame(width: WhatsNewPopoutModel.width, height: WhatsNewPopoutModel.maxHeight)
                .preferredColorScheme(.dark)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage, expanded ? "expanded" : "collapsed")
        }
    }

    func testICloudLineUsesTheAccountScreensWords() {
        let states: [AccountState] = [.checking, .signedIn, .switched, .signedOut, .neverSignedIn, .restricted,
                                      .needsSignInAgain, .couldNotDetermine, .localOnly("test")]
        for state in states {
            XCTAssertEqual(ProfileMenuModel.iCloudLine(state), state.title, "same words as Settings → Account")
        }
        XCTAssertEqual(ProfileMenuModel.iCloudLine(.signedIn), "iCloud: Signed in")
        XCTAssertEqual(ProfileMenuModel.iCloudLine(.neverSignedIn), "iCloud: Not signed in")
    }

    func testAccessibilityLabelNamesTheAccount() {
        XCTAssertEqual(ProfileMenuModel.accessibilityLabel(forName: "George"), "Account: George")
        XCTAssertEqual(ProfileMenuModel.accessibilityLabel(forName: nil), "Account: Add your name")
    }

    // MARK: SettingsRouter

    func testOpeningAtASectionRemembersItThenOpens() {
        MacSettingsSection.save(.about, to: defaults)
        let router = SettingsRouter(defaults: defaults)
        router.open(at: .account)
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .account, "the page reads the remembered section")
        XCTAssertEqual(router.openRequests, 1)
    }

    func testPlainOpenKeepsTheRememberedSection() {
        MacSettingsSection.save(.appearance, to: defaults)
        let router = SettingsRouter(defaults: defaults)
        router.open()
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .appearance, "Settings… opens where you left it")
        XCTAssertEqual(router.openRequests, 1)
    }

    // MARK: Rendering

    func testCardRendersForEveryState() {
        let states: [AccountState] = [.checking, .signedIn, .signedOut, .neverSignedIn, .localOnly("test")]
        for state in states {
            for placement in [ProfileMenuModel.Placement.sidebar, .browse] {
                let view = ProfileMenuCard(state: state, placement: placement).frame(width: 240).preferredColorScheme(.dark)
                XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(state.title) didn't render")
            }
        }
    }

    func testButtonLabelRendersWithAndWithoutAName() {
        for name in [nil, "George Trammell"] as [String?] {
            let view = ProfileButtonLabel(imageData: nil, name: name).preferredColorScheme(.dark)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    #if os(macOS)
    // MARK: Mac sidebar, offscreen

    private func makeContainer(name: String?) throws -> ModelContainer {
        let container = ModelContainerFactory.preview()
        if let name {
            try ProfileStore(context: container.mainContext).setName(name)
        }
        return container
    }

    private let sidebarSize = CGSize(width: 260, height: 300)

    /// A window holding the real `SidebarView`, laid out and drawn once.
    private func sidebarWindow(container: ModelContainer, router: SettingsRouter, menuOpen: Bool,
                               selection: Binding<SidebarItem?> = .constant(.today)) -> (NSWindow, NSHostingView<AnyView>) {
        let root = AnyView(
            SidebarView(selection: selection, profileMenuStartsOpen: menuOpen)
                .frame(width: sidebarSize.width, height: sidebarSize.height)
                .environment(router)
                .environment(PopoutController())
                .modelContainer(container)
                .environment(\.profileMenuAllowsGlass, false)
                .preferredColorScheme(.dark)
        )
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: sidebarSize), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: sidebarSize)
        window.contentView = host
        settle()
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private func settle(_ seconds: TimeInterval = 0.5) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    @discardableResult
    private func writePNG(_ host: NSView, named name: String) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("PROFILE_MENU_PNG \(url.path)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return rep
    }

    func testSidebarTopRendersWithAndWithoutAName() throws {
        for (name, file) in [("George Trammell", "sidebar-top-named"), (nil, "sidebar-top-unnamed")] as [(String?, String)] {
            let (window, host) = sidebarWindow(container: try makeContainer(name: name),
                                               router: SettingsRouter(defaults: defaults), menuOpen: false)
            defer { window.close() }
            try writePNG(host, named: file)
        }
    }

    func testSidebarTopRendersWithTheMenuOpen() throws {
        let (window, host) = sidebarWindow(container: try makeContainer(name: "George Trammell"),
                                           router: SettingsRouter(defaults: defaults), menuOpen: true)
        defer { window.close() }
        let rep = try writePNG(host, named: "sidebar-menu-open")
        // The card is drawn over the list: its elevated fill differs from the sidebar's surface where
        // the card's middle is.
        let point = ProfileMenuTests.cardPoint(row: 1)
        let card = try XCTUnwrap(rep.colorAt(x: Int(point.x * rep.size.width.ratio(rep.pixelsWide)),
                                             y: Int(point.y * rep.size.height.ratio(rep.pixelsHigh))))
        let corner = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide - 2, y: rep.pixelsHigh - 2))
        XCTAssertNotEqual(card, corner, "the open card drew over the sidebar")
    }

    /// A point inside the open card's row `row` (0 = Account settings…, 1 = Settings…), in the host's
    /// top-left coordinates.
    static func cardPoint(row: Int) -> CGPoint {
        CGPoint(x: SidebarView.profileInset + 60, y: cardContentTop + 14 + CGFloat(row) * 28)
    }

    /// The top of the card's first row.
    static var cardContentTop: CGFloat {
        ProfileButtonMetrics.top + ProfileButtonMetrics.height + ProfileMenuModel.cardGap + HITSpacing.xs
    }

    /// The quiet version line at the card's foot: five 28 pt rows, the iCloud line and two 9 pt hairlines above it.
    static var versionPoint: CGPoint {
        CGPoint(x: SidebarView.profileInset + 60, y: cardContentTop + 5 * 28 + 2 * 9 + 8)
    }

    /// The click goes to SwiftUI's hosting view, not to the sidebar list drawn under the card.
    func testTheOpenCardIsOverTheList() throws {
        let (window, host) = sidebarWindow(container: try makeContainer(name: "George"),
                                           router: SettingsRouter(defaults: defaults), menuOpen: true)
        defer { window.close() }
        for row in [0, 1] {
            let p = Self.cardPoint(row: row)
            let hit = host.hitTest(NSPoint(x: p.x, y: host.bounds.height - p.y))
            XCTAssertTrue(hit === host, "row \(row) is hit-tested to \(String(describing: hit)), not the card")
        }
    }

    /// Whether the card is drawn: a point inside it (right of the rows' words) differs from the sidebar
    /// just right of the card.
    private func cardIsShowing(_ host: NSView) throws -> Bool {
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        let y = Int(Self.cardPoint(row: 1).y * scale)
        let inside = try XCTUnwrap(rep.colorAt(x: Int((SidebarView.profileInset + 220) * scale), y: y))
        let outside = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide - 2, y: y))
        return inside != outside
    }

    /// Sends a mouse-down through the app at `point` (top-left coordinates in `host`), as the card's event
    /// monitor sees a person's click.
    private func mouseDown(at point: CGPoint, in window: NSWindow, host: NSView) throws {
        let location = NSPoint(x: point.x, y: host.bounds.height - point.y)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                    clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                  clickCount: 1, pressure: 0))
        // The up first: a mouse-down that starts tracking waits for it.
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
        settle(0.4)
    }

    func testAClickOutsideClosesTheCardAndOneInsideDoesNot() throws {
        let (window, host) = sidebarWindow(container: try makeContainer(name: "George"),
                                           router: SettingsRouter(defaults: defaults), menuOpen: true, selection: .constant(nil))
        window.orderFrontRegardless()
        defer { window.close() }
        settle()
        XCTAssertTrue(try cardIsShowing(host), "starts open")
        try mouseDown(at: Self.versionPoint, in: window, host: host)
        XCTAssertTrue(try cardIsShowing(host), "a click on the card's version line keeps it open")
        try mouseDown(at: CGPoint(x: sidebarSize.width - 10, y: sidebarSize.height - 60), in: window, host: host)
        XCTAssertFalse(try cardIsShowing(host), "a click outside closed the card")
    }

    func testEscapeClosesTheCard() throws {
        let (window, host) = sidebarWindow(container: try makeContainer(name: "George"),
                                           router: SettingsRouter(defaults: defaults), menuOpen: true, selection: .constant(nil))
        window.orderFrontRegardless()
        defer { window.close() }
        settle()
        XCTAssertTrue(try cardIsShowing(host), "starts open")
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        settle(0.4)
        XCTAssertFalse(try cardIsShowing(host), "Escape closed the card")
    }

    func testAClosedSidebarHasNoCard() throws {
        let (window, host) = sidebarWindow(container: try makeContainer(name: "George"),
                                           router: SettingsRouter(defaults: defaults), menuOpen: false, selection: .constant(nil))
        defer { window.close() }
        XCTAssertFalse(try cardIsShowing(host), "the pixel check tells open from closed")
    }
    #endif
}

private extension CGFloat {
    /// Pixels per point for a bitmap `pixels` wide whose size in points is `self`.
    func ratio(_ pixels: Int) -> CGFloat { CGFloat(pixels) / self }
}
