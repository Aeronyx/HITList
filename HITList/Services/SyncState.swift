import Foundation
import CloudKit
import OSLog

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
        }
    }

    var symbol: String {
        switch self {
        case .synced: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .offline: return "icloud.slash"
        case .notSignedIn, .restricted, .localOnly: return "xmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    var isSynced: Bool { if case .synced = self { true } else { false } }

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
    /// so nothing else syncs until it ends (brief 25: an import on Nov 1 never did).
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

/// When the toolbar bolt plays its lightning strike (brief 54): once per good sync, quietly. Fed every
/// advance of `CloudSyncMonitor.lastChangeAt` (a CloudKit import or export finished), it answers what
/// the bolt plays for it. Pure, so the rules are testable; one gate is shared by every bolt on screen.
///
/// - Launch: the session's first sync and every one that follows it within `launchQuiet` of the one
///   before are the launch's import storm: nothing plays. A store reset (`old == nil`) starts a new storm.
/// - Bursts: a sync within `burstGap` of the previous one belongs to the burst under way and plays
///   nothing, so a burst strikes once, at its start.
/// - Strikes are at least `cooldown` apart.
/// - Nothing in the background; a sync there still counts toward its burst, so coming back doesn't
///   strike late for it.
/// - Reduce Motion: a blink instead of the strike, under the same rules.
struct BoltStrikeGate {
    enum Strike: Equatable { case none, strike, blink }

    static let launchQuiet: TimeInterval = 10
    static let burstGap: TimeInterval = 3
    static let cooldown: TimeInterval = 5

    /// The `new` value of the last advance this gate was asked about.
    private(set) var lastSeenChange: Date?
    /// What it answered for `lastSeenChange`, so every bolt on screen plays the same for one advance.
    private var lastAnswer: Strike = .none
    /// When the last advance arrived, struck or not.
    private var lastAdvanceAt: Date?
    private var lastStrikeAt: Date?
    private var inLaunchStorm = true

    mutating func advance(from old: Date?, to new: Date?, now: Date, isActive: Bool, reduceMotion: Bool) -> Strike {
        guard SyncConfirmation.didAdvance(from: old, to: new), let new else { return .none }
        if new == lastSeenChange { return lastAnswer }
        let gap = lastAdvanceAt.map { now.timeIntervalSince($0) }
        lastSeenChange = new
        lastAdvanceAt = now
        lastAnswer = decide(old: old, gap: gap, now: now, isActive: isActive, reduceMotion: reduceMotion)
        if lastAnswer != .none { lastStrikeAt = now }
        return lastAnswer
    }

    private mutating func decide(old: Date?, gap: TimeInterval?, now: Date, isActive: Bool, reduceMotion: Bool) -> Strike {
        if old == nil { inLaunchStorm = true }
        if inLaunchStorm {
            guard let gap, gap >= Self.launchQuiet, old != nil else { return .none }
            inLaunchStorm = false
        }
        if let gap, gap < Self.burstGap { return .none }
        if let lastStrikeAt, now.timeIntervalSince(lastStrikeAt) < Self.cooldown { return .none }
        guard isActive else { return .none }
        return reduceMotion ? .blink : .strike
    }
}
