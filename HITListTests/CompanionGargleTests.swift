import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Briefs 102 and 104: Gargle, Graphite's companion, a gargoyle pup carved for a ledge and come half alive on it. Round 21
/// (brief 104) carved him again: his body side-on along the edge as his elders sit on a cornice, all four paws on top of
/// it and nothing of him over the front; a wing folded up his back; his head turned to you with pale horns at its sides,
/// wide low eyes, a broad nose, one fang and his tongue; his tail behind the host (brief 104's capitals) with only its
/// spade back up beside him. He plays statue in his elders' profile, a shade paler, and sleeps as stone. Every frame is
/// also checked by `CompanionSpriteTests`, `CompanionSeatTests` and `CompanionDirectorTests.testNeverADeadMinute`.
@MainActor
final class CompanionGargleTests: XCTestCase {
    private let gargle = CompanionCharacter.gargle

    private func rows(_ name: String) -> [[Character]] { gargle.rows(name)!.map(Array.init) }

    private func count(_ ink: Character, _ name: String) -> Int { gargle.rows(name)!.joined().filter { $0 == ink }.count }

    func testGraphiteHasGargleAndSmudgeIsGone() {
        XCTAssertEqual(gargle.problems, [])
        XCTAssertEqual(gargle.name, "Gargle")
        XCTAssertEqual(CompanionCast.character(forTheme: "graphite", launch: .none).id, "gargle")
        XCTAssertEqual(CompanionCast.character(forTheme: "slate", launch: .none).id, "nod", "the others keep theirs")
        XCTAssertNil(CompanionCharacter.named("smudge"))
        XCTAssertFalse(CompanionCast.byTheme.values.contains("smudge"))
        let old = CompanionLaunchOptions(arguments: ["-companion", "smudge"])
        XCTAssertEqual(CompanionCast.character(forTheme: "graphite", launch: old).id, "gargle", "an old -companion smudge")
        let forced = CompanionLaunchOptions(arguments: ["-companion", "Gargle"])
        XCTAssertEqual(CompanionCast.character(forTheme: "nord", launch: forced).id, "gargle")
    }

    /// Carved, not flat (brief 104): two tones of stone and a highlight, a head as large as his body turned to you with
    /// two wide eyes, a glint in each; pale horns at the sides of his head; one fang breaking his mouth and the tip of his
    /// tongue (the one warm detail); a wing up his back, a dark membrane with lighter ribs and a pale hooked tip.
    func testHeIsACarvedGargoylePup() {
        XCTAssertEqual(gargle.inks, [.ink, .dark, .mid, .light, .warm])
        XCTAssertEqual(gargle.seatRow, 18)
        let rest = rows("rest")
        var glints: [Int] = []
        for y in 5...10 {
            for x in 1..<19 where rest[y][x] == "l" {
                if rest[y - 1][x] == "k", rest[y + 1][x] == "k", rest[y][x - 1] == "k", rest[y][x + 1] == "k" { glints.append(x) }
            }
        }
        XCTAssertEqual(glints.count, 2, "two big eyes, a glint in each")
        XCTAssertGreaterThanOrEqual(glints[1] - glints[0], 6, "set wide")
        // Horns: pale, along their length, at the sides of the head (its top rows, left and right of the crown).
        let horns = (0...3).flatMap { y in (0..<13).filter { rest[y][$0] == "l" } }
        XCTAssertGreaterThanOrEqual(horns.filter { $0 <= 3 }.count, 3, "the left horn, pale along its length")
        XCTAssertGreaterThanOrEqual(horns.filter { $0 >= 9 }.count, 3, "and the right")
        // The mouth: one fang breaking its line, the tongue's tip under it.
        XCTAssertEqual(String(rest[11][4...8]), "dlddd", "one fang in the mouth's line")
        XCTAssertEqual(count("w", "rest"), 1, "the tip of his tongue")
        // The wing: a dark membrane up his back, with ribs in mid grey and a pale tip at the top.
        let wing = (0...11).flatMap { y in (13..<20).map { rest[y][$0] } }
        XCTAssertGreaterThan(wing.filter { $0 == "d" }.count, 40, "a dark membrane")
        XCTAssertGreaterThanOrEqual(wing.filter { $0 == "m" }.count, 8, "its ribs")
        XCTAssertTrue(rest[0][13...16].contains("l"), "its hooked tip, pale")
        // Two tones of stone and a highlight: mid and dark both carry him.
        XCTAssertGreaterThan(count("m", "rest"), 60)
        XCTAssertGreaterThan(count("d", "rest"), 60)
        XCTAssertFalse(gargle.flourishTurns)
    }

    /// Perched (brief 104): all four paws on the host's top edge, nothing of him over the front in any frame; his tail
    /// drops behind the host from under his rump, and only its spade comes back up beside him, a pixel clear of his body.
    func testHeSitsOnTopAndHisTailIsBehindTheBar() {
        let seat = gargle.seatRow
        for frame in gargle.frames {
            for y in seat..<gargle.height {
                for c in frame.rows[y] where c != CompanionInk.clear {
                    XCTAssertTrue(CompanionInk.isBehind(c), "\(frame.name) row \(y): only what is behind the host below the edge")
                }
            }
        }
        let rest = rows("rest")
        XCTAssertTrue(rest[seat].contains("D"), "his tail behind the bar")
        XCTAssertEqual(rest[seat].filter { $0 == "D" }.count, 7, "from under his rump to the spade")
        let edge = rest[seat - 1]
        XCTAssertEqual(edge[16], CompanionInk.clear, "the spade comes up a pixel clear of him")
        XCTAssertNotEqual(edge[17], CompanionInk.clear)
        XCTAssertNotEqual(edge[18], CompanionInk.clear)
        XCTAssertEqual(rest[seat - 3][18], "m", "the spade's point, pale stone above the edge")
        // His paws: the front paw and the hind foot on the edge row, toes showing.
        XCTAssertEqual(String(edge[1...5]), "dmdmd", "a front paw, its toes")
        XCTAssertEqual(String(edge[9...14]), "mdmdmm", "a hind foot")
    }

    /// Round 20's pace (brief 100): awake at least six flickers (the blink the heaviest) and four little loops, four long
    /// routines of every day, a flourish and an answer; asleep at least two breaths. The same in both places. No foot
    /// swing (round 21): in every flicker his paws stay where they are on the ledge.
    func testHeIsAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = gargle.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }.filter { $0.sky == nil }
            XCTAssertGreaterThanOrEqual(flickers.count, 6, at)
            XCTAssertEqual(flickers.max { $0.weight < $1.weight }?.name, "blink", at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter(\.little).count, 4, at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter { !$0.little && $0.sky == nil }.count, 4, at)
            for routine in awake.routines where routine.little {
                XCTAssertLessThanOrEqual(gargle.duration(of: routine, mode: awake), 2.5, "\(at) \(routine.name)")
                XCTAssertTrue((2...4).contains(routine.moves), "\(at) \(routine.name)")
            }
            XCTAssertGreaterThanOrEqual(posture.asleep.gestures.count, 2, at)
            XCTAssertTrue(posture.asleep.routines.isEmpty, at)
            let rest = rows(awake.rest)
            let edge = gargle.seatRow - 1
            for gesture in flickers {
                for tick in gesture.ticks {
                    XCTAssertEqual(Array(rows(tick.frame)[edge][0...15]), Array(rest[edge][0...15]),
                                   "\(at) \(gesture.name): his paws stay on the ledge")
                }
            }
        }
        XCTAssertEqual(gargle.plus.awake.routines.map(\.name), gargle.field.awake.routines.map(\.name))
        let names = Set(gargle.plus.awake.routines.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["statue", "periscope", "statueGame", "stretch", "chase", "dust", "tryFly"]))
    }

    /// The statue (brief 104): he turns into his elders' profile through one frame between, a shade paler (the stone's
    /// shading lifts a tone, fewer dark pixels than the pup), holds, and a peek (an eye with its glint) gives him away.
    func testHePlaysStatue() {
        let awake = gargle.plus.awake
        let statue = awake.routines.first { $0.name == "statueGame" }!
        let frames = awake.ticks(of: statue).map(\.tick.frame)
        XCTAssertTrue(frames.contains("turn") && frames.contains("statue") && frames.contains("statuePeek"))
        let turn = frames.firstIndex(of: "turn")!
        XCTAssertEqual(frames[turn + 1], "statue", "the turn is one frame between the pup and the statue")
        XCTAssertLessThan(count("d", "statue"), count("d", "rest"), "a shade paler")
        XCTAssertFalse(gargle.rows("statue")!.joined().contains("w"), "no tongue on a statue")
        XCTAssertTrue(gargle.rows("statuePeek")!.joined().contains("k"), "the peek: an eye opens")
        // The quick one, a little loop, the same turn and the same statue.
        let quick = awake.routines.first { $0.name == "statue" }!
        XCTAssertTrue(quick.little)
        XCTAssertTrue(awake.ticks(of: quick).map(\.tick.frame).contains("statue"))
        // In the rain his statue is a waterspout: its mouth open.
        XCTAssertGreaterThan(count("k", "statue@rain"), count("k", "statue"))
    }

    /// Its flourish: the grotesque's face (both wings high, fangs, a glare), spoiled by a giggle.
    func testHePullsAGrotesquesFace() {
        let frames = gargle.plus.flourish.map(\.frame)
        XCTAssertTrue(frames.contains("boo") && frames.contains("giggle"))
        let boo = rows("boo")
        XCTAssertEqual(boo[11].filter { $0 == "l" }.count, 2, "two fangs")
        XCTAssertTrue(boo[0][3...6].contains("d"), "the far wing up behind his head")
        XCTAssertEqual(gargle.flourishDuration(.plus), gargle.flourishDuration(.field))
    }

    /// Asleep he has turned to stone (brief 104: in profile, a shade paler, the statue's pose with its head down a pixel):
    /// no dark of an eye, no tongue; woken, one eye opens.
    func testAsleepHeTurnsToStone() {
        let sleep = gargle.rows("sleep")!.joined()
        XCTAssertFalse(sleep.contains("k"), "no dark of an eye: a carved line")
        XCTAssertFalse(sleep.contains("w"), "no tongue")
        XCTAssertLessThan(count("d", "sleep"), count("d", "rest"), "a shade paler")
        XCTAssertGreaterThan(gargle.difference("sleep", "rest"), 40, "a pose of its own")
        XCTAssertEqual(gargle.plus.asleep.rest, "sleep")
        XCTAssertNil(gargle.plus.asleep.rain, "asleep wins over the rain")
        XCTAssertTrue(gargle.rows("sleepPeek")!.joined().contains("k"), "woken: one eye opens")
    }

    /// Brief 91: in the rain his mouth hangs open like a spout and a drop runs from his chin (a flicker that shows), and he
    /// shakes his head dry; snow piles up twice over on his crown and back (more each time, the seat untouched) until he
    /// shakes the heap off, from the heap only; on a hot day he lies flat on the cool stone and pants.
    func testTheWeatherShowsOnHim() {
        for place in CompanionPlace.allCases {
            let awake = gargle.posture(place).awake
            let at = "\(place)"
            let drip = awake.gesture(named: "drip")!
            XCTAssertEqual(drip.sky, .rain)
            XCTAssertTrue(drip.flicker)
            for tick in drip.ticks { XCTAssertEqual(gargle.difference(tick.frame, awake.rain!), 1, "\(at): one drop") }
            XCTAssertEqual(awake.routines.first { $0.sky == .rain }?.name, "shake", at)
            var previous = awake.snow!
            for deep in awake.snowDeep {
                XCTAssertGreaterThan(count("l", deep), count("l", previous), "\(at) \(deep)")
                previous = deep
            }
            XCTAssertEqual(awake.snowDeep.count, 2, at)
            let shake = awake.routines.first { $0.shakesOff }!
            XCTAssertTrue(gargle.canDraw(shake, in: .snow, mode: awake, depth: awake.deepest), at)
            XCTAssertFalse(gargle.canDraw(shake, in: .snow, mode: awake, depth: 0), at)
            XCTAssertEqual(awake.heat, "heat")
            XCTAssertTrue(awake.gestures.contains { $0.sky == .heat && $0.flicker }, at)
            XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "flop", at)
        }
        XCTAssertGreaterThan(count("w", "heat"), 1, "his tongue out on a hot day")
        // Flat: his head is down on his paws, its top four rows lower than by day.
        let heat = rows("heat")
        let rest = rows("rest")
        let top = { (r: [[Character]]) in r.firstIndex { row in row[0...12].contains { $0 != CompanionInk.clear } }! }
        XCTAssertGreaterThanOrEqual(top(heat) - top(rest), 3, "lying flat")
    }

    /// Brief 100: an idle can be drawn over every still it may show, so it is never still for long whatever the sky.
    func testAnIdleDrawsOverEveryStill() {
        for place in CompanionPlace.allCases {
            let posture = gargle.posture(place)
            for (label, mode) in [("awake", posture.awake), ("asleep", posture.asleep)] {
                var looks: [(CompanionLook.Weather, Int)] = [(.plain, 0), (.rain, 0), (.snow, 0), (.heat, 0)]
                for depth in 0..<mode.snowDeep.count { looks.append((.snow, depth + 1)) }
                for (weather, depth) in looks {
                    let candidates = label == "asleep" ? mode.gestures : mode.flickers.map { mode.gestures[$0] }
                    let drawable = candidates.filter { gesture in
                        guard let sky = gesture.sky else {
                            return gargle.canDraw(gesture, in: weather, mode: mode, depth: depth)
                        }
                        return CompanionLook.Weather(sky) == weather && gargle.canDraw(gesture, in: weather, mode: mode, depth: depth)
                    }
                    XCTAssertFalse(drawable.isEmpty, "\(place) \(label) \(weather) \(depth): an idle that draws")
                }
            }
            // The reply to a tap plays in every weather (a frame of its own on a hot day).
            for weather in CompanionLook.Weather.allCases {
                XCTAssertTrue(gargle.canDraw(posture.awake.answer, in: weather, mode: posture.awake, depth: 0), "\(place) \(weather)")
            }
        }
    }

    /// Its seat (brief 100): he sits on the middle of the "+", and every column of every still that rests on the edge line
    /// has the "+" (SwiftUI's continuous capsule, the lower of it and the circular one at each point) less than a sprite
    /// pixel under it, which the seat fills (his outer paws are over its shoulders), or his tail goes on down behind the
    /// host there. `CompanionSeatTests` measures what is drawn, seat and all.
    func testHeSitsOnThePlus() {
        let size = FloatingAddButton.size
        let rect = CGRect(origin: .zero, size: size)
        let shapes = [Capsule(style: .continuous).path(in: rect), Capsule(style: .circular).path(in: rect)]
        func top(_ x: CGFloat) -> CGFloat {
            var y: CGFloat = 0
            while y < size.height / 2, !shapes.allSatisfy({ $0.contains(CGPoint(x: x, y: y)) }) { y += 0.01 }
            return y
        }
        let p = CompanionCharacter.pointsPerPixel
        let offset = CompanionPerch.offset(gargle, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(gargle.width) * p
        let left: CGFloat = size.width - spriteWidth + offset.width
        let posture = gargle.plus
        var stills: [String] = []
        for mode in [posture.awake, posture.asleep] { stills.append(contentsOf: mode.stills) }
        let edge = gargle.seatRow - 1
        for name in stills {
            let rows = rows(name)
            for c in 0..<gargle.width where rows[edge][c] != CompanionInk.clear {
                if CompanionInk.isBehind(rows[edge + 1][c]) { continue }
                let x0: CGFloat = left + CGFloat(c) * p
                let x1: CGFloat = x0 + p
                let gap = max(top(x0 + 0.01), top(x1 - 0.01))
                XCTAssertLessThan(gap, p, "\(name) column \(c): \(gap) pt under it, more than the seat fills")
            }
        }
        let seat = rows("rest")[edge]
        let first = seat.firstIndex { $0 != CompanionInk.clear }!
        let last = seat.lastIndex { $0 != CompanionInk.clear }!
        let first0: CGFloat = CGFloat(first)
        let last1: CGFloat = CGFloat(last + 1)
        let middle: CGFloat = left + (first0 + last1) * p / 2
        XCTAssertEqual(middle, size.width / 2, accuracy: 1)
    }

    /// The UI tests tap the companion just above the "+" (24 pt in from its right edge, 14 pt up) and the "+" just under
    /// its paws (22 pt in, 3 pt down): the first is the companion's, the second the "+"'s.
    func testTheUITestsTapsLandOnHimAndOnThePlus() {
        let size = FloatingAddButton.size
        let rest = gargle.index[gargle.plus.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: gargle.drawn[rest], width: gargle.width, mirrored: false,
                                                belowRow: gargle.seatRow)
        let offset = CompanionPerch.offset(gargle, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(gargle.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let top: CGFloat = offset.height
        XCTAssertTrue(shape.contains(CGPoint(x: size.width - 24 - left, y: -14 - top)), "a tap on him is his own")
        XCTAssertFalse(shape.contains(CGPoint(x: size.width - 22 - left, y: 3 - top)), "a tap under his paws is the +'s")
    }

    /// Brief 104: his tail drawn as the app draws it, on the real "+" at iPhone 17 and 16 widths and on the Mac's field:
    /// the part behind the host shows only outside the host's shape (`CompanionBehindTests` checks the layer itself), under
    /// the seat's half point at the rim.
    func testHisTailIsBehindTheHostWhenDrawn() throws {
        let palette = ThemePalette.all.first { $0.id == "graphite" } ?? .slate
        for host in [CompanionSeatTests.iPhone17, CompanionSeatTests.iPhone16, CompanionSeatTests.hosts[3]] {
            let pose = CompanionPose(frame: gargle.index["rest"]!, mirrored: false)
            let scene = CompanionSeatTests.Scene(character: gargle, pose: pose, host: host, palette: palette)
            let alone = CompanionSeatTests.Scene(character: gargle, pose: nil, host: host, palette: palette)
            let pixels = CompanionSeatTests.Pixels(try XCTUnwrap(CompanionSeatTests.render(scene, scale: host.scale)))
            let bare = CompanionSeatTests.Pixels(try XCTUnwrap(CompanionSeatTests.render(alone, scale: host.scale)))
            let colours = CompanionSeatTests.Palette(palette, host: host)
            let origin = CompanionSeatTests.spriteOrigin(gargle, host: host)
            let p = CompanionCharacter.pointsPerPixel
            let y0: CGFloat = origin.y + CGFloat(gargle.seatRow) * p
            // Deeper than the seat's own half point tucked into the rim under his base (`CompanionSeat.overlap`), which
            // follows the host's curve: the host also that far and a device pixel above.
            let tuck: Int = Int((CompanionSeat.overlap * host.scale).rounded(.up)) + 1
            var covered = 0
            for y in Int((y0 * host.scale).rounded())..<Int(((y0 + p) * host.scale).rounded()) {
                for c in 13...18 {
                    let x0: CGFloat = origin.x + CGFloat(c) * p
                    for x in Int((x0 * host.scale).rounded())..<Int(((x0 + p) * host.scale).rounded()) {
                        // Wholly the host there (it and its neighbours): the tail must not show on it.
                        let around = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (0, -tuck)].allSatisfy {
                            colours.shows(bare.rgb(x + $0.0, y + $0.1)) == .host
                        }
                        guard around else { continue }
                        covered += 1
                        XCTAssertLessThan(CompanionSeatTests.Palette.distance(pixels.rgb(x, y), bare.rgb(x, y)), 48,
                                          "\(host.name) \(x),\(y): his tail drawn on the host")
                    }
                }
            }
            XCTAssertGreaterThan(covered, 20, "\(host.name): the tail's row lies over the host")
        }
    }
}
