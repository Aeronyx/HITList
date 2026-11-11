import Foundation
import Observation
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Keeps every companion's life in one place (briefs 76, 79, 84 and 100): which is on screen, where and since when,
/// how it is dressed, what it is doing, and the one timer that wakes for the next thing it does. Between acts a
/// companion is a still picture and nothing runs; the timer sleeps until the next idle (a flicker or a little loop,
/// 6 to 36 seconds after the last one ends, the first 2 to 6 seconds after it comes on screen), routine (every 3 to 8
/// minutes of showing time) or the rare flourish, and only while a companion that may move is on screen and the app
/// is in front. The drawing runs in each perch's `TimelineView` for the length of an act and stops. The rules are
/// `CompanionSchedule`'s; the frames are `CompanionClock`'s.
///
/// The flourish's and the routine's clocks are kept on the device (`Preferences.companionLastFlourish`,
/// `.companionFlourishBudget`, `.companionRoutineBudget`, `.companionLastRoutine`, `.companionLastRoutineName`): each
/// budget is showing time, spent only while a companion that could play it is on screen, and saved whenever it stops
/// being spent, so quitting and reopening never brings one sooner.
///
/// Snow piles up on it (brief 91): every 8 to 14 minutes of showing time in the snow its still frame is one frame
/// deeper (`Mode.snowDeep`), kept in memory, until a shake-off; it starts again when the sky leaves snow, at a new
/// launch and when night and day change over.
///
/// Awake or asleep, and the weather, are decided while nobody is looking: when a companion comes on screen, and
/// when the app goes to the background or comes back. Night and day are read in the zone where the person is
/// (`CompanionSkySource.shared.zone`). A companion on screen across 22:00 falls asleep the next time the app is left,
/// with no transition.
@MainActor
@Observable
final class CompanionDirector {
    static let shared = CompanionDirector()

    /// The companions on screen now, by character id.
    private(set) var stages: [String: CompanionStage] = [:]
    /// Whether the timer is waiting (tests check it stops when nothing may move).
    var isWaiting: Bool { nextMoment != nil }
    /// The moment the timer is waiting for.
    @ObservationIgnored private(set) var nextMoment: Date?
    private(set) var isAppActive: Bool
    private(set) var isLowPower: Bool

    @ObservationIgnored private var instances: [String: Int] = [:]
    /// Reduce Motion: a still picture. Reduce Effects: flickers only.
    @ObservationIgnored private var still: [String: Bool] = [:]
    @ObservationIgnored private var calm: [String: Bool] = [:]
    @ObservationIgnored private var activeSince: [String: Date] = [:]
    /// When each companion's next idle comes.
    @ObservationIgnored private var nextIdle: [String: Date] = [:]
    /// The idle each played last, and in which place and look (its index means nothing in another mode).
    @ObservationIgnored private var lastIdle: [String: (idle: CompanionSchedule.Idle, place: CompanionPlace, asleep: Bool)] = [:]
    /// A demo's turns so far.
    @ObservationIgnored private var recent: [String: [Int]] = [:]
    @ObservationIgnored private var lastAnswer: [String: Date] = [:]
    /// Which way each companion faced when it last left the screen (Quill keeps its side).
    @ObservationIgnored private var turned: [String: Bool] = [:]
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var draws = 0
    @ObservationIgnored let seed: UInt64
    @ObservationIgnored private let launch: CompanionLaunchOptions
    /// False in tests, which call `fire(now:)` themselves.
    @ObservationIgnored private let runsTimer: Bool
    /// The characters it can direct, by id.
    @ObservationIgnored private let cast: [CompanionCharacter]
    /// The kept times; nil keeps nothing (tests that don't care).
    @ObservationIgnored private let defaults: UserDefaults?
    /// The zone night and day are read in (`CompanionSkySource.shared.zone`: where the person is, else the device's).
    @ObservationIgnored private let zone: () -> TimeZone
    /// What the sky is doing (`CompanionSkySource.shared`).
    @ObservationIgnored private let sky: () -> CompanionSky

    // The flourish's showing-time budget: what is left, and since when it has been spent (nil while it isn't).
    @ObservationIgnored private(set) var budget: TimeInterval
    @ObservationIgnored private var spendingSince: Date?
    @ObservationIgnored private(set) var lastFlourish: Date?
    // The routine's, the same way (brief 84).
    @ObservationIgnored private(set) var routineBudget: TimeInterval
    @ObservationIgnored private var routineSpendingSince: Date?
    @ObservationIgnored private(set) var lastRoutine: Date?
    /// "nod.swingAbout": the last routine played, never the next one.
    @ObservationIgnored private(set) var lastRoutineName: String?
    // Brief 91, snow piling up, per companion and in memory only: how deep (and in which look) it piled when it last
    // left the screen, and the showing time left before it grows another frame, spent since when.
    @ObservationIgnored private var pile: [String: (depth: Int, asleep: Bool)] = [:]
    @ObservationIgnored private var snowLeft: [String: TimeInterval] = [:]
    @ObservationIgnored private var snowSince: [String: Date] = [:]

    init(seed: UInt64 = .random(in: .min ... .max), launch: CompanionLaunchOptions = .current, observeSystem: Bool = true,
         cast: [CompanionCharacter] = CompanionCharacter.all, defaults: UserDefaults? = AppGroup.defaults,
         zone: (() -> TimeZone)? = nil, sky: (() -> CompanionSky)? = nil) {
        self.seed = seed
        self.launch = launch
        self.cast = cast
        self.defaults = defaults
        self.zone = zone ?? { CompanionSkySource.shared.zone }
        self.sky = sky ?? { CompanionSkySource.shared.sky }
        runsTimer = observeSystem
        isLowPower = observeSystem && ProcessInfo.processInfo.isLowPowerModeEnabled
        // A demo (Debug only) keeps going in the background, so a window can be recorded without taking the front.
        #if os(iOS)
        isAppActive = !observeSystem || launch.isDemo || UIApplication.shared.applicationState == .active
        #else
        isAppActive = !observeSystem || launch.isDemo || NSApplication.shared.isActive
        #endif
        let keptLast = defaults?.object(forKey: Preferences.companionLastFlourish) as? Double
        lastFlourish = keptLast.map { Date(timeIntervalSinceReferenceDate: $0) }
        let keptBudget = defaults?.object(forKey: Preferences.companionFlourishBudget) as? Double
        budget = keptBudget.map { max(0, $0) } ?? 0
        let keptRoutine = defaults?.object(forKey: Preferences.companionLastRoutine) as? Double
        lastRoutine = keptRoutine.map { Date(timeIntervalSinceReferenceDate: $0) }
        lastRoutineName = defaults?.string(forKey: Preferences.companionLastRoutineName)
        let keptRoutineBudget = defaults?.object(forKey: Preferences.companionRoutineBudget) as? Double
        routineBudget = keptRoutineBudget.map { max(0, $0) } ?? 0
        if keptBudget == nil { budget = CompanionSchedule.flourishBudget(unit: unit()) }
        if keptRoutineBudget == nil { routineBudget = CompanionSchedule.routineBudget(unit: unit()) }
        if observeSystem { observeTheSystem() }
    }

    func clock(for character: CompanionCharacter) -> CompanionClock { CompanionClock(character: character) }

    // MARK: - Presence

    /// A perch came on screen in `place`. `still`: Reduce Motion (nothing moves); `calm`: Reduce Effects (idles
    /// only).
    func appear(_ id: String, place: CompanionPlace, still isStill: Bool, calm isCalm: Bool, now: Date = .now) {
        settleBudgets(now: now)
        instances[id, default: 0] += 1
        still[id] = isStill
        calm[id] = isCalm
        if stages[id] == nil {
            let dress = dress(at: now)
            var stage = CompanionStage(since: now, place: place, look: dress.look, turned: turned[id] ?? false,
                                       sky: dress.sky)
            // The snow it had gathered, if it is still snowing and night and day haven't changed over.
            if let kept = pile[id], dress.look.weather == .snow, kept.asleep == dress.look.asleep {
                stage.snowDepth = kept.depth
            } else {
                pile[id] = nil
                snowLeft[id] = nil
            }
            stages[id] = stage
            forceSnowDepth(id)
            activeSince[id] = now
            scheduleIdle(id, after: now, first: true)
        }
        startSpending(now: now)
        reschedule(now: now)
    }

    /// A perch left the screen.
    func disappear(_ id: String, now: Date = .now) {
        guard let count = instances[id] else { return }
        if count > 1 { instances[id] = count - 1; return }
        settleBudgets(now: now)
        instances[id] = nil
        if let stage = stages[id], let character = character(id) {
            turned[id] = clock(for: character).facing(at: now, stage: stage)
            let depth = clock(for: character).snowDepth(at: now, stage: stage)
            pile[id] = stage.look.weather == .snow ? (depth, stage.look.asleep) : nil
        }
        stages[id] = nil
        activeSince[id] = nil
        nextIdle[id] = nil
        startSpending(now: now)
        reschedule(now: now)
    }

    /// Reduce Motion or Reduce Effects changed while it was showing.
    func setMotion(_ id: String, still isStill: Bool, calm isCalm: Bool, now: Date = .now) {
        guard stages[id] != nil, still[id] != isStill || calm[id] != isCalm else { return }
        settleBudgets(now: now)
        still[id] = isStill
        calm[id] = isCalm
        startSpending(now: now)
        reschedule(now: now)
    }

    /// A tap or click on a companion: its flourish if none has played for 20 minutes, else a routine if none has
    /// played for three, else a small reply now and then.
    func tap(_ id: String, now: Date = .now) {
        guard let character = character(id), let stage = stages[id] else { return }
        let clock = clock(for: character)
        let acting = clock.isActing(at: now, stage: stage)
        let pick = pickRoutine(id, now: now)
        var reply = CompanionSchedule.tapReply(now: now, onScreen: isAppActive, look: stage.look, acting: acting,
                                               still: still[id] ?? true, calm: calm[id] ?? true, lowPower: isLowPower,
                                               lastFlourish: lastFlourish, lastAnswer: lastAnswer[id],
                                               lastRoutine: lastRoutine, routines: pick != nil,
                                               plainStill: plainStill(id, stage: stage))
        // A reply that would cut through a pile of snow isn't played.
        if reply == .answer, !clock.canDraw(.answer, stage: stage) { reply = .nothing }
        switch reply {
        case .flourish: playFlourish(id, now: now)
        case .routine:
            if let pick { playRoutine(id, pick, now: now) }
        case .answer:
            lastAnswer[id] = now
            start(id, .answer, now: now)
            reschedule(now: now)
        case .nothing: break
        }
    }

    // MARK: - The schedule

    private func character(_ id: String) -> CompanionCharacter? { cast.first { $0.id == id } }

    /// The look for `now`: asleep at night where the person is (or `-companionHour`), dressed for the sky.
    func look(at now: Date) -> CompanionLook { dress(at: now).look }

    /// The look for `now` and the sky it is dressed for.
    func dress(at now: Date) -> (look: CompanionLook, sky: CompanionSky) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone()
        let hour = launch.hour ?? calendar.component(.hour, from: now)
        let sky = sky()
        return (CompanionLook(asleep: CompanionSchedule.isNight(hour: hour), weather: .init(sky)), sky)
    }

    private func unit() -> Double {
        draws += 1
        return CompanionRandom.unit(seed, draws)
    }

    /// The next idle `after` (the end of the act that just started, or the moment it came on screen when `first`):
    /// 6 to 36 s of stillness, the first 2 to 6 s.
    private func scheduleIdle(_ id: String, after now: Date, first: Bool = false) {
        if launch.isDemo {
            let wait = first ? CompanionLaunchOptions.demoSettling
                : (launch.play == .flourish ? CompanionLaunchOptions.demoFlourishInterval : CompanionLaunchOptions.demoInterval)
            nextIdle[id] = now.addingTimeInterval(wait)
            return
        }
        let gap = first ? CompanionSchedule.firstIdle(unit: unit()) : CompanionSchedule.idleGap(unit: unit())
        nextIdle[id] = now.addingTimeInterval(gap)
    }

    /// The routines it may play now, as indices into its awake mode's routines: the everyday ones that can be drawn
    /// in the weather, and the sky's own (storm takes the rain ones too); the long ones, or with `little` the little
    /// loops. Empty asleep.
    func routinePools(_ id: String, little: Bool = false) -> (everyday: [Int], weather: [Int]) {
        guard let character = character(id), let stage = stages[id], !stage.look.asleep else { return ([], []) }
        let mode = character.posture(stage.place).awake
        var everyday: [Int] = []
        var weather: [Int] = []
        let depth = stage.snowDepth
        for (i, routine) in mode.routines.enumerated() where routine.little == little {
            if let sky = routine.sky {
                guard CompanionSchedule.belongs(sky, under: stage.sky) else { continue }
                if character.canDraw(routine, in: stage.look.weather, mode: mode, depth: depth) { weather.append(i) }
            } else if character.plays(routine, in: stage.look.weather, mode: mode, depth: depth) {
                everyday.append(i)
            }
        }
        return (everyday, weather)
    }

    /// The flickers it may play now (asleep: every gesture, its breaths and stirs), as indices into the mode's
    /// gestures: the everyday ones and the sky's own, each only if it can be drawn over the still frame as it is (a
    /// pile of snow).
    func flickerPools(_ id: String) -> (everyday: [Int], weather: [Int]) {
        guard let character = character(id), let stage = stages[id] else { return ([], []) }
        let mode = character.posture(stage.place).mode(stage.look)
        let choices = stage.look.asleep ? Array(mode.gestures.indices) : mode.flickers
        var everyday: [Int] = []
        var weather: [Int] = []
        for i in choices {
            let gesture = mode.gestures[i]
            if let sky = gesture.sky, !CompanionSchedule.belongs(sky, under: stage.sky) { continue }
            guard character.canDraw(gesture, in: stage.look.weather, mode: mode, depth: stage.snowDepth) else { continue }
            if gesture.sky == nil { everyday.append(i) } else { weather.append(i) }
        }
        return (everyday, weather)
    }

    /// Every idle it may play now (brief 100): its flickers and, awake, its little loops, each with its weight and
    /// whether it is the sky's own.
    func idleChoices(_ id: String) -> [CompanionSchedule.IdleChoice] {
        guard let character = character(id), let stage = stages[id] else { return [] }
        let mode = character.posture(stage.place).mode(stage.look)
        var out: [CompanionSchedule.IdleChoice] = []
        let flickers = flickerPools(id)
        for i in flickers.everyday { out.append(.init(idle: .flicker(i), weight: mode.gestures[i].weight)) }
        for i in flickers.weather { out.append(.init(idle: .flicker(i), weight: mode.gestures[i].weight, own: true)) }
        let loops = routinePools(id, little: true)
        let routines = character.posture(stage.place).awake.routines
        for i in loops.everyday { out.append(.init(idle: .little(i), weight: routines[i].weight)) }
        for i in loops.weather { out.append(.init(idle: .little(i), weight: routines[i].weight, own: true)) }
        return out
    }

    /// Whether the still frame is the plain `rest`, so the flourish can start and end on it (brief 91).
    private func plainStill(_ id: String, stage: CompanionStage) -> Bool {
        guard let character = character(id) else { return false }
        let mode = character.posture(stage.place).mode(stage.look)
        return mode.still(stage.look.weather, depth: stage.snowDepth) == mode.rest
    }

    /// The next routine for `id` (never the one that played last), or nil.
    private func pickRoutine(_ id: String, now: Date) -> Int? {
        guard let character = character(id), let stage = stages[id], !stage.look.asleep else { return nil }
        let mode = character.posture(stage.place).awake
        let pools = routinePools(id)
        var last: Int?
        if let lastRoutineName {
            last = mode.routines.firstIndex { "\(id).\($0.name)" == lastRoutineName }
        }
        return CompanionSchedule.pickRoutine(everyday: pools.everyday, weather: pools.weather,
                                             weights: mode.routines.map(\.weight), last: last, unit: unit(), pick: unit())
    }

    /// When the flourish may come, if a companion that could play it is on screen: the budget spent out, the
    /// floor after the last one passed, and 20 seconds on the screen.
    private func flourishMoment(_ id: String) -> Date? {
        guard let spendingSince, let stage = stages[id], isAppActive, !launch.isDemo,
              canFlourish(id, stage: stage) else { return nil }
        var moment = spendingSince.addingTimeInterval(budget)
        if let lastFlourish { moment = max(moment, lastFlourish.addingTimeInterval(CompanionSchedule.flourishFloor)) }
        if let since = activeSince[id] { moment = max(moment, since.addingTimeInterval(CompanionSchedule.settling)) }
        // Never over another act: after the one playing ends.
        if let act = stage.act, let character = character(id) {
            moment = max(moment, clock(for: character).end(of: act, stage: stage))
        }
        return moment
    }

    /// When the next routine may come: its budget spent out, 20 seconds on the screen, after the act playing.
    private func routineMoment(_ id: String) -> Date? {
        guard let routineSpendingSince, let stage = stages[id], isAppActive, !launch.isDemo,
              canRoutine(id, stage: stage) else { return nil }
        var moment = routineSpendingSince.addingTimeInterval(routineBudget)
        if let since = activeSince[id] { moment = max(moment, since.addingTimeInterval(CompanionSchedule.settling)) }
        if let act = stage.act, let character = character(id) {
            moment = max(moment, clock(for: character).end(of: act, stage: stage))
        }
        return moment
    }

    private func canFlourish(_ id: String, stage: CompanionStage) -> Bool {
        guard !stage.look.asleep, stage.look.flourishes, plainStill(id, stage: stage) else { return false }
        return !(still[id] ?? true) && !(calm[id] ?? true) && !isLowPower
    }

    /// Awake, motion and effects allowed, and a routine (not a little loop) to play.
    private func canRoutine(_ id: String, stage: CompanionStage) -> Bool {
        guard !stage.look.asleep, !(still[id] ?? true), !(calm[id] ?? true), !isLowPower else { return false }
        guard let character = character(id) else { return false }
        return character.posture(stage.place).awake.routines.contains { !$0.little }
    }

    /// The timer's turn: finished acts put away, then the flourish if its moment has come and it may play, then a
    /// routine if its moment has come, else the next idle.
    func fire(now: Date = .now) {
        settleActs(now: now)
        let soon = now.addingTimeInterval(0.05)
        for id in stages.keys.sorted() {
            guard let character = character(id), var stage = stages[id], !(still[id] ?? true) else { continue }
            let clock = clock(for: character)
            let acting = clock.isActing(at: now, stage: stage)
            // The snow piles one frame deeper, between acts.
            if !acting, let moment = snowMoment(id), moment <= soon {
                settleSnow(id, now: now)
                stage.snowDepth += 1
                stages[id] = stage
                snowLeft[id] = CompanionSchedule.snowBudget(unit: unit())
                startSnow(id, now: now)
            }
            if let moment = flourishMoment(id), moment <= soon,
               CompanionSchedule.mayFlourish(now: now, look: stage.look, onScreenSince: activeSince[id], acting: acting,
                                             still: still[id] ?? true, calm: calm[id] ?? true, lowPower: isLowPower,
                                             lastFlourish: lastFlourish, plainStill: plainStill(id, stage: stage)) {
                playFlourish(id, now: now)
                continue
            }
            if let moment = routineMoment(id), moment <= soon,
               CompanionSchedule.mayRoutine(now: now, look: stage.look, onScreenSince: activeSince[id], acting: acting,
                                            still: still[id] ?? true, calm: calm[id] ?? true, lowPower: isLowPower) {
                if let pick = pickRoutine(id, now: now) {
                    playRoutine(id, pick, now: now)
                    continue
                }
                // Nothing but the last one could play: this slot passes, and the next comes a fresh stretch later.
                settleBudgets(now: now)
                routineBudget = CompanionSchedule.routineBudget(unit: unit())
                save()
                startSpending(now: now)
            }
            guard let next = nextIdle[id], next <= soon else { continue }
            if acting, let act = stage.act {
                // Something is playing (a tap's flourish): the idle waits until a little after it ends.
                nextIdle[id] = clock.end(of: act, stage: stage).addingTimeInterval(1)
                continue
            }
            playNextIdle(id, now: now)
        }
        reschedule(now: now)
    }

    private func playNextIdle(_ id: String, now: Date) {
        guard let character = character(id), let stage = stages[id] else { return }
        let mode = character.posture(stage.place).mode(stage.look)
        switch launch.play {
        case .flourish?:
            playFlourish(id, now: now)
            return
        case .answer?:
            start(id, .answer, now: now)
        case .gesture(let name)?:
            let i = mode.gestures.firstIndex { $0.name == name }
            if let i { start(id, .gesture(i), now: now) } else if name == "flourish" { playFlourish(id, now: now); return }
        case .routines?, .routine?:
            let pools = routinePools(id)
            let loops = routinePools(id, little: true)
            let all = pools.everyday + pools.weather + loops.everyday + loops.weather
            var pick: Int?
            if case .routine(let name)? = launch.play {
                pick = mode.routines.firstIndex { $0.name == name }
            } else if !all.isEmpty {
                let turn = recent[id, default: []].count % all.count
                recent[id, default: []].append(turn)
                pick = all[turn]
            }
            if let pick, !stage.look.asleep {
                playRoutine(id, pick, now: now)
                return
            }
            start(id, .answer, now: now)
        case .all?:
            // Every gesture in turn, then every routine it may play (the long ones, then the little loops), the
            // reply, then the flourish (awake, plain weather), and round again.
            let pools = routinePools(id)
            let loops = routinePools(id, little: true)
            let routines = pools.everyday + pools.weather + loops.everyday + loops.weather
            let playable = mode.gestures.indices.filter { i in
                mode.gestures[i].sky.map { CompanionSchedule.belongs($0, under: stage.sky) } ?? true
            }
            let turn = recent[id, default: []].count % (playable.count + routines.count + 2)
            recent[id, default: []].append(turn)
            let afterGestures = turn - playable.count
            if turn < playable.count { start(id, .gesture(playable[turn]), now: now) }
            else if afterGestures < routines.count { playRoutine(id, routines[afterGestures], now: now); return }
            else if afterGestures == routines.count { start(id, .answer, now: now) }
            else if canFlourish(id, stage: stage) { playFlourish(id, now: now); return }
            else { start(id, .answer, now: now) }
            scheduleIdle(id, after: now)
            return
        case .gestures?, nil:
            // An idle (brief 100): a flicker or, awake, a little loop, never the same one twice running, by weight;
            // while a sky holds, about every other one is the sky's own (a drip, a bead of sweat). The next comes a
            // gap after this one ends.
            let kept = lastIdle[id]
            let last = kept.flatMap { $0.place == stage.place && $0.asleep == stage.look.asleep ? $0.idle : nil }
            guard let idle = CompanionSchedule.pickIdle(idleChoices(id), last: last, sky: unit(), kind: unit(),
                                                        pick: unit()) else {
                scheduleIdle(id, after: now)
                return
            }
            lastIdle[id] = (idle, stage.place, stage.look.asleep)
            switch idle {
            case .flicker(let i): start(id, .gesture(i), now: now)
            case .little(let i): start(id, .routine(i), now: now)
            }
            var end = now
            if let act = stages[id]?.act { end = clock(for: character).end(of: act, stage: stages[id] ?? stage) }
            scheduleIdle(id, after: end)
            return
        }
        scheduleIdle(id, after: now)
    }

    /// Puts away the acts that have ended: the turn folded into the facing, the act cleared, so each perch goes back
    /// to its still picture. (A `TimelineView` did not draw its schedule's last entry, the return to rest: a blink
    /// stayed shut until something else redrew it. Clearing the act redraws it for certain.)
    private func settleActs(now: Date) {
        for id in stages.keys {
            guard var stage = stages[id], let act = stage.act, let character = character(id) else { continue }
            let clock = clock(for: character)
            let end = clock.end(of: act, stage: stage)
            guard now >= end.addingTimeInterval(-0.01) else { continue }
            stage.turned = clock.facing(at: max(now, end), stage: stage)
            let depth = clock.snowDepth(at: max(now, end), stage: stage)
            if depth != stage.snowDepth {
                // Shaken off: the pile starts again from the bare snow.
                settleSnow(id, now: now)
                snowLeft[id] = CompanionSchedule.snowBudget(unit: unit())
            }
            stage.snowDepth = depth
            stage.act = nil
            stages[id] = stage
            forceSnowDepth(id)
            startSnow(id, now: now)
        }
    }

    /// Starts an act, folding a finished turn into the facing.
    private func start(_ id: String, _ kind: CompanionAct.Kind, now: Date) {
        guard let character = character(id), var stage = stages[id] else { return }
        stage.turned = clock(for: character).facing(at: now, stage: stage)
        stage.act = CompanionAct(kind: kind, start: now)
        stages[id] = stage
    }

    private func playFlourish(_ id: String, now: Date) {
        guard let character = character(id), let stage = stages[id] else { return }
        settleBudgets(now: now)
        start(id, .flourish, now: now)
        // A demo (Debug) keeps nothing: the device's real clock stays as it was.
        if !launch.isDemo {
            lastFlourish = now
            budget = CompanionSchedule.flourishBudget(unit: unit())
            // The flourish takes a routine's place: the next routine is a whole stretch away.
            routineBudget = CompanionSchedule.routineBudget(unit: unit())
            save()
        }
        // The next flicker comes a while after the flourish ends, not on its heels.
        let end = clock(for: character).end(of: CompanionAct(kind: .flourish, start: now), stage: stage)
        quietAfter(id, end: end)
        startSpending(now: now)
        reschedule(now: now)
    }

    /// Plays routine `i` of its awake mode, and starts the next routine's stretch.
    private func playRoutine(_ id: String, _ i: Int, now: Date) {
        guard let character = character(id), let stage = stages[id] else { return }
        let routines = character.posture(stage.place).awake.routines
        guard routines.indices.contains(i) else { return }
        settleBudgets(now: now)
        start(id, .routine(i), now: now)
        if !launch.isDemo {
            lastRoutine = now
            lastRoutineName = "\(id).\(routines[i].name)"
            routineBudget = CompanionSchedule.routineBudget(unit: unit())
            save()
        }
        let end = clock(for: character).end(of: CompanionAct(kind: .routine(i), start: now), stage: stage)
        quietAfter(id, end: end)
        startSpending(now: now)
        reschedule(now: now)
    }

    /// After a routine or the flourish: back to still, the next idle a gap after it ends (in a demo, the next act a
    /// few seconds after).
    private func quietAfter(_ id: String, end: Date) {
        if launch.isDemo {
            nextIdle[id] = end.addingTimeInterval(CompanionLaunchOptions.demoQuiet)
            if launch.play == .flourish { scheduleIdle(id, after: end) }
            return
        }
        if let next = nextIdle[id], next < end.addingTimeInterval(CompanionSchedule.idleGap.lowerBound) {
            nextIdle[id] = end.addingTimeInterval(CompanionSchedule.idleGap(unit: unit()))
        }
    }

    /// Sleeps until the earliest moment among the companions that may move now; no timer when nothing is
    /// scheduled within the hour.
    private func reschedule(now: Date) {
        timer?.cancel()
        timer = nil
        nextMoment = nil
        guard isAppActive else { return }
        var moments: [Date] = []
        for id in stages.keys where !(still[id] ?? true) {
            if let g = nextIdle[id] { moments.append(g) }
            if let f = flourishMoment(id) { moments.append(f) }
            if let r = routineMoment(id) { moments.append(r) }
            if let p = snowMoment(id) { moments.append(p) }
            // The end of the act playing, to put it away.
            if let stage = stages[id], let act = stage.act, let character = character(id) {
                moments.append(clock(for: character).end(of: act, stage: stage))
            }
        }
        guard let next = moments.min(), next.timeIntervalSince(now) <= CompanionSchedule.horizon else { return }
        nextMoment = next
        guard runsTimer else { return }
        let wait = max(0.05, next.timeIntervalSince(now))
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    // MARK: - Snow piling up (brief 91)

    /// Whether the snow may pile deeper on `id` now: on screen, the app in front, motion allowed, snowing, not as deep
    /// as it goes, and not held by `-companionSnowDepth`.
    private func piles(_ id: String) -> Bool {
        guard isAppActive, launch.snowDepth == nil, !(still[id] ?? true), let stage = stages[id],
              stage.look.weather == .snow, let character = character(id) else { return false }
        return stage.snowDepth < character.posture(stage.place).mode(stage.look).deepest
    }

    /// When the pile grows next, after the act playing.
    private func snowMoment(_ id: String) -> Date? {
        guard let since = snowSince[id], let left = snowLeft[id], let stage = stages[id] else { return nil }
        var moment = since.addingTimeInterval(left)
        if let act = stage.act, let character = character(id) {
            moment = max(moment, clock(for: character).end(of: act, stage: stage))
        }
        return moment
    }

    private func settleSnow(_ id: String, now: Date) {
        guard let since = snowSince[id] else { return }
        let spent: TimeInterval = max(0, now.timeIntervalSince(since))
        let left: TimeInterval = (snowLeft[id] ?? 0) - spent
        snowLeft[id] = max(0, left)
        snowSince[id] = nil
    }

    private func startSnow(_ id: String, now: Date) {
        if piles(id) {
            if snowLeft[id] == nil { snowLeft[id] = CompanionSchedule.snowBudget(unit: unit()) }
            if snowSince[id] == nil { snowSince[id] = now }
        } else {
            settleSnow(id, now: now)
        }
    }

    /// `-companionSnowDepth` (Debug): the pile held at that depth whenever it snows, and back to it after a shake-off.
    private func forceSnowDepth(_ id: String) {
        guard let forced = launch.snowDepth, var stage = stages[id], stage.look.weather == .snow,
              let character = character(id) else { return }
        stage.snowDepth = min(forced, character.posture(stage.place).mode(stage.look).deepest)
        stages[id] = stage
    }

    // MARK: - The kept clocks

    /// Whether the flourish's budget is being spent: a companion that could flourish is on screen, the app in front.
    private var spendsFlourish: Bool {
        guard isAppActive, !launch.isDemo else { return false }
        return stages.contains { canFlourish($0.key, stage: $0.value) }
    }

    /// Whether the routine's is: a companion that could play a routine is on screen, the app in front.
    private var spendsRoutine: Bool {
        guard isAppActive, !launch.isDemo else { return false }
        return stages.contains { canRoutine($0.key, stage: $0.value) }
    }

    /// Takes the showing time since each budget began to be spent off it, and saves.
    private func settleBudgets(now: Date) {
        for id in Array(snowSince.keys) { settleSnow(id, now: now) }
        guard spendingSince != nil || routineSpendingSince != nil else { return }
        if let since = spendingSince {
            let spent: TimeInterval = max(0, now.timeIntervalSince(since))
            let left: TimeInterval = budget - spent
            budget = max(0, left)
            spendingSince = nil
        }
        if let since = routineSpendingSince {
            let spent: TimeInterval = max(0, now.timeIntervalSince(since))
            let left: TimeInterval = routineBudget - spent
            routineBudget = max(0, left)
            routineSpendingSince = nil
        }
        save()
    }

    private func startSpending(now: Date) {
        for id in stages.keys { startSnow(id, now: now) }
        for id in snowSince.keys where stages[id] == nil { settleSnow(id, now: now) }
        let flourish = spendsFlourish
        let routine = spendsRoutine
        if (!flourish && spendingSince != nil) || (!routine && routineSpendingSince != nil) { settleBudgets(now: now) }
        if flourish, spendingSince == nil { spendingSince = now }
        if routine, routineSpendingSince == nil { routineSpendingSince = now }
    }

    private func save() {
        guard let defaults, !launch.isDemo else { return }
        defaults.set(budget, forKey: Preferences.companionFlourishBudget)
        defaults.set(routineBudget, forKey: Preferences.companionRoutineBudget)
        if let lastFlourish { defaults.set(lastFlourish.timeIntervalSinceReferenceDate, forKey: Preferences.companionLastFlourish) }
        if let lastRoutine { defaults.set(lastRoutine.timeIntervalSinceReferenceDate, forKey: Preferences.companionLastRoutine) }
        if let lastRoutineName { defaults.set(lastRoutineName, forKey: Preferences.companionLastRoutineName) }
    }

    // MARK: - The system

    func setAppActive(_ active: Bool, now: Date = .now) {
        guard active != isAppActive, !launch.isDemo else { return }
        settleBudgets(now: now)
        isAppActive = active
        // Nobody is looking as the app goes or comes back: the moment to fall asleep, wake, or dress for the sky.
        let fresh = dress(at: now)
        for id in stages.keys {
            guard var stage = stages[id], let character = character(id) else { continue }
            guard stage.look != fresh.look || stage.sky != fresh.sky else { continue }
            let changed = stage.look != fresh.look
            stage.turned = clock(for: character).facing(at: now, stage: stage)
            if changed {
                // Out of the snow, or night and day changed over: the pile starts again.
                stage.snowDepth = 0
                snowLeft[id] = nil
                snowSince[id] = nil
            }
            stage.look = fresh.look
            stage.sky = fresh.sky
            stage.act = nil
            stages[id] = stage
            forceSnowDepth(id)
            if changed {
                recent[id] = []
                lastIdle[id] = nil
            }
        }
        if active {
            // Coming back is arriving on the screen again: 20 quiet seconds before a flourish or a routine, and the
            // first idle 2 to 6 seconds in, so a short visit sees it move.
            for id in stages.keys {
                activeSince[id] = now
                scheduleIdle(id, after: now, first: true)
            }
        }
        startSpending(now: now)
        reschedule(now: now)
    }

    func setLowPower(_ on: Bool, now: Date = .now) {
        guard on != isLowPower else { return }
        settleBudgets(now: now)
        isLowPower = on
        startSpending(now: now)
        reschedule(now: now)
    }

    private func observeTheSystem() {
        let center = NotificationCenter.default
        #if os(iOS)
        let active = UIApplication.didBecomeActiveNotification
        let inactive = UIApplication.willResignActiveNotification
        #else
        let active = NSApplication.didBecomeActiveNotification
        let inactive = NSApplication.didResignActiveNotification
        #endif
        observers.append(center.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAppActive(true) }
        })
        observers.append(center.addObserver(forName: inactive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAppActive(false) }
        })
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled) }
        })
    }
}
