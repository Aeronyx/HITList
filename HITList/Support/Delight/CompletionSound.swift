import Foundation
import AVFoundation
import OSLog

/// The sound played when a task is completed, chosen in Settings (`DelightSettingsSection`) and stored
/// as its raw value under `delight.soundName` in `AppGroup.defaults`.
///
/// The built-ins live in `HITList/Resources/Sounds/`, 44.1 kHz mono .caf:
/// `bubble` 320 ms: George's own sound (added 2026-10-31), trimmed from a 0.9 s stereo file to its
///   audible 80-400 ms with a 30 ms fade and downmixed to mono. The default.
/// `swish` 220 ms: noise through a bandpass sweeping 1.5 → 6 kHz, generated with numpy, -14 LUFS.
/// Earlier generated sounds (pop, wood, glass, marimba) were removed on 2026-10-31; a stored choice
/// naming one of them falls back to `bubble`.
enum CompletionSound: String, CaseIterable, Identifiable {
    case bubble, swish
    /// The file the user imported (`CustomSoundStore`).
    case custom
    case none

    nonisolated static let key = "delight.soundName"
    static let fallback = CompletionSound.bubble

    static let builtIns: [CompletionSound] = [.bubble, .swish]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bubble: "Bubble"
        case .swish: "Swish"
        case .custom: "Your Sound"
        case .none: "None"
        }
    }

    /// The bundled file, nil for `custom` and `none`.
    var bundleURL: URL? {
        guard Self.builtIns.contains(self) else { return nil }
        return Bundle.main.url(forResource: rawValue, withExtension: "caf")
    }

    /// The stored choice. Unset means `bubble`, unless the sound was switched off with the old
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

    /// The file to play for the stored choice: nil for `none`; `pop` when the custom file is gone.
    static func resolvedURL(in defaults: UserDefaults, custom: CustomSoundStore) -> URL? {
        switch selected(in: defaults) {
        case .none: return nil
        case .custom: return custom.fileURL ?? fallback.bundleURL
        case let sound: return sound.bundleURL
        }
    }
}

/// The user's own completion sound, copied to `<app group container>/Sounds/custom.<ext>` so it
/// survives the original being moved or deleted. Its original file name is kept for Settings.
struct CustomSoundStore {
    nonisolated static let fileNameKey = "delight.customSoundFileName"
    static let maxDuration: TimeInterval = 2
    static let allowedExtensions = ["caf", "wav", "aiff", "aif", "m4a", "mp3"]

    enum ImportError: LocalizedError {
        case unreadable
        case noAccess
        case tooLong(TimeInterval)
        case noContainer

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file isn't a sound HITList can play."
            case .noAccess: "HITList wasn't allowed to open that file."
            case .tooLong(let seconds):
                "That sound is \(String(format: "%.1f", seconds)) seconds long. Choose one of 2 seconds or less."
            case .noContainer: "HITList couldn't find its storage folder."
            }
        }
    }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "delight")

    /// Nil only when the app group container is unavailable.
    let directory: URL?
    let defaults: UserDefaults

    init(directory: URL? = AppGroup.containerURL?.appendingPathComponent("Sounds", isDirectory: true),
         defaults: UserDefaults = AppGroup.defaults) {
        self.directory = directory
        self.defaults = defaults
    }

    /// The imported file, if it is still there.
    var fileURL: URL? {
        guard let directory else { return nil }
        return Self.allowedExtensions.lazy
            .map { directory.appendingPathComponent("custom.\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The name of the file the user picked, while the copy exists.
    var displayName: String? {
        guard fileURL != nil else { return nil }
        return defaults.string(forKey: Self.fileNameKey) ?? fileURL?.lastPathComponent
    }

    static func duration(of url: URL) throws -> TimeInterval {
        do {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.processingFormat.sampleRate
        } catch {
            throw ImportError.unreadable
        }
    }

    /// Checks and copies `source` (already readable: the caller holds any security scope), replacing
    /// any earlier custom sound. Returns the stored copy.
    @discardableResult
    func importSound(from source: URL) throws -> URL {
        guard let directory else { throw ImportError.noContainer }
        let ext = source.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else { throw ImportError.unreadable }
        guard FileManager.default.isReadableFile(atPath: source.path) else { throw ImportError.noAccess }
        let seconds = try Self.duration(of: source)
        guard seconds <= Self.maxDuration else { throw ImportError.tooLong(seconds) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeFiles()
        let destination = directory.appendingPathComponent("custom.\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        defaults.set(source.lastPathComponent, forKey: Self.fileNameKey)
        Self.log.info("Imported custom completion sound (\(seconds, format: .fixed(precision: 2)) s, \(ext, privacy: .public))")
        return destination
    }

    /// Deletes the copy. The caller decides what the selection falls back to.
    func remove() {
        removeFiles()
        defaults.removeObject(forKey: Self.fileNameKey)
    }

    private func removeFiles() {
        guard let directory else { return }
        for ext in Self.allowedExtensions {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("custom.\(ext)"))
        }
    }
}
