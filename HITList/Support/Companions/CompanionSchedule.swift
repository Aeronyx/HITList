import Foundation

extension Preferences {
    /// Settings → Extras → Companions: the small pixel creatures (brief 76). On by default.
    static let companions = "delight.companions"
    /// When the last flourish played on this device, tapped or not (seconds since the reference date). Kept in
    /// the app group's defaults, never synced, so quitting and reopening never brings the next one sooner (brief 79).
    static let companionLastFlourish = "delight.companions.lastFlourish"
    /// How much more showing time (seconds) must pass before the next flourish may come; kept with the time above.
    static let companionFlourishBudget = "delight.companions.flourishBudget"
}

/// The rules of a companion's day (brief 79), pure so tests can pin them. Mostly still: one small gesture every 45
/// to 120 seconds, never the same one three times running. The flourish is rare: about once in three hours of its
/// screen showing with the app in front, never within 45 minutes of the last one. A tap may play it when none has
/// played for 20 minutes; otherwise it gets a small reply, at most once every ten seconds. Asleep from 22:00 to
/// 07:00, with a stir every few minutes and no flourish.
enum CompanionSchedule {
    /// Between one small gesture and the next, awake.
    static let gestureGap: ClosedRange<TimeInterval> = 45...120
    /// Between stirs, asleep.
    static let stirGap: ClosedRange<TimeInterval> = 360...900
    /// No flourish sooner than this after the last one (tapped or not), on this device.
    static let flourishFloor: TimeInterval = 45 * 60
    /// After the floor, the showing time until the next flourish is random with this mean (memoryless), so the
    /// gap averages three hours of showing: 45 minutes plus 2 h 15.
    static let flourishMeanAfterFloor: TimeInterval = 135 * 60
    /// The longest draw, so a run of bad luck can't leave a companion without a flourish for days of use.
    static let flourishLongest: TimeInterval = 12 * 3600
    /// A tap plays the flourish only if none has played for this long.
    static let tapFlourishRest: TimeInterval = 20 * 60
    /// A tap's small reply, at most once in this long.
    static let answerRest: TimeInterval = 10
    /// Nothing flourishes this soon after its screen appears (or the app comes back).
    static let settling: TimeInterval = 20
    /// Asleep from this hour…
    static let nightStart = 22
    /// …until this one, by the device's clock.
    static let nightEnd = 7
    /// No timer for an event further away than this: nothing is scheduled within the hour, nothing runs.
    static let horizon: TimeInterval = 3600

    static func isNight(hour: Int) -> Bool { hour >= nightStart || hour < nightEnd }

    /// The gap before the next gesture (awake) or stir (asleep), from a number in 0..<1.
    static func gap(asleep: Bool, unit: Double) -> TimeInterval {
        let range = asleep ? stirGap : gestureGap
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    /// Showing time until the next flourish may come, from a number in 0..<1: the floor, then an exponential.
    static func flourishBudget(unit: Double) -> TimeInterval {
        let u = min(max(unit, 0), 0.999_999)
        let tail: TimeInterval = -log(1 - u) * flourishMeanAfterFloor
        return flourishFloor + min(tail, flourishLongest - flourishFloor)
    }

    /// Which gesture comes next, by weight, from a number in 0..<1: never the same one three times running.
    /// - Parameter recent: the gestures played so far, oldest first.
    static func pickGesture(weights: [Int], recent: [Int], unit: Double) -> Int {
        guard weights.count > 1 else { return 0 }
        var allowed = Array(weights.indices)
        if recent.count >= 2, recent[recent.count - 1] == recent[recent.count - 2] {
            allowed.removeAll { $0 == recent[recent.count - 1] }
        }
        let total = allowed.reduce(0) { $0 + max(1, weights[$1]) }
        var pick = Int(Double(total) * min(max(unit, 0), 0.999_999))
        for i in allowed {
            let w = max(1, weights[i])
            if pick < w { return i }
            pick -= w
        }
        return allowed.last ?? 0
    }

    /// Whether the flourish may play now on its own.
    /// - Parameters:
    ///   - onScreenSince: when its screen appeared or the app came back, whichever is later (nil while not on screen).
    ///   - calm: Reduce Effects (gestures, no flourish); `still`: Reduce Motion (nothing moves).
    static func mayFlourish(now: Date, look: CompanionLook, onScreenSince: Date?, acting: Bool, still: Bool,
                            calm: Bool, lowPower: Bool, lastFlourish: Date?) -> Bool {
        guard let onScreenSince, !acting, !still, !calm, !lowPower else { return false }
        guard !look.asleep, look.weather == .plain else { return false }
        guard now.timeIntervalSince(onScreenSince) >= settling else { return false }
        if let lastFlourish, now.timeIntervalSince(lastFlourish) < flourishFloor { return false }
        return true
    }

    /// What a tap or click on the companion does.
    enum TapReply: Equatable {
        /// Its flourish: none for 20 minutes, awake, in plain weather, motion allowed.
        case flourish
        /// A small reply (a look, a blink; asleep, one eye), at most once every ten seconds.
        case answer
        case nothing
    }

    static func tapReply(now: Date, onScreen: Bool, look: CompanionLook, acting: Bool, still: Bool, calm: Bool,
                         lowPower: Bool, lastFlourish: Date?, lastAnswer: Date?) -> TapReply {
        guard onScreen, !still, !acting else { return .nothing }
        let rested = lastFlourish.map { now.timeIntervalSince($0) >= tapFlourishRest } ?? true
        if rested, !look.asleep, look.weather == .plain, !calm, !lowPower { return .flourish }
        if let lastAnswer, now.timeIntervalSince(lastAnswer) < answerRest { return .nothing }
        return .answer
    }
}

/// Debug-only launch arguments for seeing the companions without waiting hours (Release builds ignore them):
/// - `-companion quill`: that companion whatever the theme.
/// - `-companionHour 23`: the hour the night rule reads (23 is asleep, 12 awake).
/// - `-companionPlay flourish` (or `gestures`, `answer`, `all`, or one gesture's name): plays it a few seconds after
///   the companion appears and again every few seconds, and keeps going while the app is in the background, so a
///   window can be recorded. `all` takes turns through every gesture, the reply and the flourish.
///   `-companionDemo` is the same argument's old name.
/// `-companionSky rain` (the sky's own argument, `CompanionSkySource`) dresses it for the weather.
struct CompanionLaunchOptions: Equatable {
    enum Play: Equatable {
        case flourish
        case gestures
        case answer
        case all
        case gesture(String)
    }

    var play: Play?
    var hour: Int?
    var companion: String?

    static let demoSettling: TimeInterval = 3
    /// Between demo acts.
    static let demoInterval: TimeInterval = 4
    /// Between demo flourishes when only the flourish is played.
    static let demoFlourishInterval: TimeInterval = 10

    static let none = CompanionLaunchOptions(arguments: [])

    static let current: CompanionLaunchOptions = {
        #if DEBUG
        CompanionLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        .none
        #endif
    }()

    init(arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name) else { return nil }
            return i + 1 < arguments.count ? arguments[i + 1] : ""
        }
        if let raw = value("-companionPlay") ?? value("-companionDemo") {
            switch raw.lowercased() {
            case "no", "false", "0": play = nil
            case "flourish": play = .flourish
            case "gestures", "gesture": play = .gestures
            case "answer", "tap": play = .answer
            case "all", "yes", "true", "1", "": play = .all
            default: play = .gesture(raw)
            }
        }
        if let raw = value("-companionHour"), let h = Int(raw), (0...23).contains(h) { hour = h }
        if let raw = value("-companion"), !raw.isEmpty { companion = raw.lowercased() }
    }

    var isDemo: Bool { play != nil }
}
