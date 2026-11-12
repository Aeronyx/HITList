import XCTest
import SwiftUI
@testable import HITList

/// Round 24 (brief 121): the engine's light and fade. A character names the inks that give light (`glow`), each casting a
/// soft halo of its own colour over the body and under its crisp pixels, never cut at the sprite's edge, never laid out;
/// a frame says how much of the body is there (`fade`) and how bright the light is (`light`); a see-through body may
/// thin down its rows (`thinning`); Reduce Transparency draws the body solid and fades it no lower than half. A
/// character with none of it draws exactly as before.
@MainActor
final class CompanionLightTests: XCTestCase {
    typealias Frame = CompanionCharacter.Frame

    // MARK: - As before

    /// Nod and Button name no light and no fade: every pixel of their stills at 3x is its ink at `opacity(ink)` as it was
    /// before round 24, in whole crisp squares, nothing drawn outside them, at the sprite's own size; and the new opacity
    /// gives the old one for every run of every drawn pose, with Reduce Transparency too.
    func testACharacterWithNoLightDrawsAsBefore() throws {
        for character in [CompanionCharacter.nod, .button] {
            XCTAssertTrue(character.glow.isEmpty, character.id)
            XCTAssertEqual(character.thinning, 0, character.id)
            XCTAssertEqual(character.looks.count, character.drawn.count, character.id)
            for (pose, runs) in character.drawn.enumerated() {
                XCTAssertEqual(character.looks[pose].fade, 1, "\(character.id) \(pose)")
                XCTAssertEqual(character.haloStrength(pose: pose), 0, "\(character.id) \(pose)")
                for run in runs {
                    XCTAssertEqual(character.opacity(run.ink, pose: pose, row: run.y), character.opacity(run.ink))
                    if run.ink != .veil {
                        XCTAssertEqual(character.opacity(run.ink, pose: pose, row: run.y, reduceTransparency: true),
                                       character.opacity(run.ink), "\(character.id): solid already")
                    }
                }
            }
            let inks = CompanionInks(palette: .slate)
            let mode = character.plus.awake
            var stills = [mode.rest, character.plus.asleep.rest]
            for still in [mode.rain, mode.snow] { if let still { stills.append(still) } }
            for name in stills {
                let frame = try XCTUnwrap(character.index[name])
                let pose = CompanionPose(frame: frame, mirrored: false)
                let pixels = try render(CompanionSprite(character: character, pose: pose, inks: inks), scale: 3)
                XCTAssertEqual(pixels.width, character.width * 6, "\(character.id): its own size")
                XCTAssertEqual(pixels.height, character.height * 6)
                let rows = character.frames[frame].rows.map(Array.init)
                for y in 0..<character.height {
                    for x in 0..<character.width {
                        let at = "\(character.id) \(name) \(x),\(y)"
                        let px = pixels.at(x * 6 + 3, y * 6 + 3)
                        // Clear, or behind a host there is none of here: nothing drawn.
                        guard let letter = CompanionInk.read(rows[y][x]), !letter.behind else {
                            XCTAssertEqual(px.alpha, 0, at)
                            continue
                        }
                        let opacity: Double = character.opacity(letter.ink)
                        XCTAssertLessThanOrEqual(abs(px.alpha - Int((opacity * 255).rounded())), 2, at)
                        let want: [Int] = CompanionInks.rgb(inks.hex[letter.ink]!).map { Int((Double($0) * opacity).rounded()) }
                        for (have, need) in zip(px.rgb, want) { XCTAssertLessThanOrEqual(abs(have - need), 3, at) }
                        let corner = pixels.at(x * 6, y * 6)
                        XCTAssertLessThanOrEqual(abs(corner.alpha - px.alpha), 2, "\(at): crisp")
                    }
                }
            }
        }
    }

    /// Light is Phase's eyes and Glim's lantern this round, nobody else's (COMMON, round 24).
    func testOnlyPhaseAndGlimGiveLight() {
        XCTAssertEqual(CompanionCharacter.phase.glow, [.light])
        XCTAssertEqual(CompanionCharacter.glim.glow, [.warm])
        for character in CompanionCharacter.all where !["phase", "glim"].contains(character.id) {
            XCTAssertTrue(character.glow.isEmpty, character.id)
        }
        // Glim's lantern is lit awake and turned down asleep.
        let glim = CompanionCharacter.glim
        XCTAssertEqual(glim.haloStrength(pose: glim.index[glim.plus.awake.rest]!), CompanionCharacter.glowStrength)
        XCTAssertEqual(glim.haloStrength(pose: glim.index[glim.plus.asleep.rest]!),
                       CompanionCharacter.glowStrength * CompanionCharacter.asleepLight)
    }

    // MARK: - Light

    /// A lantern at the sprite's right edge: its halo reaches past the edge (not cut there), the sprite is laid out at
    /// its own size, the lantern's pixels stay crisp and solid, a dark pixel beside it stays dark, the body next to it
    /// is lit and the body far from it is as it was.
    func testAGlowCastsAHaloBeyondTheSprite() throws {
        let lit = Self.creature(Self.lantern, glow: [.light])
        let dark = Self.creature(Self.lantern)
        XCTAssertEqual(lit.problems, [])
        let inks = CompanionInks(palette: .mocha)
        let pose = CompanionPose(frame: 0, mirrored: false)
        let alone = try render(CompanionSprite(character: lit, pose: pose, inks: inks), scale: 3)
        XCTAssertEqual(alone.width, 120, "laid out at the sprite's own size")
        XCTAssertEqual(alone.height, 120)
        let pad: CGFloat = 10
        let shown = try render(CompanionSprite(character: lit, pose: pose, inks: inks).padding(pad), scale: 3)
        let plain = try render(CompanionSprite(character: dark, pose: pose, inks: inks).padding(pad), scale: 3)
        // Device pixel of sprite pixel (x, y) at its centre, with the padding.
        func at(_ x: Double, _ y: Double) -> (Int, Int) { (Int((pad + x * 2) * 3), Int((pad + y * 2) * 3)) }
        // Past the right edge, beside the lantern: light, in the lantern's colour; nothing there without the glow.
        let (ex, ey) = at(20.4, 9)
        let beyond = shown.at(ex, ey)
        XCTAssertGreaterThan(beyond.alpha, 8, "the halo is not cut at the sprite's edge")
        XCTAssertEqual(plain.at(ex, ey).alpha, 0)
        let light = CompanionInks.rgb(inks.hex[.light]!)
        let premultiplied = light.map { Double($0) * Double(beyond.alpha) / 255 }
        for (have, need) in zip(beyond.rgb, premultiplied) {
            XCTAssertLessThanOrEqual(abs(Double(have) - need), 6, "its own colour")
        }
        // The lantern itself: crisp and solid.
        let (lx, ly) = at(18.5, 8.5)
        XCTAssertEqual(shown.at(lx, ly).rgb, light)
        XCTAssertEqual(shown.at(lx, ly).alpha, 255)
        XCTAssertEqual(shown.at(lx - 2, ly - 2).rgb, light, "a whole square")
        // A dark pixel beside it stays dark (the halo goes under it).
        let (kx, ky) = at(18.5, 10.5)
        XCTAssertEqual(shown.at(kx, ky).rgb, CompanionInks.rgb(inks.hex[.ink]!))
        // The body beside it is lit; far from it, as it was.
        let (nx, ny) = at(17.5, 8.5)
        XCTAssertGreaterThan(shown.at(nx, ny).rgb.reduce(0, +), plain.at(nx, ny).rgb.reduce(0, +) + 30, "lit beside it")
        let (fx, fy) = at(3.5, 12.5)
        XCTAssertEqual(shown.at(fx, fy).rgb, plain.at(fx, fy).rgb, "as it was far from it")
        XCTAssertEqual(shown.at(fx, fy).alpha, plain.at(fx, fy).alpha)
    }

    /// A frame dims, puts out or flares the light; a frame drawn only asleep has it turned down; no glow, no halo.
    func testTheLightDimsSwellsAndSleeps() throws {
        let frames = [
            Frame(name: "rest", rows: Self.lantern),
            Frame(name: "out", light: 0, rows: Self.lantern),
            Frame(name: "flare", light: 1.5, rows: Self.lantern),
            Frame(name: "dream", rows: Self.lantern),
        ]
        let character = Self.creature(frames, glow: [.light], asleep: "dream")
        XCTAssertEqual(character.problems, [])
        func strength(_ name: String) -> Double { character.haloStrength(pose: character.index[name]!) }
        XCTAssertEqual(strength("rest"), CompanionCharacter.glowStrength)
        XCTAssertEqual(strength("out"), 0)
        XCTAssertEqual(strength("flare"), 1.5 * CompanionCharacter.glowStrength, accuracy: 1e-9)
        XCTAssertEqual(strength("dream"), CompanionCharacter.asleepLight * CompanionCharacter.glowStrength,
                       accuracy: 1e-9, "asleep the light is turned down")
        XCTAssertEqual(Self.creature(frames, asleep: "dream").haloStrength(pose: 0), 0, "no glow, no halo")
        // Put out, it draws as a character with no glow does.
        let inks = CompanionInks(palette: .tokyo)
        let out = try render(CompanionSprite(character: character, pose: .init(frame: character.index["out"]!, mirrored: false),
                                             inks: inks).padding(10), scale: 2)
        let none = try render(CompanionSprite(character: Self.creature(Self.lantern), pose: .init(frame: 0, mirrored: false),
                                              inks: inks).padding(10), scale: 2)
        XCTAssertEqual(out.bytes, none.bytes)
    }

    // MARK: - Fade

    /// A frame's fade multiplies the body (its inks and the veil); eyes, glints and the weather stay solid; a composite
    /// takes its gesture frame's fade; Reduce Transparency draws the body solid and never below half.
    func testABodyFadesAndItsEyesStay() throws {
        let rest = Self.body
        let rain = rest.enumerated().map { y, row in y == 19 ? "..pppp" + String(row.dropFirst(6)) : row }
        let frames = [
            Frame(name: "rest", rows: rest),
            Frame(name: "thin", fade: 0.5, rows: rest),
            Frame(name: "ghost", fade: 0.2, rows: rest),
            Frame(name: "rain", rows: rain),
        ]
        let character = Self.creature(frames, seeThrough: 0.2, rain: "rain")
        XCTAssertEqual(character.problems, [])
        let thin = character.index["thin"]!
        XCTAssertEqual(character.opacity(.accent, pose: thin, row: 8), 0.8 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(character.opacity(.accentDark, pose: thin, row: 8), 0.8 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(character.opacity(.veil, pose: thin, row: 8), CompanionInks.veilOpacity * 0.5, accuracy: 1e-9)
        for ink in [CompanionInk.ink, .light, .water, .waterLight, .snow] {
            XCTAssertEqual(character.opacity(ink, pose: thin, row: 8), 1, "\(ink) stays solid")
        }
        XCTAssertEqual(character.opacity(.accent, pose: 0, row: 8), 0.8, "the rest as it is")
        // Over the rain's still, the composite fades as its frame does.
        let over = character.drawnIndex("thin", over: "rain", rest: "rest")
        XCTAssertNotEqual(over, thin)
        XCTAssertEqual(character.looks[over].fade, 0.5)
        XCTAssertEqual(character.opacity(.accent, pose: over, row: 8), 0.4, accuracy: 1e-9)
        // Reduce Transparency: the body solid, faded no lower than half; the veil solid.
        let ghost = character.index["ghost"]!
        XCTAssertEqual(character.opacity(.accent, pose: 0, row: 8, reduceTransparency: true), 1)
        XCTAssertEqual(character.opacity(.veil, pose: 0, row: 8, reduceTransparency: true), 1)
        XCTAssertEqual(character.opacity(.accent, pose: thin, row: 8, reduceTransparency: true), 0.5)
        XCTAssertEqual(character.opacity(.accent, pose: ghost, row: 8, reduceTransparency: true), CompanionCharacter.leastFade)
        XCTAssertEqual(character.opacity(.ink, pose: ghost, row: 8, reduceTransparency: true), 1)
        // Drawn: the faded body at its opacity, the eye solid.
        let inks = CompanionInks(palette: .mocha)
        let pixels = try render(CompanionSprite(character: character, pose: .init(frame: thin, mirrored: false), inks: inks),
                                scale: 3)
        XCTAssertLessThanOrEqual(abs(pixels.at(4 * 6 + 3, 8 * 6 + 3).alpha - Int((0.4 * 255).rounded())), 2)
        XCTAssertEqual(pixels.at(8 * 6 + 3, 8 * 6 + 3).alpha, 255, "the eye solid")
        let solid = try render(CompanionSprite(character: character, pose: .init(frame: ghost, mirrored: false), inks: inks,
                                               reduceTransparency: true), scale: 3)
        XCTAssertLessThanOrEqual(abs(solid.at(4 * 6 + 3, 8 * 6 + 3).alpha - 128), 2, "half, with Reduce Transparency")
    }

    /// `thinning` clears a body down its rows, from its own top row to its own lowest in that frame: (1 − seeThrough)
    /// × (1 − thinning × t²). The eyes stay solid.
    func testABodyThinsDownItsRows() {
        let character = Self.creature([Frame(name: "rest", rows: Self.body)], seeThrough: 0.2, thinning: 0.5)
        XCTAssertEqual(character.problems, [])
        XCTAssertEqual(character.looks[0].body, 4...12)
        XCTAssertEqual(character.opacity(.accent, pose: 0, row: 4), 0.8, accuracy: 1e-9)
        XCTAssertEqual(character.opacity(.accent, pose: 0, row: 8), 0.8 * (1 - 0.5 * 0.25), accuracy: 1e-9)
        XCTAssertEqual(character.opacity(.accent, pose: 0, row: 12), 0.8 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(character.opacity(.veil, pose: 0, row: 12), CompanionInks.veilOpacity * 0.5, accuracy: 1e-9)
        XCTAssertEqual(character.opacity(.ink, pose: 0, row: 12), 1)
        XCTAssertEqual(character.opacity(.accent, pose: 0, row: 8, reduceTransparency: true), 1)
    }

    // MARK: - Problems

    /// `problems` knows the new ranges and the light's rules.
    func testProblemsKnowTheNewRanges() {
        let frames = [Frame(name: "rest", fade: 1.2, light: 2.5, rows: Self.lantern)]
        let bad = Self.creature(frames, thinning: 0.95, glow: [.warm, .water])
        let problems = bad.problems.joined(separator: "\n")
        XCTAssertTrue(problems.contains("fade 1.2"), problems)
        XCTAssertTrue(problems.contains("light 2.5"), problems)
        XCTAssertTrue(problems.contains("thinning 0.95"), problems)
        XCTAssertTrue(problems.contains("glows in warm"), problems)
        XCTAssertTrue(problems.contains("the weather's water gives no light"), problems)
        XCTAssertEqual(Self.creature([Frame(name: "rest", fade: 0, light: 2, rows: Self.lantern)], glow: [.light]).problems, [])
    }

    // MARK: - Helpers

    /// A body of `d` with an eye and a fleck of `m`, a 2 × 2 light at the right edge (the lantern), a dark pixel under it.
    static let lantern: [String] = (0..<20).map { y -> String in
        var row = Array(repeating: Character("."), count: 20)
        if (5...14).contains(y) { for x in 2...17 { row[x] = "d" } }
        if y == 14 { row[2] = "m" }
        if y == 8 || y == 9 { row[18] = "l"; row[19] = "l" }
        if y == 10 { row[18] = "k" }
        if y == 12 { row[10] = "k" }
        return String(row)
    }

    /// A see-through body of the accent, rows 4 to 12, its shade, an eye, a veiled hem.
    static let body: [String] = (0..<20).map { y -> String in
        var row = Array(repeating: Character("."), count: 20)
        if (4...11).contains(y) { for x in 2...12 { row[x] = "a" } }
        if y == 12 { for x in 2...12 { row[x] = "v" } }
        if y == 8 { row[8] = "k"; row[6] = "r"; row[10] = "l" }
        return String(row)
    }

    /// A test creature: the frames' first is the rest; every other is a flicker (or the asleep rest, or the rain).
    static func creature(_ rows: [String], seeThrough: Double = 0, thinning: Double = 0,
                         glow: Set<CompanionInk> = []) -> CompanionCharacter {
        creature([Frame(name: "rest", rows: rows)], seeThrough: seeThrough, thinning: thinning, glow: glow)
    }

    static func creature(_ frames: [Frame], seeThrough: Double = 0, thinning: Double = 0, glow: Set<CompanionInk> = [],
                         asleep: String? = nil, rain: String? = nil) -> CompanionCharacter {
        typealias C = CompanionCharacter
        let others = frames.dropFirst().map(\.name).filter { $0 != asleep && $0 != rain }
        let still = C.Gesture(name: "still", ticks: [.init(frame: "rest")], flicker: true)
        var gestures = [still]
        for name in others { gestures.append(C.Gesture(name: name, ticks: [.init(frame: name)], flicker: true)) }
        let awake = C.Mode(rest: "rest", rain: rain, gestures: gestures, answer: still)
        let sleeper = C.Gesture(name: "still", ticks: [.init(frame: asleep ?? "rest")], flicker: true)
        let sleep = asleep.map { C.Mode(rest: $0, gestures: [sleeper], answer: sleeper) } ?? awake
        let posture = C.Posture(awake: awake, asleep: sleep, flourish: C.ticks(("rest", 12)))
        return C(id: "tester", name: "Tester", width: 20, height: 20, seatRow: 20, frames: frames, gestureFPS: 8,
                 flourishFPS: 9, flourishTurns: false, field: posture, plus: posture, seeThrough: seeThrough,
                 thinning: thinning, glow: glow)
    }

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
}

extension CompanionCharacter {
    /// The same character with its light put out (no `glow`), for the checks that every pixel is exactly one of its
    /// inks; the halo itself is checked in `CompanionLightTests`.
    var unlit: CompanionCharacter {
        guard !glow.isEmpty else { return self }
        return CompanionCharacter(id: id, name: name, width: width, height: height, seatRow: seatRow, frames: frames,
                                  gestureFPS: gestureFPS, flourishFPS: flourishFPS, flourishTurns: flourishTurns,
                                  field: field, plus: plus, seeThrough: seeThrough, thinning: thinning)
    }
}
