import XCTest
@testable import HITList

/// Every line that speaks of sync follows the bolt, and no words anywhere claim more than it (`SyncWords`,
/// `SyncHealth`). Since 0.9.10 the words come from the mirror's own events alone: "Synced 3 min ago" names its last
/// import or export, and a session that still waits for its first import says so.
final class SyncWordsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func words(_ state: SyncState, waiting: Bool = false, lastSynced: Date? = nil) -> String {
        SyncWords.status(state: state, waiting: waiting, lastSynced: lastSynced, now: now)
    }

    func testFilledSaysWhenItLastSynced() {
        XCTAssertEqual(words(.synced(ago(2))), "Synced just now")
        XCTAssertEqual(words(.synced(ago(180))), "Synced 3 min ago")
        XCTAssertEqual(words(.synced(ago(7200))), "Synced 2 hr ago")
    }

    func testHollowBeforeTheFirstImportSaysItIsChecking() {
        XCTAssertEqual(words(.syncing, waiting: true, lastSynced: ago(180)), "Last synced 3 min ago, checking…")
        XCTAssertEqual(words(.syncing, waiting: true), "Checking with iCloud…")
    }

    func testWorkAfterTheFirstImportIsJustWork() {
        XCTAssertEqual(words(.syncing, lastSynced: ago(180)), "Syncing…")
    }

    func testTroubleKeepsItsOwnWords() {
        XCTAssertEqual(words(.notSignedIn, waiting: true), "Not signed in to iCloud")
        XCTAssertEqual(words(.offline, waiting: true), "Offline, changes will sync later")
        XCTAssertEqual(words(.error("iCloud storage is full", ago(60)), waiting: true), "Sync paused: iCloud storage is full")
        XCTAssertEqual(words(.retrying(since: ago(40)), waiting: true), SyncState.retryingWords)
        XCTAssertEqual(words(.localOnly("iCloud sync turned off")), "Local only: iCloud sync turned off")
    }

    func testNoWordsClaimMoreThanTheBolt() {
        // A hollow bolt never says synced; a filled one never names a number of changes it cannot know.
        for state in [SyncState.syncing, .retrying(since: ago(90))] {
            let text = words(state, waiting: true, lastSynced: ago(30))
            XCTAssertFalse(text.hasPrefix("Synced"), text)
            XCTAssertFalse(text.contains("Up to date"), text)
        }
        // What 0.9.9 said on George's Mac for an hour while nothing was being sent.
        for state in [SyncState.syncing, .synced(ago(5)), .retrying(since: ago(90))] {
            for waiting in [true, false] {
                XCTAssertFalse(words(state, waiting: waiting, lastSynced: ago(30)).contains("Sending"), "\(state)")
            }
        }
    }

    func testSettingsAndTheAccountRowSayTheSame() {
        let filled = SyncHealth(account: .signedIn, sync: .synced(ago(180)), waiting: false, lastSynced: ago(180))
        XCTAssertEqual(filled.line(now: now), "iCloud: Signed in · Synced 3 min ago")
        let hollow = SyncHealth(account: .signedIn, sync: .syncing, waiting: true, lastSynced: ago(180))
        XCTAssertEqual(hollow.line(now: now), "iCloud: Signed in · Last synced 3 min ago, checking…")
        XCTAssertEqual(SyncHealth(account: .signedOut, sync: .notSignedIn, waiting: true).line(now: now), "iCloud: Signed out")
    }
}
