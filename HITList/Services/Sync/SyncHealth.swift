import Foundation

/// The sync health line (brief 42, item 4): the one place the words for "which iCloud account, and is it
/// syncing" come from. Settings → iCloud's status line (`SyncStatusLine`) and Settings → Account's status row
/// (`AccountStatusRow`) both show `line`, so the two screens can't disagree: before 0.6.0 one said "Not signed
/// in to iCloud" while the other said "iCloud: Signed out".
///
/// The account's words (`AccountState`) come first; the sync's (`SyncState`) follow only when there is an
/// account to sync with, since without one every sync word would only repeat the account's.
struct SyncHealth: Equatable {
    var account: AccountState
    var sync: SyncState

    /// "iCloud: Signed in · Synced 2 min ago", "iCloud: Signed out", "iCloud: Not in use · iCloud sync turned off".
    func line(now: Date = .now) -> String {
        switch account {
        case .signedIn, .switched, .checking, .couldNotDetermine:
            return "\(account.title) · \(sync.summary(now: now))"
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
}
