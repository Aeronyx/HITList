import Foundation

/// Keeps Development and Production apart on one device (brief 25, item 6).
///
/// Every build of HITList on a device shares one app group, so before this guard a build run from Xcode
/// (CloudKit Development) opened the same `HITList.store` as the TestFlight build (Production). CloudKit's
/// mirroring keeps its change tokens and per-record metadata in the store without saying which
/// environment they belong to: the Development build would then import Development records into the
/// store the Production build mirrors, and its own edits would reach only Development, so they never
/// appeared on the other devices. George's Mac store was mirrored by a Development build until the
/// TestFlight app replaced it on the same store.
///
/// So a Development build opens `HITList-Development.store` (and writes `sync-log-Development.jsonl`)
/// unless `HITLIST_STORE_SUFFIX` already names a side store. Production builds keep `HITList.store`.
enum SyncStoreGuard {
    static let suffixVariable = "HITLIST_STORE_SUFFIX"
    static let developmentSuffix = "Development"

    /// The suffix a build should use: Development's own, or nil to keep the current store name. Never for
    /// a TestFlight or App Store build: `SyncEnvironment.resolve` never calls one Development, and this is
    /// the second lock, since a side store there would open empty and look like every task was lost.
    static func isolationSuffix(environment: SyncEnvironment, processEnvironment: [String: String]) -> String? {
        guard environment.cloudKit == .development, !environment.channel.isDistribution else { return nil }
        if let existing = processEnvironment[suffixVariable], !existing.isEmpty { return nil }
        return developmentSuffix
    }

    /// Called first in `HITListApp.init`, before anything reads the store name or opens the sync log.
    /// Returns the suffix it set, if any.
    @discardableResult
    static func isolateDevelopmentStore(environment: SyncEnvironment = .current,
                                        processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let suffix = isolationSuffix(environment: environment, processEnvironment: processEnvironment) else { return nil }
        setenv(suffixVariable, suffix, 1)
        return suffix
    }
}
