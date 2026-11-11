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

/// The sky and the local time for the companions (briefs 80, 83): what the weather is doing roughly where the person
/// is and which time zone that place is in, told to `CompanionSkySource` and to nothing else. No forecast, no
/// temperature, no place or weather on screen; tasks, reminders and lists never read the zone (they follow the
/// device's).
///
/// - **On by default, asked once** (brief 83). Settings → Extras → Weather is on for everyone who never switched it
///   off (a key never written reads on). The system's question (location while in use, reduced accuracy) comes once,
///   at the first launch (`LaunchLocationQuestion`), or from the switch for someone who refused and switches it on
///   again. Off, never asked, refused or restricted, or with Companions off: the sky is `unknown` and the app makes no
///   location or weather call. Until the question has been asked, Core Location is never touched (the location
///   source is made lazily); after that, Settings reads the permission (no prompt, no fix) to say why it is off.
/// - **Cheap.** One reduced-accuracy fix, one current-conditions request and one reverse geocode (for the zone) when
///   the app comes to the front and the last observation is older than an hour (and once an hour while it stays in
///   front); never in the background, never while hidden. The last sky and zone are kept in memory only; an
///   observation older than three hours is `unknown`, and a zone older than three hours is nil.
/// - **Fail quiet.** No capability, no network, a WeatherKit error, no fix: the sky is `unknown` (or keeps an
///   observation still under three hours old), one line in the unified log (category `weather`), no alert, and no
///   retry until the app next comes forward.
///
/// The location goes from Core Location into WeatherKit's request and Apple's geocoder and is dropped: it is never
/// stored, synced, logged or sent anywhere else.
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
    @ObservationIgnored private let makeZone: () -> any WeatherZoneSource
    @ObservationIgnored private var zoneSource: (any WeatherZoneSource)?
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
    @ObservationIgnored private let run: LaunchLocationQuestion.Run
    @ObservationIgnored private let screen: @MainActor () -> (inFront: Bool, clear: Bool)
    @ObservationIgnored private var question: Task<Void, Never>?
    /// The first launch's question is settled for this run (asked, or not to be asked).
    @ObservationIgnored private var questionSettled = false

    /// After the first scene is active, the first screen settles this long before the question may show.
    static let questionSettle: Duration = .seconds(2)
    /// While something covers the first screen, it looks again this often.
    static let questionRetry: Duration = .milliseconds(1500)

    /// The setting (`Preferences.companionWeather`): on unless someone switched it off.
    private(set) var isOn: Bool
    /// The permission as last read; `.notDetermined` until the person has switched Weather on once.
    private(set) var access: WeatherAccess = .notDetermined
    /// Apple's attribution, once asked for (Settings, while on).
    private(set) var credit: WeatherCredit?
    /// The last observation's sky and time, in memory only.
    private(set) var sky: CompanionSky = .unknown
    private(set) var observedAt: Date?
    /// The time zone of the last fix's place, in memory only; nil when unknown. `zoneAt` is when it was found.
    private(set) var zone: TimeZone?
    @ObservationIgnored private var zoneAt: Date?
    /// Location fixes and weather requests made this run (the tests count them).
    private(set) var fixes = 0
    private(set) var requests = 0
    private(set) var geocodes = 0

    /// - Parameters:
    ///   - location, weather, zone: made on first use only, so a run with Weather off never creates any.
    ///   - onForTheRun: on whatever the setting says, without saving it (the demo, `-seedDemoSky`).
    ///   - offForTheRun: off whatever the setting says, without saving it (the refused demo, as after a refusal).
    ///   - askedForTheRun: as if the person had been asked (the demo, which has no prompt).
    ///   - launch, screen: the run and what is on screen, for the first launch's question (`LaunchLocationQuestion`).
    init(location: @escaping () -> any WeatherLocationSource,
         weather: @escaping () -> any WeatherConditionSource,
         zone: @escaping () -> any WeatherZoneSource,
         sky: CompanionSkySource,
         defaults: UserDefaults = AppGroup.defaults,
         now: @escaping () -> Date = Date.init,
         onForTheRun: Bool = false,
         offForTheRun: Bool = false,
         askedForTheRun: Bool = false,
         launch: LaunchLocationQuestion.Run = .current,
         screen: @escaping @MainActor () -> (inFront: Bool, clear: Bool) = { @MainActor in
             (LaunchScreenProbe.isInFront(), LaunchScreenProbe.isScreenClear())
         }) {
        makeLocation = location
        makeWeather = weather
        makeZone = zone
        skySource = sky
        self.defaults = defaults
        clock = now
        let stored = defaults.object(forKey: Preferences.companionWeather) as? Bool ?? Preferences.companionWeatherDefault
        isOn = onForTheRun || (!offForTheRun && stored)
        self.askedForTheRun = onForTheRun || offForTheRun || askedForTheRun
        run = launch
        self.screen = screen
    }

    /// Showing the weather: switched on and allowed.
    var isShowing: Bool { isOn && access == .allowed }

    /// Companions themselves (Settings → Extras → Companions, on by default): with them off nobody needs the sky.
    var companionsOn: Bool { defaults.object(forKey: Preferences.companions) as? Bool ?? true }

    /// Whether the system's question may have been shown here: by the switch, or at a launch.
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

    private var zones: any WeatherZoneSource {
        if let zoneSource { return zoneSource }
        let made = makeZone()
        zoneSource = made
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
        askAtLaunchWhenSettled()
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
        question?.cancel()
        question = nil
    }

    // MARK: - The first launch's question (brief 83)

    /// The app is in front: once its first screen has settled, ask if `LaunchLocationQuestion` says so, looking
    /// again while something covers the screen. Going to the background stops looking until it comes back.
    private func askAtLaunchWhenSettled() {
        guard !questionSettled, question == nil else { return }
        question = Task { [weak self] in
            try? await Task.sleep(for: Self.questionSettle)
            while !Task.isCancelled {
                guard let self else { return }
                let decision = await self.considerAskingAtLaunch()
                guard decision == .later else { break }
                try? await Task.sleep(for: Self.questionRetry)
            }
            self?.question = nil
        }
    }

    /// Looks once: asks now if everything says so (and then starts the weather, or switches it off if refused).
    /// `.later` while the app is behind or its screen is covered; `.never` for the rest of the run.
    @discardableResult
    func considerAskingAtLaunch() async -> LaunchLocationQuestion.Decision {
        guard !questionSettled else { return .never }
        let shown = screen()
        let situation = LaunchLocationQuestion.Situation(build: run.build, arguments: run.arguments,
                                                         isTestHost: run.isTestHost, companionsOn: companionsOn,
                                                         weatherOn: isOn, asked: hasAsked,
                                                         isInFront: shown.inFront, isScreenClear: shown.clear)
        let decision = LaunchLocationQuestion.decide(situation) { location.access() }
        switch decision {
        case .later: return .later
        case .never:
            questionSettled = true
            return .never
        case .answered:
            questionSettled = true
            defaults.set(true, forKey: Preferences.companionWeatherAsked)
            await cameForward()
            return .answered
        case .ask:
            questionSettled = true
            await askAtLaunch()
            return .ask
        }
    }

    /// The system's question, once. Marked asked before it shows, so a launch killed meanwhile never asks twice.
    /// Allowed: the weather starts. Refused: the switch goes off (as when refused from the switch) and Extras says
    /// why, with the way to the system's settings.
    private func askAtLaunch() async {
        defaults.set(true, forKey: Preferences.companionWeatherAsked)
        Self.log.info("Location question at launch: asking")
        let answer = await location.requestAccess()
        access = answer
        Self.log.info("Location question at launch: \(String(describing: answer), privacy: .public)")
        guard answer == .allowed else {
            if answer.isRefused {
                isOn = false
                defaults.set(false, forKey: Preferences.companionWeather)
            }
            forget()
            return
        }
        await cameForward()
    }

    /// The app came to the front (or has stayed there another hour): ask for the sky if the last observation is
    /// older than an hour, and only if Weather and Companions are on and the permission allows it.
    func cameForward() async {
        let now = clock()
        expireIfStale(now: now)
        // Never asked: nothing to read and nothing to ask for (the question is the launch's, or the switch's).
        guard isOn, companionsOn, hasAsked else {
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

    /// One fix, one weather request and one geocode for the zone. A failure keeps an observation still under three
    /// hours old and is not retried until the app next comes forward; a zone that cannot be found is nil.
    private func observe() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        let place: CLLocation
        do {
            fixes += 1
            place = try await location.approximateLocation()
        } catch {
            Self.log.error("Weather unavailable: \(Self.describe(error), privacy: .public)")
            expireIfStale(now: clock())
            return
        }
        var reading: WeatherReading?
        do {
            requests += 1
            reading = try await weather.currentCondition(at: place)
        } catch {
            Self.log.error("Weather unavailable: \(Self.describe(error), privacy: .public)")
        }
        let found = await findZone(at: place)
        // Switched off (or permission lost) while the answers were on their way: they are not the sky.
        guard isOn, access == .allowed, companionsOn else { return }
        let now = clock()
        zone = found
        zoneAt = found == nil ? nil : now
        skySource.setTimeZone(found)
        if let reading {
            let observed = CompanionSky(weatherCondition: reading.condition)
            sky = observed
            observedAt = reading.date
            skySource.set(observed, at: reading.date)
            Self.log.info("Weather observed: \(observed.rawValue, privacy: .public) (\(reading.condition, privacy: .public))")
        }
        expireIfStale(now: now)
    }

    /// The fix's time zone, by Apple's geocoder; nil (one log line) when it cannot be found. The zone's name says
    /// roughly where the device is, so only a Debug build writes it to the log.
    private func findZone(at place: CLLocation) async -> TimeZone? {
        geocodes += 1
        do {
            let found = try await zones.timeZone(at: place)
            #if DEBUG
            Self.log.info("Weather zone: \(found?.identifier ?? "none", privacy: .public)")
            #else
            Self.log.info("Weather zone: \(found == nil ? "none" : found == TimeZone.current ? "the device's" : "another", privacy: .public)")
            #endif
            return found
        } catch {
            Self.log.error("Weather zone unavailable: \(Self.describe(error), privacy: .public)")
            return nil
        }
    }

    /// An observation older than three hours is `unknown`; a zone older than three hours is nil.
    private func expireIfStale(now: Date) {
        if let observedAt, now.timeIntervalSince(observedAt) >= Self.staleAfter {
            forget()
            return
        }
        if let zoneAt, now.timeIntervalSince(zoneAt) >= Self.staleAfter {
            zone = nil
            self.zoneAt = nil
            skySource.setTimeZone(nil)
        }
    }

    /// The sky is `unknown` and the zone nil: off, not allowed, stale.
    private func forget() {
        sky = .unknown
        observedAt = nil
        zone = nil
        zoneAt = nil
        if skySource.sky != .unknown || skySource.timeZone != nil { skySource.clear() }
    }

    /// An error in one line, without anything that could say where the device is.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(String(reflecting: type(of: error))) \(ns.domain) \(ns.code)"
    }
}

extension CompanionWeather {
    /// Core Location, WeatherKit and Apple's geocoder on a device; the demo under `-seedDemoSky` (Debug builds).
    static func makeShared(arguments: [String] = CommandLine.arguments, sky: CompanionSkySource = .shared,
                           defaults: UserDefaults = AppGroup.defaults) -> CompanionWeather {
        #if DEBUG
        if let demo = DemoWeatherSource.requested(arguments: arguments) {
            return CompanionWeather(location: { demo }, weather: { demo }, zone: { demo }, sky: sky, defaults: defaults,
                                    onForTheRun: demo.permission == .allowed, offForTheRun: demo.permission != .allowed,
                                    askedForTheRun: true)
        }
        #endif
        return CompanionWeather(location: { CoreLocationSource() }, weather: { WeatherKitSource() },
                                zone: { GeocoderZoneSource() }, sky: sky, defaults: defaults)
    }
}

extension Preferences {
    /// Settings → Extras → Weather (briefs 80, 83): the companion keeps local time and dresses for the weather. On
    /// by default since 0.9.3: a key never written reads on, so someone who switched it off in 0.9.2 keeps it off and
    /// everyone else is asked once at their next launch. Device-local, like every preference (the permission is the
    /// device's).
    static let companionWeather = "pref.companionWeather.enabled"
    static let companionWeatherDefault = true
    /// Set when the system's question may have been shown (the switch, or the first launch's question), before it
    /// is; until then Core Location is never touched, not even to read the permission.
    static let companionWeatherAsked = "pref.companionWeather.asked"
}
