import CryptoKit
import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Briefs 102, 104, 111 and 117: Gargle, Graphite's companion, a stone dragon pup carved for a ledge and come half alive
/// on it. Round 21 (brief 104) carved his body side-on along the edge as his elders sit on a cornice, nothing of him over
/// the front, a wing folded up his back, his tail behind the host (brief 104's capitals) with only its spade back up beside
/// him. Round 22 (brief 111) made him more of a dragon. Round 23 (brief 117; George: "a tad too big and not cute enough. I
/// still adore the nighttime sprite"): awake he is v0.9.6's night sprite with his eye open, side-on, that size, those horns,
/// that wing; one round eye with a light in it, his mouth closed with its corner up. The night sprite itself is v0.9.6's,
/// pixel for pixel. Every frame is also checked by `CompanionSpriteTests`, `CompanionSeatTests` and
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

    /// A stone dragon pup (briefs 111 and 117): two tones of stone and a highlight; in profile, his snout sticking out to the
    /// left past his crown; two pale horns swept back off the crown; one eye of his own, dark with a light in it and a warm
    /// glint low in its iris (not Button's round black eye); a wing up his back, a dark membrane with lighter ribs and a
    /// pale hooked tip.
    func testHeIsAStoneDragonPup() {
        XCTAssertEqual(gargle.inks, [.ink, .dark, .mid, .light, .warm, .glow])
        XCTAssertEqual(gargle.seatRow, 18)
        let rest = rows("rest")
        // The snout: the head reaches the left edge at the muzzle's rows and starts two or more columns in at the crown's.
        let left = { (y: Int) in rest[y].firstIndex { $0 != CompanionInk.clear }! }
        XCTAssertEqual(left(8), 0, "the snout's tip")
        XCTAssertGreaterThanOrEqual(left(4), 3, "the crown set back behind it")
        // Two horns swept back: pale along their length, each rising to the right (backwards) off the crown.
        XCTAssertEqual(rest[1][9], "l", "the far horn's tip")
        XCTAssertEqual(String(rest[2][7...8]), "ll")
        XCTAssertEqual(rest[3][6], "l")
        XCTAssertEqual(rest[2][12], "l", "the near horn's tip")
        XCTAssertEqual(String(rest[3][10...11]), "ll")
        // One eye: a light (`l`) in the dark of it, with the warm glint under the light.
        var lights: [(Int, Int)] = []
        for y in 4...8 {
            for x in 1..<10 where rest[y][x] == "l" {
                let around = [rest[y - 1][x], rest[y][x - 1], rest[y][x + 1]]
                if around.allSatisfy({ $0 == "k" }), rest[y + 1][x] == "w" { lights.append((x, y)) }
            }
        }
        XCTAssertEqual(lights.count, 1, "a light in his eye")
        XCTAssertEqual(count("w", "rest"), 1, "a warm glint, no more")
        XCTAssertFalse(rest[0...12].joined().contains("g"))
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

    /// Brief 117: awake he is the night sprite with his eye open. `rest` is v0.9.6's `sleepBreathe` (the sleep with his head
    /// up a pixel) but for the eye, the mouth and the spade a pixel up; his head is no higher than that, and no wider.
    func testAwakeHeIsTheNightSpriteWithHisEyeOpen() {
        XCTAssertLessThanOrEqual(gargle.difference("rest", "sleepBreathe"), 16, "the night sprite, his eye open")
        let rest = rows("rest")
        let sleep = rows("sleep")
        let top = { (r: [[Character]]) in r.firstIndex { row in row[0...12].contains { $0 != CompanionInk.clear } }! }
        XCTAssertEqual(top(sleep) - top(rest), 1, "his head up a pixel at most")
        let drawn = { (r: [[Character]]) in r.joined().filter { $0 != CompanionInk.clear }.count }
        XCTAssertLessThanOrEqual(drawn(rest), drawn(rows("sleepBreathe")) + 4, "no bigger than the night sprite (its spade up)")
        XCTAssertLessThan(drawn(rest), 265, "smaller than v0.9.6's awake Gargle, 265 pixels (\"a tad too big\")")
        // Same horns, same wing, same body: everything off his eye, his mouth and the spade is the night sprite's.
        let breath = rows("sleepBreathe")
        for y in 0..<gargle.height {
            for x in 0..<gargle.width where !(3...6).contains(x) || !(4...9).contains(y) {
                if x <= 4, (8...10).contains(y) { continue }
                if x >= 17, (14...16).contains(y) { continue }
                XCTAssertEqual(rest[y][x], breath[y][x], "rest \(x),\(y) is the night sprite's")
            }
        }
        // His blink is the night sprite's shut line.
        XCTAssertEqual(String(rows("blink")[7][3...6]), "dddd")
        XCTAssertEqual(String(breath[7][3...6]), "dddd")
    }

    /// Brief 117: the night sprite George adores does not change by one pixel. The digests are of each asleep still's rows
    /// joined by newlines, computed once from `git show v0.9.6:HITList/Support/Companions/Characters/Gargle.swift`.
    func testTheNightSpriteIsZeroNineSixsPixelForPixel() {
        let v096: [String: String] = [
            "sleep": "d04e0843ba17bc072c097e7769d4df8161136cc11f8e077d4d31e1c75f27dfdd",
            "sleepSnow": "5e1130c8b7f99eaee9fcbbbaf9f4b80743ab942658d8d1a11a4753379588e459",
            "sleepSnow2": "335ea9bfb786d9839ff50821aa54e1a244796263c001496baac8abc2e8c3f2b9",
        ]
        func digest(_ name: String) -> String? {
            guard let rows = gargle.rows(name) else { return nil }
            let data = Data(rows.joined(separator: "\n").utf8)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        for (name, expected) in v096 { XCTAssertEqual(digest(name), expected, "\(name) is 0.9.6's") }
        for place in CompanionPlace.allCases {
            let asleep = gargle.posture(place).asleep
            XCTAssertEqual(asleep.rest, "sleep")
            XCTAssertEqual(asleep.snow, "sleepSnow")
            XCTAssertEqual(asleep.snowDeep, ["sleepSnow2"])
        }
    }

    /// His mouth never reads as being sick (brief 111; George: "Gargle looks like he's throwing up"). At rest it is closed: the
    /// night sprite's line along the muzzle with its corner turned up (brief 117: no fang), nothing dark in it and nothing
    /// under it.
    /// In every frame nothing warm (an iris, an ember) is lower than his eyes, so whatever leaves him (a puff of smoke, an
    /// ember) goes up and away from the snout's end.
    func testHisMouthIsClosedAndNothingComesOutOfIt() {
        let rest = rows("rest")
        XCTAssertEqual(String(rest[9][0...3]), "dddd", "a line along the muzzle")
        XCTAssertEqual(rest[8][4], "d", "its corner turned up")
        XCTAssertFalse(rest[8...11].contains { $0[0...5].contains("l") }, "no fang")
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
        XCTAssertTrue(names.isSuperset(of: ["statue", "periscope", "yawn", "wag", "statueGame", "stretch", "dust", "tryFly"]))
        // Brief 117's idles: a glance, a horn flicked like an ear, the wing ruffled, the spade, a puff and an ember.
        let gestures = Set(gargle.plus.awake.gestures.map(\.name))
        XCTAssertTrue(gestures.isSuperset(of: ["glance", "hornFlick", "shrug", "tipFlick", "puff", "hiccup"]))
    }

    /// The statue (briefs 104 and 117): he is already in profile, so he simply freezes, eye shut, a shade paler (the stone's
    /// shading lifts a tone, fewer dark pixels than the pup), holds, and a peek (an eye with its light) gives him away.
    func testHePlaysStatue() {
        let awake = gargle.plus.awake
        let statue = awake.routines.first { $0.name == "statueGame" }!
        let frames = awake.ticks(of: statue).map(\.tick.frame)
        XCTAssertTrue(frames.contains("statue") && frames.contains("statuePeek") && frames.contains("statueGrin"))
        XCTAssertLessThan(count("d", "statue"), count("d", "rest"), "a shade paler")
        XCTAssertFalse(gargle.rows("statue")!.joined().contains("w"), "no glint on a statue")
        XCTAssertFalse(gargle.rows("statue")!.joined().contains("k"), "his eye shut")
        XCTAssertTrue(gargle.rows("statuePeek")!.joined().contains("k"), "the peek: an eye opens")
        XCTAssertTrue(gargle.rows("statuePeek")!.joined().contains("l"))
        XCTAssertLessThanOrEqual(gargle.difference("statue", "rest"), 24, "the same profile, frozen")
        // The quick one, a little loop, the same statue.
        let quick = awake.routines.first { $0.name == "statue" }!
        XCTAssertTrue(quick.little)
        XCTAssertTrue(awake.ticks(of: quick).map(\.tick.frame).contains("statue"))
    }

    /// Its flourish: the grotesque's roar (both wings high, fangs, a glare, a puff of smoke), spoiled by a giggle.
    func testHePullsAGrotesquesFace() {
        let frames = gargle.plus.flourish.map(\.frame)
        XCTAssertTrue(frames.contains("boo") && frames.contains("booPuff") && frames.contains("giggle"))
        let boo = rows("boo")
        XCTAssertEqual(boo[9][0...4].filter { $0 == "l" }.count, 2, "two fangs")
        XCTAssertTrue(rows("booPuff")[3...5].contains { $0[0...1].contains("m") }, "a puff of smoke above his snout")
        XCTAssertTrue(boo[0...2].contains { $0[10...12].contains("d") }, "the far wing up beside the near one")
        XCTAssertEqual(gargle.flourishDuration(.plus), gargle.flourishDuration(.field))
    }

    /// Asleep he has turned to stone (brief 104: in profile, the statue's pose with its head down a pixel): no dark of an eye,
    /// no tongue; woken, his eye opens (brief 117: his awake eye).
    func testAsleepHeTurnsToStone() {
        let sleep = gargle.rows("sleep")!.joined()
        XCTAssertFalse(sleep.contains("k"), "no dark of an eye: a carved line")
        XCTAssertFalse(sleep.contains("w"), "no tongue")
        XCTAssertEqual(gargle.plus.asleep.rest, "sleep")
        XCTAssertEqual(gargle.plus.asleep.rain, "sleepRain", "asleep in the rain: his own still (brief 124)")
        XCTAssertTrue(gargle.rows("sleepPeek")!.joined().contains("k"), "woken: one eye opens")
        XCTAssertTrue(gargle.rows("sleepPeek")!.joined().contains("w"), "his own eye, its warm glint")
        XCTAssertLessThanOrEqual(gargle.difference("sleepPeek", "sleep"), 10, "only his eye opens")
        // Brief 111: two horns swept back and a spine down his neck; a snore is a wisp of smoke from his nostril.
        let sleepRows = rows("sleep")
        XCTAssertEqual(String(sleepRows[4][10...11]), "ll", "the second horn")
        XCTAssertEqual(sleepRows[6][11], "m", "a spine")
        let murmur = gargle.plus.asleep.gesture(named: "murmur")!.ticks.map(\.frame)
        for name in murmur {
            XCTAssertTrue(rows(name)[3...6].contains { $0[0...1].contains { $0 != CompanionInk.clear } }, "\(name): a wisp above the snout")
        }
    }

    /// Brief 91, as brief 117 has it: in the rain he ducks his head and holds his wing over it like a roof, his eye looking up
    /// from under it, a drop running off its tip (a flicker that shows); now and then he peeks out, and at thunder he ducks
    /// right under. Snow piles up twice over (more each time, the seat untouched) until he shakes the heap off, from the heap
    /// only; on a hot day he lies low on the cool stone and pants.
    func testTheWeatherShowsOnHim() {
        for place in CompanionPlace.allCases {
            let awake = gargle.posture(place).awake
            let at = "\(place)"
            let drip = awake.gesture(named: "drip")!
            XCTAssertEqual(drip.sky, .rain)
            XCTAssertTrue(drip.flicker)
            // Brief 124: the drop that runs off is only water moving over the wet still, under a second.
            for tick in drip.ticks { XCTAssertTrue((1...4).contains(gargle.difference(tick.frame, awake.rain!)), "\(at): one drop") }
            XCTAssertLessThan(Double(drip.ticks.count) / gargle.gestureFPS, 1, at)
            XCTAssertEqual(awake.routines.first { $0.sky == .rain }?.name, "peek", at)
            XCTAssertEqual(awake.routines.first { $0.sky == .storm }?.name, "duck", at)
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
            XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "loll", at)
        }
        // The rain: his wing off his back and over his head, rising from his shoulder in a curve over his crown and down in
        // front of his snout to a point (higher at the shoulder than at the tip), a lighter rib along its leading edge, the
        // membrane under it in scallops, a drop on its tip; his eye open under it, looking up; his far horn still shows.
        let rain = rows("rain")
        XCTAssertEqual(String(rain[0][8...13]), "mmmmmm", "the rib, highest over his crown")
        XCTAssertEqual(String(rain[1][8...13]), "dddddd", "its membrane")
        XCTAssertEqual(rain[5][0], "m", "its tip, down in front of his snout")
        XCTAssertEqual(String([rain[6][0], rain[7][0]]), "hp", "a drop hanging from it, blue (brief 124)")
        let tops = (0..<gargle.width).map { x in (0..<gargle.height).first { rain[$0][x] != CompanionInk.clear } ?? 99 }
        XCTAssertEqual(tops[0...10].map { $0 }, tops[0...10].sorted(by: >), "it curves up from the tip to the crown")
        XCTAssertGreaterThanOrEqual(String(rain[2][0...16]).components(separatedBy: ".").filter { $0.contains("d") }.count, 3,
                                    "scallops along its lower edge")
        // The same seat, a puddle on it at his front paws (brief 124): only water differs on the edge row.
        let dry = rows("rest")
        for y in 14...19 {
            for x in 0..<gargle.width where rain[y][x] != dry[y][x] {
                XCTAssertTrue(y == 17 && x < 8 && "phu".contains(rain[y][x]), "the same seat: \(x),\(y)")
            }
        }
        XCTAssertEqual(rain[2][9], "l", "his far horn under it")
        XCTAssertTrue(rain[6...8].contains { $0[3...6].contains("k") }, "his eye open")
        XCTAssertEqual(rain[6][4], "l", "looking up")
        XCTAssertFalse(String(rain[0][13...16]).contains("l"), "the wing is off his back")
        // Thunder: he ducks right under, eye shut.
        let duck = rows("rainDuck")
        XCTAssertFalse(duck[4...9].contains { $0[3...6].contains("k") }, "his eye shut")
        XCTAssertEqual(String(duck[1][8...13]), "mmmmmm", "the wing a pixel lower")
        // Low on the cool stone: his head down at the night sprite's height, his eye half shut, his mouth open a little.
        let heat = rows("heat")
        let rest = rows("rest")
        let top = { (r: [[Character]]) in r.firstIndex { row in row[0...12].contains { $0 != CompanionInk.clear } }! }
        XCTAssertEqual(top(heat) - top(rest), 1, "lying low")
        XCTAssertEqual(heat[10][1], "k", "panting, his mouth a little open at the front")
    }

    /// Brief 124 (George: "During rain, they should have little droplets bead off of them every once in a while, and have
    /// some droplets stick around or tiny puddles pool around their feet"): in the rain, awake and asleep, blue beads on
    /// him (on the wing's outline, at its tip, on his snout; asleep on his wing, his back and his snout), a puddle under his
    /// front paws, and now and then a drop that runs off into it. No drop is left in the old light ink, nothing blinks out
    /// (every frame the rain draws whole is wet), and the blink, the glance up and the reply to a tap still play over it.
    func testTheRainIsWaterOnHim() {
        let water: Set<Character> = ["p", "h", "u"]
        func puddle(_ name: String) -> [Int] {
            rows(name)[gargle.seatRow - 1].indices.filter { water.contains(rows(name)[gargle.seatRow - 1][$0]) }
        }
        for place in CompanionPlace.allCases {
            let posture = gargle.posture(place)
            for mode in [posture.awake, posture.asleep] {
                let still = mode.rain!
                let at = "\(place) \(still)"
                let flat = gargle.rows(still)!.joined()
                for ink in water { XCTAssertTrue(flat.contains(ink), "\(at): all three blues") }
                XCTAssertLessThanOrEqual(count("l", still), count("l", mode.rest), "\(at): no drop in the old light ink")
                let pool = puddle(still)
                XCTAssertTrue((4...8).contains(pool.count), "\(at): a puddle four to eight wide, not a plinth")
                XCTAssertLessThanOrEqual(pool.max()! - pool.min()!, 7, at)
                let beads = rows(still)[0..<(gargle.seatRow - 1)].joined().filter { water.contains($0) }.count
                XCTAssertTrue((3...5).contains(beads), "\(at): a few beads, one of them two tall")
                let drip = mode.gestures.first { $0.sky == .rain }!
                XCTAssertLessThan(Double(drip.ticks.count) / gargle.gestureFPS, 1, at)
                // The drop is the only thing in the air: one run of water off him at a time, and it lands in the puddle.
                let landing = drip.ticks.last!.frame
                XCTAssertEqual(puddle(landing), pool, "\(at): it lands in the puddle")
                XCTAssertNotEqual(rows(landing)[gargle.seatRow - 1], rows(still)[gargle.seatRow - 1], "\(at): its glint jumps")
                XCTAssertTrue(gargle.canDraw(mode.answer, in: .rain, mode: mode, depth: 0), "\(at): the reply to a tap")
            }
            // Every frame the rain draws whole carries the puddle.
            let awake = posture.awake
            for tick in awake.wholeTicks(sky: .rain) + awake.wholeTicks(sky: .storm) {
                XCTAssertEqual(puddle(tick.frame).count, puddle(awake.rain!).count, "\(place) \(tick.frame): the puddle stays")
            }
            for name in ["blink@rain", "lookUp@rain", "winkFlick@rain", "sleepBreathe@sleepRain"] {
                XCTAssertFalse(puddle(name).isEmpty, "\(name): the puddle stays")
            }
            XCTAssertTrue(gargle.canDraw(awake.gesture(named: "blink")!, in: .rain, mode: awake, depth: 0), "\(place): a blink")
            XCTAssertTrue(gargle.canDraw(awake.gesture(named: "lookUp")!, in: .rain, mode: awake, depth: 0), "\(place)")
            XCTAssertTrue(gargle.canDraw(posture.asleep.gesture(named: "breathe")!, in: .rain, mode: posture.asleep, depth: 0),
                          "\(place): his breath, asleep in the rain")
        }
        // The drop runs off the wing's tip onto his nose, hangs from his chin and falls into the puddle at his paws.
        let path = gargle.plus.awake.gesture(named: "drip")!.ticks.map(\.frame)
        XCTAssertEqual(rows(path[0])[7][0], "u", "it swells at the wing's tip")
        XCTAssertTrue(path.contains { rows($0)[12][0] == "p" }, "it hangs from his chin")
        XCTAssertTrue(path.contains { rows($0)[14][0] == "h" && rows($0)[15][0] == "p" }, "it falls")
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
        // Brief 117: his horns' tips still stone at every depth; at the deepest he has drawn his wing over his head and the
        // snow lies on it, ragged, thicker toward the back.
        for name in ["snow", "snow2"] {
            let r = rows(name)
            XCTAssertEqual(r[1][9], "l", "\(name): the far horn's tip")
            XCTAssertEqual(r[2][12], "l", "\(name): the near one's")
        }
        let deepest = rows(gargle.plus.awake.snowDeep.last!)
        XCTAssertEqual(deepest[1][9], "l", "the far horn's tip under the deepest snow")
        XCTAssertEqual(deepest[2][12], "l", "and the near one's")
        var back = 0
        var front = 0
        for row in deepest {
            for (x, c) in row.enumerated() where "sbc".contains(c) {
                if x >= 10 { back += 1 } else { front += 1 }
            }
        }
        XCTAssertGreaterThan(back, front, "deeper toward his back")
        XCTAssertEqual(gargle.difference(gargle.plus.awake.snowDeep.last!, "rest"), snow(gargle.plus.awake.snowDeep.last!),
                       "only snow on him: no hat, no pose of its own")
    }

    /// Brief 124 (George: "He looks barely recognizable in deep snow"): deeper, only the drifts grow. Every pixel of him that
    /// the first dusting leaves stone stays stone at every depth (his horn tips, his brow, his eye, his snout's tip, the
    /// wing's outline), so at 1x beside `rest` he is still Gargle; the snow lies along his back, the wing's slope and elbow,
    /// his nape and against his toes, and the drift in his back's hollow is the deepest.
    func testDeepSnowLeavesHimHisOwnStone() {
        let awake = gargle.plus.awake
        let rest = rows(awake.rest)
        let dusting = rows(awake.snow!)
        for deep in awake.snowDeep {
            let pile = rows(deep)
            for y in 0..<gargle.height {
                for x in 0..<gargle.width where rest[y][x] != CompanionInk.clear {
                    XCTAssertEqual(pile[y][x], dusting[y][x], "\(deep) \(x),\(y): more of him covered")
                }
            }
            XCTAssertTrue(pile[4...8].allSatisfy { row in !row[2...6].contains { "sbc".contains($0) } }, "\(deep): his brow and eye are clear")
        }
        let deepest = rows(awake.snowDeep.last!)
        let hollow = (9...11).filter { y in (10...12).contains { "sbc".contains(deepest[y][$0]) } }
        XCTAssertEqual(hollow.count, 3, "three deep in his back's hollow")
        XCTAssertEqual(gargle.field.awake.snowDeep, awake.snowDeep)
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
