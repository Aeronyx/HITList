import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 102: Gargle, Graphite's companion in place of Smudge. A gargoyle pup crouched on the "+" as its elders crouch
/// on a parapet: a round head half its height, two big eyes with a glint, two horn nubs, small wing tips over its
/// shoulders, two paws gripping the edge and its tail over the front; asleep it turns to stone. Alive at round 20's
/// pace (brief 100), the weather on it (brief 91). Every frame is also checked by `CompanionSpriteTests` and by
/// `CompanionDirectorTests.testNeverADeadMinute`.
@MainActor
final class CompanionGargleTests: XCTestCase {
    private let gargle = CompanionCharacter.gargle

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

    /// One clean shape at real size: the head is most of it, two eyes with a glint each, two pale horn tips, a wing tip
    /// on each side, one warm pixel (its tongue), two paws and a tail over the edge, and nothing busier.
    func testItIsAGargoylePup() {
        XCTAssertEqual(gargle.inks, [.ink, .dark, .mid, .light, .warm])
        XCTAssertEqual(gargle.seatRow, 17)
        let rest = gargle.rows("rest")!.map(Array.init)
        func count(_ ink: Character, _ rows: ArraySlice<[Character]>) -> Int { rows.joined().filter { $0 == ink }.count }
        // The head: rows 2 to 12, 16 wide at its widest; the body under it no wider than 14.
        XCTAssertEqual(rest[7][2...17].filter { $0 != CompanionInk.clear }.count, 16)
        XCTAssertLessThanOrEqual(rest[15].filter { $0 != CompanionInk.clear }.count, 12)
        var glints = 0
        for y in 6...9 {
            for x in 1..<19 where rest[y][x] == "l" {
                if rest[y - 1][x] == "k", rest[y + 1][x] == "k", rest[y][x - 1] == "k", rest[y][x + 1] == "k" { glints += 1 }
            }
        }
        XCTAssertEqual(glints, 2, "two big eyes, a glint in each")
        XCTAssertEqual(count("l", rest[0...0]), 2, "two pale horn tips")
        XCTAssertEqual(count("l", rest[1...]), 2, "and only the glints besides")
        XCTAssertEqual(count("w", rest[0...]), 1, "a tongue tip")
        for y in 10...12 {
            XCTAssertNotEqual(rest[y][0], CompanionInk.clear, "a wing tip on the left")
            XCTAssertNotEqual(rest[y][19], CompanionInk.clear, "and on the right")
        }
        XCTAssertEqual(String(rest[17][6...7]), "mm", "a paw over the edge")
        XCTAssertEqual(String(rest[17][12...13]), "mm", "and the other")
        XCTAssertTrue(rest[18...19].joined().contains("d"), "its tail over the front")
        XCTAssertFalse(gargle.flourishTurns)
    }

    /// Round 20's pace (brief 100): awake at least six flickers (the blink the heaviest) and four little loops, four long
    /// routines of every day, a flourish and an answer; asleep at least two breaths. The same in both places.
    func testItIsAliveAtTheNewPace() {
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
        }
        XCTAssertEqual(gargle.plus.awake.routines.map(\.name), gargle.field.awake.routines.map(\.name))
    }

    /// Its flourish: the grotesque's face (wings high, fangs, a glare), spoiled by a giggle.
    func testItPullsAGrotesquesFace() {
        let frames = gargle.plus.flourish.map(\.frame)
        XCTAssertTrue(frames.contains("boo") && frames.contains("giggle"))
        let boo = gargle.rows("boo")!.map(Array.init)
        XCTAssertEqual(boo[11].filter { $0 == "l" }.count, 2, "two fangs")
        XCTAssertNotEqual(boo[7][0], CompanionInk.clear, "its wings high")
        XCTAssertEqual(gargle.flourishDuration(.plus), gargle.flourishDuration(.field))
    }

    /// Asleep it has turned to stone: the same greys, no glint, no tongue, its eyes two cracks; woken, one eye opens.
    func testAsleepItTurnsToStone() {
        let sleep = gargle.rows("sleep")!.joined()
        XCTAssertFalse(sleep.contains("k"), "no dark of an eye: two cracks")
        XCTAssertFalse(sleep.contains("w"), "no tongue")
        XCTAssertEqual(sleep.filter { $0 == "l" }.count, 2, "only its horn tips pale")
        XCTAssertEqual(gargle.plus.asleep.rest, "sleep")
        XCTAssertNil(gargle.plus.asleep.rain, "asleep wins over the rain")
        XCTAssertTrue(gargle.rows("sleepPeekLook")!.joined().contains("k"), "woken: one eye opens")
    }

    /// Brief 91: in the rain its mouth hangs open like a spout and a drop falls from its chin (a flicker that shows), and
    /// it shakes its head dry; snow piles up twice over (more each time, the seat untouched) until it shakes the heap
    /// off, from the heap only; on a hot day its wings droop and it pants, and it lies flat on the cool stone.
    func testTheWeatherShowsOnIt() {
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
                let more = gargle.rows(deep)!.joined().filter { $0 == "l" }.count
                let less = gargle.rows(previous)!.joined().filter { $0 == "l" }.count
                XCTAssertGreaterThan(more, less, "\(at) \(deep)")
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
        XCTAssertGreaterThan(gargle.rows("heat")!.joined().filter { $0 == "w" }.count, 1, "its tongue out on a hot day")
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
        }
    }

    /// Its seat (brief 100): on the "+" (SwiftUI's continuous capsule, the lower of it and the circular one at each
    /// point) every column of every still that rests on the edge line has the "+" right under it, to under half a device
    /// pixel at 3x, and it sits on the middle of the "+"; its paws hang over the front.
    func testItSitsOnThePlus() {
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
            let rows = gargle.rows(name)!.map(Array.init)
            for c in 0..<gargle.width where rows[edge][c] != CompanionInk.clear {
                let x0: CGFloat = left + CGFloat(c) * p
                let x1: CGFloat = x0 + p
                let gap = max(top(x0 + 0.01), top(x1 - 0.01))
                XCTAssertLessThan(gap, 0.17, "\(name) column \(c): \(gap) pt of background under it")
            }
            XCTAssertEqual(String(rows[gargle.seatRow][6...7]), "mm", "\(name): its paws over the edge")
        }
        let seat = gargle.rows("rest")![edge].map { $0 }
        let first = seat.firstIndex { $0 != CompanionInk.clear }!
        let last = seat.lastIndex { $0 != CompanionInk.clear }!
        let first0: CGFloat = CGFloat(first)
        let last1: CGFloat = CGFloat(last + 1)
        let middle: CGFloat = left + (first0 + last1) * p / 2
        XCTAssertEqual(middle, size.width / 2, accuracy: 1)
    }

    /// The UI tests tap the companion just above the "+" (24 pt in from its right edge, 14 pt up) and the "+" just under
    /// its paws (22 pt in, 3 pt down): the first is the companion's, the second the "+"'s.
    func testTheUITestsTapsLandOnItAndOnThePlus() {
        let size = FloatingAddButton.size
        let rest = gargle.index[gargle.plus.awake.rest]!
        let shape = CompanionCharacter.tapShape(runs: gargle.drawn[rest], width: gargle.width, mirrored: false,
                                                belowRow: gargle.seatRow)
        let offset = CompanionPerch.offset(gargle, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(gargle.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = size.width - spriteWidth + offset.width
        let top: CGFloat = offset.height
        XCTAssertTrue(shape.contains(CGPoint(x: size.width - 24 - left, y: -14 - top)), "a tap on it is its own")
        XCTAssertFalse(shape.contains(CGPoint(x: size.width - 22 - left, y: 3 - top)), "a tap under its paws is the +'s")
    }
}
