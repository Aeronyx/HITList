import XCTest
import HITListCore
@testable import HITList

/// Briefs 79, 84 and 100: the director that keeps the companions, driven by a simulated clock. Never a dead minute (an
/// idle every 6 to 36 seconds, awake or asleep, the first 2 to 6 seconds after it comes on screen, never the same one
/// twice running, a little loop about one in three) and nothing between, a routine every 3 to 8 minutes of showing
/// time (kept across launches, never the same twice running, never a little loop, the sky's own about every other
/// one), the rare flourish over a simulated month, its kept time across a relaunch, the tap's rules, night's edges where
/// the person is (decided while nobody is looking), weather, a theme change, no timer unless something is due within
/// the hour, and the eight-hour day the report shows.
@MainActor
final class CompanionDirectorTests: XCTestCase {
    private typealias Cast = CompanionClockTests.TestCast

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-11-11 (a Wednesday) plus `day` days, at `hour`:`minute` UTC.
    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11 + day, hour: hour, minute: minute, second: second))!
    }

    private func freshDefaults() -> UserDefaults {
        let name = "CompanionDirectorTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func director(seed: UInt64 = 3, defaults: UserDefaults? = nil, launch: CompanionLaunchOptions = .none,
                          sky: CompanionSky = .clear, cast: [CompanionCharacter] = Cast.all,
                          zone: TimeZone = TimeZone(identifier: "UTC")!) -> CompanionDirector {
        CompanionDirector(seed: seed, launch: launch, observeSystem: false, cast: cast,
                          defaults: defaults ?? freshDefaults(), zone: { zone }, sky: { sky })
    }

    /// Fires the director at each moment it waits for, until `end`; the acts that started, in order.
    @discardableResult
    private func run(_ d: CompanionDirector, _ id: String = "stayer", until end: Date) -> [CompanionAct] {
        var acts: [CompanionAct] = []
        var steps = 0
        while let next = d.nextMoment, next < end, steps < 200_000 {
            steps += 1
            d.fire(now: next)
            if let act = d.stages[id]?.act, act.start == next, acts.last != act { acts.append(act) }
        }
        return acts
    }

    // MARK: - Mostly still

    func testNothingRunsUnlessACompanionThatMayMoveIsOnScreen() {
        let d = director()
        XCTAssertFalse(d.isWaiting, "nothing on screen, no timer")
        d.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        XCTAssertTrue(d.isWaiting)
        let wait = d.nextMoment!.timeIntervalSince(time(12))
        XCTAssertTrue((2...6).contains(wait), "the first idle comes 2 to 6 seconds in, not at once: \(wait)")
        d.setAppActive(false, now: time(12, 1))
        XCTAssertFalse(d.isWaiting, "the app isn't in front: nothing runs")
        d.setAppActive(true, now: time(12, 2))
        XCTAssertTrue(d.isWaiting)
        d.disappear("stayer", now: time(12, 3))
        XCTAssertFalse(d.isWaiting, "off screen: nothing runs")
        XCTAssertTrue(d.stages.isEmpty)

        let still = director()
        still.appear("stayer", place: .field, still: true, calm: false, now: time(12))
        XCTAssertFalse(still.isWaiting, "Reduce Motion: nothing scheduled within the hour, no timer")
        still.tap("stayer", now: time(12, 0, second: 5))
        XCTAssertNil(still.stages["stayer"]?.act, "and a tap moves nothing")
    }

    func testAnIdleEveryFewSecondsAndNothingBetween() {
        let d = director()
        d.appear("stayer", place: .field, still: false, calm: false, now: time(9))
        let acts = run(d, until: time(13))
        let gestures = acts.filter { if case .gesture = $0.kind { return true } else { return false } }
        // Four hours: no fewer than one every 37 seconds, no more than one every 6.
        XCTAssertGreaterThan(gestures.count, 4 * 3600 / 37)
        XCTAssertLessThan(gestures.count, 4 * 3600 / 6)
        let clock = CompanionClock(character: Cast.stayer)
        for (a, b) in zip(acts, acts.dropFirst()) {
            let stage = CompanionStage(since: time(9), place: .field, look: .day, act: a)
            let end = clock.end(of: a, stage: stage)
            XCTAssertLessThan(end.timeIntervalSince(a.start), 2.7, "every act is short")
            if case .gesture = a.kind { XCTAssertLessThan(end.timeIntervalSince(a.start), 1, "a gesture is under a second") }
            if case .gesture = a.kind, case .gesture = b.kind {
                let still = b.start.timeIntervalSince(end)
                XCTAssertTrue((6 - 0.01...36 + 0.01).contains(still), "6 to 36 seconds still between idles: \(still)")
                XCTAssertNotEqual(a.kind, b.kind, "never the same idle twice running")
            }
            // Between acts it is a still picture: nothing to redraw.
            XCTAssertNil(clock.nextChange(after: end, stage: stage))
        }
        XCTAssertEqual(Set(gestures.map { "\($0.kind)" }).count, 3, "all three gestures come up")
    }

    func testAnActIsPutAwayWhenItEndsSoTheStillPictureIsDrawn() {
        let d = director()
        d.appear("turner", place: .field, still: false, calm: false, now: time(12))
        d.tap("turner", now: time(12, 0, second: 5))
        let clock = CompanionClock(character: Cast.turner)
        let stage = d.stages["turner"]!
        let end = clock.end(of: stage.act!, stage: stage)
        XCTAssertEqual(d.nextMoment, end, "the timer wakes when the act ends")
        d.fire(now: end)
        XCTAssertNil(d.stages["turner"]?.act, "put away")
        XCTAssertEqual(d.stages["turner"]?.turned, true, "its turn kept")
        XCTAssertTrue(d.isWaiting, "and the next gesture still waited for")
        XCTAssertGreaterThan(d.nextMoment!, end)
    }

    // MARK: - The flourish

    /// Someone who lives in the app (twelve hours a day, a month) sees one about every three hours of use, never two
    /// within 45 minutes; someone who uses it an hour a day sees it about twice a week.
    func testTheFlourishOverASimulatedMonth() {
        func month(sessions: [(start: Int, minutes: Int)], days: Int, seed: UInt64) -> (flourishes: [Date], shown: TimeInterval) {
            let d = director(seed: seed)
            var flourishes: [Date] = []
            var shown: TimeInterval = 0
            d.appear("stayer", place: .field, still: false, calm: false, now: time(sessions[0].start, day: 0))
            d.setAppActive(false, now: time(sessions[0].start, day: 0))
            for day in 0..<days {
                for session in sessions {
                    let start = time(session.start, day: day)
                    let length: TimeInterval = TimeInterval(session.minutes) * 60
                    let end = start.addingTimeInterval(length)
                    d.setAppActive(true, now: start)
                    for act in run(d, until: end) where act.kind == .flourish { flourishes.append(act.start) }
                    d.setAppActive(false, now: end)
                    shown += end.timeIntervalSince(start)
                }
            }
            return (flourishes, shown)
        }
        // Twelve hours a day, in three sittings.
        var perHour: [Double] = []
        for seed in [1, 2, 3] as [UInt64] {
            let heavy = month(sessions: [(8, 240), (13, 240), (18, 240)], days: 30, seed: seed)
            for (a, b) in zip(heavy.flourishes, heavy.flourishes.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 45 * 60, "never within 45 minutes of the last")
            }
            let hours: Double = heavy.shown / 3600
            perHour.append(hours / Double(heavy.flourishes.count))
        }
        var sumGaps: Double = 0
        for gap in perHour { sumGaps += gap }
        let meanGap: Double = sumGaps / Double(perHour.count)
        XCTAssertEqual(meanGap, 3, accuracy: 0.5, "about once in three hours of the screen showing: \(perHour)")
        // An hour a day, in three twenty-minute visits, over twelve weeks.
        var perWeek: [Double] = []
        for seed in [4, 5, 6] as [UInt64] {
            let light = month(sessions: [(9, 20), (13, 20), (20, 20)], days: 84, seed: seed)
            let count: Double = Double(light.flourishes.count)
            perWeek.append(count / 12)
        }
        var sumWeeks: Double = 0
        for week in perWeek { sumWeeks += week }
        let weekly: Double = sumWeeks / Double(perWeek.count)
        print("Companion month: \(perHour) hours of showing per flourish at twelve hours a day; \(perWeek) a week at an hour a day")
        XCTAssertEqual(weekly, 2.3, accuracy: 0.8, "perhaps twice a week: \(perWeek)")
    }

    func testTheKeptTimeSurvivesARelaunch() {
        let kept = freshDefaults()
        let first = director(seed: 1, defaults: kept)
        first.appear("stayer", place: .field, still: false, calm: false, now: time(10))
        first.tap("stayer", now: time(10, 0, second: 30))
        XCTAssertEqual(first.stages["stayer"]?.act?.kind, .flourish, "the first tap on this device plays it")
        first.disappear("stayer", now: time(10, 5))
        let budget = first.budget
        XCTAssertEqual(kept.double(forKey: Preferences.companionLastFlourish), time(10, 0, second: 30).timeIntervalSinceReferenceDate)

        // Quit and reopen: the same moment and the same budget come back, so nothing comes sooner.
        let second = director(seed: 99, defaults: kept)
        XCTAssertEqual(second.lastFlourish, time(10, 0, second: 30))
        XCTAssertEqual(second.budget, budget, accuracy: 0.001)
        second.appear("stayer", place: .field, still: false, calm: false, now: time(10, 6))
        second.tap("stayer", now: time(10, 15))
        XCTAssertEqual(second.stages["stayer"]?.act?.kind, .answer, "within 20 minutes a tap gets a reply only")
        let acts = run(second, until: time(10, 45))
        XCTAssertFalse(acts.contains { $0.kind == .flourish }, "never within 45 minutes of the last, relaunch or not")
        // The budget is spent only while it shows: an hour away costs it nothing.
        second.setAppActive(false, now: time(10, 45))
        let left = second.budget
        second.setAppActive(true, now: time(11, 45))
        second.setAppActive(false, now: time(11, 45))
        XCTAssertEqual(second.budget, left, accuracy: 0.001)
    }

    func testATapPlaysItRarelyAndRepliesOtherwise() {
        let d = director()
        d.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        d.tap("stayer", now: time(12, 0, second: 2))
        XCTAssertEqual(d.stages["stayer"]?.act, CompanionAct(kind: .flourish, start: time(12, 0, second: 2)))
        d.tap("stayer", now: time(12, 0, second: 3))
        XCTAssertEqual(d.stages["stayer"]?.act?.start, time(12, 0, second: 2), "nothing over the flourish")
        d.tap("stayer", now: time(12, 0, second: 30))
        XCTAssertEqual(d.stages["stayer"]?.act, CompanionAct(kind: .answer, start: time(12, 0, second: 30)), "a reply")
        d.tap("stayer", now: time(12, 0, second: 35))
        XCTAssertEqual(d.stages["stayer"]?.act?.start, time(12, 0, second: 30), "at most one reply in ten seconds")
        d.tap("stayer", now: time(12, 0, second: 41))
        XCTAssertEqual(d.stages["stayer"]?.act?.start, time(12, 0, second: 41))
        d.tap("stayer", now: time(12, 20, second: 3))
        XCTAssertEqual(d.stages["stayer"]?.act?.kind, .flourish, "twenty minutes on, a tap may play it again")
    }

    func testReduceEffectsLowPowerAndWeatherKeepTheGesturesAndDropTheFlourish() {
        let calm = director()
        calm.appear("stayer", place: .field, still: false, calm: true, now: time(12))
        calm.tap("stayer", now: time(12, 0, second: 5))
        XCTAssertEqual(calm.stages["stayer"]?.act?.kind, .answer)
        XCTAssertTrue(run(calm, until: time(20)).allSatisfy { $0.kind != .flourish }, "Reduce Effects: no flourish")
        XCTAssertGreaterThan(run(calm, until: time(21)).count, 20, "but the gestures go on")

        let low = director()
        low.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        low.setLowPower(true, now: time(12))
        XCTAssertTrue(low.isWaiting, "Low Power Mode keeps the gestures")
        XCTAssertTrue(run(low, until: time(20)).allSatisfy { $0.kind != .flourish })

        let rainy = director(sky: .rain)
        rainy.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        XCTAssertEqual(rainy.stages["stayer"]?.look, CompanionLook(asleep: false, weather: .rain))
        let budget = rainy.budget
        XCTAssertTrue(run(rainy, until: time(20)).allSatisfy { $0.kind != .flourish }, "sheltering: no flourish in the rain")
        rainy.setAppActive(false, now: time(20))
        XCTAssertEqual(rainy.budget, budget, accuracy: 0.001, "and none of its budget spent")
        XCTAssertEqual(director(sky: .storm).look(at: time(12)).weather, .rain)
        XCTAssertEqual(director(sky: .snow).look(at: time(12)).weather, .snow)
        XCTAssertEqual(director(sky: .unknown).look(at: time(12)), .day)
    }

    // MARK: - Night

    func testNightsEdgesAndNobodyLooking() {
        XCTAssertFalse(director().look(at: time(21, 59)).asleep)
        XCTAssertTrue(director().look(at: time(22, 0)).asleep)
        XCTAssertTrue(director().look(at: time(6, 59)).asleep)
        XCTAssertFalse(director().look(at: time(7, 0)).asleep)

        // On screen across ten o'clock: still awake until the app is left, then asleep, with no act playing.
        let d = director()
        d.appear("stayer", place: .field, still: false, calm: false, now: time(21, 50))
        run(d, until: time(22, 10))
        XCTAssertFalse(d.stages["stayer"]!.look.asleep, "nobody looked away yet")
        d.setAppActive(false, now: time(22, 10))
        XCTAssertEqual(d.stages["stayer"]?.look, CompanionLook(asleep: true, weather: .plain))
        XCTAssertNil(d.stages["stayer"]?.act)
        d.setAppActive(true, now: time(22, 30))
        // Asleep: it breathes at the same pace (its stir every 6 to 36 seconds), never a flourish, budget untouched.
        let budget = d.budget
        let night = run(d, until: time(6, 59, day: 1))
        XCTAssertFalse(night.contains { $0.kind == .flourish }, "no flourish while asleep")
        XCTAssertEqual(night.first.map { $0.start.timeIntervalSince(time(22, 30)) } ?? 99, 4, accuracy: 2.01,
                       "the first 2 to 6 seconds after coming back")
        for (a, b) in zip(night, night.dropFirst()) {
            XCTAssertTrue((6...37).contains(b.start.timeIntervalSince(a.start)), "a stir every few seconds")
        }
        XCTAssertGreaterThan(night.count, 8 * 3600 / 37)
        d.setAppActive(false, now: time(6, 59, day: 1))
        XCTAssertEqual(d.budget, budget, accuracy: 0.001)
        // Back at seven: awake.
        d.setAppActive(true, now: time(7, 0, day: 1))
        XCTAssertFalse(d.stages["stayer"]!.look.asleep)
        // A tap at night wakes it for a moment.
        let n = director()
        n.appear("stayer", place: .field, still: false, calm: false, now: time(23))
        n.tap("stayer", now: time(23, 0, second: 5))
        XCTAssertEqual(n.stages["stayer"]?.act?.kind, .answer)
        // `-companionHour 23` holds the night at noon.
        let forced = director(launch: CompanionLaunchOptions(arguments: ["-companionHour", "23"]))
        XCTAssertTrue(forced.look(at: time(12)).asleep)
    }

    // MARK: - One at a time

    func testAThemeChangeIsTheOtherCompanionAtOnce() {
        let d = director()
        d.appear("stayer", place: .plus, still: false, calm: false, now: time(12))
        // The theme changes: the perch's companion leaves and the theme's arrives, in the same place.
        d.disappear("stayer", now: time(12, 5))
        d.appear("turner", place: .plus, still: false, calm: false, now: time(12, 5))
        XCTAssertEqual(Array(d.stages.keys), ["turner"])
        XCTAssertEqual(d.stages["turner"]?.place, .plus)
        XCTAssertTrue(d.isWaiting)
    }

    func testATurnerRemembersWhichWayItLay() {
        let d = director()
        d.appear("turner", place: .field, still: false, calm: false, now: time(12))
        d.tap("turner", now: time(12, 0, second: 5))
        d.disappear("turner", now: time(12, 1))
        d.appear("turner", place: .field, still: false, calm: false, now: time(12, 2))
        XCTAssertEqual(d.stages["turner"]?.turned, true, "it comes back lying the way it last lay")
        // And a look change while nobody is looking keeps the turn.
        d.setAppActive(false, now: time(22, 30))
        XCTAssertEqual(d.stages["turner"]?.turned, true)
    }

    func testTheDemoPlaysOnCueAndKeepsNothing() {
        let kept = freshDefaults()
        let d = director(defaults: kept, launch: CompanionLaunchOptions(arguments: ["-companionPlay", "flourish"]))
        d.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        let acts = run(d, until: time(12, 1))
        XCTAssertEqual(acts.first?.start, time(12, 0, second: 3))
        XCTAssertGreaterThanOrEqual(acts.filter { $0.kind == .flourish }.count, 4)
        XCTAssertNil(kept.object(forKey: Preferences.companionLastFlourish), "a demo keeps nothing on the device")
        let all = director(launch: CompanionLaunchOptions(arguments: ["-companionPlay", "all"]))
        all.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        let kinds = run(all, until: time(12, 0, second: 30)).map(\.kind)
        XCTAssertEqual(Array(kinds.prefix(5)), [.gesture(0), .gesture(1), .gesture(2), .answer, .flourish])
    }

    // MARK: - Routines (brief 84)

    private func routines(_ acts: [CompanionAct]) -> [CompanionAct] {
        acts.filter { if case .routine = $0.kind { return true } else { return false } }
    }

    private func routineName(_ act: CompanionAct, _ character: CompanionCharacter = Cast.dancer,
                             place: CompanionPlace = .field) -> String {
        guard case .routine(let i) = act.kind else { return "" }
        return character.posture(place).awake.routines[i].name
    }

    /// Twelve hours a day for a month: a routine every 3 to 8 minutes of showing time (5.5 on average), never the
    /// same one twice running, never in a sitting's first 20 seconds, every everyday routine in turn; still between.
    func testRoutinesOverASimulatedMonth() {
        let d = director(seed: 11, sky: .clouds)
        var all: [CompanionAct] = []
        var shown: TimeInterval = 0
        var sittingStarts: [Date] = []
        d.appear("dancer", place: .field, still: false, calm: false, now: time(8))
        d.setAppActive(false, now: time(8))
        for day in 0..<30 {
            for (hour, minutes) in [(8, 240), (13, 240), (18, 240)] {
                let start = time(hour, day: day)
                let end = start.addingTimeInterval(TimeInterval(minutes) * 60)
                d.setAppActive(true, now: start)
                sittingStarts.append(start)
                let acts = run(d, "dancer", until: end)
                all.append(contentsOf: acts)
                // Within a sitting, one routine to the next is three to eight minutes; a flourish between takes a
                // routine's place, and the next comes three to eight minutes after it.
                let big = acts.filter { $0.kind == .flourish || routines([$0]).count == 1 }
                for (a, b) in zip(big, big.dropFirst()) where routines([b]).count == 1 {
                    let gap = b.start.timeIntervalSince(a.start)
                    XCTAssertGreaterThanOrEqual(gap, 180 - 1, "three minutes at least")
                    XCTAssertLessThanOrEqual(gap, 480 + 3, "eight minutes at most")
                }
                let played = routines(acts)
                for act in played {
                    XCTAssertGreaterThanOrEqual(act.start.timeIntervalSince(start), 20, "never in the first 20 seconds")
                }
                d.setAppActive(false, now: end)
                shown += end.timeIntervalSince(start)
            }
        }
        let played = routines(all)
        let names = played.map { routineName($0) }
        for (a, b) in zip(names, names.dropFirst()) { XCTAssertNotEqual(a, b, "the same routine twice running") }
        XCTAssertEqual(Set(names), ["shuffle", "stretch", "feet"], "every everyday routine, none of a sky's under clouds")
        let perRoutine: Double = shown / Double(played.count)
        print("Companion routines: one every \(Int(perRoutine)) s of showing over a month (\(played.count) in \(Int(shown / 3600)) h)")
        XCTAssertEqual(perRoutine, 330, accuracy: 45, "about one every five and a half minutes of showing")
        // Between acts it is a still picture, and a routine is a few seconds.
        let clock = CompanionClock(character: Cast.dancer)
        for act in played {
            let stage = CompanionStage(since: time(8), place: .field, look: .day, act: act)
            let length = clock.end(of: act, stage: stage).timeIntervalSince(act.start)
            XCTAssertTrue((3...7).contains(length), "three to seven seconds: \(length)")
        }
        // Flickers go on between, one every 6 to 36 seconds, and only the marked ones.
        let flickers = all.filter { if case .gesture = $0.kind { return true } else { return false } }
        XCTAssertGreaterThan(flickers.count, played.count * 8)
        XCTAssertFalse(flickers.contains { $0.kind == .gesture(2) }, "both plays only inside routines")
    }

    /// Opening the app for a minute, twenty times (a relaunch each time, an hour apart): the kept budget means no more
    /// routines than twenty minutes in one go would bring.
    func testTwentyOneMinuteVisits() {
        let kept = freshDefaults()
        var played: [CompanionAct] = []
        for visit in 0..<20 {
            let d = director(seed: UInt64(100 + visit), defaults: kept, sky: .clouds)
            let start = time(9, day: 0).addingTimeInterval(TimeInterval(visit) * 3600)
            d.appear("dancer", place: .field, still: false, calm: false, now: start)
            played.append(contentsOf: routines(run(d, "dancer", until: start.addingTimeInterval(60))))
            d.disappear("dancer", now: start.addingTimeInterval(60))
            d.setAppActive(false, now: start.addingTimeInterval(60))
        }
        print("Companion visits: \(played.count) routines in twenty one-minute visits")
        XCTAssertLessThanOrEqual(played.count, 6, "twenty minutes of showing: six at most")
        XCTAssertGreaterThanOrEqual(played.count, 1, "and the budget does run out")
        // Without the kept budget it would be up to one a visit: each launch would draw a fresh one, but the kept one
        // carries what is left, so the next launch spends it.
        XCTAssertNotNil(kept.object(forKey: Preferences.companionRoutineBudget))
    }

    /// While a sky holds, its own routine takes about every other slot; the everyday ones that can't be drawn under
    /// its prop sit out; storm takes the rain's and its own; clouds have none.
    func testTheSkysOwnRoutineAboutEveryOther() {
        func names(_ sky: CompanionSky, seed: UInt64 = 5) -> [String] {
            let d = director(seed: seed, sky: sky)
            d.appear("dancer", place: .field, still: false, calm: false, now: time(8))
            return routines(run(d, "dancer", until: time(20))).map { routineName($0) }
        }
        let rain = names(.rain)
        let drips = rain.filter { $0 == "drip" }.count
        XCTAssertEqual(Double(drips) / Double(rain.count), 0.45, accuracy: 0.15, "about every other: \(rain)")
        XCTAssertFalse(rain.contains("stretch"), "it draws where the prop is: not in the rain")
        XCTAssertFalse(rain.contains("flake") || rain.contains("bask") || rain.contains("jolt"))
        let storm = names(.storm)
        XCTAssertTrue(storm.contains("jolt") && storm.contains("drip"), "storm: the rain's and its own")
        let snow = names(.snow)
        XCTAssertEqual(Double(snow.filter { $0 == "flake" }.count) / Double(snow.count), 0.45, accuracy: 0.15)
        XCTAssertFalse(snow.contains("stretch") || snow.contains("drip"))
        let clear = names(.clear)
        XCTAssertTrue(clear.contains("bask") && clear.contains("stretch"))
        let clouds = names(.clouds)
        XCTAssertEqual(Set(clouds), ["shuffle", "stretch", "feet"])
        XCTAssertEqual(Set(names(.unknown)), ["shuffle", "stretch", "feet"])
        for list in [rain, storm, snow, clear, clouds] {
            for (a, b) in zip(list, list.dropFirst()) { XCTAssertNotEqual(a, b) }
        }
    }

    /// Reduce Motion: nothing. Reduce Effects and Low Power Mode: idles only (no routine, no flourish, and the
    /// routine's budget untouched). Asleep: a stir every few seconds, no routine.
    func testQuietWhenAskedAndAsleep() {
        let still = director()
        still.appear("dancer", place: .field, still: true, calm: false, now: time(12))
        XCTAssertFalse(still.isWaiting)
        still.tap("dancer", now: time(12, 0, second: 30))
        XCTAssertNil(still.stages["dancer"]?.act)

        for lowPower in [false, true] {
            let d = director(sky: .rain)
            d.appear("dancer", place: .field, still: false, calm: !lowPower, now: time(12))
            if lowPower { d.setLowPower(true, now: time(12)) }
            let budget = d.routineBudget
            let acts = run(d, "dancer", until: time(16))
            XCTAssertTrue(routines(acts).isEmpty, lowPower ? "Low Power Mode" : "Reduce Effects")
            XCTAssertFalse(acts.contains { $0.kind == .flourish })
            XCTAssertGreaterThan(acts.count, 100, "the flickers go on")
            d.setAppActive(false, now: time(16))
            XCTAssertEqual(d.routineBudget, budget, accuracy: 0.001, "no showing time spent on a routine it can't play")
            d.setAppActive(true, now: time(16, 1))
            d.tap("dancer", now: time(16, 2))
            XCTAssertEqual(d.stages["dancer"]?.act?.kind, .answer, "a tap: the small answer")
        }

        let night = director()
        night.appear("dancer", place: .field, still: false, calm: false, now: time(23))
        let acts = run(night, "dancer", until: time(6, 59, day: 1))
        XCTAssertTrue(routines(acts).isEmpty, "no routines asleep")
        XCTAssertGreaterThan(acts.count, 20, "a stir now and then")
        night.tap("dancer", now: time(3, day: 1))
        XCTAssertEqual(night.stages["dancer"]?.act?.kind, .answer, "a tap at night: the stir")
    }

    func testATapPlaysARoutineBetweenFlourishes() {
        let d = director(sky: .clouds)
        d.appear("dancer", place: .field, still: false, calm: false, now: time(12))
        d.tap("dancer", now: time(12, 0, second: 30))
        XCTAssertEqual(d.stages["dancer"]?.act?.kind, .flourish, "the first tap: the flourish")
        d.tap("dancer", now: time(12, 1))
        guard case .routine(let first)? = d.stages["dancer"]?.act?.kind else { return XCTFail("then a routine") }
        XCTAssertEqual(d.lastRoutine, time(12, 1))
        XCTAssertEqual(d.nextMoment, CompanionClock(character: Cast.dancer).end(of: d.stages["dancer"]!.act!, stage: d.stages["dancer"]!),
                       "the timer wakes to put it away")
        d.fire(now: time(12, 1, second: 10))
        d.tap("dancer", now: time(12, 1, second: 20))
        XCTAssertEqual(d.stages["dancer"]?.act?.kind, .answer, "within three minutes: the small answer")
        d.fire(now: time(12, 1, second: 25))
        XCTAssertNotEqual(d.stages["dancer"]?.act?.kind, .answer, "and the answer put away when it ends")
        d.tap("dancer", now: time(12, 4, second: 1))
        guard case .routine(let second)? = d.stages["dancer"]?.act?.kind else { return XCTFail("three minutes on, a routine") }
        XCTAssertNotEqual(first, second, "never the same one twice running")
        // A character with no routines answers, as before brief 84.
        let plain = director()
        plain.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        plain.tap("stayer", now: time(12, 0, second: 30))
        plain.tap("stayer", now: time(12, 1))
        XCTAssertEqual(plain.stages["stayer"]?.act?.kind, .answer)
    }

    func testARoutinesKeptClockSurvivesARelaunch() {
        let kept = freshDefaults()
        let first = director(seed: 1, defaults: kept, sky: .clouds)
        first.appear("dancer", place: .field, still: false, calm: false, now: time(10))
        let acts = routines(run(first, "dancer", until: time(10, 30)))
        XCTAssertFalse(acts.isEmpty)
        first.disappear("dancer", now: time(10, 30))
        let left = first.routineBudget
        let last = first.lastRoutineName
        XCTAssertEqual(last, "dancer.\(routineName(acts.last!))")
        let second = director(seed: 2, defaults: kept, sky: .clouds)
        XCTAssertEqual(second.routineBudget, left, accuracy: 0.001)
        XCTAssertEqual(second.lastRoutine, acts.last!.start)
        XCTAssertEqual(second.lastRoutineName, last)
        second.appear("dancer", place: .field, still: false, calm: false, now: time(11))
        let next = routines(run(second, "dancer", until: time(11, 30)))
        XCTAssertNotEqual(next.first.map { routineName($0) }, routineName(acts.last!), "not the same one again after a relaunch")
        let wait = next.first!.start.timeIntervalSince(time(11))
        XCTAssertEqual(wait, max(20, left), accuracy: 1, "what was left of the stretch, no sooner")
    }

    /// Night and day where the person is (`CompanionSkySource.zone`): 21:00 in Tokyo is awake, 22:00 asleep.
    func testTheHoursOfWhereThePersonIs() {
        let tokyo = director(zone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertFalse(tokyo.look(at: time(12)).asleep, "12:00 UTC is 21:00 in Tokyo")
        XCTAssertTrue(tokyo.look(at: time(13)).asleep, "13:00 UTC is 22:00")
        XCTAssertTrue(tokyo.look(at: time(21, 59)).asleep, "06:59 the next morning")
        XCTAssertFalse(tokyo.look(at: time(22)).asleep, "07:00")
        let newYork = director(zone: TimeZone(identifier: "America/New_York")!)
        XCTAssertFalse(newYork.look(at: time(2, 59, day: 1)).asleep, "21:59 the evening before")
        XCTAssertTrue(newYork.look(at: time(3, day: 1)).asleep, "22:00")
        // The source's zone is the device's until weather knows better.
        XCTAssertEqual(CompanionSkySource(arguments: UserDefaults(suiteName: "CompanionDirectorTests.zone")!).zone, .current)
    }

    func testTheRoutineDemo() {
        let kept = freshDefaults()
        let d = director(defaults: kept, launch: CompanionLaunchOptions(arguments: ["-companionPlay", "routine"]), sky: .clouds)
        d.appear("dancer", place: .field, still: false, calm: false, now: time(12))
        let names = routines(run(d, "dancer", until: time(12, 1))).map { routineName($0) }
        XCTAssertEqual(Array(names.prefix(4)), ["shuffle", "stretch", "feet", "shuffle"], "each in turn")
        XCTAssertNil(kept.object(forKey: Preferences.companionLastRoutine), "a demo keeps nothing")
        let one = director(launch: CompanionLaunchOptions(arguments: ["-companionPlay", "routine:drip"]), sky: .rain)
        one.appear("dancer", place: .field, still: false, calm: false, now: time(12))
        let drips = routines(run(one, "dancer", until: time(12, 1))).map { routineName($0) }
        XCTAssertGreaterThanOrEqual(drips.count, 5)
        XCTAssertEqual(Set(drips), ["drip"])
        let all = director(launch: CompanionLaunchOptions(arguments: ["-companionPlay", "all"]), sky: .rain)
        all.appear("dancer", place: .field, still: false, calm: false, now: time(12))
        let kinds = run(all, "dancer", until: time(12, 1)).map(\.kind)
        XCTAssertEqual(Array(kinds.prefix(7)), [.gesture(0), .gesture(1), .gesture(2), .routine(0), .routine(2), .routine(3), .answer],
                       "the gestures, the routines it may play in the rain, the reply")
    }

    // MARK: - The weather on the creature (brief 91)

    /// Fires until the snow has piled at least a frame deep on the weathered one; when.
    private func untilItPiles(_ d: CompanionDirector) -> Date {
        var steps = 0
        while let next = d.nextMoment, steps < 5_000 {
            steps += 1
            d.fire(now: next)
            if d.stages["weathered"]!.snowDepth > 0 { return next }
        }
        XCTFail("it never piled")
        return .distantFuture
    }

    /// An hour or two in the snow: the pile grows one frame every 8 to 14 minutes of showing time and stops at its
    /// last; a shake-off (only from the deepest) leaves it bare and it starts again. It keeps across a change of screen
    /// (the "+" goes away while a card is open), and starts again when the sky leaves snow, at night and at a new launch.
    func testASnowyHour() {
        let d = director(seed: 7, sky: .snow)
        d.appear("weathered", place: .field, still: false, calm: false, now: time(9))
        XCTAssertEqual(d.stages["weathered"]?.snowDepth, 0)
        var t = time(9)
        var depths: [(Date, Int)] = [(t, 0)]
        var shakes: [CompanionAct] = []
        var steps = 0
        while let next = d.nextMoment, next < time(13), steps < 20_000 {
            steps += 1
            d.fire(now: next)
            t = next
            let stage = d.stages["weathered"]!
            if let act = stage.act, act.start == next, case .routine(let i) = act.kind,
               Cast.weathered.field.awake.routines[i].shakesOff { shakes.append(act) }
            if depths.last!.1 != stage.snowDepth { depths.append((next, stage.snowDepth)) }
            if case .gesture(0)? = stage.act?.kind, stage.act?.start == next {
                XCTAssertLessThan(stage.snowDepth, 2, "no blink through the snow on its eye")
            }
        }
        XCTAssertFalse(shakes.isEmpty, "it shakes the snow off")
        for (a, b) in zip(depths, depths.dropFirst()) {
            if b.1 == a.1 + 1 {
                let gap = b.0.timeIntervalSince(a.0)
                XCTAssertTrue((480 - 1...840 + 8).contains(gap), "one frame deeper after 8 to 14 minutes: \(gap)")
            } else {
                XCTAssertEqual(b.1, 0, "only a shake-off makes it shallower")
                XCTAssertEqual(a.1, 2, "and only from the deepest pile")
            }
        }
        XCTAssertTrue(depths.contains { $0.1 == 2 }, "it piles to its last frame")
        print("Companion snow: \(depths.map { "\($0.1)" }.joined(separator: " → ")) with \(shakes.count) shake-offs in four hours")

        // The "+" goes and comes back (a card opened): the pile stays.
        let kept = director(seed: 8, launch: CompanionLaunchOptions(arguments: ["-companionSnowDepth", "2"]), sky: .snow)
        kept.appear("weathered", place: .plus, still: false, calm: false, now: time(9))
        XCTAssertEqual(kept.stages["weathered"]?.snowDepth, 2, "-companionSnowDepth 2")
        let grown = director(seed: 8, sky: .snow)
        grown.appear("weathered", place: .plus, still: false, calm: false, now: time(9))
        let piled = untilItPiles(grown)
        let depth = grown.stages["weathered"]!.snowDepth
        XCTAssertGreaterThan(depth, 0)
        grown.disappear("weathered", now: piled)
        grown.appear("weathered", place: .plus, still: false, calm: false, now: piled.addingTimeInterval(60))
        XCTAssertEqual(grown.stages["weathered"]?.snowDepth, depth, "kept across a change of screen")
        // Night falls while nobody looks: the pile starts again.
        grown.setAppActive(false, now: time(22, 30))
        XCTAssertEqual(grown.stages["weathered"]?.snowDepth, 0)
        // A new launch starts bare.
        let relaunched = director(seed: 9, sky: .snow)
        relaunched.appear("weathered", place: .plus, still: false, calm: false, now: time(9, 40))
        XCTAssertEqual(relaunched.stages["weathered"]?.snowDepth, 0)
        // Reduce Motion: the pile doesn't grow (nothing changes by itself).
        let still = director(sky: .snow)
        still.appear("weathered", place: .plus, still: true, calm: false, now: time(9))
        XCTAssertFalse(still.isWaiting)
    }

    func testTheSkyLeavingSnowStartsThePileAgain() {
        var sky = CompanionSky.snow
        let d = CompanionDirector(seed: 4, launch: .none, observeSystem: false, cast: Cast.all, defaults: freshDefaults(),
                                  zone: { TimeZone(identifier: "UTC")! }, sky: { sky })
        d.appear("weathered", place: .field, still: false, calm: false, now: time(9))
        let piled = untilItPiles(d)
        XCTAssertGreaterThan(d.stages["weathered"]!.snowDepth, 0)
        XCTAssertLessThan(piled, time(10))
        d.setAppActive(false, now: time(10))
        sky = .clouds
        d.setAppActive(true, now: time(10, 5))
        XCTAssertEqual(d.stages["weathered"]?.snowDepth, 0)
        XCTAssertEqual(d.stages["weathered"]?.look.weather, .plain)
        d.setAppActive(false, now: time(10, 10))
        sky = .snow
        d.setAppActive(true, now: time(10, 15))
        XCTAssertEqual(d.stages["weathered"]?.snowDepth, 0, "bare snow again")
    }

    /// While a sky holds, about every other flicker is its own (a drip in the rain and the storm, a pant in the heat);
    /// none under other skies; a character with no sky gestures flickers as before.
    func testTheSkysShareOfFlickers() {
        func flickers(_ sky: CompanionSky, _ id: String = "weathered") -> [String] {
            let d = director(seed: 12, sky: sky)
            d.appear(id, place: .field, still: false, calm: false, now: time(8))
            let mode = Cast.all.first { $0.id == id }!.field.awake
            return run(d, id, until: time(12)).compactMap { act in
                if case .gesture(let g) = act.kind { return mode.gestures[g].name }
                return nil
            }
        }
        let rain = flickers(.rain)
        XCTAssertEqual(Double(rain.filter { $0 == "drip" }.count) / Double(rain.count), 0.5, accuracy: 0.1, "\(rain.count) flickers")
        XCTAssertFalse(rain.contains("pant"))
        XCTAssertTrue(flickers(.storm).contains("drip"), "a storm drips too")
        let heat = flickers(.heat)
        XCTAssertEqual(Double(heat.filter { $0 == "pant" }.count) / Double(heat.count), 0.5, accuracy: 0.1)
        for sky in [CompanionSky.clouds, .clear, .unknown, .snow] {
            let names = Set(flickers(sky))
            XCTAssertFalse(names.contains("drip") || names.contains("pant"), "\(sky)")
        }
        XCTAssertFalse(flickers(.rain).contains("both"), "an unmarked gesture is no flicker")
        XCTAssertEqual(Set(flickers(.rain, "stayer")), ["blink", "wag", "both"], "none of it: as before")
    }

    /// A hot day by day: the heat still, its own routine and flicker about every other time, no flourish from a heat
    /// still. At night the look is asleep (the heat still is the awake one) with nothing of the heat's. A character
    /// with no heat still keeps its flourish on a hot day.
    func testHeatByDayOnly() {
        let d = director(seed: 3, sky: .heat)
        d.appear("weathered", place: .field, still: false, calm: false, now: time(8))
        XCTAssertEqual(d.stages["weathered"]?.look, CompanionLook(asleep: false, weather: .heat))
        let clock = CompanionClock(character: Cast.weathered)
        XCTAssertEqual(clock.restPose(at: time(8), stage: d.stages["weathered"]!).frame, Cast.weathered.index["hot"])
        let acts = run(d, "weathered", until: time(20))
        XCTAssertFalse(acts.contains { $0.kind == .flourish }, "no flourish from a heat still")
        let names = routines(acts).map { routineName($0, Cast.weathered) }
        XCTAssertTrue(names.contains("fan"))
        XCTAssertFalse(names.contains("shake"))
        d.tap("weathered", now: time(20, 30))
        XCTAssertNotEqual(d.stages["weathered"]?.act?.kind, .flourish)

        let night = director(sky: .heat)
        night.appear("weathered", place: .field, still: false, calm: false, now: time(23))
        let stage = night.stages["weathered"]!
        XCTAssertTrue(stage.look.asleep)
        XCTAssertEqual(clock.restPose(at: time(23), stage: stage).frame, Cast.weathered.index["sleep"], "asleep, not wilting")
        let nightActs = run(night, "weathered", until: time(4, day: 1))
        XCTAssertTrue(routines(nightActs).isEmpty)
        XCTAssertFalse(nightActs.contains { $0.kind == .gesture(3) }, "no panting in its sleep")

        let plain = director(sky: .heat)
        plain.appear("stayer", place: .field, still: false, calm: false, now: time(12))
        XCTAssertEqual(CompanionClock(character: Cast.stayer).restPose(at: time(12), stage: plain.stages["stayer"]!).frame,
                       Cast.stayer.index["rest"], "no heat still: the rest")
        plain.tap("stayer", now: time(12, 0, second: 30))
        XCTAssertEqual(plain.stages["stayer"]?.act?.kind, .flourish, "and its flourish, as before")
    }

    /// A character that uses none of brief 91: snow never piles on it, it has no sky flickers, a hot day is plain.
    func testACharacterThatUsesNoneOfIt() {
        let d = director(seed: 5, sky: .snow)
        d.appear("dancer", place: .field, still: false, calm: false, now: time(9))
        run(d, "dancer", until: time(13))
        XCTAssertEqual(d.stages["dancer"]?.snowDepth, 0)
        let hot = director(seed: 5, sky: .heat)
        hot.appear("dancer", place: .field, still: false, calm: false, now: time(9))
        let names = routines(run(hot, "dancer", until: time(13))).map { routineName($0) }
        XCTAssertEqual(Set(names), ["shuffle", "stretch", "feet"], "its everyday routines, none of a sky's")
    }

    // MARK: - Never a dead minute (brief 100)

    /// Whether an act is an idle: a flicker or a little loop.
    private func isIdle(_ act: CompanionAct, _ character: CompanionCharacter, place: CompanionPlace, look: CompanionLook) -> Bool {
        switch act.kind {
        case .gesture: return true
        case .routine(let i):
            let routines = character.posture(place).mode(look).routines
            return routines.indices.contains(i) && routines[i].little
        case .answer, .flourish: return false
        }
    }

    /// The still stretches of a showing from `from` to `to`: to the first act, from each act's end to the next one's
    /// start, and from the last one's end to `to`.
    private func stillStretches(_ acts: [CompanionAct], _ character: CompanionCharacter, place: CompanionPlace,
                                look: CompanionLook, from: Date, to: Date) -> [TimeInterval] {
        let clock = CompanionClock(character: character)
        var out: [TimeInterval] = []
        var free = from
        for act in acts {
            out.append(act.start.timeIntervalSince(free))
            let stage = CompanionStage(since: from, place: place, look: look, act: act)
            free = clock.end(of: act, stage: stage)
        }
        out.append(to.timeIntervalSince(free))
        return out
    }

    /// Ten minutes awake and ten asleep, for every character (the test cast's and the app's), in both places, under
    /// every sky and in the deepest snow: the first act within 6 seconds of coming on screen and no still stretch
    /// longer than 36 seconds. That minute is the test George ran.
    func testNeverADeadMinute() {
        let skies: [CompanionSky] = [.clouds, .rain, .storm, .snow, .heat]
        var worst: [String] = []
        for character in Cast.all + CompanionCharacter.all {
            for place in CompanionPlace.allCases {
                for sky in skies {
                    for (hour, label) in [(9, "awake"), (23, "asleep")] {
                        for deep in [false, true] where !deep || sky == .snow {
                            let launch = deep ? CompanionLaunchOptions(arguments: ["-companionSnowDepth", "9"]) : .none
                            let d = director(seed: 31, launch: launch, sky: sky, cast: [character])
                            let start = time(hour)
                            let end = start.addingTimeInterval(600)
                            d.appear(character.id, place: place, still: false, calm: false, now: start)
                            let look = d.stages[character.id]!.look
                            let acts = run(d, character.id, until: end)
                            let at = "\(character.id) \(place) \(sky)\(deep ? " deepest" : "") \(label)"
                            let stretches = stillStretches(acts, character, place: place, look: look, from: start, to: end)
                            XCTAssertLessThanOrEqual(stretches.first ?? 99, 6.01, "\(at): the first act within 6 s")
                            let longest = stretches.max() ?? 0
                            XCTAssertLessThanOrEqual(longest, 36.01, "\(at): still for \(longest) s")
                            let idles = acts.filter { isIdle($0, character, place: place, look: look) }
                            XCTAssertGreaterThanOrEqual(idles.count, 600 / 37, "\(at): \(idles.count) idles in ten minutes")
                            if place == .plus, !deep { worst.append("\(at): \(idles.count) idles, longest still \(Int(longest)) s") }
                        }
                    }
                }
            }
        }
        keep(worst.joined(separator: "\n"), as: "never-a-dead-minute.txt")
    }

    /// The first act after it comes on screen, and how long after `since` it started.
    private func firstAct(_ d: CompanionDirector, _ id: String, since: Date) -> (act: CompanionAct, wait: TimeInterval)? {
        let acts = run(d, id, until: since.addingTimeInterval(60))
        return acts.first.map { ($0, $0.start.timeIntervalSince(since)) }
    }

    /// The first idle comes 2 to 6 seconds after each way of coming on screen: the launch, back to the app (even with
    /// the next idle owed half a minute away), its tab or a sheet closing (the perch leaves and comes back), awake or
    /// asleep, and with Reduce Effects.
    func testTheFirstIdleWithinSixSecondsOfEachWayOfComingOnScreen() {
        for (hour, calm) in [(12, false), (23, false), (12, true)] {
            let d = director(seed: 41, cast: [Cast.idler])
            let at = "\(hour):00\(calm ? " calm" : "")"
            let launch = time(hour)
            d.appear("idler", place: .plus, still: false, calm: calm, now: launch)
            guard let first = firstAct(d, "idler", since: launch) else { return XCTFail("\(at): nothing at launch") }
            XCTAssertTrue((2...6).contains(first.wait), "\(at): launch, \(first.wait) s")
            // Play on a while, then leave right after an idle (the next one owed up to 36 s away) and come back.
            run(d, "idler", until: time(hour, 3))
            let away = time(hour, 3)
            d.setAppActive(false, now: away)
            let back = away.addingTimeInterval(45)
            d.setAppActive(true, now: back)
            guard let again = firstAct(d, "idler", since: back) else { return XCTFail("\(at): nothing coming back") }
            XCTAssertTrue((2...6).contains(again.wait), "\(at): back to the app, \(again.wait) s")
            XCTAssertTrue(isIdle(again.act, Cast.idler, place: .plus, look: d.stages["idler"]!.look), "\(at): an idle")
            // Its tab, or a sheet closing: the perch goes and comes back.
            let gone = time(hour, 5)
            run(d, "idler", until: gone)
            d.disappear("idler", now: gone)
            let returned = gone.addingTimeInterval(20)
            d.appear("idler", place: .plus, still: false, calm: calm, now: returned)
            guard let third = firstAct(d, "idler", since: returned) else { return XCTFail("\(at): nothing on its tab") }
            XCTAssertTrue((2...6).contains(third.wait), "\(at): its tab, \(third.wait) s")
        }
    }

    /// The idler over eight hours awake: never the same idle twice running, a little loop about one in three, the
    /// blink (the heaviest) the commonest flicker; the routine clock plays only its long routine, never a loop, and a
    /// tap's routine is the long one too. Reduce Effects and Low Power Mode: the loops go on, the routine and the
    /// flourish don't. Asleep: its two breaths, no loops.
    func testTheIdlersIdles() {
        let character = Cast.idler
        let awake = character.plus.awake
        let d = director(seed: 51, sky: .clouds, cast: [character])
        d.appear("idler", place: .plus, still: false, calm: false, now: time(9))
        let acts = run(d, "idler", until: time(17))
        let idles = acts.filter { isIdle($0, character, place: .plus, look: .day) }
        for (a, b) in zip(idles, idles.dropFirst()) { XCTAssertNotEqual(a.kind, b.kind, "the same idle twice running") }
        let loops = idles.filter { if case .routine = $0.kind { return true } else { return false } }
        XCTAssertEqual(Double(loops.count) / Double(idles.count), 1.0 / 3, accuracy: 0.05, "\(loops.count) of \(idles.count)")
        var flickers: [Int: Int] = [:]
        for act in idles { if case .gesture(let g) = act.kind { flickers[g, default: 0] += 1 } }
        XCTAssertEqual(Set(flickers.keys), [0, 1, 2], "its three flickers, never the unmarked one")
        XCTAssertGreaterThan(flickers[0]!, max(flickers[1]!, flickers[2]!), "the blink the commonest: \(flickers)")
        XCTAssertEqual(Set(loops.map(\.kind)), [.routine(1), .routine(2), .routine(3)], "every loop comes up")
        let long = acts.filter { act in
            if case .routine(let i) = act.kind { return !awake.routines[i].little }
            return false
        }
        XCTAssertFalse(long.isEmpty, "its routine plays on its own clock")
        XCTAssertTrue(long.allSatisfy { $0.kind == .routine(0) })
        XCTAssertEqual(d.lastRoutineName, "idler.shuffle", "the routine clock keeps only the long one")
        print("Companion idler: \(idles.count) idles (\(loops.count) loops), \(long.count) routines in eight hours")

        let tapped = director(seed: 52, cast: [character])
        tapped.appear("idler", place: .plus, still: false, calm: false, now: time(12))
        tapped.tap("idler", now: time(12, 0, second: 30))
        XCTAssertEqual(tapped.stages["idler"]?.act?.kind, .flourish)
        tapped.tap("idler", now: time(12, 1))
        XCTAssertEqual(tapped.stages["idler"]?.act?.kind, .routine(0), "a tap's routine is the long one, never a loop")

        for lowPower in [false, true] {
            let quiet = director(seed: 53, sky: .clouds, cast: [character])
            quiet.appear("idler", place: .plus, still: false, calm: !lowPower, now: time(12))
            if lowPower { quiet.setLowPower(true, now: time(12)) }
            let calmActs = run(quiet, "idler", until: time(14))
            let label = lowPower ? "Low Power Mode" : "Reduce Effects"
            XCTAssertTrue(calmActs.allSatisfy { isIdle($0, character, place: .plus, look: .day) }, "\(label): idles only")
            XCTAssertTrue(calmActs.contains { $0.kind == .routine(1) || $0.kind == .routine(2) || $0.kind == .routine(3) },
                          "\(label): the little loops go on")
        }

        let still = director(cast: [character])
        still.appear("idler", place: .plus, still: true, calm: false, now: time(12))
        XCTAssertFalse(still.isWaiting, "Reduce Motion: nothing moves")
        XCTAssertTrue(run(still, "idler", until: time(13)).isEmpty)

        let night = director(seed: 54, cast: [character])
        night.appear("idler", place: .plus, still: false, calm: false, now: time(23))
        let breaths = run(night, "idler", until: time(1, day: 1))
        XCTAssertTrue(breaths.allSatisfy { if case .gesture = $0.kind { return true } else { return false } }, "asleep: no loops")
        XCTAssertEqual(Set(breaths.map(\.kind)), [.gesture(0), .gesture(1)], "both its breaths")
        for (a, b) in zip(breaths, breaths.dropFirst()) { XCTAssertNotEqual(a.kind, b.kind) }
    }

    /// The least a character can be, one flicker and no loops or routines: it blinks every 6 to 36 seconds (the same
    /// one again, since it is all it has), stirs asleep at the same pace, and a tap plays its flourish, then a reply.
    func testOneFlickerAndNothingElse() {
        let character = Cast.loner
        let d = director(seed: 61, cast: [character])
        d.appear("loner", place: .plus, still: false, calm: false, now: time(12))
        let acts = run(d, "loner", until: time(13))
        XCTAssertGreaterThan(acts.count, 3600 / 37)
        XCTAssertTrue(acts.allSatisfy { $0.kind == .gesture(0) || $0.kind == .flourish }, "\(Set(acts.map(\.kind)))")
        let stretches = stillStretches(acts, character, place: .plus, look: .day, from: time(12), to: time(13))
        XCTAssertLessThanOrEqual(stretches.max() ?? 99, 36.01)
        let budget = d.routineBudget
        d.setAppActive(false, now: time(13))
        XCTAssertEqual(d.routineBudget, budget, accuracy: 0.001, "no routine to spend showing time on")
        d.setAppActive(true, now: time(13, 1))
        d.tap("loner", now: time(13, 1, second: 10))
        XCTAssertNotNil(d.stages["loner"]?.act, "a tap does something")

        let night = director(seed: 62, cast: [character])
        night.appear("loner", place: .plus, still: false, calm: false, now: time(23))
        let stirs = run(night, "loner", until: time(23, 30))
        XCTAssertGreaterThan(stirs.count, 1800 / 37)
        XCTAssertEqual(Set(stirs.map(\.kind)), [.gesture(0)])
    }

    // MARK: - A day

    /// "3 blink, 1 flourish": counts by name, in name order.
    private static func summary(_ counts: [String: Int]) -> String {
        var parts: [String] = []
        for name in counts.keys.sorted() { parts.append("\(counts[name]!) \(name)") }
        return parts.joined(separator: ", ")
    }

    /// What a companion does over a simulated eight-hour afternoon and evening, 15:00 to 23:00, with the app in front
    /// most of it (four sittings), under `sky`: per hour, its flickers by name and each routine at its moment; the
    /// flourish; night. The report's timeline (printed, and attached to the result).
    private func day(_ character: CompanionCharacter, place: CompanionPlace = .field, sky: CompanionSky = .clouds,
                     seed: UInt64 = 2026) -> (text: String, counts: [String: Int], routines: [String], asleep: Bool) {
        let d = director(seed: seed, sky: sky, cast: [character])
        let id = character.id
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm:ss"
        let short = DateFormatter()
        short.timeZone = calendar.timeZone
        short.dateFormat = "HH:mm"
        let sittings: [(Date, Date)] = [(time(15), time(17, 10)), (time(17, 40), time(19, 55)),
                                        (time(20, 30), time(22, 25)), (time(22, 40), time(23))]
        d.appear(id, place: place, still: false, calm: false, now: time(15))
        var counts: [String: Int] = [:]
        var routineNames: [String] = []
        for (i, sitting) in sittings.enumerated() {
            if i > 0 { d.setAppActive(true, now: sitting.0) }
            let look = d.stages[id]!.look
            lines.append("\(formatter.string(from: sitting.0))  app in front, \(look.asleep ? "asleep" : "awake")")
            var hourCounts: [String: Int] = [:]
            var hourRoutines: [String] = []
            var hour = calendar.component(.hour, from: sitting.0)
            func flush() {
                var text = Self.summary(hourCounts)
                if !hourRoutines.isEmpty { text += (text.isEmpty ? "" : "  |  ") + hourRoutines.joined(separator: ", ") }
                if !text.isEmpty {
                    let label = String(format: "  %02d:00–%02d:59  ", hour, hour)
                    lines.append(label + text)
                }
                hourCounts = [:]
                hourRoutines = []
            }
            for act in run(d, id, until: sitting.1) {
                let h = calendar.component(.hour, from: act.start)
                if h != hour { flush(); hour = h }
                let mode = character.posture(place).mode(look)
                switch act.kind {
                case .gesture(let g):
                    let name = look.asleep ? "stir" : mode.gestures[g].name
                    hourCounts[name, default: 0] += 1
                    counts[name, default: 0] += 1
                case .routine(let r) where mode.routines[r].little:
                    // A little loop is an idle: counted like a flicker, by name, with a tilde.
                    let name = "~" + mode.routines[r].name
                    hourCounts[name, default: 0] += 1
                    counts[name, default: 0] += 1
                case .routine(let r):
                    let name = mode.routines[r].name
                    hourRoutines.append("\(name) \(short.string(from: act.start))")
                    routineNames.append(name)
                    counts["routine", default: 0] += 1
                case .answer:
                    counts["reply", default: 0] += 1
                case .flourish:
                    counts["flourish", default: 0] += 1
                    hourRoutines.append("★ flourish \(short.string(from: act.start))")
                }
            }
            flush()
            d.setAppActive(false, now: sitting.1)
            lines.append("\(formatter.string(from: sitting.1))  app left")
        }
        lines.append("In all: " + Self.summary(counts))
        return (lines.joined(separator: "\n"), counts, routineNames, d.stages[id]!.look.asleep)
    }

    private func keep(_ text: String, as name: String) {
        print("\(name):\n\(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The test cast's dancer over the day: flickers between, a routine every few minutes, never the same twice
    /// running, asleep by the last sitting with only a stir.
    func testADancersDay() {
        let result = day(Cast.dancer)
        keep(result.text, as: "dancer-day.txt")
        XCTAssertTrue(result.asleep)
        XCTAssertGreaterThan(result.counts["stir"] ?? 0, 0)
        XCTAssertTrue((40...100).contains(result.routines.count), "\(result.routines.count) routines in about seven hours awake")
        for (a, b) in zip(result.routines, result.routines.dropFirst()) { XCTAssertNotEqual(a, b) }
        XCTAssertNil(result.counts["both"], "an unmarked gesture is no flicker")
    }

    /// What Nod does over the day: the report's timeline.
    func testAnEightHourDay() {
        let result = day(CompanionCharacter.nod)
        keep(result.text, as: "companion-day.txt")
        XCTAssertLessThanOrEqual(result.counts["flourish"] ?? 0, 5)
        XCTAssertTrue(result.asleep, "asleep by the last sitting")
        XCTAssertGreaterThan(result.counts["stir"] ?? 0, 0, "it stirs in its sleep")
        XCTAssertGreaterThan(result.counts["blink"] ?? 0, 30)
    }
}
