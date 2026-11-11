import Foundation
import HITListCore

extension Preferences {
    /// Settings → Extras → Companions: the small pixel creatures (brief 76). On by default.
    static let companions = "delight.companions"
    /// When the last flourish played on this device, tapped or not (seconds since the reference date). Kept in
    /// the app group's defaults, never synced, so quitting and reopening never brings the next one sooner (brief 79).
    static let companionLastFlourish = "delight.companions.lastFlourish"
    /// How much more showing time (seconds) must pass before the next flourish may come; kept with the time above.
    static let companionFlourishBudget = "delight.companions.flourishBudget"
    /// The same for the next routine (brief 84): showing time left before it, kept across launches, so opening the
    /// app for a minute twenty times plays no more routines than twenty minutes in one go.
    static let companionRoutineBudget = "delight.companions.routineBudget"
    /// When the last routine played on this device (seconds since the reference date), for the tap's three minutes.
    static let companionLastRoutine = "delight.companions.lastRoutine"
    /// Which routine that was ("nod.swingAbout"), so the next one is never the same.
    static let companionLastRoutineName = "delight.companions.lastRoutineName"
}

/// The rules of a companion's day (briefs 79 and 84), pure so tests can pin them. Still by default. A flicker (one
/// blink, one swing of a foot) every 40 to 110 seconds, never the same one three times running. A routine (a few
/// seconds of small moves) after 5 to 12 minutes of showing time since the last, never the same one twice running;
/// while a sky holds, its own routine takes about every other one. The flourish is rare: about once in three hours of
/// its screen showing with the app in front, never within 45 minutes of the last one. A tap may play the flourish
/// when none has played for 20 minutes, else a routine when none has played for three, else a small reply at most
/// once every ten seconds. Asleep from 22:00 to 07:00 where the person is, with a stir every few minutes and nothing
/// more. Reduce Motion: nothing moves. Reduce Effects and Low Power Mode: flickers only.
enum CompanionSchedule {
    /// Between one flicker and the next, awake. (Brief 84; was one gesture every 45 to 120 s.)
    static let flickerGap: ClosedRange<TimeInterval> = 40...110
    /// Showing time between one routine and the next (brief 84), at random.
    static let routineGap: ClosedRange<TimeInterval> = 300...720
    /// A tap plays a routine only if none has played for this long (and the flourish isn't the tap's).
    static let tapRoutineRest: TimeInterval = 3 * 60
    /// While a sky holds, the chance that the next routine is the sky's own when the last one wasn't (and that it
    /// is again when it was, if the sky has another): about every other routine is the sky's.
    static let skyShare = 0.8
    /// While a sky holds, the chance that a flicker is one of the sky's own (a drip, a bead of sweat), brief 91.
    static let skyFlickerShare = 0.5
    /// Showing time in the snow before the pile grows one frame deeper (brief 91), at random.
    static let snowGap: ClosedRange<TimeInterval> = 480...840
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

    /// The gap before the next flicker (awake) or stir (asleep), from a number in 0..<1.
    static func gap(asleep: Bool, unit: Double) -> TimeInterval {
        let range: ClosedRange<TimeInterval> = asleep ? stirGap : flickerGap
        let span: TimeInterval = range.upperBound - range.lowerBound
        let extra: TimeInterval = span * unit
        return range.lowerBound + extra
    }

    /// Showing time until the next flourish may come, from a number in 0..<1: the floor, then an exponential.
    static func flourishBudget(unit: Double) -> TimeInterval {
        let u: Double = min(max(unit, 0), 0.999_999)
        let survival: Double = 1 - u
        let tail: TimeInterval = -log(survival) * flourishMeanAfterFloor
        let longestTail: TimeInterval = flourishLongest - flourishFloor
        return flourishFloor + min(tail, longestTail)
    }

    /// Showing time in the snow until the pile grows, from a number in 0..<1: anywhere in `snowGap`.
    static func snowBudget(unit: Double) -> TimeInterval {
        let u: Double = min(max(unit, 0), 1)
        let span: TimeInterval = snowGap.upperBound - snowGap.lowerBound
        let extra: TimeInterval = span * u
        return snowGap.lowerBound + extra
    }

    /// Whether a gesture or routine of `sky` belongs under the sky that holds (`.rain` also in a storm).
    static func belongs(_ sky: CompanionSky, under holding: CompanionSky) -> Bool {
        sky == holding || (sky == .rain && holding == .storm)
    }

    /// Showing time until the next routine may come, from a number in 0..<1: anywhere in `routineGap`.
    static func routineBudget(unit: Double) -> TimeInterval {
        let u: Double = min(max(unit, 0), 1)
        let span: TimeInterval = routineGap.upperBound - routineGap.lowerBound
        let extra: TimeInterval = span * u
        return routineGap.lowerBound + extra
    }

    /// Which routine comes next: one of the sky's own (`weather`, indices into the mode's routines) about every other
    /// time while it has any, else an everyday one (`everyday`), by weight; never `last` (the one that played
    /// before). Nil when nothing but `last` could play. `unit` picks the pool, `pick` the routine in it.
    static func pickRoutine(everyday: [Int], weather: [Int], weights: [Int], last: Int?, unit: Double,
                            pick: Double) -> Int? {
        let ordinary = everyday.filter { $0 != last }
        let own = weather.filter { $0 != last }
        let lastWasOwn = last.map { weather.contains($0) } ?? false
        let share: Double = lastWasOwn ? 1 - skyShare : skyShare
        let pool: [Int]
        if own.isEmpty { pool = ordinary } else if ordinary.isEmpty { pool = own } else { pool = unit < share ? own : ordinary }
        guard !pool.isEmpty else { return nil }
        var total = 0
        for i in pool { total += max(1, weights.indices.contains(i) ? weights[i] : 1) }
        let u: Double = min(max(pick, 0), 0.999_999)
        let scaled: Double = Double(total) * u
        var left: Int = Int(scaled)
        for i in pool {
            let w = max(1, weights.indices.contains(i) ? weights[i] : 1)
            if left < w { return i }
            left -= w
        }
        return pool.last
    }

    /// Which gesture comes next, by weight, from a number in 0..<1: never the same one three times running.
    /// - Parameter recent: the gestures played so far, oldest first.
    static func pickGesture(weights: [Int], recent: [Int], unit: Double) -> Int {
        guard weights.count > 1 else { return 0 }
        var allowed = Array(weights.indices)
        if recent.count >= 2, recent[recent.count - 1] == recent[recent.count - 2] {
            allowed.removeAll { $0 == recent[recent.count - 1] }
        }
        var total = 0
        for i in allowed { total += max(1, weights[i]) }
        let u: Double = min(max(unit, 0), 0.999_999)
        let scaled: Double = Double(total) * u
        var pick: Int = Int(scaled)
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
    ///   - plainStill: the still frame is the plain `rest` (brief 91: a hot day without a heat still is one), so
    ///     the flourish can start and end on it.
    static func mayFlourish(now: Date, look: CompanionLook, onScreenSince: Date?, acting: Bool, still: Bool,
                            calm: Bool, lowPower: Bool, lastFlourish: Date?, plainStill: Bool = true) -> Bool {
        guard let onScreenSince, !acting, !still, !calm, !lowPower else { return false }
        guard !look.asleep, look.flourishes, plainStill else { return false }
        guard now.timeIntervalSince(onScreenSince) >= settling else { return false }
        if let lastFlourish, now.timeIntervalSince(lastFlourish) < flourishFloor { return false }
        return true
    }

    /// What a tap or click on the companion does.
    enum TapReply: Equatable {
        /// Its flourish: none for 20 minutes, awake, in plain weather, motion allowed.
        case flourish
        /// A routine (brief 84): no flourish due, none for three minutes, awake, effects allowed.
        case routine
        /// A small reply (a look, a blink; asleep, one eye), at most once every ten seconds.
        case answer
        case nothing
    }

    /// - Parameters:
    ///   - routines: whether it has a routine it could play now (a character with none answers instead).
    static func tapReply(now: Date, onScreen: Bool, look: CompanionLook, acting: Bool, still: Bool, calm: Bool,
                         lowPower: Bool, lastFlourish: Date?, lastAnswer: Date?, lastRoutine: Date? = nil,
                         routines: Bool = false, plainStill: Bool = true) -> TapReply {
        guard onScreen, !still, !acting else { return .nothing }
        let rested = lastFlourish.map { now.timeIntervalSince($0) >= tapFlourishRest } ?? true
        if rested, !look.asleep, look.flourishes, plainStill, !calm, !lowPower { return .flourish }
        let routineRested = lastRoutine.map { now.timeIntervalSince($0) >= tapRoutineRest } ?? true
        if routines, routineRested, !look.asleep, !calm, !lowPower { return .routine }
        if let lastAnswer, now.timeIntervalSince(lastAnswer) < answerRest { return .nothing }
        return .answer
    }

    /// Whether a routine may play now on its own: awake, motion and effects allowed, on screen past its first 20
    /// seconds, nothing else playing.
    static func mayRoutine(now: Date, look: CompanionLook, onScreenSince: Date?, acting: Bool, still: Bool, calm: Bool,
                           lowPower: Bool) -> Bool {
        guard let onScreenSince, !acting, !still, !calm, !lowPower, !look.asleep else { return false }
        return now.timeIntervalSince(onScreenSince) >= settling
    }
}

/// Debug-only launch arguments for seeing the companions without waiting hours (Release builds ignore them):
/// - `-companion quill`: that companion whatever the theme.
/// - `-companionHour 23`: the hour the night rule reads (23 is asleep, 12 awake).
/// - `-companionPlay flourish` (or `gestures`, `answer`, `all`, or one gesture's name): plays it a few seconds after
///   the companion appears and again every few seconds, and keeps going while the app is in the background, so a
///   window can be recorded. `all` takes turns through every gesture, every routine it may play now, the reply and
///   the flourish. `-companionPlay routine` takes turns through the routines it may play now (the everyday ones and
///   the sky's), `-companionPlay routine:<name>` plays that one again and again. `-companionDemo` is the old name.
/// `-companionSky rain` and `-companionZone Asia/Tokyo` (`CompanionSkySource`'s own) force the sky and the zone;
/// `-companionSnowDepth 2` piles the snow that deep (beside `-companionSky snow`).
struct CompanionLaunchOptions: Equatable {
    enum Play: Equatable {
        case flourish
        case gestures
        case answer
        case all
        case gesture(String)
        /// Every routine it may play now, in turn.
        case routines
        /// One routine, by name.
        case routine(String)
    }

    var play: Play?
    var hour: Int?
    var companion: String?
    /// `-companionSnowDepth 2`: the snow piled that many frames deep whenever it snows, and it doesn't grow.
    var snowDepth: Int?

    static let demoSettling: TimeInterval = 3
    /// Between demo acts.
    static let demoInterval: TimeInterval = 4
    /// After a demo routine or flourish ends, before the next act.
    static let demoQuiet: TimeInterval = 3
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
            case "routine", "routines": play = .routines
            default:
                if raw.lowercased().hasPrefix("routine:") {
                    play = .routine(String(raw.dropFirst("routine:".count)))
                } else {
                    play = .gesture(raw)
                }
            }
        }
        if let raw = value("-companionHour"), let h = Int(raw), (0...23).contains(h) { hour = h }
        if let raw = value("-companion"), !raw.isEmpty { companion = raw.lowercased() }
        if let raw = value("-companionSnowDepth"), let depth = Int(raw), depth >= 0 { snowDepth = depth }
    }

    var isDemo: Bool { play != nil }
}
