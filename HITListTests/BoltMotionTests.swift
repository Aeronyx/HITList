import XCTest
import SwiftUI
import ImageIO
@testable import HITList

/// The bolt's second style, the slam (brief 68; George, 2026-11-08: "twirl and strike, but not longer than a second").
/// The strike's own tests stay in `SyncStateTests`.
final class BoltMotionTests: XCTestCase {
    /// The slam sampled every millisecond, with the time of each sample.
    private func samples() -> [(time: TimeInterval, frame: BoltSlamMotion.Frame)] {
        let slam = BoltSlamMotion.timeline()
        return (0...Int((slam.duration * 1000).rounded(.up))).map { step in
            let time = Double(step) / 1000
            return (time, slam.value(time: time))
        }
    }

    func testTheSlamTwirlsHopsAndSlamsPastItsRest() {
        let all = samples()
        let peakTwirl = all.map { abs($0.frame.twirl) }.max() ?? 0
        XCTAssertGreaterThanOrEqual(peakTwirl, 360, "a whole twirl")
        XCTAssertLessThanOrEqual(peakTwirl, 720, "once or twice, never more")

        let apex = all.min { $0.frame.lift < $1.frame.lift }!
        XCTAssertLessThanOrEqual(apex.frame.lift, -2, "it hops up a few points")
        XCTAssertGreaterThanOrEqual(apex.frame.lift, -5, "a few points, no more")
        let turned = all.filter { $0.time >= apex.time }.map { abs($0.frame.twirl.truncatingRemainder(dividingBy: 360)) }
        XCTAssertTrue(turned.allSatisfy { min($0, 360 - $0) < 0.5 }, "upright from the top of the hop on, ready to come down")

        let impact = all.max { $0.frame.lift < $1.frame.lift }!
        XCTAssertGreaterThan(impact.time, apex.time, "down after up")
        XCTAssertGreaterThan(impact.frame.lift, 0.5, "it slams down past its rest position")
        XCTAssertLessThanOrEqual(impact.frame.lift, 2)
        XCTAssertLessThanOrEqual(impact.time - apex.time, 0.12, "the slam itself is fast")

        let squashed = all.min { $0.frame.squash < $1.frame.squash }!
        XCTAssertLessThan(squashed.frame.squash, 0.85, "it squashes on impact")
        XCTAssertGreaterThanOrEqual(squashed.frame.squash, 0.7, "slightly")
        XCTAssertEqual(squashed.time, impact.time, accuracy: 0.04, "at the impact")
        XCTAssertGreaterThan(squashed.frame.stretch, 1, "and spreads as it squashes")
        let warp = all.map { abs($0.frame.warp) }.max() ?? 0
        XCTAssertGreaterThan(warp, 0.04, "it warps a little")
        XCTAssertLessThanOrEqual(warp, 0.15)

        let sparking = all.filter { $0.frame.spark > 0 }
        guard let firstSpark = sparking.first, let lastSpark = sparking.last else { return XCTFail("it lets off sparks") }
        XCTAssertEqual(firstSpark.time, impact.time, accuracy: 0.02, "at the foot, as it lands")
        XCTAssertLessThanOrEqual(lastSpark.time - firstSpark.time, 0.3, "which fade almost at once")
        XCTAssertTrue(all.filter { $0.time < impact.time - 0.02 }.allSatisfy { $0.frame.spark == 0 && $0.frame.glow == 0 },
                      "nothing lights up before the impact")
        XCTAssertLessThanOrEqual(all.map(\.frame.glow).max() ?? 0, 1)
    }

    /// George, 2026-11-10: "when I said 'twirl and rise up a bit before slamming', I meant twirl on the Z axis, as in
    /// halfway through the twirl the bolt would technically be invisible or incredibly thin as the edge of the icon
    /// would be facing the user for a split second." A coin spinning on a table (brief 73): one whole turn about the
    /// vertical axis during the hop, edge-on (no width) a quarter and three quarters round, its other face (the mirror
    /// image) half-way, face-on and unmirrored from the top of the hop on.
    func testTheTwirlIsACoinSpinThatLandsFaceOn() {
        let all = samples()
        let spin = all.filter { $0.time >= BoltSlamMotion.crouch && $0.time <= BoltSlamMotion.apexAt }
        // The face's width goes 1 → 0 → −1 → 0 → 1: edge-on exactly twice.
        let crossings = zip(spin, spin.dropFirst()).filter { ($0.frame.face > 0) != ($1.frame.face > 0) }
        XCTAssertEqual(crossings.count, 2, "edge-on twice in the turn")
        for crossing in crossings {
            XCTAssertLessThan(min(abs(crossing.0.frame.face), abs(crossing.1.frame.face)), 0.02,
                              "a hairline or nothing at \(crossing.1.time) s")
        }
        let half = spin.min { abs($0.frame.twirl - 180) < abs($1.frame.twirl - 180) }!
        XCTAssertEqual(half.frame.face, -1, accuracy: 0.01, "its other face, mirrored, half-way round")
        XCTAssertGreaterThan(half.time, crossings[0].1.time)
        XCTAssertLessThan(half.time, crossings[1].1.time)
        for sample in all where sample.time <= BoltSlamMotion.crouch || sample.time >= BoltSlamMotion.apexAt {
            XCTAssertEqual(sample.frame.face, 1, accuracy: 1e-6, "face-on and unmirrored at \(sample.time) s")
        }
        XCTAssertEqual(all.last!.frame, BoltSlamMotion.Frame(), "it ends as the resting glyph")
    }

    /// Drawn by the app's own view code, the frame nearest the quarter turn is a sliver of the glyph's width, and the
    /// half turn's is the glyph's mirror image: as wide as at rest, its ink on the other side of the centre line.
    @MainActor
    func testTheSpinIsEdgeOnAtTheQuarterTurnAndMirroredAtTheHalf() throws {
        let slam = BoltSlamMotion.timeline()
        let color = boltColor
        func frame(nearest degrees: Double) -> BoltSlamMotion.Frame {
            samples().filter { $0.time < BoltSlamMotion.apexAt }
                .min { abs($0.frame.twirl - degrees) < abs($1.frame.twirl - degrees) }!.frame
        }
        let rest = try render(glyph(EmptyModifier()), scale: 2).ink
        let edgeOn = try render(glyph(BoltSlamMotion.Effect(frame: frame(nearest: 90), color: color)), scale: 2).ink
        XCTAssertLessThan(edgeOn.isNull ? 0 : edgeOn.width, rest.width * 0.15,
                          "edge-on at the quarter turn: \(edgeOn.width) pt of the glyph's \(rest.width)")
        let threeQuarters = try render(glyph(BoltSlamMotion.Effect(frame: frame(nearest: 270), color: color)), scale: 2).ink
        XCTAssertLessThan(threeQuarters.isNull ? 0 : threeQuarters.width, rest.width * 0.15, "and at three quarters")
        let halfWay = try render(glyph(BoltSlamMotion.Effect(frame: frame(nearest: 180), color: color)), scale: 2).ink
        XCTAssertEqual(halfWay.width, rest.width, accuracy: rest.width * 0.12, "the other face is the whole glyph")

        // Exactly half-way round, the glyph is its mirror image left to right (not turned upside down, which a
        // turn in the plane of the screen gives and which looks alike for a bolt): pixel for pixel.
        let size = 96  // the 48 pt square at 2x
        let plain = try render(glyph(EmptyModifier()), scale: 2).bytes
        let turned = try render(glyph(BoltSlamMotion.Effect(frame: .init(twirl: 180), color: color)), scale: 2).bytes
        let upsideDown = try render(glyph(EmptyModifier()).rotationEffect(.degrees(180)), scale: 2).bytes
        func alpha(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Int { Int(bytes[(y * size + x) * 4 + 3]) }
        func difference(_ bytes: [UInt8], fromPlainFlipped flip: Bool) -> Double {
            var total = 0
            for y in 0..<size { for x in 0..<size { total += abs(alpha(bytes, x, y) - alpha(plain, flip ? size - 1 - x : x, y)) } }
            return Double(total) / Double(size * size)
        }
        let mirrorError = difference(turned, fromPlainFlipped: true)
        XCTAssertLessThan(mirrorError, 1.5, "half-way round is the mirror image (mean alpha error \(mirrorError)/255)")
        XCTAssertGreaterThan(difference(upsideDown, fromPlainFlipped: true), mirrorError * 3,
                             "and the test tells a mirror from a turn in the screen's plane")
        XCTAssertEqual(slam.value(time: slam.duration), BoltSlamMotion.Frame())
    }

    func testTheSparksStayCloseToTheFoot() {
        // Sparks fly up and out of the foot inside a small radius, so the toolbar never clips them oddly.
        var farthest: CGFloat = 0
        var drawn = 0
        for step in 0...100 {
            let life = Double(step) / 100
            for spark in BoltSlamMotion.sparks {
                guard let streak = BoltSlamMotion.streak(of: spark, life: life) else { continue }
                drawn += 1
                for point in [streak.tail, streak.head] {
                    farthest = max(farthest, hypot(point.x, point.y))
                    XCTAssertLessThanOrEqual(point.y, 2, "sparks fly up and out of the ground, not into it")
                }
            }
            for point in BoltSlamMotion.crackle(life: life) ?? [] {
                farthest = max(farthest, hypot(point.x, point.y))
            }
        }
        XCTAssertGreaterThan(drawn, 0)
        XCTAssertLessThanOrEqual(farthest, BoltSlamMotion.sparkRadius)
        XCTAssertLessThanOrEqual(BoltSlamMotion.sparkRadius, 8, "a tiny buzz, not a firework")
        XCTAssertTrue(BoltSlamMotion.sparks.allSatisfy { BoltSlamMotion.streak(of: $0, life: 0) == nil },
                      "spent sparks draw nothing")
        XCTAssertNil(BoltSlamMotion.crackle(life: 0))
    }

    // MARK: Proving the frames

    func testTheSlamIsUnderASecondAndEndsAtRest() {
        let slam = BoltSlamMotion.timeline()
        XCTAssertEqual(slam.duration, BoltSlamMotion.duration, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(slam.duration, 0.7)
        XCTAssertLessThanOrEqual(slam.duration, 0.9, "all within a second")
        XCTAssertEqual(slam.value(time: slam.duration), BoltSlamMotion.Frame(), "back at rest when it ends")
        XCTAssertEqual(slam.value(time: slam.duration + 1), BoltSlamMotion.Frame(), "and stays there")

        // Most of the travel is fast (the hop and the slam), the settle soft: from 0.3 s after the impact on it moves
        // less than half a point and nothing lights up.
        let all = samples()
        var travelled: CGFloat = 0, byImpact: CGFloat = 0
        for (previous, sample) in zip(all, all.dropFirst()) {
            travelled += abs(sample.frame.lift - previous.frame.lift)
            if sample.time <= BoltSlamMotion.impactAt { byImpact = travelled }
        }
        XCTAssertGreaterThan(byImpact / travelled, 0.75, "most of the travel is over by the impact")
        for sample in all where sample.time >= BoltSlamMotion.impactAt + 0.3 {
            XCTAssertLessThan(abs(sample.frame.lift), 0.5, "at \(sample.time) s")
            XCTAssertEqual(sample.frame.squash, 1, accuracy: 0.02, "at \(sample.time) s")
            XCTAssertEqual(sample.frame.spark, 0, "at \(sample.time) s")
            XCTAssertEqual(sample.frame.glow, 0, "at \(sample.time) s")
        }
    }

    /// The bolt's colour in the default theme, so the frames don't depend on the test host's theme.
    private let boltColor = ThemePalette.slate.bolt

    /// The bolt as the toolbar draws it after a good sync (in Slate), wearing `effect`, in its 16 × 23 pt frame, in the
    /// middle of a 48 pt square.
    @MainActor
    private func glyph(_ effect: some ViewModifier) -> some View {
        let look = SyncBolt.look(for: .synced(.now), everSignedIn: true)
        return Image(systemName: look.symbol)
            .font(.system(size: SyncBolt.size, weight: .bold))
            .foregroundStyle(boltColor.opacity(look.opacity))
            .modifier(effect)
            .frame(width: SyncBolt.frame.width, height: SyncBolt.frame.height)
            .frame(width: 48, height: 48)
    }

    /// RGBA bytes of `view` rendered at `scale`, and the box (in points of the 48 pt square) of everything it drew.
    @MainActor
    private func render(_ view: some View, scale: CGFloat) throws -> (bytes: [UInt8], ink: CGRect) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let ink = maxX < 0 ? CGRect.null
            : CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                     width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        return (bytes, ink)
    }

    @MainActor
    func testBothStylesLeaveNoMarkAndStayInsideTheBoltsFrameAt1xAnd2x() throws {
        let slam = BoltSlamMotion.timeline()
        let strike = BoltStrikeMotion.timeline(for: .strike)
        let color = boltColor
        // The bolt's 16 × 23 pt frame in the 48 pt square, and a point of slack for antialiasing.
        let frame = CGRect(x: 24 - SyncBolt.frame.width / 2, y: 24 - SyncBolt.frame.height / 2,
                           width: SyncBolt.frame.width, height: SyncBolt.frame.height).insetBy(dx: -1, dy: -1)
        for scale in [1.0, 2.0] {
            let plain = try render(glyph(EmptyModifier()), scale: scale)
            for (name, end) in [
                ("slam", try render(glyph(BoltSlamMotion.Effect(frame: slam.value(time: slam.duration), color: color)), scale: scale)),
                ("strike", try render(glyph(BoltStrikeMotion.Effect(frame: strike.value(time: strike.duration), color: color)), scale: scale)),
                ("slam at rest", try render(glyph(BoltSlamMotion.Effect(frame: .init(), color: color)), scale: scale)),
            ] {
                // The renderer itself rounds a few edge pixels by 1/255 from one render to the next; a mark would be
                // far more than that.
                XCTAssertEqual(end.bytes.count, plain.bytes.count)
                let worst = zip(end.bytes, plain.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
                XCTAssertLessThanOrEqual(worst, 2, "\(name) at \(scale)x: differs from the glyph at rest by up to \(worst)/255")
            }
            var drawn = CGRect.null
            for step in 0...Int((slam.duration * 60).rounded(.up)) {
                let frameAt = slam.value(time: Double(step) / 60)
                let ink = try render(glyph(BoltSlamMotion.Effect(frame: frameAt, color: color)), scale: scale).ink
                drawn = drawn.union(ink)
                XCTAssertTrue(frame.contains(ink), "slam at \(step)/60 s, \(scale)x: \(ink) leaves the bolt's frame \(frame)")
            }
            XCTAssertGreaterThan(drawn.height, plain.ink.height + 2, "it moved")
        }
    }

    /// Both styles frame by frame at 1/60 s steps with their times, at 1x, 2x and 3x, from the same view code the toolbar
    /// uses, plus the slam's keyframe table: attachments of this test, kept when `HITLIST_KEEP_FRAMES` is set
    /// (`TEST_RUNNER_HITLIST_KEEP_FRAMES=1 xcodebuild test … -resultBundlePath R`, then
    /// `xcrun xcresulttool export attachments --path R --output-path <folder>`).
    @MainActor
    func testFrameStripsOfBothStyles() throws {
        let keep = ProcessInfo.processInfo.environment["HITLIST_KEEP_FRAMES"] != nil
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        let color = boltColor
        let slam = BoltSlamMotion.timeline()
        let strike = BoltStrikeMotion.timeline(for: .strike)
        // The slam's spin close up (brief 73): from the crouch to the top of the hop at 1/240 s, the edge-on frames
        // marked, so the quarter and three-quarter turns can be seen.
        let spinStart = BoltSlamMotion.crouch, spinSteps = Int(((BoltSlamMotion.apexAt - spinStart) * 240).rounded(.up))
        let styles: [(name: String, title: String, times: [TimeInterval], view: (TimeInterval) -> AnyView)] = [
            // From the first frame to one past the end, which must look like the first.
            ("slam", "1/60 s steps", (0...Int((slam.duration * 60).rounded(.up)) + 1).map { Double($0) / 60 },
             { AnyView(self.glyph(BoltSlamMotion.Effect(frame: slam.value(time: $0), color: color))) }),
            ("slam-spin", "the spin, 1/240 s steps", (0...spinSteps).map { spinStart + Double($0) / 240 },
             { AnyView(self.glyph(BoltSlamMotion.Effect(frame: slam.value(time: $0), color: color))) }),
            ("strike", "1/60 s steps", (0...Int((strike.duration * 60).rounded(.up)) + 1).map { Double($0) / 60 },
             { AnyView(self.glyph(BoltStrikeMotion.Effect(frame: strike.value(time: $0), color: color))) }),
        ]
        /// Under a slam frame: "edge" where the face is a sliver (edge-on), "mirror" where its other face shows.
        func mark(_ style: String, _ time: TimeInterval) -> (text: String, color: Color)? {
            guard style.hasPrefix("slam") else { return nil }
            let face = slam.value(time: time).face
            if abs(face) < 0.3 { return ("edge", .red) }
            if face < -0.7 { return ("mirror", .orange) }
            return nil
        }
        for style in styles {
            let times = style.times
            let columns = 10
            let sheet = VStack(alignment: .leading, spacing: 4) {
                Text("Bolt \(style.name), \(platform), \(style.title) (rendered by the app's own view code)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    ForEach(Array(stride(from: 0, to: times.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(start..<min(start + columns, times.count), id: \.self) { index in
                                VStack(spacing: 0) {
                                    style.view(times[index])
                                    Text(String(format: "%.3f s", times[index]))
                                        .font(.system(size: 7).monospacedDigit())
                                        .foregroundStyle(.gray)
                                    Text(mark(style.name, times[index])?.text ?? " ")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(mark(style.name, times[index])?.color ?? .clear)
                                }
                            }
                        }
                    }
                }
            }
            .padding(6)
            .background(ThemePalette.slate.background)
            for scale in [1.0, 2.0, 3.0] {
                let renderer = ImageRenderer(content: sheet)
                renderer.scale = scale
                let image = try XCTUnwrap(renderer.cgImage, "\(style.name) at \(scale)x")
                let data = NSMutableData()
                let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                let attachment = XCTAttachment(data: data as Data, uniformTypeIdentifier: "public.png")
                attachment.name = "bolt-\(style.name)-\(platform)-\(Int(scale))x.png"
                attachment.lifetime = keep ? .keepAlways : .deleteOnSuccess
                add(attachment)
            }
            if !style.name.hasSuffix("spin") {
                XCTAssertLessThanOrEqual(times.count, 61, "\(style.name): no more than a second of frames at 60 Hz")
            }
        }

        var table = "| t (s) | spin (° about y) | face | lift (pt, − up) | scale x | scale y | warp | flash | sparks |\n|---|---|---|---|---|---|---|---|---|\n"
        for step in 0...Int((slam.duration * 60).rounded(.up)) {
            let time = Double(step) / 60
            let fx = slam.value(time: time)
            table += String(format: "| %.3f | %.0f | %.2f | %.2f | %.3f | %.3f | %.3f | %.2f | %.2f |\n", time, fx.twirl, fx.face,
                            fx.lift, fx.stretch, fx.squash, fx.warp, fx.glow, fx.spark)
        }
        let attachment = XCTAttachment(string: table)
        attachment.name = "bolt-slam-keyframes-\(platform).md"
        attachment.lifetime = keep ? .keepAlways : .deleteOnSuccess
        add(attachment)
    }

    // MARK: The style (Settings → Extras → Sync bolt)

    func testTheSlamIsTheDefaultAndTheChoiceIsKept() {
        let defaults = UserDefaults(suiteName: "BoltStyleTests-\(UUID().uuidString)")!
        XCTAssertEqual(BoltStyle.selected(in: defaults), .slam, "the cooler one George asked for")
        defaults.set(BoltStyle.strike.rawValue, forKey: BoltStyle.key)
        XCTAssertEqual(BoltStyle.selected(in: defaults), .strike)
        defaults.set("firework", forKey: BoltStyle.key)
        XCTAssertEqual(BoltStyle.selected(in: defaults), .slam, "an unknown value reads as the default")
        XCTAssertEqual(BoltStyle.allCases.map(\.title), ["Strike", "Slam"], "today's first, in the picker")
    }

    func testEachStylePlaysOnlyWhenTheGateSaysAndReduceMotionBlinksForBoth() {
        XCTAssertEqual(BoltStyle.slam.motion(for: .strike), .slam)
        XCTAssertEqual(BoltStyle.strike.motion(for: .strike), .strike)
        for style in BoltStyle.allCases {
            XCTAssertNil(style.motion(for: .none), "the gate decides when, for both")
            XCTAssertEqual(style.motion(for: .blink), .blink, "Reduce Motion gets the blink for both")
        }
    }

    func testPlayingBumpsOnlyTheMotionThatPlays() {
        var player = BoltPlayer()
        player.play(.slam)
        XCTAssertEqual(player, BoltPlayer(strikes: 0, strikeKind: .strike, slams: 1))
        player.play(.blink)
        XCTAssertEqual(player, BoltPlayer(strikes: 1, strikeKind: .blink, slams: 1))
        player.play(.strike)
        XCTAssertEqual(player, BoltPlayer(strikes: 2, strikeKind: .strike, slams: 1))
    }
}
