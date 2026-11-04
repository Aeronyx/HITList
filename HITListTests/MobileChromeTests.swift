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

    // MARK: Tabs (brief 35)

    func testTabsRunInboxTodayFlipboardUpcoming() {
        XCTAssertEqual(MobileTab.allCases, [.inbox, .today, .flipboard, .upcoming], "Upcoming furthest right")
        XCTAssertEqual(MobileTab.allCases.map(\.title), ["Inbox", "Today", "Flipboard", "Upcoming"])
        XCTAssertEqual(MobileTab.allCases.map(\.rawValue), ["inbox", "today", "flipboard", "upcoming"])
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
        XCTAssertEqual(Preferences.startScreenChoices, [.inbox, .today, .flipboard, .upcoming])
    }

    func testViewOptionsMenuRenders() {
        let view = ViewOptionsMenu { Toggle("Show completed", isOn: .constant(true)) }
            .frame(width: 200, height: 60)
            .preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    func testSyncBoltShapesSayTheState() {
        let now = Date()
        XCTAssertEqual(SyncBolt.size, 11)
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
}
