// Compiled into Debug builds only (tests, the Debug app's pretend iCloud): none of this is in a released build. The
// long simulation runs build for release and pass `-Xswiftc -DDEBUG` (the command is in `SyncCoreSimulationTests`).
#if DEBUG
import Foundation

// The rig the engine is proven on (`dev/SYNC-ENGINE.md`, section 9): several simulated devices, each a store, a ledger,
// a `FakeTransport` and a brain, on one `FakeCloud`; scripts of steps, and seeded random runs of people's actions,
// syncs, faults and relaunches; then everyone syncs until quiet and the invariants (`SyncInvariants`) are checked.
//
// The brain is a parameter: in wave 2 `SyncCore` is wrapped to `SimBrain`. Time is the rig's own clock, stepped by the
// rig; nothing sleeps and nothing runs by itself, so a seed is the same run on every machine.

/// What the rig needs of a device's brain, and no more.
public protocol SimBrain: Sendable {
    /// The app launched: read the memory, start the transport (`SyncTransport.start(delegate:)`), look for changes.
    func start() async throws
    /// The app quits cleanly (a crash calls nothing).
    func stop() async
    /// The device's items changed (the keys a save touched; nil: anything may have).
    func localChanged(_ keys: Set<SyncKey>?) async throws
    /// The person's "sync now": a fetch, then a send.
    func syncNow() async throws
}

/// What a brain is made from, for one launch of one device.
public struct SimParts: Sendable {
    public let device: String
    public let store: MemoryLocalStore
    public let ledger: MemoryLedger
    public let transport: FakeTransport
    public let clock: SimClock
    public let log: @Sendable (String) -> Void
}

public typealias SimBrainFactory = @Sendable (SimParts) async -> any SimBrain

/// The rig's clock: it moves only when the rig moves it.
public final class SimClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: Int64

    /// Starts at 2026-09-21 (a fixed moment, so every run is the same run).
    public init(millis: Int64 = 1_790_000_000_000) { ms = millis }

    public var millis: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return ms
    }

    public func now() -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

    public func advance(milliseconds: Int64) {
        lock.lock()
        ms += max(0, milliseconds)
        lock.unlock()
    }

    /// The clock as a brain takes it (`@Sendable () -> Date`).
    public var function: @Sendable () -> Date { { [self] in self.now() } }
}

/// One device as the rig holds it now (a relaunch makes a new transport and brain on the same store).
public struct SimDevice: Sendable {
    public let name: String
    public let store: MemoryLocalStore
    public let ledger: MemoryLedger
    public let transport: FakeTransport
    public let brain: any SimBrain
    /// How many times the device was launched.
    public let launches: Int
}

/// What a person does on a device.
public enum SimAction: Sendable {
    /// Makes an item, or puts one back (an undo: the same key again). `createdAt`/`updatedAt` are stamped now when
    /// missing.
    case put(SyncRecord)
    /// Changes fields of an item that is here (nil empties one); `updatedAt` is stamped now unless given.
    case edit(SyncKey, [String: SyncValue?])
    /// Deletes an item, as the app does: a task's sub-tasks with it, references to it cleared.
    case delete(SyncKey)
}

/// What the app tells the brain after a person's save.
public enum SimHint: Sendable {
    /// The keys the save touched (the app's `didSave`).
    case keys
    /// "Anything may have changed".
    case everything
    /// Nothing: a write the brain must find by comparing (an import, a restore).
    case none
}

/// Something going wrong on one device.
public enum SimFault: Sendable {
    case network(up: Bool)
    case dropNetwork(after: Int)
    case loseNextResponse
    case crash(FakeCrash)
    case deliverTwice(FakeEventKind)
    case loseBookmark
    /// The device signed in to this account (nil: signed out); the running transport notices now.
    case account(String?)
    /// The device's store loses these items with no deletion written down (a damaged file, a read that came back
    /// short): nobody deleted them, so nothing may be deleted in iCloud and they must come back (M14).
    case loseRows([SyncKey])
}

/// Something happening in iCloud itself.
public enum SimCloudFault: Sendable {
    case deleteZone(ZoneLoss)
    case quotaFull(Bool)
    case refuseNextSave(SyncKey, SendFailure)
    /// Another (newer) build writes these keys into the record.
    case poke(SyncKey, [String: SyncValue?])
}

extension SimFault: CustomStringConvertible {
    public var description: String {
        switch self {
        case .network(let up): return up ? "network up" : "network down"
        case .dropNetwork(let count): return "network drops after \(count) more batches or pages"
        case .loseNextResponse: return "next answer from iCloud lost"
        case .crash(.afterHandling(let kind)): return "crash after handling the next \(kind.rawValue)"
        case .crash(.beforeSent): return "crash before the next sent"
        case .deliverTwice(let kind): return "deliverTwice the next \(kind.rawValue)"
        case .loseBookmark: return "bookmark lost"
        case .account(let account?): return "account signed in to \(account)"
        case .account(nil): return "account signed out"
        case .loseRows(let keys): return "store loses \(keys.map(\.description).joined(separator: ", ")) (no deletion written down)"
        }
    }
}

extension SimCloudFault: CustomStringConvertible {
    public var description: String {
        switch self {
        case .deleteZone(let reason): return "deleteZone \(reason.rawValue)"
        case .quotaFull(let full): return "quotaFull \(full)"
        case .refuseNextSave(let key, let failure): return "refuseNextSave \(key) \(failure)"
        case .poke(let key, let fields):
            return "poke \(key) " + fields.keys.sorted().map { "\($0) \(SyncInvariants.say(fields[$0] ?? nil))" }.joined(separator: ", ")
        }
    }
}

public enum SimStep: Sendable, CustomStringConvertible {
    case act(String, SimAction, hint: SimHint = .keys)
    case sync(String)
    /// The transport syncs by itself (a push, its schedule: T14).
    case byItself(String)
    /// The transport sends by itself without fetching first (its schedule after changes were added: T14), so that
    /// two devices' saves of one record can meet in iCloud (T6).
    case sendByItself(String)
    case fault(String, SimFault)
    case cloud(SimCloudFault)
    /// The app quits and launches again; without its ledger (a lost file: a merge without a memory), or without
    /// the transport's state only.
    case relaunch(String, keepLedger: Bool = true, keepTransportState: Bool = true)
    case advance(milliseconds: Int64)

    public var description: String {
        switch self {
        case .act(let device, let action, let hint):
            let told = hint == .keys ? "" : (hint == .everything ? " (hint: everything)" : " (no hint)")
            switch action {
            case .put(let record): return "\(device) put \(record.key) \(SyncInvariants.sketch(record))\(told)"
            case .edit(let key, let fields):
                let words = fields.keys.sorted().map { "\($0) \(SyncInvariants.say(fields[$0] ?? nil))" }
                return "\(device) edit \(key) \(words.joined(separator: ", "))\(told)"
            case .delete(let key): return "\(device) delete \(key)\(told)"
            }
        case .sync(let device): return "\(device) sync"
        case .byItself(let device): return "\(device) transport syncs by itself"
        case .sendByItself(let device): return "\(device) transport sends by itself"
        case .fault(let device, let fault): return "\(device) fault \(fault)"
        case .cloud(let fault): return "iCloud \(fault)"
        case .relaunch(let device, let ledger, let state):
            return "\(device) relaunch" + (ledger ? "" : " without its ledger") + (state || !ledger ? "" : " without the transport's state")
        case .advance(let ms): return "clock +\(ms) ms"
        }
    }
}

/// Which faults a random run draws from. `everyday` are those a correct engine must ride out with every invariant
/// holding; the rest change what "correct" means (a memory lost, an account changed, iCloud refusing) and are drawn
/// only when asked for.
public enum SimFaultKind: String, Hashable, Sendable, CaseIterable, Comparable {
    case networkDown, networkDrop, responseLost, crashAfterFetched, crashAfterSent, crashBeforeSent, deliverTwice,
         loseBookmark, transportStateLost, byItself, poke
    case ledgerLost, zoneDeleted, zoneReset, accountSwitch, signOut, quotaFull, refusal
    /// Added by brief 145, outside `everyday` so that the seeds kept before it still play the same runs: a send without
    /// a fetch first (two devices' saves meet: T6), and the person removing HITList's data in iCloud's settings.
    case sendByItself, zonePurged
    /// Added 2026-11-15 with the rule that only a deletion written down is a deletion: a store that loses rows.
    case rowsLost

    public static let everyday: Set<SimFaultKind> = [.networkDown, .networkDrop, .responseLost, .crashAfterFetched,
                                                     .crashAfterSent, .crashBeforeSent, .deliverTwice, .loseBookmark,
                                                     .transportStateLost, .byItself, .poke]

    public static func < (a: SimFaultKind, b: SimFaultKind) -> Bool { a.rawValue < b.rawValue }
}

public struct SimConfig: Sendable {
    /// Each device's transport.
    public var batchSize = 3
    public var fetchPageSize = 4
    public var shuffleFetches = true
    public var echo = true
    /// The faults a random run draws from.
    public var faults: Set<SimFaultKind> = SimFaultKind.everyday
    /// Of a random run's steps, in 100: a sync, a fault, a relaunch; the rest are people's actions.
    public var syncPercent = 25
    public var faultPercent = 6
    public var relaunchPercent = 2
    /// Of people's actions, in 100: the brain is told nothing, or "everything".
    public var silentPercent = 3
    public var everythingPercent = 5
    /// How many rounds of every device syncing "until quiet" may take before that is itself a failure (I7).
    public var quietRounds = 12
    /// The account every device is signed in to, and returns to before the end.
    public var account = FakeCloud.defaultAccount
    /// Where the brains' log lines go (nowhere by default).
    public var log: @Sendable (String) -> Void = { _ in }

    public init() {}
}

/// A random run's result: what to replay it with, and what was found.
public struct SimReport: Sendable, CustomStringConvertible {
    public var seed: UInt64
    public var devices: Int
    public var steps: Int
    public var findings: [SyncFinding]
    /// The steps played, one line each, numbered: the run by hand.
    public var script: [String]
    /// Syncs that failed, crashes, holds: what happened, not what is wrong.
    public var notes: [String]

    public var description: String {
        let head = "seed \(seed), \(devices) devices, \(steps) steps: "
        guard !findings.isEmpty else { return head + "every invariant holds" }
        return head + "\(findings.count) findings\n" + findings.map { "  \($0)" }.joined(separator: "\n")
    }
}

public actor SyncSimulation {
    public let cloud: FakeCloud
    public let clock: SimClock
    public let seed: UInt64
    public let config: SimConfig
    private let factory: SimBrainFactory

    private var slots: [String: SimDevice] = [:]
    public private(set) var intent = SimIntent()
    /// The number of steps played so far.
    public private(set) var step = 0
    public private(set) var script: [String] = []
    public private(set) var notes: [String] = []
    private let observed = Observed()

    // The random run's own memory (what a person could undo, which device is down or away).
    private var random: SimRandom
    private var counter = 0
    private var undo: [String: [SyncRecord]] = [:]
    private var down = Set<String>()
    private var away: [String: String?] = [:]
    private var quotaFull = false
    /// Each device's items as last read, with the store's write count and the rig's own count of what people did
    /// there: a device nothing wrote to since is not read and sorted again.
    private var cache: [String: (writes: Int, acts: Int, records: [SyncRecord])] = [:]
    private var acts: [String: Int] = [:]

    public init(seed: UInt64 = 0, config: SimConfig = SimConfig(), cloud: FakeCloud? = nil, brain: @escaping SimBrainFactory) {
        self.seed = seed
        self.config = config
        self.cloud = cloud ?? FakeCloud(defaultAccount: config.account)
        self.clock = SimClock()
        self.factory = brain
        self.random = SimRandom(seed: seed)
        self.intent.account = config.account
    }

    // MARK: Devices

    public var deviceNames: [String] { slots.keys.sorted() }

    public func device(_ name: String) -> SimDevice? { slots[name] }

    /// A new device: an empty store and ledger, signed in to the run's account, its brain started.
    public func addDevice(_ name: String) async {
        await launch(name, store: MemoryLocalStore(), ledger: MemoryLedger(), launches: 0)
    }

    /// The app quits (cleanly) and launches again on the same store; with a new ledger when `keepLedger` is false,
    /// with the transport's state forgotten when `keepTransportState` is false.
    public func relaunch(_ name: String, keepLedger: Bool = true, keepTransportState: Bool = true) async {
        guard let old = slots[name] else { return }
        if await !old.transport.hasCrashed { await old.brain.stop() }
        var ledger = old.ledger
        if !keepLedger {
            ledger = MemoryLedger()
            intent.recordAmnesia(step: step, device: name)
            observed.forgot(name)
        } else if !keepTransportState {
            await ledger.saveTransportState(nil)
        }
        await launch(name, store: old.store, ledger: ledger, launches: old.launches + 1)
    }

    private func launch(_ name: String, store: MemoryLocalStore, ledger: MemoryLedger, launches: Int) async {
        let options = FakeTransport.Options(batchSize: config.batchSize, fetchPageSize: config.fetchPageSize,
                                            shuffleFetches: config.shuffleFetches, echo: config.echo,
                                            seed: seed &+ UInt64(launches) &* 7919 &+ UInt64(name.unicodeScalars.first?.value ?? 0))
        let transport = FakeTransport(cloud: cloud, device: name, state: ledger, options: options)
        // The network is the device's, not the process's: a relaunch does not bring it back.
        if down.contains(name) { await transport.setNetwork(up: false) }
        let observed = self.observed
        await transport.observe { delivery in
            // A lost zone or an account change empties a correct brain's memory (section 10): from here on a merge
            // without a memory may settle what was changed before, and I2 takes that into account.
            // (A device that has never finished a fetch had nothing to lose: its first sign-in is not a loss.) The
            // memory is lost when no entry keeps a base: a brain keeps the deletions it has not sent yet across the
            // loss, as entries with no base (section 7), and they are no memory of iCloud's records.
            if delivery.round == 0, delivery.kind == .zoneLost || delivery.kind == .account, observed.hasFetched(name),
               ((try? await ledger.entries()) ?? []).allSatisfy({ $0.base == nil }) {
                observed.forgot(name)
            }
            // The first whole fetch after a memory was lost: the device has a base for everything again.
            if delivery.round == 0, delivery.kind == .didFetch, !delivery.failed { observed.fetched(name) }
            // Records that arrived are a memory to lose, whether or not the fetch they came in ended (round 32,
            // refusal seed 672: a device that crashed in its only fetch, then lost its transport's state, held bases
            // for what that fetch brought, and its merge without a memory was not counted).
            if delivery.round == 0, delivery.kind == .fetched { observed.received(name) }
            // I4: the device after the first delivery of an event that comes twice, and after the second.
            if delivery.willRepeat {
                observed.keep(name, await DeviceSnapshot.of(store: store, ledger: ledger, transport: transport))
            } else if delivery.round == 1, let once = observed.take(name) {
                let twice = await DeviceSnapshot.of(store: store, ledger: ledger, transport: transport)
                observed.add(SyncInvariants.twiceIsOnce(device: name, event: "\(delivery.kind.rawValue) at step \(observed.step)",
                                                        once: once, twice: twice))
            }
        }
        let parts = SimParts(device: name, store: store, ledger: ledger, transport: transport, clock: clock, log: config.log)
        let brain = await factory(parts)
        slots[name] = SimDevice(name: name, store: store, ledger: ledger, transport: transport, brain: brain, launches: launches)
        do {
            try await brain.start()
        } catch {
            note("\(name) did not start: \(error)")
        }
        await afterBrainCall(name)
    }

    // MARK: Playing

    public func play(_ steps: [SimStep]) async {
        for one in steps { await play(one) }
    }

    public func play(_ one: SimStep) async {
        step += 1
        observed.step = step
        script.append("\(step) @\(clock.millis): \(one)")
        switch one {
        case .act(let name, let action, let hint):
            await act(name, action, hint: hint)
        case .sync(let name):
            await sync(name)
        case .byItself(let name):
            guard let device = slots[name] else { break }
            await device.transport.syncByItself()
            await afterBrainCall(name)
        case .sendByItself(let name):
            guard let device = slots[name] else { break }
            await device.transport.sendByItself()
            await afterBrainCall(name)
        case .fault(let name, let fault):
            await apply(fault, on: name)
        case .cloud(let fault):
            await apply(fault)
        case .relaunch(let name, let keepLedger, let keepTransportState):
            await relaunch(name, keepLedger: keepLedger, keepTransportState: keepTransportState)
        case .advance(let ms):
            clock.advance(milliseconds: ms)
        }
        await absorb()
    }

    /// What the transports' observers noticed (a memory emptied by a lost zone or an account change), and the
    /// references iCloud saw taken away (I9), into the model, at the step it happened in.
    private func absorb() async {
        for name in observed.takeForgotten() { intent.recordAmnesia(step: step, device: name) }
        intent.recordDrops(step: step, await cloud.takeDrops())
        intent.recordRefusals(step: step, await cloud.takeRefusals())
        await recordZoneExposure()
    }

    /// Once a zone was lost: the items made before it that some device holds without a base from the zone iCloud has
    /// now (none, or one from a zone that is gone). Their copies may meet without a base (M5), a written limit.
    private func recordZoneExposure() async {
        guard let lastLoss = intent.zoneLosses.last else { return }
        let zone = await cloud.incarnation(account: config.account)
        var exposed = Set<SyncKey>()
        for name in deviceNames {
            guard let device = slots[name] else { continue }
            let entries = Dictionary(((try? await device.ledger.entries()) ?? []).map { ($0.key, $0) },
                                     uniquingKeysWith: { first, _ in first })
            for record in await held(device) where !exposed.contains(record.key) {
                let entry = entries[record.key]
                let current = zone != nil && entry?.base?.isDeleted == false
                    && entry?.system.flatMap(FakeCloud.token)?.zone == zone
                if !current, intent.madeBefore(record.key, step: lastLoss) { exposed.insert(record.key) }
            }
        }
        if !exposed.isEmpty { intent.recordZoneExposure(step: step, keys: exposed) }
    }

    private func act(_ name: String, _ action: SimAction, hint: SimHint) async {
        guard let device = slots[name] else { return }
        let now = SyncValue.millis(clock.millis)
        // A put or an edit touches its own item only; a deletion may take sub-tasks with it and clear references
        // anywhere, so it is compared whole.
        let only: SyncKey?
        switch action {
        case .put(let record): only = record.key
        case .edit(let key, _): only = key
        case .delete: only = nil
        }
        let before = await items(device.store, only)
        switch action {
        case .put(var record):
            if record.fields["createdAt"] == nil { record.fields["createdAt"] = now }
            if record.fields[SyncSchema.updatedAt] == nil { record.fields[SyncSchema.updatedAt] = now }
            await device.store.put(record)
        case .edit(let key, var changes):
            if changes[SyncSchema.updatedAt] == nil { changes[SyncSchema.updatedAt] = .some(now) }
            await device.store.edit(key, changes)
        case .delete(let key):
            await device.store.delete(key)
        }
        let after = await items(device.store, only)
        acts[name, default: 0] += 1
        if case .delete = action {
            var blind: [SyncKey] = []
            for key in before.keys.sorted() where after[key] == nil {
                let base = await device.ledger.entry(key)?.base
                if base == nil || base?.isDeleted == true { blind.append(key) }
            }
            if !blind.isEmpty { intent.recordBlindDeletions(step: step, device: name, keys: blind) }
            // A deletion is the person's; the references the store took off the rows that pointed at what went are
            // not (section 8: they are waited for, and come back with the item).
            intent.record(step: step, device: name, before: before, after: before.filter { after[$0.key] != nil })
        } else {
            intent.record(step: step, device: name, before: before, after: after)
        }
        let touched = Set(Set(before.keys).union(after.keys).filter { before[$0] != after[$0] })
        do {
            switch hint {
            case .keys: if !touched.isEmpty { try await device.brain.localChanged(touched) }
            case .everything: try await device.brain.localChanged(nil)
            case .none: break
            }
        } catch {
            note("\(name) localChanged: \(error)")
        }
        await afterBrainCall(name)
    }

    /// The device's "sync now". False when it failed or the process crashed in it.
    @discardableResult
    private func sync(_ name: String) async -> Bool {
        guard let device = slots[name] else { return false }
        var done = true
        do {
            try await device.brain.syncNow()
        } catch {
            note("\(name) sync: \(error)")
            done = false
        }
        if await device.transport.hasCrashed { done = false }
        await afterBrainCall(name)
        return done
    }

    private func apply(_ fault: SimFault, on name: String) async {
        guard let device = slots[name] else { return }
        switch fault {
        case .network(let up):
            if up { down.remove(name) } else { down.insert(name) }
            await device.transport.setNetwork(up: up)
        case .dropNetwork(let count): await device.transport.dropNetwork(after: count)
        case .loseNextResponse: await device.transport.loseNextResponse()
        case .crash(let point): await device.transport.crash(point)
        case .deliverTwice(let kind): await device.transport.deliverTwice(kind)
        case .loseBookmark: await device.transport.loseBookmark()
        case .account(let account):
            await recordAccount(name, to: account)
            await cloud.setAccount(account, for: name)
            await device.transport.noticeChanges()
            await afterBrainCall(name)
        case .loseRows(let keys):
            // Nobody is told: the next whole compare finds them missing.
            for key in keys { await device.store.lose(key) }
        }
    }

    /// The model's side of a sign-in or sign-out (section 10): the items on the device that its ledger holds no living
    /// base for are the ones iCloud never held; they stay on the device and go with it to the next account.
    private func recordAccount(_ name: String, to account: String?) async {
        guard let device = slots[name], await cloud.account(of: name) != account else { return }
        let records = (try? await device.store.records()) ?? []
        let entries = (try? await device.ledger.entries()) ?? []
        let living = Set(entries.filter { $0.base?.isDeleted == false }.map(\.key))
        intent.recordAccount(step: step, device: name, to: account,
                             travelling: records.map(\.key).filter { !living.contains($0) })
    }

    private func apply(_ fault: SimCloudFault) async {
        switch fault {
        case .deleteZone(let reason):
            await cloud.deleteZone(reason, account: config.account)
            intent.recordZoneLoss(step: step)
        case .quotaFull(let full): await cloud.setQuotaFull(full, account: config.account)
        case .refuseNextSave(let key, let failure): await cloud.refuseNextSave(of: key, with: failure)
        case .poke(let key, let fields):
            guard await cloud.record(key, account: config.account) != nil else { return }
            await cloud.poke(key, fields, account: config.account)
            intent.recordPoke(step: step, key: key, fields: fields)
        }
    }

    /// A crashed process is launched again by the person opening the app: from its store and its ledger, as they are.
    private func afterBrainCall(_ name: String) async {
        guard let device = slots[name], await device.transport.hasCrashed else { return }
        note("\(name) crashed at step \(step); launched again")
        await launch(name, store: device.store, ledger: device.ledger, launches: device.launches + 1)
    }

    private func held(_ device: SimDevice) async -> [SyncRecord] {
        let writes = await device.store.applyCount
        let mine = acts[device.name, default: 0]
        if let cached = cache[device.name], cached.writes == writes, cached.acts == mine { return cached.records }
        let records = (try? await device.store.records()) ?? []
        cache[device.name] = (writes, mine, records)
        return records
    }

    private func items(_ store: MemoryLocalStore, _ only: SyncKey? = nil) async -> [SyncKey: SyncRecord] {
        if let only {
            guard let record = await store.record(only) else { return [:] }
            return [only: record]
        }
        let records = (try? await store.records()) ?? []
        return Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func note(_ words: String) {
        if notes.count < 500 { notes.append("step \(step): \(words)") }
    }

    // MARK: The end

    /// Lifts every fault that would keep a device from syncing (the network back, room in iCloud, every device signed
    /// in to the run's account), as a person would before checking.
    public func heal() async {
        await cloud.setQuotaFull(false, account: config.account)
        quotaFull = false
        down = []
        for name in deviceNames {
            guard let device = slots[name] else { continue }
            await device.transport.setNetwork(up: true)
            await device.transport.loseNextResponse(false)
            if await cloud.account(of: name) != config.account {
                await recordAccount(name, to: config.account)
                await cloud.setAccount(config.account, for: name)
                await device.transport.noticeChanges()
                await afterBrainCall(name)
            }
        }
        down = []
        away = [:]
        await absorb()
    }

    /// Every device syncs, in name order, round after round, until a round in which every sync went through, nothing
    /// is waiting anywhere and iCloud did not change (I7). (A sync that crashed or failed halfway may have left the
    /// device short of what iCloud holds, with nothing waiting: not quiet.) `rounds`: how many it took; nil when it was not quiet within `config.quietRounds`,
    /// then `lastRound` is what iCloud accepted in the last one.
    public func syncUntilQuiet() async -> (rounds: Int?, lastRound: [SyncKey]) {
        var lastRound: [SyncKey] = []
        for round in 1...max(1, config.quietRounds) {
            let before = await cloud.records(account: config.account)
            var everyOneWent = true
            for name in deviceNames where await !sync(name) { everyOneWent = false }
            await absorb()
            let after = await cloud.records(account: config.account)
            lastRound = SyncSimulation.changed(before, after)
            var waiting = false
            for name in deviceNames where await !(slots[name]?.transport.pending() ?? []).isEmpty { waiting = true }
            if lastRound.isEmpty, !waiting, everyOneWent { return (round, []) }
        }
        return (nil, lastRound)
    }

    static func changed(_ before: [CloudRecord], _ after: [CloudRecord]) -> [SyncKey] {
        let a = Dictionary(before.map { ($0.key, $0.system) }, uniquingKeysWith: { x, _ in x })
        let b = Dictionary(after.map { ($0.key, $0.system) }, uniquingKeysWith: { x, _ in x })
        return Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted()
    }

    /// What each device holds now.
    public func holdings() async -> [DeviceHoldings] {
        var out: [DeviceHoldings] = []
        for name in deviceNames {
            guard let device = slots[name] else { continue }
            out.append(DeviceHoldings(name: name, records: (try? await device.store.records()) ?? [],
                                      pending: await device.transport.pending()))
        }
        return out
    }

    /// Heals, syncs until quiet, and checks every invariant. Findings in invariant order.
    public func check() async -> [SyncFinding] {
        await heal()
        let quiet = await syncUntilQuiet()
        let devices = await holdings()
        let cloud = await self.cloud.records(account: config.account)
        var findings: [SyncFinding] = []
        findings += SyncInvariants.sameEverywhere(devices: devices, cloud: cloud, except: intent.heldBack)
        findings += SyncInvariants.noLostEdit(devices: devices, cloud: cloud, intent: intent)
        findings += SyncInvariants.nothingComesBack(devices: devices, cloud: cloud, intent: intent)
        findings += observed.findings
        findings += SyncInvariants.oneOfEach(devices: devices)
        findings += SyncInvariants.whole(devices: devices, cloud: cloud)
        findings += SyncInvariants.quiet(devices: devices, savedInExtraRound: quiet.lastRound, rounds: quiet.rounds,
                                         limit: config.quietRounds)
        findings += SyncInvariants.newerFieldsSurvive(cloud: cloud, intent: intent)
        findings += SyncInvariants.referencesKept(intent: intent)
        // I10: every account a device was signed in to holds only its own.
        var owners = Set(intent.accountChanges.compactMap(\.account))
        owners.insert(config.account)
        if owners.count > 1 {
            for owner in owners.sorted() {
                findings += SyncInvariants.accountsApart(owner: owner, cloud: await self.cloud.records(account: owner),
                                                         intent: intent)
            }
        }
        return findings.enumerated().sorted { ($0.element.invariant, $0.offset) < ($1.element.invariant, $1.offset) }.map(\.element)
    }

    // MARK: A seeded random run

    /// `devices` devices (A, B, C, …) on one cloud, `steps` random steps drawn from `seed`, then everyone syncs until
    /// quiet and every invariant is checked. The same seed is the same run.
    public static func randomRun(seed: UInt64, devices: Int = 3, steps: Int = 1000, config: SimConfig = SimConfig(),
                                 brain: @escaping SimBrainFactory) async -> SimReport {
        let sim = SyncSimulation(seed: seed, config: config, brain: brain)
        for index in 0..<max(1, devices) { await sim.addDevice(SyncSimulation.name(index)) }
        await sim.runRandom(steps: steps)
        let findings = await sim.check()
        return SimReport(seed: seed, devices: devices, steps: steps, findings: findings, script: await sim.script,
                         notes: await sim.notes)
    }

    static func name(_ index: Int) -> String {
        index < 26 ? String(UnicodeScalar(UInt8(65 + index))) : "D\(index)"
    }

    /// Plays `count` random steps.
    public func runRandom(steps count: Int) async {
        for _ in 0..<count {
            clock.advance(milliseconds: Int64(1 + random.below(1500)))
            let next = await draw()
            await play(next)
        }
    }

    private func draw() async -> SimStep {
        let names = deviceNames
        guard let name = random.pick(names) else { return .advance(milliseconds: 1) }
        let roll = random.below(100)
        if roll < config.syncPercent { return .sync(name) }
        if roll < config.syncPercent + config.faultPercent, let fault = await drawFault(name) { return fault }
        if roll < config.syncPercent + config.faultPercent + config.relaunchPercent { return .relaunch(name) }
        return await drawAction(name) ?? .sync(name)
    }

    private func drawFault(_ name: String) async -> SimStep? {
        let kinds = config.faults.sorted()
        guard let kind = random.pick(kinds) else { return nil }
        switch kind {
        case .networkDown:
            return .fault(name, .network(up: down.contains(name)))
        case .networkDrop: return .fault(name, .dropNetwork(after: random.below(3)))
        case .responseLost: return .fault(name, .loseNextResponse)
        case .crashAfterFetched: return .fault(name, .crash(.afterHandling(.fetched)))
        case .crashAfterSent: return .fault(name, .crash(.afterHandling(.sent)))
        case .crashBeforeSent: return .fault(name, .crash(.beforeSent))
        case .deliverTwice: return .fault(name, .deliverTwice(random.chance(50) ? .fetched : .sent))
        case .loseBookmark: return .fault(name, .loseBookmark)
        case .transportStateLost: return .relaunch(name, keepLedger: true, keepTransportState: false)
        case .byItself: return .byItself(name)
        case .poke:
            let alive = await cloud.records(account: config.account).filter { !$0.record.isDeleted && SyncSchema.type($0.key.type) != nil }
            guard let target = random.pick(alive) else { return nil }
            counter += 1
            return .cloud(.poke(target.key, ["futureField": .string("from a newer build \(counter)")]))
        case .rowsLost:
            guard let device = slots[name] else { return nil }
            let records = (try? await device.store.records()) ?? []
            let entries = (try? await device.ledger.entries()) ?? []
            let bases = Dictionary(entries.compactMap { entry in entry.base.map { (entry.key, $0) } }, uniquingKeysWith: { first, _ in first })
            let parents = Set(records.compactMap { record -> String? in
                if case .reference(let parent)? = record.fields["parent"] { return parent }
                return nil
            })
            // Only items iCloud holds exactly as the device does, with nothing under them, and that no change still
            // to go points at: a row lost with a change not yet sent loses that change (and the store takes a
            // reference to a lost row off the rows that held it), which is the store's loss and not the engine's to
            // answer for.
            var pointedAtByUnsent = Set<SyncKey>()
            for record in records {
                if let base = bases[record.key], !base.isDeleted, RecordMerge.same(base, record) { continue }
                guard let type = SyncSchema.type(record.key.type) else { continue }
                for field in type.fields {
                    switch (field.kind, record.fields[field.key]) {
                    case (.reference(let target), .reference(let name)?):
                        pointedAtByUnsent.insert(SyncKey(type: target, name: name))
                    case (.references(let target), .referenceList(let names)?):
                        pointedAtByUnsent.formUnion(names.map { SyncKey(type: target, name: $0) })
                    default: break
                    }
                }
            }
            let safe = records.filter { record in
                guard let base = bases[record.key], !base.isDeleted, RecordMerge.same(base, record) else { return false }
                if record.key.type == SyncSchema.profile.name || pointedAtByUnsent.contains(record.key) { return false }
                return !(record.key.type == SyncSchema.taskItem.name && parents.contains(record.key.name))
            }
            var pool = safe.map(\.key)
            var keys: [SyncKey] = []
            for _ in 0..<min(1 + random.below(3), pool.count) {
                guard let pick = random.pick(pool) else { break }
                keys.append(pick)
                pool.removeAll { $0 == pick }
            }
            return keys.isEmpty ? nil : .fault(name, .loseRows(keys))
        case .ledgerLost: return .relaunch(name, keepLedger: false, keepTransportState: false)
        case .zoneDeleted: return .cloud(.deleteZone(.deleted))
        case .zoneReset: return .cloud(.deleteZone(.encryptedDataReset))
        case .accountSwitch, .signOut:
            if let previous = away[name] {
                away[name] = nil
                _ = previous
                return .fault(name, .account(config.account))
            }
            let other: String? = kind == .signOut ? nil : config.account + "-other"
            away[name] = .some(other)
            return .fault(name, .account(other))
        case .quotaFull:
            quotaFull.toggle()
            return .cloud(.quotaFull(quotaFull))
        case .sendByItself: return .sendByItself(name)
        case .zonePurged: return .cloud(.deleteZone(.purged))
        case .refusal:
            let alive = (try? await slots[name]?.store.records()) ?? []
            guard let target = random.pick(alive) else { return nil }
            let failure: SendFailure = random.chance(50) ? .tooLarge : .rejected(code: 15, message: "refused by the simulation")
            return .cloud(.refuseNextSave(target.key, failure))
        }
    }

    /// A person's action on the device, on what the device holds now: references only to items that are there.
    private func drawAction(_ name: String) async -> SimStep? {
        guard let device = slots[name] else { return nil }
        let records = await held(device)
        let tasks = records.filter { $0.key.type == SyncSchema.taskItem.name }
        let tops = tasks.filter { $0.fields["parent"] == nil }
        let parents = Set(tasks.compactMap { record -> String? in
            if case .reference(let name)? = record.fields["parent"] { return name } else { return nil }
        })
        let groups = records.filter { $0.key.type == SyncSchema.project.name }
        let labels = records.filter { $0.key.type == SyncSchema.taskLabel.name }
        let boards = records.filter { $0.key.type == SyncSchema.switchboard.name }
        let named = records.filter { ["Project", "TaskLabel", "SavedFilter", "Switchboard"].contains($0.key.type) }
        let deletable = records.filter { $0.key.type != SyncSchema.profile.name }
        let here = Set(records.map(\.key))
        let undoable = (undo[name] ?? []).filter { !here.contains($0.key) }
        let hint: SimHint = {
            let roll = random.below(100)
            if roll < config.silentPercent { return .none }
            if roll < config.silentPercent + config.everythingPercent { return .everything }
            return .keys
        }()
        counter += 1
        let n = counter
        let now = SyncValue.millis(clock.millis)

        let choices: [(Int, Bool)] = [
            (5, true), (4, true), (18, true), (8, !tops.isEmpty), (2, true), (2, true), (2, true),
            (18, !tasks.isEmpty), (6, !tasks.isEmpty), (6, !tasks.isEmpty && !groups.isEmpty),
            (6, !tasks.isEmpty && !labels.isEmpty), (4, tasks.count > 1), (8, !deletable.isEmpty),
            (4, !undoable.isEmpty), (5, !named.isEmpty),
        ]
        let total = choices.filter(\.1).reduce(0) { $0 + $1.0 }
        var roll = random.below(total)
        var choice = 2
        for (index, entry) in choices.enumerated() where entry.1 {
            if roll < entry.0 { choice = index; break }
            roll -= entry.0
        }

        switch choice {
        case 0:
            return .act(name, .put(SyncRecord(type: "Project", name: newName(), fields: [
                "name": .string("Group \(n)"), "colorHex": .string("#33AA\(String(format: "%02X", n % 256))"),
                "sortOrder": .int(Int64(n)), "createdAt": now, "updatedAt": now])), hint: hint)
        case 1:
            return .act(name, .put(SyncRecord(type: "TaskLabel", name: newName(), fields: [
                "name": .string("label\(n)"), "createdAt": now, "updatedAt": now])), hint: hint)
        case 2, 3:
            var fields: [String: SyncValue] = ["title": .string("task \(n)"), "priority": .int(Int64(1 + random.below(4))),
                                               "sortOrder": .int(Int64(n)), "createdAt": now, "updatedAt": now]
            if choice == 3, let parent = random.pick(tops) {
                fields["parent"] = .reference(parent.key.name)
            } else if random.chance(50), let group = random.pick(groups) {
                fields["project"] = .reference(group.key.name)
            }
            if random.chance(30), let label = random.pick(labels) { fields["labels"] = .references([label.key.name]) }
            if random.chance(30) { fields["dueDate"] = .millis(clock.millis + Int64(random.below(10)) * 86_400_000) }
            if random.chance(10), let board = random.pick(boards) { fields["switchboard"] = .reference(board.key.name) }
            return .act(name, .put(SyncRecord(type: "TaskItem", name: newName(), fields: fields)), hint: hint)
        case 4:
            return .act(name, .put(SyncRecord(type: "Switchboard", name: newName(), fields: [
                "name": .string("board \(n)"), "cadence": .string(random.chance(50) ? "daily" : "weekly"),
                "createdAt": now, "updatedAt": now])), hint: hint)
        case 5:
            return .act(name, .put(SyncRecord(type: "SavedFilter", name: newName(), fields: [
                "name": .string("filter \(n)"), "query": .string("p\(1 + random.below(4))"),
                "createdAt": now, "updatedAt": now])), hint: hint)
        case 6:
            let key = SyncKey(type: "Profile", name: "profile")
            if records.contains(where: { $0.key == key }) {
                return .act(name, .edit(key, ["displayName": .string("person \(n)"), "nameUpdatedAt": now]), hint: hint)
            }
            return .act(name, .put(SyncRecord(key: key, fields: ["displayName": .string("person \(n)"), "nameUpdatedAt": now,
                                                                  "createdAt": now, "updatedAt": now])), hint: hint)
        case 7:
            guard let task = random.pick(tasks) else { return nil }
            var changes: [String: SyncValue?] = [:]
            let fields = ["title", "notes", "priority", "dueDate", "deadline", "locationName", "recurrence", "reminderOffsetMinutes"]
            for _ in 0..<(1 + random.below(3)) {
                switch fields[random.below(fields.count)] {
                case "title": changes["title"] = .some(.string("task \(n) edited"))
                case "notes": changes["notes"] = .some(random.chance(20) ? nil : .string("notes \(n)"))
                case "priority": changes["priority"] = .some(.int(Int64(1 + random.below(4))))
                case "dueDate": changes["dueDate"] = .some(random.chance(25) ? nil : .millis(clock.millis + Int64(random.below(30)) * 86_400_000))
                case "deadline": changes["deadline"] = .some(.millis(clock.millis + 7 * 86_400_000))
                case "locationName": changes["locationName"] = .some(.string("place \(n)"))
                case "recurrence": changes["recurrence"] = .some(random.chance(30) ? nil : .string("every day"))
                default: changes["reminderOffsetMinutes"] = .some(.int(Int64(random.below(4) * 15)))
                }
            }
            return .act(name, .edit(task.key, changes), hint: hint)
        case 8:
            guard let task = random.pick(tasks) else { return nil }
            let done = task.fields["isCompleted"] == .bool(true)
            return .act(name, .edit(task.key, ["isCompleted": .bool(!done), "completedAt": done ? nil : now]), hint: hint)
        case 9:
            guard let task = random.pick(tops), let group = random.pick(groups) else { return nil }
            return .act(name, .edit(task.key, ["project": .reference(group.key.name)]), hint: hint)
        case 10:
            guard let task = random.pick(tasks), let label = random.pick(labels) else { return nil }
            var names: Set<String> = []
            if case .referenceList(let list)? = task.fields["labels"] { names = Set(list) }
            if names.contains(label.key.name) { names.remove(label.key.name) } else { names.insert(label.key.name) }
            return .act(name, .edit(task.key, ["labels": names.isEmpty ? nil : SyncValue.references(names)]), hint: hint)
        case 11:
            // A sub-task moved under another top task, or a childless top task made a sub-task: never a cycle.
            let movable = tasks.filter { !parents.contains($0.key.name) }
            guard let task = random.pick(movable) else { return nil }
            let targets = tops.filter { $0.key != task.key }
            guard let parent = random.pick(targets) else { return nil }
            return .act(name, .edit(task.key, ["parent": .reference(parent.key.name), "project": nil]), hint: hint)
        case 12:
            guard let item = random.pick(deletable) else { return nil }
            undo[name, default: []].append(item)
            return .act(name, .delete(item.key), hint: hint)
        case 13:
            guard let item = random.pick(undoable) else { return nil }
            undo[name]?.removeAll { $0.key == item.key }
            return .act(name, .put(item), hint: hint)
        default:
            guard let item = random.pick(named) else { return nil }
            return .act(name, .edit(item.key, ["name": .string("\(item.key.type.lowercased()) \(n) renamed")]), hint: hint)
        }
    }

    /// A UUID-shaped name drawn from the run's seed.
    private func newName() -> String {
        let a = random.next(), b = random.next()
        return String(format: "%08llX-%04llX-%04llX-%04llX-%012llX",
                      a >> 32, (a >> 16) & 0xFFFF, a & 0xFFFF, b >> 48, b & 0xFFFF_FFFF_FFFF)
    }
}

/// What the transports' observers find while a run plays (I4), kept where any task can add to it.
final class Observed: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [String: DeviceSnapshot] = [:]
    private var found: [SyncFinding] = []
    private var current = 0
    private var forgotten: [String] = []
    /// Devices that lost their memory and have not finished a whole fetch since.
    private var amnesic: Set<String> = []
    /// Devices that have received records (or finished a fetch) at least once.
    private var fetchedOnce: Set<String> = []

    func hasFetched(_ device: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return fetchedOnce.contains(device)
    }

    func forgot(_ device: String) {
        lock.lock()
        forgotten.append(device)
        amnesic.insert(device)
        lock.unlock()
    }

    /// Records reached the device (a `fetched` event): it has a memory of them to lose from now on.
    func received(_ device: String) {
        lock.lock()
        fetchedOnce.insert(device)
        lock.unlock()
    }

    func fetched(_ device: String) {
        lock.lock()
        fetchedOnce.insert(device)
        if amnesic.remove(device) != nil { forgotten.append(device) }
        lock.unlock()
    }

    func takeForgotten() -> [String] {
        lock.lock()
        defer { lock.unlock(); forgotten = [] }
        return forgotten
    }

    var step: Int {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }

    func keep(_ device: String, _ snapshot: DeviceSnapshot) {
        lock.lock()
        snapshots[device] = snapshot
        lock.unlock()
    }

    func take(_ device: String) -> DeviceSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshots.removeValue(forKey: device)
    }

    func add(_ findings: [SyncFinding]) {
        lock.lock()
        found += findings
        lock.unlock()
    }

    var findings: [SyncFinding] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }
}
#endif
