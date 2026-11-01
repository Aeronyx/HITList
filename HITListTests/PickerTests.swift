import XCTest
import HITListCore
@testable import HITList

/// The popout pickers' pure parts: where a card goes in the window.
@MainActor
final class PickerTests: XCTestCase {

    // MARK: Placement

    /// The minimum window's content (760 × 560 less a 52 pt toolbar), in layer coordinates.
    private let window = CGRect(x: 0, y: 52, width: 760, height: 508)
    private let dateCard = CGSize(width: 320, height: 390)

    func testCardGoesBelowItsChipWithItsLeadingEdge() {
        let chip = CGRect(x: 200, y: 100, width: 80, height: 30)
        let card = CGSize(width: 280, height: 200)
        let placed = PickerPlacement.place(anchor: chip, cardSize: card, bounds: window)
        XCTAssertEqual(placed.edge, .below)
        XCTAssertEqual(placed.frame, CGRect(x: 200, y: 130 + PickerPlacement.gap, width: 280, height: 200))
    }

    func testCardGoesAboveWhenThereIsNoRoomBelow() {
        let chip = CGRect(x: 200, y: 450, width: 80, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: CGSize(width: 280, height: 200), bounds: window)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertEqual(placed.frame.maxY, 450 - PickerPlacement.gap)
        XCTAssertEqual(placed.frame.minX, 200)
    }

    func testCardIsClampedHorizontallyInsideTheWindow() {
        let nearRight = CGRect(x: 700, y: 100, width: 50, height: 30)
        let right = PickerPlacement.frame(anchor: nearRight, cardSize: dateCard, bounds: window)
        XCTAssertEqual(right.maxX, window.maxX - PickerPlacement.margin)
        let pastLeft = CGRect(x: -40, y: 100, width: 50, height: 30)
        let left = PickerPlacement.frame(anchor: pastLeft, cardSize: dateCard, bounds: window)
        XCTAssertEqual(left.minX, window.minX + PickerPlacement.margin)
    }

    func testCardWithNoRoomEitherSideStaysInsideOnTheRoomierSide() {
        // The quick-add chip bar in the minimum window: 390 pt fits neither below nor above.
        let chip = CGRect(x: 150, y: 210, width: 70, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: dateCard, bounds: window)
        XCTAssertEqual(placed.edge, .overlapping)
        XCTAssertEqual(placed.frame.maxY, window.maxY - PickerPlacement.margin, "more room below: pinned to the bottom")
        XCTAssertTrue(window.contains(placed.frame))
        let high = CGRect(x: 150, y: 380, width: 70, height: 30)
        let up = PickerPlacement.place(anchor: high, cardSize: dateCard, bounds: window)
        XCTAssertEqual(up.frame.minY, window.minY + PickerPlacement.margin, "more room above: pinned to the top")
    }

    func testCardTallerOrWiderThanTheWindowShrinksToIt() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 150)
        let frame = PickerPlacement.frame(anchor: CGRect(x: 20, y: 20, width: 40, height: 20), cardSize: dateCard, bounds: small)
        XCTAssertEqual(frame, small.insetBy(dx: PickerPlacement.margin, dy: PickerPlacement.margin))
    }

    func testEveryCardStaysInsideEveryLegalWindow() {
        let sizes = [CGSize(width: 760, height: 508), CGSize(width: 820, height: 600), CGSize(width: 1440, height: 848)]
        let cards = PickerKind.allCases.map { CGSize(width: $0.width, height: 420) }
        for size in sizes {
            let bounds = CGRect(origin: CGPoint(x: 0, y: 52), size: size)
            for x in stride(from: -20, through: size.width + 20, by: 37) {
                for y in stride(from: 52, through: 52 + size.height - 30, by: 41) {
                    for card in cards {
                        let frame = PickerPlacement.frame(anchor: CGRect(x: x, y: y, width: 90, height: 30), cardSize: card, bounds: bounds)
                        XCTAssertTrue(bounds.contains(frame), "\(frame) leaves \(bounds)")
                        XCTAssertEqual(frame.size, card)
                    }
                }
            }
        }
    }

    func testCardsFitTheQuickAddPanel() {
        for kind in PickerKind.allCases {
            XCTAssertLessThanOrEqual(kind.width, 560 - 2 * 20, "\(kind) is wider than the panel's content")
        }
    }
}
