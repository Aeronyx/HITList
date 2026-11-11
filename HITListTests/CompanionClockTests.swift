import XCTest
import HITListCore
@testable import HITList

/// Briefs 79 and 84: the companions' pure parts on three tiny characters of their own. The clock (a still picture at
/// rest, an act's ticks, a gesture drawn over the weather's frame, the turn that sticks, a routine's steps), and the
/// schedule's rules (night's edges, the gaps, the flourish's and the routine's budgets, never the same gesture three
/// times running nor the same routine twice, the weather's share, the tap's replies, the Debug arguments).
@MainActor
final class CompanionClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// Two characters for the engine alone: one that stays facing the same way, one whose flourish turns it round.
    enum TestCast {
        static let frames: [CompanionCharacter.Frame] = [
            .init(name: "rest", rows: ["....", "kmml", "mlld", "d..d"]),
            .init(name: "blink", rows: ["....", "mmml", "mlld", "d..d"]),
            .init(name: "wag", rows: ["....", "kmml", "mlld", "dd.."]),
            .init(name: "both", rows: ["....", "mmml", "mlld", "dd.."]),
            .init(name: "hop", rows: ["kmml", "mlld", "d..d", "...."]),
            .init(name: "rain", rows: ["llll", "kmml", "mlld", "d..d"]),
            .init(name: "snow", rows: [".l.l", "kmml", "mlld", "d..d"]),
            .init(name: "sleep", rows: ["....", "....", "mmmm", "dddd"]),
            .init(name: "stir", rows: ["....", "....", "mmmm", "ddd."]),
            .init(name: "peek", rows: ["....", "....", "kmmm", "dddd"]),
            .init(name: "sleepSnow", rows: ["....", "l.l.", "mmmm", "dddd"]),
        ]
        static let awake: CompanionCharacter.Mode = CompanionCharacter.Mode(
            rest: "rest", rain: "rain", snow: "snow",
            gestures: [
                .init(name: "blink", weight: 2, ticks: CompanionCharacter.ticks(("blink", 2))),
                .init(name: "wag", ticks: CompanionCharacter.ticks(("wag", 3))),
                .init(name: "both", ticks: CompanionCharacter.ticks(("both", 2))),
            ],
            answer: .init(name: "look", ticks: CompanionCharacter.ticks(("blink", 4))))
        static let asleep: CompanionCharacter.Mode = CompanionCharacter.Mode(
            rest: "sleep", snow: "sleepSnow",
            gestures: [.init(name: "stir", ticks: CompanionCharacter.ticks(("stir", 3)))],
            answer: .init(name: "wake", ticks: CompanionCharacter.ticks(("peek", 8))))
        static func posture(turns: Bool) -> CompanionCharacter.Posture {
            var flourish: [CompanionCharacter.Tick]
            if turns {
                flourish = CompanionCharacter.ticks(("rest", 1), ("hop", 5))
                let back: [CompanionCharacter.Tick] = CompanionCharacter.ticks(mirrored: true, ("hop", 5), ("rest", 1))
                flourish.append(contentsOf: back)
            } else {
                flourish = CompanionCharacter.ticks(("rest", 1), ("hop", 10), ("rest", 1))
            }
            return CompanionCharacter.Posture(awake: awake, asleep: asleep, flourish: flourish)
        }
        static let stayer: CompanionCharacter = CompanionCharacter(
            id: "stayer", name: "Stayer", width: 4, height: 4, seatRow: 3, frames: frames, gestureFPS: 8,
            flourishFPS: 9, flourishTurns: false, field: posture(turns: false), plus: posture(turns: false))
        static let turner: CompanionCharacter = CompanionCharacter(
            id: "turner", name: "Turner", width: 4, height: 4, seatRow: 4, frames: frames, gestureFPS: 8,
            flourishFPS: 9, flourishTurns: true, field: posture(turns: true), plus: posture(turns: true))

        // Brief 84: one that comes alive now and then. Blink and wag are its flickers ("both" plays only inside a
        // routine); three everyday routines (one draws above its head, so not under the rain's or snow's prop), and
        // one each for rain, snow, storm and a clear sky, drawn whole.
        static let routineFrames: [CompanionCharacter.Frame] = frames + [
            .init(name: "lean", rows: ["....", "kmml", "mlld", ".d.d"]),
            .init(name: "tall", rows: [".mm.", "kmml", "mlld", "d..d"]),
            .init(name: "drip", rows: ["lkll", "kmml", "mlld", "d..d"]),
            .init(name: "flake", rows: [".lll", "kmml", "mlld", "d..d"]),
            .init(name: "jolt", rows: ["llll", "mmml", "mlld", "dddd"]),
            .init(name: "bask", rows: ["....", "lmml", "mlld", "d..d"]),
        ]
        typealias Routine = CompanionCharacter.Routine
        static let routines: [Routine] = [
            Routine(name: "shuffle", steps: [.gesture("blink"), .hold(4), .play(("lean", 2), ("rest", 1), ("lean", 2)),
                                             .hold(3), .gesture("wag"), .hold(4), .gesture("blink"), .hold(6)]),
            Routine(name: "stretch", steps: [.play(("tall", 2)), .hold(4), .gesture("blink"), .hold(4),
                                             .play(("tall", 3)), .hold(4), .gesture("both"), .hold(6)]),
            Routine(name: "feet", steps: [.gesture("wag"), .hold(2), .gesture("wag"), .hold(2), .play(("lean", 2)),
                                          .hold(3), .gesture("wag"), .hold(4), .gesture("blink"), .hold(6)]),
            Routine(name: "drip", sky: .rain, steps: [.hold(3), .play(("drip", 3)), .hold(3), .gesture("blink"), .hold(3),
                                                      .play(("drip", 2)), .hold(3), .gesture("wag"), .hold(6)]),
            Routine(name: "flake", sky: .snow, steps: [.hold(3), .play(("flake", 3)), .hold(3), .gesture("blink"),
                                                       .hold(3), .play(("flake", 2)), .hold(3), .gesture("wag"), .hold(6)]),
            Routine(name: "jolt", sky: .storm, steps: [.play(("jolt", 2)), .hold(4), .gesture("blink"), .hold(4),
                                                       .gesture("blink"), .hold(4), .gesture("wag"), .hold(8)]),
            Routine(name: "bask", sky: .clear, steps: [.play(("bask", 4)), .hold(4), .gesture("blink"), .hold(4),
                                                       .play(("bask", 4)), .hold(4), .gesture("blink"), .hold(6)]),
        ]
        static let lively: CompanionCharacter.Mode = CompanionCharacter.Mode(
            rest: "rest", rain: "rain", snow: "snow",
            gestures: [
                .init(name: "blink", weight: 2, ticks: CompanionCharacter.ticks(("blink", 2)), flicker: true),
                .init(name: "wag", ticks: CompanionCharacter.ticks(("wag", 3)), flicker: true),
                .init(name: "both", ticks: CompanionCharacter.ticks(("both", 2))),
            ],
            answer: .init(name: "look", ticks: CompanionCharacter.ticks(("blink", 4))),
            routines: routines)
        static let dancerPosture = CompanionCharacter.Posture(
            awake: lively, asleep: asleep, flourish: CompanionCharacter.ticks(("rest", 1), ("hop", 10), ("rest", 1)))
        static let dancer: CompanionCharacter = CompanionCharacter(
            id: "dancer", name: "Dancer", width: 4, height: 4, seatRow: 3, frames: routineFrames, gestureFPS: 8,
            flourishFPS: 9, flourishTurns: false, field: dancerPosture, plus: dancerPosture)

        // Brief 91: one the weather shows on. A heat still; snow that piles two frames deeper (the deepest covers
        // its eye, so a blink can't be drawn there); a drip in the rain and a pant in the heat, both flickers; a
        // shake-off drawn from the deepest pile; a heat routine.
        static let weatherFrames: [CompanionCharacter.Frame] = frames + routineFrames.filter { $0.name == "lean" } + [
            .init(name: "hot", rows: ["....", "kmml", "mmld", "d..d"]),
            .init(name: "snow2", rows: [".lll", "kmml", "mlld", "d..d"]),
            .init(name: "snow3", rows: ["llll", "lmml", "mlld", "d..d"]),
            .init(name: "drop", rows: ["llll", "kmml", "mlld", "dl.d"]),
            .init(name: "pant", rows: ["....", "kmml", "mmld", "dk.d"]),
            .init(name: "shake1", rows: [".lll", "lmml", "mlld", "d..d"]),
            .init(name: "shake2", rows: ["....", "kmml", "mlld", "d..d"]),
            .init(name: "fan", rows: ["....", "kmml", "mmlm", "d..d"]),
        ]
        static let weatheredAwake: CompanionCharacter.Mode = CompanionCharacter.Mode(
            rest: "rest", rain: "rain", snow: "snow", heat: "hot", snowDeep: ["snow2", "snow3"],
            gestures: [
                .init(name: "blink", weight: 2, ticks: CompanionCharacter.ticks(("blink", 2)), flicker: true),
                .init(name: "wag", ticks: CompanionCharacter.ticks(("wag", 3)), flicker: true),
                .init(name: "drip", ticks: CompanionCharacter.ticks(("drop", 2)), sky: .rain, flicker: true),
                .init(name: "pant", sky: .heat, ticks: CompanionCharacter.ticks(("pant", 2)), flicker: true),
                .init(name: "both", ticks: CompanionCharacter.ticks(("both", 2))),
            ],
            answer: .init(name: "look", ticks: CompanionCharacter.ticks(("blink", 4))),
            routines: [
                routines[0],
                Routine(name: "shake", sky: .snow, shakesOff: true, steps: [
                    .hold(3), .play(("shake1", 2)), .play(("shake2", 2)), .hold(3), .gesture("blink"), .hold(4),
                    .gesture("wag"), .hold(6)]),
                Routine(name: "fan", sky: .heat, steps: [
                    .play(("fan", 3)), .hold(2), .play(("fan", 3)), .hold(2), .gesture("pant"), .hold(4),
                    .gesture("blink"), .hold(8)]),
            ])
        static let weatheredPosture = CompanionCharacter.Posture(
            awake: weatheredAwake, asleep: asleep, flourish: CompanionCharacter.ticks(("rest", 1), ("hop", 10), ("rest", 1)))
        static let weathered: CompanionCharacter = CompanionCharacter(
            id: "weathered", name: "Weathered", width: 4, height: 4, seatRow: 3, frames: weatherFrames, gestureFPS: 8,
            flourishFPS: 9, flourishTurns: false, field: weatheredPosture, plus: weatheredPosture)

        // Brief 100: one that idles. Three flickers (a blink, the heaviest, a wag and a glance), three little loops
        // (blink-wag-wag, glance-glance-blink, a double blink) and one long routine; asleep a breath and a stir.
        static let idlerFrames: [CompanionCharacter.Frame] = frames + routineFrames.filter { $0.name == "lean" } + [
            .init(name: "glance", rows: ["....", "mkml", "mlld", "d..d"]),
            .init(name: "breath", rows: ["....", "....", "mmmm", "dd.d"]),
        ]
        static let idlerAwake: CompanionCharacter.Mode = CompanionCharacter.Mode(
            rest: "rest", rain: "rain", snow: "snow",
            gestures: [
                .init(name: "blink", weight: 3, ticks: CompanionCharacter.ticks(("blink", 2)), flicker: true),
                .init(name: "wag", ticks: CompanionCharacter.ticks(("wag", 3)), flicker: true),
                .init(name: "glance", ticks: CompanionCharacter.ticks(("glance", 4)), flicker: true),
                .init(name: "both", ticks: CompanionCharacter.ticks(("both", 2))),
            ],
            answer: .init(name: "look", ticks: CompanionCharacter.ticks(("blink", 4))),
            routines: [
                routines[0],
                Routine(name: "blinkSwing", little: true, steps: [.gesture("blink"), .hold(2), .gesture("wag"), .gesture("wag")]),
                Routine(name: "glances", little: true, steps: [.gesture("glance"), .hold(2), .gesture("glance"), .hold(1),
                                                              .gesture("blink")]),
                Routine(name: "twice", little: true, steps: [.gesture("blink"), .hold(1), .gesture("blink")]),
            ])
        static let idlerAsleep: CompanionCharacter.Mode = CompanionCharacter.Mode(
            rest: "sleep", snow: "sleepSnow",
            gestures: [.init(name: "stir", ticks: CompanionCharacter.ticks(("stir", 3))),
                       .init(name: "breath", weight: 2, ticks: CompanionCharacter.ticks(("breath", 4)))],
            answer: .init(name: "wake", ticks: CompanionCharacter.ticks(("peek", 8))))
        static let idlerPosture = CompanionCharacter.Posture(
            awake: idlerAwake, asleep: idlerAsleep, flourish: CompanionCharacter.ticks(("rest", 1), ("hop", 10), ("rest", 1)))
        static let idler: CompanionCharacter = CompanionCharacter(
            id: "idler", name: "Idler", width: 4, height: 4, seatRow: 3, frames: idlerFrames, gestureFPS: 8,
            flourishFPS: 9, flourishTurns: false, field: idlerPosture, plus: idlerPosture)

        // Brief 100: the least a character can be: one flicker, no loops, no routines.
        static let lonerPosture = CompanionCharacter.Posture(
            awake: CompanionCharacter.Mode(
                rest: "rest", gestures: [.init(name: "blink", ticks: CompanionCharacter.ticks(("blink", 2)), flicker: true)],
                answer: .init(name: "look", ticks: CompanionCharacter.ticks(("blink", 4)))),
            asleep: CompanionCharacter.Mode(
                rest: "sleep", gestures: [.init(name: "stir", ticks: CompanionCharacter.ticks(("stir", 3)))],
                answer: .init(name: "wake", ticks: CompanionCharacter.ticks(("peek", 8)))),
            flourish: CompanionCharacter.ticks(("rest", 1), ("hop", 10), ("rest", 1)))
        static let loner: CompanionCharacter = CompanionCharacter(
            id: "loner", name: "Loner", width: 4, height: 4, seatRow: 3,
            frames: frames.filter { ["rest", "blink", "hop", "sleep", "stir", "peek"].contains($0.name) }, gestureFPS: 8,
            flourishFPS: 9, flourishTurns: false, field: lonerPosture, plus: lonerPosture)

        static let all: [CompanionCharacter] = [stayer, turner, dancer, weathered, idler, loner]
    }

    private func stage(_ act: CompanionAct? = nil, look: CompanionLook = .day, turned: Bool = false,
                       place: CompanionPlace = .field, sky: CompanionSky = .unknown, depth: Int = 0) -> CompanionStage {
        CompanionStage(since: t0, place: place, look: look, turned: turned, act: act, sky: sky, snowDepth: depth)
    }

    func testTheTestCastIsGoodData() {
        for character in TestCast.all { XCTAssertEqual(character.problems, [], character.id) }
    }

    // MARK: - The clock

    func testAtRestItIsAStillPictureThatNeverChanges() {
        let c = CompanionClock(character: TestCast.stayer)
        let s = stage()
        for t in [0.0, 1, 59, 3_600, 86_400] {
            XCTAssertEqual(c.pose(at: at(t), stage: s), CompanionPose(frame: TestCast.stayer.index["rest"]!, mirrored: false))
        }
        XCTAssertNil(c.nextChange(after: t0, stage: s), "nothing to redraw while it rests")
        var entries = CompanionTimeline(clock: c, stage: s).entries(from: t0, mode: .normal).makeIterator()
        XCTAssertEqual(entries.next(), t0)
        XCTAssertNil(entries.next(), "the timeline ends: no ticking")
    }

    func testAGesturePlaysItsTicksThenTheRestFrameIsBack() {
        let character = TestCast.stayer
        let c = CompanionClock(character: character)
        let s = stage(CompanionAct(kind: .gesture(1), start: at(10)))
        XCTAssertEqual(c.pose(at: at(9.9), stage: s).frame, character.index["rest"])
        for k in 0..<3 {
            let middle: TimeInterval = (Double(k) + 0.5) / 8
            XCTAssertEqual(c.pose(at: at(10 + middle), stage: s).frame, character.index["wag"], "tick \(k)")
        }
        XCTAssertEqual(c.end(of: s.act!, stage: s), at(10.375))
        XCTAssertEqual(c.pose(at: at(10.375), stage: s).frame, character.index["rest"])
        XCTAssertFalse(c.isActing(at: at(10.375), stage: s))
        // Its changes: the first tick, then the rest frame at the end; nothing after.
        XCTAssertEqual(c.nextChange(after: at(9), stage: s), at(10))
        XCTAssertEqual(c.nextChange(after: at(10), stage: s), at(10.375))
        XCTAssertNil(c.nextChange(after: at(10.375), stage: s))
    }

    func testAGestureInTheRainIsDrawnUnderTheProp() {
        let character = TestCast.stayer
        let c = CompanionClock(character: character)
        let rainy = CompanionLook(asleep: false, weather: .rain)
        let s = stage(CompanionAct(kind: .gesture(0), start: at(10)), look: rainy)
        XCTAssertEqual(c.pose(at: at(5), stage: s).frame, character.index["rain"], "the rain pose at rest")
        let blinking = c.pose(at: at(10.05), stage: s).frame
        let rows = character.drawn[blinking]
        XCTAssertEqual(rows, CompanionCharacter.runs(of: ["llll", "mmml", "mlld", "d..d"]), "the blink, under the prop")
        XCTAssertEqual(c.pose(at: at(11), stage: s).frame, character.index["rain"])
    }

    func testEachLookHasItsStillFrame() {
        let character = TestCast.stayer
        let c = CompanionClock(character: character)
        func frame(_ look: CompanionLook) -> String {
            character.frames[c.pose(at: t0, stage: stage(look: look)).frame].name
        }
        XCTAssertEqual(frame(.day), "rest")
        XCTAssertEqual(frame(.init(asleep: false, weather: .rain)), "rain")
        XCTAssertEqual(frame(.init(asleep: false, weather: .snow)), "snow")
        XCTAssertEqual(frame(.init(asleep: true, weather: .plain)), "sleep")
        XCTAssertEqual(frame(.init(asleep: true, weather: .rain)), "sleep", "asleep wins over rain without a pose for it")
        XCTAssertEqual(frame(.init(asleep: true, weather: .snow)), "sleepSnow")
        XCTAssertEqual(CompanionLook.Weather(.storm), .rain)
        XCTAssertEqual(CompanionLook.Weather(.clouds), .plain)
        XCTAssertEqual(CompanionLook.Weather(.unknown), .plain)
        XCTAssertEqual(CompanionLook.Weather(.clear), .plain)
        XCTAssertEqual(CompanionLook.Weather(.snow), .snow)
    }

    func testAFlourishPlaysAndATurnerStaysTurned() {
        for character in TestCast.all {
            let c = CompanionClock(character: character)
            let s = stage(CompanionAct(kind: .flourish, start: at(100)))
            let ticks = character.field.flourish
            for (k, tick) in ticks.enumerated() {
                let middle: TimeInterval = (Double(k) + 0.5) / 9
                let pose = c.pose(at: at(100 + middle), stage: s)
                XCTAssertEqual(pose.frame, character.index[tick.frame], "\(character.id) tick \(k)")
                XCTAssertEqual(pose.mirrored, tick.mirrored, "\(character.id) tick \(k)")
            }
            let after = c.end(of: s.act!, stage: s)
            XCTAssertEqual(c.pose(at: after.addingTimeInterval(3_600), stage: s),
                           CompanionPose(frame: character.index["rest"]!, mirrored: character.flourishTurns))
            XCTAssertNil(c.nextChange(after: after, stage: s))
        }
        // Already turned: a gesture plays mirrored, and the next flourish turns it back.
        let c = CompanionClock(character: TestCast.turner)
        XCTAssertTrue(c.pose(at: at(10.05), stage: stage(CompanionAct(kind: .gesture(0), start: at(10)), turned: true)).mirrored)
        XCTAssertFalse(c.pose(at: at(200), stage: stage(CompanionAct(kind: .flourish, start: at(100)), turned: true)).mirrored)
    }

    func testReduceMotionIsTheStillPoseForTheHourAndTheWeather() {
        let character = TestCast.turner
        let c = CompanionClock(character: character)
        let s = stage(CompanionAct(kind: .gesture(1), start: at(10)), look: .init(asleep: true, weather: .snow))
        XCTAssertEqual(c.pose(at: at(10.1), stage: s, still: true).frame, character.index["sleepSnow"])
    }

    func testNextChangeSkipsHeldFramesAndNeverStalls() {
        for character in TestCast.all {
            let c = CompanionClock(character: character)
            let s = stage(CompanionAct(kind: .flourish, start: at(30)))
            var t = at(29)
            var changes = 0
            while let next = c.nextChange(after: t, stage: s) {
                XCTAssertGreaterThan(next, t)
                XCTAssertNotEqual(c.pose(at: next, stage: s), c.pose(at: t, stage: s), "a change is a change")
                t = next
                changes += 1
                XCTAssertLessThan(changes, 40)
            }
            // rest → hop (held) → … → rest: a handful of redraws, not one per tick.
            XCTAssertLessThanOrEqual(changes, 4, character.id)
        }
    }

    // MARK: - The schedule

    func testNightIsTenToSeven() {
        XCTAssertFalse(CompanionSchedule.isNight(hour: 21))
        XCTAssertTrue(CompanionSchedule.isNight(hour: 22))
        XCTAssertTrue(CompanionSchedule.isNight(hour: 23))
        XCTAssertTrue(CompanionSchedule.isNight(hour: 0))
        XCTAssertTrue(CompanionSchedule.isNight(hour: 6))
        XCTAssertFalse(CompanionSchedule.isNight(hour: 7))
        XCTAssertFalse(CompanionSchedule.isNight(hour: 12))
    }

    func testTheGaps() {
        XCTAssertEqual(CompanionSchedule.idleGap, 6...36, "brief 100's contract")
        XCTAssertEqual(CompanionSchedule.firstIdle, 2...6)
        XCTAssertEqual(CompanionSchedule.routineGap, 180...480)
        for i in 0..<500 {
            let u = CompanionRandom.unit(9, i)
            XCTAssertTrue((6...36).contains(CompanionSchedule.idleGap(unit: u)), "an idle every 6 to 36 s")
            XCTAssertTrue((2...6).contains(CompanionSchedule.firstIdle(unit: u)), "the first 2 to 6 s in")
            XCTAssertTrue((180...480).contains(CompanionSchedule.routineBudget(unit: u)), "a routine every 3 to 8 minutes")
        }
        XCTAssertEqual(CompanionSchedule.idleGap(unit: 0), 6)
        XCTAssertEqual(CompanionSchedule.idleGap(unit: 1), 36)
        XCTAssertEqual(CompanionSchedule.routineBudget(unit: 0), 180)
        XCTAssertEqual(CompanionSchedule.routineBudget(unit: 1), 480)
    }

    func testTheFlourishsBudgetAveragesThreeHoursAndNeverUnderFortyFive() {
        let draws = (0..<20_000).map { CompanionSchedule.flourishBudget(unit: CompanionRandom.unit(5, $0)) }
        XCTAssertGreaterThanOrEqual(draws.min()!, 45 * 60)
        XCTAssertLessThanOrEqual(draws.max()!, 12 * 3600)
        var total: TimeInterval = 0
        for draw in draws { total += draw }
        let meanHours: Double = total / Double(draws.count) / 3600
        XCTAssertEqual(meanHours, 3, accuracy: 0.1, "about once in three hours of showing")
        XCTAssertEqual(CompanionSchedule.flourishBudget(unit: 0), 45 * 60)
    }

    /// Brief 100: never the same idle twice running (unless it is all there is), a little loop about one in three,
    /// by weight within a kind, the sky's own about every other.
    func testPickingAnIdle() {
        typealias Choice = CompanionSchedule.IdleChoice
        let choices: [Choice] = [.init(idle: .flicker(0), weight: 5), .init(idle: .flicker(1)), .init(idle: .flicker(2)),
                                 .init(idle: .little(0)), .init(idle: .little(1))]
        var last: CompanionSchedule.Idle?
        var counts: [CompanionSchedule.Idle: Int] = [:]
        for i in 0..<6_000 {
            let pick = CompanionSchedule.pickIdle(choices, last: last, sky: CompanionRandom.unit(1, i),
                                                  kind: CompanionRandom.unit(2, i), pick: CompanionRandom.unit(3, i))!
            XCTAssertNotEqual(pick, last, "the same \(pick) twice running at \(i)")
            counts[pick, default: 0] += 1
            last = pick
        }
        let loops: Int = (counts[.little(0)] ?? 0) + (counts[.little(1)] ?? 0)
        XCTAssertEqual(Double(loops) / 6_000, 1.0 / 3, accuracy: 0.03, "a little loop about one in three")
        XCTAssertGreaterThan(counts[.flicker(0)]!, counts[.flicker(1)]! * 2, "the heaviest flicker the most common")
        XCTAssertGreaterThan(counts[.flicker(2)]!, 0)
        // One is all it has: that one, again and again; nothing: nothing.
        XCTAssertEqual(CompanionSchedule.pickIdle([.init(idle: .flicker(3))], last: .flicker(3), sky: 0.5, kind: 0.1, pick: 0.5),
                       .flicker(3))
        XCTAssertNil(CompanionSchedule.pickIdle([], last: nil, sky: 0, kind: 0, pick: 0))
        // Only loops, or only flickers: the kind it has.
        XCTAssertEqual(CompanionSchedule.pickIdle([.init(idle: .little(2))], last: nil, sky: 0.9, kind: 0.9, pick: 0.9), .little(2))
        // The sky's own: half with two of its own, about four in ten with only one (it can't come twice running).
        for (own, share) in [([Choice(idle: .flicker(5), own: true), Choice(idle: .little(5), own: true)], 0.5),
                             ([Choice(idle: .flicker(5), own: true)], 0.43)] as [([Choice], Double)] {
            var count = 0
            var previous: CompanionSchedule.Idle?
            for i in 0..<6_000 {
                let pick = CompanionSchedule.pickIdle(choices + own, last: previous, sky: CompanionRandom.unit(4, i),
                                                      kind: CompanionRandom.unit(5, i), pick: CompanionRandom.unit(6, i))!
                if own.contains(where: { $0.idle == pick }) { count += 1 }
                previous = pick
            }
            XCTAssertEqual(Double(count) / 6_000, share, accuracy: 0.03, "\(own.count) of its own")
        }
    }

    func testTheRulesForAFlourish() {
        func may(_ now: TimeInterval, look: CompanionLook = .day, acting: Bool = false, still: Bool = false,
                 calm: Bool = false, lowPower: Bool = false, last: TimeInterval? = nil, onScreen: Bool = true) -> Bool {
            CompanionSchedule.mayFlourish(now: at(now), look: look, onScreenSince: onScreen ? t0 : nil, acting: acting,
                                          still: still, calm: calm, lowPower: lowPower, lastFlourish: last.map(at))
        }
        XCTAssertFalse(may(19.9), "never in the first 20 seconds on a screen")
        XCTAssertTrue(may(20))
        XCTAssertFalse(may(100, onScreen: false))
        XCTAssertFalse(may(100, acting: true), "never over a gesture")
        XCTAssertFalse(may(100, still: true), "Reduce Motion")
        XCTAssertFalse(may(100, calm: true), "Reduce Effects: gestures, no flourish")
        XCTAssertFalse(may(100, lowPower: true), "Low Power Mode: gestures, no flourish")
        XCTAssertFalse(may(100, look: .init(asleep: true, weather: .plain)), "never asleep")
        XCTAssertFalse(may(100, look: .init(asleep: false, weather: .rain)), "sheltering from the rain")
        XCTAssertFalse(may(100, look: .init(asleep: false, weather: .snow)))
        XCTAssertFalse(may(3_000, last: 400), "never within 45 minutes of the last")
        XCTAssertTrue(may(3_100, last: 400))
    }

    func testWhatATapDoes() {
        func reply(_ now: TimeInterval, look: CompanionLook = .day, acting: Bool = false, still: Bool = false,
                   calm: Bool = false, lowPower: Bool = false, last: TimeInterval? = nil,
                   answer: TimeInterval? = nil) -> CompanionSchedule.TapReply {
            CompanionSchedule.tapReply(now: at(now), onScreen: true, look: look, acting: acting, still: still, calm: calm,
                                       lowPower: lowPower, lastFlourish: last.map(at), lastAnswer: answer.map(at))
        }
        XCTAssertEqual(reply(5), .flourish, "none has played on this device: the tap plays it")
        XCTAssertEqual(reply(1_299.9, last: 100), .answer, "a flourish within the last 20 minutes: a small reply")
        XCTAssertEqual(reply(1_300, last: 100), .flourish)
        XCTAssertEqual(reply(1_000, last: 100, answer: 995), .nothing, "a reply at most once every ten seconds")
        XCTAssertEqual(reply(1_000, last: 100, answer: 990), .answer)
        XCTAssertEqual(reply(5, look: .init(asleep: true, weather: .plain)), .answer, "asleep: it wakes for a moment")
        XCTAssertEqual(reply(5, look: .init(asleep: false, weather: .rain)), .answer)
        XCTAssertEqual(reply(5, calm: true), .answer)
        XCTAssertEqual(reply(5, lowPower: true), .answer)
        XCTAssertEqual(reply(5, still: true), .nothing, "Reduce Motion: nothing moves")
        XCTAssertEqual(reply(5, acting: true), .nothing)
    }

    // MARK: - Routines (brief 84)

    func testARoutineIsItsStepsInOrderAndEndsOnTheStillFrame() {
        let character = TestCast.dancer
        let c = CompanionClock(character: character)
        let mode = character.field.awake
        let shuffle = mode.routines[0]
        let ticks = mode.ticks(of: shuffle).map(\.tick.frame)
        XCTAssertEqual(ticks, ["blink", "blink", "rest", "rest", "rest", "rest", "lean", "lean", "rest", "lean", "lean",
                               "rest", "rest", "rest", "wag", "wag", "wag", "rest", "rest", "rest", "rest", "blink",
                               "blink", "rest", "rest", "rest", "rest", "rest", "rest"])
        XCTAssertEqual(shuffle.moves, 4)
        XCTAssertEqual(character.duration(of: shuffle, mode: mode), 29.0 / 8, accuracy: 0.0001)
        let s = stage(CompanionAct(kind: .routine(0), start: at(10)))
        XCTAssertEqual(c.end(of: s.act!, stage: s), at(10 + 29.0 / 8))
        for (k, name) in ticks.enumerated() {
            let middle: TimeInterval = (Double(k) + 0.5) / 8
            XCTAssertEqual(c.pose(at: at(10 + middle), stage: s).frame, character.index[name], "tick \(k)")
        }
        XCTAssertEqual(c.pose(at: c.end(of: s.act!, stage: s), stage: s).frame, character.index["rest"])
        XCTAssertNil(c.nextChange(after: c.end(of: s.act!, stage: s), stage: s), "and still again: nothing to redraw")
        // Held beats are not redraws: the timeline wakes only where the picture changes.
        var t = at(9)
        var changes = 0
        while let next = c.nextChange(after: t, stage: s) { t = next; changes += 1 }
        XCTAssertEqual(changes, 10)
    }

    func testARoutineInTheRainIsDrawnUnderThePropAndItsOwnSkysFramesWhole() {
        let character = TestCast.dancer
        let c = CompanionClock(character: character)
        let rainy = CompanionLook(asleep: false, weather: .rain)
        // An everyday routine in the rain: its held beats are the rain pose, its moves drawn under the prop.
        let s = stage(CompanionAct(kind: .routine(0), start: at(10)), look: rainy)
        XCTAssertEqual(c.pose(at: at(10 + 2.5 / 8), stage: s).frame, character.index["rain"], "a hold is the rain pose")
        let leaning = character.drawn[c.pose(at: at(10 + 6.5 / 8), stage: s).frame]
        XCTAssertEqual(leaning, CompanionCharacter.runs(of: ["llll", "kmml", "mlld", ".d.d"]), "the lean, under the prop")
        // Its own sky's routine: its frames as drawn.
        let drip = stage(CompanionAct(kind: .routine(3), start: at(10)), look: rainy, sky: .rain)
        XCTAssertEqual(c.pose(at: at(10 + 0.5 / 8), stage: drip).frame, character.index["rain"])
        XCTAssertEqual(c.pose(at: at(10 + 3.5 / 8), stage: drip).frame, character.index["drip"])
        let blink = character.drawn[c.pose(at: at(10 + 9.5 / 8), stage: drip).frame]
        XCTAssertEqual(blink, CompanionCharacter.runs(of: ["llll", "mmml", "mlld", "d..d"]), "its blink, under the prop")
        // What can be drawn where: "stretch" draws above its head, where the rain's prop and the snow's dusting are.
        let mode = character.field.awake
        XCTAssertTrue(character.plays(mode.routines[1], in: .plain, mode: mode))
        XCTAssertFalse(character.plays(mode.routines[1], in: .rain, mode: mode))
        XCTAssertFalse(character.plays(mode.routines[1], in: .snow, mode: mode))
        XCTAssertTrue(character.plays(mode.routines[0], in: .rain, mode: mode))
        XCTAssertFalse(character.plays(mode.routines[3], in: .rain, mode: mode), "a sky's own is not an everyday one")
    }

    func testFlickersAreTheMarkedGesturesOrAllOfThem() {
        XCTAssertEqual(TestCast.dancer.field.awake.flickers, [0, 1], "blink and wag; both plays only in routines")
        XCTAssertEqual(TestCast.stayer.field.awake.flickers, [0, 1, 2], "none marked: every gesture, as before brief 84")
        XCTAssertTrue(TestCast.stayer.field.awake.routines.isEmpty, "a character with no routines is good data")
    }

    func testPickingARoutine() {
        let weights = [1, 1, 1, 1, 1, 1, 1]
        // Never the one that played before; with nothing else, nothing.
        for i in 0..<400 {
            let pick = CompanionSchedule.pickRoutine(everyday: [0, 1, 2], weather: [], weights: weights, last: 1,
                                                     unit: CompanionRandom.unit(1, i), pick: CompanionRandom.unit(2, i))
            XCTAssertNotEqual(pick, 1)
            XCTAssertNotNil(pick)
        }
        XCTAssertNil(CompanionSchedule.pickRoutine(everyday: [2], weather: [], weights: weights, last: 2, unit: 0.1, pick: 0.1))
        XCTAssertEqual(CompanionSchedule.pickRoutine(everyday: [2], weather: [], weights: weights, last: nil, unit: 0.9, pick: 0.9), 2)
        // A sky's own about every other time: one of its own, or two, over a long run.
        for (weather, share) in [([3], 0.44), ([3, 4], 0.5)] as [([Int], Double)] {
            var own = 0
            var last: Int?
            for i in 0..<4_000 {
                let pick = CompanionSchedule.pickRoutine(everyday: [0, 1, 2], weather: weather, weights: weights, last: last,
                                                         unit: CompanionRandom.unit(3, i), pick: CompanionRandom.unit(4, i))
                if let pick, weather.contains(pick) { own += 1 }
                last = pick
            }
            XCTAssertEqual(Double(own) / 4_000, share, accuracy: 0.04, "\(weather)")
        }
        // By weight within a pool.
        var heavy = 0
        for i in 0..<2_000 {
            let pick = CompanionSchedule.pickRoutine(everyday: [0, 1], weather: [], weights: [3, 1], last: nil,
                                                     unit: 0.9, pick: CompanionRandom.unit(5, i))
            if pick == 0 { heavy += 1 }
        }
        XCTAssertEqual(Double(heavy) / 2_000, 0.75, accuracy: 0.05)
    }

    func testTheChecksCatchBadRoutines() {
        typealias C = CompanionCharacter
        let blink = C.Gesture(name: "blink", ticks: C.ticks(("blink", 2)), flicker: true)
        let routines = [
            C.Routine(name: "short", steps: [.gesture("blink"), .gesture("blink"), .gesture("blink"), .gesture("blink")]),
            C.Routine(name: "few", steps: [.gesture("blink"), .hold(30)]),
            C.Routine(name: "ghost", steps: [.gesture("wave"), .play(("nowhere", 1)), .hold(10), .gesture("blink"),
                                             .hold(10), .gesture("blink")]),
            C.Routine(name: "pop", steps: [.play(("jump", 2)), .hold(10), .gesture("blink"), .hold(10), .gesture("blink"),
                                           .hold(4), .gesture("blink")]),
            C.Routine(name: "cloudy", sky: .clouds, steps: [.gesture("blink"), .hold(10), .gesture("blink"), .hold(10),
                                                            .gesture("blink"), .hold(4), .gesture("blink")]),
        ]
        let awake = C.Mode(rest: "rest", gestures: [blink], answer: blink, routines: routines)
        let asleep = C.Mode(rest: "rest", gestures: [blink], answer: blink, routines: [routines[0]])
        let flourish = C.ticks(("rest", 1), ("blink", 10), ("rest", 1))
        let posture = C.Posture(awake: awake, asleep: asleep, flourish: flourish)
        let rows = ["mmmmmmmm", "mlllllll", "mlklkllm", "mmmmmmmm", "dddddddd"]
        let jump = ["llllllll", "llllllll", "dddddddd", "dddddddd", "........"]
        let bad = C(id: "bad", name: "Bad", width: 8, height: 5, seatRow: 4,
                    frames: [.init(name: "rest", rows: rows),
                             .init(name: "blink", rows: rows.enumerated().map { $0.offset == 2 ? "mlmlmllm" : $0.element }),
                             .init(name: "jump", rows: jump)],
                    gestureFPS: 8, flourishFPS: 9, flourishTurns: false, field: posture, plus: posture)
        let problems = bad.problems.joined(separator: "\n")
        for expected in ["routines while asleep", "routine short: 1.0 s", "routine few: 1 moves", "no gesture wave",
                         "no frame nowhere", "routine pop: starts or ends", "no routine belongs to a clouds sky"] {
            XCTAssertTrue(problems.contains(expected), "missing: \(expected)\n\(problems)")
        }
        // Brief 100: a little loop is two to four moves in at most 2.5 s, and never a shake-off.
        let loops = [
            C.Routine(name: "one", little: true, steps: [.gesture("blink"), .hold(2)]),
            C.Routine(name: "many", little: true, steps: [.gesture("blink"), .gesture("blink"), .gesture("blink"),
                                                          .gesture("blink"), .gesture("blink")]),
            C.Routine(name: "slow", little: true, steps: [.gesture("blink"), .hold(20), .gesture("blink")]),
            C.Routine(name: "shaky", sky: .snow, shakesOff: true, little: true, steps: [.gesture("blink"), .gesture("blink")]),
            C.Routine(name: "fine", little: true, steps: [.gesture("blink"), .hold(2), .gesture("blink"), .gesture("blink")]),
        ]
        let small = C.Posture(awake: C.Mode(rest: "rest", gestures: [blink], answer: blink, routines: loops),
                              asleep: C.Mode(rest: "rest", gestures: [blink], answer: blink), flourish: flourish)
        let little = C(id: "little", name: "Little", width: 8, height: 5, seatRow: 4, frames: bad.frames, gestureFPS: 8,
                       flourishFPS: 9, flourishTurns: false, field: small, plus: small)
        let found = little.problems.joined(separator: "\n")
        for expected in ["routine one: 1 moves, not 2…4 for a little loop", "routine many: 5 moves",
                         "routine slow: 3.0 s, a little loop longer than 2.5 s", "routine shaky: a little loop can't shake"] {
            XCTAssertTrue(found.contains(expected), "missing: \(expected)\n\(found)")
        }
        XCTAssertFalse(found.contains("routine fine"), found)
        XCTAssertFalse(found.contains("not 3.0…7.0"), "a little loop isn't held to a routine's length:\n\(found)")
    }

    // MARK: - The weather on the creature (brief 91)

    func testTheContractReadsInEveryOrder() {
        typealias C = CompanionCharacter
        let ticks = C.ticks(("blink", 2))
        let a = C.Gesture(name: "a", weight: 2, ticks: ticks, flicker: true, sky: .rain)
        let b = C.Gesture(name: "b", ticks: ticks, sky: .heat, flicker: true)
        let c = C.Gesture(name: "c", sky: .snow, ticks: ticks)
        XCTAssertEqual([a.sky, b.sky, c.sky], [.rain, .heat, .snow])
        XCTAssertEqual([a.flicker, b.flicker, c.flicker], [true, true, false])
        XCTAssertNil(C.Gesture(name: "d", ticks: ticks).sky, "nil: every sky")
        let r1 = C.Routine(name: "r1", sky: .snow, shakesOff: true, steps: [.hold(1)])
        let r2 = C.Routine(name: "r2", sky: .snow, shakesOff: true, weight: 2, steps: [.hold(1)])
        let r3 = C.Routine(name: "r3", sky: .heat, weight: 2, steps: [.hold(1)])
        XCTAssertEqual([r1.shakesOff, r2.shakesOff, r3.shakesOff], [true, true, false])
        XCTAssertEqual(r2.weight, 2)
        let m1 = C.Mode(rest: "rest", snow: "snow", gestures: [a], answer: a, routines: [r1], heat: "hot", snowDeep: ["s2"])
        let m2 = C.Mode(rest: "rest", snow: "snow", heat: "hot", snowDeep: ["s2"], gestures: [a], answer: a)
        let m3 = C.Mode(rest: "rest", snow: "snow", snowDeep: ["s2"], gestures: [a], answer: a)
        let m4 = C.Mode(rest: "rest", gestures: [a], answer: a)
        XCTAssertEqual([m1.heat, m2.heat, m3.heat, m4.heat], ["hot", "hot", nil, nil])
        XCTAssertEqual([m1.snowDeep, m2.snowDeep, m3.snowDeep, m4.snowDeep], [["s2"], ["s2"], ["s2"], []])
        XCTAssertEqual(CompanionLook.Weather(.heat), .heat)
        XCTAssertEqual(m1.still(.heat, depth: 0), "hot")
        XCTAssertEqual(m4.still(.heat, depth: 0), "rest", "no heat still: the rest")
        XCTAssertEqual(m1.still(.snow, depth: 0), "snow")
        XCTAssertEqual(m1.still(.snow, depth: 5), "s2", "the pile stops at its last")
        XCTAssertEqual(m4.still(.snow, depth: 2), "rest")
    }

    func testAShakeOffShowsTheBareSnowFromItsFirstFrameOfItsOwn() {
        let character = TestCast.weathered
        let c = CompanionClock(character: character)
        let snowy = CompanionLook(asleep: false, weather: .snow)
        let mode = character.field.awake
        // At the deepest pile the shake can play; it can't at the bare snow or half way.
        XCTAssertTrue(character.canDraw(mode.routines[1], in: .snow, mode: mode, depth: 2))
        XCTAssertFalse(character.canDraw(mode.routines[1], in: .snow, mode: mode, depth: 1))
        XCTAssertFalse(character.canDraw(mode.routines[1], in: .snow, mode: mode, depth: 0))
        let s = stage(CompanionAct(kind: .routine(1), start: at(10)), look: snowy, sky: .snow, depth: 2)
        func frame(_ tick: Double) -> String {
            let pose = c.pose(at: at(10 + (tick + 0.5) / 8), stage: s)
            return character.frames.indices.contains(pose.frame) ? character.frames[pose.frame].name : "composite"
        }
        XCTAssertEqual(frame(0), "snow3", "held at the deepest pile")
        XCTAssertEqual(frame(3), "shake1")
        XCTAssertEqual(frame(5), "shake2")
        XCTAssertEqual(frame(7), "snow", "then the bare snow")
        XCTAssertEqual(character.drawn[c.pose(at: at(10 + 10.5 / 8), stage: s).frame],
                       CompanionCharacter.runs(of: [".l.l", "mmml", "mlld", "d..d"]), "its blink over the bare snow")
        let end = c.end(of: s.act!, stage: s)
        XCTAssertEqual(c.snowDepth(at: end, stage: s), 0, "shaken off")
        XCTAssertEqual(c.restPose(at: end, stage: s).frame, character.index["snow"], "no flash of the old pile at its end")
        // At the deepest pile a blink would cut through the snow on its eye: not drawn there; one frame less deep it is.
        let deep = stage(look: snowy, sky: .snow, depth: 2)
        XCTAssertFalse(c.canDraw(.gesture(0), stage: deep))
        XCTAssertTrue(c.canDraw(.gesture(1), stage: deep), "the wag leaves the pile alone")
        XCTAssertTrue(c.canDraw(.gesture(0), stage: stage(look: snowy, sky: .snow, depth: 1)))
        XCTAssertEqual(c.restPose(at: t0, stage: deep).frame, character.index["snow3"])
    }

    func testTheWeathersOwnGesturesAreDrawnWhole() {
        let character = TestCast.weathered
        let c = CompanionClock(character: character)
        let rainy = stage(CompanionAct(kind: .gesture(2), start: at(10)), look: .init(asleep: false, weather: .rain), sky: .rain)
        XCTAssertEqual(c.pose(at: at(10.05), stage: rainy).frame, character.index["drop"], "the drip, prop and all")
        let hot = stage(CompanionAct(kind: .gesture(0), start: at(10)), look: .init(asleep: false, weather: .heat), sky: .heat)
        XCTAssertEqual(c.restPose(at: at(5), stage: hot).frame, character.index["hot"], "the heat still")
        XCTAssertEqual(character.drawn[c.pose(at: at(10.05), stage: hot).frame],
                       CompanionCharacter.runs(of: ["....", "mmml", "mmld", "d..d"]), "a blink over the heat still")
    }

    func testTheChecksCatchBadWeather() {
        typealias C = CompanionCharacter
        let blink = C.Gesture(name: "blink", ticks: C.ticks(("blink", 2)), flicker: true)
        let cloudy = C.Gesture(name: "cloudy", ticks: C.ticks(("blink", 2)), flicker: true, sky: .clouds)
        let shake = C.Routine(name: "dry", sky: .rain, shakesOff: true, steps: [.gesture("blink"), .hold(10), .gesture("blink"),
                                                                                .hold(10), .gesture("blink"), .hold(4), .gesture("blink")])
        let awake = C.Mode(rest: "rest", snow: "snow", heat: "nowhere", snowDeep: ["sunk"], gestures: [blink, cloudy],
                           answer: blink, routines: [shake])
        let asleep = C.Mode(rest: "rest", gestures: [blink], answer: blink)
        let posture = C.Posture(awake: awake, asleep: asleep, flourish: C.ticks(("rest", 1), ("blink", 10), ("rest", 1)))
        let rows = ["mmmmmmmm", "mlllllll", "mlklkllm", "mmmmmmmm", "dddddddd"]
        let bad = C(id: "bad", name: "Bad", width: 8, height: 5, seatRow: 4,
                    frames: [.init(name: "rest", rows: rows),
                             .init(name: "blink", rows: rows.enumerated().map { $0.offset == 2 ? "mlmlmllm" : $0.element }),
                             .init(name: "snow", rows: rows.enumerated().map { $0.offset == 0 ? "llllllll" : $0.element }),
                             .init(name: "sunk", rows: rows.enumerated().map { $0.offset == 3 ? "llllllll" : $0.element })],
                    gestureFPS: 8, flourishFPS: 9, flourishTurns: false, field: posture, plus: posture)
        let problems = bad.problems.joined(separator: "\n")
        for expected in ["heat: no frame nowhere", "sunk changes the line where it sits", "no gesture belongs to a clouds sky",
                         "shakesOff on a routine that isn't the snow's", "shakesOff with no frame of its own"] {
            XCTAssertTrue(problems.contains(expected), "missing: \(expected)\n\(problems)")
        }
    }

    func testTheDebugArguments() {
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app"]), .none)
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionHour", "23"]).hour, 23)
        XCTAssertNil(CompanionLaunchOptions(arguments: ["app", "-companionHour", "25"]).hour)
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companion", "Quill"]).companion, "quill")
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionPlay", "flourish"]).play, .flourish)
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionPlay", "gestures"]).play, .gestures)
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionPlay", "blink"]).play, .gesture("blink"))
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionDemo", "all"]).play, .all, "the old name")
        XCTAssertNil(CompanionLaunchOptions(arguments: ["app", "-companionPlay", "NO"]).play)
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionPlay", "routine"]).play, .routines)
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionPlay", "routine:shakeOff"]).play,
                       .routine("shakeOff"))
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionSnowDepth", "2"]).snowDepth, 2)
        XCTAssertNil(CompanionLaunchOptions(arguments: ["app"]).snowDepth)
    }

    func testATapPlaysARoutineBetweenFlourishes() {
        func reply(_ now: TimeInterval, look: CompanionLook = .day, calm: Bool = false, lowPower: Bool = false,
                   last: TimeInterval? = 0, routine: TimeInterval? = nil, answer: TimeInterval? = nil,
                   routines: Bool = true) -> CompanionSchedule.TapReply {
            CompanionSchedule.tapReply(now: at(now), onScreen: true, look: look, acting: false, still: false, calm: calm,
                                       lowPower: lowPower, lastFlourish: last.map(at), lastAnswer: answer.map(at),
                                       lastRoutine: routine.map(at), routines: routines)
        }
        XCTAssertEqual(reply(1_200, last: 0), .flourish, "twenty minutes since the flourish: the flourish")
        XCTAssertEqual(reply(600), .routine, "sooner, and no routine yet: a routine")
        XCTAssertEqual(reply(600, routine: 421), .answer, "a routine within three minutes: the small answer")
        XCTAssertEqual(reply(600, routine: 420), .routine)
        XCTAssertEqual(reply(600, routine: 590, answer: 595), .nothing, "the answer at most every ten seconds")
        XCTAssertEqual(reply(600, routines: false), .answer, "a character with no routines answers, as before")
        XCTAssertEqual(reply(600, look: .init(asleep: true, weather: .plain)), .answer, "asleep: the stir")
        XCTAssertEqual(reply(600, look: .init(asleep: false, weather: .rain)), .routine, "rain: a routine still")
        XCTAssertEqual(reply(600, calm: true), .answer, "Reduce Effects: flickers only")
        XCTAssertEqual(reply(600, lowPower: true), .answer, "Low Power Mode: flickers only")
    }

    func testEachThemeHasItsCompanionAndTheRestHaveNod() {
        XCTAssertEqual(CompanionCast.character(forTheme: "slate", launch: .none).id, "nod")
        XCTAssertEqual(CompanionCast.character(forTheme: "midnight", launch: .none).id, "quill")
        for theme in ThemePalette.all.map(\.id) where CompanionCast.byTheme[theme] == nil {
            XCTAssertEqual(CompanionCast.character(forTheme: theme, launch: .none).id, "nod", theme)
        }
        XCTAssertEqual(CompanionCast.character(forTheme: "a theme from a newer build", launch: .none).id, "nod")
        let forced = CompanionLaunchOptions(arguments: ["-companion", "quill"])
        XCTAssertEqual(CompanionCast.character(forTheme: "slate", launch: forced).id, "quill")
        // Every theme's companion is one that is drawn, and no two themes share one.
        let ids = Array(CompanionCast.byTheme.values)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids { XCTAssertNotNil(CompanionCharacter.named(id), id) }
        for theme in CompanionCast.byTheme.keys { XCTAssertTrue(ThemePalette.all.contains { $0.id == theme }, theme) }
    }
}
