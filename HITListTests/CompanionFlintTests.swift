import CryptoKit
import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 128 (round 25; George: "he's the only creature that doesn't fit the theme. He needs to have more cartoonish eyes
/// and appearance (not necessarily sillier, just less real), and perhaps make him a Gryffin"): Flint, Graphite's companion,
/// is a gryphon cub in place of Gargle the stone dragon (briefs 102 to 124). An eagle chick's head facing you on a lion
/// cub's body turned three-quarters on, drawn as the other seven are drawn: flat tones, eyes ringed in light, a peach beak
/// and talons, one folded wing, a short tail with a soft tuft. Every frame is also checked by `CompanionSpriteTests`,
/// `CompanionSeatTests` and `CompanionDirectorTests.testNeverADeadMinute`.
@MainActor
final class CompanionFlintTests: XCTestCase {
    private let flint = CompanionCharacter.flint

    private func rows(_ name: String) -> [[Character]] { flint.rows(name)!.map(Array.init) }

    private func count(_ ink: Character, _ name: String) -> Int { flint.rows(name)!.joined().filter { $0 == ink }.count }

    private func snow(_ name: String) -> Int { flint.rows(name)!.joined().filter { "sbc".contains($0) }.count }

    private func water(_ name: String) -> Int { flint.rows(name)!.joined().filter { "phu".contains($0) }.count }

    /// The pixels of `ink` in a frame with no neighbour of that ink above, below or beside them.
    private func lonely(_ ink: Character, _ name: String) -> [String] {
        let r = rows(name)
        var out: [String] = []
        for y in 0..<flint.height {
            for x in 0..<flint.width where r[y][x] == ink {
                var near = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let a = x + dx, b = y + dy
                    if a >= 0, a < flint.width, b >= 0, b < flint.height, r[b][a] == ink { near = true }
                }
                if !near { out.append("\(x),\(y)") }
            }
        }
        return out
    }

    /// The four rows by four columns of an eye whose ring starts at column `x` (rows 5 to 8 awake).
    private func eye(_ name: String, x: Int, y: Int = 5) -> [String] {
        let r = rows(name)
        return (y..<(y + 4)).map { String(r[$0][x..<(x + 4)]) }
    }

    func testGraphiteHasFlintAndSmudgeIsGone() {
        XCTAssertEqual(flint.problems, [])
        XCTAssertEqual(flint.name, "Flint")
        XCTAssertEqual(CompanionCast.character(forTheme: "graphite", launch: .none).id, "flint")
        XCTAssertEqual(CompanionCast.character(forTheme: "slate", launch: .none).id, "nod", "the others keep theirs")
        XCTAssertNil(CompanionCharacter.named("smudge"))
        XCTAssertNil(CompanionCharacter.named("gargle"))
        XCTAssertFalse(CompanionCast.byTheme.values.contains("smudge"))
        let old = CompanionLaunchOptions(arguments: ["-companion", "smudge"])
        XCTAssertEqual(CompanionCast.character(forTheme: "graphite", launch: old).id, "flint", "an old -companion smudge")
        let forced = CompanionLaunchOptions(arguments: ["-companion", "Flint"])
        XCTAssertEqual(CompanionCast.character(forTheme: "nord", launch: forced).id, "flint")
    }

    /// Brief 128: the drawing the supervisor passed (round 25) is pinned: `rest` and `sleep` by digest (SHA-256 of each
    /// still's rows joined by newlines). A change to either is a change George has not seen.
    func testHisRestAndSleepArePinned() {
        let pinned: [String: String] = [
            "rest": "2f94fb391643886aced814d44a5d6dcccdfce699503e453ab2a499f1e26023a4",
            "sleep": "d0a696098f607f0c43dc618b65b1be6fe228b9b76ec1c0b3fe1bfd8b58e4f666",
        ]
        for (name, digest) in pinned {
            let joined: String = flint.rows(name)!.joined(separator: "\n")
            let hash: String = SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, digest, "\(name) is the drawing that was passed")
        }
    }

    /// A gryphon cub, as the others are drawn: the theme's greys, its light and its warm peach (no accent); his head facing
    /// you with two feathered ear tufts and two eyes, each a dark 2 x 2 pupil in a ring of light (not Button's big round
    /// black eye: no three by three of ink anywhere); a small beak in the warm, hooked over its shade; a pale ruff; an
    /// eagle's talons in front in the warm, a lion's pale hind paw; one wing folded on his flank, dark, its leading edge
    /// light along his back, three light feather tips; a short tail with a soft tuft wider than it is tall.
    func testHeIsAGryphonCub() {
        XCTAssertEqual(flint.inks, [.ink, .dark, .mid, .light, .warm, .glow])
        XCTAssertEqual(flint.seatRow, 18)
        XCTAssertFalse(flint.flourishTurns)
        let rest = rows("rest")
        // The ear tufts rise from the crown at its two corners.
        XCTAssertEqual(rest[1][2], "m")
        XCTAssertEqual(rest[1][11], "m")
        XCTAssertEqual(String(rest[1][3...10]), "........", "a gap between the tufts")
        // Two eyes ringed in light.
        for x in [2, 8] {
            XCTAssertEqual(eye("rest", x: x), [".ll.", "lkkl", "lkkl", ".ll."].map { $0.replacingOccurrences(of: ".", with: "m") },
                           "the eye at \(x)")
        }
        for y in 0..<(flint.height - 2) {
            for x in 0..<(flint.width - 2) {
                var all = true
                for dy in 0..<3 { for dx in 0..<3 where rest[y + dy][x + dx] != "k" { all = false } }
                XCTAssertFalse(all, "a big round black eye at \(x),\(y)")
            }
        }
        // The beak: warm, between the eyes and under them, over its shade; the only warm on his face.
        XCTAssertEqual(String(rest[7][6...7]), "ww")
        XCTAssertEqual(String(rest[8][6...7]), "ww")
        XCTAssertEqual(String(rest[9][6...7]), "gg")
        XCTAssertEqual(rest[0...9].joined().filter { $0 == "w" }.count, 4)
        // The ruff, the talons and the hind paw.
        XCTAssertEqual(String(rest[11][3...8]), "llllll", "a pale ruff")
        XCTAssertEqual(String(rest[17][2...3]), "ww", "a talon")
        XCTAssertEqual(String(rest[17][6...7]), "ww", "a talon")
        XCTAssertEqual(String(rest[17][12...14]), "lll", "a lion's hind paw")
        // The wing on his flank: dark, its leading edge light along his back, three light tips on its trailing edge.
        XCTAssertEqual(String(rest[10][11...14]), "llll")
        XCTAssertEqual(String(rest[12][10...14]), "ddddd")
        XCTAssertEqual(String(rest[13][10...14]), "ldldl")
        // The tail: thin, a soft tuft at its end wider than it is tall, apart from the wing.
        var columns = Set<Int>()
        var tuftRows = Set<Int>()
        var tuft = 0
        for y in 5...9 {
            for x in 15..<20 where rest[y][x] == "l" {
                columns.insert(x)
                tuftRows.insert(y)
                tuft += 1
            }
        }
        XCTAssertGreaterThanOrEqual(tuft, 6)
        let width = columns.count, height = tuftRows.count
        XCTAssertGreaterThan(width, height, "a soft tuft, not a star on a wand")
        XCTAssertEqual(rest[10][15], ".", "dark between the wing and the tail")
        XCTAssertEqual(rest[10][16], ".")
    }

    /// Flat tones (the supervisor's rule for round 25: speckle is what made Gargle an illustration): in his rest no dark
    /// pixel stands alone. And no open eye is a single pixel, in any frame (round 24).
    func testFlatTonesAndNoEyeIsASinglePixel() {
        XCTAssertEqual(lonely("d", "rest"), [], "no stray dark pixel")
        XCTAssertEqual(lonely("w", "rest"), [])
        for frame in flint.frames {
            XCTAssertEqual(lonely("k", frame.name), [], "\(frame.name): a dark of one pixel")
        }
    }

    /// Nothing of him hangs behind the host or below his seat: the rows under it are empty in every frame.
    func testHeSitsOnTopAndNothingOfHimIsBehindTheBar() {
        for frame in flint.frames {
            for y in flint.seatRow..<flint.height {
                XCTAssertTrue(frame.rows[y].allSatisfy { $0 == CompanionInk.clear }, "\(frame.name) row \(y)")
            }
        }
    }

    /// Brief 131 seats him in Settings with `fly`: in the air, wings up, body level, the whole of him in the 20 x 20, facing
    /// the way `rest` faces (his head as it is at rest, on the left); `flyDown` the wings down. The flap routine plays them.
    func testHeFlies() {
        let rest = rows("rest")
        for name in ["fly", "flyDown"] {
            let r = rows(name)
            for y in 0...8 { XCTAssertEqual(Array(r[y][0...12]), Array(rest[y][0...12]), "\(name): his head as at rest, row \(y)") }
            let lowest = r.lastIndex { $0.contains { $0 != CompanionInk.clear } }!
            XCTAssertLessThan(lowest, flint.seatRow - 1, "\(name): off the bar")
        }
        let fly = rows("fly")
        XCTAssertTrue(fly[0...2].joined().contains("l") && fly[0...4].joined().contains("d"), "the wing up over his back")
        XCTAssertGreaterThan(fly[0...9].map { String($0[13...19]) }.joined().filter { $0 == "d" }.count, 20)
        let flap = flint.plus.awake.routines.first { $0.name == "flap" }!
        let frames = Set(flint.plus.awake.ticks(of: flap).map(\.tick.frame))
        XCTAssertTrue(frames.isSuperset(of: ["fly", "flyDown", "hover", "wingsUp"]))
        // The hover: a few pixels off the bar, his eyes down at it.
        let hover = rows("hover")
        XCTAssertLessThanOrEqual(hover.lastIndex { $0.contains { $0 != CompanionInk.clear } }!, flint.seatRow - 3)
    }

    /// Round 20's pace (brief 100): awake at least six flickers (the blink the heaviest) and four little loops, three
    /// routines of his own, a flourish and an answer; asleep at least three stirs. The same in both places. In every
    /// flicker his talons and paw stay where they are on the bar.
    func testHeIsAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = flint.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }.filter { $0.sky == nil }
            XCTAssertGreaterThanOrEqual(flickers.count, 6, at)
            XCTAssertEqual(flickers.max { $0.weight < $1.weight }?.name, "blink", at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter(\.little).count, 4, at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter { !$0.little && $0.sky == nil }.count, 3, at)
            for routine in awake.routines where routine.little {
                XCTAssertLessThanOrEqual(flint.duration(of: routine, mode: awake), 2.5, "\(at) \(routine.name)")
                XCTAssertTrue((2...4).contains(routine.moves), "\(at) \(routine.name)")
            }
            XCTAssertGreaterThanOrEqual(posture.asleep.gestures.filter { $0.sky == nil }.count, 3, at)
            XCTAssertTrue(posture.asleep.routines.isEmpty, at)
            let rest = rows(awake.rest)
            let edge = flint.seatRow - 1
            for gesture in flickers {
                for tick in gesture.ticks {
                    XCTAssertEqual(rows(tick.frame)[edge], rest[edge], "\(at) \(gesture.name): his feet stay on the bar")
                }
            }
        }
        XCTAssertEqual(flint.plus.awake.routines.map(\.name), flint.field.awake.routines.map(\.name))
        let names = Set(flint.plus.awake.routines.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["wag", "yawn", "lookAbout", "fluff", "preen", "pounce", "flap"]))
        let gestures = Set(flint.plus.awake.gestures.map(\.name))
        XCTAssertTrue(gestures.isSuperset(of: ["blink", "slowBlink", "twinkle", "glance", "earFlick", "swish", "cheep", "ruffle"]))
    }

    /// His three routines: he preens (head turned to his wing, eyes shut, a feather nibbled up); he swings his tail round in
    /// front of him, pounces on the tuft with both talons and it whisks away up behind him; he flaps and hovers.
    func testHisOwnRoutines() {
        XCTAssertGreaterThan(flint.difference("preen2", "rest"), 40, "his head turned and dipped to his wing")
        XCTAssertGreaterThan(flint.difference("preen3", "preen2"), 0, "the feather nibbled")
        let front = rows("tailFwd")
        XCTAssertEqual(String(front[15][8...10]), "lll", "the tuft lying in front of him")
        XCTAssertEqual(rows("tailFwd")[7][18], ".", "and not up behind")
        let gone = rows("tailGone")
        XCTAssertEqual(String(gone[17][4...7]), "wwww", "his talons together where the tuft was")
        XCTAssertNotEqual(String(gone[15][8...10]), "lll", "the tuft gone")
        XCTAssertTrue(gone[4...7].joined().contains("l"), "up behind him again")
    }

    /// Its flourish: wings up and a squeaky screech, spoiled by a giggle.
    func testHeScreechesAndGiggles() {
        let ticks = flint.plus.flourish.map(\.frame)
        XCTAssertTrue(ticks.contains("screech"))
        XCTAssertTrue(ticks.contains("giggle"))
        XCTAssertLessThan(ticks.firstIndex(of: "screech")!, ticks.firstIndex(of: "giggle")!)
        let screech = rows("screech")
        XCTAssertEqual(String(screech[9][6...7]), "kk", "his beak wide")
        XCTAssertGreaterThan(screech[0...4].joined().filter { $0 == "d" }.count, 10, "his wing up")
    }

    /// Asleep he lies down, his head low on his front with his eyes shut, the wing folded on his side as by day and the
    /// tuft over his talons; woken, one eye opens.
    func testAsleepHeLiesDown() {
        let sleep = rows("sleep")
        let top = sleep.firstIndex { $0.contains { $0 != CompanionInk.clear } }!
        XCTAssertGreaterThanOrEqual(top, 5, "lying down")
        XCTAssertEqual(eye("sleep", x: 2, y: 9), ["mmmm", "mmmm", "lkkl", "mllm"], "his eyes shut: a dark line, light under it")
        XCTAssertEqual(eye("sleep", x: 8, y: 9), ["mmmm", "mmmm", "lkkl", "mllm"])
        XCTAssertEqual(String(sleep[12][13...16]), "llll", "the wing's leading edge along his back")
        XCTAssertEqual(String(sleep[15][11...15]), "ldldl", "its three light tips")
        XCTAssertEqual(String(sleep[17][0...2]), "lll", "the tuft over his talons")
        XCTAssertEqual(eye("sleepPeek", x: 8, y: 9), ["mllm", "lkkl", "lkkl", "mllm"], "one eye opens")
        XCTAssertEqual(eye("sleepPeek", x: 2, y: 9)[1], "mmmm", "only one")
        XCTAssertGreaterThanOrEqual(flint.difference("sleep", "rest"), 60, "a pose of its own")
    }

    /// The weather, as round 24's water recipe and round 22's powder have it. In the rain he holds his wing over his head
    /// like a roof (its light leading edge on top), wet: two to four blue beads that stay, one hanging from the wing's front
    /// tip; a puddle round his front talons on the bar, four to eight wide, `p` with one glint and a deep pixel; now and then
    /// the drop lets go and lands in the puddle (a flicker); he peeks out; at thunder he ducks right under. Every frame the
    /// rain draws whole carries the puddle. Asleep in the rain too, the drop slower. On a hot day he pants, his wing held off
    /// his side.
    func testTheRainIsWaterOnHim() {
        let awake = flint.plus.awake
        XCTAssertEqual(awake.rain, "rain")
        let rain = rows("rain")
        // The wing an arc over his head, never a lid (the supervisor, round 25): its light top a curve whose ends sit lower
        // than its middle, dark under it, rising from his shoulder on a lean.
        XCTAssertEqual(String(rain[1][5...9]), "lllll", "the wing's leading edge over his head")
        XCTAssertEqual(String(rain[2][5...13]), "ddddddddd", "the wing over his head")
        XCTAssertEqual(rain[1][3], ".")
        XCTAssertEqual(rain[2][3], "l", "the front end lower than the middle")
        XCTAssertEqual(rain[5][0], "l", "the front edge down before his brow")
        var rims = Set<Int>()
        for y in 4...10 { if let x = rain[y].lastIndex(of: "l"), x > 12 { rims.insert(x) } }
        XCTAssertGreaterThanOrEqual(rims.count, 3, "his wing's back edge on a lean, not a bar")
        for x in [2, 8] { XCTAssertEqual(eye("rain", x: x), eye("rest", x: x), "his eyes as they are") }
        func beads(_ name: String) -> Int { rows(name)[0...16].joined().filter { "ph".contains($0) }.count }
        for name in ["rain", "sleepRain"] {
            XCTAssertTrue((2...4).contains(beads(name)), "\(name): two to four beads, \(beads(name))")
            let bar = rows(name)[flint.seatRow - 1]
            let wet = bar.indices.filter { "phu".contains(bar[$0]) }
            XCTAssertTrue((4...8).contains(wet.last! - wet.first! + 1), "\(name): a puddle four to eight wide")
            XCTAssertEqual(bar.filter { $0 == "h" }.count, 1, "\(name): one glint")
            XCTAssertEqual(bar.filter { $0 == "u" }.count, 1, "\(name): one deep pixel")
        }
        let drip = awake.gesture(named: "drip")!
        XCTAssertTrue(drip.flicker)
        XCTAssertEqual(drip.sky, .rain)
        var falls = false
        for tick in drip.ticks {
            let below: String = rows(tick.frame)[8...15].map { String($0[0...1]) }.joined()
            if below.contains("p") || below.contains("h") { falls = true }
        }
        XCTAssertTrue(falls, "a drop falls")
        for routine in awake.routines where routine.sky == .rain || routine.sky == .storm {
            for entry in awake.ticks(of: routine) where entry.tick.frame != awake.rest {
                XCTAssertGreaterThanOrEqual(water(entry.tick.frame), 6, "\(routine.name) \(entry.tick.frame): still wet")
            }
        }
        for gesture in awake.gestures where gesture.sky == .rain {
            for tick in gesture.ticks { XCTAssertGreaterThanOrEqual(water(tick.frame), 6, "\(tick.frame): still wet") }
        }
        XCTAssertTrue(awake.routines.contains { $0.sky == .rain }, "he peeks out")
        XCTAssertTrue(awake.routines.contains { $0.sky == .storm }, "he ducks at thunder")
        XCTAssertEqual(flint.plus.asleep.rain, "sleepRain")
        XCTAssertNotNil(flint.plus.asleep.gesture(named: "drip"))
        // The reply to a tap and the blink still play in the rain.
        XCTAssertTrue(flint.canDraw(awake.answer, in: .rain, mode: awake, depth: 0))
        XCTAssertTrue(flint.canDraw(awake.gesture(named: "blink")!, in: .rain, mode: awake, depth: 0))
        // Heat: his own way of being hot.
        XCTAssertEqual(awake.heat, "heat")
        XCTAssertEqual(String(rows("heat")[8][6...7]), "kk", "panting")
        XCTAssertTrue(awake.gestures.contains { $0.sky == .heat && $0.flicker })
        XCTAssertTrue(awake.routines.contains { $0.sky == .heat })
    }

    /// Snow (round 22's recipe): powder, not a cap. Each still, awake and asleep, in the three snow inks, deeper each time,
    /// the seat untouched, no block of one snow ink larger than two by three, none of the old light ink; his eyes and the
    /// tips of his ear tufts never under; then he shakes it off, from the deepest pile only.
    func testSnowIsPowderNotACap() {
        let awake = flint.plus.awake
        XCTAssertEqual(awake.snowDeep, ["snow2", "snow3"])
        var previous = "snow"
        for name in awake.snowDeep {
            XCTAssertGreaterThan(snow(name), snow(previous), "\(name): deeper")
            previous = name
        }
        XCTAssertGreaterThan(snow("sleepSnow2"), snow("sleepSnow"))
        for name in ["snow", "snow2", "snow3", "sleepSnow", "sleepSnow2"] {
            let r = rows(name)
            for ink in ["s", "b", "c"] as [Character] { XCTAssertTrue(r.joined().contains(ink), "\(name): \(ink)") }
            XCTAssertEqual(count("l", name), count("l", name.hasPrefix("sleep") ? "sleep" : "rest"), "\(name): no old light snow")
            for ink in ["s", "b", "c"] as [Character] {
                for y in 0..<(flint.height - 2) {
                    for x in 0..<(flint.width - 1) {
                        var all = true
                        for dy in 0..<3 { for dx in 0..<2 where r[y + dy][x + dx] != ink { all = false } }
                        XCTAssertFalse(all, "\(name): a block of \(ink) at \(x),\(y)")
                    }
                }
            }
        }
        for name in ["snow", "snow2", "snow3"] {
            for x in [2, 8] { XCTAssertEqual(eye(name, x: x), eye("rest", x: x), "\(name): his eyes clear") }
            XCTAssertEqual(rows(name)[1][2], "m", "\(name): his tuft's tip")
            XCTAssertEqual(rows(name)[1][11], "m", "\(name): his tuft's tip")
        }
        let first = rows("snow")
        for y in 0..<flint.height {
            let line = String(first[y].map { "sbc".contains($0) ? "*" : "." })
            XCTAssertFalse(line.contains("****"), "the dusting has gaps (row \(y))")
        }
        let shake = awake.routines.first { $0.shakesOff }!
        XCTAssertTrue(flint.canDraw(shake, in: .snow, mode: awake, depth: awake.deepest))
        XCTAssertFalse(flint.canDraw(shake, in: .snow, mode: awake, depth: 0))
        XCTAssertEqual(flint.field.awake.snowDeep, awake.snowDeep)
    }

    /// Brief 100: an idle can be drawn over every still it may show, so it is never still for long whatever the sky.
    func testAnIdleDrawsOverEveryStill() {
        for place in CompanionPlace.allCases {
            let posture = flint.posture(place)
            for (label, mode) in [("awake", posture.awake), ("asleep", posture.asleep)] {
                var looks: [(CompanionLook.Weather, Int)] = [(.plain, 0), (.rain, 0), (.snow, 0), (.heat, 0)]
                for depth in 0..<mode.snowDeep.count { looks.append((.snow, depth + 1)) }
                for (weather, depth) in looks {
                    let candidates = label == "asleep" ? mode.gestures : mode.flickers.map { mode.gestures[$0] }
                    let drawable = candidates.filter { gesture in
                        guard let sky = gesture.sky else {
                            return flint.canDraw(gesture, in: weather, mode: mode, depth: depth)
                        }
                        return CompanionLook.Weather(sky) == weather && flint.canDraw(gesture, in: weather, mode: mode, depth: depth)
                    }
                    XCTAssertFalse(drawable.isEmpty, "\(place) \(label) \(weather) \(depth): an idle that draws")
                }
            }
            // The reply to a tap plays in every weather (a frame of its own on a hot day).
            for weather in CompanionLook.Weather.allCases {
                XCTAssertTrue(flint.canDraw(posture.awake.answer, in: weather, mode: posture.awake, depth: 0), "\(place) \(weather)")
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
        let offset = CompanionPerch.offset(flint, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(flint.width) * p
        let left: CGFloat = size.width - spriteWidth + offset.width
        let posture = flint.plus
        var stills: [String] = []
        for mode in [posture.awake, posture.asleep] { stills.append(contentsOf: mode.stills) }
        let edge = flint.seatRow - 1
        for name in stills {
            let rows = rows(name)
            for c in 0..<flint.width where rows[edge][c] != CompanionInk.clear {
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
        let rest = flint.index[flint.plus.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: flint.drawn[rest], width: flint.width, mirrored: false,
                                                belowRow: flint.seatRow)
        let offset = CompanionPerch.offset(flint, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(flint.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let top: CGFloat = offset.height
        XCTAssertTrue(shape.contains(CGPoint(x: size.width - 24 - left, y: -14 - top)), "a tap on him is his own")
        XCTAssertFalse(shape.contains(CGPoint(x: size.width - 22 - left, y: 3 - top)), "a tap under his paws is the +'s")
    }

}
