import Foundation

/// The sync health line (brief 42, item 4): the one place the words for "which iCloud account, and is it
/// syncing" come from. Settings → iCloud's status line (`SyncStatusLine`) and Settings → Account's status row
/// (`AccountStatusRow`) both show `line`, so the two screens can't disagree: before 0.6.0 one said "Not signed
/// in to iCloud" while the other said "iCloud: Signed out".
///
/// The account's words (`AccountState`) come first; the sync's follow only when there is an account to sync with,
/// since without one every sync word would only repeat the account's. Since brief 95 the sync's words are the bolt's
/// (`SyncWords`): "Up to date, checked 12 s ago" only within 30 s of a beat that confirmed it.
struct SyncHealth: Equatable {
    var account: AccountState
    var sync: SyncState
    /// What the beats found (`CloudSyncMonitor.wordsVerdict`); nil where none run, so the state's own words stand.
    /// Left out, the live monitor's, so a row that builds its own line (`AccountStatusRow`) speaks as Settings does.
    var verdict: BoltTruth.Verdict?
    var lastSynced: Date?

    init(account: AccountState, sync: SyncState, verdict: BoltTruth.Verdict? = SyncHealth.liveVerdict,
         lastSynced: Date? = SyncHealth.liveLastSynced) {
        self.account = account
        self.sync = sync
        self.verdict = verdict
        self.lastSynced = lastSynced
    }

    /// "iCloud: Signed in · Up to date, checked just now", "iCloud: Signed out", "iCloud: Not in use · iCloud sync
    /// turned off". `precise`: the seconds since the check ("checked 12 s ago").
    func line(now: Date = .now, precise: Bool = false) -> String {
        switch account {
        case .signedIn, .switched, .checking, .couldNotDetermine:
            let words = SyncWords.status(state: sync, verdict: verdict, lastSynced: lastSynced, now: now, precise: precise)
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

    /// The running monitor's verdict, read on the main thread (views and tests both build lines there); nil before the
    /// monitor started (hosted tests) or where no beats run.
    static var liveVerdict: BoltTruth.Verdict? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { CloudSyncMonitor.shared.wordsVerdict }
    }

    static var liveLastSynced: Date? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { CloudSyncMonitor.shared.lastSyncedAt }
    }
}
