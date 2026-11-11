import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 88: Tuck, Moss's companion. A white snail whose shell is a clay flowerpot with a seedling growing in it (its
/// leaves the theme's accent): mostly still, a blink or an eye stalk tipping out now and then, four routines of its own,
/// the weather's own, a seedling that flowers as its flourish, and a foot that rests on what it sits on in both places.
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

    /// Mostly still: two flickers (a blink, one eye stalk tipping out), the other gestures for its routines, each small
    /// and under a second; a tap makes it flinch (eyes shut and pulled down a step), and woken it opens one eye.
    func testItsFlickersAndGesturesAreSmall() {
        for place in CompanionPlace.allCases {
            let awake = tuck.posture(place).awake
            XCTAssertEqual(awake.gestures.filter(\.flicker).map(\.name), ["blink", "twitch"])
            XCTAssertEqual(awake.gestures.map(\.name), ["blink", "twitch", "look", "lookUp", "leaf"])
            for gesture in awake.gestures + [awake.answer] {
                for tick in gesture.ticks {
                    XCTAssertLessThanOrEqual(tuck.difference(tick.frame, awake.rest), 16, "\(place) \(gesture.name)")
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
        }
    }

    /// Four routines of its own (it tends its seedling, tucks its eyes in, looks two ways at once, rights its tipping
    /// pot), each three to seven seconds of four to nine moves, and the weather's own: a drink in the rain, a flake in
    /// the snow, a start at thunder, a bask on a clear day. The everyday ones are drawn for rain and snow too.
    func testItsRoutines() {
        for place in CompanionPlace.allCases {
            let awake = tuck.posture(place).awake
            let everyday = awake.routines.filter { $0.sky == nil }
            XCTAssertEqual(everyday.map(\.name), ["tend", "tuck", "scan", "wobble"])
            XCTAssertEqual(awake.routines.compactMap(\.sky), [.rain, .snow, .storm, .clear])
            for routine in awake.routines {
                let seconds = tuck.duration(of: routine, mode: awake)
                XCTAssertTrue(CompanionCharacter.routineLength.contains(seconds), "\(routine.name): \(seconds) s")
                XCTAssertTrue(CompanionCharacter.routineMoves.contains(routine.moves), "\(routine.name): \(routine.moves)")
            }
            for routine in everyday {
                for weather in CompanionLook.Weather.allCases {
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
                let stage = CompanionStage(since: .distantPast, place: place, look: look, act: act, sky: sky)
                let end = clock.end(of: act, stage: stage)
                let last = clock.pose(at: end.addingTimeInterval(-lastTick), stage: stage)
                let still = clock.restPose(at: end, stage: stage)
                XCTAssertEqual(last, still, "\(place) \(routine.name)")
                let drawn = clock.frames(.routine(i), stage: stage).frames
                XCTAssertGreaterThan(drawn.filter { $0 != still }.count, drawn.count / 2, "\(place) \(routine.name): it moves")
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
