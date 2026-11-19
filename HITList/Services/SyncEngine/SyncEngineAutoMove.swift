import Foundation
import CloudKit
import OSLog
import SwiftData
import HITListCore

/// The move to the new sync made by the app itself (round 33, brief 167; made fit for everyone in round 34;
/// `dev/SYNC-ENGINE.md` section 14, stage 6). George, 2026-11-18: "I'd even rather the update just automatically move
/// their tasks after we've confirmed the new engine is working. The less technical stuff my friends have to deal
/// with, the better", and that evening: "I also want it to force everyone to move over to the new sync engine so we
/// can settle this once and for all."
///
/// **On from 0.9.16** (`SyncEngineSwitch.movesByItself`), and it moves the first device of an account only after
/// George has said so (R0). With the constant false `Runner.start` returns before it reads, looks for or arms
/// anything (`SyncEngineAutoMoveTests` proves it). The rules, each with a test of its name:
///
/// - **R0 George's word.** One record in the public database of the engine's container (`SyncEngineRollout`, brief
///   170), asked when it is needed and again, at most every half hour, when the app comes forward or the mirror's
///   state changes while the answer was not yes. No record, a paused one, or no answer: no account starts to move.
///   This is how one build reaches everyone and still lets George see the engine on his own devices first (he moves
///   those by hand, from the hidden group), and how he can stop the accounts that have not started if a friend
///   reports trouble.
/// - **R1 When.** Only on a launch on the mirror, with the mirror running on the store's own file, signed in, no move
///   waiting, no store reset waiting, never moved by itself before and never moved back by hand, and only once the
///   mirror has caught up in this launch: its bolt is filled, or its comparison found only what this device holds
///   and iCloud's earlier copy lacks (the engine sends that itself). What a device has not yet received from the
///   mirror would be left behind in the earlier sync's zone, so a device that still lacks something waits. **A
///   device whose mirror never catches up is not left on it alone for good**: seven days and three launches after
///   it was first ready, it moves with what it holds, and the sync log says how many records stay in the earlier
///   sync's zone (kept there, not deleted). Then the hand move's own steps (`SyncEngine.move`): a backup that
///   succeeded, the rows that share an `id` merged, the preference written. It takes effect at the next launch, and
///   the app sees to that launch itself at the first quiet moment (`SyncEngineMoveFinish`). At most one try per
///   launch; a try that failed is written in the sync log and tried again at a later launch, never in a loop.
/// - **R2 A device follows its own account.** One look per launch on the mirror for the engine's zone in the
///   engine's container (one CloudKit call, no record read), and again no sooner than half an hour later when the
///   app comes forward. Found: another device of this account has moved, so this one moves as soon as R1 allows,
///   **whatever George's word says now** (a pause must never leave one person's devices on two syncs), and until it
///   has, the line says it is waiting to join. A device on a build before this one cannot look, so the moved device
///   says that the other devices need the update.
/// - **Always a merge.** A device that moves keeps its own store and merges it with what the engine's zone holds
///   (`dev/SYNC-ENGINE.md` section 7). Round 33 had a third rule, by which a freshly installed device set its store
///   aside and took the engine's copy; the review of round 34 (brief 171) showed that the merge already does the
///   right thing with a stale copy (an item deleted on the engine since stays deleted, an item changed since keeps
///   the change), and that taking a copy could hide everything when the engine's zone was not yet whole. It is gone.
/// - **R4 Words.** One line, nothing to tap (`line`); the hidden group stays as the way back.
enum SyncEngineAutoMove {
    typealias Engine = SyncEngineBoard.Engine

    // MARK: - What a launch knows

    /// The result of the look for the engine's zone.
    enum ZoneLook: Equatable, Sendable {
        /// Not looked yet (or still looking).
        case notYet
        case found
        case absent
        /// The look could not be made (offline, iCloud busy): known as nothing.
        case unknown
    }

    /// George's word that every device may move (R0), as this launch knows it.
    enum Word: Equatable, Sendable {
        case notAsked
        /// The record is there and allows this build.
        case go
        /// No record, or one for a later build.
        case notYet
        case paused
        /// iCloud could not be asked (offline, busy, the type not yet deployed): known as no.
        case unknown
    }

    struct Facts: Equatable, Sendable {
        /// `SyncEngineSwitch.movesByItself`, or a Debug side store's `-syncEngineAutoMove YES`.
        var isOn: Bool
        /// The engine this launch runs, and the store's preference (they differ while a move waits).
        var engine: Engine
        var preferred: Engine
        /// A Debug argument chose the engine: the preference says nothing.
        var byArgument = false
        var inMemory = false
        /// SwiftData's mirror runs on this launch (`ModelContainerFactory.isCloudKitEnabled`).
        var mirrorRunning = true
        var signedIn = true
        /// The mirror has caught up in this launch (`caughtUp(_:difference:)`).
        var caughtUp = false
        /// Seven days and three launches since this store was first ready to move and the mirror had not caught up.
        var waitedLongEnough = false
        var word: Word = .notAsked
        /// Settings → Reset local cache waits for the next launch.
        var resetWaiting = false
        /// This store was moved by itself before, or moved back by hand: never again by itself.
        var movedBefore = false
        var triedThisLaunch = false
        var zone: ZoneLook = .notYet
    }

    enum Why: String, Equatable, Sendable {
        case off, onEngine, moveWaiting, argument, inMemory, mirrorOff, movedBefore, triedThisLaunch
        case signedOut, resetWaiting, zoneNotLooked, wordNotAsked, notReleased, paused, wordUnknown, mirrorBehind
    }

    enum Decision: Equatable, Sendable {
        /// Nothing this launch, whatever happens next.
        case never(Why)
        /// Not yet: asked again when the mirror's state changes, the app comes forward, the look or the word ends.
        case wait(Why)
        /// Move now.
        case move
    }

    // MARK: - The rules (pure)

    /// R0 to R2: what this launch should do.
    static func decide(_ f: Facts) -> Decision {
        guard f.isOn else { return .never(.off) }
        if f.engine == .own { return .never(.onEngine) }
        if f.byArgument { return .never(.argument) }
        if f.preferred == .own { return .never(.moveWaiting) }
        if f.inMemory { return .never(.inMemory) }
        if !f.mirrorRunning { return .never(.mirrorOff) }
        if f.movedBefore { return .never(.movedBefore) }
        if f.triedThisLaunch { return .never(.triedThisLaunch) }
        if !f.signedIn { return .wait(.signedOut) }
        if f.resetWaiting { return .wait(.resetWaiting) }
        // R2: the look comes first. A device whose account has already moved follows it, whatever the word says.
        if f.zone == .notYet { return .wait(.zoneNotLooked) }
        if f.zone != .found {
            // R0: the first device of an account waits for George's word.
            switch f.word {
            case .notAsked: return .wait(.wordNotAsked)
            case .notYet: return .wait(.notReleased)
            case .paused: return .wait(.paused)
            case .unknown: return .wait(.wordUnknown)
            case .go: break
            }
        }
        if !f.caughtUp, !f.waitedLongEnough { return .wait(.mirrorBehind) }
        return .move
    }

    /// R0: whether this launch asks for George's word now. Once when it is first needed; again, no sooner than
    /// `askAgainAfter`, while the answer was not yes (the caller passes how long ago it asked).
    static func shouldAsk(_ f: Facts, sinceLastAsk: TimeInterval?) -> Bool {
        switch decide(f) {
        case .wait(.wordNotAsked): return true
        case .wait(.notReleased), .wait(.paused), .wait(.wordUnknown):
            guard let sinceLastAsk else { return true }
            return sinceLastAsk >= askAgainAfter
        default: return false
        }
    }

    /// R2: whether this launch looks for the engine's zone now. Once when nothing is known; again, no sooner than
    /// `askAgainAfter`, while the device still waits for the word (another of the account's devices may have moved
    /// meanwhile, by hand or because the word reached it first).
    static func shouldLook(_ f: Facts, sinceLastLook: TimeInterval?) -> Bool {
        switch decide(f) {
        case .wait(.zoneNotLooked): return true
        case .wait(.notReleased), .wait(.paused), .wait(.wordUnknown):
            guard let sinceLastLook else { return true }
            return sinceLastLook >= askAgainAfter
        default: return false
        }
    }

    /// How long before a "not yet" is asked again in one launch (a Mac stays open for weeks): events ask, never a timer.
    static let askAgainAfter: TimeInterval = 30 * 60

    /// R1's patience: how long, and over how many launches, a device waits for a mirror that does not catch up.
    static let patience: TimeInterval = 7 * 86_400
    static let patientLaunches = 3
    static var patientDays: Int { Int(patience / 86_400) }

    static func waitedLongEnough(readySince: Date?, launches: Int, now: Date) -> Bool {
        guard let readySince else { return false }
        return now.timeIntervalSince(readySince) >= patience && launches >= patientLaunches
    }

    /// R1: the mirror has caught up when its bolt is filled, or when its comparison (two reads that agreed,
    /// `SyncRecordCheck`) found only what this device holds and iCloud's earlier copy lacks or holds older: the
    /// engine sends that itself. A record only iCloud holds, or holds newer, this device has not taken yet (a first
    /// download still running, or one the mirror never brought): moving now would leave it behind.
    static func caughtUp(_ state: SyncState, difference: SyncRecordCheck.Difference?) -> Bool {
        if state.isSynced { return true }
        guard case .differs = state, let difference, !difference.isEmpty else { return false }
        return leftBehind(difference) == 0
    }

    /// How many records only the earlier sync's iCloud holds, or holds newer: what a move now would leave there.
    static func leftBehind(_ difference: SyncRecordCheck.Difference?) -> Int {
        guard let difference else { return 0 }
        return difference.items.filter { $0.kind == .onlyThere || $0.kind == .newerThere }.count
    }

    // MARK: - The words (R4)

    /// The one line a person sees, or nil: while this device waits to join (another device moved), and once the move
    /// is written and waits for the app to start again.
    static func line(zone: ZoneLook, moved: Bool) -> String? {
        if moved { return "Moving to the new sync: HITList finishes the next time it opens. Nothing to do." }
        if zone == .found { return "Waiting to join the new sync: HITList moves this device once it's up to date." }
        return nil
    }

    /// Said on a device that moved by itself (the switch group, on the engine): a device on an older build cannot know.
    static let otherDevicesNote = "This device moved to the new sync by itself. Your other devices join it once they "
        + "run the latest HITList: update them soon, so a change made on one reaches the others."

    // MARK: - What a store remembers (App Group defaults, a key per store)

    static func movedAtKey(_ store: String) -> String { "syncEngine.autoMove.movedAt.\(store)" }
    static func stayKey(_ store: String) -> String { "syncEngine.autoMove.stay.\(store)" }
    static func failureKey(_ store: String) -> String { "syncEngine.autoMove.lastFailure.\(store)" }
    /// When this store was first ready to move but for a mirror that had not caught up, and how many launches since.
    static func readySinceKey(_ store: String) -> String { "syncEngine.autoMove.readySince.\(store)" }
    static func readyLaunchesKey(_ store: String) -> String { "syncEngine.autoMove.readyLaunches.\(store)" }

    static func movedBefore(store: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: movedAtKey(store)) != nil || defaults.bool(forKey: stayKey(store))
    }

    static func movedByItself(store: String = ModelContainerFactory.storeName,
                              defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: movedAtKey(store)) != nil
    }

    /// Whether this process is a Debug build on a side store launched with `-syncEngineAutoMove YES`: the rehearsal's
    /// way to run the move by itself without the constant.
    static func debugAsked(storeName: String, isDebug: Bool, arguments: [String]) -> Bool {
        guard isDebug, storeName != ModelContainerFactory.mainStoreName,
              let index = arguments.lastIndex(of: "-syncEngineAutoMove"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "YES"
    }

    static func isOn(constant: Bool = SyncEngineSwitch.movesByItself, storeName: String = ModelContainerFactory.storeName,
                     isDebug: Bool = SyncEngineSwitch.isDebugBuild, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        constant || debugAsked(storeName: storeName, isDebug: isDebug, arguments: arguments)
    }
}

// MARK: - The look for the engine's zone

/// One question to iCloud: is the engine's zone there? A stand-in answers it in the tests.
protocol SyncEngineZoneLooking: Sendable {
    func zoneExists() async throws -> Bool
}

/// The look on CloudKit: the engine's container only, the zone's own record, never an item's.
struct CloudKitZoneLook: SyncEngineZoneLooking {
    let containerID: String
    let zoneName: String

    func zoneExists() async throws -> Bool {
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        do {
            _ = try await database.recordZone(for: CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName))
            return true
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return false
        }
    }
}

// MARK: - George's word

/// One question to iCloud: has George said that every device may move? A stand-in answers it in the tests. It never
/// throws: what cannot be asked is `.unknown`, which is a no.
protocol SyncEngineWordAsking: Sendable {
    func ask() async -> SyncEngineAutoMove.Word
}

/// The question on CloudKit: the one record of `SyncEngineRollout` (brief 170), which writes its own line in the
/// sync log for each answer.
struct CloudKitWord: SyncEngineWordAsking {
    func ask() async -> SyncEngineAutoMove.Word {
        let answer = await CloudKitRollout(log: { CloudSyncMonitor.shared.write(.note, $0) }).answer()
        switch answer {
        case .go: return .go
        case .notYet: return .notYet
        case .paused: return .paused
        case .unknown: return .unknown
        }
    }
}

// MARK: - The launch's side

extension SyncEngineAutoMove {
    /// What the app gives the runner: read afresh at each decision, so the tests give their own.
    struct Live {
        var engine: @MainActor () -> Engine = { SyncEngineSwitch.current }
        var byArgument: @MainActor () -> Bool = { SyncEngineSwitch.launchedByArgument }
        var inMemory: @MainActor () -> Bool = { ModelContainerFactory.isRunningInMemory }
        var mirrorRunning: @MainActor () -> Bool = { ModelContainerFactory.isCloudKitEnabled }
        var signedIn: @MainActor () -> Bool = { CloudSyncMonitor.shared.accountStatus == .available }
        var caughtUp: @MainActor () -> Bool = {
            SyncEngineAutoMove.caughtUp(CloudSyncMonitor.shared.state, difference: CloudSyncMonitor.shared.recordDifference)
        }
        /// What a move now would leave in the earlier sync's zone (for the log, when patience ran out).
        var leftBehind: @MainActor () -> Int = { SyncEngineAutoMove.leftBehind(CloudSyncMonitor.shared.recordDifference) }
        var now: @MainActor () -> Date = { Date() }
        var log: @MainActor (String) -> Void = { CloudSyncMonitor.shared.write(.note, $0) }
        /// The hand move's steps, without a relaunch.
        var move: @MainActor () async throws -> Void
    }

    /// Runs the rules for this launch: the look, George's word where it is needed, then a decision each time the
    /// mirror's state changes or the app comes forward.
    @MainActor
    @Observable
    final class Runner {
        /// This launch's runner, while the move is on (nil when off: nothing was made).
        static private(set) var shared: Runner?

        /// The line a person sees (R4), or nil.
        private(set) var line: String?
        /// George's word as this launch knows it.
        private(set) var word: Word = .notAsked

        @ObservationIgnored let storeName: String
        @ObservationIgnored let defaults: UserDefaults
        @ObservationIgnored private let live: Live
        @ObservationIgnored private let look: SyncEngineZoneLooking
        @ObservationIgnored private let asker: SyncEngineWordAsking
        @ObservationIgnored private(set) var zone: ZoneLook = .notYet
        @ObservationIgnored private(set) var looks = 0
        @ObservationIgnored private(set) var asks = 0
        @ObservationIgnored private(set) var tried = false
        @ObservationIgnored private var lastLooked: Date?
        @ObservationIgnored private var lastAsked: Date?
        @ObservationIgnored private var isLooking = false
        @ObservationIgnored private var isAsking = false
        @ObservationIgnored private var countedThisLaunch = false
        @ObservationIgnored private var watching = false
        /// The move, the look and the question in flight (the tests wait for them).
        @ObservationIgnored private(set) var moving: Task<Void, Never>?
        @ObservationIgnored private(set) var looking: Task<Void, Never>?
        @ObservationIgnored private(set) var asking: Task<Void, Never>?

        init(storeName: String, defaults: UserDefaults, live: Live, look: SyncEngineZoneLooking, asker: SyncEngineWordAsking) {
            self.storeName = storeName
            self.defaults = defaults
            self.live = live
            self.look = look
            self.asker = asker
        }

        /// From `HITListApp.init`, after the engine's own launch. With the move off: returns at once and makes
        /// nothing (no look, no question, no observer, no key read or written).
        @discardableResult
        static func start(container: ModelContainer, isOn: Bool = SyncEngineAutoMove.isOn()) -> Runner? {
            guard isOn else { return nil }
            let storeName = ModelContainerFactory.storeName
            let zone = SyncEngineSwitch.zoneName(storeName: storeName, isDebug: SyncEngineSwitch.isDebugBuild,
                                                 arguments: ProcessInfo.processInfo.arguments)
            var live = Live(move: {
                try await SyncEngine.move(to: .own, container: container, relaunch: false)
            })
            #if DEBUG
            if storeName != ModelContainerFactory.mainStoreName {
                // A rehearsal reads the move's lines from the app's standard output, on a phone as on a Mac.
                live.log = { line in
                    CloudSyncMonitor.shared.write(.note, line)
                    print("REHEARSAL automove: \(line)")
                    fflush(stdout)
                }
            }
            #endif
            let runner = Runner(storeName: storeName, defaults: AppGroup.defaults, live: live,
                                look: CloudKitZoneLook(containerID: SyncEngineSwitch.containerID, zoneName: zone),
                                asker: CloudKitWord())
            shared = runner
            runner.begin()
            return runner
        }

        /// The first decision (which starts the look where the rules want it), and the watch on the mirror's state.
        func begin() {
            evaluate()
            watchMirror()
        }

        func facts() -> Facts {
            let preferred = SyncEngineSwitch.nextEngine(storeName: storeName, defaults: defaults)
            let waited = SyncEngineAutoMove.waitedLongEnough(
                readySince: defaults.object(forKey: SyncEngineAutoMove.readySinceKey(storeName)) as? Date,
                launches: defaults.integer(forKey: SyncEngineAutoMove.readyLaunchesKey(storeName)), now: live.now())
            return Facts(isOn: true, engine: live.engine(), preferred: preferred, byArgument: live.byArgument(),
                         inMemory: live.inMemory(), mirrorRunning: live.mirrorRunning(), signedIn: live.signedIn(),
                         caughtUp: live.caughtUp(), waitedLongEnough: waited, word: word,
                         resetWaiting: ModelContainerFactory.requestedReset(in: defaults) == storeName,
                         movedBefore: SyncEngineAutoMove.movedBefore(store: storeName, defaults: defaults),
                         triedThisLaunch: tried, zone: zone)
        }

        /// Decides once more, and acts. Returns what was decided (the tests read it).
        @discardableResult
        func evaluate() -> Decision {
            let now = facts()
            let clock = live.now()
            if !isLooking, SyncEngineAutoMove.shouldLook(now, sinceLastLook: lastLooked.map { clock.timeIntervalSince($0) }) {
                lookForZone()
            }
            if !isAsking, SyncEngineAutoMove.shouldAsk(now, sinceLastAsk: lastAsked.map { clock.timeIntervalSince($0) }) {
                askForWord()
            }
            let decision = SyncEngineAutoMove.decide(now)
            switch decision {
            case .move:
                tried = true
                if !now.caughtUp {
                    let left = live.leftBehind()
                    live.log("The earlier sync has not caught up in \(SyncEngineAutoMove.patientDays) days: moving with what this device holds"
                        + (left > 0 ? "; \(left) record(s) that only the earlier sync's iCloud holds stay there (kept, not deleted)" : ""))
                }
                moving = Task { await self.move() }
            case .wait(.mirrorBehind):
                countReadyLaunch()
            default:
                break
            }
            refreshLine()
            return decision
        }

        /// The app came forward: a "not yet" may have become a yes, or another device may have moved.
        func cameForward() {
            guard !tried else { return }
            evaluate()
        }

        /// The move, once: the hand move's steps, then the store remembers it was moved by itself.
        func move() async {
            tried = true
            guard !SyncEngineAutoMove.movedBefore(store: storeName, defaults: defaults) else { return }
            do {
                try await live.move()
                defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(storeName))
                defaults.removeObject(forKey: SyncEngineAutoMove.failureKey(storeName))
                defaults.removeObject(forKey: SyncEngineAutoMove.readySinceKey(storeName))
                defaults.removeObject(forKey: SyncEngineAutoMove.readyLaunchesKey(storeName))
                live.log("Moved to the new sync by itself, after a backup; finishes at the next launch")
                SyncEngineMoveFinish.moveWritten()
            } catch {
                let words = SyncEngineWords.error(error)
                defaults.set("\(ISO8601DateFormatter().string(from: Date())) \(words)", forKey: SyncEngineAutoMove.failureKey(storeName))
                live.log("The move to the new sync didn't happen: \(words). HITList tries again at its next launch")
            }
            refreshLine()
        }

        /// R1's patience is counted from the first launch that was ready but for the mirror, once per launch.
        private func countReadyLaunch() {
            guard !countedThisLaunch else { return }
            countedThisLaunch = true
            if defaults.object(forKey: SyncEngineAutoMove.readySinceKey(storeName)) == nil {
                defaults.set(live.now(), forKey: SyncEngineAutoMove.readySinceKey(storeName))
            }
            defaults.set(defaults.integer(forKey: SyncEngineAutoMove.readyLaunchesKey(storeName)) + 1,
                         forKey: SyncEngineAutoMove.readyLaunchesKey(storeName))
        }

        private func lookForZone() {
            looks += 1
            isLooking = true
            lastLooked = live.now()
            let look = self.look
            looking = Task {
                let result: ZoneLook
                do { result = try await look.zoneExists() ? .found : .absent } catch { result = .unknown }
                self.zoneLooked(result)
            }
        }

        func zoneLooked(_ result: ZoneLook) {
            isLooking = false
            if result != zone {
                live.log("Looked for the new sync's zone: \(result == .found ? "found, another device has moved" : result == .absent ? "not there" : "couldn't tell")")
            }
            zone = result
            evaluate()
        }

        private func askForWord() {
            asks += 1
            isAsking = true
            lastAsked = live.now()
            let asker = self.asker
            asking = Task {
                let answer = await asker.ask()
                self.wordAnswered(answer)
            }
        }

        func wordAnswered(_ answer: Word) {
            isAsking = false
            word = answer
            evaluate()
        }

        private func refreshLine() {
            let moved = SyncEngineSwitch.nextEngine(storeName: storeName, defaults: defaults) == .own
                && live.engine() == .mirror
            line = SyncEngineAutoMove.line(zone: zone, moved: moved)
        }

        /// Each change of the mirror's marks asks again (no timer).
        private func watchMirror() {
            guard !watching else { return }
            watching = true
            withObservationTracking {
                _ = CloudSyncMonitor.shared.state
                _ = CloudSyncMonitor.shared.accountStatus
                _ = CloudSyncMonitor.shared.recordDifference
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.watching = false
                    guard !self.tried else { return }
                    self.evaluate()
                    self.watchMirror()
                }
            }
        }
    }
}
