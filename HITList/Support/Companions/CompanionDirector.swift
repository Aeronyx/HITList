import Foundation
import Observation
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Keeps every companion's life in one place (briefs 76 and 79): which is on screen, where and since when, how it
/// is dressed, what it is doing, and the one timer that wakes for the next thing it does. At rest a companion is
/// a still picture and nothing runs; the timer sleeps until the next small gesture (every 45 to 120 seconds), stir
/// or the rare flourish, and only while a companion that may move is on screen and the app is in front. The
/// drawing runs in each perch's `TimelineView` for the length of an act and stops. The rules are
/// `CompanionSchedule`'s; the frames are `CompanionClock`'s.
///
/// The flourish's clock is kept on the device (`Preferences.companionLastFlourish`, `.companionFlourishBudget`):
/// the budget is showing time, spent only while a companion that could flourish is on screen, and saved whenever
/// it stops being spent, so quitting and reopening never brings a flourish sooner.
///
/// Awake or asleep, and the weather, are decided while nobody is looking: when a companion comes on screen, and
/// when the app goes to the background or comes back. A companion on screen across 22:00 falls asleep the next time
/// the app is left, with no transition.
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
    /// Reduce Motion: a still picture. Reduce Effects: gestures, no flourish.
    @ObservationIgnored private var still: [String: Bool] = [:]
    @ObservationIgnored private var calm: [String: Bool] = [:]
    @ObservationIgnored private var activeSince: [String: Date] = [:]
    /// When each companion's next gesture or stir comes.
    @ObservationIgnored private var nextGesture: [String: Date] = [:]
    /// The gestures each played, the last few.
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
    @ObservationIgnored private let calendar: Calendar
    /// What the sky is doing (`CompanionSkySource.shared`).
    @ObservationIgnored private let sky: () -> CompanionSky

    // The flourish's showing-time budget: what is left, and since when it has been spent (nil while it isn't).
    @ObservationIgnored private(set) var budget: TimeInterval
    @ObservationIgnored private var spendingSince: Date?
    @ObservationIgnored private(set) var lastFlourish: Date?

    init(seed: UInt64 = .random(in: .min ... .max), launch: CompanionLaunchOptions = .current, observeSystem: Bool = true,
         cast: [CompanionCharacter] = CompanionCharacter.all, defaults: UserDefaults? = AppGroup.defaults,
         calendar: Calendar = .current, sky: (() -> CompanionSky)? = nil) {
        self.seed = seed
        self.launch = launch
        self.cast = cast
        self.defaults = defaults
        self.calendar = calendar
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
        if keptBudget == nil { budget = CompanionSchedule.flourishBudget(unit: unit()) }
        if observeSystem { observeTheSystem() }
    }

    func clock(for character: CompanionCharacter) -> CompanionClock { CompanionClock(character: character) }

    // MARK: - Presence

    /// A perch came on screen in `place`. `still`: Reduce Motion (nothing moves); `calm`: Reduce Effects (gestures,
    /// no flourish).
    func appear(_ id: String, place: CompanionPlace, still isStill: Bool, calm isCalm: Bool, now: Date = .now) {
        settleBudget(now: now)
        instances[id, default: 0] += 1
        still[id] = isStill
        calm[id] = isCalm
        if stages[id] == nil {
            stages[id] = CompanionStage(since: now, place: place, look: look(at: now), turned: turned[id] ?? false)
            activeSince[id] = now
            scheduleGesture(id, after: now, first: true)
        }
        startSpending(now: now)
        reschedule(now: now)
    }

    /// A perch left the screen.
    func disappear(_ id: String, now: Date = .now) {
        guard let count = instances[id] else { return }
        if count > 1 { instances[id] = count - 1; return }
        settleBudget(now: now)
        instances[id] = nil
        if let stage = stages[id], let character = character(id) {
            turned[id] = clock(for: character).facing(at: now, stage: stage)
        }
        stages[id] = nil
        activeSince[id] = nil
        nextGesture[id] = nil
        startSpending(now: now)
        reschedule(now: now)
    }

    /// Reduce Motion or Reduce Effects changed while it was showing.
    func setMotion(_ id: String, still isStill: Bool, calm isCalm: Bool, now: Date = .now) {
        guard stages[id] != nil, still[id] != isStill || calm[id] != isCalm else { return }
        settleBudget(now: now)
        still[id] = isStill
        calm[id] = isCalm
        startSpending(now: now)
        reschedule(now: now)
    }

    /// A tap or click on a companion: its flourish if none has played for 20 minutes, else a small reply now and then.
    func tap(_ id: String, now: Date = .now) {
        guard let character = character(id), let stage = stages[id] else { return }
        let acting = clock(for: character).isActing(at: now, stage: stage)
        let reply = CompanionSchedule.tapReply(now: now, onScreen: isAppActive, look: stage.look, acting: acting,
                                               still: still[id] ?? true, calm: calm[id] ?? true, lowPower: isLowPower,
                                               lastFlourish: lastFlourish, lastAnswer: lastAnswer[id])
        switch reply {
        case .flourish: playFlourish(id, now: now)
        case .answer:
            lastAnswer[id] = now
            start(id, .answer, now: now)
        case .nothing: break
        }
    }

    // MARK: - The schedule

    private func character(_ id: String) -> CompanionCharacter? { cast.first { $0.id == id } }

    /// The look for `now`: asleep at night by the device's clock (or `-companionHour`), dressed for the sky.
    func look(at now: Date) -> CompanionLook {
        let hour = launch.hour ?? calendar.component(.hour, from: now)
        return CompanionLook(asleep: CompanionSchedule.isNight(hour: hour), weather: .init(sky()))
    }

    private func unit() -> Double {
        draws += 1
        return CompanionRandom.unit(seed, draws)
    }

    private func scheduleGesture(_ id: String, after now: Date, first: Bool = false) {
        if launch.isDemo {
            let wait = first ? CompanionLaunchOptions.demoSettling
                : (launch.play == .flourish ? CompanionLaunchOptions.demoFlourishInterval : CompanionLaunchOptions.demoInterval)
            nextGesture[id] = now.addingTimeInterval(wait)
            return
        }
        let asleep = stages[id]?.look.asleep ?? false
        nextGesture[id] = now.addingTimeInterval(CompanionSchedule.gap(asleep: asleep, unit: unit()))
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

    private func canFlourish(_ id: String, stage: CompanionStage) -> Bool {
        !stage.look.asleep && stage.look.weather == .plain && !(still[id] ?? true) && !(calm[id] ?? true) && !isLowPower
    }

    /// The timer's turn: finished acts put away, then the flourish if its moment has come and it may play, else the
    /// next gesture or stir.
    func fire(now: Date = .now) {
        settleActs(now: now)
        for id in stages.keys.sorted() {
            guard let character = character(id), let stage = stages[id], !(still[id] ?? true) else { continue }
            let clock = clock(for: character)
            let acting = clock.isActing(at: now, stage: stage)
            if let moment = flourishMoment(id), moment <= now.addingTimeInterval(0.05),
               CompanionSchedule.mayFlourish(now: now, look: stage.look, onScreenSince: activeSince[id], acting: acting,
                                             still: still[id] ?? true, calm: calm[id] ?? true, lowPower: isLowPower,
                                             lastFlourish: lastFlourish) {
                playFlourish(id, now: now)
                continue
            }
            guard let next = nextGesture[id], next <= now.addingTimeInterval(0.05) else { continue }
            if acting, let act = stage.act {
                // Something is playing (a tap's flourish): the gesture waits until a little after it ends.
                nextGesture[id] = clock.end(of: act, stage: stage).addingTimeInterval(1)
                continue
            }
            playNextGesture(id, now: now)
        }
        reschedule(now: now)
    }

    private func playNextGesture(_ id: String, now: Date) {
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
        case .all?:
            // Every gesture in turn, then the reply, then the flourish (awake, plain weather), and round again.
            let turn = recent[id, default: []].count % (mode.gestures.count + 2)
            recent[id, default: []].append(turn)
            if turn < mode.gestures.count { start(id, .gesture(turn), now: now) }
            else if turn == mode.gestures.count { start(id, .answer, now: now) }
            else if canFlourish(id, stage: stage) { playFlourish(id, now: now); return }
            else { start(id, .answer, now: now) }
            scheduleGesture(id, after: now)
            return
        case .gestures?, nil:
            let i = CompanionSchedule.pickGesture(weights: mode.gestures.map(\.weight), recent: recent[id] ?? [],
                                                  unit: unit())
            recent[id, default: []].append(i)
            if recent[id, default: []].count > 4 { recent[id]?.removeFirst() }
            start(id, .gesture(i), now: now)
        }
        scheduleGesture(id, after: now)
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
            stage.act = nil
            stages[id] = stage
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
        settleBudget(now: now)
        start(id, .flourish, now: now)
        // A demo (Debug) keeps nothing: the device's real clock stays as it was.
        if !launch.isDemo {
            lastFlourish = now
            budget = CompanionSchedule.flourishBudget(unit: unit())
            save()
        }
        // The next small gesture comes a while after the flourish ends, not on its heels.
        let end = clock(for: character).end(of: CompanionAct(kind: .flourish, start: now), stage: stage)
        if !launch.isDemo, let next = nextGesture[id], next < end.addingTimeInterval(CompanionSchedule.gestureGap.lowerBound) {
            nextGesture[id] = end.addingTimeInterval(CompanionSchedule.gap(asleep: false, unit: unit()))
        } else if launch.isDemo {
            scheduleGesture(id, after: end)
        }
        startSpending(now: now)
        reschedule(now: now)
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
            if let g = nextGesture[id] { moments.append(g) }
            if let f = flourishMoment(id) { moments.append(f) }
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

    // MARK: - The flourish's kept clock

    /// Whether the budget is being spent: a companion that could flourish is on screen and the app is in front.
    private var spends: Bool {
        guard isAppActive, !launch.isDemo else { return false }
        return stages.contains { canFlourish($0.key, stage: $0.value) }
    }

    /// Takes the showing time since the budget began to be spent off it, and saves.
    private func settleBudget(now: Date) {
        guard let since = spendingSince else { return }
        let spent: TimeInterval = max(0, now.timeIntervalSince(since))
        let left: TimeInterval = budget - spent
        budget = max(0, left)
        spendingSince = nil
        save()
    }

    private func startSpending(now: Date) {
        if spends {
            if spendingSince == nil { spendingSince = now }
        } else {
            settleBudget(now: now)
        }
    }

    private func save() {
        guard let defaults, !launch.isDemo else { return }
        defaults.set(budget, forKey: Preferences.companionFlourishBudget)
        if let lastFlourish { defaults.set(lastFlourish.timeIntervalSinceReferenceDate, forKey: Preferences.companionLastFlourish) }
    }

    // MARK: - The system

    func setAppActive(_ active: Bool, now: Date = .now) {
        guard active != isAppActive, !launch.isDemo else { return }
        settleBudget(now: now)
        isAppActive = active
        // Nobody is looking as the app goes or comes back: the moment to fall asleep, wake, or dress for the sky.
        let fresh = self.look(at: now)
        for id in stages.keys {
            guard var stage = stages[id], stage.look != fresh, let character = character(id) else { continue }
            stage.turned = clock(for: character).facing(at: now, stage: stage)
            stage.look = fresh
            stage.act = nil
            stages[id] = stage
            recent[id] = []
            scheduleGesture(id, after: now)
        }
        if active {
            // Coming back is arriving on the screen again: 20 quiet seconds before a flourish, and no gesture owed
            // from while it was away.
            for id in stages.keys {
                activeSince[id] = now
                if let next = nextGesture[id], next < now { scheduleGesture(id, after: now) }
            }
        }
        startSpending(now: now)
        reschedule(now: now)
    }

    func setLowPower(_ on: Bool, now: Date = .now) {
        guard on != isLowPower else { return }
        settleBudget(now: now)
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
