import Foundation
import CloudKit
import OSLog
import HITListCore

/// What the app tells the user about iCloud sync. `CloudSyncMonitor.state` derives it; Settings, the
/// sidebar footer and the account banner all read it from there.
enum SyncState: Equatable {
    case notSignedIn
    case restricted
    case offline
    case syncing
    case synced(Date)
    /// A short, human reason and when it failed. The raw error text is `CloudSyncMonitor.lastErrorDetail`.
    case error(String, Date)
    /// The container was opened without CloudKit (`ModelContainerFactory.isCloudKitEnabled == false`).
    case localOnly(String)
    /// Only ever shown, never derived (`SyncSteadiness`): an error has lasted half a minute but not yet two, so the
    /// marks say what is known rather than the error's own alarming words (brief 78: George's account blip read
    /// "Sync paused: iCloud needs you to sign in again", untrue ten seconds later).
    case retrying(since: Date)
    /// Only ever shown, never derived (`SyncRecordCheck`, 0.9.11): the mirror reports nothing wrong, and a fresh read
    /// of iCloud's records, made twice, found that this device and iCloud don't hold the same ones. The words say
    /// what differs ("1 label and 2 filters on this device aren't in iCloud"). `stuck` once it has lasted
    /// (`SyncRecordCheck.Rules.patience`): drawn as trouble, and Check iCloud… settles it; before that, as waiting.
    case differs(String, stuck: Bool)
    /// Only on HITList's own engine (round 28: `SyncEngineBoard.engine == .own`), never on the mirror: the engine's
    /// exact status as the marks draw it, look and words (`SyncEngineMarks.state`). Never steadied or gated: the engine
    /// knows what is waiting, so there is nothing to second-guess.
    case engine(SyncEngineMarks)

    /// The one-line status, e.g. "Synced 2 min ago".
    func summary(now: Date = .now) -> String {
        switch self {
        case .notSignedIn: return "Not signed in to iCloud"
        case .restricted: return "iCloud restricted"
        case .offline: return "Offline, changes will sync later"
        case .syncing: return "Syncing…"
        case .synced(let at): return "Synced \(Self.relative(at, now: now))"
        case .error(let reason, _): return "Sync paused: \(reason)"
        case .localOnly(let reason): return "Local only: \(reason)"
        case .retrying: return Self.retryingWords
        case .differs(let words, _): return words
        case .engine(let marks): return marks.words
        }
    }

    /// What `.retrying` says.
    static let retryingWords = "iCloud isn't answering, HITList will keep trying"

    var symbol: String {
        switch self {
        case .synced: return "checkmark.icloud"
        case .syncing, .retrying: return "arrow.triangle.2.circlepath.icloud"
        case .offline: return "icloud.slash"
        case .notSignedIn, .restricted, .localOnly: return "xmark.icloud"
        case .error: return "exclamationmark.icloud"
        case .differs(_, let stuck): return stuck ? "exclamationmark.icloud" : "arrow.triangle.2.circlepath.icloud"
        case .engine(let marks):
            switch marks.look {
            case .hollow: return "arrow.triangle.2.circlepath.icloud"
            case .needsYou: return "exclamationmark.icloud"
            case .offline: return "icloud.slash"
            }
        }
    }

    var isSynced: Bool { if case .synced = self { true } else { false } }

    /// Whether the marks draw it as trouble (struck through, grey or red): offline, an error, signed out, restricted.
    /// Syncing, "will keep trying" and local only are not trouble.
    var showsTrouble: Bool {
        switch self {
        case .offline, .error, .notSignedIn, .restricted: true
        case .synced, .syncing, .retrying, .localOnly: false
        case .differs(_, let stuck): stuck
        case .engine(let marks): marks.look != .hollow
        }
    }

    /// Errors the person has to act on (free up iCloud storage, update the app, a deleted iCloud zone): once they have
    /// lasted `SyncSteadiness.Windows.error` they show in their own words, without the calm "will keep trying" first.
    static func needsAction(_ reason: String) -> Bool {
        actionReasons.contains(reason)
    }

    static let actionReasons: Set<String> = ["iCloud storage is full", "update HITList", "iCloud data was deleted"]

    /// "just now", "1 min ago", "3 hr ago", "2 days ago". Fixed English wording so it can be tested;
    /// a date slightly in the future (clock skew between devices) reads as "just now".
    static func relative(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3600) hr ago"
        default:
            let days = seconds / 86_400
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    /// Precedence: no CloudKit, then account problems, then reachability, then a stalled event, then
    /// mirroring events. An error counts only while it is newer than the last successful import or export.
    /// `stalledSince` is when an import, export or setup began that has run for two minutes (ten for a
    /// store's first import) with nothing in its way (`SyncWatchdog.stalledSince`): CloudKit's mirroring runs one request at a time,
    /// so nothing else syncs until it ends (brief 25: an import on Nov 1 never did). Or when the first of local saves
    /// was made that have waited two minutes for an export with nothing running: the mirroring stopped (brief 78:
    /// George's Mac after a badContainer on 2026-11-10 exported nothing more until he relaunched).
    static func derive(
        cloudKitEnabled: Bool,
        localOnlyReason: String,
        account: CKAccountStatus?,
        isOnline: Bool,
        isSyncing: Bool,
        lastSynced: Date?,
        lastError: (reason: String, at: Date)?,
        stalledSince: Date? = nil,
        now: Date = .now
    ) -> SyncState {
        guard cloudKitEnabled else { return .localOnly(localOnlyReason) }
        switch account {
        case .noAccount: return .notSignedIn
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .error("iCloud needs you to sign in again", now)
        default: break  // .available, .couldNotDetermine or not checked yet: let the events decide
        }
        if !isOnline { return .offline }
        if let stalledSince { return .error(stalledReason, stalledSince) }
        if isSyncing { return .syncing }
        if let lastError, lastSynced.map({ lastError.at > $0 }) ?? true { return .error(lastError.reason, lastError.at) }
        if let lastSynced { return .synced(lastSynced) }
        return .syncing  // launched, nothing has finished yet
    }

    /// "Sync paused: stuck, relaunch HITList". Relaunching starts CloudKit's mirroring afresh, which is
    /// what ended every stuck event seen so far (Settings → iCloud offers it).
    #if os(macOS)
    static let stalledReason = "stuck, relaunch HITList"
    #else
    static let stalledReason = "stuck, reopen HITList"
    #endif

    /// A few words for "Sync paused: …". Looks at the error, then its underlying error, for a CKError.
    static func shortReason(for error: Error) -> String {
        let ns = error as NSError
        let candidates = [ns] + [ns.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap { $0 }
        for candidate in candidates where candidate.domain == CKErrorDomain {
            if let reason = reason(forCKErrorCode: candidate.code, in: candidate) { return reason }
        }
        // Core Data's mirroring delegate reports a missing account as NSCocoaErrorDomain 134400.
        if ns.domain == NSCocoaErrorDomain, ns.code == 134400 { return "not signed in to iCloud" }
        let text = ns.localizedDescription
        return text.count <= 60 ? text : "error \(ns.domain) \(ns.code)"
    }

    private static func reason(forCKErrorCode code: Int, in error: NSError) -> String? {
        guard let code = CKError.Code(rawValue: code) else { return nil }
        switch code {
        case .networkUnavailable, .networkFailure: return "network unavailable"
        case .notAuthenticated: return "not signed in to iCloud"
        case .accountTemporarilyUnavailable: return "iCloud needs you to sign in again"
        case .quotaExceeded: return "iCloud storage is full"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy, will retry"
        case .userDeletedZone: return "iCloud data was deleted"
        case .badContainer, .missingEntitlement, .permissionFailure: return "app can't use iCloud"
        case .incompatibleVersion: return "update HITList"
        case .serverRejectedRequest: return "iCloud rejected a change"
        case .limitExceeded: return "too many changes at once"
        case .partialFailure:
            // The first per-record error usually says what went wrong (often quotaExceeded).
            if let inner = (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error])?.values.first {
                return shortReason(for: inner)
            }
            return "some changes didn't sync"
        default: return "iCloud error \(code.rawValue)"
        }
    }
}

/// When the sync dot pulses and Settings' status line flashes its checkmark: each time
/// `CloudSyncMonitor.lastChangeAt` advances (a CloudKit import or export finished in this session).
/// Pure, so the trigger is testable.
enum SyncConfirmation {
    /// Imports and exports arrive in bursts (one event per zone); pulses closer together than this merge.
    static let minimumGap: TimeInterval = 2
    /// How long Settings shows the checkmark before the usual icon returns.
    static let checkmarkDuration: Duration = .seconds(3)
    /// The views log each confirmation (category "sync"), so it can be seen without watching the screen.
    static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// A sync finished: `new` is later than `old`, or is the session's first (`old == nil`). Views pass
    /// the values of `onChange`, which doesn't fire for the value a view appears with, so opening a
    /// screen long after the last sync doesn't pulse.
    static func didAdvance(from old: Date?, to new: Date?) -> Bool {
        guard let new else { return false }
        guard let old else { return true }
        return new > old
    }

    /// The dot pulses once per advance, never more than once per `minimumGap`, and never under Reduce Motion.
    static func shouldPulse(from old: Date?, to new: Date?, lastPulse: Date?, now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, didAdvance(from: old, to: new) else { return false }
        guard let lastPulse else { return true }
        return now.timeIntervalSince(lastPulse) >= minimumGap
    }
}

/// When the toolbar bolt plays its lightning strike: a "you're connected, synced, and good to go" moment,
/// not a sync indicator (George, 2026-11-05: "not an animation to spam every few seconds"). It strikes once,
/// on the first good sync (a `CloudSyncMonitor.lastChangeAt` advance) after:
/// - the app opens (the gate starts armed);
/// - the app comes back to the front after at least `awayLong` away (a quick app switch doesn't count);
/// - sync was in trouble (offline, an error or stuck, signed out) for at least `troubleLong`.
/// Ordinary syncs never strike: CloudKit syncs whenever something changes, so a quiet minute without edits
/// is normal, not a gap worth marking. Nothing plays while the app isn't in front; the arming waits for the
/// next good sync there. Reduce Motion: a short blink instead. Pure, so the rules are testable; one gate is
/// shared by every bolt on screen, and every call is idempotent so each bolt may report the same event.
struct BoltStrikeGate {
    enum Strike: Equatable { case none, strike, blink }

    /// Away from the front at least this long and the next good sync strikes ("reopened").
    static let awayLong: TimeInterval = 60
    /// Sync in trouble at least this long and the next good sync strikes ("hasn't synced in a while").
    static let troubleLong: TimeInterval = 60

    /// The `new` value of the last advance this gate was asked about.
    private(set) var lastSeenChange: Date?
    /// What it answered for `lastSeenChange`, so every bolt on screen plays the same for one advance.
    private var lastAnswer: Strike = .none
    /// The next good sync in front strikes. Set at launch, on coming back after `awayLong`, after a long trouble.
    private(set) var armed = true
    private var wentAwayAt: Date?
    private var troubleSince: Date?

    /// The app left the front (`isActive` false) or came back (true).
    mutating func appActive(_ isActive: Bool, now: Date) {
        guard isActive else {
            if wentAwayAt == nil { wentAwayAt = now }
            return
        }
        if let away = wentAwayAt, now.timeIntervalSince(away) >= Self.awayLong { armed = true }
        wentAwayAt = nil
    }

    #if DEBUG
    /// `-boltStrikeDemo YES`: every fake sync strikes, to record the motion.
    mutating func armForDemo() { armed = true }
    #endif

    /// Every sync state change: `healthy` for synced or syncing, false for offline, errors, signed out.
    mutating func syncState(healthy: Bool, now: Date) {
        if healthy {
            if let since = troubleSince, now.timeIntervalSince(since) >= Self.troubleLong { armed = true }
            troubleSince = nil
        } else if troubleSince == nil {
            troubleSince = now
        }
    }

    mutating func advance(from old: Date?, to new: Date?, now: Date, isActive: Bool, reduceMotion: Bool) -> Strike {
        guard SyncConfirmation.didAdvance(from: old, to: new), let new else { return .none }
        if new == lastSeenChange { return lastAnswer }
        lastSeenChange = new
        // A good sync ends any trouble, even if the state change reaches the gate after this advance.
        syncState(healthy: true, now: now)
        guard armed, isActive else {
            lastAnswer = .none
            return .none
        }
        armed = false
        lastAnswer = reduceMotion ? .blink : .strike
        return lastAnswer
    }
}

extension SyncState {
    /// For the strike gate: syncing or synced is healthy; anything that stops sync is trouble.
    var isHealthyForStrike: Bool {
        switch self {
        case .synced, .syncing: true
        case .offline, .error, .notSignedIn, .restricted, .localOnly, .retrying, .differs: false
        // Changes waiting, the first fetch, tidying up: work, not trouble.
        case .engine(let marks): marks.look == .hollow
        }
    }
}

// MARK: - HITList's own engine (round 28)

/// What the marks show while a launch runs on HITList's own engine: one look and the words for it, worked out from the
/// engine's exact status (`SyncEngineBoard.status`) and the account and network the monitor still watches, by one pure
/// function (`state`). `dev/SYNC-ENGINE.md` section 10: the bolt is filled exactly when the status says synced; hollow
/// with the number when changes are waiting; red only for a hold the person must act on. No comparison of records, no
/// gate, no steadying: none of the mirror's instruments run on the engine.
struct SyncEngineMarks: Hashable {
    enum Look: Hashable {
        /// Hollow in the theme's tint: something is still to happen and nothing is wrong (changes waiting, the first
        /// fetch, tidying up, items iCloud refused).
        case hollow
        /// Hollow in the colour of trouble: the engine holds until the person acts (`SyncWords.engineNeedsYou`).
        case needsYou
        /// Struck through in grey, as today's offline bolt: this device cannot reach iCloud now (the words say what
        /// waits).
        case offline
    }

    var look: Look
    var words: String

    /// A sync that stopped early (`SyncStatus.lastError`) reads as today's "will keep trying" this long before its own
    /// words show in red: never red in the first minute; today's two minutes (`SyncSteadiness.Windows.errorWords`).
    static let errorWordsAfter: TimeInterval = SyncSteadiness.Windows().errorWords

    /// The marks for the engine's status. `status` nil: the engine has not said anything yet this launch. `account` is
    /// iCloud's own answer (`CloudSyncMonitor.rawAccountStatus`), `isOnline` the network path, `errorSince` when the
    /// monitor first saw the current `syncError`, `lastSyncedFallback` the moment to quote when the engine is synced
    /// but has no time of its own yet. Pure, so every status can be tested.
    static func state(status: SyncStatus?, account: CKAccountStatus?, isOnline: Bool, errorSince: Date?,
                      lastSyncedFallback: Date, now: Date) -> SyncState {
        // The account first, as on the mirror: without one nothing can sync, whatever the engine last said.
        switch account {
        case .noAccount: return .notSignedIn
        case .restricted: return .restricted
        default: break
        }
        guard let status else { return .engine(checking) }
        if let hold = status.hold { return held(hold, waiting: status.waiting) }
        // Offline before any error: what stopped early offline stopped for that reason.
        if !isOnline {
            let words = SyncWords.engineOffline(waiting: status.waiting, firstFetchDone: status.firstFetchDone)
            return .engine(SyncEngineMarks(look: .offline, words: words))
        }
        if let error = syncError(status) {
            let since = errorSince ?? now
            if now.timeIntervalSince(since) >= errorWordsAfter { return .error(error, since) }
            return .retrying(since: since)
        }
        switch status.state {
        case .off, .starting: return .engine(checking)
        default: break
        }
        if !status.firstFetchDone { return .engine(checking) }
        if status.waiting > 0 { return .engine(SyncEngineMarks(look: .hollow, words: SyncWords.engineWaiting(status.waiting))) }
        if !status.refused.isEmpty { return .engine(SyncEngineMarks(look: .hollow, words: SyncWords.engineRefused(status.refused.count))) }
        if status.isSynced { return .synced(lastSynced(status) ?? lastSyncedFallback) }
        // Fetching or sending with nothing waiting: the bolt is filled exactly when the engine says synced.
        return .engine(checking)
    }

    static let checking = SyncEngineMarks(look: .hollow, words: SyncWords.engineChecking)

    /// A hold's marks: signed out as today; red for the ones the person must act on; tidying up hollow.
    static func held(_ hold: SyncHold, waiting: Int) -> SyncState {
        switch hold {
        case .noAccount: return .notSignedIn
        case .duplicates(let keys): return .engine(SyncEngineMarks(look: .hollow, words: SyncWords.engineHold(hold, waiting: waiting, duplicates: keys.count)))
        case .zonePurged, .needsUpdate, .storageFull, .failed:
            return .engine(SyncEngineMarks(look: .needsYou, words: SyncWords.engineHold(hold, waiting: waiting)))
        }
    }

    /// The latest moment the engine knows something reached or came from iCloud: its last fetch or accepted send.
    static func lastSynced(_ status: SyncStatus?) -> Date? {
        [status?.lastFetchEnded, status?.lastSendEnded].compactMap { $0 }.max()
    }

    /// The words of a sync that stopped early, or nil. A refusal for good is not one: core keeps its words apart
    /// (`SyncStatus.refusal`, since the simulation's brief), so this is `lastError` as it stands.
    static func syncError(_ status: SyncStatus) -> String? {
        status.lastError
    }
}
