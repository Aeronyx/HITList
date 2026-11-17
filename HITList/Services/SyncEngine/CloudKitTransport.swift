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
/// One engine on the private database of `containerID`, working in one zone (`SyncSchema.zoneName`; the probe and
/// the supervisor's runs pass zones of their own, so in Development the database holds several). A fetch asked for
/// here asks the engine for everything (`.all`, as Apple's sample does: the step that learns from the database which
/// zones changed is then never in question); which zones' records are then fetched is this zone alone
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
    /// Whether this fetch ended a fetch of the zone without error (or found the zone not made yet): the one sign a
    /// scheduled fetch gives that it reached iCloud at all (`didFetchChanges` carries no error).
    private var zoneFetchEnded = false
    /// How many fetches the engine has ended (`didFetchChanges`), so `fetch()` can tell that the engine really ran
    /// one for it rather than returning at once (no account, or joined to nothing).
    private var fetchesEnded = 0
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
    /// Whether a whole fetch had been seen under this state when the fetch now running began: only then are records
    /// still owed told as the fetch's words (`CloudKitTransportRules.fetchEnding`).
    private var wholeFetchSeenBeforeThisFetch = false
    /// iCloud answered this fetch that its change token has expired (16e): the bookmark is forgotten and everything
    /// fetched again, once per fetch.
    private var tokenExpired = false

    // T1: one event at a time to the brain, whichever road it comes by (an engine event, or a `didFetch`/`didSend`
    // held for a manual fetch or send until its error is known).
    private var delivering = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var stopped = false

    /// The pending list was changed here (`add`, `remove`) and the engine has not yet handed over the state that
    /// holds the change (`stateUpdate` comes a moment later, on its own). `stop()` waits for it, so a list changed
    /// just before a clean stop survives the relaunch (T3). After a crash it is lost, and the brain's comparison at
    /// the next start finds the same changes again.
    private var stateBehind = false
    private var stateWaiters: [CheckedContinuation<Void, Never>] = []
    /// How long `stop()` waits for that state: the engine hands it over within moments; past this the stop goes on.
    static let stateFlushWait: Double = 3
    /// How many times the state was written (the probe reads it).
    private(set) var stateSaves = 0

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
        if stateBehind, engine != nil { await waitForState() }
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
        let added = changes.map { CloudKitTransportRules.engineChange($0, in: zoneID) }
        engine.state.add(pendingRecordZoneChanges: added)
        // A batch may be gathering right now, each record asked for in its own turn of the brain: a save answered
        // "nothing to send" a moment ago and added again since (the person changed the item in between) must not be
        // struck from the list when the gathering ends (the review's finding 16a).
        if !dropped.isEmpty { dropped.removeAll { added.contains($0) } }
        stateBehind = true
    }

    func remove(_ changes: [PendingChange]) async {
        guard let engine, !changes.isEmpty else { return }
        engine.state.remove(pendingRecordZoneChanges: changes.map { CloudKitTransportRules.engineChange($0, in: zoneID) })
        stateBehind = true
    }

    func fetch() async throws {
        guard let engine else { throw TransportError.notStarted }
        await tellOwedAccount()
        manualFetches += 1
        let endedBefore = fetchesEnded
        var thrown: Error?
        // An expired change token (16e): the bookmark is forgotten and the fetch run once more, from nothing. Never
        // more than twice: a second expiry is told as trouble, and the next fetch tries again.
        for round in 0..<2 {
            guard let engine = self.engine else { break }
            tokenExpired = false
            thrown = nil
            do {
                try await engine.fetchChanges(CKSyncEngine.FetchChangesOptions(scope: .all))
            } catch {
                thrown = error
                if CloudKitTransportRules.isTokenExpired(error) { tokenExpired = true }
            }
            guard CloudKitTransportRules.refetchesAfterExpiredToken(expired: tokenExpired, round: round) else { break }
            await forgetExpiredToken()
        }
        tokenExpired = false
        manualFetches -= 1
        let failure = thrown.map { CloudKitTransportRules.words(for: $0) }
        // A fetch asked for here that the engine ran to its end without throwing, for an account, did reach iCloud:
        // the proof of a whole fetch. One that returned without the engine ending a fetch at all (no account; a call
        // that joined nothing) proves nothing (the review's finding 17).
        if CloudKitTransportRules.provesWholeFetch(threw: failure != nil, trouble: fetchTrouble,
                                                   engineEndedAFetch: fetchesEnded > endedBefore,
                                                   account: stored.account) {
            await wholeFetchSeen()
        }
        if heldDidFetch || (failure != nil && fetchOpen) {
            heldDidFetch = false
            fetchOpen = false
            await tellOwed()
            await deliver(.didFetch(error: CloudKitTransportRules.fetchEnding(failure ?? fetchTrouble, owed: stored.owedRecords,
                                                                              wholeFetchSeenBefore: wholeFetchSeenBeforeThisFetch)))
        }
        if let thrown, !CloudKitTransportRules.isAnsweredByEvents(thrown, sending: false) {
            log.write("fetch failed: \(failure ?? "")")
            throw thrown
        }
        if thrown == nil { await ensureSubscription() }
    }

    /// The subscription that makes iCloud push this device when the database changes: **the engine's own**, saved
    /// once per device and account after a fetch that reached iCloud. Apple's engine keeps one of its own while it
    /// schedules itself; with its scheduling off (as the app runs it) nothing here may depend on that, and after
    /// the Development side was reset in round 32 no push reached either device until one was saved again. A silent
    /// push for it reaches the app's delegate, which asks for a sync (`SyncAppDelegate`).
    static let subscriptionID = "HITListSync-Private"

    private func ensureSubscription() async {
        guard stored.subscribed != true, stored.account != nil, !stopped else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
            stored.subscribed = true
            await save()
            log.write("the push subscription is saved")
        } catch {
            log.write("the push subscription could not be saved (\(CloudKitTransportRules.words(for: error))); tried again at the next fetch")
        }
    }

    func send() async throws {
        guard engine != nil else { throw TransportError.notStarted }
        await tellOwedAccount()
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
        // Only the bookmark and the list go (T13). The account stays: the new engine announces a sign-in for whoever
        // is signed in, and the brain reads a sign-in to its own account as "the transport lost its memory" and
        // forgets its own (T12); a reset the brain asked for, to have every record again WITH its memory, must not
        // look like that (the review's finding 10: every lifted hold would have cost the brain its ledger, and unsent
        // edits a field-by-field merge). What the device knew of the zone stays too, so a zone deleted meanwhile is
        // still found lost at the next fetch instead of read as "not made yet".
        await replaceEngine(keepingPending: false)
    }

    /// The answer to an expired change token (16e; T13 and less): the bookmark forgotten, and a new engine fetches
    /// every record from nothing. Kept: the account (no account event follows, so the brain keeps its ledger, T12),
    /// what was known of the zone, the records still owed, and the pending list (put on the new engine as it was:
    /// the brain is not asked to compare again for a token iCloud let expire).
    func forgetExpiredToken() async {
        log.write("the change token has expired: the bookmark is forgotten, everything is fetched again")
        await replaceEngine(keepingPending: true)
    }

    private func replaceEngine(keepingPending: Bool) async {
        let records = keepingPending ? engine?.state.pendingRecordZoneChanges ?? [] : []
        let zones = keepingPending ? engine?.state.pendingDatabaseChanges ?? [] : []
        // Before `start()` there is no engine to replace: the state is forgotten, and `start()` makes the engine
        // with its delegate. (Making one here would leave `start()` nothing to do, and the delegate never set: found
        // by session 143.)
        guard let old = engine else {
            stored = stored.afterReset()
            await save()
            log.write("reset before start: the saved state is forgotten")
            return
        }
        // The new engine first, and the state forgotten in the same breath, before anything is awaited: from here
        // the old engine's events are ignored (`isCurrent`). In the other order the old engine, still current while
        // the forgotten state was being written, could hand in a state update of its own and put the old bookmark
        // back; a kill before the new engine's first update then restored it, and records let go meanwhile were
        // never fetched again (review 148, finding 4).
        let fresh = makeEngine(nil)
        engine = fresh
        stored = stored.afterReset()
        if !zones.isEmpty { fresh.state.add(pendingDatabaseChanges: zones) }
        if !records.isEmpty {
            fresh.state.add(pendingRecordZoneChanges: records)
            stateBehind = true
        }
        batchLimit = CloudKitTransportRules.maximumBatch
        resaveAtEnd = []
        unsentFailures = [:]
        zoneRefusal = nil
        await save()
        // Not awaited: this may run while the old engine waits for an event to be handled, and its events are
        // ignored from now on anyway (`isCurrent`).
        Task { await old.cancelOperations() }
        log.write("a new engine with no bookmark\(keepingPending ? ", \(records.count) pending change(s) kept" : "")")
    }

    // MARK: - CKSyncEngineDelegate

    /// `HITLIST_SYNC_TRACE=1`: every event the engine hands over, by name, in the log (the supervisor's runs).
    private static let traces = ProcessInfo.processInfo.environment["HITLIST_SYNC_TRACE"] == "1"

    private func trace(_ event: CKSyncEngine.Event, current: Bool) {
        let what: String
        switch event {
        case .stateUpdate: what = "stateUpdate"
        case .accountChange(let change): what = "accountChange \(change.changeType)"
        case .fetchedDatabaseChanges(let changes):
            what = "fetchedDatabaseChanges modified \(changes.modifications.map(\.zoneID.zoneName)) deleted \(changes.deletions.map(\.zoneID.zoneName))"
        case .fetchedRecordZoneChanges(let changes):
            what = "fetchedRecordZoneChanges \(changes.modifications.count) changed \(changes.deletions.count) removed"
        case .sentDatabaseChanges: what = "sentDatabaseChanges"
        case .sentRecordZoneChanges(let sent): what = "sentRecordZoneChanges \(sent.savedRecords.count) saved \(sent.failedRecordSaves.count) failed"
        case .willFetchChanges(let will): what = "willFetchChanges \(will.context.reason) \(will.context.options.scope)"
        case .willFetchRecordZoneChanges(let will): what = "willFetchRecordZoneChanges \(will.zoneID.zoneName)"
        case .didFetchRecordZoneChanges(let done): what = "didFetchRecordZoneChanges \(done.zoneID.zoneName) \(done.error.map { "error \($0.code.rawValue)" } ?? "ok")"
        case .didFetchChanges(let done): what = "didFetchChanges \(done.context.reason)"
        case .willSendChanges: what = "willSendChanges"
        case .didSendChanges: what = "didSendChanges"
        @unknown default: what = "unknown"
        }
        log.write("event\(current ? "" : " (not the current engine, ignored)"): \(what); unfetched zones \(syncEngine_unfetched)")
    }

    private var syncEngine_unfetched: [String] { engine?.state.zoneIDsWithUnfetchedServerChanges.map(\.zoneName) ?? [] }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        if Self.traces { trace(event, current: isCurrent(syncEngine)) }
        guard isCurrent(syncEngine) else { return }
        // An account change still owed to the brain from before a kill goes first (T12), ahead of whatever this
        // event brings; the engine's own bookkeeping (`stateUpdate`) and a fresh account change need not wait for it.
        if stored.owedAccount != nil {
            switch event {
            case .stateUpdate, .accountChange: break
            default: await tellOwedAccount()
            }
        }
        switch event {
        case .stateUpdate(let update):
            // T1: the brain has already kept what the events before this one brought (each `handle` returned), so
            // the bookmark this state carries never runs ahead of the ledger. A crash before this write fetches the
            // same changes again: an echo the brain takes as it is (T2).
            stored.engine = update.stateSerialization
            await save()
            stateSaves += 1
            stateBehind = false
            stateWaitEnded()

        case .accountChange(let change):
            let mapped = CloudKitTransportRules.accountChange(change.changeType, known: stored.account)
            // A real change of account: the engine has already forgotten its pending changes and its bookmark for
            // the old one, and what was known of the old account's zone says nothing of the new one's. A sign-in to
            // the account this state already belongs to (a new engine after `reset()` announces one) changes
            // nothing here: what was known of the zone must stay, or a zone deleted meanwhile would read as "not
            // made yet" (the review's findings 10 and 17).
            if mapped != nil {
                stored.zoneReady = false
                stored.fetchedWhole = false
                // Records owed from the old account's zone are none of the new one's.
                stored.owed = nil
                // And the push subscription is saved again for the new account.
                stored.subscribed = nil
            }
            stored.account = CloudKitTransportRules.currentAccount(change.changeType)
            // The change is written down as owed to the brain before it is told, and crossed off only when the brain
            // has handled it: the engine announces an account change once, so one saved as known here and lost
            // before the brain heard it (a kill in between) would never be told (the review's finding 8: the brain
            // stayed held "not signed in" for good).
            if let mapped { stored.owedAccount = StoredAccountChange(mapped) }
            await save()
            if let mapped {
                log.write("account: \(String(describing: mapped))")
                await tellOwedAccount()
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
            zoneFetchEnded = false
            fetchBrought = (0, 0)
            wholeFetchSeenBeforeThisFetch = stored.fetchedWhole == true
            await deliver(.willFetch)

        case .willFetchRecordZoneChanges:
            break

        case .didFetchRecordZoneChanges(let done):
            guard done.zoneID == zoneID else { break }
            let failure = done.error.map(CloudFailure.init)
            switch CloudKitTransportRules.fetchOutcome(failure, zoneKnown: stored.zoneReady) {
            case .fine:
                zoneFetchEnded = true
                await zoneExists()
            case .absent:
                zoneFetchEnded = true
                log.write("the zone is not in iCloud yet")
            case .lost(let loss):
                await zoneLost(loss, syncEngine: syncEngine, why: "fetch: \(failure.map(CloudKitTransportRules.words) ?? "")")
            case .trouble(let words):
                fetchTrouble = words
                log.write("fetching the zone: \(words)")
            case .tokenExpired:
                // Trouble for this fetch (it did not bring what changed); answered when it ends.
                tokenExpired = true
                fetchTrouble = failure.map(CloudKitTransportRules.words) ?? "changeTokenExpired"
                log.write("fetching the zone: the change token has expired")
            }

        case .didFetchChanges(let done):
            fetchesEnded += 1
            // One line per fetch in the sync log: what it brought and whether it reached the zone. A fetch that
            // brings nothing while another device's changes wait in iCloud is then visible as such (round 32).
            log.write("fetch ended (\(done.context.reason == .manual ? "asked" : "by itself")): \(fetchBrought.changed) changed, "
                      + "\(fetchBrought.removed) removed, zone \(zoneFetchEnded ? "reached" : "not reached")"
                      + (fetchTrouble.map { ", trouble: \($0)" } ?? ""))
            fetchBrought = (0, 0)
            // Records this build could not read are asked for again, by name, at the end of every fetch that
            // reached iCloud (16c), before the brain hears the fetch ended. Never on a timer.
            if fetchTrouble == nil, zoneFetchEnded { await retryOwed() }
            if done.context.reason == .manual, manualFetches > 0 {
                heldDidFetch = true // `fetch()` tells it, with the error it gets, if any
            } else {
                fetchOpen = false
                let ending = CloudKitTransportRules.scheduledFetchEnding(
                    trouble: fetchTrouble, reachedZone: zoneFetchEnded, wholeFetchSeen: stored.fetchedWhole == true)
                await tellOwed()
                await deliver(.didFetch(error: CloudKitTransportRules.fetchEnding(ending, owed: stored.owedRecords,
                                                                                  wholeFetchSeenBefore: wholeFetchSeenBeforeThisFetch)))
                if fetchTrouble == nil, zoneFetchEnded { await wholeFetchSeen() }
                if CloudKitTransportRules.refetchesAfterExpiredToken(expired: tokenExpired, round: 0) {
                    // A fetch the engine ran by itself: the bookmark forgotten here, and the whole fetch asked for
                    // once the engine is past this event (never from inside it, T1). That fetch is a manual one: an
                    // expiry again is told as trouble, not answered in a loop.
                    tokenExpired = false
                    await forgetExpiredToken()
                    Task { [weak self] in try? await self?.fetch() }
                }
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
        // Only this zone's records, whatever asked for the fetch: in Development the database holds the zones of
        // other runs too, and none of them is this store's.
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
        // Before anything in this batch changes it: did this device know the zone to exist?
        let zoneWasKnown = stored.zoneReady

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
            let outcome = CloudKitTransportRules.saveOutcome(cloud, batchSize: batchSize, zoneRefusal: zoneRefusal,
                                                             zoneKnown: zoneWasKnown)
            switch outcome {
            case .keep(let words, let byEngine):
                sendTrouble = words
                if !byEngine { resaveAtEnd.append(.saveRecord(id)) }
            case .conflict:
                leaveList.append(.saveRecord(id))
                do {
                    guard let server = failure.error.serverRecord else { throw CloudFailure(failure.error) }
                    failed[key] = .conflict(server: try CloudRecordCodec.cloudRecord(from: server))
                } catch {
                    // iCloud holds a version this build cannot read (a picture not downloaded with it, 16b): it is
                    // owed, like a fetched record that could not be read (16c), and asked for by name at the next
                    // fetch. The change leaves the list and the brain is not told: a refusal would keep the item out
                    // until it changes again, and a retry would lose to the same version in a loop. Nothing is
                    // overwritten meanwhile (iCloud refuses a save on any token but its own), and when the version
                    // can be read it arrives as fetched; the brain settles the two and sends what is still to go.
                    owe(id.recordName, why: "iCloud's version, in a conflict, could not be read: \(error is CloudFailure ? "none came with it" : "\(error)")")
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

        await saveIfOwedChanged()
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

    /// What the fetch in progress has brought so far, for its line in the sync log.
    private var fetchBrought = (changed: 0, removed: 0)

    private func fetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        fetchBrought.changed += changes.modifications.count
        fetchBrought.removed += changes.deletions.count
        var changed: [CloudRecord] = []
        var removed: [SyncKey] = []
        var arrived: [String] = []
        for modification in changes.modifications where modification.record.recordID.zoneID == zoneID {
            let name = modification.record.recordID.recordName
            do {
                changed.append(try CloudRecordCodec.cloudRecord(from: modification.record))
                arrived.append(name)
            } catch {
                // A record of ours this build cannot read (16c): owed, never dropped while the bookmark moves on.
                // One that is not ours at all is ignored, as before.
                if let why = CloudKitTransportRules.owedReason(error) {
                    owe(name, why: why)
                } else {
                    log.write("a fetched record is ignored: \(error)")
                }
            }
        }
        for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
            if let key = CloudRecordCodec.key(for: deletion.recordID) {
                removed.append(key)
                arrived.append(deletion.recordID.recordName)
            } else {
                log.write("a removed record is ignored: not an engine record: \(deletion.recordID.recordName)")
            }
        }
        if !(changes.modifications.isEmpty && changes.deletions.isEmpty) { await zoneExists() }
        // Owed records written down before the brain is told of the rest, and before `handle` returns (the bookmark
        // moves past them at the next state update).
        await saveIfOwedChanged()
        guard !(changed.isEmpty && removed.isEmpty) else { return }
        // A newer version that could be read, or its removal for good, settles what was owed for it; crossed off only
        // once the brain has it.
        if await deliver(.fetched(changed: changed, removed: removed)) { await settleOwed(arrived) }
    }

    // MARK: - Records owed (16c)

    private var owedChanged = false

    private func owe(_ recordName: String, why: String) {
        var owed = stored.owedRecords
        guard owed.reasons[recordName] != why else { return }
        owed.reasons[recordName] = why
        stored.owed = owed
        owedChanged = true
        log.write("\(CloudRecordCodec.key(forRecordName: recordName).map(String.init(describing:)) ?? recordName) owed: \(why)")
    }

    private func saveIfOwedChanged() async {
        guard owedChanged else { return }
        owedChanged = false
        await save()
    }

    private func settleOwed(_ recordNames: [String]) async {
        var owed = stored.owedRecords
        let before = owed.reasons.count
        for name in recordNames { owed.reasons[name] = nil }
        guard owed.reasons.count != before else { return }
        stored.owed = owed.reasons.isEmpty ? nil : owed
        await save()
        log.write("\(before - owed.reasons.count) owed record(s) settled, \(owed.reasons.count) still owed")
    }

    /// Asks iCloud for the owed records by name (a plain fetch of records, assets with them) and delivers those that
    /// can be read now as fetched. One iCloud no longer holds is crossed off: its removal for good comes with the
    /// zone's changes. Called at the end of a fetch that reached iCloud, so at each start too (the launch's sync
    /// fetches first). Nothing here loops: the next try is the next fetch.
    /// Tells the brain, just before a fetch's end, which records are still owed (brief 160): it then keeps a deletion
    /// of its own that has no base for such a key, which the whole fetch would otherwise drop.
    private func tellOwed() async {
        let keys = CloudKitTransportRules.owedKeys(stored.owedRecords)
        guard !keys.isEmpty else { return }
        await deliver(.owed(keys))
    }

    private func retryOwed() async {
        let names = stored.owedRecords.reasons.keys.sorted()
        guard !names.isEmpty, stored.account != nil else { return }
        let ids = names.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            results = try await database.records(for: ids)
        } catch {
            log.write("owed records could not be asked for: \(CloudKitTransportRules.words(for: error))")
            return
        }
        var readable: [CloudRecord] = []
        var settled: [String] = []
        for id in ids {
            switch results[id] {
            case .success(let record)?:
                do {
                    readable.append(try CloudRecordCodec.cloudRecord(from: record))
                    settled.append(id.recordName)
                } catch {
                    owe(id.recordName, why: CloudKitTransportRules.owedReason(error) ?? "\(error)")
                }
            case .failure(let error)?:
                if (error as? CKError)?.code == .unknownItem {
                    log.write("\(id.recordName): no longer in iCloud; no longer owed")
                    settled.append(id.recordName)
                } else {
                    log.write("\(id.recordName): still owed, \(CloudKitTransportRules.words(for: error))")
                }
            case nil:
                break
            }
        }
        await saveIfOwedChanged()
        if readable.isEmpty {
            await settleOwed(settled)
        } else if await deliver(.fetched(changed: readable, removed: [])) {
            await settleOwed(settled)
        }
    }

    // MARK: - The zone

    private func zoneExists() async {
        guard !stored.zoneReady else { return }
        stored.zoneReady = true
        await save()
    }

    /// A fetch is known to have reached iCloud since this state began (`StoredState.fetchedWhole`).
    private func wholeFetchSeen() async {
        guard stored.fetchedWhole != true else { return }
        stored.fetchedWhole = true
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
        stored.fetchedWhole = false
        // Nothing is owed from a zone that is gone: whatever a new one holds comes with its first fetch.
        stored.owed = nil
        await save()
        log.write("zone lost (\(loss.rawValue)) from \(why)")
        await deliver(.zoneLost(loss))
    }

    // MARK: - Delivery and state

    private func isCurrent(_ syncEngine: CKSyncEngine) -> Bool { syncEngine === engine && !stopped }

    /// Whether the brain handled it (not after `stop()`).
    @discardableResult
    private func deliver(_ event: TransportEvent) async -> Bool {
        await acquireDelivery()
        defer { releaseDelivery() }
        guard !stopped, let delegate else { return false }
        await delegate.handle(event)
        return true
    }

    /// An account change the brain has not handled yet (`StoredState.owedAccount`): told now, before anything else,
    /// and crossed off once handled. Called when the engine announces one, and before the first event, fetch or send
    /// after a launch that found one still owed.
    private func tellOwedAccount() async {
        guard let owed = stored.owedAccount else { return }
        guard let change = owed.change else {
            stored.owedAccount = nil
            await save()
            return
        }
        if await deliver(.account(change)) {
            // Only if it is still the one told: a newer change may have replaced it while the brain was handling this.
            if stored.owedAccount == owed {
                stored.owedAccount = nil
                await save()
            }
        }
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

    /// Waits for the engine's next `stateUpdate`, at most `stateFlushWait` seconds (a deadline for one thing that
    /// is pending, not a poll).
    private func waitForState() async {
        let started = Date()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // A list: two `stop()` calls may overlap, and each must be let go (the review's finding 16d).
            stateWaiters.append(continuation)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.stateFlushWait * 1_000_000_000))
                await self?.stateWaitEnded()
            }
        }
        let waited = Int(Date().timeIntervalSince(started) * 1000)
        let how = stateBehind ? "was not handed over in time" : "was written"
        log.write("stop: the state \(how) (\(waited) ms)")
    }

    private func stateWaitEnded() {
        let waiting = stateWaiters
        stateWaiters = []
        for waiter in waiting { waiter.resume() }
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
/// (so an engine that announces the same account again, its state not yet saved, is not told as a change).
/// JSON, versioned.
/// An `AccountChange` as the transport's state keeps it (the contract's type is not `Codable`).
struct StoredAccountChange: Codable, Equatable {
    var kind: String
    var previous: String?
    var current: String?

    init(_ change: AccountChange) {
        switch change {
        case .signedIn(let current):
            kind = "signedIn"; self.current = current
        case .signedOut(let previous):
            kind = "signedOut"; self.previous = previous
        case .switched(let previous, let current):
            kind = "switched"; self.previous = previous; self.current = current
        }
    }

    var change: AccountChange? {
        switch kind {
        case "signedIn": return current.map { .signedIn(current: $0) }
        case "signedOut": return previous.map { .signedOut(previous: $0) }
        case "switched":
            guard let previous, let current else { return nil }
            return .switched(previous: previous, current: current)
        default: return nil
        }
    }
}

struct StoredState: Codable {
    var version = 1
    var engine: CKSyncEngine.State.Serialization?
    var zoneReady = false
    var account: String?
    /// Whether a fetch is known to have reached iCloud since this state began (nil in a state saved before the
    /// field existed: not known). Until one has, a scheduled fetch that ended without a sign of the zone is not told
    /// to the brain as a fetch that ended well: the brain takes a fetch that ended well with no bookmark for the
    /// whole of what iCloud holds (the review's finding 3).
    var fetchedWhole: Bool?
    /// An account change the engine announced that the brain has not handled yet (nil: none owed).
    var owedAccount: StoredAccountChange?
    /// Records fetched that this build could not read, asked for again by name at each fetch until they can be
    /// (16c; nil: none, and in a state saved before the field existed).
    var owed: OwedRecords?
    /// Whether this device has saved the engine's push subscription for the account (`CloudKitTransport
    /// .ensureSubscription`; nil: not yet, and in a state saved before the field existed).
    var subscribed: Bool?

    var owedRecords: OwedRecords { owed ?? OwedRecords() }

    init(engine: CKSyncEngine.State.Serialization? = nil, zoneReady: Bool = false, account: String? = nil) {
        self.engine = engine
        self.zoneReady = zoneReady
        self.account = account
    }

    /// What `reset()` keeps (T13): the account this state belongs to, whether the zone was known to exist, and the
    /// records still owed (the whole fetch that follows brings them again anyway). The engine's own state (its
    /// bookmark and its list) and the proof of a whole fetch go.
    func afterReset() -> StoredState {
        var kept = StoredState(engine: nil, zoneReady: zoneReady, account: account)
        kept.owedAccount = owedAccount
        kept.owed = owed
        kept.subscribed = subscribed
        return kept
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

/// Records of ours iCloud holds that this build fetched and could not read (16c): by record name, why. Kept in the
/// transport's state, so they are still owed after a relaunch; written down before the bookmark moves past them.
struct OwedRecords: Codable, Equatable, Sendable {
    var reasons: [String: String] = [:]

    var isEmpty: Bool { reasons.isEmpty }

    /// For the fetch's words: how many, the first one's name (as the brain names it) and why.
    var words: String? {
        guard let first = reasons.keys.sorted().first, let why = reasons[first] else { return nil }
        let name = CloudRecordCodec.key(forRecordName: first).map(String.init(describing:)) ?? first
        let count = reasons.count
        let head = count == 1 ? "1 record in iCloud could not be read here"
                              : "\(count) records in iCloud could not be read here, the first"
        return "\(head): \(name) (\(why)); asked for again at each fetch"
    }
}

// MARK: - Decisions

/// One CloudKit error, as the decisions need it.
struct CloudFailure: Error, Equatable, Sendable {
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
    /// send was stopped (`stop()`, `reset()`, the system). `internalError`: CloudKit's own fault, not the record's.
    /// `assetFileNotFound`, `assetFileModified`: the file an asset was sent from went or changed while the send was
    /// on its way (`AssetFiles`); the record is made again, with a new file, when it is sent again (brief 160).
    static let retriedByTransport: Set<CKError.Code> = [.serverResponseLost, .batchRequestFailed, .operationCancelled,
                                                        .internalError, .assetFileNotFound, .assetFileModified]

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

    /// `zoneKnown`: whether this device knew the zone to exist before this batch came back. A zone it knew, missing:
    /// the zone was deleted (T11), and the brain must hear it, or iCloud would end with only the records of the next
    /// send while the ledger still says it holds the rest (the review's finding 4). A zone it never knew: not made
    /// yet, made now.
    static func saveOutcome(_ failure: CloudFailure, batchSize: Int, zoneRefusal: CloudFailure? = nil,
                            zoneKnown: Bool = false) -> SaveOutcome {
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
            return zoneKnown ? .zoneLost(.deleted) : .remakeZone
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

    /// What iCloud says about the build, the environment or the account rather than the record (brief 160, review 148
    /// finding 1): Production refuses a record type or field its schema lacks with `invalidArguments`, record by
    /// record; the container, an entitlement, a permission, the account's restrictions or a version say the same of
    /// every record. Never a refusal for good: the brain holds (`SyncHold.iCloudNotReady`) with everything waiting.
    static let notReadyCodes: Set<CKError.Code> = [
        .invalidArguments, .serverRejectedRequest, .permissionFailure, .badContainer, .missingEntitlement,
        .managedAccountRestricted, .incompatibleVersion, .badDatabase,
    ]

    /// T9's three: iCloud full, too large, anything else said no to for good; and T9a, iCloud not ready for this
    /// build or account.
    static func refusal(_ failure: CloudFailure) -> SendFailure {
        if notReadyCodes.contains(failure.code) { return .notReady(code: failure.code.rawValue, message: failure.message) }
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
        /// iCloud's change token for the zone has expired (16e): forget the bookmark and fetch everything.
        case tokenExpired
    }

    /// How a fetch the engine scheduled itself is told to the brain when it ends (`didFetchChanges` carries no
    /// error of its own). Trouble fetching the zone: its words. Otherwise it ended well if it showed a sign of the
    /// zone (its fetch ended, or it is not made yet), or if a fetch has reached iCloud before under this state (then
    /// one that did not get through changes nothing: the bookmark has not moved). With neither, nothing says this
    /// fetch reached iCloud, and the brain must not take it for the whole of what iCloud holds.
    static func scheduledFetchEnding(trouble: String?, reachedZone: Bool, wholeFetchSeen: Bool) -> String? {
        if let trouble { return trouble }
        if reachedZone || wholeFetchSeen { return nil }
        return notReached
    }

    static let notReached = "the fetch ended before it reached iCloud"

    /// The words a fetch ends with: its own trouble if any; else, while records are owed (16c), what is owed, so the
    /// bolt is not filled and Settings → iCloud says so. Not on the first fetch under a state (`wholeFetchSeenBefore`
    /// false): the brain takes a fetch that ended with words as one that did not end, and before its first whole
    /// fetch it sends nothing at all, so one record that can never be read (an asset over the limit) would stop every
    /// other from going. Owed words from the second fetch on keep only what the brain does after a fetch that ended
    /// well, and are cleared by the first fetch that ends with nothing owed.
    static func fetchEnding(_ words: String?, owed: OwedRecords, wholeFetchSeenBefore: Bool) -> String? {
        if let words { return words }
        return wholeFetchSeenBefore ? owed.words : nil
    }

    /// Why a record of ours could not be read, so it is owed (16c); nil when it is not ours at all (a record the
    /// mirror wrote, an unprefixed type): those are ignored, never owed.
    /// The keys of the records still owed, as the brain names them (`TransportEvent.owed`), in order.
    static func owedKeys(_ owed: OwedRecords) -> [SyncKey] {
        owed.reasons.keys.sorted().compactMap { CloudRecordCodec.key(forRecordName: $0) }
    }

    static func owedReason(_ error: Error) -> String? {
        if case CloudRecordCodec.DecodeProblem.notOurs = error { return nil }
        return "\(error)"
    }

    /// Whether a fetch the app asked for (`fetch()`) proves that iCloud was reached: it did not throw, the zone's
    /// fetch had no trouble, the engine really ended a fetch during the call, and someone is signed in.
    static func provesWholeFetch(threw: Bool, trouble: String?, engineEndedAFetch: Bool, account: String?) -> Bool {
        !threw && trouble == nil && engineEndedAFetch && account != nil
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
        case .changeTokenExpired:
            return .tokenExpired
        default:
            return .trouble(words(failure))
        }
    }

    /// Whether an error thrown by `fetchChanges` is an expired change token (the database's, or the zone's).
    static func isTokenExpired(_ error: Error) -> Bool {
        (error as? CKError)?.code == .changeTokenExpired
    }

    /// Whether to forget the bookmark and fetch again: an expired token, in the first round of a fetch only. The
    /// whole fetch that follows starts with no token, so it cannot expire; if iCloud says so anyway it is told as
    /// trouble and the next fetch (a push, the app coming forward) tries once more. Never a loop.
    static func refetchesAfterExpiredToken(expired: Bool, round: Int) -> Bool {
        expired && round == 0
    }

    static func zoneLoss(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) -> ZoneLoss {
        switch reason {
        case .deleted: return .deleted
        case .purged: return .purged
        case .encryptedDataReset: return .encryptedDataReset
        @unknown default: return .deleted
        }
    }

    /// T12: the change, by user record names; nil when the engine reports signing in to the account the transport's
    /// own saved state already belongs to (a launch that ended between the account event and the engine's first
    /// saved state), which is no change at all. After `reset()` or a lost state nothing is known, so the sign-in is
    /// told, and the brain reads a sign-in to its own account as no change (T12).
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
        case .managedAccountRestricted: return "managedAccountRestricted"
        case .incompatibleVersion: return "incompatibleVersion"
        case .badDatabase: return "badDatabase"
        case .internalError: return "internalError"
        case .assetFileModified: return "assetFileModified"
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
