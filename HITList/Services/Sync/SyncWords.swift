import Foundation
import HITListCore

/// The words every sync line speaks (the bolt's label, Settings' status line, the Account row), from the same state as
/// the bolt's look, so no words anywhere claim more than the bolt. Filled: "Synced 3 min ago", the last import or
/// export the mirror finished. Hollow before this session's first import, and until the first comparison with
/// iCloud's records is in: "Last synced 3 min ago, checking…". Records that differ: what differs, in counts
/// (`difference`). Trouble and work keep their own words (`SyncState.summary`). Pure.
enum SyncWords {
    /// The status words for `state` (`CloudSyncMonitor.state`, already held to `SyncSessionGate` and
    /// `SyncRecordCheck`). `waiting`: the session still waits for its first import or its first comparison
    /// (`CloudSyncMonitor.isChecking`); `lastSynced` is the latest import or export of any launch, for "Last synced 3
    /// min ago".
    static func status(state: SyncState, waiting: Bool, lastSynced: Date?, now: Date) -> String {
        guard waiting, case .syncing = state else { return state.summary(now: now) }
        return lastSynced.map { "Last synced \(SyncState.relative($0, now: now)), checking…" } ?? "Checking with iCloud…"
    }

    /// What a believed difference says, in the audit's own words (`SyncAuditWords.title`), the ways this device can
    /// mend first: "1 label and 2 filters on this device aren't in iCloud"; two ways at most, then "and more".
    static func difference(_ difference: SyncRecordCheck.Difference) -> String {
        let order: [SyncComparison.Difference.Kind] = [.onlyHere, .newerHere, .onlyThere, .newerThere]
        let parts = order.compactMap { kind -> String? in
            let counts = difference.counts(kind)
            guard !counts.isEmpty else { return nil }
            let what = SyncAuditWords.counted(counts)
            let one = counts.values.reduce(0, +) == 1
            switch kind {
            case .onlyHere: return "\(what) on this device \(one ? "isn't" : "aren't") in iCloud"
            case .newerHere: return "\(what) changed here \(one ? "hasn't" : "haven't") reached iCloud"
            case .onlyThere: return "\(what) in iCloud \(one ? "isn't" : "aren't") on this device"
            case .newerThere: return "\(what) changed in iCloud \(one ? "hasn't" : "haven't") arrived here"
            }
        }
        guard let first = parts.first else { return "This device and iCloud differ" }
        if parts.count == 1 { return first }
        return "\(first); \(parts[1])" + (parts.count > 2 ? ", and more" : "")
    }

    /// Under the status line in Settings while records differ: where it is settled.
    static let differenceNote = "Check iCloud… below names them, and can send them to iCloud or remove them from this device."
    /// The same while HITList is still waiting on the mirror (a change on its way, records just sent again).
    static let differenceWaitingNote = "HITList is waiting for iCloud to catch up; nothing to do yet."

    // MARK: HITList's own engine (round 28)

    /// Before the engine's first whole fetch has finished (or while it starts, or fetches with nothing waiting).
    static let engineChecking = "Checking with iCloud…"

    /// "3 changes waiting to go to iCloud"; offline: "…; they go when you are back online".
    static func engineWaiting(_ count: Int, offline: Bool) -> String {
        let changes = count == 1 ? "1 change" : "\(count) changes"
        return "\(changes) waiting to go to iCloud" + (offline ? "; they go when you are back online" : "")
    }

    /// Offline with nothing waiting: exact, since the engine knows.
    static func engineOffline(firstFetchDone: Bool) -> String {
        firstFetchDone ? "Offline; nothing is waiting to go to iCloud"
                       : "Offline; HITList checks with iCloud when you are back online"
    }

    /// Items iCloud refused for good (too large, or rejected): Settings → iCloud names them.
    static func engineRefused(_ count: Int) -> String {
        "\(count == 1 ? "1 item" : "\(count) items") couldn't go to iCloud; Settings → iCloud names \(count == 1 ? "it" : "them")"
    }

    /// A hold's words for the status line, in a person's words: what happened and, for the red ones, that nothing was
    /// lost. (`SyncHold.words` is the engine's own, for its log.) `duplicates`: how many rows share an id.
    static func engineHold(_ hold: SyncHold, waiting: Int, duplicates: Int = 0) -> String {
        switch hold {
        case .noAccount: return SyncState.notSignedIn.summary()
        case .massDeletion(let count):
            let items = count == 1 ? "1 item is" : "\(count) items are"
            return "\(items) missing from this device. Nothing has been deleted in iCloud."
        case .zonePurged: return "HITList's data was removed from iCloud in Settings."
        case .needsUpdate: return "Update HITList to sync: iCloud holds data from a newer version."
        case .storageFull:
            if waiting == 0 { return "iCloud is full." }
            return "iCloud is full: \(waiting == 1 ? "1 change is" : "\(waiting) changes are") waiting."
        case .failed(let words): return "Sync stopped: \(words)"
        case .duplicates(let keys):
            let count = max(duplicates, keys.count)
            return "Tidying up \(count == 1 ? "1 item" : "\(count) items") saved twice on this device"
        }
    }
}
