import XCTest
import CoreLocation
import HITListCore
@testable import HITList

/// Brief 80: the sky for the companions. Off by default and silent while off; asked once; one fix and one request
/// when the app comes forward and the last observation is over an hour old; an observation over three hours old is
/// `unknown`; failures are quiet and wait for the next time the app comes forward. A fake clock, fake sources.
@MainActor
final class WeatherServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""
    private var location: FakeLocation!
    private var weather: FakeWeather!
    private var sky: CompanionSkySource!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var madeLocation = 0
    private var madeWeather = 0

    override func setUp() {
        fresh()
    }

    private func fresh() {
        suite = "WeatherServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        location = FakeLocation()
        weather = FakeWeather()
        sky = CompanionSkySource(arguments: UserDefaults(suiteName: "WeatherServiceTests.noArguments")!)
        madeLocation = 0
        madeWeather = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func discard() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func service(onForTheRun: Bool = false) -> CompanionWeather {
        CompanionWeather(location: { [unowned self] in madeLocation += 1; return location },
                         weather: { [unowned self] in madeWeather += 1; return weather },
                         sky: sky, defaults: defaults, now: { [unowned self] in now }, onForTheRun: onForTheRun)
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

    // MARK: - Off

    func testOffByDefaultMakesNoLocationOrWeatherCallAtAll() async {
        let service = service()
        XCTAssertFalse(service.isOn)
        XCTAssertFalse(Preferences.companionWeatherDefault)
        await service.cameForward()
        service.refreshAccess()
        await service.loadCredit()
        XCTAssertEqual(madeLocation, 0, "Core Location is never touched while off and never asked")
        XCTAssertEqual(madeWeather, 0, "WeatherKit is never touched while off")
        XCTAssertEqual(sky.sky, .unknown)
        XCTAssertNil(service.credit)
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
    private(set) var requests = 0
    private(set) var fixes = 0
    private(set) var accessReads = 0

    func access() -> WeatherAccess {
        accessReads += 1
        return status
    }

    func requestAccess() async -> WeatherAccess {
        requests += 1
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
