import XCTest
import SwiftUI
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
    #endif
}
