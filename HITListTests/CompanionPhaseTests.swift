import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 101: Phase, Mocha's ghost, in Mallow's place. A ghost in the "+"'s own colour that lives half inside what it
/// sits on (nothing but the see-through veil at or below the edge), alive at round 20's pace, the weather on a ghost,
/// nothing between it and the "+", and see-through drawing (the veil ink and `seeThrough`) at the right opacity.
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

    /// Drawn in the accent, a little see-through all over, its eyes and glints solid; at and below the edge it sits on
    /// only the veil, so it is inside the "+" (where the veil vanishes) and inside the Mac's field (where it shows).
    func testAGhostHalfInsideWhatItSitsOn() {
        XCTAssertEqual(phase.inks, [.ink, .light, .accent, .veil])
        XCTAssertEqual(phase.seeThrough, 0.25)
        XCTAssertEqual(phase.opacity(.accent), 0.75)
        XCTAssertEqual(phase.opacity(.ink), 1, "its eyes stay solid")
        XCTAssertEqual(phase.opacity(.light), 1, "and their glints")
        XCTAssertEqual(phase.opacity(.veil), CompanionInks.veilOpacity)
        XCTAssertEqual(CompanionCharacter.nod.opacity(.mid), 1, "everyone else is solid")
        XCTAssertEqual(phase.seatRow, 17)
        for frame in phase.frames {
            for row in frame.rows[phase.seatRow...] {
                XCTAssertTrue(row.allSatisfy { $0 == CompanionInk.clear || $0 == "v" }, "\(frame.name): inside, only the veil")
            }
        }
        let rest = phase.rows("rest")!
        // Big eyes low and wide, a glint in each; a tiny mouth; a point above its crown.
        XCTAssertEqual(rest[12].filter { $0 == "l" }.count, 2, "a glint in each eye")
        XCTAssertEqual(rest[11...14].joined().filter { $0 == "k" }.count, 22, "two round eyes, four by four")
        XCTAssertEqual(rest[13].filter { $0 == "k" }.count, 8, "set wide")
        XCTAssertEqual(rest[15].filter { $0 == "k" }.count, 2, "a tiny mouth")
        XCTAssertTrue(rest[3].contains("a"), "its point")
        XCTAssertFalse(rest[0...2].joined().contains("a"), "room to rise")
        // The hem is wavy where it shows (the Mac's field).
        XCTAssertTrue(rest[19].contains("v.v") || rest[19].contains("v.vv"), "a scalloped hem, not a straight edge")
    }

    /// Round 20's pace (brief 100): at least six flickers and four little loops awake, two breaths asleep, four long
    /// routines, a flourish and an answer, in both places.
    func testAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = phase.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }
            XCTAssertGreaterThanOrEqual(flickers.filter { $0.sky == nil }.count, 6, "\(at): six flickers")
            XCTAssertGreaterThanOrEqual(posture.asleep.flickers.count, 2, "\(at): two breaths asleep")
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
            XCTAssertTrue(awake.routines.contains { $0.shakesOff }, "\(at): the heap shaken off")
            XCTAssertTrue(posture.asleep.routines.isEmpty)
            XCTAssertEqual(posture.flourish.first?.frame, "rest")
            XCTAssertFalse(awake.answer.ticks.isEmpty)
            XCTAssertNotEqual(posture.asleep.answer.ticks, awake.answer.ticks, "\(at): woken, not just looking")
        }
        XCTAssertFalse(phase.flourishTurns)
        XCTAssertEqual(phase.plus.awake.gestures.filter(\.flicker).filter { $0.sky == nil }.map(\.name),
                       ["blink", "slowBlink", "sly", "grin", "tongue", "wink", "flick"])
        XCTAssertEqual(phase.plus.awake.routines.map(\.name),
                       ["peek", "blinkOut", "sideEye", "wisp", "glance", "teehee", "popUp", "slip", "boo", "sneak",
                        "float", "catch", "thunder", "flake", "phaseOff", "cool"])
    }

    /// Its tricks: it rises right out of the "+" so its wavy hem shows; it slips under, only its point showing, and
    /// pops up further along; it vanishes but for its eyes.
    func testItsTricks() {
        let awake = phase.plus.awake
        let seat = phase.seatRow
        let risen = phase.rows("risen")!
        XCTAssertTrue(risen[seat - 1].contains("v.v"), "the wavy hem above the edge")
        XCTAssertTrue(risen[seat - 2].contains("a"), "and its body above that")
        XCTAssertTrue(awake.ticks(of: awake.routines.first { $0.name == "popUp" }!).contains { $0.tick.frame == "risen" })
        let fin = phase.rows("fin")!
        XCTAssertLessThanOrEqual(fin[..<seat].joined().filter { $0 != CompanionInk.clear }.count, 20, "only its point")
        XCTAssertFalse(fin[..<seat].joined().contains("k"), "no eyes above the edge")
        let along = phase.rows("along")!
        XCTAssertEqual(phase.rightmostColumn("along"), phase.rightmostColumn("rest") - 3, "popped up further along")
        XCTAssertTrue(along[13].contains("k"))
        // Phased: everything but its eyes is the veil.
        let gone = phase.rows("gone")!.joined()
        XCTAssertFalse(gone.contains("a"))
        XCTAssertTrue(gone.contains("k") && gone.contains("l"), "its eyes stay")
        XCTAssertTrue(phase.plus.flourish.map(\.frame).contains("gone"))
    }

    /// The weather on a ghost: rain beads on it and a drop falls straight through it (no shake-off: it isn't wet);
    /// thunder makes it jump out; snow piles on its point until it phases and the heap falls through it; heat makes it
    /// droop like wax and sink into the cool "+". Nothing in the air but a drop or a flake it touches.
    func testTheWeatherOnAGhost() {
        let awake = phase.plus.awake
        let fall = awake.gesture(named: "fall")!
        XCTAssertEqual(fall.sky, .rain)
        XCTAssertTrue(fall.flicker)
        for tick in fall.ticks {
            XCTAssertEqual(phase.difference(tick.frame, awake.rain!), 1, "\(tick.frame): one drop")
        }
        XCTAssertEqual(awake.routines.first { $0.sky == .storm }?.name, "thunder")
        XCTAssertTrue(phase.rows("stormJump")![phase.seatRow - 1].contains("v.v"), "out of the + with a jump")
        // Snow: a dusting, a cap, a heap, each more snow than the last, the seat left alone.
        func snow(_ frame: String) -> Int { phase.rows(frame)!.joined().filter { $0 == "l" }.count }
        let piles = [awake.snow!] + awake.snowDeep
        XCTAssertEqual(piles, ["snow", "snowCap", "snowHeap"])
        for (a, b) in zip(piles, piles.dropFirst()) {
            XCTAssertGreaterThan(snow(b), snow(a), "\(b) deeper than \(a)")
            XCTAssertEqual(Array(phase.rows(a)![(phase.seatRow - 1)...]), Array(phase.rows(b)![(phase.seatRow - 1)...]))
        }
        let shake = awake.routines.first { $0.shakesOff }!
        XCTAssertEqual(shake.name, "phaseOff")
        XCTAssertTrue(phase.canDraw(shake, in: .snow, mode: awake, depth: 2))
        XCTAssertFalse(phase.canDraw(shake, in: .snow, mode: awake, depth: 0), "only from the deepest pile")
        XCTAssertTrue(phase.rows("heapFall1")!.joined().contains("v"), "phased while the heap falls through it")
        // Heat: its point slumped, a drip down its side, and it sinks into the cool button.
        XCTAssertEqual(awake.heat, "heat")
        XCTAssertFalse(phase.rows("heat")![3].contains("a"), "its point slumped")
        XCTAssertEqual(awake.gesture(named: "drip")?.sky, .heat)
        XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "cool")
        // Every everyday routine that leaves the weather's pixels alone plays in it: at least one in each.
        let everyday = awake.routines.filter { $0.sky == nil }
        for weather in [CompanionLook.Weather.rain, .snow, .heat] {
            XCTAssertTrue(everyday.contains { phase.plays($0, in: weather, mode: awake) }, "one plays in \(weather)")
        }
    }

    /// Asleep it sinks to its eyes, shut, its point flopped over like a nightcap; nothing above its eyes but its head.
    func testAsleepInTheButton() {
        let sleep = phase.rows("sleep")!
        XCTAssertEqual(sleep.joined().filter { $0 == "l" }.count, 3, "the sheen on its crown, no glints: eyes shut")
        XCTAssertEqual(sleep.joined().filter { $0 == "k" }.count, 8, "two eyes shut in soft curves")
        XCTAssertGreaterThan(phase.difference("sleep", "rest"), 40, "a pose of its own")
        XCTAssertEqual(phase.plus.asleep.gestures.map(\.name), ["breathe", "snuggle", "nod"])
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
    /// in, 3 pt down): the first is Phase's, the second the "+"'s (its veil inside the button takes no tap).
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
            XCTAssertEqual(inks.hex[.veil], palette.hex.accent, "the veil is the accent")
        }
    }

    /// At 3x every device pixel is one of its inks at that ink's opacity, or clear: crisp squares, see-through where
    /// it should be and nowhere else.
    func testDrawnCrispAtItsOpacity() throws {
        for palette in [ThemePalette.mocha, .slate] {
            let inks = CompanionInks(palette: palette)
            let flourish = phase.field.flourish
            for name in ["rest", "risen", flourish[flourish.count / 2].frame] {
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
