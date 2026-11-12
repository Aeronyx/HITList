import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 104, the "behind the host" layer: a capital ink letter in a frame is that ink behind the host (`M` is `m`
/// behind). It is drawn only where the host's shape is not (`CompanionPerch.surface`), so a tail dropped behind the "+"
/// shows down to the button's curve and no further, and behind the Mac's field it ends at the field's top edge; with
/// no host (the swatch in Settings) it isn't drawn. The seat and the tap area ignore it; it may only lie below the seat
/// row. Drawn the way the app draws a companion (`CompanionFigure` on `CompanionSeatTests.Scene`).
@MainActor
final class CompanionBehindTests: XCTestCase {
    /// A test creature: a block of body in front (columns 0 to 7, so the perch lines it up there and the sprite's box
    /// reaches past the host's trailing edge) and, under the seat row, a whole slab behind the host across the box.
    static func creature(seatRow: Int = 12, behind: Character = "M") -> CompanionCharacter {
        var rows: [String] = []
        for y in 0..<20 {
            if y < seatRow - 1 {
                rows.append("llllllll" + String(repeating: ".", count: 12))
            } else if y == seatRow - 1 {
                rows.append(String(repeating: ".", count: 20))
            } else {
                rows.append(String(repeating: behind, count: 20))
            }
        }
        return character(rows, seatRow: seatRow)
    }

    static func character(_ rest: [String], seatRow: Int) -> CompanionCharacter {
        let still = CompanionCharacter.Gesture(name: "still", ticks: [.init(frame: "rest")], flicker: true)
        let mode = CompanionCharacter.Mode(rest: "rest", gestures: [still], answer: still)
        let posture = CompanionCharacter.Posture(awake: mode, asleep: mode, flourish: CompanionCharacter.ticks(("rest", 12)))
        return CompanionCharacter(id: "tester", name: "Tester", width: rest[0].count, height: rest.count, seatRow: seatRow,
                                  frames: [.init(name: "rest", rows: rest)], gestureFPS: 8, flourishFPS: 9,
                                  flourishTurns: false, field: posture, plus: posture)
    }

    // MARK: - The format

    func testACapitalIsThatInkBehindTheHost() {
        XCTAssertEqual(CompanionCharacter.runs(of: ["mMM.k", "..V.."]), [
            .init(x: 0, y: 0, length: 1, ink: .mid),
            .init(x: 1, y: 0, length: 2, ink: .mid, behind: true),
            .init(x: 4, y: 0, length: 1, ink: .ink),
            .init(x: 2, y: 1, length: 1, ink: .veil, behind: true),
        ])
        for ink in CompanionInk.allCases {
            XCTAssertEqual(CompanionInk.read(ink.rawValue)?.ink, ink)
            XCTAssertEqual(CompanionInk.read(ink.rawValue)?.behind, false)
            XCTAssertEqual(CompanionInk.read(ink.behind)?.ink, ink, "\(ink.behind)")
            XCTAssertEqual(CompanionInk.read(ink.behind)?.behind, true)
            XCTAssertTrue(CompanionInk.isBehind(ink.behind))
            XCTAssertFalse(CompanionInk.isBehind(ink.rawValue))
            XCTAssertNil(CompanionInk(rawValue: ink.behind), "no ink's own letter is another's capital")
        }
        XCTAssertNil(CompanionInk.read(CompanionInk.clear))
        XCTAssertNil(CompanionInk.read("x"))
        XCTAssertNil(CompanionInk.read("X"), "a capital of no ink is no ink")
        XCTAssertFalse(CompanionInk.isBehind("."))
        // Its ink is the same ink, at the same opacity: see-through inks keep working behind the host.
        let creature = Self.creature(behind: "V")
        XCTAssertEqual(creature.inks, [.light, .veil])
        XCTAssertEqual(creature.drawn[0].last?.ink, .veil)
        XCTAssertEqual(creature.opacity(.veil), CompanionInks.veilOpacity)
    }

    /// Round 22: fallen snow's three inks are every creature's, so they are not among a creature's own colours
    /// (the "4…6 colours" rule and the tests that pin a creature's inks never see them), and snow is never
    /// see-through.
    func testSnowInksAreNotACreaturesOwnColours() {
        XCTAssertEqual(CompanionInk.snowInks, [.snow, .snowBlue, .snowShade])
        XCTAssertEqual(CompanionCharacter.runs(of: ["sbc"]).map(\.ink), [.snow, .snowBlue, .snowShade])
        for character in CompanionCharacter.all {
            XCTAssertTrue(character.inks.isDisjoint(with: CompanionInk.snowInks), character.id)
            XCTAssertEqual(character.inks, character.allInks.subtracting(CompanionInk.weatherInks), character.id)
            for ink in CompanionInk.snowInks { XCTAssertEqual(character.opacity(ink), 1, "\(character.id) \(ink)") }
        }
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            XCTAssertEqual(inks.hex[.snow], CompanionInks.snowHex)
            XCTAssertEqual(inks.hex[.snowBlue], CompanionInks.snowBlueHex)
            XCTAssertEqual(inks.hex[.snowShade], CompanionInks.snowShadeHex)
        }
    }

    /// Round 24: water's three inks (beads, a running drop, a puddle) are every creature's too: the same blues in
    /// every theme, never see-through, never among a creature's own colours.
    func testWaterInksAreNotACreaturesOwnColours() {
        XCTAssertEqual(CompanionInk.waterInks, [.water, .waterLight, .waterDeep])
        XCTAssertEqual(CompanionInk.weatherInks, CompanionInk.snowInks.union(CompanionInk.waterInks))
        XCTAssertEqual(CompanionCharacter.runs(of: ["phu"]).map(\.ink), [.water, .waterLight, .waterDeep])
        for character in CompanionCharacter.all {
            XCTAssertTrue(character.inks.isDisjoint(with: CompanionInk.waterInks), character.id)
            for ink in CompanionInk.waterInks { XCTAssertEqual(character.opacity(ink), 1, "\(character.id) \(ink)") }
        }
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            XCTAssertEqual(inks.hex[.water], CompanionInks.waterHex)
            XCTAssertEqual(inks.hex[.waterLight], CompanionInks.waterLightHex)
            XCTAssertEqual(inks.hex[.waterDeep], CompanionInks.waterDeepHex)
        }
    }

    func testProblemsKnowTheNewMarks() {
        XCTAssertEqual(Self.creature().problems.filter { $0.contains("behind the host") || $0.contains("unknown") }, [],
                       "behind the host below the seat row is fine")
        // On the edge row (the row it sits on) and above, there is nothing to be behind.
        var rows = Self.creature().frames[0].rows
        rows[11] = "....M..............."
        rows[3] = "llllllllD..........."
        let wrong = Self.character(rows, seatRow: 12)
        XCTAssertTrue(wrong.problems.contains("tester.rest row 11: behind the host above the seat row"), "\(wrong.problems)")
        XCTAssertTrue(wrong.problems.contains("tester.rest row 3: behind the host above the seat row"))
        rows = Self.creature().frames[0].rows
        rows[15] = "Z" + String(repeating: "M", count: 19)
        XCTAssertTrue(Self.character(rows, seatRow: 12).problems.contains("tester.rest row 15: unknown ink Z"))
        // Today's cast passes as it is.
        for character in CompanionCharacter.all {
            XCTAssertEqual(character.problems, [], character.id)
        }
    }

    /// The perch lines a companion up by what is in front of the host; the seat goes under a base pixel whatever lies
    /// behind the host below it, and never under something behind; a tap on something behind the host is the host's.
    func testTheSeatAndTheTapAreaIgnoreIt() {
        let creature = Self.creature()
        XCTAssertEqual(creature.rightmostColumn("rest"), 7, "the slab behind reaches column 19; the body ends at 7")
        // A base on the edge row: a pixel over a behind one gets its seat, a pixel over a front one doesn't.
        var rows = creature.frames[0].rows
        rows[11] = "mmmm" + String(repeating: ".", count: 16)
        rows[12] = "MMmm" + String(repeating: "M", count: 16)
        let seated = Self.character(rows, seatRow: 12)
        let pose = CompanionPose(frame: 0, mirrored: false)
        XCTAssertEqual(CompanionSeat.base(seated, pose: pose).map(\.x), [0, 1])
        XCTAssertEqual(CompanionSeat.base(seated, pose: CompanionPose(frame: 0, mirrored: true)).map(\.x), [19, 18])
        // Taps: the body is the companion's; nothing behind the host is, even with no edge to cut at.
        let p = CompanionCharacter.pointsPerPixel
        let shape = CompanionCharacter.tapShape(runs: creature.drawn[0], width: creature.width, mirrored: false)
        XCTAssertTrue(shape.contains(CGPoint(x: 3 * p, y: 5 * p)))
        XCTAssertFalse(shape.contains(CGPoint(x: 15 * p + 1, y: 16 * p + 1)), "behind the host: the host's to tap")
    }

    // MARK: - Drawn

    /// On the real "+" (iPhone 17 and 16 at 3x, the iPad's plain oval at 2x) and on the Mac's field: no pixel behind the
    /// host is drawn inside the host's shape, and every one outside it is, device pixel by device pixel. Inside and
    /// outside are read from the host drawn alone, as `CompanionSeatTests` reads its edge (a path's `contains` strays
    /// up to 0.7 pt from the drawn capsule at its rounded ends); the smoothed pixels at the edge and the one each side
    /// of them are left out, two on the iPad, whose plain oval parts from the seat's shape by up to a third of a point.
    func testDrawnOnlyWhereTheHostIsNot() throws {
        let creature = Self.creature()
        let palette = ThemePalette.slate
        let inks = CompanionInks(palette: palette)
        let behind = CompanionInks.rgb(inks.hex[.mid]!)
        let p = CompanionCharacter.pointsPerPixel
        for host in CompanionSeatTests.hosts {
            let scale = host.scale
            let scene = CompanionSeatTests.Scene(character: creature, pose: CompanionPose(frame: 0, mirrored: false),
                                                 host: host, palette: palette)
            let pixels = CompanionSeatTests.Pixels(try XCTUnwrap(CompanionSeatTests.render(scene, scale: scale)))
            let alone = CompanionSeatTests.Scene(character: creature, pose: nil, host: host, palette: palette)
            let bare = CompanionSeatTests.Pixels(try XCTUnwrap(CompanionSeatTests.render(alone, scale: scale)))
            let colours = CompanionSeatTests.Palette(palette, host: host)
            let background = CompanionInks.rgb(palette.hex.background)
            let reach = host.circular ? 2 : 1
            let origin = CompanionSeatTests.spriteOrigin(creature, host: host)
            let top: CGFloat = origin.y + CGFloat(creature.seatRow) * p
            let bottom: CGFloat = origin.y + CGFloat(creature.height) * p
            let right: CGFloat = origin.x + CGFloat(creature.width) * p
            var inside = 0
            var outside = 0
            for y in Int((top * scale).rounded())..<Int((bottom * scale).rounded()) {
                for x in Int((origin.x * scale).rounded())..<Int((right * scale).rounded()) {
                    guard x >= reach, x < pixels.width - reach, y >= reach, y < pixels.height - reach else { continue }
                    // The host alone here and all round: wholly the host, or wholly the background.
                    var host0 = 0
                    var clear = 0
                    for dy in -reach...reach {
                        for dx in -reach...reach {
                            let rgb = bare.rgb(x + dx, y + dy)
                            if colours.shows(rgb) == .host {
                                host0 += 1
                            }
                            if CompanionSeatTests.Palette.distance(rgb, background) < 48 { clear += 1 }
                        }
                    }
                    let around = (2 * reach + 1) * (2 * reach + 1)
                    let rgb = pixels.rgb(x, y)
                    if host0 == around {
                        inside += 1
                        let distance = CompanionSeatTests.Palette.distance(rgb, bare.rgb(x, y))
                        XCTAssertLessThan(distance, 48, "\(host.name) \(x),\(y): \(rgb), drawn inside the host")
                    } else if clear == around {
                        outside += 1
                        let distance = CompanionSeatTests.Palette.distance(rgb, behind)
                        XCTAssertLessThan(distance, 48, "\(host.name) \(x),\(y): \(rgb), not drawn outside the host")
                    }
                }
            }
            XCTAssertGreaterThan(inside, 400, "\(host.name): the slab reaches into the host")
            XCTAssertGreaterThan(outside, 300, "\(host.name): and past it")
        }
    }

    /// With no host (Settings' swatch, a design sheet) nothing behind the host is drawn; the rest is, as before.
    func testWithNoHostItIsNotDrawn() throws {
        let creature = Self.creature()
        let inks = CompanionInks(palette: .slate)
        let view = CompanionSprite(character: creature, pose: CompanionPose(frame: 0, mirrored: false), inks: inks)
        let image = try XCTUnwrap(CompanionSeatTests.render(view, scale: 3))
        let pixels = CompanionSeatTests.Pixels(image)
        XCTAssertEqual(pixels.width, creature.width * 6)
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            let row: Int = y * pixels.width
            let i: Int = (row + x) * 4 + 3
            return pixels.bytes[i]
        }
        let rows = creature.frames[0].rows.map(Array.init)
        for y in 0..<creature.height {
            for x in 0..<creature.width {
                let c = rows[y][x]
                let shown = alpha(x * 6 + 3, y * 6 + 3)
                if c == CompanionInk.clear || CompanionInk.isBehind(c) {
                    XCTAssertEqual(shown, 0, "\(x),\(y)")
                } else {
                    XCTAssertEqual(shown, 255, "\(x),\(y)")
                }
            }
        }
    }
}
