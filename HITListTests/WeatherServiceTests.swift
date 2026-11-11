import XCTest
import CoreLocation
import HITListCore
@testable import HITList

/// Briefs 80 and 83: the sky for the companions. On by default but silent until asked; silent while off; asked once;
/// one fix and one request when the app comes forward and the last observation is over an hour old; an observation
/// over three hours old is `unknown`; failures are quiet and wait for the next time the app comes forward. A fake
/// clock, fake sources.
@MainActor
final class WeatherServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""
    private var location: FakeLocation!
    private var weather: FakeWeather!
    private var zones: FakeZone!
    private var sky: CompanionSkySource!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var madeLocation = 0
    private var madeWeather = 0
    /// What is on screen for the first launch's question: in front and clear unless a test says otherwise.
    private var inFront = true
    private var screenClear = true

    override func setUp() {
        fresh()
    }

    private func fresh() {
        suite = "WeatherServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        location = FakeLocation()
        weather = FakeWeather()
        zones = FakeZone()
        sky = CompanionSkySource(arguments: UserDefaults(suiteName: "WeatherServiceTests.noArguments")!)
        madeLocation = 0
        madeWeather = 0
        inFront = true
        screenClear = true
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func discard() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// A Release build by default, so the first launch's question may be asked; the tests pass `.debug` to check the
    /// Debug rule.
    private func service(onForTheRun: Bool = false, build: LaunchLocationQuestion.Build = .release,
                         arguments: [String] = ["HITList"]) -> CompanionWeather {
        CompanionWeather(location: { [unowned self] in madeLocation += 1; return location },
                         weather: { [unowned self] in madeWeather += 1; return weather },
                         zone: { [unowned self] in zones },
                         sky: sky, defaults: defaults, now: { [unowned self] in now }, onForTheRun: onForTheRun,
                         launch: .init(build: build, arguments: arguments, isTestHost: false),
                         screen: { [unowned self] in (inFront, screenClear) })
    }

    private func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }

    /// On, allowed, with one rain observation made at `now`.
    private func onWithRain() async -> CompanionWeather {
        location.answer = .allowed
        weather.reading = WeatherReading(condition: "heavyRain", date: now)
        let service = service()
        let on = await service.setOn(true)
        XCTAssertTrue(on)
        return service
    }

    // MARK: - On by default (brief 83), silent until asked

    func testOnByDefaultButSilentUntilAsked() async {
        let service = service()
        XCTAssertTrue(service.isOn, "a switch nobody touched is on")
        XCTAssertTrue(Preferences.companionWeatherDefault)
        XCTAssertNil(defaults.object(forKey: Preferences.companionWeather), "reading the default writes nothing")
        XCTAssertFalse(service.hasAsked)
        await service.cameForward()
        service.refreshAccess()
        await service.loadCredit()
        XCTAssertEqual(madeLocation, 0, "Core Location is never touched before the question")
        XCTAssertEqual(madeWeather, 0, "WeatherKit is never touched before the question")
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertNil(service.credit)
    }

    /// Someone updating from 0.9.2: on stays on (and was asked), off stays off, untouched reads on and is still to be
    /// asked. Nothing is rewritten.
    func testUpdatingFrom092KeepsWhatThePersonChose() async {
        struct Case { let stored: Bool?; let asked: Bool; let on: Bool }
        let cases = [Case(stored: true, asked: true, on: true),     // switched on and allowed
                     Case(stored: false, asked: true, on: false),   // switched on, then off (or refused)
                     Case(stored: false, asked: false, on: false),  // off without ever being asked
                     Case(stored: nil, asked: false, on: true)]     // never touched
        for item in cases {
            discard()
            fresh()
            if let stored = item.stored { defaults.set(stored, forKey: Preferences.companionWeather) }
            if item.asked { defaults.set(true, forKey: Preferences.companionWeatherAsked) }
            let service = service()
            XCTAssertEqual(service.isOn, item.on, "stored \(String(describing: item.stored))")
            XCTAssertEqual(service.hasAsked, item.asked)
            XCTAssertEqual(defaults.object(forKey: Preferences.companionWeather) as? Bool, item.stored, "never rewritten")
        }
    }

    // MARK: - The first launch's question (brief 83)

    func testTheFirstLaunchAsksOnceAndAllowedStartsTheWeather() async {
        location.answer = .allowed
        weather.reading = WeatherReading(condition: "heavyRain", date: now)
        let flagAtPrompt = defaults
        location.onRequest = { XCTAssertTrue(flagAtPrompt!.bool(forKey: Preferences.companionWeatherAsked),
                                             "marked asked before the prompt, so a killed launch never asks twice") }
        let service = service()
        let decision = await service.considerAskingAtLaunch()
        XCTAssertEqual(decision, .ask)
        XCTAssertEqual(location.requests, 1)
        XCTAssertTrue(service.hasAsked)
        XCTAssertTrue(service.isOn)
        XCTAssertEqual(service.access, .allowed)
        XCTAssertEqual(location.fixes, 1)
        XCTAssertEqual(weather.requests, 1)
        XCTAssertEqual(sky.sky, .rain, "allowed: the weather starts")
        XCTAssertNil(defaults.object(forKey: Preferences.companionWeather), "the switch is still the default")

        let again = await service.considerAskingAtLaunch()
        XCTAssertEqual(again, .never)
        let nextLaunch = self.service()
        let next = await nextLaunch.considerAskingAtLaunch()
        XCTAssertEqual(next, .never, "the second launch asks nothing")
        XCTAssertEqual(location.requests, 1)
    }

    func testRefusedAtTheFirstLaunchTurnsWeatherOffAndNeverAsksAgain() async {
        for answer in [WeatherAccess.denied, .restricted] {
            discard()
            fresh()
            location.answer = answer
            let service = service()
            let decision = await service.considerAskingAtLaunch()
            XCTAssertEqual(decision, .ask)
            XCTAssertFalse(service.isOn)
            XCTAssertEqual(defaults.object(forKey: Preferences.companionWeather) as? Bool, false)
            XCTAssertEqual(service.access, answer)
            XCTAssertEqual(location.fixes, 0)
            XCTAssertEqual(madeWeather, 0)
            XCTAssertEqual(sky.sky, .unknown)

            // Extras still knows why, and nothing asks again by itself.
            let later = self.service()
            later.refreshAccess()
            XCTAssertEqual(later.access, answer)
            let next = await later.considerAskingAtLaunch()
            XCTAssertEqual(next, .never)
            XCTAssertEqual(location.requests, 1)
        }
    }

    func testTheQuestionWaitsForAClearScreenInFront() async {
        let service = service()
        inFront = false
        var decision = await service.considerAskingAtLaunch()
        XCTAssertEqual(decision, .later, "behind another app or still launching")
        screenClear = false
        inFront = true
        decision = await service.considerAskingAtLaunch()
        XCTAssertEqual(decision, .later, "a sheet, card or tip is showing")
        XCTAssertEqual(location.requests, 0)
        XCTAssertFalse(service.hasAsked)
        XCTAssertEqual(madeLocation, 0, "not even the permission is read while waiting")
        screenClear = true
        decision = await service.considerAskingAtLaunch()
        XCTAssertEqual(decision, .ask)
        XCTAssertEqual(location.requests, 1)
    }

    func testADebugBuildAsksAtLaunchOnlyWhenTold() async {
        let quiet = service(build: .debug)
        let decision = await quiet.considerAskingAtLaunch()
        XCTAssertEqual(decision, .never)
        XCTAssertEqual(madeLocation, 0, "Core Location untouched")
        XCTAssertFalse(quiet.hasAsked)
        let told = service(build: .debug, arguments: ["HITList", "-askLocationAtLaunch", "YES"])
        let asked = await told.considerAskingAtLaunch()
        XCTAssertEqual(asked, .ask)
        XCTAssertEqual(location.requests, 1)
    }

    func testCompanionsOffOrWeatherOffAsksNothingAtLaunch() async {
        defaults.set(false, forKey: Preferences.companions)
        var decision = await service().considerAskingAtLaunch()
        XCTAssertEqual(decision, .never)
        defaults.set(true, forKey: Preferences.companions)
        defaults.set(false, forKey: Preferences.companionWeather)
        decision = await service().considerAskingAtLaunch()
        XCTAssertEqual(decision, .never)
        XCTAssertEqual(madeLocation, 0)
    }

    func testSwitchedOffMakesNoCallAtAll() async {
        defaults.set(false, forKey: Preferences.companionWeather)
        defaults.set(true, forKey: Preferences.companionWeatherAsked)
        location.status = .allowed
        let service = service()
        XCTAssertFalse(service.isOn)
        await service.cameForward()
        await service.loadCredit()
        XCTAssertEqual(location.fixes, 0)
        XCTAssertEqual(madeWeather, 0, "WeatherKit is never touched while off")
        XCTAssertEqual(sky.sky, .unknown)
    }

    func testSwitchingOffClearsTheSkyAndStopsEveryCall() async {
        let service = await onWithRain()
        XCTAssertEqual(sky.sky, .rain)
        await service.setOn(false)
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertEqual(defaults.object(forKey: Preferences.companionWeather) as? Bool, false)
        advance(minutes: 120)
        await service.cameForward()
        XCTAssertEqual(location.fixes, 1)
        XCTAssertEqual(weather.requests, 1)
        XCTAssertEqual(location.accessReads, 1, "off: not even the permission is read when the app comes forward")
    }

    func testCompanionsOffMakesNoCall() async {
        let service = await onWithRain()
        defaults.set(false, forKey: Preferences.companions)
        await service.companionsChanged()
        XCTAssertEqual(sky.sky, .unknown)
        advance(minutes: 120)
        await service.cameForward()
        XCTAssertEqual(weather.requests, 1)
        defaults.set(true, forKey: Preferences.companions)
        await service.companionsChanged()
        XCTAssertEqual(weather.requests, 2, "Companions back on: the sky again")
        XCTAssertEqual(sky.sky, .rain)
    }

    func testSwitchingOnWithCompanionsOffAsksButMakesNoRequest() async {
        defaults.set(false, forKey: Preferences.companions)
        location.answer = .allowed
        let service = service()
        let on = await service.setOn(true)
        XCTAssertTrue(on)
        XCTAssertEqual(location.fixes, 0)
        XCTAssertEqual(weather.requests, 0)
    }

    // MARK: - Asked once

    func testSwitchingOnAsksOnceThenObservesTheSky() async {
        location.answer = .allowed
        let observed = now.addingTimeInterval(-5 * 60)
        weather.reading = WeatherReading(condition: "heavyRain", date: observed)
        let service = service()
        let on = await service.setOn(true)
        XCTAssertTrue(on)
        XCTAssertEqual(location.requests, 1, "the system's prompt, once")
        XCTAssertEqual(location.fixes, 1)
        XCTAssertEqual(weather.requests, 1)
        XCTAssertEqual(sky.sky, .rain)
        XCTAssertEqual(sky.observedAt, observed)
        XCTAssertEqual(service.access, .allowed)
        XCTAssertEqual(defaults.object(forKey: Preferences.companionWeather) as? Bool, true)

        await service.setOn(false)
        await service.setOn(true)
        XCTAssertEqual(location.requests, 1, "already answered: never asked again")
    }

    func testRefusedStaysOffAndUnknown() async {
        for answer in [WeatherAccess.denied, .restricted] {
            discard()
            fresh()
            location.answer = answer
            let service = service()
            let on = await service.setOn(true)
            XCTAssertFalse(on)
            XCTAssertFalse(service.isOn)
            XCTAssertEqual(service.access, answer)
            XCTAssertTrue(service.access.isRefused)
            XCTAssertEqual(location.fixes, 0)
            XCTAssertEqual(weather.requests, 0)
            XCTAssertEqual(madeWeather, 0)
            XCTAssertEqual(sky.sky, .unknown)
            XCTAssertEqual(defaults.object(forKey: Preferences.companionWeather) as? Bool, false)

            // A later visit to Settings still knows why (the permission is read, nothing is asked).
            let later = self.service()
            later.refreshAccess()
            XCTAssertEqual(later.access, answer)
            XCTAssertEqual(location.requests, 1)
            await later.cameForward()
            XCTAssertEqual(location.fixes, 0)
        }
    }

    func testPermissionWithdrawnInTheSystemsSettings() async {
        let service = await onWithRain()
        location.status = .denied
        advance(minutes: 5)
        await service.cameForward()
        XCTAssertEqual(service.access, .denied)
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertEqual(location.fixes, 1)
        XCTAssertEqual(weather.requests, 1)
        XCTAssertFalse(service.isShowing)
    }

    // MARK: - The hour and the three hours

    func testComingForwardWithinAnHourMakesNoCall() async {
        let service = await onWithRain()
        advance(minutes: 59)
        await service.cameForward()
        XCTAssertEqual(weather.requests, 1)
        XCTAssertEqual(location.fixes, 1)
        weather.reading = WeatherReading(condition: "snow", date: now.addingTimeInterval(60))
        advance(minutes: 2)
        await service.cameForward()
        XCTAssertEqual(location.fixes, 2)
        XCTAssertEqual(weather.requests, 2)
        XCTAssertEqual(sky.sky, .snow)
    }

    func testAnObservationOlderThanThreeHoursIsUnknown() async {
        let service = await onWithRain()
        weather.error = FakeError.offline
        advance(minutes: 120)
        await service.cameForward()
        XCTAssertEqual(sky.sky, .rain, "two hours old and the new request failed: still the sky")
        advance(minutes: 61)
        await service.cameForward()
        XCTAssertEqual(sky.sky, .unknown, "three hours and a minute old")
        XCTAssertNil(sky.observedAt)
    }

    func testAnObservationAlreadyOlderThanThreeHoursIsNeverTheSky() async {
        location.answer = .allowed
        weather.reading = WeatherReading(condition: "snow", date: now.addingTimeInterval(-4 * 60 * 60))
        let service = service()
        await service.setOn(true)
        XCTAssertEqual(sky.sky, .unknown)
    }

    // MARK: - Failing quietly

    func testAWeatherKitErrorIsUnknownAndWaitsForTheNextTimeTheAppComesForward() async {
        location.answer = .allowed
        weather.error = FakeError.noCapability
        let service = service()
        let on = await service.setOn(true)
        XCTAssertTrue(on, "the setting stays on: the feature is simply unknown meanwhile")
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertEqual(weather.requests, 1, "no retry storm")
        advance(minutes: 1)
        await service.cameForward()
        XCTAssertEqual(weather.requests, 2, "one try each time the app comes forward")
    }

    func testNoFixMeansNoWeatherRequest() async {
        location.answer = .allowed
        location.error = FakeError.offline
        let service = service()
        await service.setOn(true)
        XCTAssertEqual(location.fixes, 1)
        XCTAssertEqual(weather.requests, 0)
        XCTAssertEqual(sky.sky, .unknown)
    }

    func testComingForwardTwiceAtOnceMakesOneRequest() async {
        let service = await onWithRain()
        advance(minutes: 90)
        weather.suspends = true
        async let first: Void = service.cameForward()
        async let second: Void = service.cameForward()
        _ = await (first, second)
        XCTAssertEqual(weather.requests, 2, "one at launch, one now")
    }

    func testAnAnswerThatArrivesAfterSwitchingOffIsNotTheSky() async {
        location.answer = .allowed
        weather.reading = WeatherReading(condition: "rain", date: now)
        weather.holds = true
        let service = service()
        async let on = service.setOn(true)
        for _ in 0..<100 where weather.held == nil { await Task.yield() }
        XCTAssertNotNil(weather.held, "the request is on its way")
        await service.setOn(false)
        weather.release()
        _ = await on
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertNil(sky.observedAt)
    }

    func testTheErrorLineNeverSaysWhere() {
        let line = CompanionWeather.describe(NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors",
                                                     code: 2, userInfo: [NSLocalizedDescriptionKey: "at 51.5, -0.12"]))
        XCTAssertFalse(line.contains("51.5"), line)
        XCTAssertTrue(line.contains("WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors 2"), line)
    }

    // MARK: - The place's time zone (brief 83)

    func testEachFixGivesTheCompanionsClockThePlacesZone() async {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        zones.answer = tokyo
        let service = await onWithRain()
        XCTAssertEqual(zones.requests, 1, "one geocode for the fix")
        XCTAssertEqual(service.zone, tokyo)
        XCTAssertEqual(sky.timeZone, tokyo)
        XCTAssertEqual(sky.zone, tokyo, "the companions keep Tokyo's hours")
        XCTAssertEqual(zones.lastLocation?.coordinate.latitude, 51.5, "the same approximate fix the weather used")
    }

    func testOneGeocodePerFixAndNoneWithoutOne() async {
        let service = await onWithRain()
        advance(minutes: 59)
        await service.cameForward()
        XCTAssertEqual(zones.requests, 1, "no fix within the hour, no geocode")
        advance(minutes: 2)
        await service.cameForward()
        XCTAssertEqual(location.fixes, 2)
        XCTAssertEqual(zones.requests, 2)

        location.error = FakeError.offline
        advance(minutes: 61)
        await service.cameForward()
        XCTAssertEqual(zones.requests, 2, "no fix: nothing to geocode")
    }

    func testAZoneThatCannotBeFoundIsNilAndTheDevicesZoneRules() async {
        zones.answer = TimeZone(identifier: "Asia/Tokyo")!
        let service = await onWithRain()
        XCTAssertNotNil(sky.timeZone)
        zones.error = FakeError.offline
        advance(minutes: 61)
        await service.cameForward()
        XCTAssertNil(service.zone)
        XCTAssertNil(sky.timeZone, "unknown is nil, never a guess")
        XCTAssertEqual(sky.zone, .current)
        XCTAssertEqual(sky.sky, .rain, "the sky does not depend on the zone")
    }

    func testTheZoneArrivesEvenWhenTheWeatherFails() async {
        zones.answer = TimeZone(identifier: "Europe/Paris")!
        location.answer = .allowed
        weather.error = FakeError.noCapability
        let service = service()
        await service.setOn(true)
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertEqual(sky.timeZone, zones.answer)
        // Three hours on with no fix since: the zone is stale too.
        location.error = FakeError.offline
        advance(minutes: 181)
        await service.cameForward()
        XCTAssertNil(sky.timeZone)
    }

    func testTheZoneIsClearedWhenWeatherGoesOffIsRefusedOrGoesStale() async {
        zones.answer = TimeZone(identifier: "America/Denver")!
        var service = await onWithRain()
        await service.setOn(false)
        XCTAssertNil(sky.timeZone, "switched off")
        XCTAssertNil(service.zone)

        service = await onWithRain()
        XCTAssertNotNil(sky.timeZone)
        location.status = .denied
        advance(minutes: 5)
        await service.cameForward()
        XCTAssertNil(sky.timeZone, "permission withdrawn")

        location.status = .allowed
        service = await onWithRain()
        XCTAssertNotNil(sky.timeZone)
        defaults.set(false, forKey: Preferences.companions)
        await service.companionsChanged()
        XCTAssertNil(sky.timeZone, "Companions off")

        defaults.set(true, forKey: Preferences.companions)
        service = await onWithRain()
        XCTAssertNotNil(sky.timeZone)
        weather.error = FakeError.offline
        zones.error = FakeError.offline
        advance(minutes: 181)
        await service.cameForward()
        XCTAssertNil(sky.timeZone, "stale with the sky")
        XCTAssertEqual(sky.sky, .unknown)
    }

    func testAZoneThatArrivesAfterSwitchingOffIsNotApplied() async {
        zones.answer = TimeZone(identifier: "Asia/Tokyo")!
        location.answer = .allowed
        weather.holds = true
        let service = service()
        async let on = service.setOn(true)
        for _ in 0..<100 where weather.held == nil { await Task.yield() }
        await service.setOn(false)
        weather.release()
        _ = await on
        XCTAssertNil(sky.timeZone)
    }

    // MARK: - Attribution

    func testAttributionIsAskedForOnlyWhileOn() async {
        weather.creditAnswer = WeatherCredit(serviceName: "\u{F8FF} Weather", markURL: URL(string: "https://example.com/mark.png"),
                                             legalURL: URL(string: "https://example.com/legal")!)
        let off = service()
        await off.loadCredit()
        XCTAssertNil(off.credit)
        XCTAssertEqual(weather.credits, 0)
        let on = await onWithRain()
        await on.loadCredit()
        await on.loadCredit()
        XCTAssertEqual(on.credit, weather.creditAnswer)
        XCTAssertEqual(weather.credits, 1, "once a run")
    }
}

// MARK: - Fakes

private enum FakeError: Error { case offline, noCapability }

@MainActor
private final class FakeLocation: WeatherLocationSource {
    var status: WeatherAccess = .notDetermined
    /// What the prompt is answered with.
    var answer: WeatherAccess = .allowed
    var error: Error?
    /// Called as the prompt would show.
    var onRequest: () -> Void = {}
    private(set) var requests = 0
    private(set) var fixes = 0
    private(set) var accessReads = 0

    func access() -> WeatherAccess {
        accessReads += 1
        return status
    }

    func requestAccess() async -> WeatherAccess {
        requests += 1
        onRequest()
        status = answer
        return status
    }

    func approximateLocation() async throws -> CLLocation {
        fixes += 1
        if let error { throw error }
        return CLLocation(latitude: 51.5, longitude: -0.12)
    }
}

@MainActor
private final class FakeZone: WeatherZoneSource {
    var answer: TimeZone? = TimeZone(identifier: "Europe/London")
    var error: Error?
    private(set) var requests = 0
    private(set) var lastLocation: CLLocation?

    func timeZone(at location: CLLocation) async throws -> TimeZone? {
        requests += 1
        lastLocation = location
        if let error { throw error }
        return answer
    }
}

@MainActor
private final class FakeWeather: WeatherConditionSource {
    var reading = WeatherReading(condition: "clear", date: Date(timeIntervalSince1970: 1_800_000_000))
    var error: Error?
    var creditAnswer = WeatherCredit.fallback
    /// Gives the main actor away a few times before answering, as a real request would.
    var suspends = false
    /// Waits for `release()` before answering.
    var holds = false
    private(set) var held: CheckedContinuation<Void, Never>?
    private(set) var requests = 0
    private(set) var credits = 0

    func release() {
        held?.resume()
        held = nil
    }

    func currentCondition(at location: CLLocation) async throws -> WeatherReading {
        requests += 1
        if suspends { for _ in 0..<5 { await Task.yield() } }
        if holds { await withCheckedContinuation { held = $0 } }
        if let error { throw error }
        return reading
    }

    func credit() async throws -> WeatherCredit {
        credits += 1
        return creditAnswer
    }
}
