import Foundation
import CloudKit
import OSLog

/// Keeps `SharedTasksStore` and the shared container in step (brief 51): two `CKSyncEngine`s, one on the private
/// database (lists I made) and one on the shared database (lists I joined), each with its state kept in the store's
/// file. Local edits arrive as `SharedTasksStore.Change`s and become the engines' pending changes; the engines fetch
/// and send on their own schedule (pushes, launches, the app becoming active), and every event lands back in the
/// store on the main actor.
///
/// Nothing here posts or observes what `CloudSyncMonitor` watches: no `NSPersistentCloudKitContainer`, no
/// `ModelContext`, and this container's pushes are routed here by `SharedTasksPush`.
final class SharedTasksSync: CKSyncEngineDelegate, @unchecked Sendable {
    let container: CKContainer
    /// Main actor only.
    private let store: SharedTasksStore
    /// Made once in `init`, never changed: read from any thread.
    private var engines: [SharedListScope: CKSyncEngine] = [:]
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sharing")

    /// Main actor: whether an engine is fetching or sending, for the Shared screen's "Syncing…".
    @MainActor var onActivity: ((Bool) -> Void)?
    /// Main actor: a failure worth a line on the Shared screen (nil clears it).
    @MainActor var onProblem: ((String?) -> Void)?
    @MainActor private var busy: Set<String> = []

    @MainActor
    init(container: CKContainer, store: SharedTasksStore) {
        self.container = container
        self.store = store
        for scope in SharedListScope.allCases {
            let database = scope == .owned ? container.privateCloudDatabase : container.sharedCloudDatabase
            let saved = store.engineState(for: scope).flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
            engines[scope] = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self))
        }
        store.onChanges = { [weak self] changes in self?.queue(changes) }
    }

    func engine(_ scope: SharedListScope) -> CKSyncEngine { engines[scope]! }

    /// Stops both engines (the preview switched off). Pending changes stay in the store's file for next time.
    @MainActor
    func shutDown() async {
        store.onChanges = nil
        for engine in engines.values { await engine.cancelOperations() }
    }

    // MARK: - Fetching and sending now

    /// Both engines fetch now (a push, the Shared screen appearing, pull to refresh).
    func fetchNow() async {
        for scope in SharedListScope.allCases {
            do {
                try await engine(scope).fetchChanges()
            } catch {
                await report(error, doing: "fetch")
            }
        }
    }

    func sendNow() async {
        for scope in SharedListScope.allCases {
            do {
                try await engine(scope).sendChanges()
            } catch {
                await report(error, doing: "send")
            }
        }
    }

    // MARK: - Local changes

    @MainActor
    func queue(_ changes: [SharedTasksStore.Change]) {
        for change in changes {
            switch change {
            case .saveZone(let listID):
                let zoneID = SharedTasksRecords.zoneID(listID: listID, ownerName: CKCurrentUserDefaultName)
                engine(.owned).state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            case .deleteZone(let listID):
                let zoneID = SharedTasksRecords.zoneID(listID: listID, ownerName: CKCurrentUserDefaultName)
                forgetPendingChanges(in: zoneID, scope: .owned)
                engine(.owned).state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
            case .saveRecord(let ref):
                engine(ref.scope).state.add(pendingRecordZoneChanges: [.saveRecord(SharedTasksRecords.recordID(ref))])
            case .deleteRecord(let ref):
                let id = SharedTasksRecords.recordID(ref)
                engine(ref.scope).state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                engine(ref.scope).state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
            case .leave(let listID, let ownerName):
                // The share itself was deleted before the store let go of the list (`SharedTasksCenter.leave`).
                forgetPendingChanges(in: SharedTasksRecords.zoneID(listID: listID, ownerName: ownerName), scope: .joined)
            case .stopSharing, .removeParticipant:
                // Done on the server first (`SharedTasksCenter`); the member records they drop follow as deletes.
                break
            }
        }
    }

    @MainActor
    private func forgetPendingChanges(in zoneID: CKRecordZone.ID, scope: SharedListScope) {
        let state = engine(scope).state
        state.remove(pendingRecordZoneChanges: state.pendingRecordZoneChanges.filter { Self.zoneID(of: $0) == zoneID })
    }

    private static func zoneID(of change: CKSyncEngine.PendingRecordZoneChange) -> CKRecordZone.ID {
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): return id.zoneID
        @unknown default: return CKRecordZone.ID()
        }
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let scope: SharedListScope = syncEngine.database.databaseScope == .shared ? .joined : .owned
        switch event {
        case .stateUpdate(let update):
            let data = try? JSONEncoder().encode(update.stateSerialization)
            await MainActor.run { store.setEngineState(data, for: scope) }

        case .accountChange(let change):
            await MainActor.run { accountChanged(change.changeType) }

        case .fetchedDatabaseChanges(let changes):
            await MainActor.run {
                store.batch {
                    for modification in changes.modifications {
                        guard let listID = SharedTasksSchema.listID(fromZoneName: modification.zoneID.zoneName) else { continue }
                        store.ensureList(listID, scope: scope, ownerName: modification.zoneID.ownerName)
                    }
                    for deletion in changes.deletions {
                        guard let listID = SharedTasksSchema.listID(fromZoneName: deletion.zoneID.zoneName) else { continue }
                        Self.log.notice("Shared Tasks: a list's zone is gone from the \(scope == .owned ? "private" : "shared", privacy: .public) database (\(String(describing: deletion.reason), privacy: .public))")
                        store.applyDeletedZone(listID)
                    }
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            await MainActor.run {
                store.batch {
                    for modification in changes.modifications { apply(modification.record, scope: scope) }
                    for deletion in changes.deletions {
                        guard let listID = SharedTasksSchema.listID(fromZoneName: deletion.recordID.zoneID.zoneName) else { continue }
                        store.applyDeletedRecord(named: deletion.recordID.recordName, listID: listID)
                    }
                }
            }

        case .sentRecordZoneChanges(let sent):
            await MainActor.run { recordZoneChangesSent(sent, scope: scope) }

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                Self.log.error("Shared Tasks: couldn't create a list's zone: \(failure.error.localizedDescription, privacy: .public)")
            }
            for (zoneID, error) in sent.failedZoneDeletes where error.code != .zoneNotFound {
                Self.log.error("Shared Tasks: couldn't delete \(zoneID.zoneName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

        case .didFetchRecordZoneChanges(let done):
            guard let error = done.error else { break }
            if error.code == .zoneNotFound || error.code == .userDeletedZone,
               let listID = SharedTasksSchema.listID(fromZoneName: done.zoneID.zoneName) {
                await MainActor.run { store.applyDeletedZone(listID) }
            } else {
                await report(error, doing: "fetch a list")
            }

        case .willFetchChanges:
            await setBusy(true, "\(scope.rawValue).fetch")
        case .didFetchChanges:
            await setBusy(false, "\(scope.rawValue).fetch")
        case .willSendChanges:
            await setBusy(true, "\(scope.rawValue).send")
        case .didSendChanges:
            await setBusy(false, "\(scope.rawValue).send")
        case .willFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope: SharedListScope = syncEngine.database.databaseScope == .shared ? .joined : .owned
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            await self?.record(for: recordID, scope: scope)
        }
    }

    // MARK: - Applying events

    @MainActor
    private func record(for recordID: CKRecord.ID, scope: SharedListScope) -> CKRecord? {
        guard let listID = SharedTasksSchema.listID(fromZoneName: recordID.zoneID.zoneName) else { return nil }
        let ref = SharedTasksStore.RecordRef(listID: listID, scope: scope, ownerName: recordID.zoneID.ownerName, recordName: recordID.recordName)
        return store.value(for: ref).map(SharedTasksRecords.record(for:))
    }

    @MainActor
    private func apply(_ record: CKRecord, scope: SharedListScope) {
        let zoneID = record.recordID.zoneID
        guard let listID = SharedTasksSchema.listID(fromZoneName: zoneID.zoneName) else { return }
        let owner = zoneID.ownerName
        switch SharedTasksRecords.decode(record) {
        case .list(let fields, let systemFields):
            store.applyServerList(fields, systemFields: systemFields, listID: listID, scope: scope, ownerName: owner)
        case .task(let task):
            store.applyServerTask(task, listID: listID, scope: scope, ownerName: owner)
        case .member(let member):
            store.applyServerMember(member, listID: listID, scope: scope, ownerName: owner)
        case .share(let share):
            store.applyShare(SharedTasksRecords.shareInfo(from: share, me: store.me), listID: listID, scope: scope, ownerName: owner)
        case .other:
            break
        }
    }

    @MainActor
    private func recordZoneChangesSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, scope: SharedListScope) {
        store.batch {
            for record in sent.savedRecords {
                guard let listID = SharedTasksSchema.listID(fromZoneName: record.recordID.zoneID.zoneName) else { continue }
                store.applySaved(recordName: record.recordID.recordName, listID: listID, systemFields: SharedTasksRecords.systemFields(of: record))
            }
            for id in sent.deletedRecordIDs {
                guard let listID = SharedTasksSchema.listID(fromZoneName: id.zoneID.zoneName) else { continue }
                store.applyDeletionConfirmed(recordName: id.recordName, listID: listID)
            }
            for (id, error) in sent.failedRecordDeletes {
                guard let listID = SharedTasksSchema.listID(fromZoneName: id.zoneID.zoneName) else { continue }
                if error.code == .unknownItem || error.code == .zoneNotFound {
                    store.applyDeletionConfirmed(recordName: id.recordName, listID: listID)
                } else if !Self.isRetriedByEngine(error) {
                    Self.log.error("Shared Tasks: a delete failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            for failure in sent.failedRecordSaves { saveFailed(failure, scope: scope) }
        }
    }

    @MainActor
    private func saveFailed(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, scope: SharedListScope) {
        let id = failure.record.recordID
        guard let listID = SharedTasksSchema.listID(fromZoneName: id.zoneID.zoneName) else { return }
        switch failure.error.code {
        case .serverRecordChanged:
            // Someone saved first: merge per field and, if anything of ours is newer, save again on their change tag.
            if let server = failure.error.serverRecord { apply(server, scope: scope) }
        case .zoneNotFound:
            if scope == .owned {
                // The zone wasn't created yet (or was lost): create it, then this record again.
                engine(.owned).state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                engine(.owned).state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            } else {
                store.applyDeletedZone(listID)
            }
        case .unknownItem:
            store.applyMissingOnServer(recordName: id.recordName, listID: listID)
        case .batchRequestFailed:
            engine(scope).state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .permissionFailure:
            Self.log.error("Shared Tasks: not allowed to save \(id.recordName, privacy: .public) (removed from the list, or view only)")
            onProblem?("You can't change this list any more.")
        default:
            if !Self.isRetriedByEngine(failure.error) {
                Self.log.error("Shared Tasks: a save failed: \(failure.error.localizedDescription, privacy: .public)")
                onProblem?(SharedTasksSync.describe(failure.error))
            }
        }
    }

    @MainActor
    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case .signIn(let user):
            store.setMe(user.recordName)
        case .switchAccounts(_, let user):
            store.forgetAll()
            store.setMe(user.recordName)
        case .signOut:
            store.forgetAll()
        @unknown default:
            break
        }
    }

    // MARK: - Status

    @MainActor
    private func setBusy(_ on: Bool, _ key: String) {
        if on { busy.insert(key) } else { busy.remove(key) }
        onActivity?(!busy.isEmpty)
        if !on, busy.isEmpty { onProblem?(nil) }
    }

    @MainActor
    private func report(_ error: Error, doing what: String) {
        if let ck = error as? CKError, Self.isHandledPerRecord(ck) {
            // A conflict or a missing record: already resolved record by record in the engine's events.
            Self.log.notice("Shared Tasks: \(what, privacy: .public) finished with per-record results: \(error.localizedDescription, privacy: .public)")
            return
        }
        Self.log.error("Shared Tasks: couldn't \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        if let ck = error as? CKError, Self.isRetriedByEngine(ck) { return }
        onProblem?(Self.describe(error))
    }

    /// A send or fetch that "fails" only because some records did (a conflict merged and saved again, a record
    /// deleted elsewhere): `sentRecordZoneChanges` / `didFetchRecordZoneChanges` deal with each one.
    static func isHandledPerRecord(_ error: CKError) -> Bool {
        [.partialFailure, .serverRecordChanged, .batchRequestFailed, .unknownItem, .zoneNotFound, .userDeletedZone].contains(error.code)
    }

    /// Errors CKSyncEngine retries by itself: nothing to show beyond "Syncing…".
    static func isRetriedByEngine(_ error: CKError) -> Bool {
        [.networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .operationCancelled]
            .contains(error.code)
    }

    /// A short line for the Shared screen.
    static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated: return "Sign in to iCloud to use Shared Tasks."
        case .networkFailure, .networkUnavailable: return "No connection. Changes will sync when you're back online."
        case .quotaExceeded: return "The list's owner is out of iCloud storage."
        case .participantMayNeedVerification: return "Open the invitation link again to confirm it's you."
        case .permissionFailure: return "You can't change this list any more."
        default: return ck.localizedDescription
        }
    }
}
