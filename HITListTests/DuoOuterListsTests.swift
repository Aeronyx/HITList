import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Brief 106: the lists beside the iPhone Duo's bar column (the outer display): nothing of ours under the system's clock
/// and battery, a row's Group never cut to a letter, the upright island's labels inside their cells, the island out of
/// the keyboard's way. The column itself is `MobileChromeTests`'.
@MainActor
final class DuoOuterListsTests: XCTestCase {
    // MARK: Item 2: strips that scroll sideways stop at the column

    func testStripsStopAtTheBarColumnOnly() {
        XCTAssertNil(IslandPlacement.bottom.barColumnEdge, "every other iPhone: the strips as they were")
        XCTAssertEqual(IslandPlacement.side(.trailing).barColumnEdge, .trailing)
        XCTAssertEqual(IslandPlacement.side(.leading).barColumnEdge, .leading)
        XCTAssertEqual(IslandPlacement.bottom.stripBackgroundEdges, .all)
        XCTAssertEqual(IslandPlacement.side(.trailing).stripBackgroundEdges, [.top, .bottom, .leading],
                       "the week strip's band stops short of the clock and battery")
        XCTAssertEqual(IslandPlacement.side(.leading).stripBackgroundEdges, [.top, .bottom, .trailing])
        XCTAssertGreaterThan(BrowseChipMetrics.fade, 0)
    }
}
