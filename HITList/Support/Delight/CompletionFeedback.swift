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

/// The sound and haptic that confirm a completed task. Settings (`DelightSettingsSection`) picks the
/// sound (`CompletionSound`, default `pop`) and toggles the haptic (default on).
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
        self.sound = sound ?? CompletionSoundPlayer { CompletionSound.resolvedURL(in: defaults) }
        self.haptics = haptics ?? CompletionHaptic()
    }

    /// Off when the sound is `none`. `soundKey` is the original on/off toggle, kept in step by
    /// `CompletionSound.select`.
    var isSoundEnabled: Bool {
        (defaults.object(forKey: Self.soundKey) as? Bool ?? true) && CompletionSound.selected(in: defaults) != .none
    }
    var areHapticsEnabled: Bool { defaults.object(forKey: Self.hapticsKey) as? Bool ?? true }

    /// Call when a task list appears so the first completion plays without a loading hitch.
    func prepare() {
        if isSoundEnabled { sound.prepare() }
        if areHapticsEnabled { haptics.prepare() }
    }

    /// The ▶ button in Settings: plays the selected sound even while it isn't otherwise played.
    func previewSound() {
        sound.play()
    }

    func taskCompleted() {
        let playSound = isSoundEnabled, playHaptic = areHapticsEnabled
        if playSound { sound.play() }
        if playHaptic { haptics.play() }
        Self.log.debug("Completion feedback: sound \(playSound), haptic \(playHaptic)")
    }
}

/// Plays the selected `CompletionSound`, loading it on first use and again whenever the choice (or
/// the custom file) changes. Played in the ambient audio category, so the ring/silent switch mutes it
/// and it mixes with music instead of pausing it.
final class CompletionSoundPlayer: FeedbackOutput {
    /// Several players so completions in quick succession overlap instead of cutting each other off.
    private static let poolSize = 3

    private struct Loaded: Equatable {
        let url: URL
        let modified: Date?
    }

    private let soundURL: () -> URL?
    private var loaded: Loaded?
    private var players: [AVAudioPlayer] = []
    private var next = 0
    private var didSetCategory = false

    /// `soundURL` is asked before every play; nil means silence.
    init(soundURL: @escaping () -> URL?) {
        self.soundURL = soundURL
    }

    func prepare() {
        #if os(iOS)
        if !didSetCategory {
            didSetCategory = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
        }
        #endif
        guard let url = soundURL() else {
            loaded = nil
            players = []
            return
        }
        let current = Loaded(url: url, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
        guard current != loaded else { return }
        loaded = current
        next = 0
        players = (0..<Self.poolSize).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
        players.forEach { $0.prepareToPlay() }
        if players.isEmpty {
            Logger(subsystem: "com.trammells.hitlist", category: "delight").error("Couldn't load completion sound \(url.lastPathComponent, privacy: .public)")
        }
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
