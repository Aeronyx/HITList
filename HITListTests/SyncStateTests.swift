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

    // MARK: Health line (brief 42, item 4)

    func testTheHealthLinePutsTheAccountFirstAndTheSyncAfterOnlyWhenThereIsAnAccount() {
        let synced = SyncState.synced(now.addingTimeInterval(-120))
        func line(_ account: AccountState, _ sync: SyncState) -> String { SyncHealth(account: account, sync: sync).line(now: now) }
        XCTAssertEqual(line(.signedIn, synced), "iCloud: Signed in · Synced 2 min ago")
        XCTAssertEqual(line(.signedIn, .offline), "iCloud: Signed in · Offline, changes will sync later")
        XCTAssertEqual(line(.switched, .syncing), "iCloud: Signed in to another account · Syncing…")
        XCTAssertEqual(line(.checking, .syncing), "iCloud: Checking… · Syncing…")
        XCTAssertEqual(line(.signedOut, .notSignedIn), "iCloud: Signed out", "not \"Not signed in to iCloud\" beside it")
        XCTAssertEqual(line(.neverSignedIn, .notSignedIn), "iCloud: Not signed in")
        XCTAssertEqual(line(.restricted, .restricted), "iCloud: Restricted")
        XCTAssertEqual(line(.needsSignInAgain, .error("iCloud needs you to sign in again", now)), "iCloud: Sign in again")
        XCTAssertEqual(line(.localOnly("iCloud sync turned off"), .localOnly("iCloud sync turned off")),
                       "iCloud: Not in use · iCloud sync turned off")
    }

    func testTheICloudAndAccountScreensSayTheSameWords() {
        let accounts: [AccountState] = [.checking, .signedIn, .switched, .signedOut, .neverSignedIn, .restricted,
                                        .needsSignInAgain, .couldNotDetermine, .localOnly("iCloud sync turned off")]
        let syncs: [SyncState] = [.synced(now), .syncing, .offline, .notSignedIn, .restricted, .error("iCloud is busy, will retry", now)]
        for account in accounts {
            for sync in syncs {
                XCTAssertEqual(SyncStatusLine.text(account: account, sync: sync, now: now),
                               AccountStatusRow.title(account: account, sync: sync, now: now), "\(account) / \(sync)")
            }
        }
    }

    // MARK: Sync log line count (brief 42, item 1)

    func testCountingLinesMatchesSplittingThem() {
        for text in ["", "a", "a\n", "a\nb", "a\n\nb\n", "\n\n", String(repeating: "{\"n\":1}\n", count: 500)] {
            let data = Data(text.utf8)
            XCTAssertEqual(SyncLog.countLines(in: data), SyncLog.lines(in: data).count, text.debugDescription)
        }
    }

    // MARK: Bolt strike (brief 54)

    /// Feeds the gate a sequence of `lastChangeAt` advances, `at` seconds from `now`, and returns what each one played.
    private func strikes(_ advances: [TimeInterval], active: Bool = true, reduceMotion: Bool = false,
                         gate: inout BoltStrikeGate) -> [BoltStrikeGate.Strike] {
        var previous = gate.lastSeenChange
        return advances.map { offset in
            let at = now.addingTimeInterval(offset)
            defer { previous = at }
            return gate.advance(from: previous, to: at, now: at, isActive: active, reduceMotion: reduceMotion)
        }
    }

    func testNothingStrikesDuringTheLaunchStorm() {
        var gate = BoltStrikeGate()
        // The session's first import, then the export and imports that follow it within the quiet gap.
        XCTAssertEqual(strikes([0, 2, 5, 11, 19], gate: &gate), [.none, .none, .none, .none, .none])
        // Once things have been quiet for the launch gap, the next good sync strikes.
        XCTAssertEqual(strikes([19 + BoltStrikeGate.launchQuiet], gate: &gate), [.strike])
    }

    func testAStoreResetStartsANewStorm() {
        var gate = BoltStrikeGate()
        _ = strikes([0, 30], gate: &gate)
        // lastChangeAt went back to nil (a store reset) and a full import follows: quiet again.
        let at = now.addingTimeInterval(100)
        XCTAssertEqual(gate.advance(from: nil, to: at, now: at, isActive: true, reduceMotion: false), .none)
    }

    func testABurstStrikesOnceAtItsStart() {
        var gate = BoltStrikeGate()
        _ = strikes([0], gate: &gate)  // launch
        // An export and the import it sets off, each under the burst gap after the one before.
        XCTAssertEqual(strikes([60, 61, 62.5, 64], gate: &gate), [.strike, .none, .none, .none])
    }

    func testStrikesAreAtLeastTheCooldownApart() {
        var gate = BoltStrikeGate()
        _ = strikes([0], gate: &gate)
        let gap = BoltStrikeGate.burstGap + 0.5  // separate bursts, but closer than the cooldown
        XCTAssertLessThan(gap, BoltStrikeGate.cooldown)
        let third = max(60 + BoltStrikeGate.cooldown, 60 + gap + BoltStrikeGate.burstGap) + 0.1  // a burst of its own, past the cooldown
        XCTAssertEqual(strikes([60, 60 + gap, third], gate: &gate), [.strike, .none, .strike])
        XCTAssertGreaterThanOrEqual(BoltStrikeGate.cooldown, 3, "no more than one strike every few seconds")
    }

    func testNoStrikeInTheBackgroundAndNoLateOneOnReturn() {
        var gate = BoltStrikeGate()
        _ = strikes([0], gate: &gate)
        XCTAssertEqual(strikes([60], active: false, gate: &gate), [.none])
        // The background sync still counts toward its burst, so coming back mid-burst doesn't strike for it.
        XCTAssertEqual(strikes([61], gate: &gate), [.none])
        XCTAssertEqual(strikes([90], gate: &gate), [.strike])
    }

    func testReduceMotionBlinksInstead() {
        var gate = BoltStrikeGate()
        _ = strikes([0], gate: &gate)
        XCTAssertEqual(strikes([60], reduceMotion: true, gate: &gate), [.blink])
        XCTAssertEqual(strikes([61, 70], reduceMotion: true, gate: &gate), [.none, .blink], "same merge and cooldown")
    }

    func testEveryBoltOnScreenGetsTheSameAnswerForOneAdvance() {
        // Two windows (or a split view) each draw a bolt; both ask about the same advance.
        var gate = BoltStrikeGate()
        _ = strikes([0], gate: &gate)
        let old = now, new = now.addingTimeInterval(60)
        XCTAssertEqual(gate.advance(from: old, to: new, now: new, isActive: true, reduceMotion: false), .strike)
        XCTAssertEqual(gate.advance(from: old, to: new, now: new.addingTimeInterval(0.01), isActive: true, reduceMotion: false),
                       .strike, "the second bolt strikes with the first, not blocked by the cooldown")
        XCTAssertEqual(gate.advance(from: new, to: new, now: new, isActive: true, reduceMotion: false), .none, "no advance")
    }

    func testTheStrikeIsShortAndSmall() {
        let strike = BoltStrikeMotion.timeline(for: .strike)
        XCTAssertLessThanOrEqual(strike.duration, 0.3)
        var peakScale: CGFloat = 1, peakTwirl: Double = 0, peakGlow: Double = 0
        for step in 0...300 {
            let fx = strike.value(time: Double(step) / 1000)
            peakScale = max(peakScale, fx.scale)
            peakTwirl = max(peakTwirl, abs(fx.twirl))
            peakGlow = max(peakGlow, fx.glow)
            XCTAssertEqual(fx.opacity, 1, "a strike never dims the bolt")
        }
        XCTAssertGreaterThan(peakScale, 1)
        XCTAssertLessThanOrEqual(peakScale, 1.12)
        XCTAssertGreaterThan(peakTwirl, 2)
        XCTAssertLessThanOrEqual(peakTwirl, 10, "a few degrees")
        XCTAssertEqual(peakGlow, 1, accuracy: 0.05, "it flashes")
        XCTAssertEqual(strike.value(time: strike.duration), BoltStrikeMotion.Frame(), "and comes back to rest")
    }

    func testTheReduceMotionBlinkOnlyFadesAndIsShorter() {
        let blink = BoltStrikeMotion.timeline(for: .blink)
        XCTAssertLessThanOrEqual(blink.duration, 0.15)
        var lowest: Double = 1
        for step in 0...150 {
            let fx = blink.value(time: Double(step) / 1000)
            XCTAssertEqual(fx.scale, 1)
            XCTAssertEqual(fx.twirl, 0)
            XCTAssertEqual(fx.glow, 0)
            lowest = min(lowest, fx.opacity)
        }
        XCTAssertLessThan(lowest, 0.7, "a visible blink")
        XCTAssertEqual(blink.value(time: blink.duration), BoltStrikeMotion.Frame())
    }
}
