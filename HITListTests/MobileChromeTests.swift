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
        XCTAssertEqual(IslandMetrics.chromeHeight, 126)
        XCTAssertEqual(FloatingAddButton.size, CGSize(width: 64, height: 42), "a wide oval, a little shorter than build 8's")
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
        XCTAssertEqual(Preferences.startTabValue("browse"), .browse)
        XCTAssertEqual(Preferences.startTabValue("inbox"), .inbox)
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
        XCTAssertEqual(SyncBolt.look(for: .notSignedIn).color, HITColor.dueOverdue)
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
