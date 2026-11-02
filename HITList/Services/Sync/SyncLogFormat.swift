import Foundation
import CloudKit

/// The three kinds of CloudKit mirroring event, as the log and the watchdog name them.
enum SyncEventType: String, Sendable, Equatable, CaseIterable {
    case setup
    case importing = "import"
    case exporting = "export"

    /// "Setup", "Import", "Export": how a log line starts.
    var title: String { rawValue.capitalized }
}

/// How the sync log spells durations, errors and counts. Pure, so tests pin the wording.
enum SyncLogFormat {
    /// "0.49 s", "4.2 s", "12 s", "7 min 12 s", "2 h 3 min", "3 d 4 h".
    static func duration(_ interval: TimeInterval) -> String {
        let t = max(0, interval)
        if t < 1 { return String(format: "%.2f s", t) }
        if t < 10 { return String(format: "%.1f s", t) }
        let s = Int(t.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s" }
        if s < 86_400 {
            let minutes = s / 60 % 60
            return minutes == 0 ? "\(s / 3600) h" : "\(s / 3600) h \(minutes) min"
        }
        let hours = s / 3600 % 24
        return hours == 0 ? "\(s / 86_400) d" : "\(s / 86_400) d \(hours) h"
    }

    /// "yes", "no" or "unknown".
    static func yesNo(_ value: Bool?) -> String { value.map { $0 ? "yes" : "no" } ?? "unknown" }

    /// Everything an error says, flattened into log fields: domain and code, CloudKit's name for the
    /// code, the description, `CKRetryAfter`, the underlying error, the first per-record errors of a
    /// partial failure, and every other userInfo value (one line each, at most `limit` characters).
    static func errorFields(_ error: Error, limit: Int = 300) -> [String: String] {
        let ns = error as NSError
        var fields: [String: String] = [
            "error": "\(ns.domain) \(ns.code)",
            "description": clip(ns.localizedDescription, limit),
        ]
        if let name = ckErrorName(ns) { fields["ckError"] = name }
        if let retry = retryAfter(ns) { fields["retryAfter"] = retry }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            var text = "\(underlying.domain) \(underlying.code)"
            if let name = ckErrorName(underlying) { text += " \(name)" }
            text += " \(underlying.localizedDescription)"
            fields["underlying"] = clip(text, limit)
            if fields["retryAfter"] == nil, let retry = retryAfter(underlying) { fields["retryAfter"] = retry }
        }
        if let partial = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partial.isEmpty {
            let samples = partial.prefix(3).map { key, value -> String in
                let inner = value as NSError
                return "\(key): \(inner.domain) \(ckErrorName(inner) ?? String(inner.code))"
            }.sorted()
            fields["partialErrors"] = clip("\(partial.count): " + samples.joined(separator: "; "), limit)
        }
        let handled: Set<String> = [NSUnderlyingErrorKey, CKPartialErrorsByItemIDKey, NSLocalizedDescriptionKey, CKErrorRetryAfterKey]
        for (key, value) in ns.userInfo where !handled.contains(key) {
            fields["info.\(key)"] = clip("\(value)", limit)
        }
        return fields
    }

    /// "5 s" from `CKErrorRetryAfterKey` (a number of seconds).
    static func retryAfter(_ error: NSError) -> String? {
        guard let value = error.userInfo[CKErrorRetryAfterKey] else { return nil }
        if let number = value as? NSNumber { return duration(number.doubleValue) }
        return "\(value)"
    }

    /// CloudKit's own name for a CKError code ("networkUnavailable"); nil for other domains.
    static func ckErrorName(_ error: NSError) -> String? {
        guard error.domain == CKErrorDomain, let code = CKError.Code(rawValue: error.code) else { return nil }
        switch code {
        case .internalError: return "internalError"
        case .partialFailure: return "partialFailure"
        case .networkUnavailable: return "networkUnavailable"
        case .networkFailure: return "networkFailure"
        case .badContainer: return "badContainer"
        case .serviceUnavailable: return "serviceUnavailable"
        case .requestRateLimited: return "requestRateLimited"
        case .missingEntitlement: return "missingEntitlement"
        case .notAuthenticated: return "notAuthenticated"
        case .permissionFailure: return "permissionFailure"
        case .unknownItem: return "unknownItem"
        case .invalidArguments: return "invalidArguments"
        case .resultsTruncated: return "resultsTruncated"
        case .serverRecordChanged: return "serverRecordChanged"
        case .serverRejectedRequest: return "serverRejectedRequest"
        case .assetFileNotFound: return "assetFileNotFound"
        case .assetFileModified: return "assetFileModified"
        case .incompatibleVersion: return "incompatibleVersion"
        case .constraintViolation: return "constraintViolation"
        case .operationCancelled: return "operationCancelled"
        case .changeTokenExpired: return "changeTokenExpired"
        case .batchRequestFailed: return "batchRequestFailed"
        case .zoneBusy: return "zoneBusy"
        case .badDatabase: return "badDatabase"
        case .quotaExceeded: return "quotaExceeded"
        case .zoneNotFound: return "zoneNotFound"
        case .limitExceeded: return "limitExceeded"
        case .userDeletedZone: return "userDeletedZone"
        case .tooManyParticipants: return "tooManyParticipants"
        case .alreadyShared: return "alreadyShared"
        case .referenceViolation: return "referenceViolation"
        case .managedAccountRestricted: return "managedAccountRestricted"
        case .participantMayNeedVerification: return "participantMayNeedVerification"
        case .serverResponseLost: return "serverResponseLost"
        case .assetNotAvailable: return "assetNotAvailable"
        case .accountTemporarilyUnavailable: return "accountTemporarilyUnavailable"
        case .participantAlreadyInvited: return "participantAlreadyInvited"
        @unknown default: return "code\(code.rawValue)"
        }
    }

    /// One line, at most `limit` characters.
    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return flat.count <= limit ? flat : String(flat.prefix(max(0, limit - 1))) + "…"
    }
}
