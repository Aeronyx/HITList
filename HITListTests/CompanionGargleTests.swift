import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Briefs 102, 104 and 111: Gargle, Graphite's companion, a stone dragon pup carved for a ledge and come half alive on it.
/// Round 21 (brief 104) carved his body side-on along the edge as his elders sit on a cornice, all four paws on top of it and
/// nothing of him over the front, a wing folded up his back, his tail behind the host (brief 104's capitals) with only its
/// spade back up beside him. Round 22 (brief 111) made him more of a dragon: his head three-quarters to you with a short
/// snout, two small horns swept back and a spine, a reptile's amber eyes with a light in each, and a mouth closed in a smile
/// with one tiny fang, so nothing ever reads as coming out of it. He plays statue in his elders' profile, a shade paler,
/// and sleeps as stone. Every frame is also checked by `CompanionSpriteTests`, `CompanionSeatTests` and
/// `CompanionDirectorTests.testNeverADeadMinute`.
@MainActor
final class CompanionGargleTests: XCTestCase {
    private let gargle = CompanionCharacter.gargle

    private func rows(_ name: String) -> [[Character]] { gargle.rows(name)!.map(Array.init) }

    private func count(_ ink: Character, _ name: String) -> Int { gargle.rows(name)!.joined().filter { $0 == ink }.count }

    private func distinct(_ names: [String]) -> [String] {
        var out: [String] = []
        for name in names where !out.contains(name) { out.append(name) }
        return out
    }

    private func snow(_ name: String) -> Int { gargle.rows(name)!.joined().filter { "sbc".contains($0) }.count }

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

    /// A stone dragon pup (brief 111): two tones of stone and a highlight; his head as large as his body, three-quarters to
    /// you, its snout sticking out to the left past his crown; two pale horns swept back off the crown; two eyes of his own,
    /// an amber iris with a light in each (not Button's round black eye); a wing up his back, a dark membrane with lighter
    /// ribs and a pale hooked tip.
    func testHeIsAStoneDragonPup() {
        XCTAssertEqual(gargle.inks, [.ink, .dark, .mid, .light, .warm, .glow])
        XCTAssertEqual(gargle.seatRow, 18)
        let rest = rows("rest")
        // The snout: the head reaches the left edge at the muzzle's rows and starts two or more columns in at the crown's.
        let left = { (y: Int) in rest[y].firstIndex { $0 != CompanionInk.clear }! }
        XCTAssertEqual(left(8), 0, "the snout's tip")
        XCTAssertGreaterThanOrEqual(left(4), 3, "the crown set back behind it")
        XCTAssertEqual(rest[8][1], "k", "a nostril at the snout's tip")
        // Two horns swept back: pale along their length, each rising to the right (backwards) off the crown.
        XCTAssertEqual(String(rest[1][7...8]), "ll", "the far horn's tip")
        XCTAssertEqual(rest[2][6], "l")
        XCTAssertEqual(String(rest[1][11...12]), "ll", "the near horn's tip")
        XCTAssertEqual(rest[2][10], "l")
        XCTAssertEqual(rest[3][12], "m", "a spine behind the near horn")
        // His eyes: each a light (`l`) beside the amber iris (`w`) and a dark pupil under or beside it.
        var lights: [Int] = []
        for y in 5...9 {
            for x in 1..<13 where rest[y][x] == "l" {
                let around = [rest[y - 1][x], rest[y + 1][x], rest[y][x - 1], rest[y][x + 1]]
                if around.contains("k"), around.contains("w") || rest[y + 1][x] == "w" { lights.append(x) }
            }
        }
        XCTAssertEqual(lights.count, 2, "a light in each eye")
        XCTAssertGreaterThanOrEqual(count("w", "rest"), 4, "amber irises")
        // Not Button's round black eye: no two-by-two of ink anywhere on his face.
        for y in 3..<12 {
            for x in 0..<13 {
                let block = [rest[y][x], rest[y][x + 1], rest[y + 1][x], rest[y + 1][x + 1]]
                XCTAssertFalse(block.allSatisfy { $0 == "k" }, "a round black eye at \(x),\(y)")
            }
        }
        // The wing: a dark membrane up his back, with ribs in mid grey and a pale tip at the top.
        let wing = (0...11).flatMap { y in (14..<20).map { rest[y][$0] } }
        XCTAssertGreaterThan(wing.filter { $0 == "d" }.count, 30, "a dark membrane")
        XCTAssertGreaterThanOrEqual(wing.filter { $0 == "m" }.count, 8, "its ribs")
        XCTAssertTrue(rest[0][13...16].contains("l"), "its hooked tip, pale")
        // Two tones of stone and a highlight: mid and dark both carry him.
        XCTAssertGreaterThan(count("m", "rest"), 60)
        XCTAssertGreaterThan(count("d", "rest"), 60)
        XCTAssertFalse(gargle.flourishTurns)
    }

    /// His mouth never reads as being sick (brief 111; George: "Gargle looks like he's throwing up"). At rest it is closed: a
    /// line along the muzzle with its corner turned up and one tiny fang over the lip, nothing dark in it and nothing under it.
    /// In every frame nothing warm (an iris, an ember) is lower than his eyes, so whatever leaves him (a puff of smoke, an
    /// ember) goes up and away from the snout's end.
    func testHisMouthIsClosedAndNothingComesOutOfIt() {
        let rest = rows("rest")
        XCTAssertEqual(String(rest[10][1...5]), "ddddd", "a line along the muzzle")
        XCTAssertEqual(rest[9][6], "d", "its corner turned up")
        XCTAssertEqual(rest[9][3], "l", "one tiny fang over the lip")
        for y in 9...12 {
            for x in 0...9 { XCTAssertFalse(["k", "w", "g"].contains(rest[y][x]), "rest \(x),\(y): dark or warm at his mouth") }
        }
        for frame in gargle.frames {
            let flat = frame.name.contains("heat") || ["heat", "pant", "flop", "flopSigh", "heatLook"].contains(frame.name)
            let lowest = flat ? 13 : 9
            for (y, row) in frame.rows.enumerated() where row.contains("w") || row.contains("g") {
                XCTAssertLessThanOrEqual(y, lowest, "\(frame.name) row \(y): something warm below his eyes")
            }
        }
        // A puff rises from his nostril and goes; a hiccup's ember rises and goes out.
        let puff = distinct(gargle.plus.awake.gesture(named: "puff")!.ticks.map(\.frame))
        XCTAssertEqual(puff, ["puff1", "puff2", "puff3"])
        let heights = puff.map { name in rows(name).firstIndex { $0[0...1].contains { $0 != CompanionInk.clear } }! }
        XCTAssertEqual(heights, heights.sorted(by: >), "the smoke drifts up")
        XCTAssertLessThan(heights.last!, 8, "above the snout")
        let ember = distinct(gargle.plus.awake.gesture(named: "hiccup")!.ticks.map(\.frame))
        let embers = ember.map { name in rows(name).firstIndex { $0[0...1].contains("w") || $0[0...1].contains("g") }! }
        XCTAssertEqual(embers, embers.sorted(by: >), "the ember rises")
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
        // Brief 111: no waterspout in the rain any more, nothing pours from his mouth.
        XCTAssertFalse(gargle.rows("statue@rain")!.joined().contains("k"))
    }

    /// Its flourish: the grotesque's roar (both wings high, fangs, a glare, a puff of smoke), spoiled by a giggle.
    func testHePullsAGrotesquesFace() {
        let frames = gargle.plus.flourish.map(\.frame)
        XCTAssertTrue(frames.contains("boo") && frames.contains("booPuff") && frames.contains("giggle"))
        let boo = rows("boo")
        XCTAssertEqual(boo[10].filter { $0 == "l" }.count, 2, "two fangs")
        XCTAssertTrue(rows("booPuff")[3...5].contains { $0[0...1].contains("m") }, "a puff of smoke above his snout")
        XCTAssertTrue(boo[0...2].contains { $0[10...12].contains("d") }, "the far wing up beside the near one")
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
        XCTAssertTrue(gargle.rows("sleepPeek")!.joined().contains("w"), "his own amber eye")
        // Brief 111: two horns swept back and a spine down his neck; a snore is a wisp of smoke from his nostril.
        let sleepRows = rows("sleep")
        XCTAssertEqual(String(sleepRows[4][10...11]), "ll", "the second horn")
        XCTAssertEqual(sleepRows[6][11], "m", "a spine")
        let murmur = gargle.plus.asleep.gesture(named: "murmur")!.ticks.map(\.frame)
        for name in murmur {
            XCTAssertTrue(rows(name)[3...6].contains { $0[0...1].contains { $0 != CompanionInk.clear } }, "\(name): a wisp above the snout")
        }
    }

    /// Brief 91, as brief 111 has it: in the rain his brow is down and a drop runs off behind his head (a flicker that shows),
    /// and he shakes his head dry; snow piles up twice over (more each time, the seat untouched) until he shakes the heap off,
    /// from the heap only; on a hot day he lies flat on the cool stone and pants.
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
                XCTAssertGreaterThan(snow(deep), snow(previous), "\(at) \(deep)")
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
        XCTAssertEqual(String(rows("heat")[14][1...2]), "kk", "panting, his mouth a little open at the front")
        // Flat: his head is down on his paws, its top four rows lower than by day.
        let heat = rows("heat")
        let rest = rows("rest")
        let top = { (r: [[Character]]) in r.firstIndex { row in row[0...12].contains { $0 != CompanionInk.clear } }! }
        XCTAssertGreaterThanOrEqual(top(heat) - top(rest), 3, "lying flat")
    }

    /// Snow (round 22's recipe): powder, not a cap. Every snow still, awake and asleep, is drawn in the three snow inks and in
    /// all three, none of the old light ink added; the first is a dusting with gaps (no run of four across); it sits where it
    /// would stay (the horns' bases, the snout, the spine, the wing's edge; never across the horns: their tips stay stone),
    /// deeper each time, and no block of one snow ink larger than two by three.
    func testSnowIsPowderNotACap() {
        for mode in [gargle.plus.awake, gargle.plus.asleep] {
            let stills = [mode.snow!] + mode.snowDeep
            var previous = 0
            for name in stills {
                let flat = gargle.rows(name)!.joined()
                for ink in ["s", "b", "c"] as [Character] { XCTAssertTrue(flat.contains(ink), "\(name): all three tones") }
                XCTAssertLessThanOrEqual(count("l", name), count("l", mode.rest), "\(name): no old white cap")
                XCTAssertGreaterThan(snow(name), previous, name)
                previous = snow(name)
                let r = rows(name)
                for y in 0..<18 {
                    for x in 0..<18 {
                        let ink = r[y][x]
                        guard "sbc".contains(ink) else { continue }
                        let block = (0..<3).allSatisfy { dy in (0..<3).allSatisfy { dx in r[y + dy][x + dx] == ink } }
                        XCTAssertFalse(block, "\(name) \(x),\(y): a block of one snow ink")
                    }
                }
            }
            for row in rows(mode.snow!) {
                var run = 0
                for c in row {
                    run = "sbc".contains(c) ? run + 1 : 0
                    XCTAssertLessThan(run, 4, "\(mode.snow!): a dusting with gaps")
                }
            }
        }
        let deepest = rows(gargle.plus.awake.snowDeep.last!)
        XCTAssertEqual(String(deepest[1][7...8]), "ll", "the far horn's tip still stone under the deepest snow")
        XCTAssertEqual(String(deepest[1][11...12]), "ll", "and the near one's")
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
