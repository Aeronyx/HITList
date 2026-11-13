import Foundation

/// The sync health line (brief 42, item 4): the one place the words for "which iCloud account, and is it
/// syncing" come from. Settings → iCloud's status line (`SyncStatusLine`) and Settings → Account's status row
/// (`AccountStatusRow`) both show `line`, so the two screens can't disagree: before 0.6.0 one said "Not signed
/// in to iCloud" while the other said "iCloud: Signed out".
///
/// The account's words (`AccountState`) come first; the sync's follow only when there is an account to sync with,
/// since without one every sync word would only repeat the account's. The sync's words are the bolt's (`SyncWords`).
struct SyncHealth: Equatable {
    var account: AccountState
    var sync: SyncState
    /// The session still waits for its first import (`CloudSyncMonitor.isWaitingForFirstImport`). Left out, the live
    /// monitor's, so a row that builds its own line (`AccountStatusRow`) speaks as Settings does.
    var waiting: Bool
    var lastSynced: Date?

    init(account: AccountState, sync: SyncState, waiting: Bool = SyncHealth.liveWaiting,
         lastSynced: Date? = SyncHealth.liveLastSynced) {
        self.account = account
        self.sync = sync
        self.waiting = waiting
        self.lastSynced = lastSynced
    }

    /// "iCloud: Signed in · Synced 3 min ago", "iCloud: Signed out", "iCloud: Not in use · iCloud sync turned off".
    func line(now: Date = .now) -> String {
        switch account {
        case .signedIn, .switched, .checking, .couldNotDetermine:
            let words = SyncWords.status(state: sync, waiting: waiting, lastSynced: lastSynced, now: now)
            return "\(account.title) · \(words)"
        case .signedOut, .neverSignedIn, .restricted, .needsSignInAgain:
            return account.title
        case .localOnly(let reason):
            return "\(account.title) · \(reason)"
        }
    }

    /// The live health, from `CloudSyncMonitor` (observed: a view reading it re-renders on a change).
    @MainActor
    static var current: SyncHealth {
        SyncHealth(account: .current, sync: CloudSyncMonitor.shared.state)
    }

    /// Whether the running monitor still waits for this session's first import, read on the main thread (views and
    /// tests both build lines there); false before the monitor started (hosted tests) or where nothing syncs.
    static var liveWaiting: Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated { CloudSyncMonitor.shared.isWaitingForFirstImport }
    }

    static var liveLastSynced: Date? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { CloudSyncMonitor.shared.lastSyncedAt }
    }
}
