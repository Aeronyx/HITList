import XCTest
import CloudKit
@testable import HITList

final class SyncStateTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func derive(
        cloudKit: Bool = true, account: CKAccountStatus? = .available, online: Bool = true, syncing: Bool = false,
        synced: TimeInterval? = nil, error: (String, TimeInterval)? = nil, stalled: TimeInterval? = nil
    ) -> SyncState {
        SyncState.derive(
            cloudKitEnabled: cloudKit, localOnlyReason: "iCloud sync turned off", account: account, isOnline: online,
            isSyncing: syncing, lastSynced: synced.map { now.addingTimeInterval($0) },
            lastError: error.map { ($0.0, now.addingTimeInterval($0.1)) },
            stalledSince: stalled.map { now.addingTimeInterval($0) }, now: now)
    }

    // MARK: Summary

    func testSummaryTexts() {
        XCTAssertEqual(SyncState.synced(now.addingTimeInterval(-120)).summary(now: now), "Synced 2 min ago")
        XCTAssertEqual(SyncState.syncing.summary(now: now), "Syncing…")
        XCTAssertEqual(SyncState.offline.summary(now: now), "Offline, changes will sync later")
        XCTAssertEqual(SyncState.notSignedIn.summary(now: now), "Not signed in to iCloud")
        XCTAssertEqual(SyncState.restricted.summary(now: now), "iCloud restricted")
        XCTAssertEqual(SyncState.error("iCloud storage is full", now).summary(now: now), "Sync paused: iCloud storage is full")
        XCTAssertEqual(SyncState.localOnly("iCloud sync turned off").summary(now: now), "Local only: iCloud sync turned off")
    }

    func testRelativeTimes() {
        func text(_ ago: TimeInterval) -> String { SyncState.relative(now.addingTimeInterval(-ago), now: now) }
        XCTAssertEqual(text(0), "just now")
        XCTAssertEqual(text(59), "just now")
        XCTAssertEqual(text(-30), "just now", "clock skew reads as now")
        XCTAssertEqual(text(60), "1 min ago")
        XCTAssertEqual(text(59 * 60 + 59), "59 min ago")
        XCTAssertEqual(text(3600), "1 hr ago")
        XCTAssertEqual(text(23 * 3600), "23 hr ago")
        XCTAssertEqual(text(86_400), "1 day ago")
        XCTAssertEqual(text(3 * 86_400), "3 days ago")
    }

    // MARK: Derivation

    func testLocalOnlyWinsOverEverything() {
        XCTAssertEqual(derive(cloudKit: false, account: .noAccount, online: false), .localOnly("iCloud sync turned off"))
    }

    func testAccountProblemsWinOverNetworkAndEvents() {
        XCTAssertEqual(derive(account: .noAccount, online: false, synced: -60), .notSignedIn)
        XCTAssertEqual(derive(account: .restricted, syncing: true), .restricted)
        XCTAssertEqual(derive(account: .temporarilyUnavailable), .error("iCloud needs you to sign in again", now))
    }

    func testOfflineWinsOverEvents() {
        XCTAssertEqual(derive(online: false, syncing: true, synced: -60), .offline)
    }

    func testEventsDecideWhenAccountAndNetworkAreFine() {
        XCTAssertEqual(derive(syncing: true, synced: -60), .syncing)
        XCTAssertEqual(derive(synced: -60), .synced(now.addingTimeInterval(-60)))
        XCTAssertEqual(derive(), .syncing, "nothing finished yet")
        XCTAssertEqual(derive(account: nil, synced: -60), .synced(now.addingTimeInterval(-60)), "account not checked yet")
    }

    func testErrorCountsOnlyUntilTheNextSuccess() {
        XCTAssertEqual(derive(synced: -120, error: ("network unavailable", -60)), .error("network unavailable", now.addingTimeInterval(-60)))
        XCTAssertEqual(derive(synced: -30, error: ("network unavailable", -60)), .synced(now.addingTimeInterval(-30)))
        XCTAssertEqual(derive(error: ("network unavailable", -60)), .error("network unavailable", now.addingTimeInterval(-60)))
        XCTAssertEqual(derive(syncing: true, error: ("network unavailable", -60)), .syncing, "a retry is running")
    }

    // MARK: Stalled (brief 25)

    @MainActor
    func testAStalledEventSaysSyncIsStuckInsteadOfSyncing() {
        let stuck = derive(syncing: true, synced: -600, stalled: -130)
        XCTAssertEqual(stuck, .error(SyncState.stalledReason, now.addingTimeInterval(-130)))
        #if os(macOS)
        XCTAssertEqual(stuck.summary(now: now), "Sync paused: stuck, relaunch HITList")
        #else
        XCTAssertEqual(stuck.summary(now: now), "Sync paused: stuck, reopen HITList")
        #endif
        XCTAssertEqual(SyncBolt.look(for: stuck, now: now).symbol, "bolt.slash.fill", "the bolt is struck through")
    }

    func testAStalledEventNoLongerReadsAsSyncedOnceItStopsCounting() {
        // Before: after 10 minutes the stuck event stopped counting and the state fell back to "Synced".
        XCTAssertEqual(derive(syncing: false, synced: -900, stalled: -700), .error(SyncState.stalledReason, now.addingTimeInterval(-700)))
    }

    func testABoltForSomeoneWhoNeverUsedICloudIsGreyNotRed() {
        // A friend on TestFlight without iCloud keeps tasks on the device: nothing is wrong, so no red bolt.
        XCTAssertEqual(SyncBolt.look(for: .notSignedIn, everSignedIn: false).color, Theme.secondaryText)
        XCTAssertEqual(SyncBolt.look(for: .notSignedIn, everSignedIn: true).color, HITColor.dueOverdue,
                       "signed out after using iCloud still needs attention")
        let defaults = UserDefaults(suiteName: "SyncBoltTests-\(UUID().uuidString)")!
        XCTAssertFalse(SyncBolt.everSignedIn(defaults))
        defaults.set(true, forKey: AccountWatch.everSignedInKey)
        XCTAssertTrue(SyncBolt.everSignedIn(defaults))
    }

    func testAccountAndNetworkStillComeFirst() {
        XCTAssertEqual(derive(online: false, stalled: -130), .offline)
        XCTAssertEqual(derive(account: .noAccount, stalled: -130), .notSignedIn)
        XCTAssertEqual(derive(cloudKit: false, stalled: -130), .localOnly("iCloud sync turned off"))
    }

    func testNotStalledIsUnchanged() {
        XCTAssertEqual(derive(syncing: true, synced: -60), .syncing)
        XCTAssertEqual(derive(synced: -60), .synced(now.addingTimeInterval(-60)))
    }

    // MARK: Error reasons

    func testShortReasonFromCKError() {
        XCTAssertEqual(SyncState.shortReason(for: CKError(.quotaExceeded)), "iCloud storage is full")
        XCTAssertEqual(SyncState.shortReason(for: CKError(.networkUnavailable)), "network unavailable")
        XCTAssertEqual(SyncState.shortReason(for: CKError(.notAuthenticated)), "not signed in to iCloud")
    }

    func testShortReasonLooksAtTheUnderlyingAndPartialErrors() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_410,
                              userInfo: [NSUnderlyingErrorKey: CKError(.zoneBusy) as NSError])
        XCTAssertEqual(SyncState.shortReason(for: wrapped), "iCloud is busy, will retry")
        let partial = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                              userInfo: [CKPartialErrorsByItemIDKey: ["record": CKError(.quotaExceeded)]])
        XCTAssertEqual(SyncState.shortReason(for: partial), "iCloud storage is full")
    }

    func testShortReasonFallsBackToShortDescriptionOrCode() {
        XCTAssertEqual(SyncState.shortReason(for: NSError(domain: NSCocoaErrorDomain, code: 134_400)), "not signed in to iCloud")
        let short = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
        XCTAssertEqual(SyncState.shortReason(for: short), "Something broke")
        let long = NSError(domain: "X", code: 2, userInfo: [NSLocalizedDescriptionKey: String(repeating: "word ", count: 20)])
        XCTAssertEqual(SyncState.shortReason(for: long), "error X 2")
    }

    // MARK: Sidebar

    func testSidebarFooterStaysQuietWhenSyncIsNormal() {
        XCTAssertFalse(SyncState.synced(now).showsInSidebar(hasSyncedBefore: true))
        XCTAssertFalse(SyncState.syncing.showsInSidebar(hasSyncedBefore: true))
        XCTAssertTrue(SyncState.syncing.showsInSidebar(hasSyncedBefore: false))
        XCTAssertTrue(SyncState.offline.showsInSidebar(hasSyncedBefore: true))
        XCTAssertTrue(SyncState.notSignedIn.showsInSidebar(hasSyncedBefore: true))
    }

    // MARK: Launch timing (brief 42, item 5)

    func testLaunchMillisecondsCountFromTheProcessStart() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(LaunchTiming.milliseconds(at: start.addingTimeInterval(0.4125), since: start), 413)
        XCTAssertNil(LaunchTiming.milliseconds(at: start, since: nil))
        let processStart = LaunchTiming.processStart
        XCTAssertNotNil(processStart, "sysctl gives this process's start time")
        if let processStart { XCTAssertLessThan(processStart, Date()) }
    }

    @MainActor
    func testFirstFrameIsLoggedOnceWithTheMarks() {
        LaunchTiming.reset()
        defer { LaunchTiming.reset() }
        LaunchTiming.mark("store")
        var lines: [(String, [String: String])] = []
        LaunchTiming.firstFrame { lines.append(($0, $1)) }
        LaunchTiming.firstFrame { lines.append(($0, $1)) }
        LaunchTiming.mark("late")
        XCTAssertEqual(lines.count, 1, "one line per process")
        XCTAssertTrue(lines[0].0.hasPrefix("First screen "), lines[0].0)
        XCTAssertTrue(lines[0].0.hasSuffix(" ms after launch"), lines[0].0)
        XCTAssertNotNil(lines[0].1["store"])
        XCTAssertNotNil(lines[0].1["firstFrame"])
        XCTAssertEqual(LaunchTiming.marks.map(\.name), ["store"], "marks after the first frame are ignored")
    }
}
