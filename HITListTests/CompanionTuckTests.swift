import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 88: Tuck, Moss's companion. A white snail whose shell is a clay flowerpot with a seedling growing in it (its
/// leaves the theme's accent): mostly still, a blink or an eye stalk tipping out now and then, four routines of its own,
/// the weather's own, a seedling that flowers as its flourish, and a foot that rests on what it sits on in both places.
/// Brief 91: the weather shows on it: rain drips off its pot's rim and it shakes itself dry, snow piles up on its pot
/// until it shrugs it off, and on a hot day it wilts with its seedling and finds the shade of its own pot.
@MainActor
final class CompanionTuckTests: XCTestCase {
    private let tuck = CompanionCharacter.tuck

    func testTuckIsMossCompanionAndGoodData() {
        XCTAssertEqual(tuck.problems, [])
        XCTAssertEqual(CompanionCharacter.named("tuck")?.id, "tuck")
        XCTAssertEqual(CompanionCast.character(forTheme: "moss", launch: .none).id, "tuck")
        XCTAssertEqual(tuck.name, "Tuck")
        XCTAssertEqual(tuck.width, 20)
        XCTAssertEqual(tuck.height, 20)
        XCTAssertEqual(tuck.seatRow, 20, "nothing hangs: its foot rests on the edge")
        XCTAssertEqual(tuck.inks, [.ink, .dark, .mid, .light, .accent])
        XCTAssertEqual(tuck.gestureFPS, 8)
        XCTAssertEqual(tuck.flourishFPS, 9)
        XCTAssertFalse(tuck.flourishTurns)
    }

    /// Its one accent detail is the seedling, and the seedling stands in its pot: no accent at or below the pot's rim, so
    /// it never meets the "+" (which is the accent too).
    func testItsSeedlingIsItsOneAccentAndStandsInThePot() {
        let rim = try? XCTUnwrap(tuck.rows("rest")?.firstIndex { $0.contains("dddddddddd") })
        guard let rim else { return }
        for frame in tuck.frames {
            for (y, row) in frame.rows.enumerated() where row.contains("a") {
                XCTAssertLessThan(y, rim, "\(frame.name) row \(y): the seedling above the rim")
            }
        }
        XCTAssertTrue(tuck.rows("rest")!.joined().contains("a"))
    }

    /// Mostly still: two flickers (a blink, one eye stalk tipping out) and the weather's two (a drip off its pot's rim in
    /// the rain, a pant on a hot day), the other gestures for its routines, each small beside the still it plays on and
    /// under a second; a tap makes it flinch (eyes shut and pulled down a step), and woken it opens one eye.
    func testItsFlickersAndGesturesAreSmall() {
        for place in CompanionPlace.allCases {
            let awake = tuck.posture(place).awake
            XCTAssertEqual(awake.gestures.filter(\.flicker).map(\.name), ["blink", "twitch", "drip", "pant"])
            XCTAssertEqual(awake.gestures.map(\.name), ["blink", "twitch", "look", "lookUp", "leaf", "drip", "pant"])
            XCTAssertEqual(awake.gestures.map(\.sky), [nil, nil, nil, nil, nil, .rain, .heat])
            for gesture in awake.gestures + [awake.answer] {
                let still = gesture.sky.map { awake.base(CompanionLook.Weather($0)) } ?? awake.rest
                for tick in gesture.ticks {
                    XCTAssertLessThanOrEqual(tuck.difference(tick.frame, still), 16, "\(place) \(gesture.name)")
                }
            }
            for gesture in awake.gestures {
                XCTAssertLessThan(tuck.duration(gesture.ticks, fps: tuck.gestureFPS), 1, gesture.name)
            }
            XCTAssertEqual(awake.answer.name, "flinch")
            let asleep = tuck.posture(place).asleep
            XCTAssertEqual(asleep.gestures.map(\.name), ["dream", "leaf"])
            XCTAssertEqual(asleep.answer.name, "wake")
            XCTAssertNotEqual(asleep.answer.ticks, awake.answer.ticks, "woken, not just looking")
        }
    }

    /// At night its eyes are pulled right in and shut, and its seedling's leaves fold up; it is the one that likes the
    /// rain (eyes up to the sky); in the snow its eyes come down and snow sits on its pot's rim.
    func testItsNightAndWeather() throws {
        let rest = try XCTUnwrap(tuck.rows("rest")), sleep = try XCTUnwrap(tuck.rows("sleep"))
        let rain = try XCTUnwrap(tuck.rows("rain")), snow = try XCTUnwrap(tuck.rows("snow"))
        XCTAssertTrue(rest.joined().contains("k"), "awake: its eyes open")
        XCTAssertFalse(sleep.joined().contains("k"), "asleep: no open eye")
        XCTAssertLessThan(Self.width(of: "a", in: sleep), Self.width(of: "a", in: rest), "asleep: its leaves fold up")
        let eyesAtRest = try XCTUnwrap(Self.topRow(of: "l", in: rest, columns: 0..<10))
        XCTAssertLessThan(try XCTUnwrap(Self.topRow(of: "l", in: rain, columns: 0..<10)), eyesAtRest, "rain: eyes up")
        XCTAssertGreaterThan(try XCTUnwrap(Self.topRow(of: "l", in: snow, columns: 0..<10)), eyesAtRest, "snow: eyes down")
        let rim = try XCTUnwrap(rest.firstIndex { $0.contains("dddddddddd") })
        XCTAssertTrue(snow[rim].contains("llllllllll"), "snow on the rim")
        for place in CompanionPlace.allCases {
            let posture = tuck.posture(place)
            XCTAssertGreaterThanOrEqual(tuck.difference(posture.asleep.rest, posture.awake.rest), 8)
            for weather in [posture.awake.rain, posture.awake.snow] {
                let change = tuck.difference(try XCTUnwrap(weather), posture.awake.rest)
                XCTAssertTrue((4...120).contains(change), "\(place): \(change) pixels")
            }
            XCTAssertEqual(posture.asleep.snow, "sleepSnow", "snow settles on its pot while it sleeps")
            XCTAssertNil(posture.asleep.rain, "asleep wins over rain")
            XCTAssertEqual(posture.awake.heat, "heat")
            XCTAssertNil(posture.asleep.heat, "a hot day is a day")
            XCTAssertEqual(posture.awake.snowDeep, ["snowDeep1", "snowDeep2"])
            XCTAssertEqual(posture.asleep.snowDeep, ["sleepSnowDeep1", "sleepSnowDeep2"], "by morning it is buried")
        }
    }

    /// Snow piles up on its pot (brief 91): a dusting, a cap that half buries its seedling, a heap with one leaf tip
    /// sticking out, the line it sits on the same at every depth. Its flickers and its eye-only routines play over the
    /// pile; the snow's own flake too; it shrugs the heap off only from the deepest, and is back to the dusting.
    func testSnowPilesUpOnItsPotAndItShrugsItOff() throws {
        let awake = tuck.field.awake
        XCTAssertEqual((0...3).map { awake.still(.snow, depth: $0) }, ["snow", "snowDeep1", "snowDeep2", "snowDeep2"])
        // Deeper, its seedling disappears under the pile, a leaf tip still sticking out of the heap.
        var leaf = Int.max
        for still in ["snow", "snowDeep1", "snowDeep2"] {
            let rows = try XCTUnwrap(tuck.rows(still))
            let showing = rows.joined().filter { $0 == "a" }.count
            XCTAssertLessThan(showing, leaf, "\(still): deeper")
            leaf = showing
            XCTAssertEqual(rows[(tuck.seatRow - 1)...], try XCTUnwrap(tuck.rows("snow"))[(tuck.seatRow - 1)...])
        }
        XCTAssertTrue((1...2).contains(leaf), "a leaf tip sticks out of the heap")
        let routine = { (name: String) in try XCTUnwrap(awake.routines.first { $0.name == name }) }
        let shrug = try routine("shrug")
        XCTAssertTrue(shrug.shakesOff)
        XCTAssertEqual(shrug.sky, .snow)
        XCTAssertTrue(tuck.canDraw(shrug, in: .snow, mode: awake, depth: 2), "from the deepest pile")
        XCTAssertFalse(tuck.canDraw(shrug, in: .snow, mode: awake, depth: 1), "not from a cap")
        for depth in 0...2 {
            XCTAssertTrue(tuck.canDraw(try routine("flake"), in: .snow, mode: awake, depth: depth), "a flake at \(depth)")
            for name in ["tuck", "scan"] {
                XCTAssertTrue(tuck.plays(try routine(name), in: .snow, mode: awake, depth: depth), "\(name) at \(depth)")
            }
            for gesture in awake.gestures where gesture.flicker && gesture.sky == nil {
                XCTAssertTrue(tuck.canDraw(gesture, in: .snow, mode: awake, depth: depth), "\(gesture.name) at \(depth)")
            }
        }
        // Its pot can't tip under a heap, nor its seedling wave from under it.
        XCTAssertFalse(tuck.plays(try routine("wobble"), in: .snow, mode: awake, depth: 2))
        XCTAssertFalse(tuck.plays(try routine("tend"), in: .snow, mode: awake, depth: 2))
    }

    /// A hot day (brief 91): its seedling wilts and so does it, eyes down a step and heavy-lidded; it pants; it tips its
    /// pot forward over its head for shade. Its everyday routines rest until the heat goes; its flickers and its reply
    /// to a tap are drawn for its tired eyes; no flourish from a heat still.
    func testAHotDayWiltsItAndItFindsShade() throws {
        let awake = tuck.field.awake
        XCTAssertEqual(awake.base(.heat), "heat")
        let rest = try XCTUnwrap(tuck.rows("rest")), heat = try XCTUnwrap(tuck.rows("heat"))
        let leaves = { (rows: [String]) in rows.firstIndex { $0.contains("a") } ?? 0 }
        XCTAssertGreaterThan(leaves(heat), leaves(rest), "its seedling wilts")
        XCTAssertGreaterThan(try XCTUnwrap(Self.topRow(of: "l", in: heat, columns: 0..<10)),
                             try XCTUnwrap(Self.topRow(of: "l", in: rest, columns: 0..<10)), "its eyes come down")
        for name in ["blink", "twitch", "look", "flinch", "flinchPeek"] {
            XCTAssertNotNil(tuck.index["\(name)@heat"], "\(name) drawn for its tired eyes")
        }
        let shade = try XCTUnwrap(awake.routines.first { $0.name == "shade" })
        XCTAssertEqual(shade.sky, .heat)
        XCTAssertTrue(tuck.canDraw(shade, in: .heat, mode: awake, depth: 0))
        for routine in awake.routines where routine.sky == nil {
            XCTAssertFalse(tuck.plays(routine, in: .heat, mode: awake), "\(routine.name) rests on a hot day")
        }
        let tipped = try XCTUnwrap(tuck.rows("tip2"))
        XCTAssertNotEqual(tipped[9], heat[9], "the pot tipped forward over its head")
    }

    /// Nothing is drawn in the air (brief 91) but a single drop it touches: the drip is one drop under its pot's rim,
    /// the shake starts with one drop falling into its leaf.
    func testNothingInTheAirButOneDrop() {
        for name in ["drip1", "drip3", "drip4"] { XCTAssertEqual(tuck.difference(name, "rain"), 1, name) }
        XCTAssertEqual(tuck.difference("drip2", "rain"), 2, "a drop stretching")
        XCTAssertEqual(tuck.difference("drop1", "rain"), 1, "the drop its leaf catches")
    }

    /// Four routines of its own (it tends its seedling, tucks its eyes in, looks two ways at once, rights its tipping
    /// pot), each three to seven seconds of four to nine moves, and the weather's own: a shake in the rain, a flake in
    /// the snow, a start at thunder, a bask on a clear day, a shrug that sends the piled snow off, shade on a hot day.
    /// The everyday ones are drawn for rain and snow too.
    func testItsRoutines() {
        for place in CompanionPlace.allCases {
            let awake = tuck.posture(place).awake
            let everyday = awake.routines.filter { $0.sky == nil }
            XCTAssertEqual(everyday.map(\.name), ["tend", "tuck", "scan", "wobble"])
            XCTAssertEqual(awake.routines.compactMap(\.sky), [.rain, .snow, .storm, .clear, .snow, .heat])
            XCTAssertEqual(awake.routines.filter(\.shakesOff).map(\.name), ["shrug"])
            for routine in awake.routines {
                let seconds = tuck.duration(of: routine, mode: awake)
                XCTAssertTrue(CompanionCharacter.routineLength.contains(seconds), "\(routine.name): \(seconds) s")
                XCTAssertTrue(CompanionCharacter.routineMoves.contains(routine.moves), "\(routine.name): \(routine.moves)")
            }
            for routine in everyday {
                for weather in [CompanionLook.Weather.plain, .rain, .snow] {
                    XCTAssertTrue(tuck.plays(routine, in: weather, mode: awake), "\(routine.name) in \(weather)")
                }
            }
            XCTAssertTrue(tuck.posture(place).asleep.routines.isEmpty)
        }
        // In the rain its eyes are raised, so a blink there is drawn for the rain, not cut out of the plain one.
        XCTAssertEqual(tuck.drawnIndex("blink", over: "rain", rest: "rest"), tuck.index["blink@rain"])
        XCTAssertEqual(tuck.drawnIndex("tucked", over: "snow", rest: "rest"), tuck.index["tucked@snow"])
    }

    /// Every act the clock plays ends on the still frame for its weather: each routine (under its own sky), the reply
    /// to a tap and the flourish.
    func testEveryActEndsOnTheStillFrameForItsWeather() {
        let clock = CompanionClock(character: tuck)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastTick: TimeInterval = 0.5 / tuck.gestureFPS
        for place in CompanionPlace.allCases {
            let awake = tuck.posture(place).awake
            for (i, routine) in awake.routines.enumerated() {
                let sky: CompanionSky = routine.sky ?? .clouds
                let look = CompanionLook(asleep: false, weather: .init(sky))
                let act = CompanionAct(kind: .routine(i), start: start)
                // A shake-off plays only from the deepest pile, and leaves the bare snow.
                let depth = routine.shakesOff ? awake.deepest : 0
                let stage = CompanionStage(since: .distantPast, place: place, look: look, act: act, sky: sky,
                                           snowDepth: depth)
                let end = clock.end(of: act, stage: stage)
                let last = clock.pose(at: end.addingTimeInterval(-lastTick), stage: stage)
                let still = clock.restPose(at: end, stage: stage)
                XCTAssertEqual(last, still, "\(place) \(routine.name)")
                let drawn = clock.frames(.routine(i), stage: stage).frames
                XCTAssertGreaterThan(drawn.filter { $0 != still }.count, drawn.count / 2, "\(place) \(routine.name): it moves")
                if routine.shakesOff { XCTAssertEqual(still.frame, tuck.index["snow"], "the heap is gone") }
            }
            for kind in [CompanionAct.Kind.answer, .flourish] {
                let act = CompanionAct(kind: kind, start: start)
                let stage = CompanionStage(since: .distantPast, place: place, look: .day, act: act)
                let end = clock.end(of: act, stage: stage)
                let fps: Double = kind == .flourish ? tuck.flourishFPS : tuck.gestureFPS
                let tick: TimeInterval = 0.5 / fps
                XCTAssertEqual(clock.pose(at: end.addingTimeInterval(-tick), stage: stage), clock.restPose(at: end, stage: stage))
            }
        }
    }

    /// Its flourish: its seedling flowers. A bud swells between the leaves and opens into a small white flower, it
    /// beams, a petal falls, the flower folds shut and it is a seedling again, in 2.2 s, rest to rest.
    func testItsFlourishIsAFlower() throws {
        for place in CompanionPlace.allCases {
            let ticks = tuck.posture(place).flourish.map(\.frame)
            XCTAssertEqual(ticks.first, "rest")
            XCTAssertEqual(ticks.last, "rest")
            for frame in ["bud1", "bud2", "bloom1", "bloom2", "petal1", "close1"] {
                XCTAssertTrue(ticks.contains(frame), frame)
            }
            XCTAssertEqual(tuck.flourishDuration(place), 20.0 / 9.0, accuracy: 0.001)
        }
        // The flower: white petals above its leaves, where the still frame has none.
        let rest = try XCTUnwrap(tuck.rows("rest")), bloom = try XCTUnwrap(tuck.rows("bloom2"))
        let leaves = try XCTUnwrap(rest.firstIndex { $0.contains("a") })
        XCTAssertFalse(rest[..<leaves].joined().contains("l"))
        XCTAssertGreaterThanOrEqual(bloom[..<leaves].joined().filter { $0 == "l" }.count, 6)
    }

    /// Nothing floats: its foot is the same in every frame and rests on the edge; on the "+" the whole of the foot's
    /// lowest row lies on the capsule's flat top (its ends curve away), and on the Mac's field on the flat too.
    func testNothingFloats() throws {
        let p = CompanionCharacter.pointsPerPixel
        let rest = try XCTUnwrap(tuck.rows("rest"))
        let foot = Self.opaque(rest[tuck.seatRow - 1])
        XCTAssertEqual(foot, Array(3...17))
        for frame in tuck.frames {
            let lowest = frame.rows.lastIndex { $0.contains { $0 != CompanionInk.clear } }
            XCTAssertEqual(lowest, tuck.seatRow - 1, "\(frame.name): its foot on the edge")
            XCTAssertEqual(Self.opaque(frame.rows[tuck.seatRow - 1]), foot, "\(frame.name): the same foot")
        }
        // The "+": a 76 × 50 pt capsule, flat on top only between its two half-circle ends.
        let size = FloatingAddButton.size
        let radius: CGFloat = size.height / 2
        let offset = CompanionPerch.offset(tuck, spot: .addButton)
        XCTAssertEqual(offset.height, -CGFloat(tuck.seatRow) * p, "the foot's row on the capsule's top edge")
        let spriteWidth: CGFloat = CGFloat(tuck.width) * p
        let left: CGFloat = size.width - spriteWidth + offset.width
        let footLeft: CGFloat = left + CGFloat(foot[0]) * p
        let footRight: CGFloat = left + CGFloat(foot[foot.count - 1] + 1) * p
        for x in [footLeft, footRight] {
            let flatEnd: CGFloat = size.width - radius
            let fromFlat: CGFloat = max(radius - x, x - flatEnd, 0)
            let inside: CGFloat = radius * radius - fromFlat * fromFlat
            let drop: CGFloat = radius - inside.squareRoot()
            XCTAssertLessThan(drop, 0.25, "the capsule's top under the foot's end at \(x) pt is \(drop) pt down")
        }
        // The Mac's field: a rounded rectangle (radius 7); the foot ends well clear of its trailing corner.
        let field = CompanionPerch.offset(tuck, spot: .searchField)
        let clearOfCorner: CGFloat = -field.width + CGFloat(tuck.width - 1 - foot[foot.count - 1]) * p
        XCTAssertGreaterThan(clearOfCorner, 7)
    }

    /// Its tap area is its body above the edge: its face takes a tap, the empty corner above its eyes doesn't.
    func testItsTapArea() throws {
        let rest = try XCTUnwrap(tuck.index[tuck.field.awake.rest])
        let shape = CompanionCharacter.tapShape(runs: tuck.drawn[rest], width: tuck.width, mirrored: false,
                                                belowRow: tuck.seatRow)
        // Sprite pixel (x, y) is the 2 pt square from (2x, 2y): its middle is (2x + 1, 2y + 1).
        XCTAssertTrue(shape.contains(CGPoint(x: 11, y: 31)), "its face, pixel (5, 15)")
        XCTAssertTrue(shape.contains(CGPoint(x: 27, y: 25)), "its pot, pixel (13, 12)")
        XCTAssertFalse(shape.contains(CGPoint(x: 1, y: 1)), "the empty corner")
    }

    // MARK: - Helpers

    private static func opaque(_ row: String) -> [Int] {
        var out: [Int] = []
        for (x, c) in row.enumerated() where c != CompanionInk.clear { out.append(x) }
        return out
    }

    /// How many columns the ink spans, over all rows.
    private static func width(of ink: Character, in rows: [String]) -> Int {
        var columns = Set<Int>()
        for row in rows {
            for (x, c) in row.enumerated() where c == ink { columns.insert(x) }
        }
        return columns.count
    }

    /// The first row where the ink appears within the columns.
    private static func topRow(of ink: Character, in rows: [String], columns: Range<Int>) -> Int? {
        for (y, row) in rows.enumerated() {
            let chars = Array(row)
            if columns.contains(where: { chars[$0] == ink }) { return y }
        }
        return nil
    }
}
