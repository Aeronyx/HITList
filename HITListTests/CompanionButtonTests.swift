import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Briefs 102 and 103: Button, Rosé's companion. Redrawn in round 21 (George: "a bit large and looks kind of creepy",
/// and a mushroom with stubs for feet "certainly shouldn't be swinging his feet"): the smallest of the eight, a face in
/// the warm of its own stem, standing on two stubs on top of its host with nothing hanging over, and idles only a
/// mushroom would do (a roll and a spore puff among them). Every frame is also checked by `CompanionSpriteTests` (good
/// data, small gestures, crisp pixels, all eight palettes), `CompanionSeatTests` (it stands on every host in every
/// still) and `CompanionDirectorTests.testNeverADeadMinute`.
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

    /// The box a frame's pixels fill: its width, its height, how many pixels.
    private static func extent(_ rows: [String]) -> (width: Int, height: Int, pixels: Int) {
        var xs: [Int] = []
        var ys: [Int] = []
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c != CompanionInk.clear {
                xs.append(x)
                ys.append(y)
            }
        }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return (0, 0, 0) }
        return (x1 - x0 + 1, y1 - y0 + 1, xs.count)
    }

    /// Brief 103, "small": awake, cap and all, at most 14 pixels wide and 13 tall, and the smallest of the cast (no
    /// other companion's resting pose is as narrow, as short or as few pixels).
    func testItIsTheSmallestOfTheCast() {
        for place in CompanionPlace.allCases {
            let rest = button.rows(button.posture(place).awake.rest)!
            let size = Self.extent(rest)
            XCTAssertLessThanOrEqual(size.width, 14, "\(place)")
            XCTAssertLessThanOrEqual(size.height, 13, "\(place)")
            for other in CompanionCharacter.all where other.id != button.id {
                let theirs = Self.extent(other.rows(other.posture(place).awake.rest)!)
                XCTAssertLessThan(size.pixels, theirs.pixels, "\(other.id) \(place)")
                XCTAssertLessThanOrEqual(size.width, theirs.width, "\(other.id) \(place)")
                XCTAssertLessThanOrEqual(size.height, theirs.height, "\(other.id) \(place)")
            }
        }
        // The rain's still is a pixel taller, never more than 13.
        XCTAssertEqual(Self.extent(button.rows("rain")!).height, Self.extent(button.rows("rest")!).height + 1)
        XCTAssertLessThanOrEqual(Self.extent(button.rows("rain")!).height, 13)
    }

    /// Brief 103, "a face nobody could call a skull": nothing bone white on it, no holes. The stem and its face are the
    /// cap's own warm rose; two small dark eyes, set wide and low, each a 2 x 2 with a glint at its top left; no other
    /// dark on the face; a soft mouth in the cap's shade, under the eyes and between them. The cap is rose with pale
    /// spots.
    func testItsFaceIsSweetNotASkull() {
        XCTAssertEqual(button.inks, [.ink, .dark, .light, .accent, .accentDark], "no mid grey, no bone")
        let rest = button.rows("rest")!.map(Array.init)
        // The stem: rows 14 to 18, columns 7 to 14. Rose with the face on it; its only pale pixels are the two glints.
        var dark: [(Int, Int)] = []
        var light: [(Int, Int)] = []
        var rose = 0
        for y in 14...18 {
            for x in 7...14 {
                switch rest[y][x] {
                case "k": dark.append((x, y))
                case "l": light.append((x, y))
                case "a": rose += 1
                default: break
                }
            }
        }
        XCTAssertGreaterThan(rose, 24, "a rose stem")
        XCTAssertEqual(dark.count, 6, "two eyes, three dark pixels each")
        XCTAssertEqual(light.count, 2, "a glint in each eye, nothing pale besides")
        for (x, y) in light {
            // The glint is the eye's top-left pixel: dark to its right, below it and diagonally.
            XCTAssertEqual(rest[y][x + 1], "k")
            XCTAssertEqual(rest[y + 1][x], "k")
            XCTAssertEqual(rest[y + 1][x + 1], "k")
        }
        // Set wide (two pixels apart, a pixel in from the stem's edges) and low (under the stem's top row).
        XCTAssertEqual(light.map(\.0).sorted(), [8, 12])
        XCTAssertEqual(Set(light.map(\.1)), [15])
        // The mouth: two pixels of the cap's shade, centred under the eyes, a row below them.
        XCTAssertEqual(rest[17][10], "r")
        XCTAssertEqual(rest[17][11], "r")
        // The cap: rose with at least three pale spots, its rim and underside in the shade.
        let cap = rest[8...13].joined()
        XCTAssertGreaterThan(cap.filter { $0 == "a" }.count, 40)
        XCTAssertGreaterThanOrEqual(cap.filter { $0 == "l" }.count, 4)
        XCTAssertFalse(cap.contains("k"))
        // Wider than the stem by three a side: a mushroom at a glance.
        XCTAssertEqual(rest[11].filter { $0 != CompanionInk.clear }.count, 14)
        XCTAssertEqual(rest[15].filter { $0 != CompanionInk.clear }.count, 8)
    }

    /// Brief 103, "standing": both stub feet on the host's top edge, nothing of it below that, in every frame it has.
    /// Two stubs of two pixels, no boots.
    func testItStandsOnItsStubs() {
        XCTAssertEqual(button.seatRow, button.height, "nothing hangs over the edge")
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            for mode in [posture.awake, posture.asleep] {
                for still in mode.stills {
                    let edge = Array(button.rows(still)![button.seatRow - 1])
                    let feet = edge.indices.filter { edge[$0] != CompanionInk.clear }
                    XCTAssertEqual(feet, [8, 9, 12, 13], "\(still): two stubs on the edge")
                    XCTAssertTrue(feet.allSatisfy { edge[$0] == "d" }, still)
                }
            }
        }
        // No kicks, swings or boots anywhere.
        let names = button.plus.awake.gestures.map(\.name) + button.plus.awake.routines.map(\.name)
            + button.plus.asleep.gestures.map(\.name) + button.frames.map(\.name)
        for word in ["kick", "swing", "boot"] {
            XCTAssertFalse(names.contains { $0.lowercased().contains(word) }, word)
        }
    }

    /// Round 20's pace (brief 100) and brief 103's list: awake at least six flickers (the blink the heaviest) and four
    /// little loops, four long routines of every day (the roll and the spore puff among them), a flourish and an answer;
    /// asleep at least two breaths. The same in both places.
    func testItIsAliveAtTheNewPace() {
        for place in CompanionPlace.allCases {
            let posture = button.posture(place)
            let awake = posture.awake
            let at = "\(place)"
            let flickers = awake.flickers.map { awake.gestures[$0] }.filter { $0.sky == nil }
            XCTAssertGreaterThanOrEqual(flickers.count, 6, at)
            XCTAssertEqual(flickers.max { $0.weight < $1.weight }?.name, "blink", at)
            XCTAssertGreaterThanOrEqual(awake.routines.filter(\.little).count, 4, at)
            let everyday = awake.routines.filter { !$0.little && $0.sky == nil }
            XCTAssertGreaterThanOrEqual(everyday.count, 4, at)
            XCTAssertTrue(everyday.contains { $0.name == "roll" }, at)
            XCTAssertTrue(everyday.contains { $0.name == "sporePuff" }, at)
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

    /// George's roll: it ducks under its cap, tucks into a ball, rolls along the bar (toward the middle of the "+",
    /// where it is flat) and back, pops upright and is dizzy for a beat. The ball stays on the bar and inside its box.
    func testItRollsAlongTheBarAndBack() {
        let awake = button.plus.awake
        let roll = awake.routines.first { $0.name == "roll" }!
        let frames = awake.ticks(of: roll).map(\.tick.frame)
        let balls = frames.filter { $0.hasPrefix("roll") }
        XCTAssertGreaterThanOrEqual(Set(balls).count, 4, "it turns as it rolls")
        func left(_ frame: String) -> Int {
            let rows = button.rows(frame)!.map(Array.init)
            var best = button.width
            for row in rows { if let x = row.firstIndex(where: { $0 != CompanionInk.clear }) { best = min(best, x) } }
            return best
        }
        let xs = balls.map(left)
        let far = xs.min()!
        XCTAssertLessThanOrEqual(far, xs.first! - 3, "a few pixels along the bar")
        XCTAssertEqual(xs.last, xs.first, "and back")
        let turn = xs.firstIndex(of: far)!
        XCTAssertEqual(xs[...turn].map { $0 }, xs[...turn].sorted(by: >), "out")
        XCTAssertEqual(xs[turn...].map { $0 }, xs[turn...].sorted(), "and back")
        for frame in Set(balls) {
            let rows = button.rows(frame)!
            XCTAssertTrue(rows[button.seatRow - 1].contains("a") || rows[button.seatRow - 1].contains("r"), "\(frame) on the bar")
        }
        // Ducked under its cap first; dizzy after.
        XCTAssertLessThan(frames.firstIndex(of: "duck2")!, frames.firstIndex(of: "roll0")!)
        XCTAssertGreaterThan(frames.firstIndex(of: "dizzy1")!, frames.lastIndex(of: "roll0")!)
        XCTAssertEqual(frames.last, awake.rest)
    }

    /// The pixels of a frame that are not joined to the rest of it (side by side or corner to corner): what it lets
    /// go into the air. The mushroom is its largest piece (on the bar or, mid-hop, above it).
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

    /// George's puff, Button's own exception to "nothing in the air" (brief 103): at most three spores, pale, each within
    /// two pixels of its cap, gone within a second; never in the rain or snow (it can't be drawn over them), and only in
    /// its one routine, never in an idle.
    func testItsSporePuffIsSmallAndBrief() {
        let awake = button.plus.awake
        let puff = awake.routines.first { $0.name == "sporePuff" }!
        let ticks = awake.ticks(of: puff).map(\.tick.frame)
        var run = 0
        var longest = 0
        var seen = 0
        for frame in ticks {
            let spores = loose(frame)
            if spores.isEmpty { run = 0; continue }
            seen += 1
            run += 1
            longest = max(longest, run)
            XCTAssertLessThanOrEqual(spores.count, 3, frame)
            let rows = button.rows(frame)!.map(Array.init)
            for spore in spores {
                XCTAssertEqual(rows[spore.y][spore.x], "l", "\(frame): a pale spore")
                // Within two pixels of the cap (above the stem, which starts on row 14 at most).
                var near = false
                for y in max(0, spore.y - 2)...min(13, spore.y + 2) {
                    for x in max(0, spore.x - 2)...min(button.width - 1, spore.x + 2) where !(x == spore.x && y == spore.y) {
                        if rows[y][x] == "a" || rows[y][x] == "r" { near = true }
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
        // Nothing loose in any idle, the answer, the flourish, or any other routine.
        var elsewhere: [String] = []
        for gesture in awake.gestures + [awake.answer] { elsewhere += gesture.ticks.map(\.frame) }
        for routine in awake.routines where routine.name != "sporePuff" { elsewhere += awake.ticks(of: routine).map(\.tick.frame) }
        elsewhere += button.plus.flourish.map(\.frame)
        for frame in Set(elsewhere) {
            XCTAssertTrue(loose(frame).isEmpty, "\(frame): nothing in the air")
        }
    }

    /// Its flourish: it spins its cap like a top, eyes shut with joy, the pale spots going round it, the cap rising as
    /// it goes; it ends where it began.
    func testItSpinsItsCapLikeATop() {
        let frames = button.plus.flourish.map(\.frame)
        var spins: [String] = []
        for frame in frames where frame.hasPrefix("spin") && spins.last != frame { spins.append(frame) }
        XCTAssertGreaterThanOrEqual(Set(spins).count, 5)
        func spots(_ frame: String) -> [[Int]] {
            let rows = button.rows(frame)!.map(Array.init)
            return rows[7...11].map { row in row.indices.filter { row[$0] == "l" } }
        }
        var previous = spots("rest")
        for frame in spins {
            let now = spots(frame)
            XCTAssertNotEqual(now, previous, "\(frame): the spots move round")
            previous = now
            XCTAssertFalse(button.rows(frame)!.joined().contains("k") && button.rows(frame)![15].contains("l"), "\(frame): eyes shut")
        }
        XCTAssertTrue(frames.contains { $0.hasPrefix("spinUp") }, "the cap rises as it spins")
        XCTAssertEqual(button.plus.flourish.first?.frame, "rest")
        XCTAssertEqual(button.plus.flourish.last?.frame, "rest")
        XCTAssertFalse(button.flourishTurns)
    }

    /// Asleep it pulls its cap down over its eyes: no dark of an eye shows, only the cap, its mouth and its stubs. Woken,
    /// one eye peeks out from under the rim.
    func testAsleepUnderItsCap() {
        let sleep = button.rows("sleep")!.map(Array.init)
        let rest = button.rows("rest")!.map(Array.init)
        XCTAssertFalse(sleep.joined().contains("k"), "no eye shows")
        let top = sleep.firstIndex { $0.contains { $0 != CompanionInk.clear } }!
        let awakeTop = rest.firstIndex { $0.contains { $0 != CompanionInk.clear } }!
        XCTAssertEqual(top, awakeTop + 3, "the cap pulled three rows down")
        XCTAssertEqual(sleep[17][10], "r", "its mouth under the rim")
        XCTAssertEqual(button.plus.asleep.rest, "sleep")
        XCTAssertNil(button.plus.asleep.rain, "asleep wins over the rain")
        XCTAssertEqual(button.plus.asleep.answer.name, "wake")
        XCTAssertEqual(button.rows("sleepPeek")!.joined().filter { $0 == "l" }.count - sleep.joined().filter { $0 == "l" }.count, 1,
                       "woken: one eye, its glint")
        // A breath lifts the cap off two shut eyes.
        XCTAssertTrue(button.rows("breathe")![16].contains("k"))
    }

    /// Brief 103's weather: in the rain it stands a pixel taller and happier (a smile), a drop on its cap's rim (a flicker
    /// that drips it) and a routine of being glad of it; snow dusts and piles twice over (more snow each time, the seat
    /// untouched) until it tips its cap and the heap slides off, from the heap only; on a hot day it wilts (shorter, its
    /// rim hanging), a bead of sweat runs down, and it wilts further, rallies and wilts again.
    func testTheWeatherShowsOnIt() {
        for place in CompanionPlace.allCases {
            let awake = button.posture(place).awake
            let at = "\(place)"
            let rest = button.rows("rest")!.map(Array.init)
            let rain = button.rows(awake.rain!)!.map(Array.init)
            // Taller by a pixel, smiling, a drop under the rim's left end.
            XCTAssertEqual(rain[7].filter { $0 != CompanionInk.clear }.count, rest[8].filter { $0 != CompanionInk.clear }.count)
            XCTAssertEqual(rain[17][9], "r")
            XCTAssertEqual(rain[17][12], "r")
            XCTAssertEqual(rain[12][4], "l", "\(at): a drop on the rim")
            XCTAssertEqual(rain[11][4], "r")
            let drip = awake.gesture(named: "drip")!
            XCTAssertEqual(drip.sky, .rain)
            XCTAssertTrue(drip.flicker)
            for tick in drip.ticks { XCTAssertEqual(button.difference(tick.frame, awake.rain!), 1, "\(at): one drop") }
            XCTAssertEqual(awake.routines.first { $0.sky == .rain }?.name, "glad", at)
            var previous = awake.snow!
            for deep in awake.snowDeep {
                let more = button.rows(deep)!.joined().filter { $0 == "l" }.count
                let less = button.rows(previous)!.joined().filter { $0 == "l" }.count
                XCTAssertGreaterThan(more, less, "\(at) \(deep)")
                previous = deep
            }
            XCTAssertEqual(awake.snowDeep.count, 2, at)
            let tip = awake.routines.first { $0.shakesOff }!
            XCTAssertEqual(tip.sky, .snow)
            XCTAssertTrue(button.canDraw(tip, in: .snow, mode: awake, depth: awake.deepest), at)
            XCTAssertFalse(button.canDraw(tip, in: .snow, mode: awake, depth: 0), at)
            XCTAssertEqual(awake.heat, "heat")
            let heat = button.rows("heat")!
            XCTAssertLessThan(Self.extent(heat).height, Self.extent(button.rows("rest")!).height, "\(at): wilted")
            XCTAssertTrue(awake.gestures.contains { $0.sky == .heat && $0.flicker }, at)
            XCTAssertEqual(awake.routines.first { $0.sky == .heat }?.name, "wilt", at)
        }
    }

    /// Brief 100: an idle can be drawn over every still it may show (each depth of snow, the heat, asleep in the snow),
    /// and brief 103 draws its idles for each, so it has several to choose from whatever the sky.
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
                    let most = label == "asleep" ? 2 : 5
                    XCTAssertGreaterThanOrEqual(drawable.count, most, "\(place) \(label) \(weather) \(depth): idles that draw")
                    if label == "awake" {
                        let loops = mode.routines.filter(\.little).filter { button.plays($0, in: weather, mode: mode, depth: depth) }
                        XCTAssertGreaterThanOrEqual(loops.count, 3, "\(place) \(weather) \(depth): little loops that draw")
                    }
                }
            }
            // The tap's answer plays in every sky, the snow at every depth included.
            for (label, mode) in [("awake", posture.awake), ("asleep", posture.asleep)] {
                for weather in CompanionLook.Weather.allCases {
                    for depth in 0...(weather == .snow ? mode.deepest : 0) {
                        XCTAssertTrue(button.canDraw(mode.answer, in: weather, mode: mode, depth: depth),
                                      "\(place) \(label) answer in \(weather) \(depth)")
                    }
                }
            }
        }
    }

    /// Its seat (brief 100): on the "+" (SwiftUI's continuous capsule, the lower of it and the circular one at each
    /// point) both stubs of every still have the "+" right under them, to under half a device pixel at 3x, centred on
    /// the button's flat. On the Mac's field (flat) the same.
    func testItStandsOnTheFlatOfThePlus() {
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
            for c in 0..<button.width where rows[edge][c] != CompanionInk.clear {
                let x0: CGFloat = left + CGFloat(c) * p
                let x1: CGFloat = x0 + p
                let gap = max(top(x0 + 0.01), top(x1 - 0.01))
                XCTAssertLessThan(gap, 0.17, "\(name) column \(c): \(gap) pt of background under it")
            }
        }
        // Centred on the "+": its stubs' middle within a point of the button's.
        let seat = button.rows("rest")![edge].map { $0 }
        let first = seat.firstIndex { $0 != CompanionInk.clear }!
        let last = seat.lastIndex { $0 != CompanionInk.clear }!
        let first0: CGFloat = CGFloat(first)
        let last1: CGFloat = CGFloat(last + 1)
        let middle: CGFloat = left + (first0 + last1) * p / 2
        XCTAssertEqual(middle, size.width / 2, accuracy: 1)
        // The roll goes toward the middle, where the "+" is flat: the ball's furthest is still on the flat.
        guard let roll = posture.awake.routines.first(where: { $0.name == "roll" }) else { return }
        for frame in Set(posture.awake.ticks(of: roll).map(\.tick.frame)) where frame.hasPrefix("roll") {
            let rows = button.rows(frame)!.map(Array.init)
            for c in 0..<button.width where rows[edge][c] != CompanionInk.clear {
                let x0: CGFloat = left + CGFloat(c) * p
                XCTAssertLessThan(top(x0 + 1), 0.17, "\(frame) column \(c) rolls on the flat")
            }
        }
    }

    /// The UI tests tap the companion just above the "+" (24 pt in from its right edge, 14 pt up) and the "+" just under
    /// its feet (22 pt in, 3 pt down): the first is the companion's, the second the "+"'s.
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
        XCTAssertFalse(shape.contains(CGPoint(x: size.width - 22 - left, y: 3 - top)), "a tap under its feet is the +'s")
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
