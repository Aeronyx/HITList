import Foundation
import Observation
import HITListCore

/// The sky the companions see (round 18). One writer, the weather service (`Services/Weather`, brief 80); the
/// companions only read it (brief 79). `.unknown` until the service has an observation and whenever weather is off.
/// The supervisor's file, so the two briefs meet here without editing each other: neither changes it.
///
/// Round 19 adds the time zone of the place the weather was read for (`timeZone`): the service (brief 83) sets it
/// with each fix and the companions' clock (brief 84) reads `zone` for the hour, so a companion keeps the hours of
/// where the person is. Nothing else in the app reads it: tasks, reminders and lists follow the device's zone.
///
/// Debug: `-companionSky rain` (any `CompanionSky` case) holds the sky at that value for the run, whatever the
/// service says, for screenshots and tests; `-companionZone Asia/Tokyo` does the same for the zone.
@MainActor
@Observable
final class CompanionSkySource {
    static let shared = CompanionSkySource()

    private(set) var sky: CompanionSky = .unknown
    /// When `sky` was last set from an observation; nil while it is `.unknown`.
    private(set) var observedAt: Date?
    /// True while a Debug launch argument holds the sky.
    private(set) var isForced = false
    /// The time zone where the person is, from the last fix; nil until there is one and whenever weather is off.
    private(set) var timeZone: TimeZone?
    /// True while a Debug launch argument holds the zone.
    private(set) var isZoneForced = false

    /// The zone a companion keeps its hours in: where the person is when that is known, else the device's.
    var zone: TimeZone { timeZone ?? .current }

    init(arguments: UserDefaults = .standard) {
        #if DEBUG
        if let forced = arguments.string(forKey: "companionSky"), let sky = CompanionSky(rawValue: forced) {
            self.sky = sky
            observedAt = Date()
            isForced = true
        }
        if let forced = arguments.string(forKey: "companionZone"), let zone = TimeZone(identifier: forced) {
            timeZone = zone
            isZoneForced = true
        }
        #endif
    }

    /// The service has an observation.
    func set(_ sky: CompanionSky, at date: Date = Date()) {
        guard !isForced else { return }
        self.sky = sky
        observedAt = sky == .unknown ? nil : date
    }

    /// The service knows which time zone the person is in (nil: it no longer does).
    func setTimeZone(_ zone: TimeZone?) {
        guard !isZoneForced else { return }
        timeZone = zone
    }

    /// Weather was switched off, lost its permission or went stale.
    func clear() {
        set(.unknown)
        setTimeZone(nil)
    }
}
