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
        XCTAssertEqual(IslandMetrics.chromeHeight, 132)
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

    #if os(iOS)
    func testScreenMenuRendersForEveryTab() {
        for tab in MobileTab.allCases {
            let view = ScreenMenu(showSettings: .constant(false)) {
                Button(tab.title) {}
            }
            .frame(width: 200, height: 60)
            .preferredColorScheme(.dark)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(tab.title) menu didn't render")
        }
    }
    #endif
}
