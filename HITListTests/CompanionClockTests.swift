import XCTest
@testable import HITList

/// Brief 76: the companions' engine, on two tiny characters of its own: the pure clock (which frame, when it next
/// changes), the seeded schedule of flourishes and its rules, the Debug launch argument, and the director that keeps
/// them (never two at once, never in the first 20 seconds, no timer while nothing may flourish).
@MainActor
final class CompanionClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func clock(_ character: CompanionCharacter, seed: UInt64 = 7) -> CompanionClock {
        CompanionClock(character: character, seed: seed)
    }

    /// Two characters for the engine alone: one that stays facing the same way, one whose flourish turns it round.
    enum TestCast {
        private static let frames: [CompanionCharacter.Frame] = [
            .init(name: "rest", rows: ["kmml", "mlld", "d..d"]),
            .init(name: "breathe", rows: ["kmml", "mlld", "dd.."]),
            .init(name: "blink", rows: ["mmml", "mlld", "d..d"]),
            .init(name: "hop", rows: ["....", "kmml", "mlld"]),
        ]
        private static let idle: [CompanionCharacter.Loop] = [
            .init(name: "plain", weight: 4, ticks: CompanionCharacter.ticks(("rest", 4), ("breathe", 2))),
            .init(name: "blink", weight: 1, ticks: CompanionCharacter.ticks(("rest", 2), ("blink", 1), ("rest", 3))),
        ]
        static let stayer = CompanionCharacter(
            id: "stayer", width: 4, height: 3, footing: .seat(row: 2), frames: frames, idleFPS: 5, idle: idle,
            flourishFPS: 9, flourish: CompanionCharacter.ticks(("rest", 1), ("hop", 10), ("rest", 1)), flourishTurns: false)
        static let turner = CompanionCharacter(
            id: "turner", width: 4, height: 3, footing: .floor, frames: frames, idleFPS: 5, idle: idle, flourishFPS: 9,
            flourish: CompanionCharacter.ticks(("rest", 1), ("hop", 5)) + CompanionCharacter.ticks(mirrored: true, ("hop", 5), ("rest", 1)),
            flourishTurns: true)
        static let all = [stayer, turner]
    }

    func testTheTestCastIsGoodData() {
        for character in TestCast.all { XCTAssertEqual(character.problems, [], character.id) }
    }

    // MARK: - Idle

    func testTheIdleStartsOnTheRestFrameAndRunsAtItsRate() {
        for character in TestCast.all {
            let c = clock(character)
            let stage = CompanionStage(since: t0)
            XCTAssertEqual(c.pose(at: t0, stage: stage), CompanionPose(frame: character.restFrame, mirrored: false))
            // The first cycle is always the first loop; tick k shows that loop's k-th frame.
            let first = character.idle[0]
            for k in 0..<character.idleLength {
                let t = at((Double(k) + 0.5) / character.idleFPS)
                XCTAssertEqual(c.pose(at: t, stage: stage).frame, character.index[first.ticks[k].frame], "\(character.id) tick \(k)")
            }
            // Exactly on a tick's start (a time far from the reference date rounds), it is that tick.
            XCTAssertEqual(c.pose(at: at(4.0 / character.idleFPS), stage: stage).frame, character.index["breathe"])
        }
    }

    func testEveryCycleStartsOnTheRestFrame() {
        for character in TestCast.all {
            let c = clock(character)
            let stage = CompanionStage(since: t0)
            for cycle in 0..<40 {
                let t = at(Double(cycle) * character.idleCycle + 0.01)
                XCTAssertEqual(c.pose(at: t, stage: stage).frame, character.restFrame, "\(character.id) cycle \(cycle)")
            }
        }
    }

    func testTheLoopsAreSeededAndVaried() {
        let character = TestCast.stayer
        let a = clock(character, seed: 1), b = clock(character, seed: 1), other = clock(character, seed: 99)
        let picksA = (0..<80).map { a.loop(forCycle: $0, anchor: t0).name }
        XCTAssertEqual(picksA, (0..<80).map { b.loop(forCycle: $0, anchor: t0).name }, "same seed, same idle")
        XCTAssertNotEqual(picksA, (0..<80).map { other.loop(forCycle: $0, anchor: t0).name }, "another seed differs")
        XCTAssertNotEqual(picksA, (0..<80).map { a.loop(forCycle: $0, anchor: at(60)).name }, "another visit differs")
        // By weight: the plain loop about four times in five.
        let picks = (1..<5_000).map { a.loop(forCycle: $0, anchor: t0).name }
        let blinks = Double(picks.filter { $0 == "blink" }.count) / Double(picks.count)
        XCTAssertEqual(blinks, 0.2, accuracy: 0.03)
    }

    // MARK: - Flourish

    func testAFlourishPlaysItsTicksThenTheIdleRestarts() {
        for character in TestCast.all {
            let c = clock(character)
            let play = at(100)
            let stage = CompanionStage(since: t0, plays: [play])
            for (k, tick) in character.flourish.enumerated() {
                let t = play.addingTimeInterval((Double(k) + 0.5) / character.flourishFPS)
                let pose = c.pose(at: t, stage: stage)
                XCTAssertEqual(pose.frame, character.index[tick.frame], "\(character.id) tick \(k)")
                XCTAssertEqual(pose.mirrored, tick.mirrored, "\(character.id) tick \(k)")
                XCTAssertTrue(c.isFlourishing(at: t, stage: stage))
            }
            let after = c.end(of: play)
            XCTAssertFalse(c.isFlourishing(at: after, stage: stage))
            // Back on the rest frame, facing the way the flourish left it, and the idle starts over from there.
            XCTAssertEqual(c.pose(at: after, stage: stage),
                           CompanionPose(frame: character.restFrame, mirrored: character.flourishTurns))
            XCTAssertEqual(c.pose(at: after.addingTimeInterval(4.5 / character.idleFPS), stage: stage).frame,
                           character.index["breathe"])
        }
    }

    func testATurnerTurnsRoundEachTimeAndAStayerDoesNot() {
        let turner = clock(TestCast.turner), stayer = clock(TestCast.stayer)
        let stage = CompanionStage(since: t0, plays: [at(100), at(400), at(800)])
        XCTAssertTrue(turner.pose(at: at(200), stage: stage).mirrored, "after one turn")
        XCTAssertFalse(turner.pose(at: at(500), stage: stage).mirrored, "after two")
        XCTAssertTrue(turner.pose(at: at(900), stage: stage).mirrored, "after three")
        // The second flourish starts from the turned pose: mirrored until its own turn, then back.
        XCTAssertTrue(turner.pose(at: at(400.05), stage: stage).mirrored)
        XCTAssertFalse(turner.pose(at: at(400 + 10.5 / 9), stage: stage).mirrored)
        for t in [200.0, 500, 900] { XCTAssertFalse(stayer.pose(at: at(t), stage: stage).mirrored) }
        // A stage that starts turned keeps it.
        XCTAssertTrue(turner.pose(at: at(5), stage: CompanionStage(since: t0, turned: true)).mirrored)
    }

    func testReduceMotionIsTheRestFrameWhicheverWayItLastLay() {
        let c = clock(TestCast.turner)
        let stage = CompanionStage(since: t0, plays: [at(100)])
        XCTAssertEqual(c.pose(at: at(50), stage: stage, still: true), CompanionPose(frame: 0, mirrored: false))
        XCTAssertEqual(c.pose(at: at(100.5), stage: stage, still: true), CompanionPose(frame: 0, mirrored: false),
                       "mid-flourish it hasn't turned yet")
        XCTAssertEqual(c.pose(at: at(200), stage: stage, still: true), CompanionPose(frame: 0, mirrored: true))
    }

    // MARK: - When the drawing changes

    func testNextChangeSkipsHeldFrames() {
        let c = clock(TestCast.stayer)
        let stage = CompanionStage(since: t0)
        // The first loop holds the rest frame for four ticks, then breathes.
        let next = c.nextChange(after: t0, stage: stage)
        XCTAssertEqual(next.timeIntervalSince(t0), 4 / 5, accuracy: 1e-6)
        XCTAssertNotEqual(c.pose(at: next, stage: stage), c.pose(at: t0, stage: stage))
    }

    func testNextChangeNeverStallsAndStopsAtAKnownFlourish() {
        for character in TestCast.all {
            let c = clock(character)
            let play = at(30)
            let stage = CompanionStage(since: t0, plays: [play])
            var t = t0
            var changes = 0
            while t < at(60) {
                let next = c.nextChange(after: t, stage: stage)
                XCTAssertGreaterThan(next, t, "\(character.id) at \(t.timeIntervalSince(t0))")
                // A held frame may run past a loop's end, but the clock never looks further than this ahead.
                XCTAssertLessThanOrEqual(next.timeIntervalSince(t), max(character.idleCycle, character.flourishDuration) + 1 + 1e-6)
                if t < play { XCTAssertLessThanOrEqual(next, play) }
                t = next
                changes += 1
            }
            // A few changes a second at most: far fewer than a 60 Hz redraw.
            XCTAssertLessThan(changes, 60 * 6, character.id)
            XCTAssertGreaterThan(changes, 10, character.id)
        }
    }

    func testNextChangeFromATickStartIsTheNextTick() {
        // Tick starts computed by adding to a far-off date round a hair either way; the next change must still move on.
        let c = clock(TestCast.stayer)
        let play = at(10)
        let stage = CompanionStage(since: t0, plays: [play])
        var t = play
        for _ in 0..<12 {
            let next = c.nextChange(after: t, stage: stage)
            XCTAssertGreaterThan(next.timeIntervalSince(t), 0.05)
            t = next
        }
    }

    func testTheTimelineYieldsTheClocksChanges() {
        let c = clock(TestCast.turner)
        let stage = CompanionStage(since: t0)
        var entries = CompanionTimeline(clock: c, stage: stage).entries(from: t0, mode: .normal).makeIterator()
        XCTAssertEqual(entries.next(), t0)
        XCTAssertEqual(entries.next(), c.nextChange(after: t0, stage: stage))
    }

    // MARK: - The schedule

    func testFlourishesComeTwoToSixMinutesApart() {
        var gaps: [TimeInterval] = []
        for i in 0..<500 {
            let gap = CompanionSchedule.gap(seed: 42, index: i)
            XCTAssertTrue(CompanionSchedule.interval.contains(gap), "\(gap)")
            gaps.append(gap)
        }
        XCTAssertEqual(gaps, (0..<500).map { CompanionSchedule.gap(seed: 42, index: $0) }, "seeded")
        XCTAssertLessThan(gaps.min()!, 140)
        XCTAssertGreaterThan(gaps.max()!, 340)
        XCTAssertEqual(CompanionSchedule.interval, 120...360)
    }

    func testTheRulesForAFlourish() {
        let since = at(0)
        func may(_ now: TimeInterval, busy: TimeInterval? = nil, last: TimeInterval? = nil, calm: Bool = false,
                 lowPower: Bool = false, onScreen: Bool = true) -> Bool {
            CompanionSchedule.mayFlourish(now: at(now), onScreenSince: onScreen ? since : nil, busyUntil: busy.map(at),
                                          lastPlay: last.map(at), calm: calm, lowPower: lowPower)
        }
        XCTAssertFalse(may(19.9), "never in the first 20 seconds on a screen")
        XCTAssertTrue(may(20))
        XCTAssertFalse(may(100, onScreen: false), "not while its screen isn't showing")
        XCTAssertFalse(may(100, busy: 99), "never while another is playing")
        XCTAssertFalse(may(100, busy: 96), "nor just after")
        XCTAssertTrue(may(100, busy: 90))
        XCTAssertFalse(may(100, calm: true), "Reduce Motion / Reduce Effects")
        XCTAssertFalse(may(100, lowPower: true), "Low Power Mode: idle only")
        XCTAssertFalse(may(100, last: 70), "not again for a while")
        XCTAssertTrue(may(100, last: 30))
    }

    func testATapPlaysAtOnceThenNotForAWhile() {
        func may(_ now: TimeInterval, busy: TimeInterval? = nil, last: TimeInterval? = nil) -> Bool {
            CompanionSchedule.mayPlayOnTap(now: at(now), onScreen: true, busyUntil: busy.map(at), lastPlay: last.map(at),
                                           calm: false, lowPower: false)
        }
        XCTAssertTrue(may(2), "a tap doesn't wait the 20 seconds")
        XCTAssertFalse(may(10, busy: 11), "not over another flourish")
        XCTAssertFalse(may(50, last: 2), "not again within the minute")
        XCTAssertTrue(may(63, last: 2))
        XCTAssertFalse(CompanionSchedule.mayPlayOnTap(now: at(5), onScreen: true, busyUntil: nil, lastPlay: nil,
                                                      calm: true, lowPower: false))
        XCTAssertFalse(CompanionSchedule.mayPlayOnTap(now: at(5), onScreen: true, busyUntil: nil, lastPlay: nil,
                                                      calm: false, lowPower: true))
    }

    func testTheDemoLaunchArgument() {
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app"]).demo, [])
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionDemo", "nod"]).demo, ["nod"])
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionDemo", "stayer,turner"]).demo, ["stayer", "turner"])
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionDemo", "all"]).demo, Set(CompanionCharacter.all.map(\.id)))
        XCTAssertEqual(CompanionLaunchOptions(arguments: ["app", "-companionDemo", "NO"]).demo, [])
        XCTAssertEqual(CompanionSchedule.gap(seed: 1, index: 3, demo: true), CompanionLaunchOptions.demoInterval)
    }

    // MARK: - The director

    private func director(demo: [String] = []) -> CompanionDirector {
        let launch = demo.isEmpty ? CompanionLaunchOptions.none
            : CompanionLaunchOptions(arguments: ["-companionDemo", demo.joined(separator: ",")])
        return CompanionDirector(seed: 3, launch: launch, observeSystem: false, cast: TestCast.all)
    }

    func testTheDirectorKeepsWhatIsOnScreen() {
        let d = director()
        d.appear("stayer", calm: false, now: at(0))
        d.appear("stayer", calm: false, now: at(1))
        XCTAssertEqual(d.stages["stayer"]?.since, at(0))
        XCTAssertTrue(d.isWaiting)
        d.disappear("stayer", now: at(2))
        XCTAssertNotNil(d.stages["stayer"], "a second window still shows it")
        d.disappear("stayer", now: at(3))
        XCTAssertNil(d.stages["stayer"])
        XCTAssertFalse(d.isWaiting, "no timer when nothing is on screen")
    }

    func testTheDirectorWaitsForTheEarliestMoment() {
        let d = director()
        d.appear("stayer", calm: false, now: at(0))
        let moment = try? XCTUnwrap(d.nextMoment)
        XCTAssertNotNil(moment)
        if let moment { XCTAssertTrue((120...360).contains(moment.timeIntervalSince(at(0))), "\(moment.timeIntervalSince(at(0)))") }
    }

    func testNeverTwoAtOnceAndNeverInTheFirstTwentySeconds() {
        let d = director()
        d.appear("stayer", calm: false, now: at(0))
        d.appear("turner", calm: false, now: at(0))
        // Both moments (2 to 6 minutes in) have passed by 400 s: only one of them plays.
        d.fire(now: at(400))
        let playing = ["stayer", "turner"].filter { !(d.stages[$0]?.plays.isEmpty ?? true) }
        XCTAssertEqual(playing.count, 1, "never two companions at once")
        // Back in the app after a while away: 20 quiet seconds first, whatever the moment says.
        let e = director()
        e.appear("stayer", calm: false, now: at(0))
        e.setAppActive(false, now: at(500))
        XCTAssertFalse(e.isWaiting, "no timer while the app isn't active")
        e.setAppActive(true, now: at(1_000))
        e.fire(now: at(1_005))
        XCTAssertEqual(e.stages["stayer"]?.plays, [], "back in the app: 20 quiet seconds first")
    }

    func testTapsLowPowerAndCalm() {
        let d = director()
        d.appear("turner", calm: false, now: at(0))
        d.tap("turner", now: at(5))
        XCTAssertEqual(d.stages["turner"]?.plays, [at(5)])
        d.tap("turner", now: at(30))
        XCTAssertEqual(d.stages["turner"]?.plays, [at(5)], "not again for a while")
        d.setLowPower(true, now: at(40))
        XCTAssertFalse(d.isWaiting, "Low Power Mode: no timer")
        d.tap("turner", now: at(100))
        XCTAssertEqual(d.stages["turner"]?.plays, [at(5)])
        let calm = director()
        calm.appear("stayer", calm: true, now: at(0))
        XCTAssertFalse(calm.isWaiting, "Reduce Motion: no timer")
        calm.tap("stayer", now: at(5))
        calm.fire(now: at(400))
        XCTAssertEqual(calm.stages["stayer"]?.plays, [])
    }

    func testATurnerRemembersWhichWayItLay() {
        let d = director()
        d.appear("turner", calm: false, now: at(0))
        d.tap("turner", now: at(5))
        d.disappear("turner", now: at(60))
        d.appear("turner", calm: false, now: at(120))
        XCTAssertEqual(d.stages["turner"]?.turned, true, "it comes back lying the way it last lay")
    }

    func testDemosTakeTurnsAndWaitRatherThanMiss() {
        let d = director(demo: ["stayer", "turner"])
        // The turner came on screen first, so its demo (8 s in) lands in the middle of the stayer's (3 s in).
        d.appear("turner", calm: false, now: at(-4.5))
        d.appear("stayer", calm: false, now: at(0))
        d.fire(now: at(3))
        XCTAssertEqual(d.stages["stayer"]?.plays, [at(3)], "the first demo a few seconds in")
        // The turner's turn comes while the stayer still plays: it waits for the end instead of missing it.
        d.fire(now: at(3.5))
        XCTAssertEqual(d.stages["turner"]?.plays ?? [], [])
        let end = at(3).addingTimeInterval(TestCast.stayer.flourishDuration)
        d.fire(now: end.addingTimeInterval(0.6))
        XCTAssertEqual(d.stages["turner"]?.plays.count, 1, "then it plays")
    }
}
