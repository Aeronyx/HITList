import Foundation
import CloudKit
import OSLog

/// What the private database said about the Core Data zone since a database change token.
struct ICloudDatabaseAnswer: Equatable, Sendable {
    /// The zone's records changed (or it was created) since the token.
    var zoneChanged = false
    /// The zone was deleted or purged (iCloud data deleted in Settings, or a reset of encrypted data).
    var zoneDeleted = false
    /// The new archived token.
    var token: Data?
}

/// What the beats and the audit ask iCloud (brief 95), behind a protocol so the tests answer instead. Every call needs
/// the account and the network; none writes anything to iCloud.
protocol ICloudZoneReading: Sendable {
    /// Whether the Core Data zone changed since `token` (the private database's; nil: never asked). One small request:
    /// the beat.
    func zoneChanged(since token: Data?, timeout: TimeInterval) async -> Result<ICloudDatabaseAnswer, SyncBeatFailure>
    /// The zone's records changed or deleted since `token` (nil: every record), keeping only what the index holds.
    /// `progress` hears the running count of records read.
    func zoneChanges(since token: Data?, timeout: TimeInterval,
                     progress: @escaping @Sendable (Int) -> Void) async -> Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure>
    /// The names of `recordNames` (`CD_title`, `CD_name` or `CD_displayName`), for the audit's lists, on the device only.
    func names(of recordNames: [String], timeout: TimeInterval) async -> Result<[String: String], SyncBeatFailure>
}

/// The live reader: CloudKit operations on the tasks container's private database, at the user's priority, each with
/// a timeout of its own and a race against it (a CloudKit call that hangs, offline or with `cloudd` stuck, doesn't stop
/// when cancelled; `ICloudCheck` learned it first).
struct ICloudZoneReader: ICloudZoneReading {
    var containerID: String = HITListSchema.cloudKitContainerID

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: ICloudCheck.mirrorZoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// The fields the index keeps; every other field (titles, notes, pictures) stays in iCloud.
    static let indexKeys: [CKRecord.FieldKey] = ["CD_entityName", "CD_id", "CD_updatedAt"]
    /// The fields that name a record, for the audit's lists.
    static let nameKeys: [CKRecord.FieldKey] = ["CD_title", "CD_name", "CD_displayName"]

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    private var database: CKDatabase { CKContainer(identifier: containerID).privateCloudDatabase }

    private static func configuration(timeout: TimeInterval) -> CKOperation.Configuration {
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 2
        configuration.isLongLived = false
        configuration.qualityOfService = .userInitiated
        return configuration
    }

    // MARK: The beat

    func zoneChanged(since token: Data?, timeout: TimeInterval) async -> Result<ICloudDatabaseAnswer, SyncBeatFailure> {
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: Self.token(from: token))
        operation.fetchAllChanges = true
        operation.configuration = Self.configuration(timeout: timeout)
        let box = Box(ICloudDatabaseAnswer())
        let zoneName = ICloudCheck.mirrorZoneName
        operation.recordZoneWithIDChangedBlock = { id in
            if id.zoneName == zoneName { box.update { $0.zoneChanged = true } }
        }
        operation.recordZoneWithIDWasDeletedBlock = { id in
            if id.zoneName == zoneName { box.update { $0.zoneDeleted = true } }
        }
        operation.recordZoneWithIDWasPurgedBlock = { id in
            if id.zoneName == zoneName { box.update { $0.zoneDeleted = true } }
        }
        operation.changeTokenUpdatedBlock = { token in box.update { $0.token = Self.data(from: token) } }
        return await Self.race(operation, in: database, timeout: timeout) { finish in
            operation.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let (token, _)):
                    box.update { $0.token = Self.data(from: token) }
                    finish(.success(box.value))
                case .failure(let error):
                    finish(.failure(Self.failure(for: error)))
                }
            }
        }
    }

    // MARK: The zone

    func zoneChanges(since token: Data?, timeout: TimeInterval,
                     progress: @escaping @Sendable (Int) -> Void) async -> Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure> {
        let first = await fetchZone(since: token, timeout: timeout, progress: progress)
        // A token iCloud no longer knows (`changeTokenExpired`): read the whole zone instead, once.
        if case .failure(let failure) = first, failure.reason == Self.expiredTokenReason, token != nil {
            Self.log.notice("iCloud index: the zone's change token expired; reading every record again")
            return await fetchZone(since: nil, timeout: timeout, progress: progress)
        }
        return first
    }

    private func fetchZone(since token: Data?, timeout: TimeInterval,
                           progress: @escaping @Sendable (Int) -> Void) async -> Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure> {
        let zoneID = Self.zoneID
        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = Self.token(from: token)
        options.desiredKeys = Self.indexKeys
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: options])
        operation.fetchAllChanges = true
        operation.configuration = Self.configuration(timeout: timeout)
        let box = Box(ICloudZoneIndex.ZoneChanges(isFullRead: token == nil))
        let counter = Box(0)
        operation.recordWasChangedBlock = { recordID, result in
            guard case .success(let record) = result else { return }
            let entry = Self.entry(for: record)
            box.update { $0.changed[recordID.recordName] = entry }
            let count = counter.update { (value: inout Int) -> Int in
                value += 1
                return value
            }
            if count % 200 == 0 { progress(count) }
        }
        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            box.update {
                $0.changed[recordID.recordName] = nil
                $0.deleted.append(recordID.recordName)
            }
        }
        operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            box.update { $0.token = Self.data(from: token) }
        }
        let zoneFailure = Box<SyncBeatFailure?>(nil)
        operation.recordZoneFetchResultBlock = { _, result in
            switch result {
            case .success(let (token, _, _)):
                box.update { $0.token = Self.data(from: token) }
            case .failure(let error):
                if Self.isMissingZone(error) {
                    box.update { $0.zoneMissing = true }
                } else {
                    zoneFailure.update { $0 = Self.failure(for: error) }
                }
            }
        }
        let result: Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure> = await Self.race(operation, in: database, timeout: timeout) { finish in
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    if let failure = zoneFailure.value { finish(.failure(failure)) } else { finish(.success(box.value)) }
                case .failure(let error):
                    if Self.isMissingZone(error) {
                        var changes = box.value
                        changes.zoneMissing = true
                        finish(.success(changes))
                    } else {
                        finish(.failure(zoneFailure.value ?? Self.failure(for: error)))
                    }
                }
            }
        }
        if case .success = result { progress(counter.value) }
        // Cut short with records and a token to go on from (a large zone on a slow network): keep what came, so the next
        // beat goes on from there rather than starting over.
        if case .failure = result {
            var partial = box.value
            if let reached = partial.token, reached != token, !partial.changed.isEmpty || !partial.deleted.isEmpty {
                partial.token = reached
                partial.reachedEnd = false
                return .success(partial)
            }
        }
        return result
    }

    // MARK: Names, for the audit

    func names(of recordNames: [String], timeout: TimeInterval) async -> Result<[String: String], SyncBeatFailure> {
        guard !recordNames.isEmpty else { return .success([:]) }
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: Self.zoneID) }
        let operation = CKFetchRecordsOperation(recordIDs: ids)
        operation.desiredKeys = Self.nameKeys
        operation.configuration = Self.configuration(timeout: timeout)
        let box = Box([String: String]())
        operation.perRecordResultBlock = { recordID, result in
            guard case .success(let record) = result else { return }
            let name = Self.nameKeys.lazy.compactMap { record[$0] as? String }.first { !$0.isEmpty }
            if let name { box.update { $0[recordID.recordName] = name } }
        }
        return await Self.race(operation, in: database, timeout: timeout) { finish in
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success: finish(.success(box.value))
                case .failure(let error):
                    // Some records missing is still an answer: the ones found are named.
                    if (error as? CKError)?.code == .partialFailure { finish(.success(box.value)) } else {
                        finish(.failure(Self.failure(for: error)))
                    }
                }
            }
        }
    }

    // MARK: Records

    /// What the index keeps of one record.
    static func entry(for record: CKRecord) -> ICloudZoneIndex.Entry {
        let type = record.recordType
        let named = record["CD_entityName"] as? String
        let entity = named ?? (type.hasPrefix("CD_") ? String(type.dropFirst(3)) : type)
        return ICloudZoneIndex.Entry(type: type, entity: entity, id: uuid(record["CD_id"]),
                                     updatedAt: record["CD_updatedAt"] as? Date, modifiedAt: record.modificationDate)
    }

    /// Core Data writes a UUID attribute as a string (Apple, "Reading CloudKit Records for Core Data").
    static func uuid(_ value: Any?) -> UUID? {
        if let text = value as? String { return UUID(uuidString: text) }
        if let uuid = value as? UUID { return uuid }
        return nil
    }

    // MARK: Errors

    static let expiredTokenReason = "change token expired"

    static func isMissingZone(_ error: Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }
        return code == .zoneNotFound || code == .userDeletedZone
    }

    /// How a CloudKit error reads to the bolt (`SyncBeatFailure.Kind`) and in a few words.
    static func failure(for error: Error) -> SyncBeatFailure {
        let reason = SyncState.shortReason(for: error)
        guard let ckError = error as? CKError else { return SyncBeatFailure(.other, reason) }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return SyncBeatFailure(.network, reason)
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return SyncBeatFailure(.account, reason)
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return SyncBeatFailure(.busy, reason, retryAfter: ckError.retryAfterSeconds)
        case .changeTokenExpired:
            return SyncBeatFailure(.other, expiredTokenReason)
        case .operationCancelled:
            return SyncBeatFailure(.timeout, "cancelled")
        default:
            return SyncBeatFailure(.other, reason, retryAfter: ckError.retryAfterSeconds)
        }
    }

    // MARK: Plumbing

    static func data(from token: CKServerChangeToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func token(from data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    /// Adds `operation` to `database` and returns its outcome, or a timeout once `timeout` plus a little has passed
    /// without one (the operation is then cancelled). `install` sets the operation's final block, which calls `finish`.
    private static func race<T: Sendable>(_ operation: CKDatabaseOperation, in database: CKDatabase, timeout: TimeInterval,
                                          install: (@escaping @Sendable (Result<T, SyncBeatFailure>) -> Void) -> Void) async -> Result<T, SyncBeatFailure> {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            install { once.resume($0) }
            database.add(operation)
            let limit = timeout + 3
            Task {
                try? await Task.sleep(for: .seconds(limit))
                if once.resume(.failure(.timedOut(after: timeout))) { operation.cancel() }
            }
        }
    }

    /// A value shared with CloudKit's callbacks, which arrive on its own queues.
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value

        init(_ value: Value) { stored = value }

        var value: Value {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        @discardableResult
        func update<R>(_ change: (inout Value) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return change(&stored)
        }
    }

    /// Resumes a continuation with the first value only; says whether this call was the one.
    private final class Once<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?

        init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }

        @discardableResult
        func resume(_ value: T) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
            return pending != nil
        }
    }
}
