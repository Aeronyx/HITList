import Foundation

/// When the sync bolt may be filled, from what CloudKit's mirror itself reports and nothing else (0.9.10).
///
/// HITList syncs through SwiftData's CloudKit mirror (`NSPersistentCloudKitContainer` underneath). The mirror decides
/// when to import and export, retries by itself, and tells the app one thing: each setup, import and export, with its
/// start, its end and its error. That is the whole of what HITList knows about sync, so it is the whole of what the
/// marks say:
/// - **Hollow** from a launch (and from the moment an iCloud account comes back, or the store is reset) until the mirror
///   has finished an import: the mirror imports at every launch, so this is its first real exchange with iCloud.
/// - **Filled** from then on, for as long as nothing fails: "Synced 3 min ago" names the last import or export.
/// - **Trouble** as the mirror reports it (`SyncState.derive`, steadied by `SyncSteadiness`).
/// - With the account available, the network up and nothing running, no import `Rules.silence` after the wait began
///   reads "iCloud isn't answering, HITList will keep trying": never a hollow bolt with no words for why.
///
/// It replaces brief 95's beats (a CloudKit request of HITList's own every 15 s, a copy of iCloud's record index and a
/// record-by-record comparison that held the bolt hollow whenever the two differed). On George's Mac on 2026-11-13
/// three records from October that iCloud didn't have kept the bolt hollow for good, in words that weren't true
/// ("Sending 3 changes to iCloud…"), while every import and export of the mirror succeeded. The comparison is still
/// there, on request: Settings → iCloud → Check iCloud… (`SyncAudit`).
///
/// Pure: `CloudSyncMonitor` feeds it and wakes it once at `nextDeadline(after:)`. Nothing here runs on a timer of its
/// own, asks iCloud anything, or animates.
struct SyncSessionGate: Equatable {
    struct Rules: Equatable {
        /// No import this long after the wait began, with nothing in the way and nothing running: the mirror is silent.
        var silence: TimeInterval = 60
    }

    let rules: Rules
    /// Since when this session has waited for an import; nil before `begin` and once one finished.
    private(set) var waitingSince: Date?
    /// Where the silence clock counts from: the wait's start, or the last moment nothing stood in the way. Nil while
    /// it can't count (offline, no account, the process suspended).
    private(set) var clockFrom: Date?
    /// The latest import that finished well in this session.
    private(set) var importedAt: Date?
    private(set) var isBlocked = false
    private(set) var isSuspended = false

    init(rules: Rules = Rules()) {
        self.rules = rules
    }

    /// The marks wait for an import: the bolt isn't filled yet.
    var isWaiting: Bool { waitingSince != nil }

    // MARK: Feeding it

    /// A launch with CloudKit on, an iCloud account that came back, a store that was reset: nothing has been fetched
    /// for what is on screen now.
    mutating func begin(at now: Date) {
        waitingSince = now
        clockFrom = canCount ? now : nil
    }

    /// The mirror finished an import well.
    mutating func imported(at now: Date) {
        importedAt = now
        waitingSince = nil
        clockFrom = nil
    }

    /// Sync can't happen at all right now (offline, no usable iCloud account), or can again. The time it couldn't
    /// doesn't count as silence.
    mutating func block(_ blocked: Bool, at now: Date) {
        guard blocked != isBlocked else { return }
        isBlocked = blocked
        restartClock(now)
    }

    /// The process stopped running (iPhone and iPad in the background, a Mac asleep), or runs again.
    mutating func suspend(_ suspended: Bool, at now: Date) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        restartClock(now)
    }

    private var canCount: Bool { !isBlocked && !isSuspended }

    private mutating func restartClock(_ now: Date) {
        clockFrom = isWaiting && canCount ? now : nil
    }

    // MARK: Reading it

    /// The wait has lasted `Rules.silence` with nothing in the way and nothing running.
    func isSilent(inFlight: Bool, at now: Date) -> Bool {
        guard isWaiting, !inFlight, let clockFrom else { return false }
        return now.timeIntervalSince(clockFrom) >= rules.silence
    }

    /// The state every mark draws: the steadied state, never "synced" while the session still waits for its first
    /// import. Trouble and "local only" pass through in their own words.
    func gate(_ shown: SyncState, inFlight: Bool, at now: Date) -> SyncState {
        if case .localOnly = shown { return shown }
        if shown.showsTrouble { return shown }
        guard let waitingSince else { return shown }
        if isSilent(inFlight: inFlight, at: now) { return .retrying(since: waitingSince) }
        if case .synced = shown { return .syncing }
        return shown
    }

    /// The next moment `gate` can change with nothing new fed in, strictly after `now`; nil when none.
    func nextDeadline(after now: Date) -> Date? {
        guard isWaiting, let clockFrom else { return nil }
        let at = clockFrom.addingTimeInterval(rules.silence)
        return at > now ? at : nil
    }
}
