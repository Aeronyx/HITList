import XCTest
@testable import HITList

/// Brief 95, rules 4 and 5: every line that speaks of sync follows the bolt's truth, and no words anywhere claim more
/// than the bolt (`SyncWords`, `SyncHealth`).
final class SyncWordsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func verdict(_ why: BoltTruth.Why?, filled: Bool = false, confirmedAt: Date? = nil) -> BoltTruth.Verdict {
        BoltTruth.Verdict(filled: filled, confirmedAt: confirmedAt, why: why, trouble: nil)
    }

    private func words(_ state: SyncState, _ verdict: BoltTruth.Verdict?, lastSynced: Date? = nil, precise: Bool = false) -> String {
        SyncWords.status(state: state, verdict: verdict, lastSynced: lastSynced, now: now, precise: precise)
    }

    func testFilledSaysWhenItWasChecked() {
        let filled = verdict(nil, filled: true, confirmedAt: ago(12))
        XCTAssertEqual(words(.synced(ago(12)), filled, precise: true), "Up to date, checked 12 s ago")
        XCTAssertEqual(words(.synced(ago(2)), filled, precise: true), "Up to date, checked just now")
        XCTAssertEqual(words(.synced(ago(12)), filled), "Up to date, checked just now", "the bolt's label, between redraws")
    }

    func testHollowSaysWhatItWaitsFor() {
        XCTAssertEqual(words(.syncing, verdict(.checking), lastSynced: ago(180)), "Last synced 3 min ago, checking…")
        XCTAssertEqual(words(.syncing, verdict(.checking)), "Checking with iCloud…")
        XCTAssertEqual(words(.syncing, verdict(.missed(.sending(2)))), "Sending 2 changes to iCloud…")
        XCTAssertEqual(words(.syncing, verdict(.missed(.receiving(1)))), "Receiving 1 change from iCloud…")
        XCTAssertEqual(words(.syncing, verdict(.missed(.reading))), "Reading what iCloud holds…")
        XCTAssertEqual(words(.syncing, verdict(.missed(.noAnswer(SyncBeatFailure(.timeout, "no answer within 6.0 s")))),
                             lastSynced: ago(40)),
                       "Last synced just now; iCloud didn't answer (no answer within 6.0 s), asking again…")
        XCTAssertEqual(words(.syncing, verdict(.blocked(.account)), lastSynced: ago(7200)),
                       "Last synced 2 hr ago, checking the iCloud account…")
        XCTAssertEqual(words(.syncing, verdict(.blocked(.offline))), "waiting for the network…")
    }

    func testTroubleKeepsItsOwnWords() {
        XCTAssertEqual(words(.notSignedIn, verdict(.blocked(.account))), "Not signed in to iCloud")
        XCTAssertEqual(words(.offline, verdict(.blocked(.offline))), "Offline, changes will sync later")
        XCTAssertEqual(words(.error("iCloud storage is full", ago(60)), verdict(.checking)), "Sync paused: iCloud storage is full")
        XCTAssertEqual(words(.error(BoltTruth.apartReason, ago(200)), verdict(.missed(.receiving(1)))), SyncWords.apartWords)
        XCTAssertEqual(words(.retrying(since: ago(40)), verdict(.checking)), SyncState.retryingWords)
    }

    func testWithoutBeatsTheStatesOwnWordsStand() {
        XCTAssertEqual(words(.synced(ago(120)), nil), "Synced 2 min ago", "sync off, a replay: the old words")
        XCTAssertEqual(words(.localOnly("iCloud sync turned off"), nil), "Local only: iCloud sync turned off")
    }

    func testNoWordsClaimMoreThanTheBolt() {
        // Every hollow state's words: none says synced or up to date.
        let whys: [BoltTruth.Why] = [.checking, .blocked(.account), .blocked(.offline), .missed(.reading),
                                     .missed(.sending(1)), .missed(.receiving(3)),
                                     .missed(.noAnswer(SyncBeatFailure(.network, "network unavailable")))]
        for why in whys {
            let text = words(.syncing, verdict(why), lastSynced: ago(30))
            XCTAssertFalse(text.contains("Up to date"), text)
            XCTAssertFalse(text.hasPrefix("Synced"), text)
        }
    }

    func testSettingsAndTheAccountRowSayTheSame() {
        let filled = verdict(nil, filled: true, confirmedAt: ago(12))
        let health = SyncHealth(account: .signedIn, sync: .synced(ago(12)), verdict: filled, lastSynced: ago(12))
        XCTAssertEqual(health.line(now: now, precise: true), "iCloud: Signed in · Up to date, checked 12 s ago")
        let hollow = SyncHealth(account: .signedIn, sync: .syncing, verdict: verdict(.checking), lastSynced: ago(180))
        XCTAssertEqual(hollow.line(now: now), "iCloud: Signed in · Last synced 3 min ago, checking…")
        XCTAssertEqual(SyncHealth(account: .signedOut, sync: .notSignedIn, verdict: verdict(.blocked(.account))).line(now: now),
                       "iCloud: Signed out")
    }
}
