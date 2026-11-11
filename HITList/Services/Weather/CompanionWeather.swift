import Foundation
import CoreLocation
import Observation
import OSLog
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The sky for the companions (brief 80): what the weather is doing roughly where the person is, told to
/// `CompanionSkySource` and to nothing else. No forecast, no temperature, no weather on screen.
///
/// - **Off by default, asked once.** Settings → Extras → Weather. Switching it on asks for location while in use, at
///   reduced accuracy. Off, never asked, refused or restricted, or with Companions off: the sky is `unknown` and the
///   app makes no location or weather call. Until the person has switched it on once, Core Location is never touched
///   (the location source is made lazily); after that, Settings reads the permission (no prompt, no fix) to say why
///   it is off.
/// - **Cheap.** One reduced-accuracy fix and one current-conditions request when the app comes to the front and the
///   last observation is older than an hour (and once an hour while it stays in front); never in the background,
///   never while hidden. The last sky is kept in memory only; an observation older than three hours is `unknown`.
/// - **Fail quiet.** No capability, no network, a WeatherKit error, no fix: the sky is `unknown` (or keeps an
///   observation still under three hours old), one line in the unified log (category `weather`), no alert, and no
///   retry until the app next comes forward.
///
/// The location goes from Core Location into WeatherKit's request and is dropped: it is never stored, synced, logged
/// or sent anywhere else.
@MainActor
@Observable
final class CompanionWeather {
    static let shared = CompanionWeather.makeShared()

    /// An observation this fresh is not asked for again.
    static let refreshAfter: TimeInterval = 60 * 60
    /// An observation this old is no longer the sky.
    static let staleAfter: TimeInterval = 3 * 60 * 60

    nonisolated static let log = Logger(subsystem: "com.trammells.hitlist", category: "weather")

    @ObservationIgnored private let makeLocation: () -> any WeatherLocationSource
    @ObservationIgnored private let makeWeather: () -> any WeatherConditionSource
    @ObservationIgnored private var locationSource: (any WeatherLocationSource)?
    @ObservationIgnored private var weatherSource: (any WeatherConditionSource)?
    @ObservationIgnored private let skySource: CompanionSkySource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var hourly: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private let askedForTheRun: Bool

    /// The setting (`Preferences.companionWeather`).
    private(set) var isOn: Bool
    /// The permission as last read; `.notDetermined` until the person has switched Weather on once.
    private(set) var access: WeatherAccess = .notDetermined
    /// Apple's attribution, once asked for (Settings, while on).
    private(set) var credit: WeatherCredit?
    /// The last observation's sky and time, in memory only.
    private(set) var sky: CompanionSky = .unknown
    private(set) var observedAt: Date?
    /// Location fixes and weather requests made this run (the tests count them).
    private(set) var fixes = 0
    private(set) var requests = 0

    /// - Parameters:
    ///   - location, weather: made on first use only, so a run with Weather off never creates either.
    ///   - onForTheRun: on whatever the setting says, without saving it (the demo, `-seedDemoSky`).
    ///   - askedForTheRun: as if the person had been asked (the demo, which has no prompt).
    init(location: @escaping () -> any WeatherLocationSource,
         weather: @escaping () -> any WeatherConditionSource,
         sky: CompanionSkySource,
         defaults: UserDefaults = AppGroup.defaults,
         now: @escaping () -> Date = Date.init,
         onForTheRun: Bool = false,
         askedForTheRun: Bool = false) {
        makeLocation = location
        makeWeather = weather
        skySource = sky
        self.defaults = defaults
        clock = now
        isOn = onForTheRun || (defaults.object(forKey: Preferences.companionWeather) as? Bool ?? Preferences.companionWeatherDefault)
        self.askedForTheRun = onForTheRun || askedForTheRun
    }

    /// Showing the weather: switched on and allowed.
    var isShowing: Bool { isOn && access == .allowed }

    /// Companions themselves (Settings → Extras → Companions, on by default): with them off nobody needs the sky.
    var companionsOn: Bool { defaults.object(forKey: Preferences.companions) as? Bool ?? true }

    /// Whether the person has ever switched Weather on here (and so may have been asked).
    var hasAsked: Bool { askedForTheRun || defaults.bool(forKey: Preferences.companionWeatherAsked) }

    private var location: any WeatherLocationSource {
        if let locationSource { return locationSource }
        let made = makeLocation()
        locationSource = made
        return made
    }

    private var weather: any WeatherConditionSource {
        if let weatherSource { return weatherSource }
        let made = makeWeather()
        weatherSource = made
        return made
    }

    // MARK: - Triggers

    /// Once, at launch: listens for the app coming to the front and going away. Makes no call by itself.
    func start() {
        guard !started else { return }
        started = true
        #if os(iOS)
        let active = UIApplication.didBecomeActiveNotification
        let inactive = UIApplication.willResignActiveNotification
        #else
        let active = NSApplication.didBecomeActiveNotification
        let inactive = NSApplication.didResignActiveNotification
        #endif
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
        observers.append(center.addObserver(forName: inactive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resignedActive() }
        })
        // The demo has no location or network to wait for: its sky shows at once, even in a window opened behind
        // others (`open -g`) for screenshots. A real run waits for the app to come forward.
        if askedForTheRun { Task { await cameForward() } }
    }

    private func becameActive() {
        Task { await cameForward() }
        // While the app stays in front (a Mac can for a whole day), the same rule once an hour.
        hourly?.cancel()
        hourly = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshAfter))
                guard !Task.isCancelled else { return }
                await self?.cameForward()
            }
        }
    }

    private func resignedActive() {
        hourly?.cancel()
        hourly = nil
    }

    /// The app came to the front (or has stayed there another hour): ask for the sky if the last observation is
    /// older than an hour, and only if Weather and Companions are on and the permission allows it.
    func cameForward() async {
        let now = clock()
        expireIfStale(now: now)
        guard isOn, companionsOn else {
            forget()
            return
        }
        access = location.access()
        guard access == .allowed else {
            forget()
            return
        }
        if let observedAt, now.timeIntervalSince(observedAt) < Self.refreshAfter { return }
        await observe()
    }

    /// Companions was switched on or off in Extras.
    func companionsChanged() async {
        if companionsOn { await cameForward() } else { forget() }
    }

    // MARK: - The setting

    /// Switches Weather on or off. On asks for location the first time; refused, the setting stays off and `access`
    /// says why. Returns whether it is on.
    @discardableResult
    func setOn(_ on: Bool) async -> Bool {
        guard on else {
            isOn = false
            defaults.set(false, forKey: Preferences.companionWeather)
            forget()
            return false
        }
        defaults.set(true, forKey: Preferences.companionWeatherAsked)
        var current = location.access()
        if current == .notDetermined { current = await location.requestAccess() }
        access = current
        guard current == .allowed else {
            isOn = false
            defaults.set(false, forKey: Preferences.companionWeather)
            forget()
            Self.log.info("Weather stays off: location \(String(describing: current), privacy: .public)")
            return false
        }
        isOn = true
        defaults.set(true, forKey: Preferences.companionWeather)
        if companionsOn { await observe() }
        return true
    }

    /// Reads the permission again for Settings, without asking or locating. Before the person has ever switched
    /// Weather on, nothing is read: Core Location is not touched.
    func refreshAccess() {
        guard hasAsked else { return }
        access = location.access()
        if access != .allowed, isOn { forget() }
    }

    /// Apple's attribution for Settings, while Weather is on; the fallback (the name and the legal page) meanwhile or
    /// if Apple's answer never comes.
    func loadCredit() async {
        guard isShowing, credit == nil else { return }
        do {
            credit = try await weather.credit()
        } catch {
            Self.log.error("Weather attribution failed: \(Self.describe(error), privacy: .public)")
        }
    }

    // MARK: - Observing

    /// One fix and one request. A failure keeps an observation still under three hours old and is not retried
    /// until the app next comes forward.
    private func observe() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            fixes += 1
            let place = try await location.approximateLocation()
            requests += 1
            let reading = try await weather.currentCondition(at: place)
            // Switched off (or permission lost) while the answer was on its way: it is not the sky.
            guard isOn, access == .allowed, companionsOn else { return }
            let observed = CompanionSky(weatherCondition: reading.condition)
            sky = observed
            observedAt = reading.date
            skySource.set(observed, at: reading.date)
            expireIfStale(now: clock())
        } catch {
            Self.log.error("Weather unavailable: \(Self.describe(error), privacy: .public)")
            expireIfStale(now: clock())
        }
    }

    /// An observation older than three hours is `unknown`.
    private func expireIfStale(now: Date) {
        guard let observedAt, now.timeIntervalSince(observedAt) >= Self.staleAfter else { return }
        forget()
    }

    /// The sky is `unknown`: off, not allowed, stale.
    private func forget() {
        sky = .unknown
        observedAt = nil
        if skySource.sky != .unknown { skySource.clear() }
    }

    /// An error in one line, without anything that could say where the device is.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(String(reflecting: type(of: error))) \(ns.domain) \(ns.code)"
    }
}

extension CompanionWeather {
    /// Core Location and WeatherKit on a device; the demo under `-seedDemoSky` (Debug builds).
    static func makeShared(arguments: [String] = CommandLine.arguments, sky: CompanionSkySource = .shared,
                           defaults: UserDefaults = AppGroup.defaults) -> CompanionWeather {
        #if DEBUG
        if let demo = DemoWeatherSource.requested(arguments: arguments) {
            return CompanionWeather(location: { demo }, weather: { demo }, sky: sky, defaults: defaults,
                                    onForTheRun: demo.permission == .allowed, askedForTheRun: true)
        }
        #endif
        return CompanionWeather(location: { CoreLocationSource() }, weather: { WeatherKitSource() }, sky: sky,
                                defaults: defaults)
    }
}

extension Preferences {
    /// Settings → Extras → Weather (brief 80): the companion dresses for the weather. Off by default; device-local,
    /// like every preference (the permission is the device's).
    static let companionWeather = "pref.companionWeather.enabled"
    static let companionWeatherDefault = false
    /// Set the first time Weather is switched on (when the system may have asked); until then Core Location is
    /// never touched, not even to read the permission.
    static let companionWeatherAsked = "pref.companionWeather.asked"
}
