import Foundation

// The engine's road to iCloud, as the brain (`SyncCore`) sees it: one zone of records, changes to send, changes
// fetched. Two things implement it: `CloudKitTransport` in the app (on Apple's `CKSyncEngine`) and `FakeCloud`'s
// devices (a pretend iCloud in memory, for tests). The rules both keep are in `dev/SYNC-ENGINE.md`, "The transport's
// rules" (T1 to T14); a test that passes on the fake must mean the same on CloudKit.

/// A record as iCloud holds it: its fields (every one the transport could read, known to this build or not) and
/// iCloud's own token for this version of it.
public struct CloudRecord: Hashable, Sendable, Codable {
    public var record: SyncRecord
    /// Opaque: what iCloud needs back to accept a change to this version of the record (CloudKit: the record's
    /// encoded system fields, its change tag among them). Kept in the ledger, sent back with the next change.
    public var system: Data

    public init(record: SyncRecord, system: Data) {
        self.record = record
        self.system = system
    }

    public var key: SyncKey { record.key }
}

/// A record on its way to iCloud: its fields now, and the token iCloud gave for the version this device last saw
/// (nil: iCloud has never held it, as far as this device knows).
public struct OutgoingRecord: Hashable, Sendable {
    public var record: SyncRecord
    public var system: Data?

    public init(record: SyncRecord, system: Data?) {
        self.record = record
        self.system = system
    }
}

/// A change waiting to go to iCloud. The transport keeps the list across launches and takes a change off it when
/// iCloud has accepted it (T3, T4).
public enum PendingChange: Hashable, Sendable, Codable {
    /// Send the record as it is when its turn comes (`SyncTransportDelegate.recordToSend`): an item made or changed
    /// here, or the marker of one deleted here.
    case save(SyncKey)
    /// Remove the record from iCloud for good: a marker past its lifetime.
    case delete(SyncKey)

    public var key: SyncKey {
        switch self {
        case .save(let key), .delete(let key): return key
        }
    }
}

/// The iCloud account under the app changed. Accounts are named by an opaque id (CloudKit: the user record's name).
public enum AccountChange: Hashable, Sendable {
    case signedIn(current: String)
    case signedOut(previous: String)
    case switched(previous: String, current: String)
}

/// The zone is gone from iCloud, and why.
public enum ZoneLoss: String, Hashable, Sendable, Codable {
    /// Removed by the app or the developer (never by a release build of HITList; the CloudKit dashboard in testing).
    case deleted
    /// The person removed HITList's data in iCloud's storage settings: they want it gone.
    case purged
    /// The person reset their encrypted data during account recovery: the data here is still wanted.
    case encryptedDataReset
}

/// Why iCloud refused one change.
public enum SendFailure: Hashable, Sendable {
    /// iCloud holds a version this device had not seen (or holds the record when this device thought it new):
    /// `server` is that version. Settle the two and send again (T6).
    case conflict(server: CloudRecord)
    /// The change was to a record iCloud does not hold (T7).
    case unknownItem
    /// The person's iCloud storage is full (T9).
    case quotaExceeded
    /// The record is larger than iCloud takes (T9).
    case tooLarge
    /// Anything else iCloud says no to for good, with its code and words, for the log (T9).
    case rejected(code: Int, message: String)
}

/// What a transport tells the brain. One at a time, in order (T1).
public enum TransportEvent: Sendable {
    /// T12.
    case account(AccountChange)
    /// A fetch begins; `fetched` and `zoneLost` events follow, then `didFetch`.
    case willFetch
    /// Records iCloud holds that are new or changed since the last fetch this device finished (T2), and records
    /// that are no longer there at all (removed for good, T8).
    case fetched(changed: [CloudRecord], removed: [SyncKey])
    /// T11.
    case zoneLost(ZoneLoss)
    /// The fetch ended: everything up to now has been delivered (`error` nil), or it stopped early and will be
    /// tried again (`error`: its words, for the log and the status line). `CloudKitTransport` also gives words, from
    /// the second fetch under its state on, while a record it could not read is still owed (brief 149).
    case didFetch(error: String?)
    case willSend
    /// One batch came back (T3 to T9): `saved` as iCloud now holds them, `removed` for good, and the changes
    /// refused. A change that is neither here nor refused is still pending (the network dropped: T5). Every change
    /// named here has left the pending list before the event is delivered, so one the delegate adds back while
    /// handling it stays.
    case sent(saved: [CloudRecord], removed: [SyncKey], failed: [SyncKey: SendFailure])
    case didSend(error: String?)
}

public protocol SyncTransportDelegate: AnyObject, Sendable {
    /// T1: the next event waits until this returns, and whatever the event brought must be kept on disk before it
    /// does: the transport then moves its bookmark past it and will not bring it again. Never call `fetch()` or
    /// `send()` from inside it.
    func handle(_ event: TransportEvent) async

    /// The record to send for a pending save, as it is now (T3). Nil when there is nothing to send for it after all:
    /// the transport drops the pending change.
    func recordToSend(_ key: SyncKey) async -> OutgoingRecord?
}

/// The road to iCloud. The transport owns: the zone (it makes it when it is missing), the bookmark of what has been
/// fetched, the list of pending changes, retries after the network or iCloud's limits, and waking on a push.
public protocol SyncTransport: AnyObject, Sendable {
    /// Begins: restores its bookmark and its pending list (`SyncTransportState`), and from now on delivers events
    /// to `delegate` (kept strongly until `stop()`). An account that changed while the app was not running is the
    /// first event.
    func start(delegate: any SyncTransportDelegate) async

    /// Ends: no event after it returns.
    func stop() async

    /// The changes waiting to go, in the order they were added (T3).
    func pending() async -> [PendingChange]

    /// Adds changes to send. A save and a delete of the same record replace each other: the last added stays
    /// (T3). Adding one that is already there changes nothing. Sending is scheduled by the transport itself.
    func add(_ changes: [PendingChange]) async

    /// Takes changes off the list unsent.
    func remove(_ changes: [PendingChange]) async

    /// Fetches now. Returns when every event of the fetch has been handled; throws when it could not be done
    /// (the events say what did arrive).
    func fetch() async throws

    /// Sends everything pending now. Returns when every event of the send has been handled.
    func send() async throws

    /// Forgets the bookmark and the pending list: the next fetch brings every record in the zone (T13). For a
    /// ledger that was reset.
    func reset() async
}

/// Where a transport keeps its own state between launches (CloudKit: `CKSyncEngine.State.Serialization`, encoded).
/// The ledger provides it, so the bookmark is forgotten with the ledger and never outlives it (T13).
public protocol SyncTransportState: Sendable {
    func loadTransportState() async -> Data?
    func saveTransportState(_ state: Data?) async
}
