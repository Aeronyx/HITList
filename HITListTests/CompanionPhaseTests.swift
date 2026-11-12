import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 101, redrawn in brief 110: Phase, Mocha's ghost, in Mallow's place. A little cloth ghost in the "+"'s own
/// colour that hovers wholly on top of what it sits on (nothing hangs over it or lies behind it), eyes of its own,
/// alive at round 20's pace, weather that passes through it, nothing between it and the "+", and see-through drawing
/// (`seeThrough`, and the veil while it phases) at the right opacity.
/// `CompanionSpriteTests` also runs every check that holds for every companion on it.
@MainActor
final class CompanionPhaseTests: XCTestCase {
    let phase = CompanionCharacter.phase

    func testMochaHasPhaseAndMallowIsGone() {
        XCTAssertEqual(CompanionCast.character(forTheme: "mocha", launch: .none).id, "phase")
        XCTAssertEqual(CompanionCharacter.named("phase")?.name, "Phase")
        XCTAssertNil(CompanionCharacter.named("mallow"))
        XCTAssertFalse(CompanionCast.byTheme.values.contains("mallow"))
        // An old `-companion mallow` falls back to the theme's; a theme with no companion of its own borrows Nod.
        let old = CompanionLaunchOptions(arguments: ["-companion", "mallow"])
        XCTAssertEqual(CompanionCast.character(forTheme: "mocha", launch: old).id, "phase")
        XCTAssertEqual(CompanionCast.character(forTheme: "a-theme-not-drawn-yet", launch: .none).id, "nod")
        XCTAssertEqual(phase.problems, [])
    }

    /// Brief 110: a little cloth ghost, drawn in the accent with the accent's shade for its folds, a quarter
    /// see-through all over, its eyes and lights solid; nothing hangs (seat row 20), so nothing of it lies over the
    /// button's face or behind it, and no still has the veil (no darker band on the "+").
    func testAClothGhostOnTopOfWhatItSitsOn() {
        XCTAssertEqual(phase.inks, [.ink, .light, .accent, .accentDark, .veil])
        XCTAssertEqual(phase.seeThrough, 0.25)
        XCTAssertEqual(phase.opacity(.accent), 0.75)
        XCTAssertEqual(phase.opacity(.accentDark), 0.75, "its folds see-through like the rest of its cloth")
        XCTAssertEqual(phase.opacity(.ink), 1, "its pupils stay solid")
        XCTAssertEqual(phase.opacity(.light), 1, "and the light in its eyes")
        XCTAssertEqual(phase.opacity(.veil), CompanionInks.veilOpacity)
        XCTAssertEqual(CompanionCharacter.nod.opacity(.mid), 1, "everyone else is solid")
        XCTAssertEqual(phase.seatRow, phase.height, "nothing hangs over the edge it sits on")
        for frame in phase.frames {
            XCTAssertFalse(frame.rows.joined().contains(where: CompanionInk.isBehind), "\(frame.name): nothing behind the host")
        }
        for place in CompanionPlace.allCases {
            let posture = phase.posture(place)
            for still in posture.awake.stills + posture.asleep.stills {
                XCTAssertFalse(phase.rows(still)!.joined().contains("v"), "\(still): no veil, no dim band on the button")
            }
        }
        let rest = phase.rows("rest")!.map(Array.init)
        func span(_ y: Int) -> ClosedRange<Int> {
            let cols = rest[y].indices.filter { rest[y][$0] != CompanionInk.clear }
            return cols.first!...cols.last!
        }
        // Its longest point rests on the bar's top: only it is on the last row.
        XCTAssertEqual(span(19), 8...10, "the longest point, on the bar")
        XCTAssertEqual(rest[19].filter { $0 != CompanionInk.clear }.count, 3)
        // A hanging cloth, not a figure: a one-pixel pinch under the head, then a skirt that flares to the head's width
        // (12 to 14 pixels) and falls into points of different lengths, the right corner lifted, folds shaded in.
        XCTAssertEqual(span(12).count, span(11).count - 2, "a one-pixel pinch each side, where it would be tied")
        XCTAssertGreaterThanOrEqual(span(13).count, span(11).count, "and the cloth flares out again")
        XCTAssertTrue((12...16).contains(span(15).count), "the skirt as wide as the head")
        XCTAssertEqual(phase.rightmostColumn("rest"), 19, "the corner lifted out")
        XCTAssertTrue(rest[14][19] != CompanionInk.clear && rest[17][19] == CompanionInk.clear, "lifted, not hanging")
        XCTAssertTrue(rest[18].contains("a") && !rest[18][12...].contains("a"), "a shorter point beside the longest")
        XCTAssertGreaterThanOrEqual(rest[13...].joined().filter { $0 == "r" }.count, 8, "folds and the corner's underside")
        // Eyes of its own (round 22): pale, a dusky iris, a dark pupil and a light in each; not Button's round black eye.
        for x in [7, 13] {
            let eye = (8...10).flatMap { y in rest[y][x..<(x + 3)] }
            XCTAssertEqual(eye.filter { $0 == "k" }.count, 1, "a small pupil")
            XCTAssertEqual(eye.filter { $0 == "l" }.count, 2, "pale, with a light")
            XCTAssertEqual(eye.filter { $0 == "r" }.count, 2, "a dusky iris")
        }
        XCTAssertEqual(rest[11...12].joined().filter { $0 == "k" }.count, 3, "a small smile")
        // Its own point, curling back, above its crown, with a row of room to rise.
        XCTAssertTrue(rest[2].contains("a") && rest[3].contains("a"), "its point")
        XCTAssertFalse(rest[0...1].joined().contains("a"), "room to rise")
    }

    /// Round 20's pace (brief 100): at least six flickers and four little loops awake, three breaths asleep, four long
    /// routines, a flourish and an answer, in both places.
    func testAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = phase.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }
            XCTAssertGreaterThanOrEqual(flickers.filter { $0.sky == nil }.count, 6, "\(at): six flickers")
            XCTAssertGreaterThanOrEqual(posture.asleep.flickers.count, 3, "\(at): three breaths asleep")
            let little = awake.routines.filter(\.little)
            XCTAssertGreaterThanOrEqual(little.count, 4, "\(at): four little loops")
            for loop in little {
                XCTAssertTrue((2...4).contains(loop.moves), "\(at) \(loop.name): \(loop.moves) moves")
                XCTAssertLessThanOrEqual(phase.duration(of: loop, mode: awake), 2.5, "\(at) \(loop.name)")
                XCTAssertNil(loop.sky, "\(at) \(loop.name): an everyday idle")
            }
            let long = awake.routines.filter { !$0.little && $0.sky == nil }
            XCTAssertGreaterThanOrEqual(long.count, 4, "\(at): four long routines")
            for routine in long {
                XCTAssertTrue((3...7).contains(phase.duration(of: routine, mode: awake)), "\(at) \(routine.name)")
                XCTAssertTrue((4...9).contains(routine.moves), "\(at) \(routine.name)")
            }
            for sky in [CompanionSky.rain, .storm, .snow, .heat] {
                XCTAssertTrue(awake.routines.contains { $0.sky == sky }, "\(at): one for \(sky)")
            }
            XCTAssertTrue(awake.routines.contains { $0.shakesOff }, "\(at): the drift dipped through")
            XCTAssertTrue(posture.asleep.routines.isEmpty)
            XCTAssertEqual(posture.flourish.first?.frame, "rest")
            XCTAssertFalse(awake.answer.ticks.isEmpty)
            XCTAssertNotEqual(posture.asleep.answer.ticks, awake.answer.ticks, "\(at): woken, not just looking")
        }
        XCTAssertFalse(phase.flourishTurns)
        XCTAssertEqual(phase.plus.awake.gestures.filter(\.flicker).filter { $0.sky == nil }.map(\.name),
                       ["blink", "slowBlink", "sly", "look", "grin", "flick", "corner", "otherCorner"])
        XCTAssertEqual(phase.plus.awake.routines.map(\.name),
                       ["blinkOut", "sideEye", "bob", "wisp", "teehee", "duck", "boo", "float", "through", "sneak", "wave",
                        "watch", "thunder", "flake", "dip", "cool"])
    }

    /// Its tricks: going through the bar is drawn by leaving out what is below its top (a ghost through a wall), never
    /// by a dim band; it cruises along under it with only its point showing and pops up further along; it vanishes but
    /// for its eyes; it bobs, hovering.
    func testItsTricks() {
        let awake = phase.plus.awake
        let rest = phase.rows("rest")!
        // Sunk to its eyes: its upper rows, moved down, cut at the bar's top, all of it the cloth's own inks.
        let sunk = phase.rows("sinkEyes")!
        XCTAssertEqual(sunk[19].filter { $0 != CompanionInk.clear }.count, rest[10].filter { $0 != CompanionInk.clear }.count,
                       "the row at its eyes is on the bar, the rest of it left out below")
        XCTAssertFalse(sunk.joined().contains("v"))
        let fin = phase.rows("fin")!
        XCTAssertLessThanOrEqual(fin.joined().filter { $0 != CompanionInk.clear }.count, 6, "only its point")
        XCTAssertFalse(fin.joined().contains("k"), "no eyes above the bar")
        XCTAssertEqual(phase.rightmostColumn("along"), phase.rightmostColumn("rest") - 3, "popped up further along")
        let through = awake.ticks(of: awake.routines.first { $0.name == "through" }!).map(\.tick.frame)
        XCTAssertTrue(through.contains("fin") && through.contains("along"))
        // Phased: everything but its eyes is gone.
        let gone = phase.rows("gone")!.joined()
        XCTAssertFalse(gone.contains("a"), "no cloth")
        XCTAssertTrue(gone.contains("k") && gone.contains("l"), "its eyes stay")
        XCTAssertTrue(phase.rows("fade")!.joined().contains("v"), "see-through all over as it goes")
        XCTAssertTrue(phase.plus.flourish.map(\.frame).contains("gone"))
        // It hovers: the bob lifts all of it a pixel off the bar.
        XCTAssertEqual(phase.rows("bob")!, Array(rest[1...]) + [String(repeating: ".", count: 20)])
    }

    /// Weather passes through a ghost (brief 110): nothing wets or covers it. In the rain it holds out a corner and
    /// looks up, and drops fall through that corner and through it (no beads, no shake-off); thunder makes it jump;
    /// snow never settles on it, but gathers on the bar under its hem, deeper each time, while it hangs higher and
    /// looks down at it, and at the deepest it dips through the drift; on a hot day it hangs limp like washing.
    func testTheWeatherPassesThroughAGhost() {
        let awake = phase.plus.awake
        let rain = awake.rain!
        let snowInks: Set<Character> = ["s", "b", "c"]
        XCTAssertLessThanOrEqual(phase.difference(rain, "rest"), 16, "the rain changes only its look and its corner")
        XCTAssertFalse(phase.rows(rain)!.joined().contains { snowInks.contains($0) })
        let through = awake.gesture(named: "through")!
        XCTAssertEqual(through.sky, .rain)
        XCTAssertTrue(through.flicker)
        for tick in through.ticks {
            XCTAssertLessThanOrEqual(phase.difference(tick.frame, rain), 8, "\(tick.frame): one drop, and its eyes")
        }
        let watch = awake.routines.first { $0.name == "watch" }!
        XCTAssertEqual(watch.sky, .rain)
        XCTAssertTrue(phase.rows("rainDrop1")![6].contains("l"), "the drop shows lighter inside it")
        XCTAssertEqual(phase.rows("rainDrop4")![19].filter { $0 == "l" }.count, 1, "and leaves by its hem onto the bar")
        XCTAssertEqual(awake.routines.first { $0.sky == .storm }?.name, "thunder")
        // Snow: none of it on the ghost. Take the snow away and what is left is the ghost, raised.
        let rest = phase.rows("rest")!
        let blankRow = String(repeating: ".", count: 20)
        let piles = [awake.snow!] + awake.snowDeep
        XCTAssertEqual(piles, ["snow", "snowDeep1", "snowDeep2"])
        let lifts = [1, 1, 1]
        var previous = -1
        for (pile, lift) in zip(piles, lifts) {
            let rows = phase.rows(pile)!
            let bare = rows.map { String($0.map { snowInks.contains($0) ? CompanionInk.clear : $0 }) }
            let raised = Array(rest[lift...]) + Array(repeating: blankRow, count: lift)
            let face = bare.indices.filter { bare[$0] != raised[$0] }
            XCTAssertTrue(face.allSatisfy { (5...12).contains($0) }, "\(pile): the ghost raised \(lift), looking down; rows \(face)")
            let count = rows.joined().filter { snowInks.contains($0) }.count
            XCTAssertGreaterThan(count, previous, "\(pile): deeper than the last")
            previous = count
            for y in rows.indices where rows[y].contains(where: { snowInks.contains($0) }) {
                XCTAssertGreaterThanOrEqual(y, 17, "\(pile): the drift is on the bar, not on it")
            }
            XCTAssertEqual(rows[19], phase.rows("snow")![19], "\(pile): the line it sits on is the first drift's")
            // The recipe's three tones, and nothing of the old snow (its light ink) under it.
            XCTAssertTrue(["s", "b", "c"].allSatisfy { rows.joined().contains($0) }, pile)
        }
        let dip = awake.routines.first { $0.shakesOff }!
        XCTAssertEqual(dip.name, "dip")
        XCTAssertTrue(phase.canDraw(dip, in: .snow, mode: awake, depth: 2))
        XCTAssertFalse(phase.canDraw(dip, in: .snow, mode: awake, depth: 0), "only from the deepest drift")
        XCTAssertTrue(phase.rows("dip4")![0].contains("s"), "it comes up with one flake on its point")
        XCTAssertTrue(phase.rows("dipFlake0")![6].contains("s"), "which falls through it")
        // Heat: limp like washing, and it sinks into the cool button.
        XCTAssertEqual(awake.heat, "heat")
        XCTAssertFalse(phase.rows("heat")![2].contains("a"), "its point flopped over")
        XCTAssertEqual(awake.gesture(named: "puff")?.sky, .heat)
        XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "cool")
        // Its flickers and its answer are drawn for every weather's still, so it is as alive in the weather.
        for still in [rain, "heat", "snow", "snowDeep1", "snowDeep2"] {
            for name in ["blink", "sly", "lookL", "lookR", "grin", "flick", "winkTongue", "wink"] {
                XCTAssertNotNil(phase.index["\(name)@\(still)"], "\(name)@\(still)")
            }
        }
    }

    /// Asleep it slumps into a soft heap of cloth on the bar, its point flopped over, the closed face showing.
    func testAsleepAHeapOfCloth() {
        let sleep = phase.rows("sleep")!
        XCTAssertEqual(sleep.joined().filter { $0 == "l" }.count, 3, "the sheen on its crown, no light in shut eyes")
        XCTAssertEqual(sleep[13].filter { $0 == "r" }.count, 6, "two eyes shut")
        XCTAssertEqual(sleep[14].filter { $0 == "k" }.count, 2, "a small mouth")
        XCTAssertTrue(sleep[10].hasSuffix("aa"), "its point flopped over")
        XCTAssertFalse(sleep[0...7].joined().contains("a"), "a heap, low")
        XCTAssertGreaterThan(phase.difference("sleep", "rest"), 40, "a pose of its own")
        XCTAssertEqual(phase.plus.asleep.gestures.map(\.name), ["breathe", "nod", "murmur"])
    }

    /// Nothing between it and the "+" (brief 100's seat, until its check exists): on the glass capsule (the lower of
    /// SwiftUI's continuous and circular shapes at each point), every column resting on the edge line reaches the curve
    /// in every still, within under half a point; on the flat field every one sits on the line.
    func testNothingBetweenItAndThePlus() {
        let size = FloatingAddButton.size
        let rect = CGRect(origin: .zero, size: size)
        let shapes = [Capsule(style: .continuous).path(in: rect), Capsule(style: .circular).path(in: rect)]
        // The top edge every quarter point: how far down the first point of both shapes is.
        var tops: [Int: CGFloat] = [:]
        for q in 0...Int(size.width * 4) {
            let x: CGFloat = CGFloat(q) / 4
            var y: CGFloat = 0
            while y < size.height / 2, !shapes.allSatisfy({ $0.contains(CGPoint(x: x, y: y)) }) { y += 0.02 }
            tops[q] = y
        }
        func top(_ x: CGFloat) -> CGFloat { tops[Int((x * 4).rounded())] ?? size.height / 2 }
        let p = CompanionCharacter.pointsPerPixel
        let offset = CompanionPerch.offset(phase, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(phase.width) * p
        let boxLeft: CGFloat = size.width - spriteWidth + offset.width
        var stills: [String] = []
        for mode in [phase.plus.awake, phase.plus.asleep] { stills.append(contentsOf: mode.stills) }
        XCTAssertEqual(stills.count, 8)
        for name in stills {
            let rows = phase.rows(name)!.map(Array.init)
            let seat = phase.seatRow
            for c in 0..<phase.width where rows[seat - 1][c] != CompanionInk.clear {
                var y = seat - 1
                while y + 1 < rows.count, rows[y + 1][c] != CompanionInk.clear { y += 1 }
                let bottom: CGFloat = CGFloat(y + 1 - seat) * p
                let x0: CGFloat = boxLeft + CGFloat(c) * p
                var lowest: CGFloat = 0
                for k in 0...8 {
                    let step: CGFloat = CGFloat(k) * p / 8
                    lowest = max(lowest, top(x0 + step))
                }
                let gap: CGFloat = lowest - bottom
                XCTAssertLessThanOrEqual(gap, 0.45, "\(name) column \(c): \(gap) pt of background under it")
            }
        }
    }

    /// The UI tests tap just above the "+" (24 pt in from its right edge, 14 pt up) and just under the companion (22 pt
    /// in, 3 pt down): the first is Phase's, the second the "+"'s.
    func testTheUITestsTapsLandOnItAndOnThePlus() {
        let size = FloatingAddButton.size
        let rest = phase.index[phase.plus.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: phase.drawn[rest], width: phase.width, mirrored: false,
                                                belowRow: phase.seatRow)
        let offset = CompanionPerch.offset(phase, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(phase.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let onIt = CGPoint(x: size.width - 24 - left, y: -14 - offset.height)
        let underIt = CGPoint(x: size.width - 22 - left, y: 3 - offset.height)
        XCTAssertTrue(shape.contains(onIt), "a tap on it is its own")
        XCTAssertFalse(shape.contains(underIt), "a tap under it is the +'s")
    }

    /// Its body, over every theme's window, stands apart from it (a little see-through, so mixed toward it), and its
    /// eyes (the window's colour) stand apart from its body.
    func testItReadsOnEveryTheme() {
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            for ground in [palette.hex.background, palette.hex.surface, palette.hex.elevated] {
                let body = CompanionInks.mix(inks.hex[.accent]!, ground, phase.seeThrough)
                XCTAssertGreaterThan(contrast(body, ground), 2.5, "\(palette.id) body on \(ground)")
                XCTAssertGreaterThan(contrast(body, inks.hex[.ink]!), 2.5, "\(palette.id) eyes on its body")
            }
            XCTAssertEqual(inks.hex[.veil], CompanionInks.mix(palette.hex.accent, palette.hex.background, CompanionInks.veilDusk),
                           "the veil is the accent dimmed toward the background")
            // Its folds (the accent's shade) stand apart from its cloth.
            let fold = CompanionInks.mix(inks.hex[.accentDark]!, palette.hex.background, phase.seeThrough)
            XCTAssertGreaterThan(contrast(CompanionInks.mix(inks.hex[.accent]!, palette.hex.background, phase.seeThrough), fold), 1.5,
                                 "\(palette.id): its folds read")
        }
    }

    /// At 3x every device pixel is one of its inks at that ink's opacity, or clear: crisp squares, see-through where
    /// it should be and nowhere else.
    func testDrawnCrispAtItsOpacity() throws {
        for palette in [ThemePalette.mocha, .slate] {
            let inks = CompanionInks(palette: palette)
            let flourish = phase.field.flourish
            for name in ["rest", "boo", "snowDeep2", flourish[flourish.count / 2].frame] {
                let frame = phase.index[name]!
                let pose = CompanionPose(frame: frame, mirrored: false)
                let pixels = try render(CompanionSprite(character: phase, pose: pose, inks: inks), scale: 3)
                XCTAssertEqual(pixels.width, phase.width * 6)
                let rows = phase.frames[frame].rows.map(Array.init)
                for y in 0..<phase.height {
                    for x in 0..<phase.width {
                        let c = rows[y][x]
                        let px = pixels.at(x * 6 + 3, y * 6 + 3)
                        guard c != CompanionInk.clear else {
                            XCTAssertEqual(px.alpha, 0, "\(name) \(x),\(y)")
                            continue
                        }
                        let ink: CompanionInk = CompanionInk(rawValue: c)!
                        let opacity: Double = phase.opacity(ink)
                        let alpha: Int = Int((opacity * 255).rounded())
                        XCTAssertLessThanOrEqual(abs(px.alpha - alpha), 2, "\(palette.id) \(name) \(x),\(y) \(c)")
                        // Premultiplied: the ink's colour times its opacity.
                        let want: [Int] = CompanionInks.rgb(inks.hex[ink]!).map { Int((Double($0) * opacity).rounded()) }
                        for (have, need) in zip(px.rgb, want) {
                            XCTAssertLessThanOrEqual(abs(have - need), 3, "\(palette.id) \(name) \(x),\(y) \(c)")
                        }
                        // A whole square: the block's corners are the same pixel.
                        let corner = pixels.at(x * 6, y * 6)
                        XCTAssertLessThanOrEqual(abs(corner.alpha - px.alpha), 2, "\(name) \(x),\(y): crisp")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func at(_ x: Int, _ y: Int) -> (rgb: [Int], alpha: Int) {
            let row: Int = y * width
            let i: Int = (row + x) * 4
            let r = Int(bytes[i])
            let g = Int(bytes[i + 1])
            let b = Int(bytes[i + 2])
            let a = Int(bytes[i + 3])
            return ([r, g, b], a)
        }
    }

    private func render<V: View>(_ view: V, scale: CGFloat) throws -> Pixels {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, bytes: bytes)
    }

    private func linear(_ v: Int) -> Double {
        let s: Double = Double(v) / 255
        if s <= 0.03928 { return s / 12.92 }
        let shifted: Double = (s + 0.055) / 1.055
        return pow(shifted, 2.4)
    }

    private func luminance(_ hex: String) -> Double {
        let c: [Int] = CompanionInks.rgb(hex)
        let r: Double = 0.2126 * linear(c[0])
        let g: Double = 0.7152 * linear(c[1])
        let b: Double = 0.0722 * linear(c[2])
        return r + g + b
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        let light: Double = max(la, lb) + 0.05
        let dark: Double = min(la, lb) + 0.05
        return light / dark
    }
}
