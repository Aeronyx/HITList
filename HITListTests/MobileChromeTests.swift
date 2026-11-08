import XCTest
import SwiftUI
@testable import HITList

/// The iPhone chrome (brief 20): the island's measurements, the glass decision, the start tab, and that
/// the "…" and view-options controls build.
@MainActor
final class MobileChromeTests: XCTestCase {
    func testIslandIsACapsuleInsetFromTheEdges() {
        XCTAssertEqual(IslandMetrics.height, 64)
        XCTAssertEqual(IslandMetrics.sideInset, HITSpacing.l)
        XCTAssertEqual(IslandMetrics.bottomGap, HITSpacing.s)
        XCTAssertEqual(IslandMetrics.cornerRadius, IslandMetrics.height / 2, "a capsule")
        XCTAssertEqual(IslandMetrics.pillRadius, IslandMetrics.cornerRadius - IslandMetrics.pillInset, "concentric pill")
    }

    // MARK: The island's motion (brief 58)

    func testPillIsConcentricWithTheIslandOnBothAxes() {
        XCTAssertEqual(IslandMetrics.pillInset, 6)
        XCTAssertEqual(IslandMetrics.pillHeight, 52, "the bottom island less its inset above and below")
        XCTAssertEqual(IslandMetrics.pillRadius, IslandMetrics.pillHeight / 2, "a capsule, concentric with the island")
        XCTAssertEqual(IslandMetrics.sidePillWidth, 54, "upright: the island's 66 pt less its inset on both sides")
        XCTAssertEqual(IslandMetrics.pillOpacity, 0.18)
    }

    func testPillSlidesOnAFirmSpringAndJumpsUnderReduceMotion() {
        let spring = HITMotion.SpringSpec.tabPill
        XCTAssertEqual(spring.response, 0.28)
        XCTAssertEqual(spring.damping, 0.86)
        XCTAssertLessThan(spring.overshoot, 0.01, "no visible bounce: under a point on a tab's 80 pt move")
        XCTAssertNotNil(HITMotion.tabPill(reduceMotion: false))
        XCTAssertNil(HITMotion.tabPill(reduceMotion: true), "Reduce Motion: the pill jumps")
        XCTAssertEqual(HITMotion.TabPill.stretch, 1.1)
        XCTAssertLessThanOrEqual(HITMotion.TabPill.stretchDuration + HITMotion.TabPill.settleDuration, 0.25,
                                 "the stretch is over by the time the pill arrives")
    }

    func testTheNewTabArrivesWithThePillAndTheOldOneLetsGoFirst() {
        XCTAssertEqual(MobileTabBar.itemAnimation(selected: true, reduceMotion: false), HITMotion.tabPill)
        XCTAssertEqual(MobileTabBar.itemAnimation(selected: false, reduceMotion: false), HITMotion.quick,
                       "the outgoing tab is grey within 100 ms: never two tabs selected")
        XCTAssertLessThan(HITMotion.Role.quick.arrival, 0.2)
        XCTAssertNil(MobileTabBar.itemAnimation(selected: true, reduceMotion: true))
        XCTAssertNil(MobileTabBar.itemAnimation(selected: false, reduceMotion: true))
    }

    func testOnlyAChangeOfTabTicks() {
        XCTAssertEqual(TabTap(tapped: .inbox, selected: .today), .change)
        XCTAssertTrue(TabTap(tapped: .inbox, selected: .today).playsHaptic)
        XCTAssertEqual(TabTap(tapped: .today, selected: .today), .reselect, "a re-tap pops to the root")
        XCTAssertFalse(TabTap(tapped: .today, selected: .today).playsHaptic, "no haptic on a re-tap")
        for tapped in MobileTab.allCases {
            for selected in MobileTab.allCases {
                XCTAssertEqual(TabTap(tapped: tapped, selected: selected).playsHaptic, tapped != selected)
            }
        }
    }

    func testScreensCrossfadeWithASmallRiseAndNoSlide() {
        XCTAssertEqual(HITMotion.TabSwitch.duration, 0.2)
        XCTAssertEqual(HITMotion.TabSwitch.rise, 6)
        XCTAssertEqual(HITMotion.TabSwitch.reducedDuration, 0.15, "Reduce Motion: opacity only, a little quicker")
        XCTAssertEqual(HITMotion.tabSwitch(reduceMotion: false), .easeInOut(duration: 0.2))
        XCTAssertEqual(HITMotion.tabSwitch(reduceMotion: true), .easeInOut(duration: 0.15))
        XCTAssertLessThanOrEqual(HITMotion.TabSwitch.duration, 0.25, "within the motion system's 250 ms")
    }

    func testTheUprightIslandHasRoomToBreathe() {
        // Brief 63: the friend on the iPhone Duo found the upright island's tabs cramped.
        XCTAssertEqual(IslandMetrics.sideItemHeight, 60, "52 before")
        XCTAssertEqual(IslandMetrics.sideWidth, 66, "60 before")
        XCTAssertEqual(IslandMetrics.sideHeight, 4 * 60 + 2 * 6)
        XCTAssertEqual(IslandMetrics.sideLabelGap, 5)
        XCTAssertEqual(IslandMetrics.labelGap, 3, "the bottom island unchanged")
        XCTAssertEqual(IslandMetrics.sideAddButtonGap, 16, "the + under the upright island")
        XCTAssertEqual(IslandMetrics.addButtonGap, 12, "the + above the bottom island unchanged")
        XCTAssertEqual(IslandMetrics.sideAddButtonSize, CGSize(width: 66, height: 50), "as wide as the island")
        XCTAssertEqual(IslandMetrics.sideChromeHeight, 8 + 50 + 16 + 252)
        XCTAssertEqual(IslandMetrics.sideColumnWidth, 74)

        // Still inside the outer display's 84 pt bar column and on the camera's line, which sits 36 pt into it.
        let column: CGFloat = 84
        let offset = IslandPlacement.sideOffset(columnWidth: column, cameraCentre: 36)
        XCTAssertEqual(offset, -6, "follows the camera")
        XCTAssertGreaterThanOrEqual(column / 2 + offset - IslandMetrics.sideWidth / 2, 0, "inside the column's inner edge")
        XCTAssertLessThanOrEqual(column / 2 + offset + IslandMetrics.sideWidth / 2, column, "inside the screen's edge")

        // The fallback to the bottom island moves up with the taller island: upright (678 pt) it stands at the
        // side, on its side (466 pt) it goes to the bottom.
        XCTAssertEqual(IslandPlacement.sideMinimumWindowHeight, 636)
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .trailing, windowHeight: 678), .side(.trailing))
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .trailing, windowHeight: 466), .bottom)
        XCTAssertEqual(IslandPlacement(verticalBarEdge: .trailing, windowHeight: 620), .bottom,
                       "a column too short for the taller island and the system's items")
    }

    func testIslandRendersOnBothAxes() {
        for axis in [Axis.horizontal, .vertical] {
            let bar = MobileTabBar(selection: .constant(.upcoming), day: 7, axis: axis)
                .frame(width: 393, height: 300)
                .preferredColorScheme(.dark)
            XCTAssertNotNil(ImageRenderer(content: bar).cgImage, "\(axis)")
        }
    }

    func testChromeHeightIsTheIslandPlusThePlus() {
        XCTAssertEqual(IslandMetrics.chromeHeight,
                       IslandMetrics.bottomGap + IslandMetrics.height + IslandMetrics.addButtonGap + FloatingAddButton.size.height)
        XCTAssertEqual(IslandMetrics.chromeHeight, 134)
        XCTAssertEqual(FloatingAddButton.size, CGSize(width: 76, height: 50), "a wide oval, a good bit larger than build 13's")
    }

    func testRowsMeasureLikeTheReference() {
        // Todoist's row (George's reference): a little more above the title than below the second line.
        let insets = ListMetrics.rowInsets(compact: false)
        XCTAssertEqual(insets.top, 12)
        XCTAssertEqual(insets.bottom, 10)
        XCTAssertEqual(insets.leading, insets.trailing)
        let compact = ListMetrics.rowInsets(compact: true)
        XCTAssertLessThan(compact.top, insets.top)
        XCTAssertLessThan(compact.bottom, insets.bottom)
        XCTAssertEqual(ListMetrics.rowLineGap, 4)
    }

    func testRowTypeIsAStepLargerOnlyBesideTheUprightIsland() {
        // Brief 63: a friend on the iPhone Duo asked for slightly larger type on the outer display.
        #if os(iOS)
        XCTAssertEqual(HITType.taskTitleSize, 16, "every other iPhone: unchanged")
        XCTAssertEqual(HITType.taskTitleSideSize, 17)
        XCTAssertEqual(HITType.taskTitleTracking, -0.3, "the same tracking at both sizes")
        XCTAssertEqual(HITType.taskMetaSize, 12)
        XCTAssertEqual(HITType.taskMetaSideSize, 13)
        XCTAssertEqual(HITType.taskTitle, HITFont.inter(16, .regular, relativeTo: .body))
        XCTAssertEqual(HITType.taskTitleSide, HITFont.inter(17, .regular, relativeTo: .body))
        XCTAssertEqual(HITType.taskMeta, HITType.caption, "the meta line is the caption size it always was")
        XCTAssertEqual(HITType.taskMetaSide, HITFont.inter(13, .regular, relativeTo: .caption))
        #endif
        XCTAssertEqual(HITType.taskTitle(for: .bottom), HITType.taskTitle)
        XCTAssertEqual(HITType.taskMeta(for: .bottom), HITType.taskMeta)
        for edge in [HorizontalEdge.leading, .trailing] {
            XCTAssertEqual(HITType.taskTitle(for: .side(edge)), HITType.taskTitleSide)
            XCTAssertEqual(HITType.taskMeta(for: .side(edge)), HITType.taskMetaSide)
        }
        XCTAssertEqual(EnvironmentValues().listIslandPlacement, .bottom, "outside the iPhone shell: the usual sizes")
    }

    func testGlassNeedsTheOSAndBothSwitchesOff() {
        XCTAssertTrue(HITEffects.allowsGlass(osSupportsGlass: true, reduceEffects: false, reduceTransparency: false))
        XCTAssertFalse(HITEffects.allowsGlass(osSupportsGlass: false, reduceEffects: false, reduceTransparency: false))
        XCTAssertFalse(HITEffects.allowsGlass(osSupportsGlass: true, reduceEffects: true, reduceTransparency: false))
        XCTAssertFalse(HITEffects.allowsGlass(osSupportsGlass: true, reduceEffects: false, reduceTransparency: true))
    }

    func testStartTabFallsBackToToday() {
        XCTAssertEqual(Preferences.startTabValue(nil), .today)
        XCTAssertEqual(Preferences.startTabValue("nonsense"), .today)
        XCTAssertEqual(Preferences.startTabValue("inbox"), .inbox)
    }

    // MARK: Tabs (brief 35, order swapped back in brief 40)

    func testTabsRunInboxTodayUpcomingFlipboard() {
        XCTAssertEqual(MobileTab.allCases, [.inbox, .today, .upcoming, .flipboard], "Flipboard furthest right")
        XCTAssertEqual(MobileTab.allCases.map(\.title), ["Inbox", "Today", "Upcoming", "Flipboard"])
        XCTAssertEqual(MobileTab.allCases.map(\.rawValue), ["inbox", "today", "upcoming", "flipboard"],
                       "raw values unchanged: a stored start tab still means the same screen")
    }

    func testFlipboardTabLooksLikeItsSidebarRow() {
        // SidebarView: row("Flipboard", "switch.2", .flipboard).
        XCTAssertEqual(MobileTab.flipboard.symbol, "switch.2")
        XCTAssertEqual(MobileTab.flipboard.title, "Flipboard")
        XCTAssertEqual(MobileTab.inbox.symbol, "tray")
        XCTAssertEqual(MobileTab.upcoming.symbol, "calendar.badge.clock")
        XCTAssertNil(MobileTab(rawValue: "browse"), "Browse is a pushed screen now, not a tab")
    }

    func testFlipboardIsAStartScreenAndBrowseFallsBackToToday() {
        XCTAssertEqual(Preferences.startTabValue("flipboard"), .flipboard)
        XCTAssertEqual(Preferences.startTabValue("upcoming"), .upcoming)
        XCTAssertEqual(Preferences.startTabValue("browse"), .today, "someone who chose Browse opens on Today")
        XCTAssertEqual(Preferences.startScreenChoices, [.inbox, .today, .upcoming, .flipboard])
    }

    // MARK: Top-right control (brief 35)

    func testTopRightIsSearchOnATabAndAGearFromBrowseOn() {
        XCTAssertEqual(MobileTopControl.forScreen(atTabRoot: true), .browse, "Inbox, Today, Flipboard, Upcoming")
        XCTAssertEqual(MobileTopControl.forScreen(atTabRoot: false), .settings,
                       "Browse and the lists pushed from it never push a second Browse")
    }

    func testTopRightControlsLookAndRead() {
        XCTAssertEqual(MobileTopControl.browse.symbol, "magnifyingglass")
        XCTAssertEqual(MobileTopControl.browse.title, "Browse")
        XCTAssertEqual(MobileTopControl.browse.identifier, "browseButton")
        XCTAssertEqual(MobileTopControl.settings.symbol, "gearshape")
        XCTAssertEqual(MobileTopControl.settings.title, "Settings")
        XCTAssertEqual(MobileTopControl.settings.identifier, "settingsButton")
    }

    func testViewOptionsMenuRendersWithTheScreensItems() {
        let view = ViewOptionsMenu { Toggle("Show completed", isOn: .constant(true)) }
            .environment(\.screenMenuItems, AnyView(Button("Review Inbox…") {}))
            .frame(width: 200, height: 60)
            .preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    func testScreenOptionButtonRendersAloneAndWithItems() {
        let plain = ScreenOptionButton(action: {}) { Image(systemName: "speaker.wave.2") }
        XCTAssertNotNil(ImageRenderer(content: plain.frame(width: 60, height: 60)).cgImage)
        let withItems = plain.environment(\.screenMenuItems, AnyView(Button("Add Switch…") {}))
        XCTAssertNotNil(ImageRenderer(content: withItems.frame(width: 60, height: 60)).cgImage)
    }

    func testViewOptionsMenuRenders() {
        let view = ViewOptionsMenu { Toggle("Show completed", isOn: .constant(true)) }
            .frame(width: 200, height: 60)
            .preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    func testSyncBoltShapesSayTheState() {
        let now = Date()
        // 15% larger than the original 11 pt (George, brief 54), its tap frame grown with it.
        XCTAssertEqual(SyncBolt.size, 12.65, accuracy: 0.001)
        XCTAssertEqual(SyncBolt.frame.width, 16)
        XCTAssertEqual(SyncBolt.frame.height, 23)
        XCTAssertEqual(SyncBolt.look(for: .synced(now), now: now).symbol, "bolt.fill", "synced: filled")
        XCTAssertEqual(SyncBolt.look(for: .syncing).symbol, "bolt", "syncing: hollow")
        XCTAssertEqual(SyncBolt.look(for: .offline).symbol, "bolt.slash.fill", "offline: struck through")
        XCTAssertEqual(SyncBolt.look(for: .synced(now.addingTimeInterval(-2 * SyncBolt.staleAfter)), now: now).symbol,
                       "bolt.slash.fill", "stale: struck through")
        XCTAssertEqual(SyncBolt.look(for: .synced(now), now: now).color, Theme.bolt, "the theme's bolt pastel, not the accent")
        XCTAssertEqual(SyncBolt.look(for: .notSignedIn, everSignedIn: true).color, HITColor.dueOverdue)
        XCTAssertEqual(SyncBolt.look(for: .offline).color, Theme.secondaryText)
    }

    func testScreenMenuRendersForEveryTab() {
        for tab in MobileTab.allCases {
            let view = ScreenMenu(onSettings: {}) {
                Button(tab.title) {}
            }
            .frame(width: 200, height: 60)
            .preferredColorScheme(.dark)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(tab.title) menu didn't render")
        }
    }

    #if os(iOS)
    // MARK: Browse (brief 35)

    func testBrowseEndsWithCompletedThenSettings() {
        XCTAssertEqual(BrowseView.lastRows, [.completed, .settings], "no Flipboard row: it is a tab now")
        XCTAssertEqual(BrowseView.lastRows.map(\.title), ["Completed", "Settings"])
        XCTAssertEqual(BrowseView.lastRows.map(\.symbol), ["checkmark.circle", "gearshape"])
    }

    // MARK: Browse's top left (brief 40)

    func testBrowseProfileShowsTheNameThenTheFirstNameThenTheAvatar() {
        let tenPerCharacter: (String) -> CGFloat = { CGFloat($0.count) * 10 }
        func fit(_ name: String?, _ width: CGFloat = 100) -> BrowseProfileButton.Fit {
            BrowseProfileButton.fit(name: name, maxWidth: width, width: tenPerCharacter)
        }
        XCTAssertEqual(fit("George"), .name("George"))
        XCTAssertEqual(fit("George Trammell"), .name("George"), "too long: the first name")
        XCTAssertEqual(fit("George Trammell", 150), .name("George Trammell"), "15 characters: fits exactly")
        XCTAssertEqual(fit("Bartholomew Fitzgerald"), .avatarOnly, "not even the first name fits")
        XCTAssertEqual(fit("  George  "), .name("George"), "trimmed")
        XCTAssertEqual(fit(nil, 130), .prompt("Add your name"), "no profile yet")
        XCTAssertEqual(fit("   ", 130), .prompt("Add your name"))
        XCTAssertEqual(fit(nil), .prompt("Add name"), "the short prompt where the long one doesn't fit")
        XCTAssertEqual(fit(nil, 40), .avatarOnly)
        XCTAssertNil(BrowseProfileButton.Fit.avatarOnly.text)
    }

    func testBrowseProfileMeasuresWithItsOwnFont() {
        let short = BrowseProfileButton.textWidth("Al")
        let long = BrowseProfileButton.textWidth("Alexandria")
        XCTAssertGreaterThan(short, 0)
        XCTAssertGreaterThan(long, short)
        // Measured on an iPhone 17 (2026-11-04): "George Tra" (80 pt) kept Browse's New and gear, "George
        // Tram" (94 pt) pushed the gear into a "…" overflow. The room leaves a margin for an iPhone 16.
        func real(_ name: String?) -> BrowseProfileButton.Fit {
            BrowseProfileButton.fit(name: name, maxWidth: BrowseProfileButton.maxNameWidth, width: BrowseProfileButton.textWidth)
        }
        XCTAssertLessThan(BrowseProfileButton.maxNameWidth, 80)
        XCTAssertEqual(real("George"), .name("George"))
        XCTAssertEqual(real("George Trammell"), .name("George"))
        XCTAssertEqual(real(nil), .prompt("Add name"))
    }
    #endif
}
