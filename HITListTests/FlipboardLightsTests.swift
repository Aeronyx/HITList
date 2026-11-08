import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// George, 2026-11-08: the switches' lights "slowly float in from the left side of the screen" whenever a friend opens
/// the Flipboard on his iPhone; they should be "more sleek/modern" and "actually stick to their switches"; and "all
/// switches should be the same width and height". The drift was the overdue light's `PhaseAnimator`, whose easing
/// carried its first layout; it breathes on a clock now (`FlipLightStyle.breath`), and nothing in a tile is placed
/// from a `GeometryReader`. These pin the parts that can be pinned without a screen; `HITListUITests`'s
/// `testFlipboardLightsStayOnTheirSwitches` films the tab switch and measures the tiles.
@MainActor
final class FlipboardLightsTests: XCTestCase {

    // MARK: One size for every tile

    func testEveryTileIsAsTallAsTheTallest() {
        let heights: [CGFloat] = [200, 236, 150]
        let (frames, size) = FlipboardLayout.frames(width: 344, columns: 2, spacing: 14, spans: [1, 1, 1],
                                                    keepsOwnHeight: [false, false, false]) { index, _ in heights[index] }
        XCTAssertEqual(frames.map(\.height), [236, 236, 236], "a short switch and the + tile take the tallest's height")
        XCTAssertEqual(frames.map(\.width), [165, 165, 165], "equal columns")
        XCTAssertEqual(frames[2].minY, 236 + 14, "the second row starts under the first")
        XCTAssertEqual(size.height, 236 + 14 + 236)
    }

    func testTheSwitchCardKeepsItsOwnHeight() {
        // Two tiles, then the card two columns wide (it starts a new row of three).
        let heights: [CGFloat] = [210, 236, 320]
        let (frames, _) = FlipboardLayout.frames(width: 600, columns: 3, spacing: 14, spans: [1, 1, 2],
                                                 keepsOwnHeight: [false, false, true]) { index, _ in heights[index] }
        XCTAssertEqual(frames[0].height, 236)
        XCTAssertEqual(frames[1].height, 236)
        XCTAssertEqual(frames[2].height, 320, "the card is as tall as it measures")
        XCTAssertEqual(frames[2].minY, 236 + 14)
    }

    func testTheTileHeightIgnoresTheCard() {
        // A card taller than every tile doesn't stretch the tiles beside it.
        let heights: [CGFloat] = [400, 236, 220]
        let (frames, _) = FlipboardLayout.frames(width: 600, columns: 3, spacing: 14, spans: [2, 1, 1],
                                                 keepsOwnHeight: [true, false, false]) { index, _ in heights[index] }
        XCTAssertEqual(frames.map(\.height), [400, 236, 236])
    }

    /// The face is laid out the same for every kind of switch, so the tiles measure alike even before the grid evens
    /// them: a one-word title and one that needs two lines and more, a plain switch and a ten-flip charger, red and green.
    func testEveryKindOfSwitchFaceMeasuresTheSame() throws {
        let faces: [(String, Int, Int, Flipboard.Side, Bool)] = [
            ("Run", 1, 0, .red, false),
            ("Clean the litter box", 1, 0, .red, true),
            ("Descale the coffee machine and wash the filter basket", 1, 0, .red, false),
            ("Practice guitar", 4, 4, .green, false),
            ("Go to the gym", 10, 3, .red, false),
            ("Change the bed sheets", 1, 0, .green, false),
        ]
        let heights = try faces.map { title, target, lamps, side, overdue in
            try height(of: FlipSwitchFace(title: title, ruleText: "every week", target: target, lamps: lamps, side: side,
                                          isOverdue: overdue, fraction: 0.4, caption: "Due in 2 days", reduceMotion: true) {
                RockerSwitch(tilt: side == .green ? 1 : -1)
            })
        }
        XCTAssertEqual(Set(heights).count, 1, "every face the same height: \(heights)")
    }

    // MARK: The lights

    func testThePillsSayWhatTheSwitchSays() {
        let red = FlipLightStyle.pill(0, target: 1, lit: 0, side: .red)
        XCTAssertEqual(red.tint, FlipLightStyle.red)
        XCTAssertEqual(red.level, 1, "a plain red switch: fully lit")
        let done = FlipLightStyle.pill(0, target: 1, lit: 1, side: .green)
        XCTAssertEqual(done.tint, FlipLightStyle.green)
        XCTAssertEqual(done.level, FlipLightStyle.doneLevel, "done: lit, softer")
        XCTAssertLessThan(FlipLightStyle.doneLevel, 1)

        // A red charger with one of three flips: the first green, the others dark with a little red.
        XCTAssertEqual(FlipLightStyle.pill(0, target: 3, lit: 1, side: .red).tint, FlipLightStyle.green)
        let waiting = FlipLightStyle.pill(1, target: 3, lit: 1, side: .red)
        XCTAssertNil(waiting.tint)
        XCTAssertEqual(waiting.ember, FlipLightStyle.ember)
        // Charged: every pill green, no ember.
        for index in 0..<3 {
            XCTAssertEqual(FlipLightStyle.pill(index, target: 3, lit: 3, side: .green).tint, FlipLightStyle.green)
        }
        XCTAssertEqual(FlipLightStyle.pill(2, target: 3, lit: 2, side: .green).ember, 0)
    }

    /// The overdue light breathes on a clock: its brightness at a moment, never an animation that could carry layout.
    func testAnOverdueLightBreathesBetweenDimAndLitOnAClock() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let period = FlipLightStyle.breathPeriod
        XCTAssertEqual(FlipLightStyle.breath(at: start), FlipLightStyle.breathLow, accuracy: 0.0001, "dimmest at the start")
        XCTAssertEqual(FlipLightStyle.breath(at: start.addingTimeInterval(period / 2)), 1, accuracy: 0.0001, "fully lit halfway")
        XCTAssertEqual(FlipLightStyle.breath(at: start.addingTimeInterval(period)), FlipLightStyle.breathLow, accuracy: 0.0001,
                       "one breath per period")
        for step in 0..<50 {
            let level = FlipLightStyle.breath(at: start.addingTimeInterval(Double(step) * period / 50))
            XCTAssertGreaterThanOrEqual(level, FlipLightStyle.breathLow - 0.0001)
            XCTAssertLessThanOrEqual(level, 1.0001)
        }
    }

    func testTheIntervalLineFillsFromTheLeadingEdge() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 3)
        XCTAssertEqual(FractionCapsule(fraction: 0.5).path(in: rect).boundingRect.width, 60, accuracy: 0.01)
        XCTAssertEqual(FractionCapsule(fraction: 0.5).path(in: rect).boundingRect.minX, 0, accuracy: 0.01)
        XCTAssertTrue(FractionCapsule(fraction: 0).path(in: rect).isEmpty, "nothing elapsed: no line")
        XCTAssertEqual(FractionCapsule(fraction: 1.5).path(in: rect).boundingRect.width, 120, accuracy: 0.01, "never past the end")
        XCTAssertEqual(FractionCapsule(fraction: 0.001).path(in: rect).boundingRect.width, 3, accuracy: 0.01,
                       "a moment in: a dot, never a sliver")
    }

    // MARK: Helpers

    /// The height `view` takes at a phone tile's width, rendered at 1x.
    private func height<V: View>(of view: V) throws -> Int {
        let renderer = ImageRenderer(content: view.frame(width: 165).preferredColorScheme(.dark))
        renderer.proposedSize = ProposedViewSize(width: 165, height: nil)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage, "rendered").height
    }
}
