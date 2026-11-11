import Foundation

extension Preferences {
    /// Settings → Extras → Companions: the small pixel creatures in quiet corners (brief 76). On by default.
    static let companions = "delight.companions"
}

/// When a companion's rare flourish may come, and whether it may play when it does (brief 76), pure so tests
/// can pin it: each companion's own seeded run of moments 2 to 6 minutes apart; never in the first 20 seconds
/// on a screen, never while another companion is playing (or just after), never in Low Power Mode, under Reduce
/// Motion or Reduce Effects, or while the app isn't active. A tap may play one at once, then not again for a while.
enum CompanionSchedule {
    /// The gap between one companion's flourishes, in seconds.
    static let interval: ClosedRange<TimeInterval> = 120...360
    /// Nothing flourishes this soon after its screen appears (or the app comes back).
    static let settling: TimeInterval = 20
    /// Quiet after any flourish before another companion's may start, so two never run together.
    static let quietAfter: TimeInterval = 6
    /// After a companion plays (a tap or its turn), not again for at least this long.
    static let rest: TimeInterval = 60

    /// The `index`th gap of the run seeded by `seed`.
    static func gap(seed: UInt64, index: Int, demo: Bool = false) -> TimeInterval {
        if demo { return CompanionLaunchOptions.demoInterval }
        return interval.lowerBound + (interval.upperBound - interval.lowerBound) * CompanionRandom.unit(seed, index)
    }

    /// Whether a flourish that comes due at `now` plays.
    /// - Parameters:
    ///   - onScreenSince: when the companion's screen appeared, or the app became active, whichever is later
    ///     (nil while it isn't on screen).
    ///   - busyUntil: when the last flourish of any companion ends.
    ///   - lastPlay: when this companion last played.
    static func mayFlourish(now: Date, onScreenSince: Date?, busyUntil: Date?, lastPlay: Date?, calm: Bool,
                            lowPower: Bool, settling: TimeInterval = settling, quiet: TimeInterval = quietAfter) -> Bool {
        guard let onScreenSince, !calm, !lowPower else { return false }
        guard now.timeIntervalSince(onScreenSince) >= settling else { return false }
        if let busyUntil, now < busyUntil.addingTimeInterval(quiet) { return false }
        if let lastPlay, now.timeIntervalSince(lastPlay) < rest { return false }
        return true
    }

    /// Whether a tap on the companion plays its flourish: on screen, nothing playing, and not tapped into one in
    /// the last minute. The 20 seconds don't apply: someone reached for it.
    static func mayPlayOnTap(now: Date, onScreen: Bool, busyUntil: Date?, lastPlay: Date?, calm: Bool,
                             lowPower: Bool) -> Bool {
        guard onScreen, !calm, !lowPower else { return false }
        if let busyUntil, now < busyUntil { return false }
        if let lastPlay, now.timeIntervalSince(lastPlay) < rest { return false }
        return true
    }
}

/// Debug-only launch arguments for seeing the companions without waiting minutes:
/// `-companionDemo nod` (or `quill`, or `all`) plays that companion's flourish a few seconds after it appears and
/// then every `demoInterval` seconds (with `all`, the companions take turns, half an interval apart, still never two
/// at once), and keeps them moving while the app is in the background so a window can be recorded. Release builds
/// ignore it.
struct CompanionLaunchOptions: Equatable {
    /// Character ids whose flourish is demoed; empty when off.
    var demo: Set<String> = []

    static let demoInterval: TimeInterval = 10
    static let demoSettling: TimeInterval = 3

    static let none = CompanionLaunchOptions(arguments: [])

    static let current: CompanionLaunchOptions = {
        #if DEBUG
        CompanionLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        .none
        #endif
    }()

    init(arguments: [String]) {
        guard let i = arguments.firstIndex(of: "-companionDemo") else { return }
        let value = i + 1 < arguments.count ? arguments[i + 1].lowercased() : "all"
        switch value {
        case "no", "false", "0": demo = []
        case "all", "yes", "true", "1", "": demo = Set(CompanionCharacter.all.map(\.id))
        default: demo = Set(value.split(separator: ",").map(String.init))
        }
    }

    func demos(_ id: String) -> Bool { demo.contains(id) }
}
