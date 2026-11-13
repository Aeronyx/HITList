import Foundation

/// The words every sync line speaks (the bolt's label, Settings' status line, the Account row), from the same state as
/// the bolt's look, so no words anywhere claim more than the bolt. Filled: "Synced 3 min ago", the last import or
/// export the mirror finished. Hollow before this session's first import: "Last synced 3 min ago, checking…". Trouble
/// and work keep their own words (`SyncState.summary`). Pure.
enum SyncWords {
    /// The status words for `state` (`CloudSyncMonitor.state`, already held to `SyncSessionGate`). `waiting`: the
    /// session still waits for its first import (`SyncSessionGate.isWaiting`); `lastSynced` is the latest import or
    /// export of any launch, for "Last synced 3 min ago".
    static func status(state: SyncState, waiting: Bool, lastSynced: Date?, now: Date) -> String {
        guard waiting, case .syncing = state else { return state.summary(now: now) }
        return lastSynced.map { "Last synced \(SyncState.relative($0, now: now)), checking…" } ?? "Checking with iCloud…"
    }
}
