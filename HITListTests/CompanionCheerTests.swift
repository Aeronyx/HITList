import XCTest
import HITListCore
@testable import HITList

/// Brief 132: the companion cheers a completed task. `CompletionDelightHook` tells the director; the creature on screen
/// plays its cheer (one to two seconds) awake in plain weather; at most one cheer in any 6 seconds; never over a
/// flourish or a long routine (dropped then); asleep its `answer` (the sleepy peek) at most once a minute; under a sky
/// that holds its answer drawn over the weather's still, or nothing when that can't be drawn (never a dry frame in the
/// rain); Reduce Motion, Reduce Effects and Low Power Mode nothing; the next idle's wait starts when the cheer ends.
@MainActor
final class CompanionCheerTests: XCTestCase {
    private typealias Cast = CompanionClockTests.TestCast

    private func time(_ hour: Int, minute: Int = 0, second: Double = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
        return base.addingTimeInterval(second)
    }

    private func director(sky: CompanionSky = .clear, cast: [CompanionCharacter] = Cast.all,
                          launch: CompanionLaunchOptions = .none) -> CompanionDirector {
        CompanionDirector(seed: 132, launch: launch, observeSystem: false, cast: cast, defaults: nil,
                          zone: { TimeZone(identifier: "UTC")! }, sky: { sky })
    }

    private func kind(_ d: CompanionDirector, _ id: String) -> CompanionAct.Kind? { d.stages[id]?.act?.kind }

    // MARK: - The rule, pure

    func testTheRule() {
        let now = time(12)
        func reply(look: CompanionLook = .day, onScreen: Bool = true, busy: Bool = false, still: Bool = false,
                   calm: Bool = false, lowPower: Bool = false, lastCheer: Date? = nil, lastSleepy: Date? = nil,
                   answerDraws: Bool = true) -> CompanionSchedule.CheerReply {
            CompanionSchedule.cheerReply(now: now, onScreen: onScreen, look: look, busy: busy, still: still, calm: calm,
                                         lowPower: lowPower, lastCheer: lastCheer, lastSleepy: lastSleepy,
                                         answerDraws: answerDraws)
        }
        XCTAssertEqual(reply(), .cheer)
        XCTAssertEqual(reply(onScreen: false), .nothing, "the app not in front")
        XCTAssertEqual(reply(busy: true), .nothing, "a flourish or a routine playing: dropped")
        XCTAssertEqual(reply(still: true), .nothing, "Reduce Motion: nothing moves")
        XCTAssertEqual(reply(calm: true), .nothing, "Reduce Effects: idles only")
        XCTAssertEqual(reply(lowPower: true), .nothing, "Low Power Mode: idles only")
        XCTAssertEqual(reply(lastCheer: now.addingTimeInterval(-5.9)), .nothing, "one in any 6 seconds")
        XCTAssertEqual(reply(lastCheer: now.addingTimeInterval(-6)), .cheer)
        let asleep = CompanionLook(asleep: true, weather: .plain)
        XCTAssertEqual(reply(look: asleep), .answer, "asleep: the sleepy peek")
        XCTAssertEqual(reply(look: asleep, lastSleepy: now.addingTimeInterval(-59)), .nothing, "at most once a minute")
        XCTAssertEqual(reply(look: asleep, lastSleepy: now.addingTimeInterval(-60)), .answer)
        XCTAssertEqual(reply(look: asleep, answerDraws: false), .nothing)
        for weather in [CompanionLook.Weather.rain, .snow, .heat] {
            XCTAssertEqual(reply(look: CompanionLook(asleep: false, weather: weather)), .answer, "\(weather): its answer")
            XCTAssertEqual(reply(look: CompanionLook(asleep: false, weather: weather), answerDraws: false), .nothing,
                           "\(weather): nothing rather than a dry frame")
            XCTAssertEqual(reply(look: CompanionLook(asleep: true, weather: weather)), .answer, "\(weather) asleep")
        }
    }

    // MARK: - The director

    func testItCheersAndTheNextIdleWaitsFromTheCheersEnd() {
        let d = director(cast: [Cast.stayer])
        d.appear("stayer", place: .plus, still: false, calm: false, now: time(12))
        let now = time(12, second: 1)
        d.cheer(now: now)
        XCTAssertEqual(kind(d, "stayer"), .cheer)
        let clock = CompanionClock(character: Cast.stayer)
        let stage = d.stages["stayer"]!
        let end = clock.end(of: stage.act!, stage: stage)
        XCTAssertEqual(d.nextMoment, end, "the timer wakes when the cheer ends, not before")
        d.fire(now: end)
        XCTAssertNil(d.stages["stayer"]?.act, "put away")
        let wait = d.nextMoment!.timeIntervalSince(end)
        XCTAssertTrue((4...12).contains(wait), "the next idle 4 to 12 s after the cheer ends: \(wait)")
    }

    func testOneCheerInAnySixSeconds() {
        let d = director(cast: [Cast.stayer])
        d.appear("stayer", place: .plus, still: false, calm: false, now: time(12))
        var starts: [Date] = []
        // Ten tasks ticked half a second apart, then one more after the six seconds.
        for i in 0..<10 {
            let now = time(12, second: 2 + Double(i) * 0.5)
            d.fire(now: now)
            d.cheer(now: now)
            if let act = d.stages["stayer"]?.act, act.kind == .cheer, starts.last != act.start { starts.append(act.start) }
        }
        XCTAssertEqual(starts.count, 1, "ten in a row cheer once")
        let later = time(12, second: 8.1)
        d.fire(now: later)
        d.cheer(now: later)
        XCTAssertEqual(kind(d, "stayer"), .cheer, "and again once 6 seconds have passed")
        XCTAssertEqual(d.stages["stayer"]?.act?.start, later)
    }

    func testNeverCutsAFlourishOrARoutineShort() {
        let d = director(cast: [Cast.stayer])
        d.appear("stayer", place: .plus, still: false, calm: false, now: time(12))
        d.tap("stayer", now: time(12, second: 30))
        XCTAssertEqual(kind(d, "stayer"), .flourish, "a tap plays the flourish")
        d.cheer(now: time(12, second: 30.5))
        XCTAssertEqual(kind(d, "stayer"), .flourish, "the cheer is dropped, the flourish plays on")
        XCTAssertEqual(d.stages["stayer"]?.act?.start, time(12, second: 30))

        let dancer = director(cast: [Cast.dancer])
        dancer.appear("dancer", place: .plus, still: false, calm: false, now: time(12))
        dancer.tap("dancer", now: time(12, second: 30))     // the flourish
        dancer.tap("dancer", now: time(12, minute: 1, second: 1)) // a routine (no flourish for 20 minutes)
        guard case .routine(let r)? = kind(dancer, "dancer"), !Cast.dancer.plus.awake.routines[r].little else {
            return XCTFail("a routine plays: \(String(describing: kind(dancer, "dancer")))")
        }
        dancer.cheer(now: time(12, minute: 1, second: 2))
        XCTAssertEqual(kind(dancer, "dancer"), .routine(r), "the routine plays on")

        // A flicker is small: the cheer takes its place.
        let e = director(cast: [Cast.stayer])
        e.appear("stayer", place: .plus, still: false, calm: false, now: time(12))
        let first = e.nextMoment!
        e.fire(now: first)
        guard case .gesture? = kind(e, "stayer") else { return XCTFail("an idle first") }
        e.cheer(now: first.addingTimeInterval(0.1))
        XCTAssertEqual(kind(e, "stayer"), .cheer)
    }

    func testAsleepTheSleepyPeekAtMostOnceAMinute() {
        let d = director(cast: [Cast.stayer])
        d.appear("stayer", place: .plus, still: false, calm: false, now: time(23))
        d.cheer(now: time(23, second: 1))
        XCTAssertEqual(kind(d, "stayer"), .answer, "the sleepy peek")
        d.fire(now: time(23, second: 3))
        d.cheer(now: time(23, second: 20))
        XCTAssertNotEqual(d.stages["stayer"]?.act?.start, time(23, second: 20), "not again within the minute")
        d.fire(now: time(23, minute: 1, second: 1))
        d.cheer(now: time(23, minute: 1, second: 1.5))
        XCTAssertEqual(kind(d, "stayer"), .answer)
        XCTAssertEqual(d.stages["stayer"]?.act?.start, time(23, minute: 1, second: 1.5))
    }

    func testUnderASkyItsAnswerOrNothingNeverADryFrame() {
        for sky in [CompanionSky.rain, .storm, .snow, .heat] {
            for deep in [false, true] where !deep || sky == .snow {
                let launch = deep ? CompanionLaunchOptions(arguments: ["-companionSnowDepth", "9"]) : .none
                let d = director(sky: sky, cast: [Cast.weathered], launch: launch)
                d.appear("weathered", place: .plus, still: false, calm: false, now: time(12))
                let stage = d.stages["weathered"]!
                let draws = CompanionClock(character: Cast.weathered).canDraw(.answer, stage: stage)
                d.cheer(now: time(12, second: 1))
                let at = "\(sky)\(deep ? " deepest" : "")"
                XCTAssertEqual(kind(d, "weathered"), draws ? .answer : nil, "\(at)")
                XCTAssertNotEqual(kind(d, "weathered"), .cheer, "\(at): no cheer under a sky that holds")
            }
        }
        // The deepest snow covers its eye: its answer can't be drawn there, so nothing plays.
        let deep = director(sky: .snow, cast: [Cast.weathered],
                            launch: CompanionLaunchOptions(arguments: ["-companionSnowDepth", "9"]))
        deep.appear("weathered", place: .plus, still: false, calm: false, now: time(12))
        deep.cheer(now: time(12, second: 1))
        XCTAssertNil(kind(deep, "weathered"))
    }

    func testQuietWhenAskedOffScreenOrInTheBackground() {
        let d = director(cast: [Cast.stayer])
        d.cheer(now: time(12))
        XCTAssertTrue(d.stages.isEmpty, "no companion on screen (Extras → Companions off): nothing")
        d.appear("stayer", place: .plus, still: true, calm: false, now: time(12))
        d.cheer(now: time(12, second: 1))
        XCTAssertNil(kind(d, "stayer"), "Reduce Motion")
        d.setMotion("stayer", still: false, calm: true, now: time(12, second: 2))
        d.cheer(now: time(12, second: 3))
        XCTAssertNil(kind(d, "stayer"), "Reduce Effects")
        d.setMotion("stayer", still: false, calm: false, now: time(12, second: 4))
        d.setLowPower(true, now: time(12, second: 4))
        d.cheer(now: time(12, second: 5))
        XCTAssertNotEqual(kind(d, "stayer"), .cheer, "Low Power Mode")
        d.setLowPower(false, now: time(12, second: 6))
        d.setAppActive(false, now: time(12, second: 6))
        d.cheer(now: time(12, second: 7))
        XCTAssertNotEqual(kind(d, "stayer"), .cheer, "the app in the background")
    }
}
