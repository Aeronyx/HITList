import CryptoKit
import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 102: Button, Rosé's companion in place of Posy. A button mushroom in the theme's own rose, its face on its
/// stem, two boots; alive at round 20's pace (brief 100) and the weather on it (brief 91). Round 21 redrew it small;
/// round 22 brings 0.9.4's back pixel for pixel (brief 109; George: "Please completely revert to the previous mushroom
/// creature … I actually kind of liked his creepy-but-slightly-endearing big-eyed smile and rosy cheeks. His sleeping
/// sprite was also great."). Every frame is also checked by `CompanionSpriteTests` (good data, small gestures, crisp
/// pixels, all eight palettes), `CompanionSeatTests` and `CompanionDirectorTests.testNeverADeadMinute`.
@MainActor
final class CompanionButtonTests: XCTestCase {
    private let button = CompanionCharacter.button

    func testRoseHasButtonAndPosyAndPipAreGone() {
        XCTAssertEqual(button.problems, [])
        XCTAssertEqual(button.name, "Button")
        XCTAssertEqual(CompanionCast.character(forTheme: "rose", launch: .none).id, "button")
        for gone in ["posy", "pip"] {
            XCTAssertNil(CompanionCharacter.named(gone), gone)
            XCTAssertFalse(CompanionCast.byTheme.values.contains(gone), gone)
            // An old `-companion posy` falls back to the theme's.
            let old = CompanionLaunchOptions(arguments: ["-companion", gone])
            XCTAssertEqual(CompanionCast.character(forTheme: "rose", launch: old).id, "button", gone)
        }
        let forced = CompanionLaunchOptions(arguments: ["-companion", "button"])
        XCTAssertEqual(CompanionCast.character(forTheme: "nord", launch: forced).id, "button")
    }

    /// Brief 109, "completely revert": every still it shows that is not snow or rain (awake, heat, asleep; the same in
    /// both places) is 0.9.4's, row for row. The digests are of each still's rows joined by newlines, computed once
    /// from `git show v0.9.4:HITList/Support/Companions/Characters/Button.swift`. The rain's is brief 120's: the cap
    /// pulled down over its eyes (George: "grab his mushroom hood and warp it down a bit, attempting to hide"), with brief
    /// 124's water on it (blue beads on the cap, its two drops blue, a puddle round its boots).
    func testItIsZeroNineFoursButtonPixelForPixel() {
        let v094: [String: String] = [
            "rest": "5a6420179c928ee7fce5f6ffbfec11a6408a184482c7879efd979a8be0ec0c1a",
            "rain": "38f0771fd5362d9d962ff527fec45c0425d0d4363a6f8d2634c753aa70e95dbd",
            "heat": "7bcbb8e948ea38c99f254b33721bd8870fbf6788fe238fc3681da63fb2ed3ca8",
            "sleep": "2f79dd4fa7141ec21214971a993bea07b540d03ac6463a799ec82139de22db83",
        ]
        func digest(_ name: String) -> String? {
            guard let rows = button.rows(name) else { return nil }
            let data = Data(rows.joined(separator: "\n").utf8)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        for (name, expected) in v094 { XCTAssertEqual(digest(name), expected, "\(name) is 0.9.4's (the rain brief 120's, wet)") }
        XCTAssertEqual(button.width, 20)
        XCTAssertEqual(button.height, 20)
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            XCTAssertEqual(posture.awake.rest, "rest", "\(place)")
            XCTAssertEqual(posture.awake.rain, "rain", "\(place)")
            XCTAssertEqual(posture.awake.heat, "heat", "\(place)")
            XCTAssertEqual(posture.asleep.rest, "sleep", "\(place)")
        }
    }

    /// A mushroom at a glance: a cap in the accent (with its own shade) half its height and wider than its body by
    /// three pixels a side, pale spots on it, a pale face on the stem with two big round eyes, each with a glint, rosy
    /// cheeks, and two boots of a pixel's height standing on the edge (brief 109: seat row 19, the soles on the host).
    func testItIsAMushroomInTheThemesRose() {
        XCTAssertEqual(button.inks, [.ink, .dark, .mid, .light, .accent, .accentDark])
        XCTAssertEqual(button.seatRow, 19)
        let rest = button.rows("rest")!.map(Array.init)
        func count(_ ink: Character, _ rows: ArraySlice<[Character]>) -> Int { rows.joined().filter { $0 == ink }.count }
        // The cap: rows 1 to 10, mostly rose, with pale marks; its widest row spans the sprite.
        XCTAssertGreaterThan(count("a", rest[1...10]), 100)
        XCTAssertGreaterThanOrEqual(count("l", rest[1...10]), 8, "spots and a sheen")
        XCTAssertEqual(rest[8].filter { $0 != CompanionInk.clear }.count, 20)
        // The body under it, at most 16 wide, three pixels in from the cap's ends at its top.
        XCTAssertEqual(rest[12].filter { $0 != CompanionInk.clear }.count, 14)
        XCTAssertLessThanOrEqual(rest[14].filter { $0 != CompanionInk.clear }.count, 16)
        // Two eyes, each with a glint inside it: a light pixel with the eye's dark on all four sides.
        var glints = 0
        for y in 12...15 {
            for x in 1..<19 where rest[y][x] == "l" {
                if rest[y - 1][x] == "k", rest[y + 1][x] == "k", rest[y][x - 1] == "k", rest[y][x + 1] == "k" { glints += 1 }
            }
        }
        XCTAssertEqual(glints, 2, "two eyes, a glint in each")
        XCTAssertEqual(count("a", rest[16...16]), 4, "rosy cheeks")
        // Boots on the edge row, a pixel high, nothing longer.
        XCTAssertEqual(count("d", rest[18...18]), 4)
        XCTAssertEqual(button.seatRow - 1, 18, "the soles are the edge row")
        XCTAssertTrue(rest[19].allSatisfy { $0 == CompanionInk.clear })
        XCTAssertFalse(button.flourishTurns)
    }

    /// Round 20's pace (brief 100): awake at least six flickers (the blink the heaviest) and four little loops, four long
    /// routines of every day, a flourish and an answer; asleep at least two breaths. The same in both places.
    func testItIsAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }.filter { $0.sky == nil }
            XCTAssertGreaterThanOrEqual(flickers.count, 6, at)
            XCTAssertEqual(flickers.max { $0.weight < $1.weight }?.name, "blink", at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter(\.little).count, 4, at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter { !$0.little && $0.sky == nil }.count, 4, at)
            for routine in awake.routines where routine.little {
                XCTAssertLessThanOrEqual(button.duration(of: routine, mode: awake), 2.5, "\(at) \(routine.name)")
                XCTAssertTrue((2...4).contains(routine.moves), "\(at) \(routine.name)")
            }
            XCTAssertGreaterThanOrEqual(posture.asleep.gestures.count, 2, at)
            XCTAssertTrue(posture.asleep.routines.isEmpty, at)
            XCTAssertGreaterThan(button.flourishDuration(place), 1.8, at)
        }
        XCTAssertEqual(button.plus.awake.routines.map(\.name), button.field.awake.routines.map(\.name))
    }

    /// Brief 109 (George, of 0.9.4's Button: "he has tiny stubs for feet and it makes no sense for his character's
    /// vibe"): no boot ever moves. In every frame it has, awake or asleep, in every weather and the flourish, the boots'
    /// row is the resting one, and no idle or routine is named for a boot or a kick.
    func testItsBootsNeverSwing() {
        let boots = button.rows("rest")![button.seatRow - 1]
        for frame in button.frames {
            XCTAssertEqual(frame.rows[button.seatRow - 1], boots, "\(frame.name): the boots planted")
        }
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            for mode in [posture.awake, posture.asleep] {
                let names = mode.gestures.map(\.name) + mode.routines.map(\.name) + [mode.answer.name]
                for name in names {
                    XCTAssertFalse(name.lowercased().contains("boot") || name.lowercased().contains("kick"), "\(place) \(name)")
                }
            }
        }
    }

    /// Brief 109's idles, a mushroom's, drawn on 0.9.4's body: its cap bobs (the crown squashes a pixel and springs up a
    /// pixel), it puffs (cheeks out, the cap lifted a pixel, then the breath let go), its cap wobbles; and among its
    /// routines the spore puff. Each little loop starts and ends a step from the still.
    func testItHasAMushroomsIdles() {
        for place in CompanionPlace.allCases {
            let awake = button.posture(place).awake
            for name in ["bob", "puffUp", "capWobble"] {
                let loop = awake.routines.first { $0.name == name }
                XCTAssertNotNil(loop, "\(place) \(name)")
                XCTAssertEqual(loop?.little, true, "\(place) \(name)")
                XCTAssertTrue(loop.map { button.plays($0, in: .plain, mode: awake) } ?? false, "\(place) \(name)")
            }
            XCTAssertTrue(awake.routines.contains { $0.name == "sporePuff" && !$0.little }, "\(place)")
        }
        let rest = button.rows("rest")!.map(Array.init)
        let squash = button.rows("squash")!.map(Array.init)
        XCTAssertTrue(squash[1].allSatisfy { $0 == CompanionInk.clear }, "the crown down a pixel")
        XCTAssertEqual(squash[2], rest[1])
        XCTAssertEqual(Array(squash[6...]), Array(rest[6...]), "only the crown moves")
        let puff = button.rows("puff")!.map(Array.init)
        XCTAssertEqual(puff[0], rest[1], "the cap lifted a pixel")
        XCTAssertGreaterThan(puff[15].filter { $0 != CompanionInk.clear }.count, rest[15].filter { $0 != CompanionInk.clear }.count,
                             "cheeks out")
        XCTAssertFalse(puff[16].contains("k"), "the breath held")
        XCTAssertGreaterThan(button.rows("blow")![16].filter { $0 == "k" }.count, rest[16].filter { $0 == "k" }.count, "and let go")
    }

    /// The pixels of a frame not joined to the rest of it (side by side or corner to corner): what it lets go into
    /// the air.
    private func loose(_ frame: String) -> [(x: Int, y: Int)] {
        let rows = button.rows(frame)!.map(Array.init)
        var piece: [Int: Int] = [:]
        var sizes: [Int] = []
        for y in rows.indices {
            for x in rows[y].indices where rows[y][x] != CompanionInk.clear && piece[y * 100 + x] == nil {
                let id = sizes.count
                var queue = [(x, y)]
                piece[y * 100 + x] = id
                var size = 0
                while let (px, py) = queue.popLast() {
                    size += 1
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = px + dx, ny = py + dy
                            guard rows.indices.contains(ny), rows[ny].indices.contains(nx) else { continue }
                            guard rows[ny][nx] != CompanionInk.clear, piece[ny * 100 + nx] == nil else { continue }
                            piece[ny * 100 + nx] = id
                            queue.append((nx, ny))
                        }
                    }
                }
                sizes.append(size)
            }
        }
        guard let body = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return [] }
        var out: [(x: Int, y: Int)] = []
        for (key, id) in piece where id != body { out.append((key % 100, key / 100)) }
        return out.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    /// Its spore puff, Button's own exception to "nothing in the air" (the format's header): a few spores let go from
    /// under its cap that drift up and fade, at most three pixels at a time, pale or fading, each within two pixels of
    /// its cap, gone within a second; never in the rain or snow, and only in its one routine. Elsewhere nothing is
    /// loose but the rain's own drop.
    func testItsSporePuffIsSmallAndBrief() {
        let awake = button.plus.awake
        let puff = awake.routines.first { $0.name == "sporePuff" }!
        let ticks = awake.ticks(of: puff).map(\.tick.frame)
        var run = 0
        var longest = 0
        var seen = 0
        for frame in ticks {
            let spores = loose(frame)
            let changed = button.difference(frame, "rest")
            if spores.isEmpty && !frame.hasPrefix("spore") { run = 0; continue }
            seen += spores.count
            run += 1
            longest = max(longest, run)
            XCTAssertLessThanOrEqual(changed, 3, "\(frame): a few spores, nothing else")
            let rows = button.rows(frame)!.map(Array.init)
            for spore in spores {
                XCTAssertTrue(["l", "m"].contains(rows[spore.y][spore.x]), "\(frame): a pale spore")
                var near = false
                for y in max(0, spore.y - 2)...min(button.height - 1, spore.y + 2) {
                    for x in max(0, spore.x - 2)...min(button.width - 1, spore.x + 2) where rows[y][x] == "a" || rows[y][x] == "r" {
                        near = true
                    }
                }
                XCTAssertTrue(near, "\(frame): spore at \(spore) within two pixels of its cap")
            }
        }
        XCTAssertGreaterThan(seen, 0, "it does let some go")
        XCTAssertLessThan(Double(longest) / button.gestureFPS, 1, "gone within a second")
        for depth in 0...awake.deepest {
            XCTAssertFalse(button.plays(puff, in: .snow, mode: awake, depth: depth), "not in the snow (\(depth))")
        }
        XCTAssertFalse(button.plays(puff, in: .rain, mode: awake))
        var elsewhere: [String] = []
        for gesture in awake.gestures + [awake.answer] where gesture.sky == nil { elsewhere += gesture.ticks.map(\.frame) }
        for routine in awake.routines where routine.name != "sporePuff" && routine.sky == nil {
            elsewhere += awake.ticks(of: routine).map(\.tick.frame)
        }
        elsewhere += button.plus.flourish.map(\.frame)
        for frame in Set(elsewhere) { XCTAssertTrue(loose(frame).isEmpty, "\(frame): nothing in the air") }
    }

    /// Its flourish: it spins its cap like a parasol, the pale spots going round it.
    func testItSpinsItsCap() {
        let frames = button.plus.flourish.map(\.frame)
        let spins = frames.filter { $0.hasPrefix("spin") }
        XCTAssertGreaterThanOrEqual(Set(spins).count, 5)
        func spots(_ frame: String) -> [Int] {
            let rows = button.rows(frame)!.map(Array.init)
            return rows[4...7].map { row in row.firstIndex(of: "l") ?? -1 }
        }
        XCTAssertNotEqual(spots("spin1"), spots("spin2"), "the spots move round")
        XCTAssertNotEqual(spots("spin2"), spots("spin3"))
    }

    /// Asleep it pulls its cap down over its eyes: no dark of an eye shows, only the cap, its cheeks and its mouth.
    func testAsleepUnderItsCap() {
        let sleep = button.rows("sleep")!.map(Array.init)
        XCTAssertTrue(sleep[0...3].joined().allSatisfy { $0 == CompanionInk.clear }, "the cap pulled down")
        XCTAssertTrue(sleep[12...13].joined().contains("r"), "its rim over where its eyes were")
        XCTAssertEqual(button.plus.asleep.rest, "sleep")
        XCTAssertEqual(button.plus.asleep.rain, "sleepRain", "asleep in the rain: its own still (brief 124)")
        XCTAssertEqual(button.plus.asleep.answer.name, "wake")
        XCTAssertTrue(button.rows("sleepPeekLook")!.joined().contains("k"), "woken: one eye peeks out")
    }

    /// Brief 91: in the rain a drop runs off its rim (a flicker that shows) and it peeks out from under it (120); snow
    /// piles up twice over (more snow each time, the seat untouched) until it tips its cap and the heap slides off,
    /// from the heap only; on a hot day it lifts its cap, a bead of sweat runs down, and it fans itself with the cap.
    func testTheWeatherShowsOnIt() {
        for place in CompanionPlace.allCases {
            let awake = button.posture(place).awake
            let at = "\(place)"
            let drip = awake.gesture(named: "drip")!
            XCTAssertEqual(drip.sky, .rain)
            XCTAssertTrue(drip.flicker)
            // Brief 124: the drop and the trickle are only water moving over the wet still.
            for gesture in awake.gestures where gesture.sky == .rain {
                for tick in gesture.ticks {
                    XCTAssertTrue((1...4).contains(button.difference(tick.frame, awake.rain!)), "\(at) \(tick.frame): one drop")
                }
            }
            XCTAssertEqual(awake.routines.first { $0.sky == .rain }?.name, "peek", at)
            // Brief 120: hiding under its cap: the rim pulled down over its eyes, its hands on the rim's ends, its eyes
            // (each with a glint) peeking out from under.
            let rain = button.rows(awake.rain!)!.map(Array.init)
            XCTAssertEqual(String(rain[13]), "rarrrrrrrrrrrrrrrrar", "\(at): the rim across its face")
            XCTAssertEqual(rain[14][1], "l", "\(at): a hand on the rim")
            XCTAssertEqual(rain[14][18], "l", "\(at): and the other")
            XCTAssertTrue(String(rain[14]).contains("klk"), "\(at): its eyes peek out, glints and all")
            var previous = awake.snow!
            let snowInks: Set<Character> = ["s", "b", "c"]
            for deep in awake.snowDeep {
                let more = button.rows(deep)!.joined().filter { snowInks.contains($0) }.count
                let less = button.rows(previous)!.joined().filter { snowInks.contains($0) }.count
                XCTAssertGreaterThan(more, less, "\(at) \(deep)")
                previous = deep
            }
            XCTAssertEqual(awake.snowDeep.count, 2, at)
            let tip = awake.routines.first { $0.shakesOff }!
            XCTAssertEqual(tip.sky, .snow)
            XCTAssertTrue(button.canDraw(tip, in: .snow, mode: awake, depth: awake.deepest), at)
            XCTAssertFalse(button.canDraw(tip, in: .snow, mode: awake, depth: 0), at)
            XCTAssertEqual(awake.heat, "heat")
            XCTAssertTrue(awake.gestures.contains { $0.sky == .heat && $0.flicker }, at)
            XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "fan", at)
            // The lifted cap: its top row is the sprite's first on a hot day, its neck shows under the rim.
            XCTAssertTrue(button.rows("heat")![0].contains("r"))
            XCTAssertFalse(button.rows("rest")![0].contains("r"))
        }
    }

    /// Brief 124 (George: "During rain, they should have little droplets bead off of them every once in a while, and have
    /// some droplets stick around or tiny puddles pool around their feet"): in the rain, awake and asleep, blue beads on
    /// its cap, a drop hanging at the rim's ends, a puddle round its boots on the flat of the "+"; now and then the left
    /// drop lets go and falls past the "+"'s shoulder (its cap is wider than the flat), and more rarely a drop off its
    /// right hand runs down its side into the puddle, whose glint jumps. No drop is left in the light ink, nothing blinks
    /// out, and the blink, the look up and the reply to a tap still play over it.
    func testTheRainIsWaterOnIt() {
        let water: Set<Character> = ["p", "h", "u"]
        let edge = button.seatRow - 1
        func row(_ name: String, _ y: Int) -> [Character] { Array(button.rows(name)![y]) }
        func puddle(_ name: String) -> [Int] { row(name, edge).indices.filter { water.contains(row(name, edge)[$0]) } }
        func lights(_ name: String) -> Int { button.rows(name)!.joined().filter { $0 == "l" }.count }
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            for mode in [posture.awake, posture.asleep] {
                let still = mode.rain!
                let at = "\(place) \(still)"
                let flat = button.rows(still)!.joined()
                for ink in water { XCTAssertTrue(flat.contains(ink), "\(at): all three blues") }
                XCTAssertLessThanOrEqual(lights(still), lights(mode.rest), "\(at): no drop in the light ink")
                let pool = puddle(still)
                XCTAssertTrue((4...8).contains(pool.count), "\(at): a puddle four to eight wide, not a plinth")
                XCTAssertLessThanOrEqual(pool.max()! - pool.min()!, 7, at)
                XCTAssertTrue(pool.allSatisfy { (5...14).contains($0) }, "\(at): on the flat of the \"+\"")
                let beads = button.rows(still)![0..<edge].joined().filter { water.contains($0) }.count
                XCTAssertTrue((3...6).contains(beads), "\(at): beads on the cap, a drop at each end of its rim")
                for gesture in mode.gestures where gesture.sky == .rain {
                    XCTAssertLessThan(Double(gesture.ticks.count) / button.gestureFPS, 1, "\(at) \(gesture.name)")
                    for tick in gesture.ticks { XCTAssertEqual(puddle(tick.frame), pool, "\(at) \(tick.frame): the puddle stays") }
                }
                XCTAssertTrue(button.canDraw(mode.answer, in: .rain, mode: mode, depth: 0), "\(at): the reply to a tap")
            }
            let awake = posture.awake
            for tick in awake.wholeTicks(sky: .rain) {
                XCTAssertFalse(puddle(tick.frame).isEmpty, "\(place) \(tick.frame): the puddle stays")
            }
            for name in ["lookUp@rain", "blink@rain", "half@rain", "wink@rain", "breathe@sleepRain", "snuggle@sleepRain",
                         "sleepPeek@sleepRain", "sleepPeekLook@sleepRain"] {
                XCTAssertFalse(puddle(name).isEmpty, "\(name): the puddle stays")
            }
            XCTAssertTrue(button.canDraw(awake.gesture(named: "blink")!, in: .rain, mode: awake, depth: 0), "\(place): a blink")
            XCTAssertTrue(button.canDraw(awake.gesture(named: "lookUp")!, in: .rain, mode: awake, depth: 0), "\(place)")
            let asleep = posture.asleep
            for name in ["breathe", "murmur", "snuggle"] {
                XCTAssertTrue(button.canDraw(asleep.gesture(named: name)!, in: .rain, mode: asleep, depth: 0), "\(place) \(name)")
            }
        }
        // The trickle lands in the puddle: its glint jumps to where the drop comes down.
        let trickle = button.plus.awake.gesture(named: "trickle")!.ticks.map(\.frame)
        XCTAssertEqual(row(trickle.last!, edge)[14], "h", "it lands in the puddle")
        XCTAssertNotEqual(row(trickle.last!, edge), row("rain", edge), "the glint jumps")
        XCTAssertEqual(row("drip1", 17)[0], "u", "the left drop swells")
    }

    /// Round 22's snow (COMMON; George: "more like powdery, pixelated fallen snow than just white globs … add some blue
    /// hues"): every snow still, awake and asleep, is its body with only the three snow inks added (none of the old
    /// light-ink snow), all three in each, no block of one snow ink past 2 × 3, at most three deep in any column, the
    /// seat untouched; the first a dusting with gaps in it, not one band; the cap's pale spots showing at every depth.
    func testItsSnowIsPowder() {
        let snowInks: Set<Character> = ["s", "b", "c"]
        let posture = button.plus
        let stills: [(String, String)] = [(posture.awake.snow!, "rest")] + posture.awake.snowDeep.map { ($0, "rest") }
            + [(posture.asleep.snow!, "sleep")] + posture.asleep.snowDeep.map { ($0, "sleep") }
        for (name, bodyName) in stills {
            let rows = button.rows(name)!.map(Array.init)
            let body = button.rows(bodyName)!.map(Array.init)
            var used = Set<Character>()
            var depth = [Int](repeating: 0, count: button.width)
            // Brief 120: at the deepest its cheeks go redder (the blush a pixel wider each side), the one change but snow.
            let deepest = name == posture.awake.snowDeep.last || name == posture.asleep.snowDeep.last
            if deepest {
                XCTAssertEqual(rows[16][7], "a", "\(name): its cheeks redder")
                XCTAssertEqual(rows[16][12], "a", "\(name): both")
            }
            for y in rows.indices {
                for x in rows[y].indices where rows[y][x] != body[y][x] {
                    if deepest, y == 16, x == 7 || x == 12 { continue }
                    XCTAssertTrue(snowInks.contains(rows[y][x]), "\(name) row \(y) column \(x): only snow is added")
                    used.insert(rows[y][x])
                    depth[x] += 1
                }
            }
            XCTAssertEqual(used, snowInks, "\(name): three tones")
            XCTAssertLessThanOrEqual(depth.max() ?? 0, 3, "\(name): at most three deep")
            XCTAssertEqual(rows[button.seatRow - 1], body[button.seatRow - 1], "\(name): the seat untouched")
            // The cap's pale spots (light ink on rows 3 to 7 of the awake cap) all still show.
            let spotRows = bodyName == "rest" ? 3...7 : 6...10
            for y in spotRows {
                for x in body[y].indices where body[y][x] == "l" { XCTAssertEqual(rows[y][x], "l", "\(name): the spot at \(x), \(y)") }
            }
            for ink in snowInks {
                for y in rows.indices {
                    for x in rows[y].indices {
                        var run = 0
                        while x + run < rows[y].count, rows[y][x + run] == ink { run += 1 }
                        XCTAssertLessThanOrEqual(run, 3, "\(name) row \(y): a run of \(ink)")
                        var tall = 0
                        while y + tall < rows.count, rows[y + tall][x] == ink { tall += 1 }
                        XCTAssertLessThanOrEqual(tall, 3, "\(name) column \(x): a column of \(ink)")
                        if x + 2 < rows[y].count, y + 2 < rows.count {
                            let block = (0...2).allSatisfy { dy in (0...2).allSatisfy { dx in rows[y + dy][x + dx] == ink } }
                            XCTAssertFalse(block, "\(name): a 3 x 3 block of \(ink) at \(x), \(y)")
                        }
                    }
                }
            }
        }
        // The dusting: on the crown's own row the snow has gaps, the cap's rim showing between.
        let dust = button.rows(posture.awake.snow!)!.map(Array.init)
        let crown = dust[1].filter { $0 != CompanionInk.clear }
        XCTAssertTrue(crown.contains("r") && crown.contains { snowInks.contains($0) }, "a dusting with gaps")
        XCTAssertTrue(dust[0].allSatisfy { $0 == CompanionInk.clear }, "a dusting adds no height")
        // Nothing of the old light-ink snow in any frame of the snow's routine or the snow's breath.
        for name in ["tip1", "tip2", "tip3", "tipGone", "breathe@sleepSnow", "breathe@sleepSnow2", "sleepPeek@sleepSnow"] {
            let rows = button.rows(name)!
            XCTAssertTrue(rows[0...10].joined().contains { snowInks.contains($0) }, "\(name): its snow is the new snow")
        }
    }

    /// Brief 100: an idle can be drawn over every still it may show (each depth of snow, the heat, asleep in the snow),
    /// so it is never still for long whatever the sky.
    func testAnIdleDrawsOverEveryStill() {
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            for (label, mode) in [("awake", posture.awake), ("asleep", posture.asleep)] {
                var looks: [(CompanionLook.Weather, Int)] = [(.plain, 0), (.rain, 0), (.snow, 0), (.heat, 0)]
                for depth in 0..<mode.snowDeep.count { looks.append((.snow, depth + 1)) }
                for (weather, depth) in looks {
                    let candidates = label == "asleep" ? mode.gestures : mode.flickers.map { mode.gestures[$0] }
                    let drawable = candidates.filter { gesture in
                        guard let sky = gesture.sky else {
                            return button.canDraw(gesture, in: weather, mode: mode, depth: depth)
                        }
                        return CompanionLook.Weather(sky) == weather && button.canDraw(gesture, in: weather, mode: mode, depth: depth)
                    }
                    XCTAssertFalse(drawable.isEmpty, "\(place) \(label) \(weather) \(depth): an idle that draws")
                }
            }
        }
    }

    /// Its seat (briefs 100 and 109): it stands on top of its host. On the "+" (SwiftUI's continuous capsule, the lower
    /// of it and the circular one at each point) every column of every still on the edge row (its soles) has the "+"
    /// right under it, to under half a device pixel at 3x, and nothing of it is below that row in any frame it has:
    /// no boot over the "+"'s face. Centred on the "+". On the Mac's field (flat) the same.
    func testItStandsOnThePlus() {
        let size = FloatingAddButton.size
        let rect = CGRect(origin: .zero, size: size)
        let shapes = [Capsule(style: .continuous).path(in: rect), Capsule(style: .circular).path(in: rect)]
        func top(_ x: CGFloat) -> CGFloat {
            var y: CGFloat = 0
            while y < size.height / 2, !shapes.allSatisfy({ $0.contains(CGPoint(x: x, y: y)) }) { y += 0.01 }
            return y
        }
        let p = CompanionCharacter.pointsPerPixel
        let offset = CompanionPerch.offset(button, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(button.width) * p
        let left: CGFloat = size.width - spriteWidth + offset.width
        let posture = button.plus
        var stills: [String] = []
        for mode in [posture.awake, posture.asleep] { stills.append(contentsOf: mode.stills) }
        let edge = button.seatRow - 1
        for name in stills {
            let rows = button.rows(name)!.map(Array.init)
            XCTAssertTrue(rows[edge].contains("d"), "\(name): its boots on the edge")
            for c in 0..<button.width where rows[edge][c] != CompanionInk.clear {
                let x0: CGFloat = left + CGFloat(c) * p
                let x1: CGFloat = x0 + p
                let gap = max(top(x0 + 0.01), top(x1 - 0.01))
                XCTAssertLessThan(gap, 0.17, "\(name) column \(c): \(gap) pt of background under it")
            }
        }
        for frame in button.frames {
            let below = frame.rows[button.seatRow...].joined()
            XCTAssertTrue(below.allSatisfy { $0 == CompanionInk.clear }, "\(frame.name): nothing over the host's face")
        }
        // Centred on the "+": its soles' middle within a point of the button's.
        let seat = button.rows("rest")![edge].map { $0 }
        let first = seat.firstIndex { $0 != CompanionInk.clear }!
        let last = seat.lastIndex { $0 != CompanionInk.clear }!
        let first0: CGFloat = CGFloat(first)
        let last1: CGFloat = CGFloat(last + 1)
        let middle: CGFloat = left + (first0 + last1) * p / 2
        XCTAssertEqual(middle, size.width / 2, accuracy: 1)
    }

    /// The UI tests tap the companion just above the "+" (24 pt in from its right edge, 14 pt up) and the "+" just under
    /// its soles (22 pt in, 3 pt down): the first is the companion's, the second the "+"'s.
    func testTheUITestsTapsLandOnItAndOnThePlus() {
        let size = FloatingAddButton.size
        let rest = button.index[button.plus.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: button.drawn[rest], width: button.width, mirrored: false,
                                                belowRow: button.seatRow)
        let offset = CompanionPerch.offset(button, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(button.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let top: CGFloat = offset.height
        XCTAssertTrue(shape.contains(CGPoint(x: size.width - 24 - left, y: -14 - top)), "a tap on it is its own")
        XCTAssertFalse(shape.contains(CGPoint(x: size.width - 22 - left, y: 3 - top)), "a tap under its boots is the +'s")
    }

    /// The accent's shade reads on every theme: apart from the window, and a step from the accent it shades.
    func testItsShadeReadsOnEveryTheme() {
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            let shade = inks.hex[.accentDark]!
            XCTAssertEqual(shade, CompanionInks.mix(palette.hex.accent, palette.hex.background, CompanionInks.accentDarkMix))
            XCTAssertGreaterThan(Self.contrast(shade, palette.hex.background), 2, palette.id)
            XCTAssertGreaterThan(Self.contrast(inks.hex[.accent]!, shade), 1.8, palette.id)
        }
    }

    private static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let c = CompanionInks.rgb(hex).map { v -> Double in
                let s = Double(v) / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            let r: Double = 0.2126 * c[0]
            let g: Double = 0.7152 * c[1]
            let bl: Double = 0.0722 * c[2]
            return r + g + bl
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
