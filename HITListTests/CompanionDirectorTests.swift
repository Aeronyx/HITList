import XCTest
import HITListCore
@testable import HITList

/// Brief 79: the director that keeps the companions, driven by a simulated clock. Mostly still (a gesture every 45 to
/// 120 seconds and nothing between), the rare flourish over a simulated month, its kept time across a relaunch, the
/// tap's rules, night's edges (decided while nobody is looking), weather, a theme change, no timer unless something
/// is due within the hour, and the eight-hour day the report shows.
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
                          sky: CompanionSky = .clear, cast: [CompanionCharacter] = Cast.all) -> CompanionDirector {
        CompanionDirector(seed: seed, launch: launch, observeSystem: false, cast: cast,
                          defaults: defaults ?? freshDefaults(), calendar: calendar, sky: { sky })
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
        XCTAssertTrue((45...120).contains(wait), "the first gesture comes 45 to 120 seconds in, not at once: \(wait)")
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

    func testAGestureNowAndThenAndNothingBetween() {
        let d = director()
        d.appear("stayer", place: .field, still: false, calm: false, now: time(9))
        let acts = run(d, until: time(13))
        let gestures = acts.filter { if case .gesture = $0.kind { return true } else { return false } }
        XCTAssertGreaterThan(gestures.count, 4 * 3600 / 120 - 2)
        XCTAssertLessThan(gestures.count, 4 * 3600 / 45 + 2)
        let clock = CompanionClock(character: Cast.stayer)
        var kinds: [CompanionAct.Kind] = []
        for (a, b) in zip(acts, acts.dropFirst()) {
            let stage = CompanionStage(since: time(9), place: .field, look: .day, act: a)
            let end = clock.end(of: a, stage: stage)
            XCTAssertLessThan(end.timeIntervalSince(a.start), 2.7, "every act is short")
            if case .gesture = a.kind { XCTAssertLessThan(end.timeIntervalSince(a.start), 1, "a gesture is under a second") }
            if case .gesture = a.kind, case .gesture = b.kind {
                let gap = b.start.timeIntervalSince(a.start)
                XCTAssertTrue((45...121).contains(gap), "one small gesture every 45 to 120 seconds: \(gap)")
            }
            // Between acts it is a still picture: nothing to redraw.
            XCTAssertNil(clock.nextChange(after: end, stage: stage))
            kinds.append(a.kind)
        }
        for i in 2..<kinds.count where kinds[i] == kinds[i - 1] && kinds[i] == kinds[i - 2] {
            if case .gesture = kinds[i] { XCTFail("the same gesture three times running at \(i)") }
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
                    let end = start.addingTimeInterval(TimeInterval(session.minutes * 60))
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
            perHour.append(heavy.shown / 3600 / Double(heavy.flourishes.count))
        }
        let meanGap = perHour.reduce(0, +) / Double(perHour.count)
        XCTAssertEqual(meanGap, 3, accuracy: 0.5, "about once in three hours of the screen showing: \(perHour)")
        // An hour a day, in three twenty-minute visits, over twelve weeks.
        var perWeek: [Double] = []
        for seed in [4, 5, 6] as [UInt64] {
            let light = month(sessions: [(9, 20), (13, 20), (20, 20)], days: 84, seed: seed)
            perWeek.append(Double(light.flourishes.count) / 12)
        }
        let weekly = perWeek.reduce(0, +) / Double(perWeek.count)
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
        // Asleep: a stir every six to fifteen minutes, never a flourish, and the budget untouched.
        let budget = d.budget
        let night = run(d, until: time(6, 59, day: 1))
        XCTAssertFalse(night.contains { $0.kind == .flourish }, "no flourish while asleep")
        for (a, b) in zip(night, night.dropFirst()) {
            XCTAssertTrue((360...901).contains(b.start.timeIntervalSince(a.start)), "a rare stir")
        }
        XCTAssertGreaterThan(night.count, 20)
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

    // MARK: - A day

    /// What Nod does over a simulated eight-hour afternoon and evening, 15:00 to 23:00, with the app in front most
    /// of it: the report's timeline (printed, and attached to the result).
    func testAnEightHourDay() {
        let nod = CompanionCharacter.nod
        let d = director(seed: 2026, cast: [nod])
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm:ss"
        let sittings: [(Date, Date)] = [(time(15), time(17, 10)), (time(17, 40), time(19, 55)),
                                        (time(20, 30), time(22, 25)), (time(22, 40), time(23))]
        d.appear("nod", place: .field, still: false, calm: false, now: time(15))
        var counts: [String: Int] = [:]
        var flourishes = 0
        for (i, sitting) in sittings.enumerated() {
            if i > 0 { d.setAppActive(true, now: sitting.0) }
            let look = d.stages["nod"]!.look
            lines.append("\(formatter.string(from: sitting.0))  app in front, \(look.asleep ? "asleep" : "awake")")
            var hourCounts: [String: Int] = [:]
            var hour = calendar.component(.hour, from: sitting.0)
            func flush() {
                let text = hourCounts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
                if !text.isEmpty { lines.append(String(format: "  %02d:00–%02d:59  ", hour, hour) + text) }
                hourCounts = [:]
            }
            for act in run(d, "nod", until: sitting.1) {
                let h = calendar.component(.hour, from: act.start)
                if h != hour { flush(); hour = h }
                let name: String
                switch act.kind {
                case .gesture(let g):
                    let mode = nod.field.mode(look)
                    name = look.asleep ? "stir" : mode.gestures[g].name
                case .answer: name = "reply"
                case .flourish:
                    name = "flourish"
                    flourishes += 1
                    lines.append("  \(formatter.string(from: act.start))  ★ the flourish")
                }
                hourCounts[name, default: 0] += 1
                counts[name, default: 0] += 1
            }
            flush()
            d.setAppActive(false, now: sitting.1)
            lines.append("\(formatter.string(from: sitting.1))  app left")
        }
        lines.append("In all: " + counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
        let text = lines.joined(separator: "\n")
        print("Companion day:\n\(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "companion-day.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(flourishes, 5)
        XCTAssertTrue(d.stages["nod"]!.look.asleep, "asleep by the last sitting")
        XCTAssertGreaterThan(counts["stir"] ?? 0, 0, "it stirs in its sleep")
        XCTAssertGreaterThan(counts["blink"] ?? 0, 30)
    }
}
