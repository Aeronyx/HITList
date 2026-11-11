import XCTest
import HITListCore
@testable import HITList

/// Brief 79: the companions' pure parts on two tiny characters of their own. The clock (a still picture at rest, an
/// act's ticks, a gesture drawn over the weather's frame, the turn that sticks), and the schedule's rules (night's
/// edges, the gaps, the flourish's budget, never the same gesture three times running, the tap's replies, the Debug
/// arguments).
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
        static let all: [CompanionCharacter] = [stayer, turner]
    }

    private func stage(_ act: CompanionAct? = nil, look: CompanionLook = .day, turned: Bool = false,
                       place: CompanionPlace = .field) -> CompanionStage {
        CompanionStage(since: t0, place: place, look: look, turned: turned, act: act)
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
        for i in 0..<500 {
            let u = CompanionRandom.unit(9, i)
            XCTAssertTrue((45...120).contains(CompanionSchedule.gap(asleep: false, unit: u)))
            XCTAssertTrue((360...900).contains(CompanionSchedule.gap(asleep: true, unit: u)), "a stir every six to fifteen minutes")
        }
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

    func testNeverTheSameGestureThreeTimesRunning() {
        var recent: [Int] = []
        var counts = [0, 0, 0]
        for i in 0..<3_000 {
            let pick = CompanionSchedule.pickGesture(weights: [5, 1, 1], recent: recent, unit: CompanionRandom.unit(4, i))
            if recent.count >= 2 { XCTAssertFalse(recent.suffix(2) == [pick, pick], "three \(pick)s running at \(i)") }
            recent.append(pick)
            counts[pick] += 1
        }
        XCTAssertGreaterThan(counts[0], counts[1] * 2, "by weight")
        XCTAssertGreaterThan(counts[2], 0)
        XCTAssertEqual(CompanionSchedule.pickGesture(weights: [3], recent: [0, 0], unit: 0.5), 0, "one gesture is all it has")
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
