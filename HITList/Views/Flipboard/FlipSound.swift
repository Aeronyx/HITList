import Foundation
import OSLog

/// The light-switch click played on every flip, toggled by "Flip Sound" in the board's `…` menu
/// (`flipboard.sound` in `AppGroup.defaults`, default on). Haptics follow the completion setting
/// (`FlipHaptic`). Played through `CompletionSoundPlayer`, so it uses the ambient category: the silent
/// switch mutes it and it never pauses music.
///
/// `HITList/Resources/Sounds/flip.caf`, 110 ms, 44.1 kHz mono 16-bit, generated with numpy (2026-10-31):
/// - two clicks, at 4 ms and 39 ms (35 ms apart), the second at 0.45 gain: each a 3 ms uniform-noise
///   burst with a 0.8 ms exponential decay, mixed 0.55 dry with a two-pole bandpass resonator at
///   2.5 kHz (Q 6, ×6 gain);
/// - under them a 180 Hz sine "body thump" at 0.18 gain, 2 ms attack and 22 ms exponential decay;
/// - peak-normalised, then soft-limited with `0.708 · tanh(1.6x) / tanh(1.6)` (ceiling -3 dBFS),
///   10 ms linear fade-out. Noise seed 7.
@MainActor
enum FlipSound {
    nonisolated static let key = "flipboard.sound"

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "delight")
    private static let player = CompletionSoundPlayer { Bundle.main.url(forResource: "flip", withExtension: "caf") }
    /// George's `bubble.caf` (the default completion sound), played when a charger fills up.
    private static let chargedPlayer = CompletionSoundPlayer { Bundle.main.url(forResource: "bubble", withExtension: "caf") }

    static var isEnabled: Bool { AppGroup.defaults.object(forKey: key) as? Bool ?? true }

    /// Call when the board appears so the first flip plays without a loading hitch.
    static func prepare() {
        guard isEnabled else { return }
        player.prepare()
        chargedPlayer.prepare()
    }

    static func play() {
        guard isEnabled else { return }
        player.play()
        log.info("Flip sound played")
    }

    /// The last flip of a charger: the bubble, just after the click.
    static func playCharged() {
        guard isEnabled else { return }
        chargedPlayer.play()
        log.info("Charged sound played")
    }
}

/// Which chargers the board last showed full, by task id, with the due date of that full interval:
/// the first time the board shows the next interval (count 0, red) the lamps drain right to left once.
/// Kept per device in `AppGroup.defaults`; it only drives an animation.
@MainActor
enum FlipDrainMemory {
    nonisolated static let key = "flipboard.shownFull"

    private static var entries: [String: Double] {
        get { AppGroup.defaults.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: key) }
    }

    static func recordedDue(for id: UUID) -> Date? {
        entries[id.uuidString].map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    static func recordFull(_ id: UUID, due: Date?) {
        guard let due else { return forget(id) }
        let value = due.timeIntervalSinceReferenceDate
        if entries[id.uuidString] != value { entries[id.uuidString] = value }
    }

    static func forget(_ id: UUID) {
        if entries[id.uuidString] != nil { entries[id.uuidString] = nil }
    }
}
