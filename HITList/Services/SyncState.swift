import Foundation
import CloudKit

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

    /// Precedence: no CloudKit, then account problems, then reachability, then mirroring events.
    /// An error counts only while it is newer than the last successful import or export.
    static func derive(
        cloudKitEnabled: Bool,
        localOnlyReason: String,
        account: CKAccountStatus?,
        isOnline: Bool,
        isSyncing: Bool,
        lastSynced: Date?,
        lastError: (reason: String, at: Date)?,
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
        if isSyncing { return .syncing }
        if let lastError, lastSynced.map({ lastError.at > $0 }) ?? true { return .error(lastError.reason, lastError.at) }
        if let lastSynced { return .synced(lastSynced) }
        return .syncing  // launched, nothing has finished yet
    }

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
