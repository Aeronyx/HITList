import Foundation
import CloudKit
import OSLog
import HITListCore

/// Where the transport's lines go: the app's `sync` log category by default; the probe also prints them.
struct SyncTransportLog: Sendable {
    let write: @Sendable (String) -> Void

    init(_ write: @escaping @Sendable (String) -> Void) { self.write = write }

    static let system: SyncTransportLog = {
        let logger = Logger(subsystem: "com.trammells.hitlist", category: "sync")
        // Keys, counts and CloudKit's error codes only: never a title (the sync log's rule).
        return SyncTransportLog { logger.notice("Engine transport: \($0, privacy: .public)") }
    }()
}

/// The engine's road to iCloud on Apple's `CKSyncEngine` (brief 142; the rules T1 to T14 are in `dev/SYNC-ENGINE.md`,
/// section 6, and this file keeps them as `FakeCloud` does).
///
/// One engine on the private database of `containerID`, working in one zone (`SyncSchema.zoneName`; the probe passes
/// a zone of its own). The mirror's zone lives in the same database: fetches are scoped to this zone
/// (`nextFetchChangesOptions`), batches hold only this zone's changes (`context.options.scope.contains` and the zone),
/// and every event is filtered by zone before the brain sees it.
///
/// Every decision about an error is a small pure function in `CloudKitTransportRules`, tested without a server; this
/// actor only carries them out. Its own state (`StoredState`: the engine's serialization, whether the zone is known
/// to exist, the account it belongs to) is written through `SyncTransportState` on every `stateUpdate`.
actor CloudKitTransport: SyncTransport, CKSyncEngineDelegate {
    enum TransportError: Error, CustomStringConvertible {
        case notStarted
        var description: String { "the transport has not started" }
    }

    nonisolated let containerID: String
    nonisolated let zoneID: CKRecordZone.ID
    private let stateStore: any SyncTransportState
    private let automaticallySync: Bool
    private let log: SyncTransportLog
    private let assets = AssetFiles()

    private var engine: CKSyncEngine?
    private var delegate: (any SyncTransportDelegate)?
    private var stored = StoredState()

    /// How many changes the next batch may hold: 250 (CloudKit's limit per request), halved after `limitExceeded`
    /// (the batch initialiser counts records, not bytes) and doubled back after each batch that went through.
    private(set) var batchLimit = CloudKitTransportRules.maximumBatch

    // One fetch and one send at a time, as the engine runs them.
    private var manualFetches = 0
    private var manualSends = 0
    private var fetchOpen = false
    private var sendOpen = false
    private var heldDidFetch = false
    private var heldDidSend = false
    private var fetchTrouble: String?
    private var sendTrouble: String?
    /// Saves refused before they reached iCloud (the record could not be made): told with the next `sent`.
    private var unsentFailures: [SyncKey: SendFailure] = [:]
    /// Changes to add again when the send ends (the zone is made first; adding them during the send would have the
    /// engine send them again before the zone exists).
    private var resaveAtEnd: [CKSyncEngine.PendingRecordZoneChange] = []
    /// Why the zone could not be made, when it was refused for good this send (`quotaExceeded`): the saves that fail
    /// for want of it are then refused with that reason instead of being tried again in a loop.
    private var zoneRefusal: CloudFailure?
    private var zoneRemade = false

    // T1: one event at a time to the brain, whichever road it comes by (an engine event, or a `didFetch`/`didSend`
    // held for a manual fetch or send until its error is known).
    private var delivering = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var stopped = false

    init(containerID: String, zoneName: String = SyncSchema.zoneName, state: any SyncTransportState,
         automaticallySync: Bool = true, log: SyncTransportLog = .system) {
        self.containerID = containerID
        self.zoneID = CloudRecordCodec.zoneID(zoneName)
        self.stateStore = state
        self.automaticallySync = automaticallySync
        self.log = log
    }

    private var database: CKDatabase { CKContainer(identifier: containerID).privateCloudDatabase }

    // MARK: - SyncTransport

    func start(delegate: any SyncTransportDelegate) async {
        guard engine == nil else { return }
        self.delegate = delegate
        stopped = false
        AssetFiles.sweepStale()
        stored = StoredState.decode(await stateStore.loadTransportState(), log: log)
        engine = makeEngine(stored.engine)
        log.write("started in zone \(zoneID.zoneName) (state \(stored.engine == nil ? "new" : "restored"), zone \(stored.zoneReady ? "known" : "not known"), automatic \(automaticallySync))")
    }

    func stop() async {
        stopped = true
        // No event after this returns (the protocol's promise): wait out the one being handled, if any.
        await acquireDelivery()
        releaseDelivery()
        guard let engine else { return }
        self.engine = nil
        delegate = nil
        await engine.cancelOperations()
        assets.removeAll()
    }

    func pending() async -> [PendingChange] {
        guard let engine else { return [] }
        return engine.state.pendingRecordZoneChanges.compactMap { CloudKitTransportRules.pendingChange($0, in: zoneID) }
    }

    func add(_ changes: [PendingChange]) async {
        guard let engine else { return log.write("add before start: \(changes.count) change(s) not added") }
        guard !changes.isEmpty else { return }
        // The zone first: the engine sends database changes before record changes. Saving a zone that exists
        // changes nothing, so it is queued whenever the zone is not known to exist.
        if !stored.zoneReady, changes.contains(where: { if case .save = $0 { return true } else { return false } }) {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        engine.state.add(pendingRecordZoneChanges: changes.map { CloudKitTransportRules.engineChange($0, in: zoneID) })
    }

    func remove(_ changes: [PendingChange]) async {
        guard let engine, !changes.isEmpty else { return }
        engine.state.remove(pendingRecordZoneChanges: changes.map { CloudKitTransportRules.engineChange($0, in: zoneID) })
    }

    func fetch() async throws {
        guard let engine else { throw TransportError.notStarted }
        manualFetches += 1
        var thrown: Error?
        do {
            try await engine.fetchChanges(CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zoneID])))
        } catch {
            thrown = error
        }
        manualFetches -= 1
        let failure = thrown.map { CloudKitTransportRules.words(for: $0) }
        if heldDidFetch || (failure != nil && fetchOpen) {
            heldDidFetch = false
            fetchOpen = false
            await deliver(.didFetch(error: failure ?? fetchTrouble))
        }
        if let thrown, !CloudKitTransportRules.isAnsweredByEvents(thrown, sending: false) {
            log.write("fetch failed: \(failure ?? "")")
            throw thrown
        }
    }

    func send() async throws {
        guard engine != nil else { throw TransportError.notStarted }
        manualSends += 1
        var thrown: Error?
        // A send that found the zone missing makes it and adds the refused saves again at its end: once more, so
        // that they go before `send()` returns (T14). Never more than twice.
        for round in 0..<2 {
            guard let engine = self.engine else { break }
            zoneRemade = false
            do {
                // All scopes: the engine's own pending changes are only ever this zone's (and its saveZone), and a
                // zone-scoped send is not documented to carry the zone's own save. Batches are cut to the zone.
                try await engine.sendChanges(CKSyncEngine.SendChangesOptions(scope: .all))
                thrown = nil
            } catch {
                thrown = error
            }
            guard zoneRemade, round == 0 else { break }
            log.write("the zone was made again during the send: sending once more")
        }
        manualSends -= 1
        let failure = thrown.map { CloudKitTransportRules.words(for: $0) }
        if heldDidSend || (failure != nil && sendOpen) {
            heldDidSend = false
            sendOpen = false
            await deliver(.didSend(error: failure ?? sendTrouble))
        }
        if let thrown, !CloudKitTransportRules.isAnsweredByEvents(thrown, sending: true) {
            log.write("send failed: \(failure ?? "")")
            throw thrown
        }
    }

    func reset() async {
        // The state forgotten on disk first: a crash before the new engine exists leaves a forgotten state, which is
        // what was asked. (The other order could leave the old bookmark to be restored at the next launch.)
        let account = stored.account
        stored = StoredState(engine: nil, zoneReady: false, account: account)
        await save()
        let old = engine
        engine = makeEngine(nil)
        batchLimit = CloudKitTransportRules.maximumBatch
        resaveAtEnd = []
        unsentFailures = [:]
        zoneRefusal = nil
        if let old {
            // Not awaited: `reset()` may be called while the old engine waits for an event to be handled, and its
            // events are ignored from now on anyway (`isCurrent`).
            Task { await old.cancelOperations() }
        }
        log.write("reset: a new engine with no state")
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard isCurrent(syncEngine) else { return }
        switch event {
        case .stateUpdate(let update):
            // T1: the brain has already kept what the events before this one brought (each `handle` returned), so
            // the bookmark this state carries never runs ahead of the ledger. A crash before this write fetches the
            // same changes again: an echo the brain takes as it is (T2).
            stored.engine = update.stateSerialization
            await save()

        case .accountChange(let change):
            let mapped = CloudKitTransportRules.accountChange(change.changeType, known: stored.account)
            // The engine has already forgotten its pending changes (and its bookmark) for the old account.
            stored.zoneReady = false
            stored.account = CloudKitTransportRules.currentAccount(change.changeType)
            await save()
            if let mapped {
                log.write("account: \(String(describing: mapped))")
                await deliver(.account(mapped))
            } else {
                log.write("account: the same account as before (\(stored.account ?? "none")), not told again")
            }

        case .fetchedDatabaseChanges(let changes):
            if changes.modifications.contains(where: { $0.zoneID == zoneID }) { await zoneExists() }
            if let deletion = changes.deletions.first(where: { $0.zoneID == zoneID }) {
                await zoneLost(CloudKitTransportRules.zoneLoss(deletion.reason), syncEngine: syncEngine, why: "fetched deletion")
            }

        case .fetchedRecordZoneChanges(let changes):
            await fetched(changes)

        case .sentDatabaseChanges(let sent):
            await sentZones(sent)

        case .sentRecordZoneChanges(let sent):
            await sentRecords(sent, syncEngine: syncEngine)

        case .willFetchChanges:
            fetchOpen = true
            fetchTrouble = nil
            await deliver(.willFetch)

        case .willFetchRecordZoneChanges:
            break

        case .didFetchRecordZoneChanges(let done):
            guard done.zoneID == zoneID else { break }
            let failure = done.error.map(CloudFailure.init)
            switch CloudKitTransportRules.fetchOutcome(failure, zoneKnown: stored.zoneReady) {
            case .fine:
                await zoneExists()
            case .absent:
                log.write("the zone is not in iCloud yet")
            case .lost(let loss):
                await zoneLost(loss, syncEngine: syncEngine, why: "fetch: \(failure.map(CloudKitTransportRules.words) ?? "")")
            case .trouble(let words):
                fetchTrouble = words
                log.write("fetching the zone: \(words)")
            }

        case .didFetchChanges(let done):
            if done.context.reason == .manual, manualFetches > 0 {
                heldDidFetch = true // `fetch()` tells it, with the error it gets, if any
            } else {
                fetchOpen = false
                await deliver(.didFetch(error: fetchTrouble))
            }

        case .willSendChanges:
            sendOpen = true
            sendTrouble = nil
            await deliver(.willSend)

        case .didSendChanges(let done):
            await sendEnded(syncEngine: syncEngine, manual: done.context.reason == .manual && manualSends > 0)

        @unknown default:
            log.write("an engine event this build does not know: \(event)")
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard isCurrent(syncEngine), delegate != nil else { return nil }
        // A record whose provider gives nothing is dropped from the list here (T3: nil drops the change), so the
        // next round asks for the next changes instead of the same ones.
        while true {
            let pending = syncEngine.state.pendingRecordZoneChanges.filter {
                context.options.scope.contains($0) && CloudKitTransportRules.zone(of: $0) == zoneID
            }
            guard !pending.isEmpty else { return nil }
            let slice = Array(pending.prefix(batchLimit))
            dropped = []
            let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: slice) { id in
                await self.recordToSend(id)
            }
            if !dropped.isEmpty {
                syncEngine.state.remove(pendingRecordZoneChanges: dropped)
                log.write("\(dropped.count) pending save(s) dropped: nothing to send for them")
            }
            if let batch, !(batch.recordsToSave.isEmpty && batch.recordIDsToDelete.isEmpty) { return batch }
            guard !dropped.isEmpty else { return batch } // nothing was dropped: the engine's answer stands
        }
    }

    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                 syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        // Only this zone, whatever asked for the fetch (a push, the schedule): the mirror's zone is none of ours.
        var options = CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zoneID]), operationGroup: context.options.operationGroup)
        options.prioritizedZoneIDs = [zoneID]
        return options
    }

    // MARK: - Sending

    private var dropped: [CKSyncEngine.PendingRecordZoneChange] = []

    private func recordToSend(_ id: CKRecord.ID) async -> CKRecord? {
        guard id.zoneID == zoneID, let key = CloudRecordCodec.key(for: id) else {
            dropped.append(.saveRecord(id))
            log.write("a pending save not named by the engine, dropped: \(id.recordName)")
            return nil
        }
        guard let delegate, let outgoing = await delegate.recordToSend(key) else {
            if self.delegate != nil { dropped.append(.saveRecord(id)) }
            return nil
        }
        guard outgoing.record.key == key else {
            dropped.append(.saveRecord(id))
            unsentFailures[key] = .rejected(code: CloudKitTransportRules.localRefusal, message: "the record given is \(outgoing.record.key)")
            return nil
        }
        do {
            return try CloudRecordCodec.record(for: outgoing, in: zoneID, assets: assets)
        } catch {
            dropped.append(.saveRecord(id))
            unsentFailures[key] = .rejected(code: CloudKitTransportRules.localRefusal, message: "\(error)")
            log.write("\(key) not sent: \(error)")
            return nil
        }
    }

    private func sentZones(_ sent: CKSyncEngine.Event.SentDatabaseChanges) async {
        if sent.savedZones.contains(where: { $0.zoneID == zoneID }) {
            zoneRefusal = nil
            await zoneExists()
            log.write("zone \(zoneID.zoneName) saved")
        }
        for failure in sent.failedZoneSaves where failure.zone.zoneID == zoneID {
            let refusal = CloudFailure(failure.error)
            log.write("the zone could not be made: \(CloudKitTransportRules.words(refusal))")
            if !CloudKitTransportRules.retriedByEngine.contains(refusal.code) { zoneRefusal = refusal }
        }
        for (id, error) in sent.failedZoneDeletes where id == zoneID {
            log.write("the zone could not be deleted: \(CloudKitTransportRules.words(CloudFailure(error)))")
        }
    }

    private func sentRecords(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) async {
        let batchSize = sent.savedRecords.count + sent.failedRecordSaves.count + sent.deletedRecordIDs.count + sent.failedRecordDeletes.count
        var saved: [CloudRecord] = []
        var removed: [SyncKey] = []
        var failed: [SyncKey: SendFailure] = [:]
        var leaveList: [CKSyncEngine.PendingRecordZoneChange] = []
        var addNow: [CKSyncEngine.PendingRecordZoneChange] = []
        var lost: ZoneLoss?
        var shrank = false

        for record in sent.savedRecords where record.recordID.zoneID == zoneID {
            // Read before the asset's file goes: the record as iCloud now holds it is ours plus its new token.
            do {
                saved.append(try CloudRecordCodec.cloudRecord(from: record))
            } catch {
                log.write("a saved record could not be read back: \(error)")
            }
            assets.release(record.recordID)
        }
        if !saved.isEmpty { await zoneExists() }

        for id in sent.deletedRecordIDs where id.zoneID == zoneID {
            if let key = CloudRecordCodec.key(for: id) { removed.append(key) }
        }

        for failure in sent.failedRecordSaves where failure.record.recordID.zoneID == zoneID {
            let id = failure.record.recordID
            assets.release(id)
            guard let key = CloudRecordCodec.key(for: id) else { continue }
            let cloud = CloudFailure(failure.error)
            let outcome = CloudKitTransportRules.saveOutcome(cloud, batchSize: batchSize, zoneRefusal: zoneRefusal)
            switch outcome {
            case .keep(let words, let byEngine):
                sendTrouble = words
                if !byEngine { resaveAtEnd.append(.saveRecord(id)) }
            case .conflict:
                leaveList.append(.saveRecord(id))
                if let server = failure.error.serverRecord, let record = try? CloudRecordCodec.cloudRecord(from: server) {
                    failed[key] = .conflict(server: record)
                } else {
                    failed[key] = .rejected(code: cloud.code.rawValue, message: "a conflict without iCloud's record")
                }
            case .refused(let reason):
                leaveList.append(.saveRecord(id))
                failed[key] = reason
            case .remakeZone:
                // Brief 142: the zone again, and the refused saves again, without telling the brain.
                stored.zoneReady = false
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                resaveAtEnd.append(.saveRecord(id))
                zoneRemade = true
            case .zoneLost(let loss):
                lost = loss
            case .shrinkBatch:
                shrank = true
                addNow.append(.saveRecord(id))
            }
            log.write("\(key) not saved: \(CloudKitTransportRules.words(cloud)) → \(outcome)")
        }

        for (id, error) in sent.failedRecordDeletes where id.zoneID == zoneID {
            guard let key = CloudRecordCodec.key(for: id) else { continue }
            let cloud = CloudFailure(error)
            let outcome = CloudKitTransportRules.deleteOutcome(cloud, batchSize: batchSize)
            switch outcome {
            case .done:
                leaveList.append(.deleteRecord(id))
                removed.append(key)
            case .keep(let words, let byEngine):
                sendTrouble = words
                if !byEngine { resaveAtEnd.append(.deleteRecord(id)) }
            case .refused(let reason):
                leaveList.append(.deleteRecord(id))
                failed[key] = reason
            case .zoneLost(let loss):
                lost = loss
            case .shrinkBatch:
                shrank = true
                addNow.append(.deleteRecord(id))
            }
            log.write("\(key) not deleted: \(CloudKitTransportRules.words(cloud)) → \(outcome)")
        }

        batchLimit = CloudKitTransportRules.nextBatchLimit(current: batchLimit, batchSize: batchSize, limitExceeded: shrank)
        // Off the list before the brain hears of them (T6, T7, T9): it adds again what is still to go, and that
        // must not be taken off by this.
        if !leaveList.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: leaveList) }
        if !addNow.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: addNow) }
        for (key, failure) in unsentFailures where failed[key] == nil { failed[key] = failure }
        unsentFailures = [:]

        if !(saved.isEmpty && removed.isEmpty && failed.isEmpty) {
            await deliver(.sent(saved: saved, removed: removed, failed: failed))
        }
        if let lost { await zoneLost(lost, syncEngine: syncEngine, why: "send") }
    }

    private func sendEnded(syncEngine: CKSyncEngine, manual: Bool) async {
        if !resaveAtEnd.isEmpty {
            // Added again only now, after the zone's save is queued: the engine schedules another send for them
            // (and `send()` runs one more round itself).
            if !stored.zoneReady { syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]) }
            syncEngine.state.add(pendingRecordZoneChanges: resaveAtEnd)
            resaveAtEnd = []
        }
        if !unsentFailures.isEmpty {
            let failed = unsentFailures
            unsentFailures = [:]
            await deliver(.sent(saved: [], removed: [], failed: failed))
        }
        // Every asset file of this send goes, whatever became of its record.
        assets.removeAll()
        if manual {
            heldDidSend = true // `send()` tells it, with the error it gets, if any
        } else {
            sendOpen = false
            await deliver(.didSend(error: sendTrouble))
        }
    }

    // MARK: - Fetching

    private func fetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        var changed: [CloudRecord] = []
        var removed: [SyncKey] = []
        for modification in changes.modifications where modification.record.recordID.zoneID == zoneID {
            do {
                changed.append(try CloudRecordCodec.cloudRecord(from: modification.record))
            } catch {
                log.write("a fetched record is ignored: \(error)")
            }
        }
        for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
            if let key = CloudRecordCodec.key(for: deletion.recordID) {
                removed.append(key)
            } else {
                log.write("a removed record is ignored: not an engine record: \(deletion.recordID.recordName)")
            }
        }
        if !(changes.modifications.isEmpty && changes.deletions.isEmpty) { await zoneExists() }
        guard !(changed.isEmpty && removed.isEmpty) else { return }
        await deliver(.fetched(changed: changed, removed: removed))
    }

    // MARK: - The zone

    private func zoneExists() async {
        guard !stored.zoneReady else { return }
        stored.zoneReady = true
        await save()
    }

    /// T11: the list and the zone forgotten, then the brain told. The engine drops its bookmark for a zone it has
    /// fetched the deletion of; the brain calls `reset()` when it wants every record again.
    private func zoneLost(_ loss: ZoneLoss, syncEngine: CKSyncEngine, why: String) async {
        let state = syncEngine.state
        state.remove(pendingRecordZoneChanges: state.pendingRecordZoneChanges.filter { CloudKitTransportRules.zone(of: $0) == zoneID })
        state.remove(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        resaveAtEnd = []
        stored.zoneReady = false
        await save()
        log.write("zone lost (\(loss.rawValue)) from \(why)")
        await deliver(.zoneLost(loss))
    }

    // MARK: - Delivery and state

    private func isCurrent(_ syncEngine: CKSyncEngine) -> Bool { syncEngine === engine && !stopped }

    private func deliver(_ event: TransportEvent) async {
        await acquireDelivery()
        defer { releaseDelivery() }
        guard !stopped, let delegate else { return }
        await delegate.handle(event)
    }

    private func acquireDelivery() async {
        while delivering {
            await withCheckedContinuation { waiters.append($0) }
        }
        delivering = true
    }

    private func releaseDelivery() {
        delivering = false
        if !waiters.isEmpty { waiters.removeFirst().resume() }
    }

    private func save() async {
        await stateStore.saveTransportState(stored.encoded(log: log))
    }

    private func makeEngine(_ serialization: CKSyncEngine.State.Serialization?) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: self)
        configuration.automaticallySync = automaticallySync
        return CKSyncEngine(configuration)
    }
}

// MARK: - The transport's own state

/// What `CloudKitTransport` keeps through `SyncTransportState`: the engine's serialization (its bookmarks and pending
/// list), whether the zone is known to exist (so it is made only when needed), and the account the state belongs to
/// (so a new engine's "signed in" for the same account is not told as a change). JSON, versioned.
struct StoredState: Codable {
    var version = 1
    var engine: CKSyncEngine.State.Serialization?
    var zoneReady = false
    var account: String?

    init(engine: CKSyncEngine.State.Serialization? = nil, zoneReady: Bool = false, account: String? = nil) {
        self.engine = engine
        self.zoneReady = zoneReady
        self.account = account
    }

    static func decode(_ data: Data?, log: SyncTransportLog) -> StoredState {
        guard let data else { return StoredState() }
        do {
            return try JSONDecoder().decode(StoredState.self, from: data)
        } catch {
            // Unreadable: start afresh. The engine then fetches every record (an echo of everything, T2) and has
            // no pending list; the brain's comparison finds again what is waiting.
            log.write("the saved state could not be read, starting afresh: \(error)")
            return StoredState()
        }
    }

    func encoded(log: SyncTransportLog) -> Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            log.write("the state could not be written: \(error)")
            return nil
        }
    }
}

// MARK: - Decisions

/// One CloudKit error, as the decisions need it.
struct CloudFailure: Equatable, Sendable {
    var code: CKError.Code
    /// `zoneNotFound` caused by the person resetting their encrypted data (`CKErrorUserDidResetEncryptedDataKey`).
    var encryptedDataReset: Bool
    var message: String

    init(code: CKError.Code, encryptedDataReset: Bool = false, message: String = "") {
        self.code = code
        self.encryptedDataReset = encryptedDataReset
        self.message = message
    }

    init(_ error: CKError) {
        let reset = (error.userInfo[CKErrorUserDidResetEncryptedDataKey] as? NSNumber)?.boolValue ?? false
        self.init(code: error.code, encryptedDataReset: reset, message: error.localizedDescription)
    }
}

/// Every decision `CloudKitTransport` makes about what iCloud answered: pure, so each is tested without a server
/// (the SDK lets no test build an engine event). The table in brief 142's report is these functions.
enum CloudKitTransportRules {
    static let maximumBatch = 250
    /// `SendFailure.rejected`'s code for a change refused before it reached iCloud (the record could not be made).
    static let localRefusal = -1

    /// The codes `CKSyncEngine` retries by itself, keeping the change on its list (T5; `CKSyncEngine.h`).
    static let retriedByEngine: Set<CKError.Code> = [
        .notAuthenticated, .accountTemporarilyUnavailable, .networkFailure, .networkUnavailable,
        .requestRateLimited, .serviceUnavailable, .zoneBusy,
    ]

    /// Passing trouble the engine does not retry by itself: the transport adds the change again when the send ends.
    /// `serverResponseLost`: the save may have landed; sent again on the same token, it lands or comes back as a
    /// conflict carrying our own version, which the brain settles as the same. `batchRequestFailed`: another
    /// change in an atomic batch failed (the transport never asks for atomic batches). `operationCancelled`: the
    /// send was stopped (`stop()`, `reset()`, the system).
    static let retriedByTransport: Set<CKError.Code> = [.serverResponseLost, .batchRequestFailed, .operationCancelled]

    enum SaveOutcome: Equatable {
        /// T5: stays pending (`byEngine`: on the engine's own list; else added again at the send's end).
        case keep(words: String, byEngine: Bool)
        /// T6: off the list, the brain gets iCloud's version.
        case conflict
        /// The zone is missing: made again, the save added again, the brain not told.
        case remakeZone
        /// T11.
        case zoneLost(ZoneLoss)
        /// The batch was too big: the change stays, the next batch is half the size.
        case shrinkBatch
        /// T7, T9: off the list, the brain told why.
        case refused(SendFailure)
    }

    static func saveOutcome(_ failure: CloudFailure, batchSize: Int, zoneRefusal: CloudFailure? = nil) -> SaveOutcome {
        if retriedByEngine.contains(failure.code) { return .keep(words: words(failure), byEngine: true) }
        if retriedByTransport.contains(failure.code) { return .keep(words: words(failure), byEngine: false) }
        switch failure.code {
        case .serverRecordChanged:
            return .conflict
        case .unknownItem:
            return .refused(.unknownItem)
        case .zoneNotFound:
            if failure.encryptedDataReset { return .zoneLost(.encryptedDataReset) }
            // The zone was refused for good this send (iCloud full): no loop of making it again.
            if let zoneRefusal { return .refused(refusal(zoneRefusal)) }
            return .remakeZone
        case .userDeletedZone:
            return .zoneLost(.purged)
        case .limitExceeded:
            return batchSize > 1 ? .shrinkBatch : .refused(.tooLarge)
        default:
            return .refused(refusal(failure))
        }
    }

    enum DeleteOutcome: Equatable {
        /// T7: a delete of a record iCloud does not hold (or a zone it is not in) counts as done.
        case done
        case keep(words: String, byEngine: Bool)
        case zoneLost(ZoneLoss)
        case shrinkBatch
        case refused(SendFailure)
    }

    static func deleteOutcome(_ failure: CloudFailure, batchSize: Int) -> DeleteOutcome {
        if retriedByEngine.contains(failure.code) { return .keep(words: words(failure), byEngine: true) }
        if retriedByTransport.contains(failure.code) { return .keep(words: words(failure), byEngine: false) }
        switch failure.code {
        case .unknownItem:
            return .done
        case .zoneNotFound:
            return failure.encryptedDataReset ? .zoneLost(.encryptedDataReset) : .done
        case .userDeletedZone:
            return .zoneLost(.purged)
        case .limitExceeded:
            return batchSize > 1 ? .shrinkBatch : .refused(.rejected(code: failure.code.rawValue, message: failure.message))
        default:
            return .refused(refusal(failure))
        }
    }

    /// T9's three: iCloud full, too large, anything else said no to for good.
    static func refusal(_ failure: CloudFailure) -> SendFailure {
        switch failure.code {
        case .quotaExceeded: return .quotaExceeded
        default: return .rejected(code: failure.code.rawValue, message: failure.message)
        }
    }

    enum FetchOutcome: Equatable {
        case fine
        /// The zone is not in iCloud and never was, as far as this device knows: nothing to fetch yet.
        case absent
        case lost(ZoneLoss)
        case trouble(String)
    }

    /// The end of a fetch of the zone (`didFetchRecordZoneChanges`).
    static func fetchOutcome(_ failure: CloudFailure?, zoneKnown: Bool) -> FetchOutcome {
        guard let failure else { return .fine }
        switch failure.code {
        case .userDeletedZone:
            return .lost(.purged)
        case .zoneNotFound:
            if failure.encryptedDataReset { return .lost(.encryptedDataReset) }
            // A zone this device knew, gone without a reason given: deleted (the dashboard, a test). One it never
            // knew: not made yet, nothing lost.
            return zoneKnown ? .lost(.deleted) : .absent
        default:
            return .trouble(words(failure))
        }
    }

    static func zoneLoss(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) -> ZoneLoss {
        switch reason {
        case .deleted: return .deleted
        case .purged: return .purged
        case .encryptedDataReset: return .encryptedDataReset
        @unknown default: return .deleted
        }
    }

    /// T12: the change, by user record names; nil when a new engine (after `reset()`, or one whose state was lost)
    /// reports signing in to the account the transport already belonged to, which is no change at all.
    static func accountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType, known: String?) -> AccountChange? {
        switch change {
        case .signIn(let current):
            return current.recordName == known ? nil : .signedIn(current: current.recordName)
        case .signOut(let previous):
            return .signedOut(previous: previous.recordName)
        case .switchAccounts(let previous, let current):
            return .switched(previous: previous.recordName, current: current.recordName)
        @unknown default:
            return nil
        }
    }

    static func currentAccount(_ change: CKSyncEngine.Event.AccountChange.ChangeType) -> String? {
        switch change {
        case .signIn(let current): return current.recordName
        case .switchAccounts(_, let current): return current.recordName
        case .signOut: return nil
        @unknown default: return nil
        }
    }

    /// The next batch's size: half after `limitExceeded`, back up by doubling after a batch that went through.
    static func nextBatchLimit(current: Int, batchSize: Int, limitExceeded: Bool) -> Int {
        if limitExceeded { return max(1, min(current, batchSize) / 2) }
        return min(maximumBatch, current * 2)
    }

    /// Whether a thrown error from `fetchChanges`/`sendChanges` was already answered record by record or zone by zone
    /// in the events (a conflict, a missing record or zone): then `fetch()`/`send()` do not throw it again.
    static func isAnsweredByEvents(_ error: Error, sending: Bool) -> Bool {
        guard let error = error as? CKError else { return false }
        let perItem: Set<CKError.Code> = sending
            ? [.partialFailure, .serverRecordChanged, .batchRequestFailed, .unknownItem, .zoneNotFound, .userDeletedZone,
               .limitExceeded, .quotaExceeded]
            : [.partialFailure, .zoneNotFound, .userDeletedZone]
        return perItem.contains(error.code)
    }

    static func words(for error: Error) -> String {
        if let error = error as? CKError { return words(CloudFailure(error)) }
        return "\(error)"
    }

    static func words(_ failure: CloudFailure) -> String {
        "\(name(failure.code)) (\(failure.code.rawValue))" + (failure.message.isEmpty ? "" : ": \(failure.message)")
    }

    static func name(_ code: CKError.Code) -> String {
        switch code {
        case .networkUnavailable: return "networkUnavailable"
        case .networkFailure: return "networkFailure"
        case .serviceUnavailable: return "serviceUnavailable"
        case .requestRateLimited: return "requestRateLimited"
        case .notAuthenticated: return "notAuthenticated"
        case .accountTemporarilyUnavailable: return "accountTemporarilyUnavailable"
        case .zoneBusy: return "zoneBusy"
        case .serverRecordChanged: return "serverRecordChanged"
        case .unknownItem: return "unknownItem"
        case .zoneNotFound: return "zoneNotFound"
        case .userDeletedZone: return "userDeletedZone"
        case .quotaExceeded: return "quotaExceeded"
        case .limitExceeded: return "limitExceeded"
        case .batchRequestFailed: return "batchRequestFailed"
        case .partialFailure: return "partialFailure"
        case .serverResponseLost: return "serverResponseLost"
        case .operationCancelled: return "operationCancelled"
        case .invalidArguments: return "invalidArguments"
        case .serverRejectedRequest: return "serverRejectedRequest"
        case .permissionFailure: return "permissionFailure"
        case .changeTokenExpired: return "changeTokenExpired"
        case .assetFileNotFound: return "assetFileNotFound"
        case .missingEntitlement: return "missingEntitlement"
        case .badContainer: return "badContainer"
        default: return "CKError"
        }
    }

    // MARK: Names of pending changes

    static func engineChange(_ change: PendingChange, in zoneID: CKRecordZone.ID) -> CKSyncEngine.PendingRecordZoneChange {
        switch change {
        case .save(let key): return .saveRecord(CloudRecordCodec.recordID(for: key, in: zoneID))
        case .delete(let key): return .deleteRecord(CloudRecordCodec.recordID(for: key, in: zoneID))
        }
    }

    /// The engine's pending change as the brain names it; nil for one in another zone or not named by the engine.
    static func pendingChange(_ change: CKSyncEngine.PendingRecordZoneChange, in zoneID: CKRecordZone.ID) -> PendingChange? {
        switch change {
        case .saveRecord(let id):
            guard id.zoneID == zoneID, let key = CloudRecordCodec.key(for: id) else { return nil }
            return .save(key)
        case .deleteRecord(let id):
            guard id.zoneID == zoneID, let key = CloudRecordCodec.key(for: id) else { return nil }
            return .delete(key)
        @unknown default:
            return nil
        }
    }

    static func zone(of change: CKSyncEngine.PendingRecordZoneChange) -> CKRecordZone.ID? {
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): return id.zoneID
        @unknown default: return nil
        }
    }
}
