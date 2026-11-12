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

    // MARK: A board's lights and its row (brief 126)

    private func lights(_ count: Int, on: (Int) -> Bool = { $0 % 3 != 1 }) -> [BoardLight] {
        (0..<count).map { BoardLight(id: UUID(), title: "Switch \($0 + 1)", isOn: on($0)) }
    }

    /// The strip draws dots while they fit the header's real width, then slimmer segments, then the bar with its count:
    /// decided by the width, not by how many there are. The widths of an iPhone 16's panel header beside "Before Bed"
    /// (about 230 pt) and a Mac's (about 600).
    func testTheLightsFallBackByTheWidthTheyHave() {
        XCTAssertEqual(BoardLights.dotsWidth(3), 3 * 7 + 2 * 4)
        XCTAssertEqual(BoardLights.segmentsWidth(40), 40 * 3 + 39 * 2)
        XCTAssertEqual(BoardLights.mode(count: 3, width: 230), .dots)
        XCTAssertEqual(BoardLights.mode(count: 12, width: 230), .dots)
        XCTAssertEqual(BoardLights.mode(count: 20, width: 230), .dots, "20 dots are 216 pt")
        XCTAssertEqual(BoardLights.mode(count: 20, width: 150), .segments)
        XCTAssertEqual(BoardLights.mode(count: 40, width: 230), .segments, "40 segments are 198 pt")
        XCTAssertEqual(BoardLights.mode(count: 40, width: 600), .dots)
        XCTAssertEqual(BoardLights.mode(count: 40, width: 120), .bar)
        XCTAssertEqual(BoardLights.mode(count: 60, width: 230), .bar)
        // Never cut off: whatever is chosen fits, or is the bar.
        for count in [1, 3, 12, 20, 40, 80] {
            for width in stride(from: CGFloat(20), through: 700, by: 7) {
                switch BoardLights.mode(count: count, width: width) {
                case .dots: XCTAssertLessThanOrEqual(BoardLights.dotsWidth(count), width + 0.5)
                case .segments: XCTAssertLessThanOrEqual(BoardLights.segmentsWidth(count), width + 0.5)
                case .bar: XCTAssertGreaterThan(BoardLights.segmentsWidth(count), width + 0.5)
                }
            }
        }
    }

    /// A tap along the strip picks the light under it, in the row's order.
    func testATapPicksTheLightUnderIt() {
        XCTAssertEqual(BoardLights.index(at: 3, count: 5, mode: .dots), 0)
        XCTAssertEqual(BoardLights.index(at: 3 + 11 * 2, count: 5, mode: .dots), 2)
        XCTAssertEqual(BoardLights.index(at: 500, count: 5, mode: .dots), 4, "past the end: the last")
        XCTAssertEqual(BoardLights.index(at: -10, count: 5, mode: .dots), 0)
        XCTAssertEqual(BoardLights.index(at: 1.5 + 5 * 7, count: 40, mode: .segments), 7)
        XCTAssertNil(BoardLights.index(at: 10, count: 40, mode: .bar), "the bar has no single light")
    }

    /// VoiceOver reads the strip as one element, with the names of what is still off.
    func testVoiceOverReadsTheStripAsOne() {
        let five = ["Take meds", "Brush teeth", "Floss", "Read", "Lights out"].enumerated().map {
            BoardLight(id: UUID(), title: $0.element, isOn: ![1, 2].contains($0.offset))
        }
        XCTAssertEqual(BoardLights.accessibilityLabel(five), "3 of 5 on. Off: Brush teeth, Floss.")
        XCTAssertEqual(BoardLights.accessibilityLabel(lights(4) { _ in true }), "All 4 on.")
        XCTAssertEqual(BoardLights.accessibilityLabel([]), "No switches.")
        XCTAssertEqual(BoardLights.count(lights(24) { $0 < 17 }), "17 of 24")
    }

    /// Every width a phone, the Duo, an iPad or a Mac window gives the board: a row shows whole tiles and a clear part
    /// of the next, a fifth to two fifths of a tile (a tile shown nine-tenths read as a clipping fault), its tiles never
    /// wider than the grid's and never under 128 pt. On an iPhone 16 (a 361 pt panel): two whole tiles of about 145 pt.
    func testARowShowsWholeTilesAndAClearPartOfTheNext() {
        let spacing = FlipboardView.spacing, inset = BoardPanel.inset
        // Phones from the Duo's outer display (about 342 pt) up; regular widths from the Mac's narrowest board up.
        for compact in [true, false] {
            for even in [false, true] {
                let narrowest: CGFloat = compact || even ? 330 : 470
                for width in stride(from: narrowest, through: 1600, by: 1) {
                    let columns = FlipboardLayout.columnCount(width: width, compact: compact, spacing: spacing, even: even)
                    let grid = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
                    let tile = FlipboardLayout.rowTileWidth(width: width, inset: inset, spacing: spacing, gridTile: grid)
                    let peek = FlipboardLayout.rowPeek(width: width, tile: tile, spacing: spacing, inset: inset)
                    XCTAssertLessThanOrEqual(tile, grid + 0.5, "width \(width)")
                    XCTAssertGreaterThanOrEqual(tile, 128, "width \(width)")
                    XCTAssertGreaterThanOrEqual(peek, 0.19, "width \(width), tile \(tile): \(peek)")
                    XCTAssertLessThanOrEqual(peek, 0.41, "width \(width), tile \(tile): \(peek)")
                }
            }
        }
        let phone = FlipboardLayout.rowTileWidth(width: 361, inset: inset, spacing: spacing, gridTile: (361 - spacing) / 2)
        XCTAssertEqual(phone, 144.6, accuracy: 0.5)
        XCTAssertEqual(FlipboardLayout.rowPeek(width: 361, tile: phone, spacing: spacing, inset: inset), 0.22, accuracy: 0.01)
    }

    /// Whatever room the header leaves it, the strip draws within it on one line (dots, segments or the bar, chosen by
    /// `ViewThatFits`), with Differentiate Without Color off and on. Narrower than the bar and its count (about 115
    /// pt), `BoardHeaderLayout` gives the strip a line of its own. With `STRIP_DIR` set, a picture of every mode.
    func testTheStripDrawsWithinItsRoomOnOneLine() throws {
        func make(_ count: Int) -> [BoardLight] { (0..<count).map { BoardLight(id: UUID(), title: "S\($0)", isOn: $0 % 3 != 1) } }
        for count in [3, 12, 20, 40] {
            for width in [CGFloat(130), 150, 230, 400] {
                for differentiate in [false, true] {
                    let size = Self.offered(width, BoardLightsStrip(lights: make(count), differentiate: differentiate))
                    XCTAssertGreaterThan(size.width, 20, "measured")
                    XCTAssertLessThanOrEqual(size.width, width + 0.5, "\(count) lights in \(width) pt")
                    XCTAssertLessThanOrEqual(size.height, BoardLights.lineHeight + 0.5, "\(count) lights in \(width) pt: one line")
                }
            }
        }
        guard let folder = ProcessInfo.processInfo.environment["STRIP_DIR"] else { return }
        let allOn = (0..<4).map { BoardLight(id: UUID(), title: "\($0)", isOn: true) }
        let sheet = HStack(alignment: .top, spacing: 24) {
            ForEach([false, true], id: \.self) { shapes in
                VStack(alignment: .trailing, spacing: 12) {
                    Text(shapes ? "Differentiate Without Color" : "Colour").font(HITType.caption).foregroundStyle(.white)
                    ForEach(Array([(5, CGFloat(230)), (20, 230), (40, 230), (40, 150), (24, 130)].enumerated()), id: \.offset) { _, sample in
                        BoardLightsStrip(lights: make(sample.0), differentiate: shapes).frame(width: sample.1, alignment: .trailing)
                    }
                    BoardLightsStrip(lights: allOn, differentiate: shapes).frame(width: 230, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.09, green: 0.1, blue: 0.13))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        #if os(macOS)
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        let data = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        #else
        let data = try XCTUnwrap(renderer.uiImage?.pngData())
        #endif
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("lights-strip-modes.png"))
    }

    /// A board's header (`BoardHeaderLayout`): the lights sit on the name's line at the trailing end while they fit
    /// beside it; a long name or the largest type sends them to a line of their own under the cadence. Either way they
    /// never overlap the name or the cadence, stay one line, and the header is as tall as what it holds. The parts
    /// answer as text and the strip do: a name wraps at the width it is offered, the strip picks dots, segments or the bar.
    func testTheHeaderKeepsTheLightsClearOfTheName() {
        func name(ideal: CGFloat, line: CGFloat) -> (CGFloat) -> CGSize {
            { width in CGSize(width: min(ideal, width), height: line * (ideal / max(1, width)).rounded(.up)) }
        }
        func strip(_ count: Int) -> (CGFloat) -> CGSize {
            { width in
                switch BoardLights.mode(count: count, width: width) {
                case .dots: CGSize(width: BoardLights.dotsWidth(count), height: BoardLights.lineHeight)
                case .segments: CGSize(width: BoardLights.segmentsWidth(count), height: BoardLights.lineHeight)
                case .bar: CGSize(width: 115, height: BoardLights.lineHeight)
                }
            }
        }
        let cadence: (CGFloat) -> CGSize = { width in CGSize(width: min(160, width), height: 15 * (160 / width).rounded(.up)) }

        // An iPhone 16's panel header: "Before Bed" and five lights on one line.
        let phone = BoardHeaderLayout.arrange(width: 337, gap: 12, lineSpacing: 3, titleIdeal: CGSize(width: 90, height: 20),
                                              title: name(ideal: 90, line: 20), lights: strip(5), below: cadence)
        XCTAssertEqual(phone.lights.maxX, 337, accuracy: 0.5, "at the trailing end")
        XCTAssertEqual(phone.lights.midY, 10, accuracy: 0.5, "on the name's line")
        XCTAssertLessThanOrEqual(phone.title.maxX, phone.lights.minX - 12 + 0.5)
        // The largest type: the name takes the line, and the lights go under the cadence.
        let large = BoardHeaderLayout.arrange(width: 337, gap: 12, lineSpacing: 3, titleIdeal: CGSize(width: 520, height: 62),
                                              title: name(ideal: 520, line: 62), lights: strip(5), below: cadence)
        XCTAssertEqual(large.lights.minX, 0, "leading, on a line of their own")
        XCTAssertGreaterThan(large.lights.minY, large.below?.maxY ?? 0)

        for ideal in stride(from: CGFloat(40), through: 700, by: 15) {
            for count in [1, 3, 12, 20, 40, 80] {
                for width in [CGFloat(300), 337, 600] {
                    let a = BoardHeaderLayout.arrange(width: width, gap: 12, lineSpacing: 3,
                                                      titleIdeal: CGSize(width: ideal, height: 20),
                                                      title: name(ideal: ideal, line: 20), lights: strip(count), below: cadence)
                    let label = "name \(ideal) pt, \(count) lights, \(width) pt"
                    XCTAssertFalse(a.title.intersects(a.lights), label)
                    XCTAssertFalse(a.below.map { $0.intersects(a.lights) } ?? false, label)
                    XCTAssertEqual(a.lights.height, BoardLights.lineHeight, label)
                    XCTAssertLessThanOrEqual(a.lights.maxX, width + 0.5, label)
                    XCTAssertGreaterThanOrEqual(a.size.height, max(a.lights.maxY, a.below?.maxY ?? 0, a.title.maxY) - 0.5, label)
                }
            }
        }
    }

    /// The size `view` takes when offered `width` (and any height), as a header's layout offers it.
    private static func offered<V: View>(_ width: CGFloat, _ view: V) -> CGSize {
        let box = OfferedSize()
        let renderer = ImageRenderer(content: Offer(width: width, box: box) { view })
        _ = renderer.cgImage
        return box.size
    }
}

private final class OfferedSize {
    var size = CGSize.zero
}

/// Offers its one view a width and keeps the size it answers.
private struct Offer: Layout {
    let width: CGFloat
    let box: OfferedSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
        box.size = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: nil))
    }
}
