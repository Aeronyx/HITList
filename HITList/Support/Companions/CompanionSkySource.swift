import Foundation
import Observation
import HITListCore

/// The sky the companions see (round 18). One writer, the weather service (`Services/Weather`, brief 80); the
/// companions only read it (brief 79). `.unknown` until the service has an observation and whenever weather is off.
/// The supervisor's file, so the two briefs meet here without editing each other: neither changes it.
///
/// Debug: `-companionSky rain` (any `CompanionSky` case) holds the sky at that value for the run, whatever the
/// service says, for screenshots and tests.
@MainActor
@Observable
final class CompanionSkySource {
    static let shared = CompanionSkySource()

    private(set) var sky: CompanionSky = .unknown
    /// When `sky` was last set from an observation; nil while it is `.unknown`.
    private(set) var observedAt: Date?
    /// True while a Debug launch argument holds the sky.
    private(set) var isForced = false

    init(arguments: UserDefaults = .standard) {
        #if DEBUG
        if let forced = arguments.string(forKey: "companionSky"), let sky = CompanionSky(rawValue: forced) {
            self.sky = sky
            observedAt = Date()
            isForced = true
        }
        #endif
    }

    /// The service has an observation.
    func set(_ sky: CompanionSky, at date: Date = Date()) {
        guard !isForced else { return }
        self.sky = sky
        observedAt = sky == .unknown ? nil : date
    }

    /// Weather was switched off, lost its permission or went stale.
    func clear() { set(.unknown) }
}
