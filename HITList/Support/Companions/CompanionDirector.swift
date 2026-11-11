import Foundation
import Observation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Keeps every companion's life in one place (brief 76): which are on screen and since when, the flourishes
/// they have played, and the one timer that wakes for the next flourish. The timer runs only while a companion
/// that may flourish is on screen and the app is active; the drawing itself runs in each perch's `TimelineView`,
/// which SwiftUI stops while it is off screen. The rules are `CompanionSchedule`'s; the frames are
/// `CompanionClock`'s.
@MainActor
@Observable
final class CompanionDirector {
    static let shared = CompanionDirector()

    /// The companions on screen now, by character id.
    private(set) var stages: [String: CompanionStage] = [:]
    /// Whether the timer is waiting for a flourish (tests check it stops when nothing may flourish).
    var isWaiting: Bool { timer != nil }
    /// The moment the timer is waiting for.
    @ObservationIgnored private(set) var nextMoment: Date?
    private(set) var isAppActive: Bool
    private(set) var isLowPower: Bool

    @ObservationIgnored private var instances: [String: Int] = [:]
    @ObservationIgnored private var calm: [String: Bool] = [:]
    @ObservationIgnored private var activeSince: [String: Date] = [:]
    @ObservationIgnored private var due: [String: (date: Date, index: Int)] = [:]
    @ObservationIgnored private var lastPlay: [String: Date] = [:]
    @ObservationIgnored private var busyUntil: Date?
    /// Which way each companion faced when it last left the screen (Quill keeps its side).
    @ObservationIgnored private var turned: [String: Bool] = [:]
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored let seed: UInt64
    @ObservationIgnored private let launch: CompanionLaunchOptions
    /// False in tests, which call `fire(now:)` themselves.
    @ObservationIgnored private let runsTimer: Bool
    /// The characters it can direct, by id.
    @ObservationIgnored private let cast: [CompanionCharacter]

    init(seed: UInt64 = .random(in: .min ... .max), launch: CompanionLaunchOptions = .current, observeSystem: Bool = true,
         cast: [CompanionCharacter] = CompanionCharacter.all) {
        self.seed = seed
        self.launch = launch
        self.cast = cast
        runsTimer = observeSystem
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // A demo (Debug only) keeps going in the background, so a window can be recorded without taking the front.
        #if os(iOS)
        isAppActive = !observeSystem || !launch.demo.isEmpty || UIApplication.shared.applicationState == .active
        #else
        isAppActive = !observeSystem || !launch.demo.isEmpty || NSApplication.shared.isActive
        #endif
        if observeSystem { observeTheSystem() }
    }

    /// The clock for a character, seeded per character so two companions never blink together.
    func clock(for character: CompanionCharacter) -> CompanionClock {
        CompanionClock(character: character, seed: seed ^ CompanionRandom.seed(character.id))
    }

    // MARK: - Presence

    /// A perch came on screen. `calm`: Reduce Motion or Reduce Effects is on (no flourish, no timer for it).
    func appear(_ id: String, calm isCalm: Bool, now: Date = .now) {
        instances[id, default: 0] += 1
        calm[id] = isCalm
        if stages[id] == nil {
            stages[id] = CompanionStage(since: now, turned: turned[id] ?? false)
            activeSince[id] = now
            scheduleFirst(id, now: now)
        }
        reschedule(now: now)
    }

    /// A perch left the screen.
    func disappear(_ id: String, now: Date = .now) {
        guard let count = instances[id] else { return }
        if count > 1 { instances[id] = count - 1; return }
        instances[id] = nil
        if let stage = stages[id], let character = character(id) {
            turned[id] = clock(for: character).pose(at: now, stage: stage, still: true).mirrored
        }
        stages[id] = nil
        activeSince[id] = nil
        reschedule(now: now)
    }

    /// Reduce Motion or Reduce Effects changed while it was showing.
    func setCalm(_ id: String, _ isCalm: Bool, now: Date = .now) {
        guard stages[id] != nil, calm[id] != isCalm else { return }
        calm[id] = isCalm
        reschedule(now: now)
    }

    /// A tap or click on a companion: its flourish, once in a while.
    func tap(_ id: String, now: Date = .now) {
        let onScreen = stages[id] != nil && isAppActive
        guard CompanionSchedule.mayPlayOnTap(now: now, onScreen: onScreen, busyUntil: busyUntil, lastPlay: lastPlay[id],
                                             calm: calm[id] ?? true, lowPower: isLowPower) else { return }
        play(id, now: now)
    }

    // MARK: - The schedule

    private func characterSeed(_ id: String) -> UInt64 { seed ^ CompanionRandom.seed(id) }

    private func character(_ id: String) -> CompanionCharacter? { cast.first { $0.id == id } }

    private func scheduleFirst(_ id: String, now: Date) {
        if launch.demos(id) {
            if due[id] == nil {
                let order = Double(cast.firstIndex { $0.id == id } ?? 0)
                due[id] = (now.addingTimeInterval(CompanionLaunchOptions.demoSettling + order * CompanionLaunchOptions.demoInterval / 2), 0)
            }
            return
        }
        if due[id] == nil {
            due[id] = (now.addingTimeInterval(CompanionSchedule.gap(seed: characterSeed(id), index: 0)), 0)
        }
        rollForward(id, past: now)
    }

    /// Moves a companion's next moment past `now`, skipping the ones it missed (no catching up).
    private func rollForward(_ id: String, past now: Date) {
        guard var next = due[id] else { return }
        while next.date <= now {
            next.index += 1
            next.date = next.date.addingTimeInterval(CompanionSchedule.gap(seed: characterSeed(id), index: next.index,
                                                                           demo: launch.demos(id)))
        }
        due[id] = next
    }

    /// The timer's turn: every companion whose moment has come plays if it may, then waits for its next one.
    func fire(now: Date = .now) {
        let ready = stages.keys.filter { (due[$0]?.date ?? .distantFuture) <= now.addingTimeInterval(0.05) }.sorted()
        for id in ready {
            let settling = launch.demos(id) ? CompanionLaunchOptions.demoSettling : CompanionSchedule.settling
            let demoPause = launch.demos(id) ? nil : lastPlay[id]
            if isAppActive, CompanionSchedule.mayFlourish(now: now, onScreenSince: activeSince[id], busyUntil: busyUntil,
                                                          lastPlay: demoPause, calm: calm[id] ?? true,
                                                          lowPower: isLowPower, settling: settling,
                                                          quiet: launch.demos(id) ? 0 : CompanionSchedule.quietAfter) {
                play(id, now: now)
            } else if launch.demos(id), let busyUntil, now < busyUntil, let next = due[id] {
                // A demo waits its turn rather than missing it (two demos on one beat would collide every time).
                due[id] = (busyUntil.addingTimeInterval(0.5), next.index)
                continue
            }
            rollForward(id, past: now)
        }
        reschedule(now: now)
    }

    private func play(_ id: String, now: Date) {
        guard let character = character(id), var stage = stages[id] else { return }
        let clock = clock(for: character)
        // Fold the finished flourishes into the facing, so the list stays one long.
        let facing = clock.pose(at: now, stage: stage, still: true).mirrored
        let anchor = stage.plays.last.map(clock.end(of:)) ?? stage.since
        stage = CompanionStage(since: anchor, turned: facing, plays: [now])
        stages[id] = stage
        lastPlay[id] = now
        busyUntil = clock.end(of: now)
        // Its own next moment comes no sooner than a minute after this one.
        if let next = due[id], next.date < now.addingTimeInterval(CompanionSchedule.rest), !launch.demos(id) {
            due[id] = (now.addingTimeInterval(CompanionSchedule.rest), next.index)
        }
        reschedule(now: now)
    }

    /// Sleeps until the earliest moment among the companions that may flourish now; no timer otherwise.
    private func reschedule(now: Date) {
        timer?.cancel()
        timer = nil
        nextMoment = nil
        guard isAppActive, !isLowPower else { return }
        let candidates = stages.keys.filter { !(calm[$0] ?? true) }
        guard let next = candidates.compactMap({ due[$0]?.date }).min() else { return }
        nextMoment = next
        guard runsTimer else { timer = Task {}; return }
        let wait = max(0.05, next.timeIntervalSince(now))
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    // MARK: - The system

    func setAppActive(_ active: Bool, now: Date = .now) {
        guard active != isAppActive, launch.demo.isEmpty else { return }
        isAppActive = active
        if active {
            // Coming back is arriving on the screen again: 20 quiet seconds first.
            for id in stages.keys { activeSince[id] = now }
            for id in stages.keys { rollForward(id, past: now) }
        }
        reschedule(now: now)
    }

    func setLowPower(_ on: Bool, now: Date = .now) {
        guard on != isLowPower else { return }
        isLowPower = on
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
