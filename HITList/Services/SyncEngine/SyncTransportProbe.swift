#if DEBUG
import Foundation
import CloudKit
import OSLog
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif

/// Debug only (brief 142, item 3): proves `CloudKitTransport` against CloudKit **Development** with two transports in
/// one process standing for two devices (two engines on one database: allowed in Development only), each with its
/// own state in memory, in a zone of the probe's own (`HITListProbe-<random>`) that it deletes at the end, also when
/// a step fails. The engine's real zone is never touched.
///
/// Run (a signed Debug Mac build; never a Release build, never the real store):
///
///     HITLIST_STORE_SUFFIX=s142 …/Debug/HITList.app/Contents/MacOS/HITList -syncTransportProbe YES -ApplePersistenceIgnoreState YES
///
/// Each step is one line on stdout and in the log (`category: sync`): `PROBE ok <step>` or `PROBE FAIL <step>: <why>`,
/// findings as `PROBE note <what>`, then `PROBE done N ok, M failed`, and the app quits. It refuses to run on the
/// real store (`ModelContainerFactory.isMainStoreOpen`) or outside Development.
enum SyncTransportProbe {
    static var isAsked: Bool { ProcessInfo.processInfo.arguments.contains("-syncTransportProbe") }

    private static let logger = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    static func emit(_ line: String) {
        print(line)
        fflush(stdout)
        logger.notice("\(line, privacy: .public)")
    }

    /// Called once at launch (`HITListApp.init`): runs the probe when asked, then quits.
    @MainActor
    static func runIfAsked() {
        guard isAsked else { return }
        guard !ModelContainerFactory.isMainStoreOpen else {
            emit("PROBE FAIL refused: the real store is open (\(ModelContainerFactory.storeName)); run with HITLIST_STORE_SUFFIX=s142")
            return
        }
        guard SyncEnvironment.current.cloudKit == .development else {
            emit("PROBE FAIL refused: this build's CloudKit environment is \(SyncEnvironment.current.cloudKit.rawValue), not Development")
            return
        }
        Task.detached(priority: .userInitiated) {
            let result = await ProbeRun(containerID: HITListSchema.cloudKitContainerID).run()
            emit("PROBE done \(result.ok) ok, \(result.failed) failed")
            await MainActor.run { quit() }
        }
    }

    @MainActor
    private static func quit() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #endif
    }
}

// MARK: - A device: the brain's side, recorded

/// Stands in for the brain on one "device": hands out the records it was given to send, and keeps what every event
/// brought, as a brain would (so a later step can send on the token iCloud gave).
private actor ProbeDevice: SyncTransportDelegate {
    let name: String
    private var outgoing: [SyncKey: OutgoingRecord] = [:]
    private(set) var accounts: [AccountChange] = []
    private(set) var saved: [SyncKey: CloudRecord] = [:]
    private(set) var failed: [SyncKey: SendFailure] = [:]
    private(set) var removed: Set<SyncKey> = []
    private(set) var fetched: [SyncKey: CloudRecord] = [:]
    private(set) var fetchedRemoved: Set<SyncKey> = []
    private(set) var zoneLosses: [ZoneLoss] = []
    private(set) var sentBatches: [Int] = []
    private(set) var didFetchErrors: [String?] = []
    private(set) var didSendErrors: [String?] = []
    private(set) var eventNames: [String] = []
    /// iCloud's token for every record, as a ledger keeps it: never cleared between steps.
    private(set) var tokens: [SyncKey: Data] = [:]
    /// How many times the transport asked for each record.
    private(set) var asked: [SyncKey: Int] = [:]
    /// Records to change and add again while their `sent` is handled, as the brain does for an edit made while the
    /// save was on its way (139's finding).
    private var readdOnSent: [SyncKey: OutgoingRecord] = [:]
    private weak var transport: CloudKitTransport?

    init(_ name: String) { self.name = name }

    func attach(_ transport: CloudKitTransport) { self.transport = transport }

    func token(_ key: SyncKey) -> Data? { tokens[key] }

    func readd(_ record: OutgoingRecord) { readdOnSent[record.record.key] = record }

    func handle(_ event: TransportEvent) async {
        switch event {
        case .account(let change):
            accounts.append(change)
            eventNames.append("account")
        case .willFetch:
            eventNames.append("willFetch")
        case .fetched(let changed, let gone):
            for record in changed {
                fetched[record.key] = record
                tokens[record.key] = record.system
                keyWaiters.removeValue(forKey: record.key)?.resume(returning: true)
            }
            fetchedRemoved.formUnion(gone)
            eventNames.append("fetched(\(changed.count),\(gone.count))")
        case .zoneLost(let loss):
            zoneLosses.append(loss)
            eventNames.append("zoneLost")
        case .didFetch(let error):
            didFetchErrors.append(error)
            eventNames.append("didFetch")
        case .willSend:
            eventNames.append("willSend")
        case .sent(let done, let gone, let refused):
            for record in done {
                saved[record.key] = record
                tokens[record.key] = record.system
            }
            removed.formUnion(gone)
            for key in gone { tokens[key] = nil }
            for (key, failure) in refused {
                failed[key] = failure
                if case .conflict(let server) = failure { tokens[key] = server.system }
            }
            for record in done {
                guard let again = readdOnSent.removeValue(forKey: record.key) else { continue }
                outgoing[record.key] = OutgoingRecord(record: again.record, system: record.system)
                await transport?.add([.save(record.key)])
            }
            sentBatches.append(done.count + gone.count + refused.count)
            eventNames.append("sent(\(done.count),\(gone.count),\(refused.count))")
        case .didSend(let error):
            didSendErrors.append(error)
            eventNames.append("didSend")
        }
    }

    func recordToSend(_ key: SyncKey) async -> OutgoingRecord? {
        asked[key, default: 0] += 1
        return outgoing[key]
    }

    func unstage(_ key: SyncKey) { outgoing[key] = nil }

    private var keyWaiters: [SyncKey: CheckedContinuation<Bool, Never>] = [:]

    /// Waits until a fetch brings `key`, at most `seconds` (one deadline for one awaited thing).
    func waitForFetch(_ key: SyncKey, seconds: Double) async -> Bool {
        if fetched[key] != nil { return true }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            keyWaiters[key] = continuation
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.giveUp(key)
            }
        }
    }

    private func giveUp(_ key: SyncKey) { keyWaiters.removeValue(forKey: key)?.resume(returning: false) }

    func stage(_ records: [OutgoingRecord]) {
        for record in records { outgoing[record.record.key] = record }
    }

    /// Forgets what the events of earlier steps brought (not the records staged to send).
    func clear() {
        saved = [:]
        failed = [:]
        removed = []
        fetched = [:]
        fetchedRemoved = []
        sentBatches = []
        didFetchErrors = []
        didSendErrors = []
        eventNames = []
        asked = [:]
    }
}

/// A transport's state, in memory: a device's ledger, for the probe.
private actor ProbeState: SyncTransportState {
    private(set) var data: Data?
    private(set) var writes = 0
    func loadTransportState() async -> Data? { data }
    func saveTransportState(_ state: Data?) async {
        data = state
        writes += 1
    }
}

/// A bare `CKSyncEngine`'s delegate (`rawEngine`): records what the engine does by itself.
private final class RawEngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var _stateUpdates = 0
    private var _events: [String] = []
    private var _pendingAtSent: [[CKSyncEngine.PendingRecordZoneChange]] = []
    private var _saved: [CKRecord.ID] = []
    private var _batchCalls = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func set(_ records: [CKRecord.ID: CKRecord]) { locked { self.records = records } }
    var stateUpdates: Int { locked { _stateUpdates } }
    var events: [String] { locked { _events } }
    var pendingAtSent: [[CKSyncEngine.PendingRecordZoneChange]] { locked { _pendingAtSent } }
    var saved: [CKRecord.ID] { locked { _saved } }
    var batchCalls: Int { locked { _batchCalls } }
    private var _failedCodes: [Int] = []
    var failedCodes: [Int] { locked { _failedCodes } }
    /// Answers one batch request again (the next send).
    func rearm() { locked { _batchCalls = 0 } }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let pending = syncEngine.state.pendingRecordZoneChanges
        locked {
            switch event {
            case .stateUpdate: _stateUpdates += 1; _events.append("stateUpdate")
            case .accountChange: _events.append("account")
            case .sentRecordZoneChanges(let sent):
                _pendingAtSent.append(pending)
                _saved += sent.savedRecords.map(\.recordID)
                _failedCodes += sent.failedRecordSaves.map { $0.error.code.rawValue }
                _events.append("sent(\(sent.savedRecords.count),\(sent.failedRecordSaves.count))")
            case .willSendChanges: _events.append("willSend")
            case .didSendChanges: _events.append("didSend")
            default: _events.append("other")
            }
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // Asked once only: if the engine kept a change whose record was nil, asking again would loop.
        let first = locked { () -> Bool in
            _batchCalls += 1
            return _batchCalls == 1
        }
        guard first else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let records = locked { self.records }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { records[$0] }
    }
}

/// Counts the mirror's successful imports while it lives.
private final class ImportCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = 0
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.seen += 1
            self.lock.unlock()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}

/// Waits for the mirror's next successful import (`CloudSyncMonitor` posts `.cloudKitImportSucceeded`).
private final class ImportWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var observer: NSObjectProtocol?

    static func next(within seconds: Double) async -> Bool {
        let watch = ImportWatch()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            watch.lock.lock()
            watch.continuation = continuation
            watch.observer = NotificationCenter.default.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: nil) { _ in
                watch.finish(true)
            }
            watch.lock.unlock()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                watch.finish(false)
            }
        }
    }

    private func finish(_ value: Bool) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        let observer = self.observer
        self.observer = nil
        lock.unlock()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        waiting?.resume(returning: value)
    }
}

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ why: String) { description = why }
}

// MARK: - The run

private final class ProbeRun: @unchecked Sendable {
    let containerID: String
    let zoneName = "HITListProbe-" + String(UUID().uuidString.prefix(8))
    var ok = 0
    var failed = 0

    init(containerID: String) { self.containerID = containerID }

    private var database: CKDatabase { CKContainer(identifier: containerID).privateCloudDatabase }
    private var zoneID: CKRecordZone.ID { CloudRecordCodec.zoneID(zoneName) }

    private func step(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            ok += 1
            SyncTransportProbe.emit("PROBE ok \(name)")
        } catch {
            failed += 1
            SyncTransportProbe.emit("PROBE FAIL \(name): \(error)")
        }
    }

    private func note(_ text: String) { SyncTransportProbe.emit("PROBE note \(text)") }

    private func transport(_ device: String, state: ProbeState, automatic: Bool = false) -> CloudKitTransport {
        CloudKitTransport(containerID: containerID, zoneName: zoneName, state: state, automaticallySync: automatic,
                          log: SyncTransportLog { line in SyncTransportProbe.emit("  [\(device)] \(line)") })
    }

    private func expect(_ condition: Bool, _ why: @autoclosure () -> String) throws {
        if !condition { throw ProbeFailure(why()) }
    }

    func run() async -> (ok: Int, failed: Int) {
        SyncTransportProbe.emit("PROBE start: container \(containerID), Development, zone \(zoneName)")
        // A step that hangs (a CloudKit call that never answers) must not leave the zone behind or the app running.
        let zone = zoneName, container = containerID
        let watchdog = Task.detached {
            try await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            SyncTransportProbe.emit("PROBE FAIL watchdog: still running after 10 minutes; deleting the zone and quitting")
            _ = try? await CKContainer(identifier: container).privateCloudDatabase
                .modifyRecordZones(saving: [], deleting: [CloudRecordCodec.zoneID(zone)])
            SyncTransportProbe.emit("PROBE done (watchdog)")
            exit(2)
        }
        defer { watchdog.cancel() }

        var account: CKAccountStatus = .couldNotDetermine
        await step("account") {
            account = try await CKContainer(identifier: containerID).accountStatus()
            try expect(account == .available, "iCloud account status \(account.rawValue), not available")
        }
        guard account == .available else { return (ok, failed) }

        await removeLeftoverZones()
        await steps()
        await cleanUp()
        return (ok, failed)
    }

    // MARK: Steps

    private let stateA = ProbeState()
    private let stateB = ProbeState()
    private let deviceA = ProbeDevice("A")
    private let deviceB = ProbeDevice("B")
    private var a: CloudKitTransport!
    private var b: CloudKitTransport!
    private var a2: CloudKitTransport?
    private var originals: [SyncRecord] = []

    private func key(_ type: String) -> SyncKey { originals.first { $0.key.type == type }!.key }

    /// Whether SwiftData's mirror runs in this launch (no `-disableCloudKit YES`). With it on, only the steps that
    /// are about the mirror run (the save of every type, then the mirror's check); every other step runs in a launch
    /// with the mirror off, so nothing but the transports writes the zone (the supervisor's decision, 2026-11-15).
    private var mirrorIsOn: Bool { !AppGroup.defaults.bool(forKey: "disableCloudKit") && !ModelContainerFactory.isRunningInMemory }

    private var countsBefore: [String: Int]?

    private func steps() async {
        if mirrorIsOn {
            // The launch's own import first, so that what the store holds before A's save is what it held anyway.
            let launchImport = await ImportWatch.next(within: 30)
            countsBefore = await Self.storeCounts()
            note("mirror on: \(launchImport ? "the launch's import came" : "no launch import within 30 s"); the side store holds \(Self.describe(countsBefore))")
        }
        a = transport("A", state: stateA)
        b = transport("B", state: stateB)
        await deviceA.attach(a)
        await deviceB.attach(b)
        await a.start(delegate: deviceA)
        await b.start(delegate: deviceB)
        originals = Self.everyType()

        // 1. One record of every type, every field: also how Development learns the record types and fields.
        await step("every type saved by A (\(originals.count) records, every field)") {
            await deviceA.stage(originals.map { OutgoingRecord(record: $0, system: nil) })
            await a.add(originals.map { .save($0.key) })
            try await a.send()
            let saved = await deviceA.saved
            let refused = await deviceA.failed
            try expect(refused.isEmpty, "refused: \(refused)")
            for record in originals {
                guard let back = saved[record.key] else { throw ProbeFailure("\(record.key) not saved") }
                try expect(back.record == record, "\(record.key) saved as \(Self.difference(back.record, record))")
            }
            let pending = await a.pending()
            try expect(pending.isEmpty, "still pending: \(pending)")
        }
        let accountsA = await deviceA.accounts
        note("A's account events after its first send: \(accountsA.map { String(describing: $0) })")

        if mirrorIsOn {
            await mirrorLeavesTheZoneAlone()
            note("mirror on: the other steps run in a launch with -disableCloudKit YES")
            return
        }
        note("the mirror check runs in a launch with the mirror on")

        // 2. B fetches them, equal field for field.
        await step("B fetches every type, equal") {
            try await b.fetch()
            let fetched = await deviceB.fetched
            for record in originals {
                guard let back = fetched[record.key] else { throw ProbeFailure("\(record.key) not fetched") }
                try expect(back.record == record, "\(record.key) fetched as \(Self.difference(back.record, record))")
            }
            try expect(Set(fetched.keys) == Set(originals.map(\.key)), "fetched other records: \(Set(fetched.keys).subtracting(originals.map(\.key)))")
            let errors = await deviceB.didFetchErrors
            try expect(errors == [nil], "didFetch errors \(errors)")
        }
        let accountsB = await deviceB.accounts
        let eventsB = await deviceB.eventNames
        note("B's first fetch: events \(eventsB), accounts \(accountsB.map { String(describing: $0) })")

        // The echo: A fetches right after its own save.
        await step("A fetches after its own save (the echo)") {
            try await a.fetch()
            let echoed = await deviceA.fetched
            let mine = Set(originals.map(\.key)).intersection(echoed.keys)
            note("echo: A's fetch after its own save brought back \(mine.count) of its \(originals.count) records")
            for record in originals {
                if let back = echoed[record.key] {
                    try expect(back.record == record, "the echo of \(record.key) differs: \(Self.difference(back.record, record))")
                }
            }
        }

        await conflict()
        await marker()
        await unknownItem()
        await newerBuild()
        await batches()
        await readdWhileSent()
        await nilRecord()
        await restart()
        await push()
        await rawEngine()
    }

    /// The brain adds a save again while it handles the `sent` of that record (an edit made while the save was on
    /// its way): the change must go again, in this send or the next, not be wiped by the engine (139's finding).
    private func readdWhileSent() async {
        await step("a save added again while its sent is handled is not lost") {
            let key = key("Switchboard")
            guard let token = await deviceA.token(key) else { throw ProbeFailure("A has no token for the switchboard") }
            var first = originals.first { $0.key == key }!
            first["name"] = .string("Edited once")
            first["updatedAt"] = .date(Date())
            var second = first
            second["name"] = .string("Edited again while on its way")
            await deviceA.clear()
            await deviceA.stage([OutgoingRecord(record: first, system: token)])
            await deviceA.readd(OutgoingRecord(record: second, system: nil))
            await a.add([.save(key)])
            try await a.send()
            let asked = await deviceA.asked[key] ?? 0
            let pending = await a.pending()
            let saved = await deviceA.saved[key]
            note("re-added during its sent: asked \(asked) time(s) in the send, pending after: \(pending.contains(.save(key)))")
            if asked >= 2 {
                try expect(saved?.record["name"] == .string("Edited again while on its way"), "the second edit was asked for but not saved")
            } else {
                try expect(pending.contains(.save(key)), "the re-added save was wiped: neither sent again nor pending")
                try await a.send()
                let savedAgain = await deviceA.saved[key]
                try expect(savedAgain?.record["name"] == .string("Edited again while on its way"), "the second edit did not go")
            }
        }
    }

    /// T3: a pending save whose record the brain no longer has is dropped, and the send goes on with the rest.
    private func nilRecord() async {
        await step("a pending save with nothing to send is dropped (T3)") {
            let gone = SyncKey(type: "TaskItem", name: UUID().uuidString)
            let kept = SyncRecord(type: "TaskLabel", name: UUID().uuidString, fields: [
                "name": .string("After a nil"), "colorHex": .string("#654321"), "createdAt": .date(Date()), "updatedAt": .date(Date()),
            ])
            await deviceA.clear()
            await deviceA.unstage(gone)
            await deviceA.stage([OutgoingRecord(record: kept, system: nil)])
            await a.add([.save(gone), .save(kept.key)])
            try await a.send()
            let pending = await a.pending()
            let saved = await deviceA.saved[kept.key]
            let refused = await deviceA.failed
            try expect(!pending.contains(.save(gone)), "the save with nothing to send is still pending")
            try expect(saved != nil, "the next change did not go")
            try expect(refused[gone] == nil, "the dropped save was told as refused: \(refused[gone].map { String(describing: $0) } ?? "")")
        }
    }

    /// An automatic transport (as the app will run it) hears another device's change by itself: a push, then the
    /// engine's own fetch. Told as a note, not a step: whether a push reaches this Debug process at all is up to
    /// Apple's push service in Development, which the probe cannot command (the mirror's own import shows whether
    /// one came).
    private func push() async {
        do {
            let deviceC = ProbeDevice("C")
            let c = transport("C", state: ProbeState(), automatic: true)
            await c.start(delegate: deviceC)
            try await c.fetch()
            await deviceC.clear()
            let pushed = SyncRecord(type: "TaskLabel", name: UUID().uuidString, fields: [
                "name": .string("Pushed"), "colorHex": .string("#0A0B0C"), "createdAt": .date(Date()), "updatedAt": .date(Date()),
            ])
            await deviceB.clear()
            await deviceB.stage([OutgoingRecord(record: pushed, system: nil)])
            await b.add([.save(pushed.key)])
            try await b.send()
            let sentAt = Date()
            let heard = await deviceC.waitForFetch(pushed.key, seconds: 60)
            let after = Date().timeIntervalSince(sentAt)
            let events = await deviceC.eventNames
            await c.stop()
            let how = heard ? "fetched B's change by itself after \(String(format: "%.1f", after)) s" : "heard nothing in 60 s"
            note("push: an automatic transport \(how); its events \(events)")
        } catch {
            note("push: not tried: \(error)")
        }
    }

    /// The finding of 2026-11-15 (`142-sync-cloudkit/FINDING-mirror-imports-engine-zone.md`): with the mirror on, its
    /// import (pushed by the engine's own saves) takes the engine's records for its own. After A's first save this
    /// waits for the mirror's next import, then reads every record straight from iCloud: none may carry a `CD_` key
    /// or be gone. Run only when the mirror is on (no `-disableCloudKit YES`); it fails until the engine's records are
    /// out of the mirror's reach.
    private func mirrorLeavesTheZoneAlone() async {
        await step("the mirror leaves the engine's zone alone") {
            let imports = ImportCounter()
            let imported = await ImportWatch.next(within: 60)
            let countsAfter = await Self.storeCounts()
            note("mirror: \(imported ? "an import ran after A's save" : "no import within 60 s of A's save") (imports seen: \(imports.count)); the side store holds \(Self.describe(countsAfter)) (before: \(Self.describe(countsBefore)))")
            let ids = originals.map { CloudRecordCodec.recordID(for: $0.key, in: zoneID) }
            let results = try await database.records(for: ids)
            var problems: [String] = []
            for (record, id) in zip(originals, ids) {
                switch results[id] {
                case .success(let server)?:
                    let foreign = server.allKeys().filter { $0.hasPrefix("CD_") }.sorted()
                    if !foreign.isEmpty { problems.append("\(record.key) carries \(foreign.joined(separator: ","))") }
                    if server.recordType != CloudRecordCodec.recordType(for: record.key.type) {
                        problems.append("\(record.key) is now of type \(server.recordType)")
                    }
                case .failure(let error)?:
                    problems.append("\(record.key) gone: \(CloudKitTransportRules.words(for: error))")
                case nil:
                    problems.append("\(record.key) not answered")
                }
            }
            if let before = countsBefore, let after = countsAfter, before != after {
                problems.append("the side store changed: \(Self.describe(before)) → \(Self.describe(after))")
            }
            try expect(imported, "no import of the mirror's came to check against")
            try expect(problems.isEmpty, problems.joined(separator: "; "))
        }
    }

    /// How many of each of the six models the side store holds.
    @MainActor
    static func storeCounts() -> [String: Int]? {
        guard let container = IntentStore.container else { return nil }
        let context = ModelContext(container)
        func count<T: PersistentModel>(_ type: T.Type) -> Int { (try? context.fetchCount(FetchDescriptor<T>())) ?? -1 }
        return [
            "TaskItem": count(TaskItem.self), "Project": count(Project.self), "TaskLabel": count(TaskLabel.self),
            "SavedFilter": count(SavedFilter.self), "Switchboard": count(Switchboard.self), "Profile": count(Profile.self),
        ]
    }

    static func describe(_ counts: [String: Int]?) -> String {
        guard let counts else { return "(unknown)" }
        return counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
    }

    /// Before anything else: zones of earlier probe runs that were cut short (a quit mid-run), so none stays behind.
    private func removeLeftoverZones() async {
        await step("leftover probe zones removed") {
            let zones = try await database.allRecordZones()
            let leftovers = zones.map(\.zoneID).filter { $0.zoneName.hasPrefix("HITListProbe-") && $0.zoneName != zoneName }
            guard !leftovers.isEmpty else { return note("no leftover probe zone") }
            let result = try await database.modifyRecordZones(saving: [], deleting: leftovers)
            let failed = result.deleteResults.filter { if case .failure = $0.value { return true } else { return false } }
            note("removed \(leftovers.count - failed.count) leftover zone(s): \(leftovers.map(\.zoneName))")
            try expect(failed.isEmpty, "not removed: \(failed.keys.map(\.zoneName))")
        }
    }

    /// What the SDK leaves unsaid, asked of a bare `CKSyncEngine` (no transport in between): is a pending save whose
    /// provider gave nil kept on the list; is a saved change off the list before its `sent` event; does a change to
    /// the list bring a `stateUpdate`; and what the batch initialiser returns when every record is nil.
    private func rawEngine() async {
        await step("the bare engine answers the SDK's open questions") {
            let empty = await CKSyncEngine.RecordZoneChangeBatch(
                pendingChanges: [.saveRecord(CKRecord.ID(recordName: "TaskItem.none", zoneID: zoneID))]) { _ in nil }
            note("raw: the batch initialiser with every record nil returns \(empty == nil ? "nil" : "a batch of \(empty!.recordsToSave.count) saves")")

            let raw = RawEngineDelegate()
            var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: nil, delegate: raw)
            configuration.automaticallySync = false
            let engine = CKSyncEngine(configuration)
            let missing = CKRecord.ID(recordName: "TaskItem.\(UUID().uuidString)", zoneID: zoneID)
            let presentID = CKRecord.ID(recordName: "TaskLabel.\(UUID().uuidString)", zoneID: zoneID)
            let present = CKRecord(recordType: CloudRecordCodec.recordType(for: "TaskLabel"), recordID: presentID)
            present["name"] = "Raw" as NSString
            raw.set([presentID: present])
            let updatesBefore = raw.stateUpdates
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(missing), .saveRecord(presentID)])
            try await engine.sendChanges()
            let after = engine.state.pendingRecordZoneChanges
            note("raw: stateUpdates during add and send: \(raw.stateUpdates - updatesBefore); events \(raw.events)")
            note("raw: a pending save whose provider gave nil is \(after.contains(.saveRecord(missing)) ? "KEPT on the list" : "taken off the list") by the engine")
            if let seen = raw.pendingAtSent.first {
                note("raw: inside its sentRecordZoneChanges event the saved change is \(seen.contains(.saveRecord(presentID)) ? "STILL on the list" : "already off the list")")
            } else {
                note("raw: no sentRecordZoneChanges event came")
            }
            note("raw: batches asked for: \(raw.batchCalls)")

            // T4/T6 ordering: is a refused (serverRecordChanged) change still on the list inside its event, and after?
            engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
            let stale = CKRecord(recordType: CloudRecordCodec.recordType(for: "TaskLabel"), recordID: presentID)
            stale["name"] = "Raw, no token" as NSString
            raw.set([presentID: stale])
            raw.rearm()
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(presentID)])
            try? await engine.sendChanges()
            let conflictSeen = raw.pendingAtSent.dropFirst().first
            let conflictCodes = raw.failedCodes
            let conflictAfter = engine.state.pendingRecordZoneChanges.contains(.saveRecord(presentID))
            if let conflictSeen {
                note("raw: a save refused with \(conflictCodes) is \(conflictSeen.contains(.saveRecord(presentID)) ? "STILL on the list" : "already off the list") inside its sentRecordZoneChanges event, and \(conflictAfter ? "KEPT on the list" : "off the list") after the send")
            } else {
                note("raw: the second send brought no sentRecordZoneChanges event (codes \(conflictCodes))")
            }
            engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
            await engine.cancelOperations()
            try expect(raw.saved.contains(presentID), "the bare engine did not save the record it was given")
        }
    }

    /// 3. B changes a task, A changes the same task without fetching: A's save is refused with B's version (T6).
    private func conflict() async {
        await step("conflict: A gets B's version") {
            let taskKey = key("TaskItem")
            guard let bCopy = await deviceB.fetched[taskKey] else { throw ProbeFailure("B has no copy") }
            guard let aToken = await deviceA.saved[taskKey]?.system else { throw ProbeFailure("A has no token") }
            var bRecord = bCopy.record
            bRecord["title"] = .string("Changed on B")
            bRecord["updatedAt"] = .date(Date())
            await deviceB.clear()
            await deviceB.stage([OutgoingRecord(record: bRecord, system: bCopy.system)])
            await b.add([.save(taskKey)])
            try await b.send()
            let bAnswer = await deviceB.failed[taskKey]
            guard let bSaved = await deviceB.saved[taskKey] else {
                throw ProbeFailure("B's change not saved: \(bAnswer.map { String(describing: $0) } ?? "no answer")")
            }
            var aRecord = originals.first { $0.key == taskKey }!
            aRecord["notes"] = .string("Changed on A")
            aRecord["updatedAt"] = .date(Date())
            await deviceA.clear()
            await deviceA.stage([OutgoingRecord(record: aRecord, system: aToken)])
            await a.add([.save(taskKey)])
            try await a.send()
            let aAnswer = await deviceA.failed[taskKey]
            let aSaved = await deviceA.saved[taskKey] != nil
            guard case .conflict(let server)? = aAnswer else {
                throw ProbeFailure("A got \(aAnswer.map { String(describing: $0) } ?? "no failure") (saved: \(aSaved))")
            }
            try expect(server.record == bSaved.record, "the conflict carries \(Self.difference(server.record, bSaved.record))")
            let tag = CloudRecordCodec.unarchive(server.system)?.recordChangeTag
            try expect(tag != nil && tag == CloudRecordCodec.unarchive(bSaved.system)?.recordChangeTag, "change tag \(tag ?? "nil") is not B's")
            let pending = await a.pending()
            try expect(!pending.contains(.save(taskKey)), "the refused save is still pending (T6)")
        }
    }

    /// 4. A leaves a marker on a record; B fetches it with every other field emptied.
    private func marker() async {
        await step("marker: A deletes a project, B fetches the marker") {
            let projectKey = key("Project")
            guard let token = await deviceA.token(projectKey) else {
                throw ProbeFailure("A has no token for the project")
            }
            let marker = SyncRecord.marker(projectKey, deletedAt: Date())
            await deviceA.clear()
            await deviceA.stage([OutgoingRecord(record: marker, system: token)])
            await a.add([.save(projectKey)])
            try await a.send()
            let answer = await deviceA.failed[projectKey]
            guard let saved = await deviceA.saved[projectKey] else {
                throw ProbeFailure("not saved: \(answer.map { String(describing: $0) } ?? "no answer")")
            }
            try expect(saved.record == marker, "saved as \(Self.difference(saved.record, marker))")
            await deviceB.clear()
            try await b.fetch()
            guard let fetched = await deviceB.fetched[projectKey] else { throw ProbeFailure("B did not fetch it") }
            try expect(fetched.record == marker, "B fetched \(Self.difference(fetched.record, marker))")
            let others = await Set(deviceB.fetched.keys).subtracting([projectKey])
            note("B's fetch after the marker also brought \(others.count) other record(s): \(others.sorted())")
        }
    }

    /// 5. T8 a record removed for good; T7 a save on a token of a removed record, a delete of one never there.
    private func unknownItem() async {
        let ghost = SyncRecord(type: "TaskLabel", name: UUID().uuidString, fields: [
            "name": .string("Ghost"), "colorHex": .string("#123456"), "createdAt": .date(Date()), "updatedAt": .date(Date()),
        ])
        let never = SyncKey(type: "TaskLabel", name: UUID().uuidString)
        var token: Data?
        await step("delete for good (T8) and a delete of a record never there (T7)") {
            await deviceA.clear()
            await deviceA.stage([OutgoingRecord(record: ghost, system: nil)])
            await a.add([.save(ghost.key)])
            try await a.send()
            token = await deviceA.saved[ghost.key]?.system
            try expect(token != nil, "the ghost was not saved")
            await deviceA.clear()
            await a.add([.delete(ghost.key), .delete(never)])
            try await a.send()
            let removed = await deviceA.removed
            let refused = await deviceA.failed
            try expect(removed.contains(ghost.key), "the ghost was not removed (refused: \(refused))")
            try expect(removed.contains(never), "the delete of a record never there was not done (refused: \(refused[never].map { String(describing: $0) } ?? "nothing"))")
            let pending = await a.pending()
            try expect(pending.isEmpty, "still pending: \(pending)")
        }
        await step("a save on a removed record's token is unknownItem (T7)") {
            guard let token else { throw ProbeFailure("no token from the step before") }
            var again = ghost
            again["name"] = .string("Ghost again")
            await deviceA.clear()
            await deviceA.stage([OutgoingRecord(record: again, system: token)])
            await a.add([.save(ghost.key)])
            try await a.send()
            let answer = await deviceA.failed[ghost.key]
            let wasSaved = await deviceA.saved[ghost.key] != nil
            try expect(answer == .unknownItem, "got \(answer.map { String(describing: $0) } ?? "no failure") (saved: \(wasSaved))")
            let pending = await a.pending()
            try expect(!pending.contains(.save(ghost.key)), "still pending")
        }
        await step("B learns of the removal") {
            await deviceB.clear()
            try await b.fetch()
            let gone = await deviceB.fetchedRemoved
            let changed = await deviceB.fetched
            note("B's fetch after the ghost came and went: removed \(gone.sorted()), changed \(changed.keys.sorted())")
            try expect(changed[ghost.key] == nil, "B fetched the removed ghost as a record")
        }
    }

    /// 6. A key a newer build wrote survives a save by this transport (T4).
    private func newerBuild() async {
        await step("a newer build's key survives a save") {
            let metaKey = key(SyncSchema.metaType)
            let id = CloudRecordCodec.recordID(for: metaKey, in: zoneID)
            let server = try await database.record(for: id)
            server["probeNewerBuildField"] = "kept" as NSString
            _ = try await database.modifyRecords(saving: [server], deleting: [], savePolicy: .ifServerRecordUnchanged)
            await deviceA.clear()
            try await a.fetch()
            guard let fetched = await deviceA.fetched[metaKey] else { throw ProbeFailure("A did not fetch the meta record") }
            try expect(fetched.record["probeNewerBuildField"] == .string("kept"), "the transport did not bring the unknown key")
            var mine = SyncRecord(key: metaKey)
            mine[SyncSchema.metaFormatVersion] = fetched.record[SyncSchema.metaFormatVersion]
            mine[SyncSchema.updatedAt] = .date(Date())
            await deviceA.stage([OutgoingRecord(record: mine, system: fetched.system)])
            await a.add([.save(metaKey)])
            try await a.send()
            let metaAnswer = await deviceA.failed[metaKey]
            let metaSaved = await deviceA.saved[metaKey] != nil
            try expect(metaSaved, "not saved: \(metaAnswer.map { String(describing: $0) } ?? "no answer")")
            let after = try await database.record(for: id)
            try expect(after["probeNewerBuildField"] as? String == "kept", "the newer build's key is gone: \(String(describing: after["probeNewerBuildField"]))")
            try expect((after[SyncSchema.updatedAt] as? Date).map { SyncValue.date($0) } == mine[SyncSchema.updatedAt], "this build's change did not land")
        }
    }

    /// 7. 300 records go in two batches, one `sent` each (T10).
    private func batches() async {
        await step("300 records in two batches") {
            let many = (0..<300).map { index -> SyncRecord in
                SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: [
                    "title": .string("Probe \(index)"), "notes": .string(""), "priority": .int(4),
                    "hasDueTime": .bool(false), "isCompleted": .bool(false), "sortOrder": .int(Int64(index)),
                    "flipTarget": .int(1), "flipCount": .int(0), "overdueBecomesTask": .bool(false),
                    "createdAt": .date(Date()), "updatedAt": .date(Date()),
                ])
            }
            await deviceA.clear()
            await deviceA.stage(many.map { OutgoingRecord(record: $0, system: nil) })
            await a.add(many.map { .save($0.key) })
            try await a.send()
            let batches = await deviceA.sentBatches
            let saved = await deviceA.saved
            let refused = await deviceA.failed
            note("the 300 went in batches of \(batches)")
            try expect(refused.isEmpty, "refused \(refused.count): \(refused.values.first.map { String(describing: $0) } ?? "")")
            try expect(saved.count == 300, "saved \(saved.count) of 300")
            try expect(batches == [250, 50], "batches \(batches), not [250, 50]")
        }
    }

    /// 8. The state A saved makes a new transport that has A's pending list (T3) and fetches only what changed since.
    private func restart() async {
        await step("a new transport from A's state: pending kept, a fetch brings only what changed") {
            await deviceA.clear()
            try await a.fetch() // A catches up with everything (its own 300 among it)
            let labelKey = key("TaskLabel")
            let kept = key("SavedFilter")
            await a.add([.save(kept)])
            await a.stop()
            let writes = await stateA.writes
            let savedState = await stateA.data
            try expect(savedState != nil, "A saved no state (\(writes) writes)")

            let deviceA2 = ProbeDevice("A2")
            let restarted = transport("A2", state: stateA)
            a2 = restarted
            await restarted.start(delegate: deviceA2)
            let pending = await restarted.pending()
            try expect(pending == [.save(kept)], "pending after the restart: \(pending)")
            await restarted.remove([.save(kept)])

            guard let bToken = await deviceB.token(labelKey) else { throw ProbeFailure("B has no token for the label") }
            var changed = originals.first { $0.key == labelKey }!
            changed["name"] = .string("Renamed on B")
            changed["updatedAt"] = .date(Date())
            await deviceB.clear()
            await deviceB.stage([OutgoingRecord(record: changed, system: bToken)])
            await b.add([.save(labelKey)])
            try await b.send()
            let renamed = await deviceB.saved[labelKey] != nil
            try expect(renamed, "B's rename not saved")

            try await restarted.fetch()
            let fetched = await deviceA2.fetched
            let removed = await deviceA2.fetchedRemoved
            let events = await deviceA2.eventNames
            note("A2's fetch: events \(events)")
            try expect(Set(fetched.keys) == [labelKey], "fetched \(fetched.count): \(fetched.keys.sorted().prefix(5))")
            try expect(removed.isEmpty, "removed \(removed)")
            try expect(fetched[labelKey]?.record["name"] == .string("Renamed on B"), "not B's rename")
        }
    }

    // MARK: Clean up

    private func cleanUp() async {
        await a2?.stop()
        await a?.stop()
        await b?.stop()
        if let subscriptions = try? await database.allSubscriptions() {
            note("subscriptions in the private database: \(subscriptions.map(\.subscriptionID))")
        }
        await step("zone \(zoneName) deleted") {
            let result = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
            if case .failure(let error)? = result.deleteResults[zoneID] { throw error }
        }
    }

    // MARK: Records

    /// One record of every type the engine sends (and the zone's `Meta`), every field set to a value that is not its
    /// default.
    static func everyType() -> [SyncRecord] {
        let project = UUID().uuidString, label = UUID().uuidString, switchboard = UUID().uuidString
        var out: [SyncRecord] = []
        var types: [(String, String?, [SyncField])] = SyncSchema.types.map { ($0.name, $0.singleton, $0.fields) }
        types.append((SyncSchema.metaType, SyncSchema.metaName, CloudRecordCodec.metaFields))
        for (type, singleton, fields) in types {
            let name: String
            switch type {
            case "Project": name = project
            case "TaskLabel": name = label
            case "Switchboard": name = switchboard
            default: name = singleton ?? UUID().uuidString
            }
            var record = SyncRecord(type: type, name: name)
            for (index, field) in fields.enumerated() {
                let value: SyncValue
                switch field.kind {
                case .string: value = .string("Probe \(type).\(field.key) ✓")
                case .int: value = .int(field.key == SyncSchema.metaFormatVersion ? Int64(SyncSchema.formatVersion) : Int64(7 + index))
                case .bool: value = .bool(true)
                case .date: value = .date(Date(timeIntervalSince1970: 1_763_190_000.123 + Double(index)))
                case .data: value = .data(Data((0..<512).map { UInt8(($0 * 31 + index) & 0xff) }))
                case .reference(let target):
                    value = .reference(target == "Project" ? project : target == "Switchboard" ? switchboard : UUID().uuidString)
                case .references: value = .references([label, UUID().uuidString])
                }
                record[field.key] = value
            }
            out.append(record)
        }
        return out
    }

    static func difference(_ a: SyncRecord, _ b: SyncRecord) -> String {
        guard a.key == b.key else { return "\(a.key) instead of \(b.key)" }
        let keys = Set(a.fields.keys).union(b.fields.keys).sorted()
        let differing = keys.filter { a.fields[$0]?.comparable != b.fields[$0]?.comparable }
        return differing.map { "\($0): \(a.fields[$0].map { String(describing: $0.comparable) } ?? "absent") ≠ \(b.fields[$0].map { String(describing: $0.comparable) } ?? "absent")" }
            .joined(separator: "; ")
    }
}
#endif
