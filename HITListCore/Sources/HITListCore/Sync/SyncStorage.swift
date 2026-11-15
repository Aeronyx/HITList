import Foundation

// What the brain (`SyncCore`) needs from the device: the items as they are saved (`SyncLocalStore`, in the app
// SwiftData's `SwiftDataSyncStore`) and its own memory of what iCloud holds (`SyncLedger`, in the app a small store
// of its own beside the data). `SyncMemory.swift` has both in memory, for tests.

// MARK: The device's items

/// One write to the device's items, made only if the item is still as the decision found it.
public struct LocalWrite: Hashable, Sendable {
    public var key: SyncKey
    /// What the device must hold for the write to go ahead: the record the decision was made on, or nil when the
    /// item must not exist here. Compared with `RecordMerge.same` (known fields, required ones filled in, data by
    /// digest, a set of references as a set), never field by field as written: a store that hands out a list in
    /// another order must not make every write stale. (A person may have changed the item between
    /// the read and the write: then nothing is written, the key comes back from `apply`, and the brain decides
    /// again on the newer record.)
    public var expected: SyncRecord?
    /// What the device holds afterwards; nil deletes the item.
    public var record: SyncRecord?

    public init(key: SyncKey, expected: SyncRecord?, record: SyncRecord?) {
        self.key = key
        self.expected = expected
        self.record = record
    }
}

public enum SyncStoreError: Error, Equatable {
    /// The device holds more than one item for a key (two rows with one `id`): they must be merged before the
    /// engine can run (`Deduplicator`).
    case duplicates([SyncKey])
}

/// The device's items, as records (`SyncSchema`).
public protocol SyncLocalStore: Sendable {
    /// Every item the device holds, as last saved: one record per item, with exactly the fields of its type
    /// (`SyncSchema.types`; required ones always present, empty ones absent), dates in whole milliseconds,
    /// references by record name and only to items that exist here. Throws `SyncStoreError.duplicates` when two
    /// rows share a key.
    func records() async throws -> [SyncRecord]

    /// The same, for some keys only; a key with no item is absent from the answer.
    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord]

    /// Makes the writes in one transaction, in an order that keeps references whole (a record after the ones it
    /// points at; deletions last), each only if its `expected` still holds (`RecordMerge.same`). A reference to an
    /// item that does not exist here is written as none. **A deletion removes exactly the rows the writes name**:
    /// when deleting a row would take others with it (a task's sub-tasks, by the store's own cascade) and the writes
    /// do not name every one of them as a deletion too, that write is stale and nothing is deleted for it (the
    /// brain names each row it means to delete, having settled each: `dev/SYNC-ENGINE.md` section 8). Returns the
    /// keys whose write did not go ahead: nothing was written for them.
    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey>

    /// The items deleted on this device, by a person or by the app on their behalf, that the brain has not taken
    /// note of yet (`forget(deletions:)`). **This is the only way the brain learns of a deletion here**: an item that
    /// is merely not on the device is never a deletion (`dev/SYNC-ENGINE.md` section 4), so a store that reads empty,
    /// loses a row or is put back from a copy can never delete anything in iCloud. The store writes a deletion down
    /// as it is saved (a task's sub-tasks that go with it too), and keeps it until the brain has; the engine's own
    /// deletions (`apply`) are never in it. A key in it whose item is here again is simply ignored.
    func deletions() async throws -> Set<SyncKey>

    /// The brain has written these down (`LedgerEntry.deletedHereAt`): they need not be told again.
    func forget(deletions: Set<SyncKey>) async throws
}

// MARK: The engine's memory

/// What the engine remembers about one record.
public struct LedgerEntry: Hashable, Sendable, Codable {
    public var key: SyncKey
    /// The record as iCloud held it when this device and iCloud last agreed on it: the fields this build knows,
    /// `data` as digests (`SyncRecord.comparable`); a marker when iCloud holds the item as deleted. Nil: they have
    /// never agreed (the item is new here and has not been accepted yet).
    public var base: SyncRecord?
    /// iCloud's token for the version `base` is (`CloudRecord.system`). Nil with a nil `base`.
    public var system: Data?
    /// The time of the marker this device still has to send: when the item was deleted here
    /// (`SyncLocalStore.deletions`) while `base` says iCloud holds it, or before the two ever agreed (no `base`: kept
    /// until a fetch shows whether iCloud holds the item). Nil when there is no marker to send, and cleared when
    /// the item is here again. Never set because an item is merely absent.
    public var deletedHereAt: Date?

    public init(key: SyncKey, base: SyncRecord? = nil, system: Data? = nil, deletedHereAt: Date? = nil) {
        self.key = key
        self.base = base
        self.system = system
        self.deletedHereAt = deletedHereAt
    }
}

/// One transaction on the ledger.
public struct LedgerWrite: Sendable {
    public var upsert: [LedgerEntry] = []
    public var remove: [SyncKey] = []
    /// Records waiting for an item they point at (`dev/SYNC-ENGINE.md` section 8), replaced by key: per record, its
    /// key and the reference fields it is waiting for (`system` is not used and may be empty).
    public var deferUpsert: [CloudRecord] = []
    public var deferRemove: [SyncKey] = []
    /// Named facts to set (a value) or forget (nil).
    public var facts: [String: Data?] = [:]

    public init() {}

    public var isEmpty: Bool {
        upsert.isEmpty && remove.isEmpty && deferUpsert.isEmpty && deferRemove.isEmpty && facts.isEmpty
    }
}

/// The engine's memory, kept on the device beside the items and never synced: for every record, what iCloud last
/// held (`LedgerEntry`); the references records are waiting for (`deferred`); and a few named facts (the account the
/// memory belongs to, whether the first fetch has finished, the transport's own state). Losing it loses nothing of
/// the person's: the engine then merges everything afresh (`dev/SYNC-ENGINE.md`, "A merge without a memory").
public protocol SyncLedger: SyncTransportState {
    func entries() async throws -> [LedgerEntry]
    func deferred() async throws -> [CloudRecord]
    func fact(_ name: String) async throws -> Data?
    /// All of `write` or none of it.
    func write(_ write: LedgerWrite) async throws
    /// Forgets everything: every entry, every deferred record, every fact (the transport's state among them).
    func reset() async throws
}

/// The names of the ledger's facts.
public enum LedgerFact {
    /// The iCloud account the memory belongs to (UTF-8 of `AccountChange`'s id).
    public static let account = "account"
    /// Present once the first whole fetch has finished: from then on an item here that iCloud lacks is new, not
    /// unknown.
    public static let firstFetchDone = "firstFetchDone"
    /// The transport's own state (`SyncTransportState`).
    public static let transport = "transport"
    /// Why the engine is waiting for the person, if it is (`SyncCore` defines the values).
    public static let hold = "hold"
}
