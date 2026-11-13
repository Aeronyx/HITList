import XCTest
@testable import HITList

/// When the bolt may be filled (`SyncSessionGate`, 0.9.10): from the mirror's own events and nothing else. Hollow from
/// a launch until the session's first import, filled after it; trouble in its own words; a minute of silence says so.
/// The times are those of George's Mac on 2026-11-13, where 0.9.9 kept the bolt hollow for good.
final class SyncSessionGateTests: XCTestCase {
    private let launch = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { launch.addingTimeInterval(seconds) }
    private var remembered: SyncState { .synced(at(-86_400)) }

    // MARK: Before anything is known

    func testWithoutASessionNothingIsHeldBack() {
        // Sync off, hosted tests, a replay: `begin` was never called, so the steadied state stands as it is.
        let gate = SyncSessionGate()
        XCTAssertFalse(gate.isWaiting)
        XCTAssertEqual(gate.gate(.synced(at(-60)), inFlight: false, at: at(0)), .synced(at(-60)))
        XCTAssertEqual(gate.gate(.syncing, inFlight: true, at: at(0)), .syncing)
        XCTAssertNil(gate.nextDeadline(after: at(0)))
    }

    // MARK: A launch

    func testALaunchIsHollowUntilTheFirstImportThenFilled() {
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        XCTAssertTrue(gate.isWaiting)
        // 12:25:12: the marks would show the remembered "Synced 1 day ago". Not yet: nothing was fetched.
        XCTAssertEqual(gate.gate(remembered, inFlight: false, at: at(0.4)), .syncing)
        // 12:25:13.1: an export finished first. Still nothing fetched.
        XCTAssertEqual(gate.gate(.synced(at(1.1)), inFlight: false, at: at(1.1)), .syncing)
        // 12:25:13.6: the import finished.
        gate.imported(at: at(1.6))
        XCTAssertFalse(gate.isWaiting)
        XCTAssertEqual(gate.gate(.synced(at(1.6)), inFlight: false, at: at(1.6)), .synced(at(1.6)))
        XCTAssertNil(gate.nextDeadline(after: at(1.6)), "at rest nothing is left to wake for")
    }

    func testOnceFilledItStaysFilledWhateverTheStoreAndICloudHold() {
        // George's Mac held three records iCloud didn't. That is Check iCloud…'s business; the mirror's exchanges all
        // succeeded, so the bolt is filled and says when it last synced, an hour later as at the start.
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        gate.imported(at: at(1.6))
        for seconds in stride(from: 2.0, through: 3600, by: 15) {
            XCTAssertEqual(gate.gate(.synced(at(1.6)), inFlight: false, at: at(seconds)), .synced(at(1.6)))
        }
    }

    func testWorkAndTroublePassThroughInTheirOwnWords() {
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        for state in [SyncState.offline, .notSignedIn, .restricted, .error("iCloud storage is full", at(3)),
                      .localOnly("iCloud sync turned off"), .syncing, .retrying(since: at(2))] {
            XCTAssertEqual(gate.gate(state, inFlight: false, at: at(5)), state, "\(state)")
        }
        gate.imported(at: at(6))
        for state in [SyncState.offline, .error("iCloud storage is full", at(3)), .syncing, .synced(at(6))] {
            XCTAssertEqual(gate.gate(state, inFlight: false, at: at(7)), state, "\(state)")
        }
    }

    // MARK: Silence

    func testAMinuteOfSilenceSaysSoAndTheNextImportEndsIt() {
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        XCTAssertEqual(gate.nextDeadline(after: at(0)), at(60))
        XCTAssertEqual(gate.gate(remembered, inFlight: false, at: at(59)), .syncing)
        // Never a hollow bolt with no words for why.
        XCTAssertEqual(gate.gate(remembered, inFlight: false, at: at(60)), .retrying(since: at(0)))
        XCTAssertNil(gate.nextDeadline(after: at(60)))
        gate.imported(at: at(200))
        XCTAssertEqual(gate.gate(.synced(at(200)), inFlight: false, at: at(200)), .synced(at(200)))
    }

    func testAnImportStillRunningIsNotSilence() {
        // A store's first import can run for minutes with nothing wrong.
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        XCTAssertFalse(gate.isSilent(inFlight: true, at: at(300)))
        XCTAssertEqual(gate.gate(.syncing, inFlight: true, at: at(300)), .syncing)
    }

    func testTimeItCouldNotSyncDoesNotCountAsSilence() {
        var gate = SyncSessionGate()
        gate.block(true, at: at(-5))
        gate.begin(at: at(0))
        XCTAssertNil(gate.nextDeadline(after: at(0)), "offline: no clock runs")
        XCTAssertFalse(gate.isSilent(inFlight: false, at: at(600)))
        gate.block(false, at: at(600))
        XCTAssertEqual(gate.nextDeadline(after: at(600)), at(660), "a full minute from the moment it could")
        XCTAssertFalse(gate.isSilent(inFlight: false, at: at(659)))
        XCTAssertTrue(gate.isSilent(inFlight: false, at: at(660)))
    }

    func testTimeInTheBackgroundDoesNotCountAsSilence() {
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        gate.suspend(true, at: at(10))
        XCTAssertNil(gate.nextDeadline(after: at(10)))
        XCTAssertFalse(gate.isSilent(inFlight: false, at: at(7200)))
        gate.suspend(false, at: at(7200))
        XCTAssertEqual(gate.nextDeadline(after: at(7200)), at(7260))
        // The same answer twice changes nothing.
        gate.suspend(false, at: at(7230))
        XCTAssertEqual(gate.nextDeadline(after: at(7230)), at(7260))
    }

    // MARK: An account that comes back, a store that is reset

    func testBeginningAgainIsHollowAgainUntilTheNextImport() {
        // George's Mac, 2026-11-11: the bolt filled the instant iCloud let the account back in, before anything had
        // been fetched. The account's return begins the wait again.
        var gate = SyncSessionGate()
        gate.begin(at: at(0))
        gate.imported(at: at(2))
        gate.begin(at: at(500))
        XCTAssertTrue(gate.isWaiting)
        XCTAssertEqual(gate.gate(.synced(at(2)), inFlight: false, at: at(501)), .syncing)
        XCTAssertEqual(gate.importedAt, at(2), "the last import keeps its time, for the words")
        gate.imported(at: at(503))
        XCTAssertEqual(gate.gate(.synced(at(503)), inFlight: false, at: at(503)), .synced(at(503)))
    }
}
