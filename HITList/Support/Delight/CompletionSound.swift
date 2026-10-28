import Foundation

/// The sound played when a task is completed, chosen in Settings (`DelightSettingsSection`) and stored
/// as its raw value under `delight.soundName` in `AppGroup.defaults`.
///
/// The built-ins live in `HITList/Resources/Sounds/`: 44.1 kHz mono .caf generated with numpy and
/// `afconvert`, each normalised to -14 LUFS (K-weighted, ungated) and soft-limited under -1 dBFS.
/// `pop` 140 ms: bandpassed noise burst sliding 1.6 kHz → 500 Hz over a damped sine thunk 900 → 350 Hz.
/// `wood` 300 ms: A5 bar with free-bar partials (1, 2.76, 5.4) and a noise mallet knock.
/// `glass` 320 ms: C7 bell, inharmonic partials (1, 2.32, 4.25, 6.63), brightest fastest.
/// `swish` 220 ms: noise through a bandpass sweeping 1.5 → 6 kHz.
/// `marimba` 340 ms: C5 then G5 90 ms later, fundamental plus tuned 4th partial.
enum CompletionSound: String, CaseIterable, Identifiable {
    case pop, wood, glass, swish, marimba
    case none

    nonisolated static let key = "delight.soundName"
    static let fallback = CompletionSound.pop

    static let builtIns: [CompletionSound] = [.pop, .wood, .glass, .swish, .marimba]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pop: "Pop"
        case .wood: "Wood"
        case .glass: "Glass"
        case .swish: "Swish"
        case .marimba: "Marimba"
        case .none: "None"
        }
    }

    /// The bundled file, nil for `none`.
    var bundleURL: URL? {
        guard Self.builtIns.contains(self) else { return nil }
        return Bundle.main.url(forResource: rawValue, withExtension: "caf")
    }

    /// The stored choice. Unset means `pop`, unless the sound was switched off with the old
    /// on/off toggle (`CompletionFeedback.soundKey`), which reads as `none`.
    static func selected(in defaults: UserDefaults) -> CompletionSound {
        if let raw = defaults.string(forKey: key) { return CompletionSound(rawValue: raw) ?? fallback }
        return defaults.object(forKey: CompletionFeedback.soundKey) as? Bool == false ? .none : fallback
    }

    static func select(_ sound: CompletionSound, in defaults: UserDefaults) {
        defaults.set(sound.rawValue, forKey: key)
        // Keep the old toggle in step so a picked sound is never silenced by it.
        defaults.set(sound != .none, forKey: CompletionFeedback.soundKey)
    }

    /// The file to play for the stored choice: nil for `none`.
    static func resolvedURL(in defaults: UserDefaults) -> URL? {
        selected(in: defaults).bundleURL
    }
}
