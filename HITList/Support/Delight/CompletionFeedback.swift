import Foundation
import AVFoundation
import OSLog
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One channel of completion feedback (the sound, or the haptic).
@MainActor
protocol FeedbackOutput: AnyObject {
    /// Loads whatever the first `play()` would otherwise wait for. Cheap after the first call.
    func prepare()
    func play()
}

/// The sound and haptic that confirm a completed task. Each has a toggle in Settings
/// (`DelightSettingsSection`); both default on.
@MainActor
final class CompletionFeedback {
    nonisolated static let soundKey = "delight.sound"
    nonisolated static let hapticsKey = "delight.haptics"

    static let shared = CompletionFeedback()

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "delight")

    private let defaults: UserDefaults
    private let sound: FeedbackOutput
    private let haptics: FeedbackOutput

    /// Nil outputs mean the real sound and haptic (default arguments can't build main-actor objects).
    init(defaults: UserDefaults = AppGroup.defaults, sound: FeedbackOutput? = nil, haptics: FeedbackOutput? = nil) {
        self.defaults = defaults
        self.sound = sound ?? CompletionSound()
        self.haptics = haptics ?? CompletionHaptic()
    }

    var isSoundEnabled: Bool { defaults.object(forKey: Self.soundKey) as? Bool ?? true }
    var areHapticsEnabled: Bool { defaults.object(forKey: Self.hapticsKey) as? Bool ?? true }

    /// Call when a task list appears so the first completion plays without a loading hitch.
    func prepare() {
        if isSoundEnabled { sound.prepare() }
        if areHapticsEnabled { haptics.prepare() }
    }

    func taskCompleted() {
        let playSound = isSoundEnabled, playHaptic = areHapticsEnabled
        if playSound { sound.play() }
        if playHaptic { haptics.play() }
        Self.log.debug("Completion feedback: sound \(playSound), haptic \(playHaptic)")
    }
}

/// `CompletionSound.caf`: 280 ms, generated with numpy (an E6 tick, then a B6 ding 50 ms later; sines
/// with soft harmonics and exponential decay; peak -6 dBFS). Played in the ambient audio category, so
/// the ring/silent switch mutes it and it mixes with music instead of pausing it.
final class CompletionSound: FeedbackOutput {
    /// Several players so completions in quick succession overlap instead of cutting each other off.
    private static let poolSize = 3
    private var players: [AVAudioPlayer] = []
    private var next = 0
    private var didPrepare = false

    func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        guard let url = Bundle.main.url(forResource: "CompletionSound", withExtension: "caf") else {
            Logger(subsystem: "com.trammells.hitlist", category: "delight").error("CompletionSound.caf missing from the bundle")
            return
        }
        players = (0..<Self.poolSize).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
        players.forEach { $0.prepareToPlay() }
    }

    func play() {
        prepare()
        guard !players.isEmpty else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.currentTime = 0
        player.play()
    }
}

/// `.success` notification haptic on iPhone; the trackpad's `.levelChange` tap on the Mac.
final class CompletionHaptic: FeedbackOutput {
    #if os(iOS)
    private var generator: UINotificationFeedbackGenerator?

    func prepare() {
        if generator == nil { generator = UINotificationFeedbackGenerator() }
        generator?.prepare()
    }

    func play() {
        prepare()
        generator?.notificationOccurred(.success)
    }
    #else
    func prepare() {}

    func play() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    #endif
}
