import Foundation

// What the engine is doing, for the bolt and Settings → iCloud (`dev/SYNC-ENGINE.md`, "Holds and the bolt").
// `SyncCore` publishes one of these each time it changes.

/// Why the engine is waiting for the person or the world instead of syncing. Each has its way out (`SyncCore`).
public enum SyncHold: Hashable, Sendable, Codable {
    /// Signed out of iCloud. Lifted by a sign-in (`AccountChange.signedIn`).
    case noAccount
    /// iCloud's format (`Meta/meta`) is newer than this build reads. Lifted by a build that reads it.
    case needsUpdate
    /// The person removed HITList's data in iCloud's settings. Lifted by `SyncCore.answer(_:)`.
    case zonePurged
    /// iCloud is full. What is waiting stays waiting; tried again on return to the app (`SyncCore.resume()`,
    /// `start()`, `syncNow()`, `localChanged(nil)`).
    case storageFull
    /// iCloud refused what was sent for a reason that is not the records' (`SendFailure.notReady`: a schema not yet
    /// deployed, the container, an entitlement, a permission, a version). Kept and lifted exactly as `storageFull`
    /// is: what is waiting stays waiting, tried again on return to the app and by "Try again", never by a timer.
    case iCloudNotReady
    /// Two rows on the device share a key. Lifted by `SyncCore.resume()` once the app has merged them.
    case duplicates([SyncKey])
    /// The device's items or the engine's memory could not be read or written: the words. Tried again at the next
    /// `start()` or `resume()`.
    case failed(String)

    /// Whether a fetched record is set aside unread while this hold lasts (and everything is fetched again when it
    /// lifts). Only a full iCloud still takes what arrives: reading is not what it refuses.
    var stopsFetching: Bool { !triedOnReturn }

    /// The holds iCloud's answer to a send puts the brain in (`storageFull`, `iCloudNotReady`): one path for both.
    /// The device is still compared and counted (nothing is added to the list), what arrives is still read, and the
    /// hold is lifted on return to the app (`SyncCore.localChanged(nil)`, `start()`, `syncNow()`, `resume()`).
    public var triedOnReturn: Bool {
        switch self {
        case .storageFull, .iCloudNotReady: return true
        default: return false
        }
    }

    /// Whether the hold is kept in the ledger across a relaunch. `duplicates` and `failed` are found again (or not)
    /// by the next start itself.
    var persists: Bool {
        switch self {
        case .noAccount, .needsUpdate, .zonePurged, .storageFull, .iCloudNotReady: return true
        case .duplicates, .failed: return false
        }
    }

    /// For the log and the status line.
    public var words: String {
        switch self {
        case .noAccount: return "Not signed in to iCloud"
        case .needsUpdate: return "Update HITList to sync"
        case .zonePurged: return "HITList's data was removed from iCloud"
        case .storageFull: return "iCloud is full"
        case .iCloudNotReady: return "iCloud isn't ready for this version of HITList"
        case .duplicates(let keys): return "\(keys.count) item\(keys.count == 1 ? "" : "s") on this device share an id"
        case .failed(let words): return words
        }
    }
}

/// The words of a `failed` hold, which a person reads after "Sync stopped:" (brief 160, review 147 F10): one fixed
/// sentence per way the brain can fail, never a Swift error and never "engine", "ledger" or "memory". The error itself
/// goes to the sync log, on the line that says the hold began.
public enum SyncFailureWords {
    /// The ledger (the engine's records beside the store) could not be written.
    public static let recordsNotSaved = "HITList couldn't save its sync records on this device."
    /// The ledger could not be read at a start.
    public static let recordsNotRead = "HITList couldn't read its sync records on this device."
    /// The store's items could not be read.
    public static let dataNotRead = "HITList couldn't read the data on this device."
    /// The store's items could not be read or written while something from iCloud was settled.
    public static let dataNotSaved = "HITList couldn't read or save the data on this device."
    /// A deletion the store wrote down could not be taken up.
    public static let deletionNotNoted = "HITList couldn't note a deletion made on this device."

    public static let all = [recordsNotSaved, recordsNotRead, dataNotRead, dataNotSaved, deletionNotNoted]
}

/// The engine's state for the bolt: what it is doing, how many changes wait, and whether everything is in iCloud.
public struct SyncStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Not started, or stopped.
        case off
        /// Reading its memory and starting the transport.
        case starting
        case idle
        case fetching
        case sending
        /// Waiting for the person or the world (`SyncHold`). A hold outranks fetching and sending.
        case held(SyncHold)
    }

    public var state: State
    /// Changes waiting to go to iCloud: items made, changed or deleted here that iCloud does not hold yet, markers
    /// past their lifetime to remove, the zone's `Meta/meta` when iCloud has none. Exact: the brain compares, it
    /// does not count events. Nothing is counted for an item that has never been to iCloud before the first fetch
    /// has finished (it may turn out to be there already).
    public var waiting: Int
    /// Whether a whole fetch has finished since the engine's memory began (`LedgerFact.firstFetchDone`).
    public var firstFetchDone: Bool
    /// When the last fetch that ended without an error ended.
    public var lastFetchEnded: Date?
    /// When iCloud last accepted a batch of this device's changes.
    public var lastSendEnded: Date?
    /// The words of the last thing that went wrong and has not been put right since: a fetch or a send that stopped
    /// early, or a backup that failed. (Refusals for good are `refusal`, apart, since 2026-11-15.)
    public var lastError: String?
    /// Records iCloud refused for good (too large, or rejected): kept out of the pending list until the item
    /// changes again, never retried in a loop.
    public var refused: [SyncKey]
    /// The words for the records iCloud refused for good (`refused`); nil when there are none. Kept apart from
    /// `lastError` (added beside, brief 145, at the status session's request): a refusal is not a passing error.
    public var refusal: String?

    public init(state: State = .off, waiting: Int = 0, firstFetchDone: Bool = false, lastFetchEnded: Date? = nil,
                lastSendEnded: Date? = nil, lastError: String? = nil, refused: [SyncKey] = [], refusal: String? = nil) {
        self.state = state
        self.waiting = waiting
        self.firstFetchDone = firstFetchDone
        self.lastFetchEnded = lastFetchEnded
        self.lastSendEnded = lastSendEnded
        self.lastError = lastError
        self.refused = refused
        self.refusal = refusal
    }

    /// The filled bolt, exactly as `dev/SYNC-ENGINE.md` section 10 defines it: idle, nothing waiting, the first
    /// fetch finished, no error; and nothing iCloud refused for good waiting on the person.
    public var isSynced: Bool {
        state == .idle && waiting == 0 && firstFetchDone && lastError == nil && refused.isEmpty
    }

    /// The hold, if the engine is held.
    public var hold: SyncHold? {
        if case .held(let hold) = state { return hold }
        return nil
    }
}

/// Why the engine is about to remove the person's items from the device (`SyncHost.willRemoveLocalData`).
public enum SyncRemovalReason: String, Hashable, Sendable {
    /// Signed out of iCloud: what was synced leaves the device, as it did under the mirror.
    case signedOut
    /// Another account signed in: the previous account's synced items leave the device.
    case accountSwitched
    /// The person removed HITList's data in iCloud's settings and answered "remove here too".
    case zonePurged
}

/// The person's answer when HITList's data was removed from iCloud (`SyncHold.zonePurged`).
public enum PurgeAnswer: String, Hashable, Sendable {
    /// Remove what was synced from this device too (after a backup).
    case removeHere
    /// Keep this device's items and send them all to iCloud again.
    case keepAndSendAgain
}

public enum SyncCoreError: Error, Equatable {
    /// `syncNow()` while the engine is held.
    case held(SyncHold)
    /// `syncNow()` before `start()`.
    case notStarted
    /// `answer(_:)` while the engine is not waiting for one.
    case noQuestion
    /// `answer(.removeHere)` with no host to write the backup: nothing was removed.
    case noBackup
}
