import Foundation
import CloudKit
import OSLog
import SwiftData
import HITListCore

/// The move to the new sync made by the app itself (round 33, brief 167; `dev/SYNC-ENGINE.md` section 14, stage 6).
/// George, 2026-11-18: "I'd even rather the update just automatically move their tasks after we've confirmed the new
/// engine is working. The less technical stuff my friends have to deal with, the better."
///
/// **Off** while `SyncEngineSwitch.movesByItself` is false (0.9.15): `Runner.start` then returns before it reads,
/// looks for or arms anything, and the launch is today's (`SyncEngineAutoMoveTests` proves it). The rules, each with
/// a test of its name:
///
/// - **R1 When.** Only on a launch on the mirror, with the mirror running on the store's own file, signed in, no move
///   waiting, no store reset waiting, never moved by itself before and never moved back by hand, and only once the
///   mirror's bolt is filled (the condition the hand move's warning reads): what a device has not yet received would
///   be missing from what it sends. Then the hand move's own steps (`SyncEngine.move`): a backup that succeeded, the
///   rows that share an `id` merged, the preference written. It takes effect at the next launch, on every platform:
///   no relaunch nobody asked for, the Mac included. At most one try per launch; a try that failed is written in the
///   sync log and tried again at a later launch, never in a loop.
/// - **R2 Another device moved.** One look per launch on the mirror for the engine's zone in the engine's container
///   (one CloudKit call, no record read). Found: this device moves as soon as R1 allows, and until it has, the line
///   says it is waiting to join the new sync. A device on a build before this one cannot look, so the moved device
///   says that the other devices need the update.
/// - **R3 A store with nothing of its own.** A store first opened by a build that moves by itself (`freshSince`,
///   written by `SyncEngineSwitch.decideForLaunch` when the file is not there yet) in which no item was made or
///   changed after that moment, except the untouched seeds and profile this device made itself, and which finds the
///   engine's zone, takes the engine's copy: the store is set aside at the next launch (never deleted) and the engine
///   downloads into a new one. Anything else (a store from an older build, an item changed here, a look that failed)
///   is the safe side: an ordinary merge, in which items may come back and nothing is lost. A change made after the
///   move was written turns it back into an ordinary merge before the reopen.
/// - **R4 Words.** One line, nothing to tap (`line`); the hidden group stays as the way back.
enum SyncEngineAutoMove {
    typealias Engine = SyncEngineBoard.Engine

    // MARK: - What a launch knows

    /// The result of the one look for the engine's zone.
    enum ZoneLook: Equatable, Sendable {
        /// Not looked yet (or still looking).
        case notYet
        case found
        case absent
        /// The look could not be made (offline, iCloud busy): known as nothing.
        case unknown
    }

    /// Whether the store holds anything of this device's own (R3).
    enum Ownership: Equatable, Sendable {
        case nothingOfItsOwn
        case holdsItsOwn
        /// Not known (the store was opened before a build that moves by itself): the safe side, merge.
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
        /// The mirror's bolt is filled (`CloudSyncMonitor.state.isSynced`).
        var boltFilled = false
        /// Settings → Reset local cache, or a fresh copy, waits for the next launch.
        var resetWaiting = false
        /// This store was moved by itself before, or moved back by hand: never again by itself.
        var movedBefore = false
        var triedThisLaunch = false
        var zone: ZoneLook = .notYet
        var ownership: Ownership = .unknown
    }

    enum Why: String, Equatable, Sendable {
        case off, onEngine, moveWaiting, argument, inMemory, mirrorOff, movedBefore, triedThisLaunch
        case signedOut, resetWaiting, boltNotFilled, zoneNotLooked
    }

    enum Decision: Equatable, Sendable {
        /// Nothing this launch, whatever happens next.
        case never(Why)
        /// Not yet: asked again when the mirror's state changes or the look ends.
        case wait(Why)
        /// Move now; `freshCopy`: take the engine's copy (R3).
        case move(freshCopy: Bool)
    }

    // MARK: - The rules (pure)

    /// R1 to R3: what this launch should do.
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
        // The look decides between a merge and the engine's copy: it is waited for, once.
        if f.zone == .notYet { return .wait(.zoneNotLooked) }
        if !f.boltFilled { return .wait(.boltNotFilled) }
        return .move(freshCopy: f.zone == .found && f.ownership == .nothingOfItsOwn)
    }

    /// R2: whether this launch looks for the engine's zone (once; the caller keeps "once").
    static func shouldLook(_ f: Facts) -> Bool {
        guard f.zone == .notYet else { return false }
        switch decide(f) {
        case .never: return false
        case .wait(let why): return why != .signedOut
        case .move: return false
        }
    }

    /// One row of the store, for R3.
    struct Row: Equatable, Sendable {
        let id: UUID
        let createdAt: Date
        let updatedAt: Date
        var isProfile = false
    }

    /// R3: whether the store holds anything of this device's own. An item made or changed after `freshSince` is the
    /// device's own, except a seed (a name-based id, `SeedIdentity`) or the profile this device made and nobody
    /// changed since (`updatedAt` within a second of `createdAt`). Without `freshSince`: not known.
    static func ownership(rows: [Row], freshSince: Date?) -> Ownership {
        guard let freshSince else { return .unknown }
        for row in rows where row.updatedAt > freshSince {
            let untouched = abs(row.updatedAt.timeIntervalSince(row.createdAt)) < 1
            if untouched, row.isProfile || isSeedID(row.id) { continue }
            return .holdsItsOwn
        }
        return .nothingOfItsOwn
    }

    /// Seeds' ids are name-based (RFC 4122 version 5, `SeedIdentity`); everything else is random (version 4).
    static func isSeedID(_ id: UUID) -> Bool { (id.uuid.6 >> 4) == 5 }

    // MARK: - The words (R4)

    /// The one line a person sees, or nil: while this device waits to join (another device moved), and once the move
    /// is written and waits for the app to open again.
    static func line(zone: ZoneLook, moved: Bool, freshCopy: Bool) -> String? {
        if moved {
            return freshCopy
                ? "Moving to the new sync: HITList finishes the next time it opens, and brings your tasks down from iCloud."
                : "Moving to the new sync: HITList finishes the next time it opens. Nothing to do."
        }
        if zone == .found { return "Waiting to join the new sync: HITList moves this device once it's up to date." }
        return nil
    }

    /// Said on a device that moved by itself (the switch group, on the engine): a device on an older build cannot know.
    static let otherDevicesNote = "This device moved to the new sync by itself. Your other devices join it once they "
        + "run the latest HITList: update them soon, so a change made on one reaches the others."

    // MARK: - What a store remembers (App Group defaults, a key per store)

    static func movedAtKey(_ store: String) -> String { "syncEngine.autoMove.movedAt.\(store)" }
    static func stayKey(_ store: String) -> String { "syncEngine.autoMove.stay.\(store)" }
    static func freshSinceKey(_ store: String) -> String { "syncEngine.autoMove.freshSince.\(store)" }
    static func failureKey(_ store: String) -> String { "syncEngine.autoMove.lastFailure.\(store)" }

    static func movedBefore(store: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: movedAtKey(store)) != nil || defaults.bool(forKey: stayKey(store))
    }

    static func movedByItself(store: String = ModelContainerFactory.storeName,
                              defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: movedAtKey(store)) != nil
    }

    /// Written by `SyncEngineSwitch.decideForLaunch` when the store's file is not there yet and the move is on.
    static func noteFreshStore(store: String, fileExists: Bool, isOn: Bool, now: Date = Date(), defaults: UserDefaults) {
        guard isOn, !fileExists, defaults.object(forKey: freshSinceKey(store)) == nil else { return }
        defaults.set(now, forKey: freshSinceKey(store))
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

    /// The store's rows, for R3.
    @MainActor
    static func rows(in context: ModelContext) -> [Row] {
        func all<M: PersistentModel>(_ type: M.Type, _ row: (M) -> Row) -> [Row] {
            ((try? context.fetch(FetchDescriptor<M>())) ?? []).map(row)
        }
        return all(TaskItem.self) { Row(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            + all(Project.self) { Row(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            + all(TaskLabel.self) { Row(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            + all(SavedFilter.self) { Row(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            + all(Switchboard.self) { Row(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
            + all(Profile.self) { Row(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, isProfile: true) }
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

// MARK: - The launch's side

extension SyncEngineAutoMove {
    /// What the app gives the runner: read afresh at each decision, so the tests give their own.
    struct Live {
        var engine: @MainActor () -> Engine = { SyncEngineSwitch.current }
        var byArgument: @MainActor () -> Bool = { SyncEngineSwitch.launchedByArgument }
        var inMemory: @MainActor () -> Bool = { ModelContainerFactory.isRunningInMemory }
        var mirrorRunning: @MainActor () -> Bool = { ModelContainerFactory.isCloudKitEnabled }
        var signedIn: @MainActor () -> Bool = { CloudSyncMonitor.shared.accountStatus == .available }
        var boltFilled: @MainActor () -> Bool = { CloudSyncMonitor.shared.state.isSynced }
        var log: @MainActor (String) -> Void = { CloudSyncMonitor.shared.write(.note, $0) }
        /// The hand move's steps, without a relaunch.
        var move: @MainActor (_ freshCopy: Bool) async throws -> Void
    }

    /// Runs the rules for this launch: one look, then a decision each time the mirror's state changes.
    @MainActor
    @Observable
    final class Runner {
        /// This launch's runner, while the move is on (nil when off: nothing was made).
        static private(set) var shared: Runner?

        /// The line a person sees (R4), or nil.
        private(set) var line: String?

        @ObservationIgnored let storeName: String
        @ObservationIgnored let defaults: UserDefaults
        @ObservationIgnored private let live: Live
        @ObservationIgnored private let look: SyncEngineZoneLooking
        @ObservationIgnored private let rows: @MainActor () -> [Row]
        @ObservationIgnored private(set) var zone: ZoneLook = .notYet
        @ObservationIgnored private(set) var looks = 0
        @ObservationIgnored private(set) var tried = false
        @ObservationIgnored private(set) var movedWithFreshCopy: Bool?
        @ObservationIgnored private var watching = false
        /// The move and the look in flight (the tests wait for them).
        @ObservationIgnored private(set) var moving: Task<Void, Never>?
        @ObservationIgnored private(set) var looking: Task<Void, Never>?
        @ObservationIgnored private var saveObserver: NSObjectProtocol?

        init(storeName: String, defaults: UserDefaults, live: Live, look: SyncEngineZoneLooking,
             rows: @escaping @MainActor () -> [Row]) {
            self.storeName = storeName
            self.defaults = defaults
            self.live = live
            self.look = look
            self.rows = rows
        }

        /// From `HITListApp.init`, after the engine's own launch. With the move off: returns at once and makes
        /// nothing (no look, no observer, no key read or written).
        @discardableResult
        static func start(container: ModelContainer, isOn: Bool = SyncEngineAutoMove.isOn()) -> Runner? {
            guard isOn else { return nil }
            let storeName = ModelContainerFactory.storeName
            let zone = SyncEngineSwitch.zoneName(storeName: storeName, isDebug: SyncEngineSwitch.isDebugBuild,
                                                 arguments: ProcessInfo.processInfo.arguments)
            let live = Live(move: { fresh in
                try await SyncEngine.move(to: .own, container: container, freshCopy: fresh, relaunch: false)
            })
            let runner = Runner(storeName: storeName, defaults: AppGroup.defaults, live: live,
                                look: CloudKitZoneLook(containerID: SyncEngineSwitch.containerID, zoneName: zone),
                                rows: { SyncEngineAutoMove.rows(in: container.mainContext) })
            shared = runner
            runner.begin(context: container.mainContext)
            return runner
        }

        /// The look (once, when the rules want it), the first decision, and the watch on the mirror's state.
        func begin(context: ModelContext? = nil) {
            if let context { watchSaves(of: context) }
            evaluate()
            watchMirror()
        }

        func facts() -> Facts {
            let freshSince = defaults.object(forKey: SyncEngineAutoMove.freshSinceKey(storeName)) as? Date
            let preferred = SyncEngineSwitch.nextEngine(storeName: storeName, defaults: defaults)
            return Facts(isOn: true, engine: live.engine(), preferred: preferred, byArgument: live.byArgument(),
                         inMemory: live.inMemory(), mirrorRunning: live.mirrorRunning(), signedIn: live.signedIn(),
                         boltFilled: live.boltFilled(),
                         resetWaiting: ModelContainerFactory.requestedReset(in: defaults) == storeName,
                         movedBefore: SyncEngineAutoMove.movedBefore(store: storeName, defaults: defaults),
                         triedThisLaunch: tried, zone: zone,
                         ownership: SyncEngineAutoMove.ownership(rows: rows(), freshSince: freshSince))
        }

        /// Decides once more, and acts. Returns what was decided (the tests read it).
        @discardableResult
        func evaluate() -> Decision {
            let now = facts()
            if looks == 0, SyncEngineAutoMove.shouldLook(now) { lookForZone() }
            let decision = SyncEngineAutoMove.decide(now)
            if case .move(let fresh) = decision {
                tried = true
                moving = Task { await self.move(freshCopy: fresh) }
            }
            refreshLine()
            return decision
        }

        /// The move, once: the hand move's steps, then the store remembers it was moved by itself.
        func move(freshCopy: Bool) async {
            tried = true
            guard !SyncEngineAutoMove.movedBefore(store: storeName, defaults: defaults) else { return }
            do {
                try await live.move(freshCopy)
                defaults.set(Date(), forKey: SyncEngineAutoMove.movedAtKey(storeName))
                defaults.removeObject(forKey: SyncEngineAutoMove.failureKey(storeName))
                movedWithFreshCopy = freshCopy
                live.log(freshCopy
                    ? "Moved to the new sync by itself, taking its copy (nothing of this device's own); finishes at the next launch"
                    : "Moved to the new sync by itself, after a backup; finishes at the next launch")
            } catch {
                let words = SyncEngineWords.error(error)
                defaults.set("\(ISO8601DateFormatter().string(from: Date())) \(words)", forKey: SyncEngineAutoMove.failureKey(storeName))
                live.log("The move to the new sync didn't happen: \(words). HITList tries again at its next launch")
            }
            refreshLine()
        }

        private func lookForZone() {
            looks += 1
            let look = self.look
            looking = Task {
                let result: ZoneLook
                do { result = try await look.zoneExists() ? .found : .absent } catch { result = .unknown }
                self.zoneLooked(result)
            }
        }

        func zoneLooked(_ result: ZoneLook) {
            zone = result
            live.log("Looked for the new sync's zone: \(result == .found ? "found, another device has moved" : result == .absent ? "not there" : "couldn't tell")")
            evaluate()
        }

        private func refreshLine() {
            let moved = SyncEngineSwitch.nextEngine(storeName: storeName, defaults: defaults) == .own
                && live.engine() == .mirror
            let fresh = moved && ModelContainerFactory.requestedReset(in: defaults) == storeName
            line = SyncEngineAutoMove.line(zone: zone, moved: moved, freshCopy: fresh)
        }

        /// Each change of the mirror's marks asks again (no timer).
        private func watchMirror() {
            guard !watching else { return }
            watching = true
            withObservationTracking {
                _ = CloudSyncMonitor.shared.state
                _ = CloudSyncMonitor.shared.accountStatus
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

        /// R3's last guard: a fresh copy written, then something of the person's made or changed before the reopen
        /// turns it into an ordinary merge (the reset request is taken back), so nothing made in between is set aside.
        private func watchSaves(of context: ModelContext) {
            saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.savedAfterMove() }
            }
        }

        func savedAfterMove() {
            guard movedWithFreshCopy == true,
                  ModelContainerFactory.requestedReset(in: defaults) == storeName else { return }
            let freshSince = defaults.object(forKey: SyncEngineAutoMove.freshSinceKey(storeName)) as? Date
            guard SyncEngineAutoMove.ownership(rows: rows(), freshSince: freshSince) != .nothingOfItsOwn else { return }
            defaults.removeObject(forKey: ModelContainerFactory.resetLocalStoreKey)
            movedWithFreshCopy = false
            live.log("Something changed here after the move to the new sync: this device will merge its copy instead of taking iCloud's")
            refreshLine()
        }
    }
}
